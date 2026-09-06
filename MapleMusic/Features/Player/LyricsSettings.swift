import Combine
import Foundation

@MainActor
final class LyricsSettings: ObservableObject {
    @Published var usesGeniusFallback: Bool {
        didSet { UserDefaults.standard.set(usesGeniusFallback, forKey: "lyrics-genius-fallback") }
    }
    @Published private(set) var hasGeniusToken = false
    @Published var errorMessage: String?

    private let vault = GeniusTokenVault()
    private let client = GeniusLyricsClient()

    init() {
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
        guard usesGeniusFallback, let token = try await vault.load(), !token.isEmpty else { return nil }
        return try await client.lyrics(for: track, accessToken: token)
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
