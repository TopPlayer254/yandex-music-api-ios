import Combine
import Foundation

@MainActor
final class WaveMotionStore: ObservableObject {
    @Published private(set) var level: Float = 0

    func update(_ value: Float) {
        let target = min(max(value, 0), 1)
        level += (target - level) * (target > level ? 0.72 : 0.32)
    }

    func reset() { level = 0 }
}
