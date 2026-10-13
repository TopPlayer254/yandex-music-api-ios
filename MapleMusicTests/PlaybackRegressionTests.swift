import Combine
import Foundation
import XCTest
@testable import MapleMusic

final class PlaybackRegressionTests: XCTestCase {
    @MainActor
    func testClockDoesNotInvalidatePlayerAndStopResetsPosition() {
        let service = AnyMusicService(DemoMusicService())
        let offline = OfflineStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let lyrics = LyricsSettings()
        let downloads = DownloadsStore(offlineStore: offline, service: service, lyricsSettings: lyrics)
        let player = PlayerStore(service: service, offlineStore: offline, downloads: downloads,
            lyricsSettings: lyrics, downloadPreferences: DownloadPreferences())
        var invalidations = 0
        let subscription = player.objectWillChange.sink { invalidations += 1 }
        player.clock.time = 82
        XCTAssertEqual(player.currentTime, 82)
        XCTAssertEqual(invalidations, 0, "A progress tick must not redraw the whole app")
        player.stop()
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.duration, 0)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testDiagnosticsRedactNestedCredentials() throws {
        let safe = DiagnosticLog.redacted([
            "error": "bad request", "access_token": "secret",
            "nested": ["email": "private@example.org", "status": 415],
            "message": "Authorization Bearer secret123"
        ])
        let data = try JSONSerialization.data(withJSONObject: safe)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("private@example.org"))
        XCTAssertTrue(text.contains("415"))
    }

    func testEnvelopeRejectsInvalidTimes() {
        let envelope = AudioEnvelope(levels: [0.2, 0.8], secondsPerBin: 0.1)
        XCTAssertEqual(envelope.level(at: .nan), 0)
        XCTAssertEqual(envelope.level(at: .infinity), 0)
        XCTAssertEqual(envelope.level(at: 100_000), 0.8, accuracy: 0.001)
    }

    func testPlaylistSnapshotsSurviveReopenAndAreAccountScoped() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineStore(root: root)
        await store.setScope("account-one")
        let track = Track(id: "track", title: "Песня", artist: Artist(id: "artist", name: "Исполнитель"), albumTitle: "Альбом", duration: 90)
        let playlist = Playlist(id: "../../playlist", name: "Офлайн", artwork: Artwork(), tracks: [track], isEditable: true)
        let library = MusicLibrary(recentlyAdded: [track], liked: [track], playlists: [playlist])
        try await store.cachePlaylist(playlist)
        try await store.cacheLibrary(library)
        let reopened = OfflineStore(root: root)
        await reopened.setScope("account-one")
        let cachedPlaylist = await reopened.cachedPlaylist(playlist.id)
        let cachedLibrary = await reopened.cachedLibrary()
        XCTAssertEqual(cachedPlaylist, playlist)
        XCTAssertEqual(cachedLibrary, library)
        await reopened.setScope("account-two")
        let otherPlaylist = await reopened.cachedPlaylist(playlist.id)
        let otherLibrary = await reopened.cachedLibrary()
        XCTAssertNil(otherPlaylist)
        XCTAssertNil(otherLibrary)
    }
}
