import Foundation
import XCTest
@testable import MapleMusic

final class UploadAndAccountTests: XCTestCase {
    func testUploadedTrackUsesServerIDAndUGCArtist() throws {
        let json = #"{"id":"ugc-123","title":"Own song","ugcArtistName":"Own artist","filename":"own.mp3","albums":[{"id":42,"title":"Uploads"}],"available":true}"#
        let track = try XCTUnwrap(JSONDecoder().decode(YandexJSON.self, from: Data(json.utf8)).track())
        XCTAssertEqual(track.id, "ugc-123")
        XCTAssertEqual(track.artist.name, "Own artist")
        XCTAssertEqual(track.isCloudUpload, true)
        XCTAssertEqual(track.availableQualities, [.high])
    }

    func testMP3TargetAcceptsOnlyHTTPSYandexDomains() {
        XCTAssertTrue(YandexUpload.isTrustedTarget(URL(string: "https://music-loader.yandex.net/upload")!))
        for target in ["http://music-loader.yandex.net/upload", "https://yandex.net.example.org/upload",
                       "https://example.org/upload", "https://user@yandex.net/upload", "https://yandex.net:8443/upload"] {
            XCTAssertFalse(YandexUpload.isTrustedTarget(URL(string: target)!))
        }
    }

    func testAccountSlotsSeparateCredentialsWithoutChangingExistingDownloadNamespace() throws {
        let oldJSON = #"{"kind":"yandex","endpoint":"https://api.music.yandex.net","streamAPI":"automatic"}"#
        let existing = try JSONDecoder().decode(ProviderConfiguration.self, from: Data(oldJSON.utf8))
        var second = existing
        second.accountSlot = "account-2"
        XCTAssertEqual(existing.credentialID, existing.credentialNamespace)
        XCTAssertEqual(second.credentialNamespace, existing.credentialNamespace)
        XCTAssertNotEqual(second.credentialID, existing.credentialID)
    }
}
