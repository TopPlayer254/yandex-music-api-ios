import ActivityKit
import Combine
import UIKit

@MainActor
final class LiveActivityController: ObservableObject {
    static let shared = LiveActivityController()
    @Published private(set) var status = "Выключено"
    private var activity: Activity<MaplePlaybackActivity>?
    private var pending: Task<Void, Never>?

    func update(track: Track?, playing: Bool, time: Double, duration: Double, lyrics: Lyrics?) {
        let enabled = UserDefaults.standard.bool(forKey: "developer-live-activity")
        let previous = pending
        pending = Task {
            await previous?.value
            guard enabled, let track else {
                for item in Activity<MaplePlaybackActivity>.activities {
                    await item.end(nil, dismissalPolicy: .immediate)
                }
                activity = nil
                status = enabled ? "Нет воспроизведения" : "Выключено"
                return
            }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                status = "Live Activities запрещены в настройках iOS"
                return
            }
            let lines = lyrics?.isSynchronized == true ? lyrics?.lines ?? [] : []
            let index = LyricsSynchronizer.activeLineIndex(at: time, lines: lines)
            let currentLine = index.map { String(lines[$0].text.prefix(220)) }
            let nextIndex = (index ?? -1) + 1
            let nextLine = lines.indices.contains(nextIndex) ? String(lines[nextIndex].text.prefix(220)) : nil
            let state = MaplePlaybackActivity.ContentState(
                title: track.title, artist: track.artist.name, isPlaying: playing,
                elapsed: time.isFinite ? max(time, 0) : 0,
                duration: duration.isFinite ? max(duration, 0) : 0, updatedAt: Date(),
                currentLine: currentLine, nextLine: nextLine, hasSynchronizedLyrics: !lines.isEmpty
            )
            let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(max(duration - time, 60)))
            if activity?.activityState == .dismissed || activity?.activityState == .ended { activity = nil }
            if activity == nil { activity = Activity<MaplePlaybackActivity>.activities.first }
            if let activity {
                await activity.update(content)
                status = lines.isEmpty ? "Ожидание синхронизированного текста" : "Показывается текст песни"
            } else if UIApplication.shared.applicationState == .active {
                do {
                    activity = try Activity.request(attributes: MaplePlaybackActivity(sessionID: UUID().uuidString), content: content, pushType: nil)
                    status = lines.isEmpty ? "Ожидание синхронизированного текста" : "Показывается текст песни"
                } catch { status = error.localizedDescription }
            } else { status = "Откройте приложение для запуска Live Activity" }
        }
    }
}
