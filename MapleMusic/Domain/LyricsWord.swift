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

enum LyricGlyphMotion {
    /// A feathered front travels across the word's typographic advances.
    /// These are visual phases, not fabricated per-letter audio timestamps.
    static func phase(wordProgress: Double, center: Double, wordWidth: Double) -> Double {
        guard wordWidth > 0, wordProgress.isFinite else { return 0 }
        let feather = min(max(wordWidth * 0.22, 8), 24)
        let front = min(max(wordProgress, 0), 1) * (wordWidth + feather)
        let phase = min(max((front - center) / feather, 0), 1)
        return phase * phase * (3 - 2 * phase)
    }
}
