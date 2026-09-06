import Foundation
import Combine

struct BulkDownloadProgress: Equatable {
    let completed: Int
    let total: Int
}

@MainActor
final class DownloadsStore: ObservableObject {
    @Published private(set) var entries: [OfflineEntry] = []
    @Published private(set) var activeTrackIDs: Set<String> = []
    @Published private(set) var bulkProgress: BulkDownloadProgress?
    @Published var errorMessage: String?

    private let offlineStore: OfflineStore
    private let service: AnyMusicService
    private let lyricsSettings: LyricsSettings

    init(offlineStore: OfflineStore, service: AnyMusicService, lyricsSettings: LyricsSettings) {
        self.offlineStore = offlineStore
        self.service = service
        self.lyricsSettings = lyricsSettings
    }

    func refresh() async {
        entries = await offlineStore.entries()
    }

    func isDownloaded(_ track: Track) -> Bool {
        entries.contains { $0.trackID == track.id }
    }

    func download(_ track: Track, quality: AudioQuality) async {
        guard !activeTrackIDs.contains(track.id) else { return }
        activeTrackIDs.insert(track.id)
        errorMessage = nil
        defer { activeTrackIDs.remove(track.id) }
        do {
            try await save(track, quality: quality)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func downloadAll(_ tracks: [Track], quality: AudioQuality) async {
        guard bulkProgress == nil else { return }
        var seen = Set<String>()
        let pending = tracks.filter {
            seen.insert($0.id).inserted
                && $0.downloadAllowed
                && !isDownloaded($0)
                && !activeTrackIDs.contains($0.id)
        }
        guard !pending.isEmpty else { return }

        errorMessage = nil
        bulkProgress = BulkDownloadProgress(completed: 0, total: pending.count)
        var failed = 0
        for (index, track) in pending.enumerated() {
            guard !Task.isCancelled else { break }
            activeTrackIDs.insert(track.id)
            do {
                try await save(track, quality: quality)
            } catch is CancellationError {
                activeTrackIDs.remove(track.id)
                break
            } catch {
                failed += 1
            }
            activeTrackIDs.remove(track.id)
            bulkProgress = BulkDownloadProgress(completed: index + 1, total: pending.count)
        }
        await refresh()
        bulkProgress = nil
        if failed > 0 {
            errorMessage = "Не удалось скачать \(failed) из \(pending.count) треков."
        }
    }

    func remove(_ track: Track) async {
        do {
            try await offlineStore.remove(trackID: track.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAll() async {
        errorMessage = nil
        do {
            try await offlineStore.removeAll()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ track: Track, quality: AudioQuality) async throws {
        let asset = try await service.playbackAsset(for: track, quality: quality)
        let lyrics: Lyrics?
        if let serviceLyrics = try? await service.lyrics(for: track), !serviceLyrics.lines.isEmpty {
            lyrics = serviceLyrics
        } else {
            lyrics = try? await lyricsSettings.fallbackLyrics(for: track)
        }
        try await offlineStore.save(track: track, asset: asset, lyrics: lyrics)
    }
}
