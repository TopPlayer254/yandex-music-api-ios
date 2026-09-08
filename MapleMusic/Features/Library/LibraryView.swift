import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var downloads: DownloadsStore
    @State private var showsAccount = false
    @State private var showsNewPlaylist = false
    @State private var playlistName = ""

    var body: some View {
        NavigationStack {
            Group {
                if let library = catalog.library ?? offlineLibrary {
                    List {
                        Section {
                            NavigationLink {
                                TrackListView(title: "Недавно добавленные", tracks: library.recentlyAdded)
                            } label: {
                                Label("Недавно добавленные", systemImage: "clock")
                            }
                            NavigationLink {
                                TrackListView(title: "Любимые", tracks: library.liked, showsDownloadAll: true)
                            } label: {
                                Label("Любимые", systemImage: "heart.fill")
                            }
                            NavigationLink {
                                DownloadsView(allTracks: allTracks(in: library))
                            } label: {
                                Label("Загруженные", systemImage: "arrow.down.circle.fill")
                            }
                        }
                        Section("Плейлисты") {
                            ForEach(library.playlists) { playlist in
                                NavigationLink {
                                    PlaylistView(playlist: playlist)
                                } label: {
                                    HStack(spacing: 12) {
                                        ArtworkView(artwork: playlist.artwork, cornerRadius: 7)
                                            .frame(width: 50, height: 50)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(playlist.name)
                                            Text((playlist.totalTrackCount ?? playlist.tracks.count).russianTrackCount)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else if catalog.isLoading {
                    LibraryLoadingPlaceholder()
                } else if auth.state == .signedOut {
                    ContentUnavailableView {
                        Label("Войдите в аккаунт", systemImage: "person.crop.circle")
                    } description: {
                        Text("После входа здесь появятся любимые треки и плейлисты.")
                    } actions: {
                        Button("Открыть настройки") { showsAccount = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if let error = catalog.libraryErrorMessage {
                    ContentUnavailableView {
                        Label("Не удалось загрузить медиатеку", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Повторить") { Task { await catalog.refreshLibrary() } }
                            .buttonStyle(.borderedProminent)
                        Button("Открыть настройки") { showsAccount = true }
                    }
                } else {
                    ContentUnavailableView(
                        "Медиатека пуста",
                        systemImage: "square.stack",
                        description: Text("Добавленные в аккаунте треки и плейлисты появятся здесь.")
                    )
                }
            }
            .navigationTitle("Медиатека")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsNewPlaylist = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Новый плейлист")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AccountToolbarButton(isPresented: $showsAccount)
                }
            }
            .refreshable { await catalog.refreshLibrary() }
            .sheet(isPresented: $showsAccount) { AccountView() }
            .alert("Новый плейлист", isPresented: $showsNewPlaylist) {
                TextField("Название плейлиста", text: $playlistName)
                Button("Отмена", role: .cancel) { playlistName = "" }
                Button("Создать") {
                    let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    playlistName = ""
                    guard !name.isEmpty else { return }
                    Task { await catalog.createPlaylist(named: name) }
                }
            }
        }
    }

    private var offlineLibrary: MusicLibrary? {
        let tracks = downloads.entries.compactMap(\.track)
        guard !tracks.isEmpty else { return nil }
        return MusicLibrary(recentlyAdded: tracks, liked: [], playlists: [])
    }

    private func allTracks(in library: MusicLibrary) -> [Track] {
        var seen = Set<String>()
        return (library.recentlyAdded + library.liked + library.playlists.flatMap(\.tracks)).filter {
            seen.insert($0.id).inserted
        }
    }
}

struct TrackListView: View {
    @EnvironmentObject private var appearance: AppearanceSettings
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var downloads: DownloadsStore
    let title: String
    let tracks: [Track]
    var showsDownloadAll = false

    var body: some View {
        List {
            if !tracks.isEmpty {
                HStack(spacing: 10) {
                    Button { Task { await player.play(tracks[0], queue: tracks) } } label: {
                        Label("Воспроизвести", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .tint(appearance.tint)
                    .adaptiveProminentButtonStyle()

                    if showsDownloadAll {
                        DownloadAllButton(tracks: tracks)
                    }
                }
            }
            ForEach(tracks) { track in
                TrackRow(
                    track: track,
                    isDownloaded: downloads.isDownloaded(track),
                    isDownloading: downloads.activeTrackIDs.contains(track.id),
                    play: { Task { await player.play(track, queue: tracks) } },
                    toggleDownload: {
                        Task {
                            if downloads.isDownloaded(track) {
                                await downloads.remove(track)
                            } else {
                                await downloads.download(track, quality: player.preferredQuality)
                            }
                        }
                    }
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView("Нет треков", systemImage: "music.note")
            }
        }
    }
}

struct PlaylistView: View {
    @EnvironmentObject private var appearance: AppearanceSettings
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var downloads: DownloadsStore
    private let initialPlaylist: Playlist
    @State private var loaded: Playlist?
    private var playlist: Playlist { loaded ?? initialPlaylist }
    init(playlist: Playlist) { initialPlaylist = playlist }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    ArtworkView(artwork: playlist.artwork, cornerRadius: 18)
                        .frame(maxWidth: 280)
                        .aspectRatio(1, contentMode: .fit)
                        .shadow(color: .black.opacity(0.2), radius: 15, y: 8)
                    VStack(spacing: 4) {
                        Text(playlist.name).font(.title2.bold())
                        if let description = playlist.description {
                            Text(description).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    HStack(spacing: 10) {
                        Button { if let first = playlist.tracks.first { Task { await player.play(first, queue: playlist.tracks) } } } label: {
                            Label("Воспроизвести", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.white)
                        }
                        .tint(appearance.tint)
                        .adaptiveProminentButtonStyle()

                        DownloadAllButton(tracks: playlist.tracks)
                    }

                    Button {
                        if let random = playlist.tracks.randomElement() {
                            player.isShuffling = true
                            Task { await player.play(random, queue: playlist.tracks) }
                        }
                    } label: {
                        Label("Перемешать", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                    }
                    .adaptiveSecondaryButtonStyle()
                    .accessibilityLabel("Перемешать")
                }
                .listRowBackground(Color.clear)
                .padding(.vertical)
            }

            ForEach(playlist.tracks) { track in
                TrackRow(
                    track: track,
                    isDownloaded: downloads.isDownloaded(track),
                    isDownloading: downloads.activeTrackIDs.contains(track.id),
                    play: { Task { await player.play(track, queue: playlist.tracks) } },
                    toggleDownload: {
                        Task {
                            if downloads.isDownloaded(track) { await downloads.remove(track) }
                            else { await downloads.download(track, quality: player.preferredQuality) }
                        }
                    }
                )
                .swipeActions {
                    if playlist.isEditable {
                        Button("Удалить", role: .destructive) {
                            Task {
                                await catalog.remove(track, from: playlist)
                                loaded = await catalog.loadPlaylist(playlist.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { loaded = await catalog.loadPlaylist(initialPlaylist.id) }
        .refreshable { loaded = await catalog.loadPlaylist(initialPlaylist.id) }
    }
}

private struct DownloadAllButton: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var downloads: DownloadsStore
    let tracks: [Track]

    var body: some View {
        Button {
            Task { await downloads.downloadAll(tracks, quality: player.preferredQuality) }
        } label: {
            if let progress = downloads.bulkProgress {
                Label("\(progress.completed)/\(progress.total)", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            } else {
                Label("Скачать всё", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
        }
        .adaptiveSecondaryButtonStyle()
        .disabled(
            tracks.isEmpty
                || downloads.bulkProgress != nil
                || tracks.filter(\.downloadAllowed).allSatisfy(downloads.isDownloaded)
        )
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadsStore
    let allTracks: [Track]

    private var downloadedTracks: [Track] {
        downloads.entries.compactMap(\.track)
    }

    var body: some View {
        TrackListView(title: "Загруженные", tracks: downloadedTracks)
            .task { await downloads.refresh() }
    }
}

private struct LibraryLoadingPlaceholder: View {
    var body: some View {
        List {
            ForEach(0 ..< 5, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.quaternary)
                        .frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Название плейлиста").font(.body)
                        Text("12 треков").font(.caption)
                    }
                }
            }
            .redacted(reason: .placeholder)
        }
        .listStyle(.insetGrouped)
        .accessibilityLabel("Загрузка медиатеки")
    }
}
