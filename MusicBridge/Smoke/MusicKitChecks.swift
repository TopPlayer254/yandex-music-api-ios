import Foundation
import MusicKit

@MainActor
@objc(KreshkaMusicKitChecks)
final class MusicKitChecks: NSObject {
    private static var autoupdatingResponses: [AnyObject] = []
    @objc(run:)
    static func run(_ completion: @escaping (NSError?) -> Void) {
        Task {
            do {
                guard await MusicAuthorization.request() == .authorized else {
                    throw failure("Genuine MusicKit authorization was not granted")
                }
                NSLog("KRESHKA_GENUINE_MUSICKIT_AUTHORIZATION_PASSED")
                // This is the actual private getter on the device crash path,
                // rather than only the public request/response conversion.
                try verifyAutoupdating(MusicLibraryRequest<MusicKit.Song>())
                try verifyAutoupdating(MusicLibraryRequest<MusicKit.Playlist>())
                NSLog("KRESHKA_NATIVE_AUTOUPDATING_INITIALIZATION_PASSED")
                let songs = try await MusicLibraryRequest<MusicKit.Song>().response()
                guard !songs.items.isEmpty else { throw failure("MusicKit dropped every song") }
                for song in songs.items {
                    guard !song.id.rawValue.isEmpty, !song.title.isEmpty else { throw failure("Invalid MusicKit song") }
                }
                let artists = try await MusicLibraryRequest<MusicKit.Artist>().response()
                guard !artists.items.isEmpty else { throw failure("MusicKit dropped every artist") }
                for artist in artists.items {
                    guard !artist.id.rawValue.isEmpty, !artist.name.isEmpty else { throw failure("Invalid MusicKit artist") }
                }
                let albums = try await MusicLibraryRequest<MusicKit.Album>().response()
                guard !albums.items.isEmpty else { throw failure("MusicKit dropped every album") }
                for album in albums.items {
                    guard !album.id.rawValue.isEmpty, !album.title.isEmpty else { throw failure("Invalid MusicKit album") }
                }
                let playlists = try await MusicLibraryRequest<MusicKit.Playlist>().response()
                guard !playlists.items.isEmpty else { throw failure("MusicKit dropped every playlist") }
                for playlist in playlists.items {
                    guard !playlist.id.rawValue.isEmpty, !playlist.name.isEmpty else { throw failure("Invalid MusicKit playlist") }
                }
                NSLog("KRESHKA_PUBLIC_MUSICKIT_LIBRARY_PASSED songs=%ld playlists=%ld", songs.items.count, playlists.items.count)
                completion(nil)
            } catch {
                NSLog("KRESHKA_PUBLIC_MUSICKIT_LIBRARY_FAILED %@", error.localizedDescription)
                completion(error as NSError)
            }
        }
    }

    private static func failure(_ reason: String) -> NSError {
        NSError(domain: "KreshkaMusicKitCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
    }

    private static func verifyAutoupdating<Request>(_ value: Request) throws {
        var request = value
        let metadata = unsafeBitCast(Request.self, to: UnsafeRawPointer.self)
        guard let pointer = withUnsafePointer(to: &request, {
            KreshkaMakeAutoupdatingResponse($0, metadata)
        }) else { throw failure("Native MusicKit autoupdating ABI unavailable") }
        autoupdatingResponses.append(Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue())
    }
}
