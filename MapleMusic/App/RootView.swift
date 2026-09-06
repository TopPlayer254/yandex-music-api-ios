import SwiftUI

enum AppTab: Hashable {
    case home
    case library
    case search
}

struct RootView: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var downloads: DownloadsStore
    @State private var selection: AppTab = .home

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                ModernTabs(selection: $selection)
            } else {
                LegacyTabs(selection: $selection)
            }
        }
        .sheet(isPresented: $player.isShowingNowPlaying) {
            NowPlayingView()
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
        }
        .alert("Музыкальный сервис", isPresented: Binding(
            get: { catalog.errorMessage != nil || downloads.errorMessage != nil },
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
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "Неизвестная ошибка")
        }
    }
}

@available(iOS 26.0, *)
private struct ModernTabs: View {
    @EnvironmentObject private var player: PlayerStore
    @Binding var selection: AppTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Главная", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Медиатека", systemImage: "square.stack.fill", value: AppTab.library) {
                LibraryView()
            }
            Tab("Поиск", systemImage: "magnifyingglass", value: AppTab.search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            if let track = player.currentTrack {
                ModernMiniPlayer(track: track)
            }
        }
    }
}

private struct LegacyTabs: View {
    @Binding var selection: AppTab

    var body: some View {
        TabView(selection: $selection) {
            LegacyTabContent { HomeView() }
                .tabItem { Label("Главная", systemImage: "house.fill") }
                .tag(AppTab.home)

            LegacyTabContent { LibraryView() }
                .tabItem { Label("Медиатека", systemImage: "square.stack.fill") }
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

@available(iOS 26.0, *)
private struct ModernMiniPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @EnvironmentObject private var player: PlayerStore
    let track: Track

    var body: some View {
        if placement == .inline {
            HStack(spacing: 8) {
                ArtworkView(artwork: track.artwork, cornerRadius: 6)
                    .frame(width: 30, height: 30)
                Text(track.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                playbackButton(size: 30)
            }
            .contentShape(Rectangle())
            .onTapGesture { player.isShowingNowPlaying = true }
        } else {
            HStack(spacing: 11) {
                ArtworkView(artwork: track.artwork, cornerRadius: 7)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(track.artist.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if player.isBuffering { ProgressView().controlSize(.small) }
                playbackButton(size: 38)
                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: 34, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Следующий трек")
            }
            .padding(.horizontal, 10)
            .overlay(alignment: .bottom) { progressBar }
            .contentShape(Rectangle())
            .onTapGesture { player.isShowingNowPlaying = true }
        }
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

    private var progressBar: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.tint)
                .frame(width: proxy.size.width * player.progress, height: 2)
        }
        .frame(height: 2)
    }
}

private struct LegacyMiniPlayer: View {
    @EnvironmentObject private var player: PlayerStore
    let track: Track

    var body: some View {
        HStack(spacing: 11) {
            ArtworkView(artwork: track.artwork, cornerRadius: 7)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(track.artist.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if player.isBuffering { ProgressView().controlSize(.small) }
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .frame(width: 34, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Следующий трек")
        }
        .padding(6)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 15, style: .continuous), interactive: true)
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Capsule()
                    .fill(.tint)
                    .frame(width: proxy.size.width * player.progress, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 10)
        }
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .onTapGesture { player.isShowingNowPlaying = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Сейчас играет \(track.title), \(track.artist.name)")
    }
}
