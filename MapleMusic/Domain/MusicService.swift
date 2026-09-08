import Foundation

protocol MusicService: Sendable {
    func home() async throws -> HomeFeed
    func setWaveSettings(_ settings: WaveConfiguration) async throws
    func search(query: String) async throws -> MusicSearchResults
    func album(id: String) async throws -> Album
    func artist(id: String) async throws -> ArtistDetails
    func library() async throws -> MusicLibrary
    func playlist(id: String) async throws -> Playlist
    func createPlaylist(name: String) async throws -> Playlist
    func add(trackID: String, toPlaylistID playlistID: String) async throws
    func remove(trackID: String, fromPlaylistID playlistID: String) async throws
    func setFavorite(trackID: String, isFavorite: Bool) async throws
    func playbackAsset(for track: Track, quality: AudioQuality) async throws -> PlaybackAsset
    func lyrics(for track: Track) async throws -> Lyrics?
}

struct AnyMusicService: MusicService {
    private let _home: @Sendable () async throws -> HomeFeed
    private let _setWaveSettings: @Sendable (WaveConfiguration) async throws -> Void
    private let _search: @Sendable (String) async throws -> MusicSearchResults
    private let _album: @Sendable (String) async throws -> Album
    private let _artist: @Sendable (String) async throws -> ArtistDetails
    private let _library: @Sendable () async throws -> MusicLibrary
    private let _playlist: @Sendable (String) async throws -> Playlist
    private let _createPlaylist: @Sendable (String) async throws -> Playlist
    private let _add: @Sendable (String, String) async throws -> Void
    private let _remove: @Sendable (String, String) async throws -> Void
    private let _setFavorite: @Sendable (String, Bool) async throws -> Void
    private let _playback: @Sendable (Track, AudioQuality) async throws -> PlaybackAsset
    private let _lyrics: @Sendable (Track) async throws -> Lyrics?

    init<Service: MusicService>(_ service: Service) {
        _home = service.home
        _setWaveSettings = service.setWaveSettings
        _search = service.search
        _album = service.album
        _artist = service.artist
        _library = service.library
        _playlist = service.playlist
        _createPlaylist = service.createPlaylist
        _add = service.add
        _remove = service.remove
        _setFavorite = service.setFavorite
        _playback = service.playbackAsset
        _lyrics = service.lyrics
    }

    func home() async throws -> HomeFeed { try await _home() }
    func setWaveSettings(_ settings: WaveConfiguration) async throws { try await _setWaveSettings(settings) }
    func search(query: String) async throws -> MusicSearchResults { try await _search(query) }
    func album(id: String) async throws -> Album { try await _album(id) }
    func artist(id: String) async throws -> ArtistDetails { try await _artist(id) }
    func library() async throws -> MusicLibrary { try await _library() }
    func playlist(id: String) async throws -> Playlist { try await _playlist(id) }
    func createPlaylist(name: String) async throws -> Playlist { try await _createPlaylist(name) }
    func add(trackID: String, toPlaylistID playlistID: String) async throws { try await _add(trackID, playlistID) }
    func remove(trackID: String, fromPlaylistID playlistID: String) async throws { try await _remove(trackID, playlistID) }
    func setFavorite(trackID: String, isFavorite: Bool) async throws { try await _setFavorite(trackID, isFavorite) }
    func playbackAsset(for track: Track, quality: AudioQuality) async throws -> PlaybackAsset { try await _playback(track, quality) }
    func lyrics(for track: Track) async throws -> Lyrics? { try await _lyrics(track) }
}
