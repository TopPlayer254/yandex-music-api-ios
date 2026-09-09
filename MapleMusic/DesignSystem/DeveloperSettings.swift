import Combine
import Foundation

@MainActor
final class DeveloperSettings: ObservableObject {
    @Published var usesNewShaderBasedWave: Bool {
        didSet {
            UserDefaults.standard.set(usesNewShaderBasedWave, forKey: Self.shaderWaveKey)
        }
    }

    @Published var showsCodename: Bool {
        didSet {
            UserDefaults.standard.set(showsCodename, forKey: Self.codenameKey)
        }
    }

    private static let shaderWaveKey = "developer-use-new-shader-wave"
    private static let codenameKey = "developer-show-codename"

    init() {
        usesNewShaderBasedWave = UserDefaults.standard.bool(forKey: Self.shaderWaveKey)
        showsCodename = UserDefaults.standard.bool(forKey: Self.codenameKey)
    }
}
