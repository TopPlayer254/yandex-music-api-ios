import Combine
import CryptoKit
import Foundation

enum ProviderKind: String, CaseIterable, Codable, Identifiable {
    case yandex, gateway, demo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .yandex: "Яндекс Музыка (неофициальный API)"
        case .gateway: "Свой API-шлюз"
        case .demo: "Локальная демоверсия"
        }
    }
}

struct ProviderConfiguration: Codable, Equatable {
    var kind: ProviderKind = .yandex
    var endpoint = "https://api.music.yandex.net"
    var streamAPI: YandexMusicService.StreamAPI = .automatic

    var credentialID: String {
        let digest = SHA256.hash(data: Data("\(kind.rawValue):\(endpoint)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    func validatedURL() throws -> URL {
        guard let url = URL(string: endpoint), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw MusicServiceError.message("Введите HTTPS-адрес API без логина, пароля и параметров запроса.")
        }
        return url
    }
}

@MainActor
final class ProviderSettings: ObservableObject {
    @Published private(set) var configuration: ProviderConfiguration
    @Published private(set) var generation = UUID()
    init() {
        if let data = UserDefaults.standard.data(forKey: "provider-configuration"),
           var configuration = try? JSONDecoder().decode(ProviderConfiguration.self, from: data) {
            // 0.3 persisted File info as a normal choice even though its raw
            // encraw output may require remuxing before AVPlayer can open it.
            if configuration.kind == .yandex, configuration.streamAPI == .modern,
               !UserDefaults.standard.bool(forKey: "did-migrate-stream-api-0.4") {
                configuration.streamAPI = .automatic
                if let migrated = try? JSONEncoder().encode(configuration) {
                    UserDefaults.standard.set(migrated, forKey: "provider-configuration")
                }
            }
            UserDefaults.standard.set(true, forKey: "did-migrate-stream-api-0.4")
            self.configuration = configuration
        } else { configuration = ProviderConfiguration() }
    }
    func apply(_ configuration: ProviderConfiguration) throws {
        if configuration.kind != .demo { _ = try configuration.validatedURL() }
        let data = try JSONEncoder().encode(configuration)
        UserDefaults.standard.set(data, forKey: "provider-configuration")
        self.configuration = configuration
        generation = UUID()
    }
    func reloadSession() { generation = UUID() }
}
