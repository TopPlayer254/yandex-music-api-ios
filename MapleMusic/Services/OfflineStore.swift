import CryptoKit
import Foundation

struct OfflineEntry: Codable, Hashable, Identifiable, Sendable {
    var id: String { trackID }
    let trackID: String
    let relativePath: String
    let quality: AudioQuality
    let codec: String
    let bitDepth: Int?
    let sampleRate: Int?
    let byteCount: Int64
    let savedAt: Date
    var track: Track? = nil
    var lyrics: Lyrics? = nil
}

actor OfflineStore {
    private struct Manifest: Codable {
        var entries: [String: OfflineEntry] = [:]
    }

    private struct ImportedPlaylists: Codable {
        var trackIDsByPlaylist: [String: [String]] = [:]
    }

    private let baseRoot: URL
    private var root: URL
    private var manifestURL: URL
    private var manifest: Manifest
    private var importedPlaylistsURL: URL
    private var importedPlaylists: ImportedPlaylists

    init(root: URL? = nil) {
        let resolvedRoot: URL
        if let root {
            resolvedRoot = root
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            resolvedRoot = documents
                .appendingPathComponent("Maple Music", isDirectory: true)
                .appendingPathComponent("Загрузки", isDirectory: true)
            Self.migrateLegacyRootIfNeeded(to: resolvedRoot)
        }
        self.root = resolvedRoot
        self.baseRoot = resolvedRoot
        manifestURL = resolvedRoot.appendingPathComponent("manifest.json")
        importedPlaylistsURL = resolvedRoot.appendingPathComponent("imported-playlists.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        manifest = (try? Data(contentsOf: manifestURL)).flatMap { try? decoder.decode(Manifest.self, from: $0) } ?? Manifest()
        importedPlaylists = (try? Data(contentsOf: importedPlaylistsURL))
            .flatMap { try? decoder.decode(ImportedPlaylists.self, from: $0) } ?? ImportedPlaylists()
    }

    func setScope(_ scope: String) {
        root = baseRoot.appendingPathComponent(safeFileName(scope), isDirectory: true)
        manifestURL = root.appendingPathComponent("manifest.json")
        importedPlaylistsURL = root.appendingPathComponent("imported-playlists.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        manifest = (try? Data(contentsOf: manifestURL)).flatMap { try? decoder.decode(Manifest.self, from: $0) } ?? Manifest()
        importedPlaylists = (try? Data(contentsOf: importedPlaylistsURL))
            .flatMap { try? decoder.decode(ImportedPlaylists.self, from: $0) } ?? ImportedPlaylists()
    }

    func localLyrics(for trackID: String) -> Lyrics? { manifest.entries[trackID]?.lyrics }

    func entries() -> [OfflineEntry] {
        manifest.entries.values.filter { contains(trackID: $0.trackID) }.sorted { $0.savedAt > $1.savedAt }
    }

    func contains(trackID: String) -> Bool {
        guard let entry = manifest.entries[trackID] else { return false }
        let url = root.appendingPathComponent(entry.relativePath)
        return isInsideRoot(url) && FileManager.default.fileExists(atPath: url.path)
    }

    func localAsset(for track: Track) -> PlaybackAsset? {
        guard let entry = manifest.entries[track.id] else { return nil }
        let url = root.appendingPathComponent(entry.relativePath)
        guard isInsideRoot(url), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return PlaybackAsset(
            url: url,
            quality: entry.quality,
            codec: entry.codec,
            bitDepth: entry.bitDepth,
            sampleRate: entry.sampleRate,
            expiresAt: nil,
            allowsOfflineDownload: true
        )
    }

    func importedTracks(forPlaylistID playlistID: String) -> [Track] {
        (importedPlaylists.trackIDsByPlaylist[playlistID] ?? []).compactMap { trackID in
            guard contains(trackID: trackID) else { return nil }
            return manifest.entries[trackID]?.track
        }
    }

    @discardableResult
    func importMP3(
        from source: URL,
        title: String,
        artistName: String,
        albumTitle: String,
        duration: TimeInterval,
        playlistID: String
    ) throws -> Track {
        guard source.isFileURL, source.pathExtension.lowercased() == "mp3" else {
            throw MusicServiceError.message("Выберите файл MP3.")
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = albumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanArtist.isEmpty else {
            throw MusicServiceError.message("Укажите название и исполнителя.")
        }

        try ensureRoot()
        let trackID = "local:\(UUID().uuidString)"
        let track = Track(
            id: trackID,
            title: cleanTitle,
            artist: Artist(id: "local-artist:\(UUID().uuidString)", name: cleanArtist),
            albumTitle: cleanAlbum,
            duration: max(duration, 0),
            artwork: Artwork(colors: ["FFCC00", "FF375F"]),
            downloadAllowed: true,
            availableQualities: [.high]
        )
        let relativePath = visibleFileName(for: track, extension: "mp3")
        let destination = root.appendingPathComponent(relativePath)
        guard isInsideRoot(destination) else { throw MusicServiceError.offlineUnavailable }
        let temporary = root.appendingPathComponent(".\(UUID().uuidString).import")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: source, to: temporary)
        try FileManager.default.moveItem(at: temporary, to: destination)

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDestination = destination
        try? mutableDestination.setResourceValues(resourceValues)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        let entry = OfflineEntry(
            trackID: trackID,
            relativePath: relativePath,
            quality: .high,
            codec: "mp3",
            bitDepth: nil,
            sampleRate: nil,
            byteCount: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            savedAt: Date(),
            track: track
        )

        let previousManifest = manifest
        let previousImportedPlaylists = importedPlaylists
        manifest.entries[trackID] = entry
        importedPlaylists.trackIDsByPlaylist[playlistID, default: []].append(trackID)
        do {
            try persistManifest()
            try persistImportedPlaylists()
        } catch {
            manifest = previousManifest
            importedPlaylists = previousImportedPlaylists
            try? FileManager.default.removeItem(at: destination)
            try? persistManifest()
            try? persistImportedPlaylists()
            throw error
        }
        return track
    }

    func addImportedTrack(_ trackID: String, toPlaylistID playlistID: String) throws {
        guard trackID.hasPrefix("local:"), contains(trackID: trackID) else {
            throw MusicServiceError.offlineUnavailable
        }
        var trackIDs = importedPlaylists.trackIDsByPlaylist[playlistID, default: []]
        guard !trackIDs.contains(trackID) else { return }
        trackIDs.append(trackID)
        importedPlaylists.trackIDsByPlaylist[playlistID] = trackIDs
        try persistImportedPlaylists()
    }

    func removeImportedTrack(_ trackID: String, fromPlaylistID playlistID: String) throws {
        importedPlaylists.trackIDsByPlaylist[playlistID]?.removeAll { $0 == trackID }
        try persistImportedPlaylists()
    }

    @discardableResult
    func save(track: Track, asset: PlaybackAsset, lyrics: Lyrics? = nil) async throws -> OfflineEntry {
        guard track.downloadAllowed, asset.allowsOfflineDownload else {
            throw MusicServiceError.offlineUnavailable
        }
        try ensureRoot()
        let activeRoot = root
        let ext = MediaFileLoader.fileExtension(for: asset)
        let relativePath = visibleFileName(for: track, extension: ext)
        let destination = root.appendingPathComponent(relativePath)
        guard isInsideRoot(destination) else { throw MusicServiceError.offlineUnavailable }

        let temporary = root.appendingPathComponent(".\(UUID().uuidString).download")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await MediaFileLoader.download(asset, to: temporary)
        guard root == activeRoot else { throw CancellationError() }
        try FileManager.default.moveItem(at: temporary, to: destination)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDestination = destination
        try? mutableDestination.setResourceValues(resourceValues)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let entry = OfflineEntry(
            trackID: track.id,
            relativePath: relativePath,
            quality: asset.quality,
            codec: asset.codec,
            bitDepth: asset.bitDepth,
            sampleRate: asset.sampleRate,
            byteCount: byteCount,
            savedAt: Date(), track: track, lyrics: lyrics
        )
        let previous = manifest.entries[track.id]
        manifest.entries[track.id] = entry
        do { try persistManifest() }
        catch {
            manifest.entries[track.id] = previous
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        if let previous {
            let old = root.appendingPathComponent(previous.relativePath)
            if isInsideRoot(old) { try? FileManager.default.removeItem(at: old) }
        }
        return entry
    }

    func remove(trackID: String) throws {
        let entry = manifest.entries.removeValue(forKey: trackID)
        for playlistID in Array(importedPlaylists.trackIDsByPlaylist.keys) {
            importedPlaylists.trackIDsByPlaylist[playlistID]?.removeAll { $0 == trackID }
        }
        guard let entry else {
            try persistImportedPlaylists()
            return
        }
        let target = root.appendingPathComponent(entry.relativePath)
        guard isInsideRoot(target) else { throw MusicServiceError.offlineUnavailable }
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try persistManifest()
        try persistImportedPlaylists()
    }

    func removeAll() throws {
        for entry in manifest.entries.values {
            let target = root.appendingPathComponent(entry.relativePath)
            guard isInsideRoot(target) else { throw MusicServiceError.offlineUnavailable }
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        }
        manifest.entries.removeAll()
        importedPlaylists.trackIDsByPlaylist.removeAll()
        try persistManifest()
        try persistImportedPlaylists()
    }

    private func ensureRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableRoot = root
        try? mutableRoot.setResourceValues(resourceValues)
    }

    private func persistManifest() throws {
        try ensureRoot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private func persistImportedPlaylists() throws {
        try ensureRoot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(importedPlaylists).write(to: importedPlaylistsURL, options: .atomic)
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = root.standardizedFileURL.pathComponents
        let targetPath = url.standardizedFileURL.pathComponents
        return targetPath.starts(with: rootPath)
    }

    private func safeFileName(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func visibleFileName(for track: Track, extension ext: String) -> String {
        let source = "\(track.artist.name) – \(track.title)"
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = source.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = String((cleaned.isEmpty ? "Трек" : cleaned).prefix(96))
        return "\(stem)-\(safeFileName(track.id).prefix(8))-\(UUID().uuidString.prefix(6)).\(ext)"
    }

    private static func migrateLegacyRootIfNeeded(to destination: URL) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path),
              let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let legacy = support.appendingPathComponent("Offline", isDirectory: true)
        guard manager.fileExists(atPath: legacy.path) else { return }
        do {
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.moveItem(at: legacy, to: destination)
        } catch {
            // The old location remains intact; a later launch can retry.
        }
    }
}
