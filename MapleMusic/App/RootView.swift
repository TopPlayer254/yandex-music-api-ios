import SwiftUI

enum AppTab: Hashable {
    case home
    case library
    case search
}

struct RootView: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @State private var selection: AppTab = .home
    @Namespace private var playerTransition

    var body: some View {
        Group {
            if #available(iOS 26.1, *) {
                ModernTabs(selection: $selection)
            } else {
                LegacyTabs(selection: $selection)
            }
        }
        .environment(\.playerTransition, playerTransition)
        .onOpenURL { url in
            if url.scheme == "maplemusic", ["player", "lyrics"].contains(url.host ?? ""), player.currentTrack != nil {
                player.opensLyrics = url.host == "lyrics"
                player.isShowingNowPlaying = true
            }
        }
        .task(id: "\(player.currentTrack?.artwork.url?.absoluteString ?? "")|\(appearance.accent.rawValue)") {
            await appearance.followArtwork(player.currentTrack?.artwork)
        }
        .fullScreenCover(isPresented: $player.isShowingNowPlaying) {
            if #available(iOS 18.0, *) {
                NowPlayingView()
                    .navigationTransition(.zoom(sourceID: "mini-player", in: playerTransition))
            } else {
                NowPlayingView()
            }
        }
        .modifier(MusicErrorPresentation(isPlayer: false))
    }
}

struct MusicErrorPresentation: ViewModifier {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var downloads: DownloadsStore
    @EnvironmentObject private var developer: DeveloperSettings
    let isPlayer: Bool
    private var isActive: Bool { player.isShowingNowPlaying == isPlayer }

    func body(content: Content) -> some View {
        content
        .alert("Музыкальный сервис", isPresented: Binding(
            get: { isActive && !developer.usesNewRetryScreen && (catalog.errorMessage != nil || downloads.errorMessage != nil) },
            set: {
                if !$0 {
                    catalog.errorMessage = nil
                    downloads.errorMessage = nil
                }
            }
        )) {
            Button("ОК", role: .cancel) {
                catalog.errorMessage = nil
                downloads.errorMessage = nil
            }
        } message: {
            Text(downloads.errorMessage ?? catalog.errorMessage ?? "")
        }
        .alert("Ошибка воспроизведения", isPresented: Binding(
            get: { isActive && !developer.usesNewRetryScreen && player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "Неизвестная ошибка")
        }
        .sheet(isPresented: Binding(
            get: { isActive && developer.usesNewRetryScreen && (player.errorMessage != nil || catalog.errorMessage != nil || downloads.errorMessage != nil) },
            set: { if !$0 { clearErrors() } }
        )) {
            let playbackError = player.errorMessage != nil
            RetryScreen(
                message: player.errorMessage ?? downloads.errorMessage ?? catalog.errorMessage ?? "Ошибка загрузки",
                actionTitle: playbackError ? "Повторить воспроизведение" : "Обновить данные"
            ) {
                clearErrors()
                if playbackError { player.retryPlayback() }
                else { Task { await catalog.bootstrap(); await downloads.refresh() } }
            }
        }
    }

    private func clearErrors() {
        player.errorMessage = nil
        catalog.errorMessage = nil
        downloads.errorMessage = nil
    }
}

@available(iOS 26.1, *)
private struct ModernTabs: View {
    @EnvironmentObject private var player: PlayerStore
    @Binding var selection: AppTab

    var body: some View {
        tabs
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory(isEnabled: player.currentTrack != nil) {
                if let track = player.currentTrack {
                    ModernMiniPlayer(track: track)
                }
            }
            .animation(.smooth(duration: 0.28), value: player.currentTrack?.id)
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Главная", systemImage: selection == .home ? "house.fill" : "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Медиатека", systemImage: selection == .library ? "square.stack.fill" : "square.stack", value: AppTab.library) {
                LibraryView()
            }
            Tab("Поиск", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView()
            }
        }
    }
}

private struct LegacyTabs: View {
    @Binding var selection: AppTab

    var body: some View {
        TabView(selection: $selection) {
            LegacyTabContent { HomeView() }
                .tabItem { Label("Главная", systemImage: selection == .home ? "house.fill" : "house") }
                .tag(AppTab.home)

            LegacyTabContent { LibraryView() }
                .tabItem { Label("Медиатека", systemImage: selection == .library ? "square.stack.fill" : "square.stack") }
                .tag(AppTab.library)

            LegacyTabContent { SearchView() }
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
        }
    }
}

private struct LegacyTabContent<Content: View>: View {
    @EnvironmentObject private var player: PlayerStore
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 6) {
                if let track = player.currentTrack {
                    LegacyMiniPlayer(track: track)
                        .padding(.horizontal, 8)
                }
            }
    }
}

@available(iOS 26.1, *)
private struct ModernMiniPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @EnvironmentObject private var player: PlayerStore
    let track: Track

    var body: some View {
        Group {
        if placement == .inline {
            HStack(spacing: 8) {
                Button { showNowPlaying() } label: {
                    HStack(spacing: 8) {
                        ArtworkView(artwork: track.artwork, cornerRadius: 6)
                            .frame(width: 32, height: 32)
                        MarqueeText(
                            track.title,
                            font: .caption.weight(.semibold),
                            color: .primary,
                            height: 17
                        )
                        Spacer(minLength: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                playbackButton(size: 44)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 8) {
                Button { showNowPlaying() } label: {
                    HStack(spacing: 10) {
                        ArtworkView(artwork: track.artwork, cornerRadius: 7)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            MarqueeText(
                                track.title,
                                font: .subheadline.weight(.semibold),
                                color: .primary,
                                height: 20
                            )
                            MarqueeText(track.artist.name, font: .caption, color: .secondary, height: 16)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if player.isBuffering { ProgressView().controlSize(.small) }
                playbackButton(size: 44)
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").frame(width: 38, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Следующий трек")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        }
        .modifier(MiniPlayerTransitionSource())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > 55,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 { player.next() }
                else { player.previous() }
            }
        )
    }

    private func playbackButton(size: CGFloat) -> some View {
        Button { player.togglePlayback() } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .frame(width: size, height: size)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
    }

    private func showNowPlaying() {
        withAnimation(.smooth(duration: 0.28)) {
            player.isShowingNowPlaying = true
        }
    }

}

private struct LegacyMiniPlayer: View {
    @EnvironmentObject private var player: PlayerStore
    let track: Track

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.24)) {
                    player.isShowingNowPlaying = true
                }
            } label: {
                HStack(spacing: 10) {
                    ArtworkView(artwork: track.artwork, cornerRadius: 7)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        MarqueeText(
                            track.title,
                            font: .subheadline.weight(.semibold),
                            color: .primary,
                            height: 20
                        )
                        MarqueeText(track.artist.name, font: .caption, color: .secondary, height: 16)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if player.isBuffering { ProgressView().controlSize(.small) }
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .frame(width: 38, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Следующий трек")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 15, style: .continuous), interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Сейчас играет \(track.title), \(track.artist.name)")
        .modifier(MiniPlayerTransitionSource())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > 55,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 { player.next() }
                else { player.previous() }
            }
        )
    }
}

private struct PlayerTransitionKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var playerTransition: Namespace.ID? {
        get { self[PlayerTransitionKey.self] }
        set { self[PlayerTransitionKey.self] = newValue }
    }
}

private struct MiniPlayerTransitionSource: ViewModifier {
    @Environment(\.playerTransition) private var namespace
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace {
            content.matchedTransitionSource(id: "mini-player", in: namespace)
        } else { content }
    }
}
