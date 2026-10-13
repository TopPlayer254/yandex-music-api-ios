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
    @State private var backgroundVisible = false
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        ZStack {
            ArtworkBackdrop(artwork: player.currentTrack?.artwork)
                .opacity(backgroundVisible ? 1 : 0)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

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
                    .padding(.horizontal, 42)
                    .padding(.bottom, 14)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: page)
        .preferredColorScheme(.dark)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if player.opensLyrics { page = .lyrics; player.opensLyrics = false }
            withAnimation(.easeOut(duration: reducesMotion ? 0 : 0.35)) { backgroundVisible = true }
        }
        .presentationDragIndicator(.hidden)
        .modifier(MusicErrorPresentation(isPlayer: true))
        .onChange(of: player.currentTrack?.id) { _, trackID in
            if trackID == nil { dismiss() }
        }
        .onChange(of: player.opensLyrics) { _, requested in
            if requested { page = .lyrics; player.opensLyrics = false }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)

            VStack(spacing: 2) {
                Text(page.title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                MarqueeText(
                    player.currentTrack?.albumTitle ?? "Maple Music",
                    font: .caption,
                    color: .white,
                    height: 16
                )
            }
            .frame(maxWidth: .infinity)

            moreMenu
        }
        .foregroundStyle(.white)
        .frame(height: 46)
    }

    private var moreMenu: some View {
        StableNowPlayingMenu(
            track: player.currentTrack,
            quality: player.preferredQuality,
            isShuffling: player.isShuffling,
            repeatMode: player.repeatMode,
            isDownloaded: player.currentTrack.map(downloads.isDownloaded) ?? false,
            selectQuality: { player.preferredQuality = $0 },
            toggleShuffle: { player.isShuffling.toggle() },
            cycleRepeat: { player.cycleRepeatMode() },
            download: { track in Task { await downloads.download(track, quality: player.preferredQuality) } },
            removeDownload: { track in Task { await downloads.remove(track) } }
        )
        .equatable()
    }

    private var playerPage: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 620
            let artworkSide = min(proxy.size.width - 56, proxy.size.height * (compact ? 0.36 : 0.44))

            VStack(spacing: compact ? 10 : 18) {
                Spacer(minLength: compact ? 8 : 18)

                if let track = player.currentTrack {
                    ArtworkView(artwork: track.artwork, cornerRadius: compact ? 12 : 16)
                        .frame(width: artworkSide, height: artworkSide)
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                        .scaleEffect(player.isPlaying ? 1 : 0.94)
                        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: player.isPlaying)
                }

                Spacer(minLength: compact ? 6 : 12)
                metadata
                PlaybackScrubber(player: player, clock: player.clock)
                transportControls(compact: compact)
                volumeControl
                Spacer(minLength: 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
        }
    }

    private var metadata: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    player.currentTrack?.title ?? "Ничего не играет",
                    font: .title3.bold(),
                    color: .white,
                    height: 25
                )
                MarqueeText(
                    player.currentTrack?.artist.name ?? "",
                    font: .title3,
                    color: .white.opacity(0.68),
                    height: 25
                )
            }

            Spacer(minLength: 8)
            if player.isBuffering {
                ProgressView().tint(.white)
            }
            if let track = player.currentTrack {
                Button { Task { await catalog.toggleFavorite(track) } } label: {
                    Image(systemName: catalog.isFavorite(track) ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(catalog.isFavorite(track) ? appearance.tint : .white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(catalog.isFavorite(track) ? 0.16 : 0), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(catalog.isFavorite(track) ? "Убрать из любимого" : "Добавить в любимое")
            }
        }
        .foregroundStyle(.white)
    }

    private func transportControls(compact: Bool) -> some View {
        HStack {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: compact ? 28 : 32))
                    .frame(width: 58, height: 58)
            }
            Spacer()
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 42 : 48, weight: .medium))
                    .frame(width: 76, height: 68)
                    .contentTransition(.symbolEffect(.replace))
            }
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: compact ? 28 : 32))
                    .frame(width: 58, height: 58)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
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
        HStack {
            Button { page = page == .lyrics ? .player : .lyrics } label: {
                Image(systemName: "quote.bubble")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(page == .lyrics ? appearance.tint : .white)
                    .background(.white.opacity(page == .lyrics ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Текст песни")
            Spacer()
            AirPlayButton()
                .frame(width: 20, height: 20)
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay")
            Spacer()
            Button { page = page == .queue ? .player : .queue } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(page == .queue ? appearance.tint : .white)
                    .background(.white.opacity(page == .queue ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Очередь")
        }
        .font(.title3)
    }

}

private struct StableNowPlayingMenu: View, Equatable {
    let track: Track?
    let quality: AudioQuality
    let isShuffling: Bool
    let repeatMode: RepeatMode
    let isDownloaded: Bool
    let selectQuality: (AudioQuality) -> Void
    let toggleShuffle: () -> Void
    let cycleRepeat: () -> Void
    let download: (Track) -> Void
    let removeDownload: (Track) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.track?.id == rhs.track?.id && lhs.quality == rhs.quality
            && lhs.isShuffling == rhs.isShuffling && lhs.repeatMode == rhs.repeatMode
            && lhs.isDownloaded == rhs.isDownloaded
    }

    var body: some View {
        Menu {
            Menu("Качество") {
                ForEach(AudioQuality.selectableCases) { option in
                    Button {
                        selectQuality(option)
                    } label: {
                        if quality == option { Label(option.title, systemImage: "checkmark") }
                        else { Text(option.title) }
                    }
                }
            }
            if let track {
                TrackActions(track: track)
                if isDownloaded {
                    Button("Удалить загрузку", systemImage: "trash", role: .destructive) {
                        removeDownload(track)
                    }
                } else if track.downloadAllowed {
                    Button("Загрузить", systemImage: "arrow.down.circle") { download(track) }
                }
            }
            Divider()
            Button(isShuffling ? "Выключить перемешивание" : "Перемешать", systemImage: "shuffle") {
                toggleShuffle()
            }
            Button(repeatTitle, systemImage: repeatMode == .one ? "repeat.1" : "repeat") {
                cycleRepeat()
            }
        } label: {
            Image(systemName: "ellipsis").font(.headline).frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Действия с треком")
    }

    private var repeatTitle: String {
        switch repeatMode {
        case .off: "Повтор: выключен"
        case .all: "Повторять очередь"
        case .one: "Повторять трек"
        }
    }
}

struct MinimalTrackSlider: View {
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
            .frame(height: 7)
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

struct ArtworkBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    let artwork: Artwork?
    @State private var drifts = false
    @State private var image: UIImage?

    var body: some View {
        let displayedImage = image ?? artwork?.url.flatMap { ArtworkImageCache.shared.cachedImage(for: $0) }
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let displayedImage {
                    Image(uiImage: displayedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .scaleEffect(drifts ? 1.22 : 1.08)
                        .offset(x: drifts ? 22 : -18, y: drifts ? -16 : 18)
                        .saturation(1.12)
                        .blur(radius: 62, opaque: true)
                } else {
                    Color(uiColor: .systemGray5)
                }
                Color.black.opacity(0.32)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reducesMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drifts = true
            }
        }
        .task(id: artwork?.url) {
            guard let url = artwork?.url else {
                image = nil
                return
            }
            if let cached = ArtworkImageCache.shared.cachedImage(for: url) {
                image = cached
                return
            }
            image = nil
            let loadedImage = await ArtworkImageCache.shared.image(for: url)
            guard !Task.isCancelled, artwork?.url == url else { return }
            image = loadedImage
        }
    }
}

private struct LyricsView: View {
    @EnvironmentObject private var player: PlayerStore

    var body: some View { TimedLyricsView(player: player, clock: player.lyricsClock) }
}

private struct TimedLyricsView: View {
    @ObservedObject var player: PlayerStore
    @ObservedObject var clock: LyricsClock

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
                                            .foregroundStyle(index == clock.index ? .white : .white.opacity(0.38))
                                            .scaleEffect(index == clock.index ? 1 : 0.98, anchor: .leading)
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
                    .onChange(of: clock.index) { _, index in
                        guard lyrics.isSynchronized else { return }
                        guard let index else { return }
                        withAnimation(.easeOut(duration: 0.35)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Текст недоступен", systemImage: "quote.bubble")
                } description: {
                    Text(player.lyricsErrorMessage ?? "Ищем текст у Яндекса и в открытом каталоге LRCLIB.")
                } actions: {
                    Button("Повторить") { player.reloadLyrics() }
                        .buttonStyle(.bordered)
                }
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
                        PlayingEqualizer(isPlaying: player.isPlaying, color: appearance.tint)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 12) {
                Button { player.isShuffling.toggle() } label: {
                    Label("Перемешать", systemImage: "shuffle")
                        .padding(12)
                        .foregroundStyle(player.isShuffling ? appearance.accentText : .white)
                        .background(player.isShuffling ? appearance.tint : .white.opacity(0.12), in: Capsule())
                }
                .accessibilityValue(player.isShuffling ? "Включено" : "Выключено")
                Button { player.cycleRepeatMode() } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(player.repeatMode != .off ? appearance.accentText : .white)
                        .background(player.repeatMode != .off ? appearance.tint : .white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Повтор")
                .accessibilityValue(player.repeatMode == .off ? "Выключен" : (player.repeatMode == .one ? "Один трек" : "Вся очередь"))
                Spacer()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
    }
}

private struct PlayingEqualizer: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    let isPlaying: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying || reducesMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: isPlaying && !reducesMotion
                            ? 5 + 12 * abs(sin(time * (5.2 + Double(index) * 1.3) + Double(index)))
                            : 6)
                }
            }
            .frame(width: 20, height: 19)
        }
        .accessibilityLabel(isPlaying ? "Сейчас играет" : "Выбранный трек")
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
