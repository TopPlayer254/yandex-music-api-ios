import Foundation

actor GeniusLyricsClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lyrics(for track: Track, accessToken: String) async throws -> Lyrics? {
        var components = URLComponents(string: "https://api.genius.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(track.artist.name) \(track.title)")]
        guard let searchURL = components.url else { throw MusicServiceError.invalidResponse }

        var searchRequest = URLRequest(url: searchURL)
        searchRequest.timeoutInterval = 20
        searchRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        searchRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        searchRequest.setValue("MapleMusic/0.7 (iOS)", forHTTPHeaderField: "User-Agent")
        let (searchData, searchResponse) = try await session.data(for: searchRequest)
        try validate(searchResponse)

        let json = try JSONSerialization.jsonObject(with: searchData) as? [String: Any]
        let response = json?["response"] as? [String: Any]
        let hits = response?["hits"] as? [[String: Any]] ?? []
        let candidates: [(url: URL, score: Int)] = hits.compactMap { hit in
            guard let result = hit["result"] as? [String: Any] else { return nil }
            guard let rawURL = result["url"] as? String else { return nil }
            guard let url = URL(string: rawURL), url.scheme == "https" else { return nil }
            guard let host = url.host else { return nil }
            guard host == "genius.com" || host.hasSuffix(".genius.com") else { return nil }
            let title = (result["title"] as? String) ?? ""
            var artist = ""
            if let primaryArtist = result["primary_artist"] as? [String: Any],
               let name = primaryArtist["name"] as? String {
                artist = name
            }
            return (url, Self.matchScore(track: track, title: title, artist: artist))
        }
        guard let songURL = candidates.max(by: { $0.score < $1.score })?.url else { return nil }

        var pageRequest = URLRequest(url: songURL)
        pageRequest.timeoutInterval = 20
        pageRequest.cachePolicy = .returnCacheDataElseLoad
        pageRequest.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 MapleMusic/0.7",
            forHTTPHeaderField: "User-Agent"
        )
        let (pageData, pageResponse) = try await session.data(for: pageRequest)
        try validate(pageResponse)
        guard let html = String(data: pageData, encoding: .utf8) else {
            throw MusicServiceError.invalidResponse
        }
        let lines = GeniusLyricsParser.extractLines(from: html)
        guard !lines.isEmpty else { return nil }
        return Lyrics(
            trackID: track.id,
            writers: nil,
            lines: lines.map { LyricsLine(time: 0, text: $0) },
            isSynchronized: false,
            source: "Genius"
        )
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw MusicServiceError.invalidResponse }
        switch http.statusCode {
        case 200 ..< 300: return
        case 401, 403:
            throw MusicServiceError.message("Genius отклонил API-ключ. Проверьте Client Access Token в настройках.")
        default: throw MusicServiceError.http(http.statusCode)
        }
    }

    private static func matchScore(track: Track, title: String, artist: String) -> Int {
        let expectedTitle = normalized(track.title)
        let expectedArtist = normalized(track.artist.name)
        let actualTitle = normalized(title)
        let actualArtist = normalized(artist)
        var score = 0
        if actualTitle == expectedTitle { score += 8 }
        else if actualTitle.contains(expectedTitle) || expectedTitle.contains(actualTitle) { score += 4 }
        if actualArtist == expectedArtist { score += 6 }
        else if actualArtist.contains(expectedArtist) || expectedArtist.contains(actualArtist) { score += 3 }
        return score
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum GeniusLyricsParser {
    static func extractLines(from html: String) -> [String] {
        guard let opening = try? NSRegularExpression(
            pattern: #"<div[^>]*data-lyrics-container\s*=\s*[\"']true[\"'][^>]*>"#,
            options: [.caseInsensitive]
        ) else { return [] }
        let source = html as NSString
        let matches = opening.matches(in: html, range: NSRange(location: 0, length: source.length))
        var fragments: [String] = []
        for match in matches {
            fragments.append(containerText(in: source, after: NSMaxRange(match.range)))
        }
        let joined = fragments.joined(separator: "\n")
        let withoutSections = joined.replacingOccurrences(
            of: #"\[[^\]]*\]"#,
            with: "",
            options: [.regularExpression]
        )
        return withoutSections
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func containerText(in html: NSString, after start: Int) -> String {
        var cursor = start
        var depth = 1
        var output = ""
        while cursor < html.length, depth > 0 {
            let tagRange = html.range(of: "<", options: [], range: NSRange(location: cursor, length: html.length - cursor))
            if tagRange.location == NSNotFound {
                output += html.substring(from: cursor)
                break
            }
            output += html.substring(with: NSRange(location: cursor, length: tagRange.location - cursor))
            let closeRange = html.range(of: ">", options: [], range: NSRange(location: tagRange.location, length: html.length - tagRange.location))
            guard closeRange.location != NSNotFound else { break }
            let tag = html.substring(with: NSRange(location: tagRange.location, length: NSMaxRange(closeRange) - tagRange.location))
                .lowercased()
            if tag.hasPrefix("<div") { depth += 1 }
            if tag.hasPrefix("</div") {
                depth -= 1
                if depth > 0 { output += "\n" }
            } else if tag.hasPrefix("<br") || tag.hasPrefix("</p") || tag.hasPrefix("</li") {
                output += "\n"
            }
            cursor = NSMaxRange(closeRange)
        }
        return decodeEntities(output)
    }

    private static func decodeEntities(_ value: String) -> String {
        var result = value
        let named = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        guard let numeric = try? NSRegularExpression(pattern: #"&#(x?[0-9a-fA-F]+);"#) else { return result }
        let mutable = NSMutableString(string: result)
        for match in numeric.matches(in: result, range: NSRange(location: 0, length: mutable.length)).reversed() {
            let token = mutable.substring(with: match.range(at: 1))
            let radix = token.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(token.dropFirst()) : token
            if let value = UInt32(digits, radix: radix), let scalar = UnicodeScalar(value) {
                mutable.replaceCharacters(in: match.range, with: String(scalar))
            }
        }
        return mutable as String
    }
}
