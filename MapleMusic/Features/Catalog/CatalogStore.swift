import AVFoundation
import Foundation
import Combine

@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var home: HomeFeed?
    @Published private(set) var library: MusicLibrary?
    @Published private(set) var searchResults = MusicSearchResults()
    @Published private(set) var isLoading = false
    @Published private(set) var isSearching = false
    @Published private(set) var homeErrorMessage: String?
    @Published private(set) var libraryErrorMessage: String?
    @Published private(set) var searchErrorMessage: String?
    @Published var errorMessage: String?

    private let service: AnyMusicService
    private let offlineStore: OfflineStore
    private var searchTask: Task<Void, Never>?

    init(service: AnyMusicService, offlineStore: OfflineStore) {
        self.service = service
        self.offlineStore = offlineStore
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        async let homeLoad: Void = refreshHome()
        async let libraryLoad: Void = refreshLibrary()
        _ = await (homeLoad, libraryLoad)
        if home == nil, let library, !library.recentlyAdded.isEmpty {
            home = HomeFeed(
                greeting: "Слушать сейчас",
                featured: Array(library.recentlyAdded.prefix(5)),
                shelves: [MusicShelf(
                    id: "library-fallback",
                    title: "Из медиатеки",
                    subtitle: "Недавно добавленные треки",
                    layout: .list,
                    tracks: library.recentlyAdded
                )]
            )
            homeErrorMessage = nil
        }
    }

    func refreshHome() async {
        do {
            home = try await service.home()
            homeErrorMessage = nil
        } catch {
            guard !Self.isCancellation(error) else { return }
            homeErrorMessage = error.localizedDescription
        }
    }

    func applyWaveSettings(_ settings: WaveConfiguration) async -> Bool {
        do {
            try await service.setWaveSettings(settings)
            await refreshHome()
            return homeErrorMessage == nil
        } catch {
            guard !Self.isCancellation(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshLibrary() async {
        do {
            let fetched = try await service.library()
            library = await libraryByMergingImportedTracks(fetched)
            libraryErrorMessage = nil
        } catch {
            guard !Self.isCancellation(error) else { return }
            libraryErrorMessage = error.localizedDescription
        }
    }

    func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = MusicSearchResults()
            searchErrorMessage = nil
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let results = try await service.search(query: trimmed)
                guard !Task.isCancelled else { return }
                searchResults = results
                searchErrorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return }
                searchResults = MusicSearchResults()
                searchErrorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    func createPlaylist(named name: String) async {
        do {
            let playlist = try await service.createPlaylist(name: name)
            if var snapshot = library {
                snapshot = MusicLibrary(
                    recentlyAdded: snapshot.recentlyAdded,
                    liked: snapshot.liked,
                    playlists: snapshot.playlists + [playlist]
                )
                library = snapshot
            } else {
                await refreshLibrary()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPlaylist(_ id: String) async -> Playlist? {
        do {
            let playlist = try await service.playlist(id: id)
            return await playlistByMergingImportedTracks(playlist)
        }
        catch { errorMessage = error.localizedDescription; return nil }
    }
    func loadAlbum(_ id: String) async throws -> Album {
        try await service.album(id: id)
    }
    func loadArtist(_ id: String) async throws -> ArtistDetails {
        try await service.artist(id: id)
    }
    @discardableResult
    func add(_ track: Track, to playlist: Playlist) async -> Bool {
        do {
            if track.isLocalImport {
                try await offlineStore.addImportedTrack(track.id, toPlaylistID: playlist.id)
                await refreshPublishedLibraryImports()
            } else {
                try await service.add(trackID: track.id, toPlaylistID: playlist.id)
                await refreshLibrary()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    func remove(_ track: Track, from playlist: Playlist) async {
        do {
            if track.isLocalImport {
                try await offlineStore.removeImportedTrack(track.id, fromPlaylistID: playlist.id)
                await refreshPublishedLibraryImports()
            } else {
                try await service.remove(trackID: track.id, fromPlaylistID: playlist.id)
                await refreshLibrary()
            }
        }
        catch { errorMessage = error.localizedDescription }
    }
    func isFavorite(_ track: Track) -> Bool { library?.liked.contains { $0.id == track.id } ?? false }
    func toggleFavorite(_ track: Track) async {
        guard !track.isLocalImport else { return }
        do { try await service.setFavorite(trackID: track.id, isFavorite: !isFavorite(track)); await refreshLibrary() }
        catch { errorMessage = error.localizedDescription }
    }

    func importMP3(
        from fileURL: URL,
        title: String,
        artist: String,
        album: String,
        into playlist: Playlist
    ) async -> Track? {
        do {
            let asset = AVURLAsset(url: fileURL)
            guard try await asset.load(.isPlayable) else {
                throw MusicServiceError.message("Этот MP3 не поддерживается проигрывателем.")
            }
            let loadedDuration = try await asset.load(.duration).seconds
            let duration = loadedDuration.isFinite ? max(loadedDuration, 0) : 0
            let track = try await offlineStore.importMP3(
                from: fileURL,
                title: title,
                artistName: artist,
                albumTitle: album,
                duration: duration,
                playlistID: playlist.id
            )
            await refreshPublishedLibraryImports()
            return track
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func refreshPublishedLibraryImports() async {
        guard let library else { return }
        self.library = await libraryByMergingImportedTracks(library)
    }

    private func libraryByMergingImportedTracks(_ library: MusicLibrary) async -> MusicLibrary {
        var playlists: [Playlist] = []
        for playlist in library.playlists {
            playlists.append(await playlistByMergingImportedTracks(playlist))
        }
        return MusicLibrary(
            recentlyAdded: library.recentlyAdded,
            liked: library.liked,
            playlists: playlists
        )
    }

    private func playlistByMergingImportedTracks(_ playlist: Playlist) async -> Playlist {
        let imported = await offlineStore.importedTracks(forPlaylistID: playlist.id)
        let priorImportedCount = playlist.tracks.filter(\.isLocalImport).count
        let remoteTracks = playlist.tracks.filter { !$0.isLocalImport }
        let remoteIDs = Set(remoteTracks.map(\.id))
        let currentImports = imported.filter { !remoteIDs.contains($0.id) }
        let remoteCount = max(
            (playlist.totalTrackCount ?? playlist.tracks.count) - priorImportedCount,
            remoteTracks.count
        )
        var merged = playlist
        merged.tracks = remoteTracks + currentImports
        merged.totalTrackCount = remoteCount + currentImports.count
        return merged
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
