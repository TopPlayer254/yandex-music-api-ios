import XCTest
@testable import MapleMusic

final class AppearanceAndWordLyricsTests: XCTestCase {
    func testSRGBLuminanceAndContrast() {
        XCTAssertEqual(ContrastRGB.black.contrast(with: .white), 21, accuracy: 0.001)
        XCTAssertEqual(ContrastRGB(red: 0.5, green: 0.5, blue: 0.5).luminance, 0.21404, accuracy: 0.0001)
    }

    func testButtonLabelsAndStandaloneAccentsRemainReadableAcrossPalette() {
        for r in stride(from: 0.0, through: 1.0, by: 0.1) {
            for g in stride(from: 0.0, through: 1.0, by: 0.1) {
                for b in stride(from: 0.0, through: 1.0, by: 0.1) {
                    let color = ContrastRGB(red: r, green: g, blue: b)
                    XCTAssertGreaterThanOrEqual(color.buttonLabel.contrast(with: color), 4.5)
                    for surface in [ContrastRGB.white, .black] {
                        XCTAssertGreaterThanOrEqual(color.readable(on: surface).contrast(with: surface), 4.5)
                    }
                }
            }
        }
    }

    func testEnhancedLRCWordTimingsAndWhitespace() throws {
        let line = try XCTUnwrap(LRCParser.parse("[00:10.00]<00:10.00>Моя <00:10.50>волна<00:12.00>").first)
        XCTAssertEqual(line.text, "Моя волна")
        XCTAssertEqual(line.words?.map(\.text), ["Моя ", "волна"])
        XCTAssertEqual(line.words?.map(\.start), [10, 10.5])
        XCTAssertEqual(line.words?.compactMap(\.end), [10.5, 12])
        XCTAssertEqual(line.words?[0].progress(at: 10.25), 0.5)
    }

    func testEnhancedLRCDuplicateLinesAndOffsets() throws {
        let lines = LRCParser.parse("[offset:-200]\n[00:10.00][00:20.00]<00:10.00>Да <00:11.00>да<00:12.00>")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1].words?.first?.start ?? -1, 19.8, accuracy: 0.001)
        XCTAssertEqual(lines[1].words?.last?.end ?? -1, 21.8, accuracy: 0.001)
    }

    func testUntimedOrMalformedWordsDoNotGetInventedTimings() {
        XCTAssertNil(LRCParser.parse("[00:10.00]Обычная строка").first?.words)
        XCTAssertNil(LRCParser.parse("[00:10.00]До <00:10.00>слова").first?.words)
        let invalid = LRCParser.parse("[00:10.00]<00:12.00>Раз <00:11.00>два").first
        XCTAssertNil(invalid?.words)
        XCTAssertEqual(invalid?.text, "Раз два")
    }

    func testUnknownWordEndUsesDiscreteHighlightAndSeeksResetProgress() {
        let word = LyricsWord(text: "слово", start: 2, end: nil)
        XCTAssertEqual(word.progress(at: 1), 0)
        XCTAssertEqual(word.progress(at: 2), 1)
        let timed = LyricsWord(text: "слово", start: 2, end: 4)
        XCTAssertEqual(timed.progress(at: 100), 1)
        XCTAssertEqual(timed.progress(at: 1), 0)
        XCTAssertEqual(timed.progress(at: .nan), 0)
    }

    func testOldCachedLinesDecodeAndWordTimingsRoundTrip() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","time":2,"text":"Строка"}"#
        let line = try JSONDecoder().decode(LyricsLine.self, from: Data(json.utf8))
        XCTAssertNil(line.words)
        let timed = LRCParser.parse("[00:01.00]<00:01.00>Слово<00:02.00>")
        let data = try JSONEncoder().encode(timed)
        XCTAssertEqual(try JSONDecoder().decode([LyricsLine].self, from: data), timed)
    }

    @MainActor
    func testLyricClockInterpolationIsBoundedAndStopsOnPauseOrSeek() {
        let clock = PlaybackClock()
        clock.time = 5
        XCTAssertEqual(clock.displayTime(at: clock.sampledAt.addingTimeInterval(0.1), playing: true), 5.1, accuracy: 0.001)
        XCTAssertEqual(clock.displayTime(at: clock.sampledAt.addingTimeInterval(10), playing: true), 5.3, accuracy: 0.001)
        XCTAssertEqual(clock.displayTime(at: clock.sampledAt.addingTimeInterval(1), playing: false), 5)
        clock.time = 0
        XCTAssertEqual(clock.displayTime(at: clock.sampledAt, playing: true), 0)
    }
}
