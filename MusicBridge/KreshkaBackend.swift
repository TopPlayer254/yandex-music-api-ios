import Combine
import Foundation
import SwiftUI
import UIKit

/// Objective-C boundary used by the original application's model adapters.
/// The service, credentials, downloads and player are the existing Maple code.
@MainActor
@objc(KreshkaBackend)
final class KreshkaBackend: NSObject, ObservableObject {
    private static let instance = KreshkaBackend()
    fileprivate let settings = ProviderSettings()
    fileprivate let appearance = AppearanceSettings()
    fileprivate let developer = DeveloperSettings()
    @Published fileprivate var container: AppContainer!
    private var observations = Set<AnyCancellable>()
    private var containerObservations = Set<AnyCancellable>()
    private var tracks: [String: Track] = [:]
    private var bootstrapTask: Task<Void, Never>?
    private weak var settingsController: UIViewController?

    @objc static func sharedInstance() -> KreshkaBackend { instance }

    override private init() {
        super.init()
        // Fixture selection is restricted to the separate simulator test host.
        // The packaged Music application always uses its user's saved provider.
        if Bundle.main.bundleIdentifier?.hasSuffix(".smoke") == true,
           ProcessInfo.processInfo.environment["KRESHKA_SMOKE_CATALOG"] == "1" {
            var fixture = ProviderConfiguration()
            fixture.kind = .demo
            try? settings.apply(fixture)
        }
        rebuild()
        settings.$generation.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }.store(in: &observations)
    }

    private func rebuild() {
        bootstrapTask?.cancel()
        container?.player.stop()
        containerObservations.removeAll()
        tracks.removeAll()
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
        current.catalog.$library.compactMap { $0 }.removeDuplicates()
            .receive(on: DispatchQueue.main).sink { [weak self] library in
                guard let self, self.container === current else { return }
                self.remember(library.liked + library.recentlyAdded + library.playlists.flatMap(\.tracks))
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
        if action == "settings" { presentSettings(); return ["presented": true] }
        if action == "state" { return (snapshot as? [String: Any]) ?? [:] }
        // Native screens request the library during launch, before Keychain
        // restoration has completed. Do not cache an unauthorized response then.
        await bootstrapTask?.value
        if action == "readyState" { return (snapshot as? [String: Any]) ?? [:] }
        guard signedIn else { throw MusicServiceError.unauthorized }
        let service = container.service
        switch action {
        case "playlist.create":
            let name = ((payload["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw MusicServiceError.message("Введите название плейлиста.") }
            let playlist = try await service.createPlaylist(name: name)
            for id in payload["tracks"] as? [String] ?? [] {
                try await service.add(trackID: id, toPlaylistID: playlist.id)
            }
            await container.catalog.refreshLibrary()
            NotificationCenter.default.post(name: .init("KreshkaCatalogChanged"), object: self)
            return ["playlist": encode(playlist) ?? [:]]
        case "catalog":
            let query = (payload["query"] as? String) ?? ""
            let identifier = (payload["id"] as? String) ?? ""
            let kind = (payload["kind"] as? String) ?? "song"
            let containerKind = (payload["containerKind"] as? String) ?? kind
            if !query.isEmpty {
                let results = try await service.search(query: query)
                remember(results.tracks)
                return (encode(results) as? [String: Any]) ?? [:]
            }
            if containerKind == "playlist", !identifier.isEmpty {
                let playlist = try await service.playlist(id: identifier)
                remember(playlist.tracks)
                return ["tracks": encode(playlist.tracks) ?? [], "playlists": encode([playlist]) ?? []]
            }
            if containerKind == "album", !identifier.isEmpty {
                let album = try await service.album(id: identifier)
                remember(album.tracks)
                return ["tracks": encode(album.tracks) ?? [], "albums": encode([album]) ?? []]
            }
            if containerKind == "artist", !identifier.isEmpty {
                let artist = try await service.artist(id: identifier)
                remember(artist.tracks)
                return ["tracks": encode(artist.tracks) ?? [], "albums": encode(artist.albums) ?? []]
            }
            if container.catalog.library == nil { await container.catalog.refreshLibrary() }
            guard let library = container.catalog.library else {
                throw MusicServiceError.message(container.catalog.libraryErrorMessage ?? "Не удалось загрузить медиатеку.")
            }
            remember(library.liked + library.recentlyAdded + library.playlists.flatMap(\.tracks))
            let liked = library.liked
            let albums = Dictionary(grouping: liked, by: { $0.albumID ?? $0.albumTitle }).map { key, values in
                Album(id: key, title: values[0].albumTitle, artists: [values[0].artist],
                      artwork: values[0].artwork, year: nil, genre: nil, tracks: values,
                      trackCount: values.count)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            let artists = Dictionary(grouping: liked, by: { $0.artist.id }).compactMap { $0.value.first?.artist }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let identifiers = payload["ids"] as? [String] ?? []
            let selected = identifiers.isEmpty ? liked : identifiers.compactMap { tracks[$0] }
            return ["tracks": encode(selected) ?? [], "albums": encode(albums) ?? [],
                    "artists": encode(artists) ?? [], "playlists": encode(library.playlists) ?? []]
        case "home":
            if container.catalog.home == nil { await container.catalog.refreshHome() }
            guard let home = container.catalog.home else {
                throw MusicServiceError.message(container.catalog.homeErrorMessage ?? "Не удалось загрузить главную.")
            }
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
            } else if container.player.currentTrack != nil {
                container.player.resume()
            } else {
                throw MusicServiceError.message("Сначала выберите трек из медиатеки Яндекса.")
            }
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
        presentSettings()
        settings.opensAccount = true
    }

    @objc func presentSettings() {
        if let settingsController,
           settingsController.presentingViewController != nil || settingsController.isBeingPresented { return }
        guard let presenter = Self.presenter() else { return }
        let controller = UIHostingController(rootView: BridgeSettingsRoot(backend: self))
        settingsController = controller
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

@MainActor
private struct BridgeSettingsRoot: View {
    @ObservedObject var backend: KreshkaBackend
    @ObservedObject private var settings: ProviderSettings
    @ObservedObject private var appearance: AppearanceSettings

    init(backend: KreshkaBackend) {
        self.backend = backend
        settings = backend.settings
        appearance = backend.appearance
    }

    var body: some View {
        AccountView()
            .sheet(isPresented: $settings.opensAccount) {
                NavigationStack { AccountSettingsView() }
            }
            .environmentObject(backend.container)
            .environmentObject(backend.container.auth)
            .environmentObject(backend.container.player)
            .environmentObject(backend.container.catalog)
            .environmentObject(backend.container.downloads)
            .environmentObject(backend.settings)
            .environmentObject(backend.appearance)
            .environmentObject(backend.developer)
            .environmentObject(backend.container.lyricsSettings)
            .environmentObject(backend.container.downloadPreferences)
            .environmentObject(backend.container.waveSettings)
            .id(ObjectIdentifier(backend.container))
            .tint(backend.appearance.tint)
            .preferredColorScheme(backend.appearance.interfaceStyle.colorScheme)
    }
}
