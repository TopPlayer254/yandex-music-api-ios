import AVFoundation
import CryptoKit
import Foundation

struct MusicHapticFrame: Codable, Sendable {
    let intensity: Float
    let sharpness: Float
}

struct MusicHapticAnalysis: Codable, Sendable {
    static let version = 1
    let frames: [MusicHapticFrame]
    let interval: Double
}

/// Full PCM analysis off the main actor, at 10 ms resolution. No synthetic beat clock.
actor MusicHapticAnalyzer {
    static let shared = MusicHapticAnalyzer()
    private let root: URL
    private var generation = 0

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicHaptics-v1", isDirectory: true)
    }

    func clear() throws {
        generation += 1
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func analyze(_ url: URL) async throws -> MusicHapticAnalysis {
        let ticket = generation
        // The complete content hash survives temporary playback filenames and distinguishes qualities/edits.
        var hash = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let data = try handle.read(upToCount: 256 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        let key = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let destination = root.appendingPathComponent(key + ".json")
        if let data = try? Data(contentsOf: destination),
           let cached = try? JSONDecoder().decode(MusicHapticAnalysis.self, from: data) { return cached }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw MusicServiceError.invalidResponse }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MusicServiceError.invalidResponse }
        defer { reader.cancelReading() }
        var energy: [Double] = [], bass: [Double] = [], counts: [Int] = []
        var low = 0.0
        let alpha = 1 - exp(-2 * Double.pi * 180 / 22050)
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            var pcm = [Int16](repeating: 0, count: bytes / 2)
            let copied = pcm.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: $0.baseAddress!) }
            guard copied == noErr else { continue }
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard start.isFinite, start >= 0 else { continue }
            for (index, value) in pcm.enumerated() {
                let time = start + Double(index) / 22050
                guard time < 3 * 3600 else { throw MusicServiceError.message("Трек слишком длинный для локальных хаптиков.") }
                let bin = Int(time / 0.01)
                while energy.count <= bin { energy.append(0); bass.append(0); counts.append(0) }
                let x = Double(value) / 32768
                low += alpha * (x - low)
                energy[bin] += x * x; bass[bin] += low * low; counts[bin] += 1
            }
        }
        guard reader.status == .completed else { throw reader.error ?? MusicServiceError.invalidResponse }
        let rms = zip(energy, counts).map { sqrt($0.0 / Double(max($0.1, 1))) }
        let sorted = rms.sorted()
        let reference = max(sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], 0.02)
        var previous = 0.0
        let frames = rms.enumerated().map { index, level -> MusicHapticFrame in
            let lowLevel = sqrt(bass[index] / Double(max(counts[index], 1)))
            let onset = max(level - previous, 0) / reference
            previous = level
            let intensity = level < 0.001 ? 0 : min(1, 0.5 * level / reference + 0.35 * lowLevel / reference + 1.5 * onset)
            let sharpness = min(1, max(0, 0.2 + 0.5 * (1 - lowLevel / max(level, 0.001)) + onset))
            return MusicHapticFrame(intensity: Float(intensity), sharpness: Float(sharpness))
        }
        let result = MusicHapticAnalysis(frames: frames, interval: 0.01)
        guard !frames.isEmpty else { throw MusicServiceError.invalidResponse }
        try Task.checkCancellation()
        guard generation == ticket else { throw CancellationError() }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(result).write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return result
    }
}
