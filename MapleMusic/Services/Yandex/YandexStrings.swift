import Foundation

enum YandexStrings {
    static var shadowBanTitle: String {
        NSLocalizedString("yandex.wave.shadow_ban.title", comment: "My Wave shadow-ban title")
    }

    static var shadowBanMessage: String {
        NSLocalizedString("yandex.wave.shadow_ban.message", comment: "My Wave shadow-ban explanation")
    }

    static var loginCanceled: String {
        NSLocalizedString("yandex.login.canceled", comment: "Yandex ID login canceled")
    }

    static var loginExpired: String {
        NSLocalizedString("yandex.login.expired", comment: "Yandex ID device code expired")
    }

    static func loginRejected(_ detail: String?) -> String {
        guard let detail, !detail.isEmpty else {
            return NSLocalizedString("yandex.login.rejected", comment: "Yandex ID login rejected")
        }
        return String(
            format: NSLocalizedString("yandex.login.rejected.detail", comment: "Yandex ID detailed rejection"),
            detail
        )
    }

    static func readableLoginError(code: String?, detail: String?) -> String {
        let normalized = [code, detail]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if normalized.contains("отмен")
            || normalized.contains("cancel")
            || normalized.contains("access_denied")
            || normalized.contains("authorization_declined") {
            return loginCanceled
        }
        if normalized.contains("expired") || normalized.contains("истек") {
            return loginExpired
        }
        return loginRejected(detail ?? code)
    }
}
