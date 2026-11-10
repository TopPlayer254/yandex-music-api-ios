import XCTest
@testable import MapleMusic

final class MusicHapticsTests: XCTestCase {
    func testPCMAnalysisSilenceAttacksAndContentCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("test.wav")
        var wav = Data()
        func text(_ value: String) { wav.append(Data(value.utf8)) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + 22050 * 2)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(22050))
        number(UInt32(44100)); number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(44100))
        for index in 0..<22050 {
            let t = Double(index) / 22050
            let amplitude = t >= 0.2 && t < 0.4 ? 0.6 * sin(2 * .pi * 70 * t) : 0
            number(Int16(amplitude * 32767))
        }
        try wav.write(to: url)
        let cache = root.appendingPathComponent("cache")
        let analyzer = MusicHapticAnalyzer(root: cache)
        let result = try await analyzer.analyze(url)
        XCTAssertEqual(result.interval, 0.01)
        XCTAssertGreaterThanOrEqual(result.frames.count, 99)
        XCTAssertTrue(result.frames.prefix(10).allSatisfy { $0.intensity == 0 })
        XCTAssertTrue(result.frames[20..<40].contains { $0.intensity > 0.2 })
        XCTAssertTrue(result.frames.allSatisfy { $0.intensity.isFinite && (0...1).contains($0.intensity) && (0...1).contains($0.sharpness) })
        let relocated = root.appendingPathComponent("same-content.wav")
        try wav.write(to: relocated)
        let reused = try await analyzer.analyze(relocated)
        XCTAssertEqual(result.frames.map(\.intensity), reused.frames.map(\.intensity))
        XCTAssertEqual(result.frames.map(\.sharpness), reused.frames.map(\.sharpness))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path).count, 1)
        try await analyzer.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

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
