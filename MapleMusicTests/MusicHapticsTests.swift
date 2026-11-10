import XCTest
@testable import MapleMusic

final class MusicHapticsTests: XCTestCase {
    func testLyricsSurviveAudioClearAndCanBeClearedIndependently() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: source)
        let store = OfflineStore(root: root.appendingPathComponent("offline"))
        let track = Track(id: "one", title: "One", artist: Artist(id: "a", name: "Artist"), albumTitle: "", duration: 1)
        let lyrics = Lyrics(trackID: track.id, writers: nil, lines: [LyricsLine(time: 0, text: "Hello")])
        let asset = PlaybackAsset(url: source, quality: .high, codec: "PCM", bitDepth: 16, sampleRate: 44100, expiresAt: nil, allowsOfflineDownload: true)
        _ = try await store.save(track: track, asset: asset, lyrics: lyrics)
        try await store.removeAll()
        let retained = await store.localLyrics(for: track.id)
        XCTAssertEqual(retained, lyrics)
        try await store.clearLyrics()
        let cleared = await store.localLyrics(for: track.id)
        XCTAssertNil(cleared)
        try await store.cacheLyrics(lyrics)
        await store.setScope("other-account")
        let other = await store.localLyrics(for: track.id)
        XCTAssertNil(other)
    }

    func testLegacyTrackWithoutISRCStillDecodes() throws {
        let track = Track(id: "one", title: "One", artist: Artist(id: "a", name: "Artist"), albumTitle: "", duration: 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        json.removeValue(forKey: "isrc")
        let restored = try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.isrc)
    }

    func testISRCIsTakenFromYandexMetadata() throws {
        let json = #"{"id":"1","title":"Music","isrc":"USABC2400001"}"#
        let track = try JSONDecoder().decode(YandexJSON.self, from: Data(json.utf8)).track()
        XCTAssertEqual(track?.isrc, "USABC2400001")
    }
}
