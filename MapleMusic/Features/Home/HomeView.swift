import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var settings: ProviderSettings
    @EnvironmentObject private var waveSettings: WaveSettings
    @EnvironmentObject private var developerSettings: DeveloperSettings
    @State private var showsAccount = false
    @State private var showsWaveSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let home = catalog.home, hasContent(home) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            if developerSettings.usesNewShaderBasedWave,
                               let wave = home.shelves.first(where: { $0.id == "my-wave" }) {
                                shelfView(wave)
                                featured(home.featured)
                                ForEach(home.shelves.filter { $0.id != wave.id }) { shelf in
                                    shelfView(shelf)
                                }
                            } else {
                                featured(home.featured)
                                ForEach(home.shelves) { shelf in
                                    shelfView(shelf)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                } else if catalog.isLoading {
                    HomeLoadingPlaceholder()
                } else if auth.state == .signedOut {
                    ContentUnavailableView {
                        Label("Ваша музыка начинается здесь", systemImage: "music.note.house")
                    } description: {
                        Text("Войдите в аккаунт в настройках, чтобы открыть свою музыку.")
                    } actions: {
                        Button("Открыть настройки") { showsAccount = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if let error = catalog.homeErrorMessage {
                    ContentUnavailableView {
                        Label("Не удалось загрузить главную", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Повторить") { Task { await catalog.refreshHome() } }
                            .buttonStyle(.borderedProminent)
                        Button("Открыть настройки") { showsAccount = true }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Пока нет рекомендаций", systemImage: "music.note.house")
                    } description: {
                        Text("Откройте поиск или обновите страницу немного позже.")
                    } actions: {
                        Button("Обновить") { Task { await catalog.refreshHome() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(developerSettings.showsCodename ? "" : "Главная")
            .navigationBarTitleDisplayMode(developerSettings.showsCodename ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if developerSettings.showsCodename {
                        Image("CodenameLogo")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 193, height: 26)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("хуЯндекс Maple")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AccountToolbarButton(isPresented: $showsAccount)
                }
            }
            .refreshable { await catalog.refreshHome() }
            .sheet(isPresented: $showsAccount) { AccountView() }
            .sheet(isPresented: $showsWaveSettings) { WaveSettingsView() }
        }
    }

    private func hasContent(_ home: HomeFeed) -> Bool {
        !home.featured.isEmpty || home.shelves.contains { !$0.tracks.isEmpty }
    }

    private func featured(_ tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Слушать сейчас")
                .font(.title2.bold())
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(tracks) { track in
                        Button { Task { await player.play(track, queue: tracks) } } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkView(artwork: track.artwork, cornerRadius: 14)
                                    .frame(width: 260, height: 260)
                                    .shadow(color: .black.opacity(0.18), radius: 12, y: 7)
                                Text(track.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                Text(track.artist.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 260, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { TrackActions(track: track) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func shelfView(_ shelf: MusicShelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if shelf.id == "my-wave-shadow-ban" {
                        Label(shelf.title, systemImage: "exclamationmark.triangle.fill")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                    } else {
                        Text(shelf.title).font(.title2.bold())
                    }
                    if let subtitle = shelf.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if shelf.id == "my-wave",
                   settings.configuration.kind == .yandex,
                   !developerSettings.usesNewShaderBasedWave {
                    Button { showsWaveSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Настроить Мою волну")
                }
            }
            .padding(.horizontal)

            if shelf.id == "my-wave",
               developerSettings.usesNewShaderBasedWave,
               let firstTrack = shelf.tracks.first {
                let isCurrentWaveTrack = shelf.tracks.contains { $0.id == player.currentTrack?.id }
                WaveLaunchButton(
                    artwork: player.currentTrack?.artwork ?? firstTrack.artwork,
                    mood: waveSettings.configuration.moodEnergy,
                    isPlaying: isCurrentWaveTrack && player.isPlaying,
                    isBuffering: isCurrentWaveTrack && player.isBuffering,
                    action: {
                        if isCurrentWaveTrack {
                            player.togglePlayback()
                        } else {
                            Task { await player.play(firstTrack, queue: shelf.tracks) }
                        }
                    },
                    settingsAction: { showsWaveSettings = true }
                )
                .padding(.horizontal)
            }

            if shelf.id == "my-wave", developerSettings.usesNewShaderBasedWave {
                EmptyView()
            } else if shelf.layout == .cards {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(shelf.tracks) { track in
                            Button { Task { await player.play(track, queue: shelf.tracks) } } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    ArtworkView(artwork: track.artwork)
                                        .frame(width: 156, height: 156)
                                    Text(track.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                    Text(track.artist.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 156, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { TrackActions(track: track) }
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(shelf.tracks) { track in
                        CompactTrackRow(track: track, queue: shelf.tracks)
                        if track.id != shelf.tracks.last?.id { Divider().padding(.leading, 76) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct HomeLoadingPlaceholder: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Слушать сейчас").font(.title2.bold())
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)
                    .frame(height: 260)
                ForEach(0 ..< 4, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Название трека")
                            Text("Исполнитель").font(.subheadline)
                        }
                    }
                }
            }
            .padding()
            .redacted(reason: .placeholder)
        }
        .accessibilityLabel("Загрузка главной")
    }
}

private struct CompactTrackRow: View {
    @EnvironmentObject private var player: PlayerStore
    let track: Track
    let queue: [Track]

    var body: some View {
        Button { Task { await player.play(track, queue: queue) } } label: {
            HStack(spacing: 12) {
                ArtworkView(artwork: track.artwork, cornerRadius: 7).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).foregroundStyle(.primary).lineLimit(1)
                    Text(track.artist.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .contextMenu { TrackActions(track: track) }
    }
}
