import Foundation
import XCTest
@testable import MapleMusic

final class OfflineStoreTests: XCTestCase {
    func testCopiesAndRemovesLicensedLocalAsset() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: source)

        let store = OfflineStore(root: root.appendingPathComponent("offline", isDirectory: true))
        let artist = Artist(id: "artist", name: "Artist")
        let track = Track(id: "track/with unsafe path", title: "Track", artist: artist, albumTitle: "Album", duration: 10)
        let asset = PlaybackAsset(
            url: source,
            quality: .lossless,
            codec: "PCM",
            bitDepth: 16,
            sampleRate: 44_100,
            expiresAt: nil,
            allowsOfflineDownload: true
        )

        let entry = try await store.save(track: track, asset: asset)
        XCTAssertFalse(entry.relativePath.contains("/"))
        let containsAfterSave = await store.contains(trackID: track.id)
        let localAsset = await store.localAsset(for: track)
        XCTAssertTrue(containsAfterSave)
        XCTAssertNotNil(localAsset)

        let reopened = OfflineStore(root: root.appendingPathComponent("offline", isDirectory: true))
        let restored = await reopened.entries()
        XCTAssertEqual(restored.first?.track, track)

        let userFile = root.appendingPathComponent("offline/notes.txt")
        try Data("keep".utf8).write(to: userFile)
        try await reopened.removeAll()
        let entriesAfterClear = await reopened.entries()
        let containsAfterClear = await reopened.contains(trackID: track.id)
        XCTAssertTrue(entriesAfterClear.isEmpty)
        XCTAssertFalse(containsAfterClear)
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))

        await store.setScope("another-account")
        let otherAccountAsset = await store.localAsset(for: track)
        XCTAssertNil(otherAccountAsset)
    }

    func testRejectsAssetWithoutDownloadPermission() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineStore(root: root)
        let track = Track(
            id: "locked",
            title: "Locked",
            artist: Artist(id: "artist", name: "Artist"),
            albumTitle: "Album",
            duration: 10,
            downloadAllowed: false
        )
        let asset = PlaybackAsset(
            url: root.appendingPathComponent("missing.wav"),
            quality: .high,
            codec: "AAC",
            bitDepth: nil,
            sampleRate: nil,
            expiresAt: nil,
            allowsOfflineDownload: false
        )
        do {
            try await store.save(track: track, asset: asset)
            XCTFail("Expected offline permission failure")
        } catch let error as MusicServiceError {
            XCTAssertEqual(error, .offlineUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testImportsMP3WithMetadataAndPersistsPlaylistMembership() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.mp3")
        try Data([0x49, 0x44, 0x33, 0x04]).write(to: source)
        let offlineRoot = root.appendingPathComponent("offline", isDirectory: true)
        let store = OfflineStore(root: offlineRoot)

        let track = try await store.importMP3(
            from: source,
            title: "Custom title",
            artistName: "Custom artist",
            albumTitle: "Custom album",
            duration: 42,
            playlistID: "owner:playlist"
        )
        XCTAssertTrue(track.isLocalImport)
        XCTAssertEqual(track.title, "Custom title")
        XCTAssertEqual(track.artist.name, "Custom artist")
        XCTAssertEqual(track.albumTitle, "Custom album")

        let reopened = OfflineStore(root: offlineRoot)
        let imported = await reopened.importedTracks(forPlaylistID: "owner:playlist")
        XCTAssertEqual(imported, [track])
        let asset = await reopened.localAsset(for: track)
        XCTAssertEqual(asset?.codec, "mp3")
        XCTAssertTrue(asset?.url.isFileURL == true)

        try await reopened.addImportedTrack(track.id, toPlaylistID: "owner:other")
        let copiedMembership = await reopened.importedTracks(forPlaylistID: "owner:other")
        XCTAssertEqual(copiedMembership, [track])
        try await reopened.removeImportedTrack(track.id, fromPlaylistID: "owner:playlist")
        let removedMembership = await reopened.importedTracks(forPlaylistID: "owner:playlist")
        XCTAssertTrue(removedMembership.isEmpty)
    }
}
