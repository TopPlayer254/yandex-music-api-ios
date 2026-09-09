import AVFoundation
import Foundation
import MediaPlayer
import Combine
import Network

@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var resolvedAsset: PlaybackAsset?
    @Published private(set) var lyrics: Lyrics?
    @Published var preferredQuality: AudioQuality {
        didSet { UserDefaults.standard.set(preferredQuality.rawValue, forKey: "preferred-quality") }
    }
    @Published var volume: Double {
        didSet {
            let clamped = min(max(volume, 0), 1)
            player.volume = Float(clamped)
            UserDefaults.standard.set(clamped, forKey: "player-volume")
        }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffling = false
    @Published var isShowingNowPlaying = false
    @Published var errorMessage: String?
    @Published private(set) var isBuffering = false

    private let service: AnyMusicService
    private let offlineStore: OfflineStore
    private let downloads: DownloadsStore
    private let lyricsSettings: LyricsSettings
    private let downloadPreferences: DownloadPreferences
    private let player = AVPlayer()
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.hikeri.yamusic.network-monitor")
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var itemStatus: NSKeyValueObservation?
    private var requestID = UUID()
    private var playbackFile: URL?
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var networkIsAvailable = true
    private var recoveryTask: Task<Void, Never>?
    private var pendingRecovery: PlaybackRecovery?

    private struct PlaybackRecovery {
        let track: Track
        let queue: [Track]
        let resumeTime: TimeInterval
        let attempt: Int
    }

    init(
        service: AnyMusicService,
        offlineStore: OfflineStore,
        downloads: DownloadsStore,
        lyricsSettings: LyricsSettings,
        downloadPreferences: DownloadPreferences
    ) {
        self.service = service
        self.offlineStore = offlineStore
        self.downloads = downloads
        self.lyricsSettings = lyricsSettings
        self.downloadPreferences = downloadPreferences
        let savedQuality = AudioQuality(rawValue: UserDefaults.standard.string(forKey: "preferred-quality") ?? "")
        preferredQuality = savedQuality == .lossless ? .lossless : .high
        if let savedVolume = UserDefaults.standard.object(forKey: "player-volume") as? Double {
            volume = savedVolume
        } else {
            volume = 1
        }
        player.volume = Float(volume)
        configureObservers()
        configureRemoteCommands()
        configureNetworkMonitor()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        networkMonitor.cancel()
        artworkTask?.cancel()
        recoveryTask?.cancel()
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var activeLyricsLineIndex: Int? {
        guard lyrics?.isSynchronized == true, let lines = lyrics?.lines, !lines.isEmpty else { return nil }
        return LyricsSynchronizer.activeLineIndex(at: currentTime, lines: lines)
    }

    func play(_ track: Track, queue proposedQueue: [Track]? = nil) async {
        await play(track, queue: proposedQueue, recoveryAttempt: 0)
    }

    private func play(_ track: Track, queue proposedQueue: [Track]?, recoveryAttempt: Int) async {
        if recoveryAttempt == 0 {
            recoveryTask?.cancel()
            recoveryTask = nil
            pendingRecovery = nil
        }
        let identifier = UUID()
        requestID = identifier
        if recoveryAttempt == 0 {
            beginPlaybackSelection(track, queue: proposedQueue)
        } else {
            isBuffering = true
            errorMessage = nil
        }
        var preparedFile: URL?
        do {
            let asset: PlaybackAsset
            if let offline = await offlineStore.localAsset(for: track) {
                asset = offline
            } else {
                asset = try await service.playbackAsset(for: track, quality: resolvedPreferredQuality(for: track))
            }
            guard requestID == identifier else { return }
            var playbackURL = asset.url
            let isHLS = asset.transport == "hls" || asset.url.pathExtension.lowercased() == "m3u8"
            let expectedExtension = MediaFileLoader.fileExtension(for: asset)
            let needsPreparedFile = asset.decryptionKey != nil
                || (!asset.url.isFileURL && !isHLS)
                || (asset.url.isFileURL && asset.url.pathExtension.lowercased() != expectedExtension)
            if needsPreparedFile {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("maple-\(identifier).\(MediaFileLoader.fileExtension(for: asset))")
                try await MediaFileLoader.download(asset, to: file)
                guard requestID == identifier else { try? FileManager.default.removeItem(at: file); return }
                preparedFile = file
                playbackURL = file
            }

            let mediaAsset = AVURLAsset(url: playbackURL)
            let isPlayable = try await mediaAsset.load(.isPlayable)
            guard isPlayable else {
                throw MusicServiceError.message("Формат этого трека не поддерживается проигрывателем.")
            }
            guard requestID == identifier else {
                if let preparedFile { try? FileManager.default.removeItem(at: preparedFile) }
                return
            }

            playbackFile = preparedFile
            resolvedAsset = asset
            if let proposedQueue, !proposedQueue.isEmpty {
                queue = proposedQueue
            } else if !queue.contains(where: { $0.id == track.id }) {
                queue = [track]
            }
            currentTrack = track

            let item = AVPlayerItem(asset: mediaAsset)
            itemStatus = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                let status = observed.status
                let error = observed.error
                Task { @MainActor in
                    guard let self, self.requestID == identifier else { return }
                    self.isBuffering = status == .unknown
                    if status == .failed { self.failCurrentPlayback(error) }
                }
            }
            player.replaceCurrentItem(with: item)
            prepareAudioSession()
            player.play()
            isPlaying = true
            updateNowPlayingInfo()
            Task {
                let cached = await offlineStore.localLyrics(for: track.id)
                let fetched: Lyrics?
                if let cached {
                    fetched = cached
                } else if let serviceLyrics = try? await service.lyrics(for: track),
                          !serviceLyrics.lines.isEmpty {
                    fetched = serviceLyrics
                } else {
                    fetched = try? await lyricsSettings.fallbackLyrics(for: track)
                }
                guard requestID == identifier else { return }
                lyrics = fetched
            }
            if downloadPreferences.automaticallyDownloadsPlayedTracks,
               track.downloadAllowed,
               !downloads.isDownloaded(track),
               !downloads.activeTrackIDs.contains(track.id) {
                Task { await downloads.download(track, quality: resolvedPreferredQuality(for: track)) }
            }
        } catch is CancellationError {
            guard requestID == identifier else { return }
            if let preparedFile { try? FileManager.default.removeItem(at: preparedFile) }
            isBuffering = false
        } catch {
            guard requestID == identifier else { return }
            if let preparedFile { try? FileManager.default.removeItem(at: preparedFile) }
            if !networkIsAvailable || Self.isConnectivityError(error) {
                if recoveryAttempt < 2 {
                    prepareRecovery(
                        for: track,
                        queue: proposedQueue,
                        resumeTime: 0,
                        attempt: recoveryAttempt + 1
                    )
                } else {
                    pendingRecovery = nil
                    isBuffering = false
                    errorMessage = "Сеть вернулась, но трек пока не загрузился. Нажмите воспроизведение, чтобы повторить."
                    updateNowPlayingInfo()
                }
                return
            }
            isBuffering = false
            errorMessage = error.localizedDescription
            updateNowPlayingInfo()
        }
    }

    private func beginPlaybackSelection(_ track: Track, queue proposedQueue: [Track]?) {
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatus = nil
        if let playbackFile { try? FileManager.default.removeItem(at: playbackFile) }
        playbackFile = nil
        resolvedAsset = nil
        isPlaying = false
        isBuffering = true
        errorMessage = nil
        if let proposedQueue, !proposedQueue.isEmpty {
            queue = proposedQueue
        } else if !queue.contains(where: { $0.id == track.id }) {
            queue = [track]
        }
        currentTrack = track
        duration = track.duration
        currentTime = 0
        lyrics = nil
        loadNowPlayingArtwork(for: track)
        updateNowPlayingInfo()
    }

    func stop() {
        requestID = UUID()
        recoveryTask?.cancel()
        recoveryTask = nil
        pendingRecovery = nil
        artworkTask?.cancel()
        artworkTask = nil
        nowPlayingArtwork = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatus = nil
        isPlaying = false
        isBuffering = false
        currentTrack = nil
        queue = []
        lyrics = nil
        resolvedAsset = nil
        if let playbackFile { try? FileManager.default.removeItem(at: playbackFile) }
        playbackFile = nil
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets = []
        updateNowPlayingInfo()
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard player.currentItem != nil else {
            if let currentTrack { Task { await play(currentTrack) } }
            return
        }
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func seek(to time: TimeInterval) {
        let target = min(max(time, 0), duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        updateNowPlayingInfo()
    }

    func next() {
        guard let currentTrack, !queue.isEmpty else { return }
        let nextTrack: Track?
        if isShuffling {
            nextTrack = queue.filter { $0.id != currentTrack.id }.randomElement() ?? currentTrack
        } else if let index = queue.firstIndex(where: { $0.id == currentTrack.id }), index + 1 < queue.count {
            nextTrack = queue[index + 1]
        } else if repeatMode == .all {
            nextTrack = queue.first
        } else {
            nextTrack = nil
        }
        if let nextTrack { Task { await play(nextTrack) } } else { pause() }
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let currentTrack,
              let index = queue.firstIndex(where: { $0.id == currentTrack.id }),
              index > 0
        else {
            seek(to: 0)
            return
        }
        Task { await play(queue[index - 1]) }
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    private func resolvedPreferredQuality(for track: Track) -> AudioQuality {
        if preferredQuality == .automatic { return .automatic }
        if track.availableQualities.contains(preferredQuality) { return preferredQuality }
        return track.availableQualities.contains(.high) ? .high : .automatic
    }

    private func handleEnd() {
        if repeatMode == .one {
            seek(to: 0)
            resume()
        } else {
            next()
        }
    }

    private func prepareAudioSession() {
        // AVPlayer activates the session itself. Setting only the playback
        // category at the moment playback starts avoids a launch-time -50.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    private func configureNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor in
                self?.networkPathDidChange(isAvailable: isAvailable)
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    private func networkPathDidChange(isAvailable: Bool) {
        let wasAvailable = networkIsAvailable
        networkIsAvailable = isAvailable

        if !isAvailable {
            recoveryTask?.cancel()
            recoveryTask = nil
            if let track = currentTrack,
               playbackFile == nil,
               resolvedAsset?.url.isFileURL == false {
                pendingRecovery = PlaybackRecovery(track: track, queue: queue, resumeTime: currentTime, attempt: 1)
                player.pause()
                isPlaying = false
                isBuffering = true
                updateNowPlayingInfo()
            }
        } else if !wasAvailable || pendingRecovery != nil {
            scheduleRecovery()
        }
    }

    private func prepareRecovery(
        for track: Track,
        queue proposedQueue: [Track]?,
        resumeTime: TimeInterval,
        attempt: Int
    ) {
        let recoveryQueue: [Track]
        if let proposedQueue, !proposedQueue.isEmpty {
            recoveryQueue = proposedQueue
        } else if queue.contains(where: { $0.id == track.id }) {
            recoveryQueue = queue
        } else {
            recoveryQueue = [track]
        }
        pendingRecovery = PlaybackRecovery(
            track: track,
            queue: recoveryQueue,
            resumeTime: resumeTime,
            attempt: attempt
        )
        errorMessage = nil
        isPlaying = false
        isBuffering = true
        if player.currentItem == nil {
            currentTrack = track
            queue = recoveryQueue
            duration = track.duration
            currentTime = resumeTime
            lyrics = nil
            loadNowPlayingArtwork(for: track)
            updateNowPlayingInfo()
        }
        if networkIsAvailable {
            scheduleRecovery()
        }
    }

    private func scheduleRecovery() {
        guard networkIsAvailable, pendingRecovery != nil, recoveryTask == nil else { return }
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled,
                  let self,
                  self.networkIsAvailable,
                  let recovery = self.pendingRecovery
            else { return }
            self.pendingRecovery = nil
            self.recoveryTask = nil
            await self.play(
                recovery.track,
                queue: recovery.queue,
                recoveryAttempt: recovery.attempt
            )
            if self.currentTrack?.id == recovery.track.id,
               self.player.currentItem != nil,
               recovery.resumeTime > 0 {
                self.seek(to: recovery.resumeTime)
            }
        }
    }

    private func loadNowPlayingArtwork(for track: Track) {
        artworkTask?.cancel()
        artworkTask = nil
        nowPlayingArtwork = nil
        guard let url = track.artwork.url else { return }
        let trackID = track.id
        artworkTask = Task { [weak self] in
            guard let image = await ArtworkImageCache.shared.image(for: url),
                  !Task.isCancelled,
                  let self,
                  self.currentTrack?.id == trackID
            else { return }
            self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.updateNowPlayingInfo()
        }
    }

    private static func isConnectivityError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [
                .notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                .internationalRoamingOff, .dataNotAllowed,
            ].contains(urlError.code)
        }
        if let serviceError = error as? MusicServiceError,
           serviceError == .http(0) {
            return true
        }
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           (underlying as NSError) !== nsError {
            return isConnectivityError(underlying)
        }
        return false
    }

    private func failCurrentPlayback(_ error: Error?) {
        if let track = currentTrack,
           !networkIsAvailable || error.map(Self.isConnectivityError) == true {
            let resumeTime = currentTime
            player.pause()
            player.replaceCurrentItem(with: nil)
            itemStatus = nil
            isPlaying = false
            isBuffering = true
            resolvedAsset = nil
            if let playbackFile { try? FileManager.default.removeItem(at: playbackFile) }
            playbackFile = nil
            prepareRecovery(for: track, queue: queue, resumeTime: resumeTime, attempt: 1)
            updateNowPlayingInfo()
            return
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatus = nil
        isPlaying = false
        isBuffering = false
        resolvedAsset = nil
        currentTrack = nil
        lyrics = nil
        artworkTask?.cancel()
        artworkTask = nil
        nowPlayingArtwork = nil
        duration = 0
        currentTime = 0
        isShowingNowPlaying = false
        if let playbackFile { try? FileManager.default.removeItem(at: playbackFile) }
        playbackFile = nil
        if let detail = error?.localizedDescription, !detail.isEmpty {
            errorMessage = "Не удалось воспроизвести трек. \(detail)"
        } else {
            errorMessage = "Не удалось воспроизвести трек. Попробуйте другой режим API в настройках."
        }
        updateNowPlayingInfo()
    }

    private func configureObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? max(time.seconds, 0) : 0
                if let seconds = self.player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
                    self.duration = seconds
                }
                self.updateNowPlayingInfo()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let endedItem = notification.object as? AVPlayerItem,
                      let currentItem = self.player.currentItem,
                      endedItem === currentItem
                else { return }
                self.handleEnd()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        remoteTargets.append((center.playCommand, center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }))
        remoteTargets.append((center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }))
        remoteTargets.append((center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }))
        remoteTargets.append((center.nextTrackCommand, center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }))
        remoteTargets.append((center.previousTrackCommand, center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }))
        remoteTargets.append((center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }))
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist.name,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyExternalContentIdentifier: track.id,
        ]
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

enum LyricsSynchronizer {
    static func activeLineIndex(at time: TimeInterval, lines: [LyricsLine]) -> Int? {
        guard !lines.isEmpty, time >= lines[0].time else { return nil }
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lines[middle].time <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return max(0, lower - 1)
    }
}
