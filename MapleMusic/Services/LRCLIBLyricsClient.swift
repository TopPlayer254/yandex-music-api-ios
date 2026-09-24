import Foundation

actor LRCLIBLyricsClient {
    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func lyrics(for track: Track) async throws -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist.name),
            URLQueryItem(name: "album_name", value: track.albumTitle),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        guard let url = components.url else { throw MusicServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("MapleMusic/0.11.0 (iOS; contact: https://github.com/TopPlayer254/yandex-music-api-ios)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MusicServiceError.invalidResponse }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw MusicServiceError.http(http.statusCode) }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard result.instrumental != true else { return nil }
        if let synced = result.syncedLyrics {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty {
                return Lyrics(trackID: track.id, writers: nil, lines: lines, source: "LRCLIB")
            }
        }
        guard let plain = result.plainLyrics else { return nil }
        let lines = plain.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { LyricsLine(time: 0, text: $0) }
        guard !lines.isEmpty else { return nil }
        return Lyrics(trackID: track.id, writers: nil, lines: lines, isSynchronized: false, source: "LRCLIB")
    }
}
