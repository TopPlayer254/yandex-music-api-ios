import SwiftUI
import UniformTypeIdentifiers

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
    @State private var presentedSheet: PlaylistSheet?
    @State private var showsFileImporter = false
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
        .toolbar {
            if playlist.isEditable {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            presentedSheet = .addFromLibrary
                        } label: {
                            Label("Добавить из медиатеки", systemImage: "music.note.list")
                        }
                        Button {
                            showsFileImporter = true
                        } label: {
                            Label("Импортировать MP3", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить треки")
                }
            }
        }
        .task { loaded = await catalog.loadPlaylist(initialPlaylist.id) }
        .refreshable { loaded = await catalog.loadPlaylist(initialPlaylist.id) }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.mp3],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { presentedSheet = .importMetadata(url) }
            case let .failure(error):
                catalog.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .addFromLibrary:
                AddTracksToPlaylistView(playlist: playlist, onAdded: appendToDisplayedPlaylist)
            case let .importMetadata(url):
                ImportedMP3MetadataView(
                    fileURL: url,
                    playlist: playlist,
                    onImported: appendToDisplayedPlaylist
                )
            }
        }
    }

    private func appendToDisplayedPlaylist(_ track: Track) {
        guard !playlist.tracks.contains(where: { $0.id == track.id }) else { return }
        var updated = playlist
        updated.tracks.append(track)
        updated.totalTrackCount = (playlist.totalTrackCount ?? playlist.tracks.count) + 1
        loaded = updated
    }
}

private enum PlaylistSheet: Identifiable {
    case addFromLibrary
    case importMetadata(URL)

    var id: String {
        switch self {
        case .addFromLibrary: "library"
        case let .importMetadata(url): "import:\(url.absoluteString)"
        }
    }
}

private struct AddTracksToPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalog: CatalogStore
    let playlist: Playlist
    let onAdded: (Track) -> Void
    @State private var query = ""
    @State private var addedTrackIDs: Set<String>

    init(playlist: Playlist, onAdded: @escaping (Track) -> Void) {
        self.playlist = playlist
        self.onAdded = onAdded
        _addedTrackIDs = State(initialValue: Set(playlist.tracks.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List(filteredTracks) { track in
                Button {
                    Task {
                        guard await catalog.add(track, to: playlist) else { return }
                        addedTrackIDs.insert(track.id)
                        onAdded(track)
                    }
                } label: {
                    HStack(spacing: 12) {
                        ArtworkView(artwork: track.artwork, cornerRadius: 7)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).foregroundStyle(.primary).lineLimit(1)
                            Text(track.artist.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: addedTrackIDs.contains(track.id) ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(addedTrackIDs.contains(track.id))
            }
            .overlay {
                if availableTracks.isEmpty {
                    ContentUnavailableView(
                        "Нет доступных треков",
                        systemImage: "music.note.list",
                        description: Text("Добавьте музыку в медиатеку или импортируйте MP3.")
                    )
                }
            }
            .searchable(text: $query, prompt: "Название или исполнитель")
            .navigationTitle("Добавить треки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private var availableTracks: [Track] {
        guard let library = catalog.library else { return [] }
        var seen = Set<String>()
        return (library.recentlyAdded + library.liked + library.playlists.flatMap(\.tracks)).filter {
            seen.insert($0.id).inserted
        }
    }

    private var filteredTracks: [Track] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return availableTracks }
        return availableTracks.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.artist.name.localizedCaseInsensitiveContains(needle)
        }
    }
}

private struct ImportedMP3MetadataView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var downloads: DownloadsStore
    let fileURL: URL
    let playlist: Playlist
    let onImported: (Track) -> Void
    @State private var title: String
    @State private var artist = "Неизвестный исполнитель"
    @State private var album = "Без альбома"
    @State private var isImporting = false

    init(fileURL: URL, playlist: Playlist, onImported: @escaping (Track) -> Void) {
        self.fileURL = fileURL
        self.playlist = playlist
        self.onImported = onImported
        _title = State(initialValue: fileURL.deletingPathExtension().lastPathComponent)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Метаданные") {
                    TextField("Название", text: $title)
                    TextField("Исполнитель", text: $artist)
                    TextField("Альбом", text: $album)
                }
                Section {
                    LabeledContent("Файл", value: fileURL.lastPathComponent)
                } footer: {
                    Text("Файл копируется в локальное хранилище Maple Music и добавляется только в этот плейлист. На сервер Яндекса он не загружается.")
                }
            }
            .navigationTitle("Импорт MP3")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Импортировать") { importFile() }
                        .disabled(
                            isImporting
                                || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
            .overlay {
                if isImporting { ProgressView().controlSize(.large) }
            }
        }
    }

    private func importFile() {
        isImporting = true
        Task {
            let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope { fileURL.stopAccessingSecurityScopedResource() }
                isImporting = false
            }
            if let track = await catalog.importMP3(
                from: fileURL,
                title: title,
                artist: artist,
                album: album,
                into: playlist
            ) {
                await downloads.refresh()
                onImported(track)
                dismiss()
            }
        }
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
