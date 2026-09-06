import SwiftUI

struct ArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: artist.artwork ?? Artwork(), cornerRadius: 28)
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            Text(artist.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
        }
    }
}

struct AlbumRow: View {
    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: album.artwork, cornerRadius: 7)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(album.title).lineLimit(1)
                Text(albumSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var albumSubtitle: String {
        var values = [album.artistNames]
        if let year = album.year { values.append(String(year)) }
        return values.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct AlbumDetailView: View {
    @EnvironmentObject private var appearance: AppearanceSettings
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var downloads: DownloadsStore
    private let initialAlbum: Album
    @State private var loadedAlbum: Album?
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(album: Album) {
        initialAlbum = album
    }

    private var album: Album { loadedAlbum ?? initialAlbum }

    var body: some View {
        List {
            Section {
                albumHeader
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
            }

            if isLoading && album.tracks.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Загрузка альбома…")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else if let errorMessage, album.tracks.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Не удалось загрузить альбом", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Повторить") { Task { await load() } }
                    }
                }
            }

            if !album.tracks.isEmpty {
                Section("Треки") {
                    ForEach(album.tracks) { track in
                        TrackRow(
                            track: track,
                            isDownloaded: downloads.isDownloaded(track),
                            isDownloading: downloads.activeTrackIDs.contains(track.id),
                            play: { Task { await player.play(track, queue: album.tracks) } },
                            toggleDownload: {
                                Task {
                                    if downloads.isDownloaded(track) { await downloads.remove(track) }
                                    else { await downloads.download(track, quality: player.preferredQuality) }
                                }
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: initialAlbum.id) { await load() }
        .refreshable { await load() }
    }

    private var albumHeader: some View {
        VStack(spacing: 14) {
            ArtworkView(artwork: album.artwork, cornerRadius: 16)
                .frame(maxWidth: 260)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.16), radius: 12, y: 6)

            VStack(spacing: 5) {
                Text(album.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if let artist = album.artists.first {
                    NavigationLink {
                        ArtistDetailView(artist: artist)
                    } label: {
                        Text(album.artistNames)
                            .font(.headline)
                            .foregroundStyle(appearance.tint)
                    }
                    .buttonStyle(.plain)
                }
                Text(albumMetadata)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    guard let first = album.tracks.first else { return }
                    Task { await player.play(first, queue: album.tracks) }
                } label: {
                    Label("Воспроизвести", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                }
                .tint(appearance.tint)
                .adaptiveProminentButtonStyle()
                .disabled(album.tracks.isEmpty)

                Button {
                    Task { await downloads.downloadAll(album.tracks, quality: player.preferredQuality) }
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
                .disabled(downloadButtonDisabled)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var albumMetadata: String {
        var values: [String] = []
        if let year = album.year { values.append(String(year)) }
        if let genre = album.genre, !genre.isEmpty { values.append(genre.capitalized) }
        values.append(album.trackCount.russianTrackCount)
        return values.joined(separator: " · ")
    }

    private var downloadButtonDisabled: Bool {
        let downloadable = album.tracks.filter(\.downloadAllowed)
        return downloadable.isEmpty
            || downloads.bulkProgress != nil
            || downloadable.allSatisfy(downloads.isDownloaded)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            loadedAlbum = try await catalog.loadAlbum(initialAlbum.id)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var downloads: DownloadsStore
    private let initialArtist: Artist
    @State private var details: ArtistDetails?
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(artist: Artist) {
        initialArtist = artist
    }

    private var artist: Artist { details?.artist ?? initialArtist }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    ArtworkView(artwork: artist.artwork ?? Artwork(), cornerRadius: 100)
                        .frame(width: 190, height: 190)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
                    Text(artist.name)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .padding(.vertical, 8)
            }

            if isLoading && details == nil {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Загрузка исполнителя…")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else if let errorMessage, details == nil {
                Section {
                    ContentUnavailableView {
                        Label("Не удалось загрузить исполнителя", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Повторить") { Task { await load() } }
                    }
                }
            }

            if let tracks = details?.tracks, !tracks.isEmpty {
                Section("Популярные треки") {
                    ForEach(tracks.prefix(12)) { track in
                        TrackRow(
                            track: track,
                            isDownloaded: downloads.isDownloaded(track),
                            isDownloading: downloads.activeTrackIDs.contains(track.id),
                            play: { Task { await player.play(track, queue: tracks) } },
                            toggleDownload: {
                                Task {
                                    if downloads.isDownloaded(track) { await downloads.remove(track) }
                                    else { await downloads.download(track, quality: player.preferredQuality) }
                                }
                            }
                        )
                    }
                }
            }

            if let albums = details?.albums, !albums.isEmpty {
                Section("Альбомы") {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            AlbumRow(album: album)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: initialArtist.id) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            details = try await catalog.loadArtist(initialArtist.id)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
