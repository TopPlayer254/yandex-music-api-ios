import AVFoundation
import CoreMedia
import Foundation

struct AudioEnvelope: Sendable {
    let levels: [Float]
    let secondsPerBin: Double

    func level(at time: TimeInterval) -> Float {
        guard !levels.isEmpty else { return 0 }
        let position = max(0, time / secondsPerBin)
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
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { return nil }

        let binDuration = 0.08
        var squares: [Double] = []
        var counts: [Int] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount >= MemoryLayout<Int16>.size else { continue }
            let sampleCount = byteCount / MemoryLayout<Int16>.size
            let timestamp = max(0, CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            guard timestamp.isFinite else { continue }
            let bin = min(Int(timestamp / binDuration), Int(3 * 60 * 60 / binDuration))
            while squares.count <= bin { squares.append(0); counts.append(0) }
            var samples = [Int16](repeating: 0, count: sampleCount)
            let status = samples.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: bytes.baseAddress!)
            }
            guard status == noErr else { continue }
            // Subsample long buffers; a visual envelope does not need every PCM frame.
            for index in stride(from: 0, to: sampleCount, by: 8) {
                let amplitude = Double(samples[index]) / Double(Int16.max)
                squares[bin] += amplitude * amplitude
                counts[bin] += 1
            }
        }
        guard reader.status == .completed, !squares.isEmpty else { return nil }
        let levels = zip(squares, counts).map { pair -> Float in
            let (sum, count) = pair
            guard count > 0 else { return 0 }
            let rms = sqrt(sum / Double(count))
            return Float(min(max(pow(rms / 0.18, 0.65), 0), 1))
        }
        return AudioEnvelope(levels: levels, secondsPerBin: binDuration)
    }
}
