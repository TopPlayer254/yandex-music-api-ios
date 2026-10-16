import Foundation

struct LyricsWord: Codable, Hashable, Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval?

    func progress(at time: TimeInterval) -> Double {
        guard time.isFinite, start.isFinite, time >= start else { return 0 }
        guard let end, end.isFinite, end > start else { return 1 }
        return min(max((time - start) / (end - start), 0), 1)
    }
}
