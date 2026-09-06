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
    private var searchTask: Task<Void, Never>?

    init(service: AnyMusicService) {
        self.service = service
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

    func refreshLibrary() async {
        do {
            library = try await service.library()
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
        do { return try await service.playlist(id: id) }
        catch { errorMessage = error.localizedDescription; return nil }
    }
    func loadAlbum(_ id: String) async throws -> Album {
        try await service.album(id: id)
    }
    func loadArtist(_ id: String) async throws -> ArtistDetails {
        try await service.artist(id: id)
    }
    func add(_ track: Track, to playlist: Playlist) async {
        do { try await service.add(trackID: track.id, toPlaylistID: playlist.id); await refreshLibrary() }
        catch { errorMessage = error.localizedDescription }
    }
    func remove(_ track: Track, from playlist: Playlist) async {
        do { try await service.remove(trackID: track.id, fromPlaylistID: playlist.id); await refreshLibrary() }
        catch { errorMessage = error.localizedDescription }
    }
    func isFavorite(_ track: Track) -> Bool { library?.liked.contains { $0.id == track.id } ?? false }
    func toggleFavorite(_ track: Track) async {
        do { try await service.setFavorite(trackID: track.id, isFavorite: !isFavorite(track)); await refreshLibrary() }
        catch { errorMessage = error.localizedDescription }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
