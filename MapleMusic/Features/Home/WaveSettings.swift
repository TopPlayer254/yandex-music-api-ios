import Combine
import Foundation

@MainActor
final class WaveSettings: ObservableObject {
    @Published var configuration: WaveConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(configuration) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
    }

    private static let storageKey = "my-wave-configuration"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(WaveConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = WaveConfiguration()
        }
    }
}
