import XCTest
@testable import MapleMusic

final class AudioEnvelopeTests: XCTestCase {
    func testInterpolatesBetweenAudioBins() {
        let envelope = AudioEnvelope(levels: [0, 1, 0.5], secondsPerBin: 0.1)
        XCTAssertEqual(envelope.level(at: 0.05), 0.5, accuracy: 0.001)
        XCTAssertEqual(envelope.level(at: 0.15), 0.75, accuracy: 0.001)
        XCTAssertEqual(envelope.level(at: 9), 0.5, accuracy: 0.001)
    }

    func testEmptyEnvelopeIsSilent() {
        XCTAssertEqual(AudioEnvelope(levels: [], secondsPerBin: 0.1).level(at: 1), 0)
    }
}
