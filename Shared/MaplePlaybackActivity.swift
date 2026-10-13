import ActivityKit
import Foundation

struct MaplePlaybackActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let artist: String
        let isPlaying: Bool
        let elapsed: Double
        let duration: Double
        let updatedAt: Date
        let currentLine: String?
        let nextLine: String?
        let hasSynchronizedLyrics: Bool

        var timerRange: ClosedRange<Date> {
            let start = updatedAt.addingTimeInterval(-max(elapsed, 0))
            return start...start.addingTimeInterval(max(duration, elapsed + 1))
        }
    }
    let sessionID: String
}
