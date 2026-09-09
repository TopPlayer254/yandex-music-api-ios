import Combine
import Foundation

@MainActor
final class DeveloperSettings: ObservableObject {
    @Published var usesNewShaderBasedWave: Bool {
        didSet {
            UserDefaults.standard.set(usesNewShaderBasedWave, forKey: Self.shaderWaveKey)
        }
    }

    private static let shaderWaveKey = "developer-use-new-shader-wave"

    init() {
        usesNewShaderBasedWave = UserDefaults.standard.bool(forKey: Self.shaderWaveKey)
    }
}
