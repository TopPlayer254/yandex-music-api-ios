import Foundation

// The unofficial API mixes numeric and string identifiers and adds fields frequently.
enum YandexJSON: Decodable, Sendable {
    case object([String: YandexJSON]), array([YandexJSON]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode([YandexJSON].self) { self = .array(v) }
        else { self = .object(try value.decode([String: YandexJSON].self)) }
    }

    subscript(_ key: String) -> YandexJSON {
        if case let .object(v) = self { return v[key] ?? .null }; return .null
    }
    var array: [YandexJSON] { if case let .array(v) = self { return v }; return [] }
    var string: String? {
        switch self {
        case let .string(v): return v
        case let .number(v): return v.isFinite ? String(format: "%.0f", v) : nil
        default: return nil
        }
    }
    var number: Double? {
        if case let .number(v) = self { return v }
        return string.flatMap(Double.init)
    }
    var bool: Bool? { if case let .bool(v) = self { return v }; return nil }

    func track() -> Track? {
        guard let id = self["id"].string, let title = self["title"].string else { return nil }
        let album = self["albums"].array.first ?? .null
        let artists = self["artists"].array
        let parsedArtists = artists.compactMap { $0.artist() }
        let artistName = parsedArtists.isEmpty
            ? artists.compactMap { $0["name"].string }.joined(separator: ", ")
            : parsedArtists.map(\.name).joined(separator: ", ")
        let albumID = album["id"].string
        let available = self["available"].bool ?? false
        return Track(
            id: albumID.map { "\(id):\($0)" } ?? id,
            title: title,
            artist: Artist(
                id: parsedArtists.first?.id ?? artists.first?["id"].string ?? "unknown",
                name: artistName,
                artwork: parsedArtists.first?.artwork
            ),
            albumID: albumID,
            albumTitle: album["title"].string ?? "",
            duration: (self["durationMs"].number ?? 0) / 1000,
            artwork: Artwork(url: Self.artworkURL(self["coverUri"].string ?? album["coverUri"].string)),
            isExplicit: self["contentWarning"].string == "explicit",
            downloadAllowed: available && (self["availableForPremiumUsers"].bool ?? available),
            availableQualities: [.automatic, .high, .lossless]
        )
    }

    func artist() -> Artist? {
        guard let id = self["id"].string, let name = self["name"].string else { return nil }
        let cover = self["cover"]["uri"].string
            ?? self["coverUri"].string
            ?? self["ogImage"].string
        let artworkURL = Self.artworkURL(cover)
        return Artist(
            id: id,
            name: name,
            artwork: artworkURL.map { Artwork(url: $0) }
        )
    }

    func album(tracks suppliedTracks: [Track]? = nil) -> Album? {
        guard let id = self["id"].string, let title = self["title"].string else { return nil }
        let artists = self["artists"].array.compactMap { $0.artist() }
        let tracks = suppliedTracks ?? self["volumes"].array.flatMap(\.array).compactMap { $0.track() }
        let cover = self["coverUri"].string
            ?? self["cover"]["uri"].string
            ?? self["ogImage"].string
        return Album(
            id: id,
            title: title,
            artists: artists,
            artwork: Artwork(url: Self.artworkURL(cover)),
            year: self["year"].number.map(Int.init),
            genre: self["genre"].string,
            tracks: tracks,
            trackCount: Int(self["trackCount"].number ?? Double(tracks.count))
        )
    }

    static func artworkURL(_ uri: String?) -> URL? {
        guard var uri, !uri.isEmpty else { return nil }
        uri = uri.replacingOccurrences(of: "%%", with: "600x600")
        if !uri.hasPrefix("https://") { uri = "https://" + uri.replacingOccurrences(of: "http://", with: "") }
        return URL(string: uri)
    }
}

enum LRCParser {
    static func parse(_ text: String) -> [LyricsLine] {
        guard let pattern = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#) else { return [] }
        var lines: [LyricsLine] = []
        let offsetPattern = try? NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#)
        var offset: Double = 0
        if let match = offsetPattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) { offset = (Double(text[range]) ?? 0) / 1000 }
        for raw in text.components(separatedBy: .newlines) {
            let matches = pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
            guard let last = matches.last, let tail = Range(last.range, in: raw) else { continue }
            let words = String(raw[tail.upperBound...]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Range(match.range(at: 1), in: raw), let seconds = Range(match.range(at: 2), in: raw),
                      let m = Double(raw[minutes]), let s = Double(raw[seconds]) else { continue }
                lines.append(LyricsLine(time: max(0, m * 60 + s + offset), text: words))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
