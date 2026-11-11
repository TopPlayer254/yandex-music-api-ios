import AVFoundation
import CoreMedia
import Foundation

struct AudioEnvelope: Sendable {
    let levels: [Float]
    let secondsPerBin: Double
    var bandLevels: [[Float]] = []

    func bands(at time: TimeInterval) -> [Float] {
        bandLevels.map { AudioEnvelope(levels: $0, secondsPerBin: secondsPerBin).level(at: time) }
    }

    func level(at time: TimeInterval) -> Float {
        guard !levels.isEmpty, time.isFinite, secondsPerBin > 0 else { return 0 }
        let position = min(max(0, time / secondsPerBin), Double(levels.count - 1))
        let first = min(Int(position), levels.count - 1)
        let second = min(first + 1, levels.count - 1)
        let blend = Float(position - Double(first))
        return levels[first] * (1 - blend) + levels[second] * blend
    }
}

actor AudioEnvelopeAnalyzer {
    func analyze(fileURL: URL) async throws -> AudioEnvelope? {
        guard fileURL.isFileURL else { return nil }
        let asset = AVURLAsset(url: fileURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 22050,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }

        let binDuration = 0.05
        let rates = [160.0, 650.0, 2600.0].map { 1 - exp(-2 * Double.pi * $0 / 22050) }
        var low = [0.0, 0.0, 0.0]
        var squares: [[Double]] = Array(repeating: [], count: 5)
        var counts: [Int] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount >= 2, byteCount.isMultiple(of: 2) else { continue }
            let sampleCount = byteCount / MemoryLayout<Int16>.size
            let timestamp = max(0, CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            guard timestamp.isFinite else { continue }
            var samples = [Int16](repeating: 0, count: sampleCount)
            let status = samples.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: bytes.baseAddress!)
            }
            guard status == noErr else { continue }
            for (index, sample) in samples.enumerated() {
                let time = timestamp + Double(index) / 22050
                guard time < 3 * 60 * 60 else { return nil }
                let bin = Int(time / binDuration)
                while counts.count <= bin {
                    counts.append(0)
                    for band in squares.indices { squares[band].append(0) }
                }
                let amplitude = Double(sample) / 32768
                squares[0][bin] += amplitude * amplitude
                for i in low.indices { low[i] += rates[i] * (amplitude - low[i]) }
                let bass = low[0], lowMid = low[1] - low[0], mid = low[2] - low[1], high = amplitude - low[2]
                squares[1][bin] += bass * bass
                squares[2][bin] += lowMid * lowMid
                squares[3][bin] += mid * mid
                squares[4][bin] += high * high
                counts[bin] += 1
            }
        }
        guard reader.status == .completed, !counts.isEmpty else { return nil }
        let normalized = squares.map { band -> [Float] in
            let rms = zip(band, counts).map { sqrt($0.0 / Double(max($0.1, 1))) }
            let sorted = rms.sorted()
            let peak = max(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], 0.014)
            return rms.map { Float(min(pow($0 / peak, 1.35), 1)) }
        }
        return AudioEnvelope(levels: normalized[0], secondsPerBin: binDuration, bandLevels: Array(normalized.dropFirst()))
    }
}
