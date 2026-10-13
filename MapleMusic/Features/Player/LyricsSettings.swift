import Combine
import Foundation

enum LyricsSource: String, CaseIterable, Identifiable, Codable {
    case service, lrclib, genius
    var id: Self { self }
    var title: String {
        switch self { case .service: "Музыкальный сервис"; case .lrclib: "LRCLIB"; case .genius: "Genius" }
    }
}

@MainActor
final class LyricsSettings: ObservableObject {
    @Published var usesGeniusFallback: Bool {
        didSet { UserDefaults.standard.set(usesGeniusFallback, forKey: "lyrics-genius-fallback") }
    }
    @Published private(set) var hasGeniusToken = false
    @Published var errorMessage: String?
    @Published var sourceOrder: [LyricsSource] {
        didSet { UserDefaults.standard.set(sourceOrder.map(\.rawValue), forKey: "lyrics-source-order") }
    }

    private let vault = GeniusTokenVault()
    private let client = GeniusLyricsClient()
    private let lrclib = LRCLIBLyricsClient()

    init() {
        let saved = (UserDefaults.standard.stringArray(forKey: "lyrics-source-order") ?? []).compactMap(LyricsSource.init(rawValue:))
        var seen = Set<LyricsSource>()
        sourceOrder = (saved + LyricsSource.allCases).filter { seen.insert($0).inserted }
        usesGeniusFallback = UserDefaults.standard.bool(forKey: "lyrics-genius-fallback")
    }

    func restore() async {
        let token = try? await vault.load()
        hasGeniusToken = token?.isEmpty == false
    }

    func saveToken(_ rawValue: String) async -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = "Введите Genius Client Access Token."
            return false
        }
        do {
            try await vault.save(value)
            hasGeniusToken = true
            usesGeniusFallback = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearToken() async {
        do {
            try await vault.clear()
            hasGeniusToken = false
            usesGeniusFallback = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fallbackLyrics(for track: Track) async throws -> Lyrics? {
        if let lyrics = try? await lrclib.lyrics(for: track), !lyrics.lines.isEmpty { return lyrics }
        guard usesGeniusFallback, let token = try await vault.load(), !token.isEmpty else { return nil }
        return try await client.lyrics(for: track, accessToken: token)
    }

    func lyrics(for track: Track, service: AnyMusicService) async throws -> Lyrics? {
        var failures: [String] = []
        for source in sourceOrder {
            try Task.checkCancellation()
            do {
                let lyrics: Lyrics?
                switch source {
                case .service: lyrics = try await service.lyrics(for: track)
                case .lrclib: lyrics = try await lrclib.lyrics(for: track)
                case .genius:
                    guard usesGeniusFallback, let token = try await vault.load(), !token.isEmpty else { continue }
                    lyrics = try await client.lyrics(for: track, accessToken: token)
                }
                if let lyrics, !lyrics.lines.isEmpty { return lyrics }
            } catch is CancellationError { throw CancellationError() }
            catch { failures.append("\(source.title): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { throw MusicServiceError.message(failures.joined(separator: "\n")) }
        return nil
    }
}

@MainActor
final class DownloadPreferences: ObservableObject {
    @Published var automaticallyDownloadsPlayedTracks: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticallyDownloadsPlayedTracks,
                forKey: "automatically-download-played-tracks"
            )
        }
    }

    init() {
        automaticallyDownloadsPlayedTracks = UserDefaults.standard.bool(
            forKey: "automatically-download-played-tracks"
        )
    }
}
