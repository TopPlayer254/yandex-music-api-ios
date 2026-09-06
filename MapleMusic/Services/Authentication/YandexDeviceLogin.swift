import AuthenticationServices
import Combine
import Foundation
import UIKit

@MainActor
final class YandexDeviceLogin: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var userCode: String?
    @Published private(set) var verificationURL: URL?
    @Published private(set) var isRunning = false
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var webSession: ASWebAuthenticationSession?
    private var webSessionID: UUID?
    // Public device-client parameters used by yandex-music-api; server acceptance
    // can change. An account token can also be entered directly in Settings.
    private let clientID = "23cabbbdc6cd418abb4b39c32c41195d"
    private let clientSecret = "53bc75238f0c4d08a118e51fe9203300"

    func start(receive: @escaping @MainActor (String) async -> Void) {
        cancel()
        isRunning = true
        error = nil
        task = Task {
            defer { isRunning = false }
            do {
                let code = try await post("device/code", fields: ["client_id": clientID,
                    // Match the device flow used by the first working build.
                    "device_id": UUID().uuidString, "device_name": "Maple Music"])
                guard let deviceCode = code["device_code"].string, let userCode = code["user_code"].string,
                      let raw = code["verification_url"].string ?? code["verification_uri"].string,
                      let url = URL(string: raw), url.scheme == "https",
                      ["oauth.yandex.ru", "oauth.yandex.com", "ya.ru", "passport.yandex.ru"].contains(url.host ?? "") else {
                    throw MusicServiceError.message("Вход по коду сейчас недоступен. Используйте токен доступа в настройках.")
                }
                self.userCode = userCode
                self.verificationURL = url
                openVerificationPage()
                let deadline = Date().addingTimeInterval(code["expires_in"].number ?? 600)
                var interval = max(code["interval"].number ?? 5, 5)
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(interval))
                    let result = try await post("token", fields: ["grant_type": "device_code", "code": deviceCode,
                        "client_id": clientID, "client_secret": clientSecret])
                    try Task.checkCancellation()
                    if let token = result["access_token"].string {
                        webSession?.cancel()
                        webSession = nil
                        webSessionID = nil
                        await receive(token)
                        return
                    }
                    switch result["error"].string {
                    case "authorization_pending": continue
                    case "slow_down": interval += 5
                    default:
                        let detail = result["error_description"].string ?? result["error"].string
                        throw MusicServiceError.message(detail.map { "Яндекс отклонил вход: \($0)" }
                            ?? "Вход отклонён или время ожидания истекло. Запросите новый код.")
                    }
                }
                throw MusicServiceError.message("Срок действия кода входа истёк.")
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    func cancel() {
        task?.cancel()
        task = nil
        webSession?.cancel()
        webSession = nil
        webSessionID = nil
        isRunning = false
        userCode = nil
        verificationURL = nil
    }

    func openVerificationPage() {
        guard let verificationURL else { return }
        webSession?.cancel()
        let sessionID = UUID()
        let session = ASWebAuthenticationSession(url: verificationURL, callbackURLScheme: nil) { [weak self] _, _ in
            Task { @MainActor in
                guard self?.webSessionID == sessionID else { return }
                self?.webSession = nil
                self?.webSessionID = nil
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        webSession = session
        webSessionID = sessionID
        if !session.start() {
            webSession = nil
            webSessionID = nil
            error = "Не удалось открыть временное окно Яндекс ID. Нажмите кнопку открытия ещё раз."
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        if let scene = scenes.first, let window = scene.windows.first { return window }
        return ASPresentationAnchor()
    }

    private func post(_ path: String, fields: [String: String]) async throws -> YandexJSON {
        var request = URLRequest(url: URL(string: "https://oauth.yandex.ru/\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 400 else {
            throw MusicServiceError.message("Сервер авторизации недоступен.")
        }
        return try JSONDecoder().decode(YandexJSON.self, from: data)
    }
}
