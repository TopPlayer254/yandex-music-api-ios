import Foundation
import MusicKit

@MainActor
@objc(KreshkaMusicKitChecks)
final class MusicKitChecks: NSObject {
    @objc(run:)
    static func run(_ completion: @escaping (NSError?) -> Void) {
        Task {
            do {
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
}
