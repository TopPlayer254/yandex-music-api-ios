import Combine
import Foundation

@MainActor
final class DiagnosticLog: ObservableObject {
    static let shared = DiagnosticLog()
    @Published private(set) var lastResponse = "Ошибок в текущем сеансе пока нет."

    func record(path: String, status: Int, data: Data) {
        guard UserDefaults.standard.bool(forKey: "developer-literal-errors") else { return }
        // Only JSON is retained: HTML and arbitrary responses can embed credentials.
        let body: String
        if let json = try? JSONSerialization.jsonObject(with: data),
           let safe = try? JSONSerialization.data(withJSONObject: Self.redacted(json), options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: safe, encoding: .utf8) {
            body = String(text.prefix(16_384))
        } else { body = "Не-JSON ответ скрыт (\(data.count) байт)." }
        lastResponse = "HTTP \(status) · \(path.components(separatedBy: "?")[0])\n\n\(body)"
    }

    static func redacted(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues { child in redacted(child) }.reduce(into: [String: Any]()) { result, pair in
                let name = pair.key.lowercased()
                let sensitive = ["token", "cookie", "authorization", "password", "secret", "email", "login", "uid", "account", "url", "sign"]
                result[pair.key] = sensitive.contains(where: name.contains) ? "[скрыто]" : pair.value
            }
        }
        if let array = value as? [Any] { return array.map(redacted) }
        if let text = value as? String {
            return text.replacingOccurrences(of: "(?i)(?:OAuth|Bearer)\\s+[^\\s\"]+", with: "[скрыто]", options: .regularExpression)
        }
        return value
    }

    func clear() { lastResponse = "Диагностика очищена." }
}
