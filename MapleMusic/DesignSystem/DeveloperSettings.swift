import Combine
import Foundation

@MainActor
final class DeveloperSettings: ObservableObject {
    @Published var usesLiveActivity: Bool {
        didSet { UserDefaults.standard.set(usesLiveActivity, forKey: "developer-live-activity") }
    }
    @Published var showsLiteralCrashResponse: Bool {
        didSet { UserDefaults.standard.set(showsLiteralCrashResponse, forKey: "developer-literal-errors") }
    }
    @Published var usesNewRetryScreen: Bool {
        didSet { UserDefaults.standard.set(usesNewRetryScreen, forKey: "developer-retry-screen") }
    }
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
        usesLiveActivity = UserDefaults.standard.bool(forKey: "developer-live-activity")
        showsLiteralCrashResponse = UserDefaults.standard.bool(forKey: "developer-literal-errors")
        usesNewRetryScreen = UserDefaults.standard.bool(forKey: "developer-retry-screen")
        usesNewShaderBasedWave = UserDefaults.standard.bool(forKey: Self.shaderWaveKey)
        showsCodename = UserDefaults.standard.bool(forKey: Self.codenameKey)
    }
}
