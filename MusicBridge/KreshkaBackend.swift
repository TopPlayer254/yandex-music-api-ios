import Combine
import Foundation
import SwiftUI
import UIKit

/// Objective-C boundary used by the original application's model adapters.
/// The service, credentials, downloads and player are the existing Maple code.
@MainActor
@objc(KreshkaBackend)
final class KreshkaBackend: NSObject {
    private static let instance = KreshkaBackend()
    private let settings = ProviderSettings()
    private let appearance = AppearanceSettings()
    private let developer = DeveloperSettings()
    private var container: AppContainer!
    private var observations = Set<AnyCancellable>()
    private var containerObservations = Set<AnyCancellable>()
    private var tracks: [String: Track] = [:]
    private var bootstrapTask: Task<Void, Never>?

    @objc static func sharedInstance() -> KreshkaBackend { instance }

    override private init() {
        super.init()
        rebuild()
        settings.$generation.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }.store(in: &observations)
    }

    private func rebuild() {
        bootstrapTask?.cancel()
        container?.player.stop()
        containerObservations.removeAll()
        container = AppContainer(configuration: settings.configuration)
        let current = container!
        current.player.$currentTrack.combineLatest(current.player.$isPlaying)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self, self.container === current else { return }
                NotificationCenter.default.post(name: .init("KreshkaPlaybackChanged"), object: self)
            }.store(in: &containerObservations)
        current.auth.$state.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, self.container === current else { return }
            NotificationCenter.default.post(name: .init("KreshkaCatalogChanged"), object: self)
        }.store(in: &containerObservations)
        bootstrapTask = Task { [weak self] in
            await current.bootstrap()
            guard !Task.isCancelled, let self, self.container === current else { return }
            self.remember(current.catalog.library?.liked ?? [])
            NotificationCenter.default.post(name: .init("KreshkaCatalogChanged"), object: self)
        }
    }

    @objc var snapshot: NSDictionary {
        var result: [String: Any] = [
            "playing": container.player.isPlaying,
            "time": container.player.currentTime,
            "duration": container.player.duration,
            "provider": settings.configuration.kind.rawValue,
            "signedIn": signedIn,
            "queue": encode(container.player.queue) ?? [],
        ]
        if let track = container.player.currentTrack { result["track"] = encode(track) }
        if let lyrics = container.player.lyrics { result["lyrics"] = encode(lyrics) }
        return result as NSDictionary
    }

    private var signedIn: Bool {
        if case .signedIn = container.auth.state { return true }
        return settings.configuration.kind == .demo
    }

    private func encode<Value: Encodable>(_ value: Value) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }

    private func remember(_ values: [Track]) {
        values.forEach { tracks[$0.id] = $0 }
    }

    @objc(execute:payload:completion:)
    func execute(_ action: String, payload: NSDictionary,
                 completion: @escaping (NSDictionary?, NSError?) -> Void) {
        Task { @MainActor in
            do {
                let value = try await perform(action, payload: payload)
                completion(value as NSDictionary, nil)
            } catch {
                completion(nil, error as NSError)
            }
        }
    }

    private func perform(_ action: String, payload: NSDictionary) async throws -> [String: Any] {
        if action == "account" { presentAccount(); return ["presented": true] }
        if action == "state" { return (snapshot as? [String: Any]) ?? [:] }
        guard signedIn else { throw MusicServiceError.unauthorized }
        let service = container.service
        switch action {
        case "catalog":
            let query = (payload["query"] as? String) ?? ""
            let identifier = (payload["id"] as? String) ?? ""
            let kind = (payload["kind"] as? String) ?? "song"
            if !query.isEmpty {
                let results = try await service.search(query: query)
                remember(results.tracks)
                return (encode(results) as? [String: Any]) ?? [:]
            }
            if kind == "playlist", !identifier.isEmpty {
                let playlist = try await service.playlist(id: identifier)
                remember(playlist.tracks)
                return ["tracks": encode(playlist.tracks) ?? [], "playlists": encode([playlist]) ?? []]
            }
            if kind == "album", !identifier.isEmpty {
                let album = try await service.album(id: identifier)
                remember(album.tracks)
                return ["tracks": encode(album.tracks) ?? [], "albums": encode([album]) ?? []]
            }
            if kind == "artist", !identifier.isEmpty {
                let artist = try await service.artist(id: identifier)
                remember(artist.tracks)
                return ["tracks": encode(artist.tracks) ?? [], "albums": encode(artist.albums) ?? []]
            }
            let library = try await service.library()
            remember(library.liked + library.recentlyAdded + library.playlists.flatMap(\.tracks))
            let liked = library.liked
            let albums = Dictionary(grouping: liked, by: { $0.albumID ?? $0.albumTitle }).map { key, values in
                Album(id: key, title: values[0].albumTitle, artists: [values[0].artist],
                      artwork: values[0].artwork, year: nil, genre: nil, tracks: values)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            let artists = Dictionary(grouping: liked, by: { $0.artist.id }).compactMap { $0.value.first?.artist }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return ["tracks": encode(liked) ?? [], "albums": encode(albums) ?? [],
                    "artists": encode(artists) ?? [], "playlists": encode(library.playlists) ?? []]
        case "home":
            let home = try await service.home()
            remember(home.featured + home.shelves.flatMap(\.tracks))
            return ["tracks": encode(home.featured + home.shelves.flatMap(\.tracks)) ?? []]
        case "play":
            let identifier = payload["id"] as? String
            if let identifier, let track = tracks[identifier] {
                let queueIDs = payload["queue"] as? [String] ?? []
                let queue = queueIDs.compactMap { tracks[$0] }
                await container.player.play(track, queue: queue.isEmpty ? [track] : queue)
                if let error = container.player.errorMessage { throw MusicServiceError.message(error) }
            } else if identifier != nil {
                throw MusicServiceError.message("Трек отсутствует в загруженном каталоге.")
            } else if !container.player.isPlaying { container.player.togglePlayback() }
        case "pause": container.player.pause()
        case "toggle": container.player.togglePlayback()
        case "stop": container.player.stop()
        case "next": container.player.next()
        case "previous": container.player.previous()
        case "seek": container.player.seek(to: (payload["time"] as? NSNumber)?.doubleValue ?? 0)
        case "favorite":
            guard let identifier = payload["id"] as? String else { throw MusicServiceError.invalidResponse }
            try await service.setFavorite(trackID: identifier, isFavorite: (payload["enabled"] as? Bool) ?? true)
        case "download":
            guard let identifier = payload["id"] as? String, let track = tracks[identifier] else {
                throw MusicServiceError.invalidResponse
            }
            await container.downloads.download(track, quality: container.player.preferredQuality)
        default: throw MusicServiceError.unsupportedFeature("Неподдерживаемая команда адаптера: \(action)")
        }
        return (snapshot as? [String: Any]) ?? [:]
    }

    @objc func presentAccount() {
        guard let presenter = Self.presenter() else { return }
        let controller = UIHostingController(rootView:
            NavigationStack { AccountSettingsView() }
                .environmentObject(container).environmentObject(container.auth)
                .environmentObject(container.player).environmentObject(container.catalog)
                .environmentObject(container.downloads).environmentObject(settings)
                .environmentObject(appearance).environmentObject(developer)
                .environmentObject(container.lyricsSettings)
                .environmentObject(container.downloadPreferences)
                .environmentObject(container.waveSettings)
        )
        controller.modalPresentationStyle = .pageSheet
        presenter.present(controller, animated: true)
    }

    private static func presenter() -> UIViewController? {
        var root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = root?.presentedViewController { root = presented }
        return root
    }
}
