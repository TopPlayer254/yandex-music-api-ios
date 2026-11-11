import AVKit
import SwiftUI

struct NowPlayingView: View {
    private enum Page {
        case player
        case lyrics
        case queue
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appearance: AppearanceSettings
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var downloads: DownloadsStore
    @State private var page: Page = .player
    @State private var backgroundVisible = false
    @GestureState private var pull: CGFloat = 0
    @Namespace private var coverTransition
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        ZStack {
            ArtworkBackdrop(artwork: player.currentTrack?.artwork)
                .opacity(backgroundVisible ? 1 : 0)

            GeometryReader { size in
                let compact = size.size.height < 680
                VStack(spacing: 0) {
                    grabber
                    Group {
                        if page == .player {
                            expandedArtwork
                        } else {
                            VStack(spacing: 0) {
                                HStack(spacing: 10) {
                                    if let track = player.currentTrack {
                                        ArtworkView(artwork: track.artwork, cornerRadius: 8)
                                            .frame(width: 48, height: 48)
                                            .matchedGeometryEffect(id: "playing-cover", in: coverTransition)
                                    }
                                    metadata(compact: true)
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 12)
                                if page == .lyrics { LyricsView().transition(.opacity) }
                                else { QueueView().transition(.opacity) }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)

                    VStack(spacing: compact ? 3 : 10) {
                        PlaybackScrubber(player: player, clock: player.clock)
                        transportControls(compact: compact)
                        volumeControl
                        pageControls.padding(.horizontal, 14)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                }
            }
        }
        .offset(y: pull)
        .animation(reducesMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88), value: page)
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

    private var grabber: some View {
        Button { dismiss() } label: {
            Capsule().fill(.white.opacity(0.45))
                .frame(width: 38, height: 5)
                .frame(width: 104, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Свернуть плеер")
        .simultaneousGesture(DragGesture(minimumDistance: 8)
            .updating($pull) { value, offset, _ in offset = max(value.translation.height, 0) * 0.75 }
            .onEnded { if $0.translation.height > 58 || $0.predictedEndTranslation.height > 120 { dismiss() } })
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

    private var expandedArtwork: some View {
        GeometryReader { proxy in
            let artworkSide = max(1, min(proxy.size.width - 56, proxy.size.height - 80))

            VStack(spacing: 12) {
                Spacer(minLength: 4)
                if let track = player.currentTrack {
                    ArtworkView(artwork: track.artwork, cornerRadius: 16)
                        .frame(width: artworkSide, height: artworkSide)
                        .matchedGeometryEffect(id: "playing-cover", in: coverTransition)
                        .scaleEffect(player.isPlaying || reducesMotion ? 1 : 0.91)
                        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: player.isPlaying)
                }
                Spacer(minLength: 6)
                metadata(compact: false)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
        }
    }

    private func metadata(compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 10) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    player.currentTrack?.title ?? "Ничего не играет",
                    font: compact ? .subheadline.bold() : .title3.bold(),
                    color: .white,
                    height: compact ? 20 : 25
                )
                MarqueeText(
                    player.currentTrack?.artist.name ?? "",
                    font: compact ? .caption : .title3,
                    color: .white.opacity(0.68),
                    height: compact ? 16 : 25
                )
            }

            if player.isBuffering {
                ProgressView().tint(.white)
            }
            if let track = player.currentTrack {
                Button { Task { await catalog.toggleFavorite(track) } } label: {
                    Image(systemName: catalog.isFavorite(track) ? "heart.fill" : "heart")
                        .font(compact ? .subheadline : .title3)
                        .foregroundStyle(catalog.isFavorite(track) ? appearance.accentText : .white)
                        .frame(width: compact ? 34 : 40, height: compact ? 34 : 40)
                        .background(catalog.isFavorite(track) ? appearance.buttonTint : .clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(catalog.isFavorite(track) ? "Убрать из любимого" : "Добавить в любимое")
            }
            moreMenu
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
                    .foregroundStyle(page == .lyrics ? appearance.accentText : .white)
                    .background(page == .lyrics ? appearance.buttonTint : .clear, in: RoundedRectangle(cornerRadius: 12))
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
                    .foregroundStyle(page == .queue ? appearance.accentText : .white)
                    .background(page == .queue ? appearance.buttonTint : .clear, in: RoundedRectangle(cornerRadius: 12))
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
                    Button(role: .destructive) { removeDownload(track) } label: {
                        Label("Удалить загрузку", systemImage: "trash").tint(.red)
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
        case .off: String(localized: "Повтор: выключен")
        case .all: String(localized: "Повторять очередь")
        case .one: String(localized: "Повторять трек")
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
    @State private var color = Color(red: 0.11, green: 0.12, blue: 0.15)

    var body: some View {
        color
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: artwork?.url) {
            var next = Color(red: 0.11, green: 0.12, blue: 0.15)
            if let url = artwork?.url, let image = await ArtworkImageCache.shared.image(for: url)?.cgImage,
               let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                       bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                if let data = context.data?.assumingMemoryBound(to: UInt8.self) {
                    next = Color(red: 0.06 + Double(data[0]) / 650,
                                 green: 0.06 + Double(data[1]) / 650,
                                 blue: 0.07 + Double(data[2]) / 650)
                }
            }
            guard !Task.isCancelled else { return }
            withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.45)) { color = next }
        }
    }
}

private struct LyricsView: View {
    @EnvironmentObject private var player: PlayerStore

    var body: some View { TimedLyricsView(player: player, clock: player.lyricsClock) }
}

private struct TimedLyricsView: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @ObservedObject var player: PlayerStore
    @ObservedObject var clock: LyricsClock
    @GestureState private var browsing = false
    @State private var followAt = Date.distantPast

    var body: some View {
        Group {
            if let lyrics = player.lyrics, !lyrics.lines.isEmpty {
                GeometryReader { viewport in
                let height = viewport.size.height
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                                if lyrics.isSynchronized {
                                    Button {
                                        followAt = .distantPast
                                        player.seek(to: line.time)
                                    } label: {
                                        LyricLineView(line: line, active: index == clock.index,
                                                      playing: player.isPlaying && !player.isBuffering,
                                                      clock: player.clock)
                                            .font(.title.bold())
                                            .multilineTextAlignment(.leading)
                                            .scaleEffect(reducesMotion || index == clock.index ? 1 : 0.96, anchor: .leading)
                                            .blur(radius: reducesMotion || browsing || index == clock.index ? 0 : 1.5)
                                            .animation(reducesMotion ? nil : .spring(response: 0.55, dampingFraction: 0.88), value: clock.index)
                                    }
                                    .buttonStyle(.plain)
                                    .modifier(LyricFlowMotion(line: index, active: browsing ? nil : clock.index, enabled: !reducesMotion))
                                    .visualEffect { effect, bounds in
                                        let y = bounds.frame(in: .named("lyricsViewport")).midY
                                        let edge = max(height - 82, 1)
                                        return effect.blur(radius: 5 * min(max((y - edge) / 82, 0), 1))
                                    }
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
                        .padding(.horizontal, 26)
                        .padding(.top, lyrics.isSynchronized ? height * 0.24 : 18)
                        .padding(.bottom, lyrics.isSynchronized ? height * 0.64 : 30)
                    }
                    .scrollIndicators(.hidden)
                    .coordinateSpace(name: "lyricsViewport")
                    .mask { LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.09),
                        .init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom) }
                    .simultaneousGesture(DragGesture(minimumDistance: 8)
                        .updating($browsing) { _, state, _ in state = true }
                        .onEnded { _ in followAt = Date().addingTimeInterval(4) })
                    .onChange(of: clock.index, initial: true) { _, index in
                        guard lyrics.isSynchronized, !browsing, Date() >= followAt, let index else { return }
                        scroll(to: index, proxy: proxy)
                    }
                    .task(id: followAt) {
                        guard lyrics.isSynchronized, followAt > Date() else { return }
                        do { try await Task.sleep(for: .seconds(max(followAt.timeIntervalSinceNow, 0))) }
                        catch { return }
                        if !browsing, let index = clock.index { scroll(to: index, proxy: proxy) }
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

    private func scroll(to index: Int, proxy: ScrollViewProxy) {
        withAnimation(reducesMotion ? nil : .spring(response: 0.55, dampingFraction: 0.83)) {
            proxy.scrollTo(index, anchor: UnitPoint(x: 0.5, y: 0.31))
        }
    }
}

private struct LyricFlowMotion: ViewModifier {
    let line: Int
    let active: Int?
    let enabled: Bool
    @State private var lift: CGFloat = 0
    @State private var lastActive: Int?

    func body(content: Content) -> some View {
        content.offset(y: lift)
            .onChange(of: active, initial: true) { _, next in
                let previous = lastActive
                lastActive = next
                guard enabled, let next, let previous, abs(next - previous) == 1,
                      (-1...5).contains(line - next) else { return }
                let distance = max(line - next, 0)
                let direction: CGFloat = next > previous ? 1 : -1
                withTransaction(Transaction(animation: nil)) {
                    lift = direction * CGFloat(10 + min(distance, 4) * 3)
                }
                withAnimation(.spring(response: 0.47, dampingFraction: 0.64)
                    .delay(Double(min(distance, 4)) * 0.037)) { lift = 0 }
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
                        PlayingEqualizer(motion: player.waveMotion, isPlaying: player.isPlaying, color: .white)
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
                        .background(player.isShuffling ? appearance.buttonTint : .white.opacity(0.12), in: Capsule())
                }
                .accessibilityValue(player.isShuffling ? "Включено" : "Выключено")
                Button { player.cycleRepeatMode() } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(player.repeatMode != .off ? appearance.accentText : .white)
                        .background(player.repeatMode != .off ? appearance.buttonTint : .white.opacity(0.12), in: Circle())
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
    @ObservedObject var motion: WaveMotionStore
    let isPlaying: Bool
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(1...4, id: \.self) { index in
                Capsule().fill(color)
                    .frame(width: 3, height: isPlaying && !reducesMotion ? 4 + 14 * CGFloat(motion.levels[index]) : 4)
            }
        }
        .frame(width: 20, height: 19)
        .animation(reducesMotion ? nil : .linear(duration: 0.05), value: motion.levels)
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
