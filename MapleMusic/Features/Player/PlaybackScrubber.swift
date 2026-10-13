import SwiftUI

// Only this leaf observes the playback clock. Artwork, menus and tabs do not.
struct PlaybackScrubber: View {
    @ObservedObject var player: PlayerStore
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        VStack(spacing: 3) {
            MinimalTrackSlider(
                value: Binding(get: { clock.time }, set: player.seek),
                range: 0...max(player.duration, 1),
                activeColor: .white.opacity(0.9),
                inactiveColor: .white.opacity(0.24)
            )
            .accessibilityLabel("Позиция воспроизведения")
            .accessibilityValue(clock.time.musicTime)
            HStack {
                Text(clock.time.musicTime)
                Spacer()
                Text("−\(max(player.duration - clock.time, 0).musicTime)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.62))
        }
    }
}
