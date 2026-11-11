import Combine
import Foundation

@MainActor
final class WaveMotionStore: ObservableObject {
    @Published private(set) var levels = [Float](repeating: 0, count: 5)
    var level: Float { levels[0] }
    var bands: ArraySlice<Float> { levels.dropFirst() }

    func update(_ value: Float, bands: [Float]) {
        let input = [value] + bands
        let next = levels.enumerated().map { index, previous -> Float in
            let target = index < input.count ? min(max(input[index], 0), 1) : 0
            let smoothed = previous + (target - previous) * (target > previous ? 0.72 : 0.32)
            return smoothed < 0.002 ? 0 : smoothed
        }
        if next != levels { levels = next }
    }

    func reset() { if levels.contains(where: { $0 != 0 }) { levels = Array(repeating: 0, count: 5) } }
}
