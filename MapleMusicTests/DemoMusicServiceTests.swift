import XCTest
@testable import MapleMusic

final class DemoMusicServiceTests: XCTestCase {
    func testDemoServiceSupportsCoreFlows() async throws {
        let service = DemoMusicService()
        let home = try await service.home()
        XCTAssertFalse(home.featured.isEmpty)

        let results = try await service.search(query: "Northern")
        XCTAssertEqual(results.tracks.first?.id, "northern-lights")

        let albumResults = try await service.search(query: "Afterglow")
        let album = try await service.album(id: try XCTUnwrap(albumResults.albums.first?.id))
        XCTAssertEqual(album.tracks.count, 2)

        let artistResults = try await service.search(query: "Maple Sessions")
        let artist = try await service.artist(id: try XCTUnwrap(artistResults.artists.first?.id))
        XCTAssertEqual(artist.albums.count, 2)
        XCTAssertEqual(artist.tracks.count, 4)

        let library = try await service.library()
        XCTAssertFalse(library.playlists.isEmpty)

        let lyrics = try await service.lyrics(for: home.featured[0])
        XCTAssertFalse(lyrics?.lines.isEmpty ?? true)
    }
}
