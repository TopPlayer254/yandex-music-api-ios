import Foundation

enum AudioQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case high
    case lossless

    var id: Self { self }

    // Automatic remains decodable for existing manifests and gateway responses,
    // but the UI presents the two choices that have distinct user meaning.
    static var selectableCases: [AudioQuality] { [.high, .lossless] }

    var title: String {
        switch self {
        case .automatic, .high: "Стандартное"
        case .lossless: "Lossless (Яндекс Плюс)"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic, .high: "Обычное качество веб-плеера, доступное без Плюса"
        case .lossless: "FLAC, если качество доступно аккаунту"
        }
    }
}

enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case all
    case one
}

struct Artist: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let artwork: Artwork?

    init(id: String, name: String, artwork: Artwork? = nil) {
        self.id = id
        self.name = name
        self.artwork = artwork
    }
}

struct Artwork: Codable, Hashable, Sendable {
    let url: URL?
    let colors: [String]

    init(url: URL? = nil, colors: [String] = []) {
        self.url = url
        self.colors = colors
    }
}

struct Track: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let artist: Artist
    let albumID: String?
    let albumTitle: String
    let duration: TimeInterval
    let artwork: Artwork
    let isExplicit: Bool
    let downloadAllowed: Bool
    let availableQualities: Set<AudioQuality>

    init(
        id: String,
        title: String,
        artist: Artist,
        albumID: String? = nil,
        albumTitle: String,
        duration: TimeInterval,
        artwork: Artwork = Artwork(),
        isExplicit: Bool = false,
        downloadAllowed: Bool = true,
        availableQualities: Set<AudioQuality> = [.automatic, .high]
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.duration = duration
        self.artwork = artwork
        self.isExplicit = isExplicit
        self.downloadAllowed = downloadAllowed
        self.availableQualities = availableQualities
    }
}

struct Album: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let artists: [Artist]
    let artwork: Artwork
    let year: Int?
    let genre: String?
    let tracks: [Track]
    let trackCount: Int

    var artistNames: String {
        artists.map(\.name).joined(separator: ", ")
    }
}

struct ArtistDetails: Codable, Hashable, Sendable {
    let artist: Artist
    let tracks: [Track]
    let albums: [Album]
}

struct MusicSearchResults: Codable, Hashable, Sendable {
    let tracks: [Track]
    let albums: [Album]
    let artists: [Artist]

    init(tracks: [Track] = [], albums: [Album] = [], artists: [Artist] = []) {
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
    }

    var isEmpty: Bool {
        tracks.isEmpty && albums.isEmpty && artists.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case tracks, albums, artists
    }

    init(from decoder: Decoder) throws {
        if let legacyTracks = try? decoder.singleValueContainer().decode([Track].self) {
            self.init(tracks: legacyTracks)
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            tracks: try values.decodeIfPresent([Track].self, forKey: .tracks) ?? [],
            albums: try values.decodeIfPresent([Album].self, forKey: .albums) ?? [],
            artists: try values.decodeIfPresent([Artist].self, forKey: .artists) ?? []
        )
    }
}

struct Playlist: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var description: String?
    var artwork: Artwork
    var tracks: [Track]
    var isEditable: Bool
    var totalTrackCount: Int? = nil
}

struct MusicShelf: Codable, Hashable, Identifiable, Sendable {
    enum Layout: String, Codable, Sendable {
        case cards
        case list
    }

    let id: String
    let title: String
    let subtitle: String?
    let layout: Layout
    let tracks: [Track]
}

struct HomeFeed: Codable, Hashable, Sendable {
    let greeting: String
    let featured: [Track]
    let shelves: [MusicShelf]
}

struct MusicLibrary: Codable, Hashable, Sendable {
    let recentlyAdded: [Track]
    let liked: [Track]
    let playlists: [Playlist]
}

struct PlaybackAsset: Codable, Hashable, Sendable {
    let url: URL
    let quality: AudioQuality
    let codec: String
    let bitDepth: Int?
    let sampleRate: Int?
    let expiresAt: Date?
    let allowsOfflineDownload: Bool
    var decryptionKey: String? = nil
    var transport: String? = nil
}

struct LyricsLine: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let time: TimeInterval
    let text: String

    init(id: UUID = UUID(), time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

struct Lyrics: Codable, Hashable, Sendable {
    let trackID: String
    let writers: String?
    let lines: [LyricsLine]
    let isSynchronized: Bool
    let source: String?

    init(
        trackID: String,
        writers: String?,
        lines: [LyricsLine],
        isSynchronized: Bool = true,
        source: String? = nil
    ) {
        self.trackID = trackID
        self.writers = writers
        self.lines = lines
        self.isSynchronized = isSynchronized
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case trackID, writers, lines, isSynchronized, source
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        trackID = try values.decode(String.self, forKey: .trackID)
        writers = try values.decodeIfPresent(String.self, forKey: .writers)
        lines = try values.decode([LyricsLine].self, forKey: .lines)
        isSynchronized = try values.decodeIfPresent(Bool.self, forKey: .isSynchronized) ?? true
        source = try values.decodeIfPresent(String.self, forKey: .source)
    }
}

struct UserProfile: Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let avatarURL: URL?
}

enum MusicServiceError: LocalizedError, Equatable {
    case notConfigured
    case unauthorized
    case forbidden
    case invalidResponse
    case http(Int)
    case offlineUnavailable
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Музыкальный сервис не настроен."
        case .unauthorized: "Войдите в аккаунт, чтобы продолжить."
        case .forbidden: "Аккаунту недоступно воспроизведение этого трека."
        case .invalidResponse: "Музыкальный сервис вернул некорректный ответ."
        case let .http(status): "Музыкальный сервис вернул ошибку HTTP \(status)."
        case .offlineUnavailable: "Этот трек недоступен для офлайн-воспроизведения."
        case let .message(message): message
        }
    }
}
