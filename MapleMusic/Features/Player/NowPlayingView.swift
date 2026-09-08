import AVKit
import SwiftUI

struct NowPlayingView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case player
        case lyrics
        case queue

        var id: Self { self }
        var title: String {
            switch self {
            case .player: "Исполняется"
            case .lyrics: "Текст песни"
            case .queue: "Далее"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appearance: AppearanceSettings
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var downloads: DownloadsStore
    @State private var page: Page = .player

    var body: some View {
        ZStack {
            ArtworkBackdrop(artwork: player.currentTrack?.artwork)

            VStack(spacing: 0) {
                dismissHandle

                Group {
                    switch page {
                    case .player:
                        playerPage
                    case .lyrics:
                        LyricsView()
                    case .queue:
                        QueueView()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))

                pageControls
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: page)
        .preferredColorScheme(.dark)
        .onChange(of: player.currentTrack?.id) { _, trackID in
            if trackID == nil { dismiss() }
        }
    }

    private var dismissHandle: some View {
        Capsule()
            .fill(.white.opacity(0.32))
            .frame(width: 58, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { gesture in
                        if gesture.translation.height > 36 { dismiss() }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Свернуть плеер")
            .accessibilityAddTraits(.isButton)
    }

    private var moreMenu: some View {
        Menu {
            Picker("Качество", selection: $player.preferredQuality) {
                ForEach(AudioQuality.selectableCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }

            if let track = player.currentTrack {
                TrackActions(track: track)
                if downloads.isDownloaded(track) {
                    Button("Удалить загрузку", systemImage: "trash", role: .destructive) {
                        Task { await downloads.remove(track) }
                    }
                } else if track.downloadAllowed {
                    Button("Загрузить", systemImage: "arrow.down.circle") {
                        Task { await downloads.download(track, quality: player.preferredQuality) }
                    }
                }
            }

            Divider()
            Button(player.isShuffling ? "Выключить перемешивание" : "Перемешать", systemImage: "shuffle") {
                player.isShuffling.toggle()
            }
            Button(repeatTitle, systemImage: player.repeatMode == .one ? "repeat.1" : "repeat") {
                player.cycleRepeatMode()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Действия с треком")
    }

    private var playerPage: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 620
            let contentWidth = min(max(proxy.size.width - 64, 240), 520)
            let artworkSide = min(contentWidth * 0.8, proxy.size.height * (compact ? 0.34 : 0.4))

            VStack(spacing: 0) {
                Spacer(minLength: compact ? 4 : 12)

                if let track = player.currentTrack {
                    ArtworkView(artwork: track.artwork, cornerRadius: compact ? 12 : 16)
                        .frame(width: artworkSide, height: artworkSide)
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                        .scaleEffect(player.isPlaying ? 1 : 0.94)
                        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: player.isPlaying)
                }

                Spacer(minLength: compact ? 12 : 24)
                metadata
                    .frame(width: contentWidth)
                Spacer().frame(height: compact ? 8 : 14)
                scrubber
                    .frame(width: contentWidth)
                Spacer().frame(height: compact ? 8 : 14)
                transportControls(compact: compact)
                    .frame(width: contentWidth)
                Spacer().frame(height: compact ? 8 : 16)
                volumeControl
                    .frame(width: contentWidth)
                Spacer(minLength: compact ? 2 : 10)
            }
            .frame(width: contentWidth, height: proxy.size.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var metadata: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.currentTrack?.title ?? "Ничего не играет")
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(player.currentTrack?.artist.name ?? "")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            if player.isBuffering {
                ProgressView().tint(.white)
            }
            if let track = player.currentTrack {
                Button { Task { await catalog.toggleFavorite(track) } } label: {
                    Image(systemName: catalog.isFavorite(track) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(catalog.isFavorite(track) ? appearance.tint : .white)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(catalog.isFavorite(track) ? "Убрать из любимого" : "Добавить в любимое")
            }
            moreMenu
        }
        .foregroundStyle(.white)
    }

    private var scrubber: some View {
        VStack(spacing: 3) {
            MinimalTrackSlider(
                value: Binding(get: { player.currentTime }, set: player.seek),
                range: 0 ... max(player.duration, 1),
                activeColor: .white.opacity(0.9),
                inactiveColor: .white.opacity(0.24)
            )
            .accessibilityLabel("Позиция воспроизведения")
            .accessibilityValue(player.currentTime.musicTime)

            HStack {
                Text(player.currentTime.musicTime)
                Spacer()
                Text("−\(max(player.duration - player.currentTime, 0).musicTime)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.62))
        }
    }

    private func transportControls(compact: Bool) -> some View {
        HStack(spacing: 0) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: compact ? 28 : 32))
                    .frame(width: 58, height: 58)
            }
            .frame(maxWidth: .infinity)
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 42 : 48, weight: .medium))
                    .frame(width: 76, height: 68)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity)
            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: compact ? 28 : 32))
                    .frame(width: 58, height: 58)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var volumeControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
            MinimalTrackSlider(
                value: $player.volume,
                range: 0 ... 1,
                activeColor: .white.opacity(0.72),
                inactiveColor: .white.opacity(0.22)
            )
                .accessibilityLabel("Громкость")
                .accessibilityValue("\(Int(player.volume * 100)) процентов")
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.62))
    }

    private var pageControls: some View {
        HStack(spacing: 0) {
            Button { page = page == .lyrics ? .player : .lyrics } label: {
                Image(systemName: "quote.bubble")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(page == .lyrics ? appearance.tint : .white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Текст песни")
            .frame(maxWidth: .infinity)
            AirPlayButton()
                .frame(width: 20, height: 20)
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay")
                .frame(maxWidth: .infinity)
            Button { page = page == .queue ? .player : .queue } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(page == .queue ? appearance.tint : .white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Очередь")
            .frame(maxWidth: .infinity)
        }
        .font(.title3)
        .frame(maxWidth: 520)
    }

    private var repeatTitle: String {
        switch player.repeatMode {
        case .off: "Повтор: выключен"
        case .all: "Повторять очередь"
        case .one: "Повторять трек"
        }
    }

}

private struct MinimalTrackSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let activeColor: Color
    let inactiveColor: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(inactiveColor)
                Capsule()
                    .fill(activeColor)
                    .frame(width: width * fraction)
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newFraction = min(max(gesture.location.x / width, 0), 1)
                        value = range.lowerBound + newFraction * span
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityAdjustableAction { direction in
            let step = max((range.upperBound - range.lowerBound) / 20, 0.05)
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

private struct ArtworkBackdrop: View {
    let artwork: Artwork?
    @State private var drifts = false
    @State private var image: UIImage?

    var body: some View {
        let displayedImage = image ?? artwork?.url.flatMap { ArtworkImageCache.shared.cachedImage(for: $0) }
        ZStack {
            Color.black
            if let displayedImage {
                Image(uiImage: displayedImage)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(drifts ? 1.22 : 1.08)
                    .offset(x: drifts ? 22 : -18, y: drifts ? -16 : 18)
                    .saturation(1.12)
                    .blur(radius: 62, opaque: true)
            } else {
                Color(uiColor: .systemGray5)
            }
            Color.black.opacity(0.32)
        }
        .ignoresSafeArea()
        .clipped()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drifts = true
            }
        }
        .task(id: artwork?.url) {
            guard let url = artwork?.url else { return }
            if let cached = ArtworkImageCache.shared.cachedImage(for: url) {
                image = cached
                return
            }
            image = nil
            image = await ArtworkImageCache.shared.image(for: url)
        }
    }
}

private struct LyricsView: View {
    @EnvironmentObject private var player: PlayerStore

    var body: some View {
        Group {
            if let lyrics = player.lyrics, !lyrics.lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                                if lyrics.isSynchronized {
                                    Button { player.seek(to: line.time) } label: {
                                        Text(line.text)
                                            .font(.title2.bold())
                                            .multilineTextAlignment(.leading)
                                            .foregroundStyle(index == player.activeLyricsLineIndex ? .white : .white.opacity(0.38))
                                            .scaleEffect(index == player.activeLyricsLineIndex ? 1 : 0.98, anchor: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .id(index)
                                } else {
                                    Text(line.text)
                                        .font(.title2.bold())
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(.white.opacity(0.9))
                                        .id(index)
                                }
                            }
                            if let writers = lyrics.writers, !writers.isEmpty {
                                Text("Авторы: \(writers)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.45))
                                    .padding(.top, 16)
                            }
                            if let source = lyrics.source, !source.isEmpty {
                                Text("Текст: \(source)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.45))
                                    .padding(.top, 8)
                            }
                        }
                        .padding(24)
                    }
                    .onChange(of: player.activeLyricsLineIndex) { _, index in
                        guard lyrics.isSynchronized else { return }
                        guard let index else { return }
                        withAnimation(.easeOut(duration: 0.35)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Текст недоступен",
                    systemImage: "quote.bubble",
                    description: Text("Он появится, если выбранный музыкальный сервис предоставляет текст песни.")
                )
                .foregroundStyle(.white)
            }
        }
    }
}

private struct QueueView: View {
    @EnvironmentObject private var appearance: AppearanceSettings
    @EnvironmentObject private var player: PlayerStore

    var body: some View {
        List(player.queue) { track in
            Button { Task { await player.play(track) } } label: {
                HStack(spacing: 12) {
                    ArtworkView(artwork: track.artwork, cornerRadius: 7)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).foregroundStyle(.white)
                        Text(track.artist.name).font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    if player.currentTrack?.id == track.id {
                        Image(systemName: "waveform").foregroundStyle(appearance.tint)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct AirPlayButton: UIViewRepresentable {
    @EnvironmentObject private var appearance: AppearanceSettings

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(appearance.tint)
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.activeTintColor = UIColor(appearance.tint)
    }
}
