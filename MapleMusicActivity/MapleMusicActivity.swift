import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MapleMusicActivityBundle: WidgetBundle {
    var body: some Widget { PlaybackActivityWidget() }
}

struct PlaybackActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MaplePlaybackActivity.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .font(.title2).foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                ActivityLyrics(state: context.state)
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
            .widgetURL(URL(string: "maplemusic://lyrics"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill").foregroundStyle(.yellow)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) { ActivityLyrics(state: context.state) }
            } compactLeading: {
                Image(systemName: "music.note").foregroundStyle(.yellow)
            } compactTrailing: {
                Text(context.state.currentLine ?? "Текст песни").font(.caption).lineLimit(1).frame(maxWidth: 110)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "quote.bubble" : "pause.fill")
            }
            .widgetURL(URL(string: "maplemusic://lyrics"))
        }
    }
}

private struct ActivityLyrics: View {
    let state: MaplePlaybackActivity.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.hasSynchronizedLyrics {
                Text(state.currentLine ?? "♪").font(.headline).lineLimit(2)
                if let next = state.nextLine {
                    Text(next).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                Text("Открыть текст песни").font(.headline)
                Text("Синхронизированный текст недоступен").font(.caption).foregroundStyle(.secondary)
            }
            if !state.isPlaying { Label("На паузе", systemImage: "pause.fill").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
