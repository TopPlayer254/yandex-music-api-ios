import CryptoKit
import Foundation
import Security

struct OAuthToken: Codable, Equatable, Sendable {
    let accessToken: String
    let tokenType: String
    let refreshToken: String?
    let expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(30)
    }
}

struct BackendSession: Codable, Equatable, Sendable {
    let accessToken: String
    let expiresAt: Date
    let userID: String

    var isExpired: Bool {
        expiresAt <= Date().addingTimeInterval(30)
    }
}

private enum KeychainCodableStore {
    static func load<Value: Decodable>(service: String, account: String, as type: Value.Type) throws -> Value? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AuthError.keychain(status)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    static func save<Value: Encodable>(_ value: Value, service: String, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AuthError.keychain(updateStatus)
        }
        var insert = query
        attributes.forEach { insert[$0.key] = $0.value }
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else { throw AuthError.keychain(insertStatus) }
    }

    static func clear(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.keychain(status)
        }
    }
}

private enum ProtectedFileCodableStore {
    static func load<Value: Decodable>(service: String, account: String, as type: Value.Type) throws -> Value? {
        let url = try fileURL(service: service, account: account)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    static func save<Value: Encodable>(_ value: Value, service: String, account: String) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(
            to: fileURL(service: service, account: account),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    static func clear(service: String, account: String) throws {
        let url = try fileURL(service: service, account: account)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func fileURL(service: String, account: String) throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Credentials", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data("\(service):\(account)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return root.appendingPathComponent(digest).appendingPathExtension("json")
    }
}

actor KeychainTokenVault {
    private let service = "com.hikeri.yamusic.oauth"
    private let legacyService = "app.maplemusic.oauth"
    private let account: String

    init(account: String = "yandex-token") { self.account = account }

    func load() throws -> OAuthToken? {
        // The protected app-container copy is the source of truth for sideloads:
        // some signing methods accept SecItemAdd but fail the next read.
        do {
            if let token = try ProtectedFileCodableStore.load(service: service, account: account, as: OAuthToken.self) {
                return token
            }
        } catch {
            try? ProtectedFileCodableStore.clear(service: service, account: account)
        }
        for candidate in [service, legacyService] {
            do {
                if let token = try KeychainCodableStore.load(service: candidate, account: account, as: OAuthToken.self) {
                    try? ProtectedFileCodableStore.save(token, service: service, account: account)
                    if candidate == legacyService {
                        try? KeychainCodableStore.save(token, service: service, account: account)
                    }
                    return token
                }
            } catch {
                // Unsigned and sideloaded builds can receive errSecParam or
                // errSecMissingEntitlement here. The protected app file below
                // keeps sign-in usable without exposing the token in Documents.
            }
        }
        return nil
    }

    func save(_ token: OAuthToken) throws {
        try ProtectedFileCodableStore.save(token, service: service, account: account)
        try? KeychainCodableStore.save(token, service: service, account: account)
    }

    func clear() throws {
        try? KeychainCodableStore.clear(service: service, account: account)
        try? KeychainCodableStore.clear(service: legacyService, account: account)
        try ProtectedFileCodableStore.clear(service: service, account: account)
    }
}

actor BackendSessionVault {
    private let service = "com.hikeri.yamusic.backend-session"
    private let account = "current-session"

    func load() throws -> BackendSession? {
        do {
            if let session = try ProtectedFileCodableStore.load(service: service, account: account, as: BackendSession.self) {
                return session
            }
        } catch {
            try? ProtectedFileCodableStore.clear(service: service, account: account)
        }
        do {
            if let session = try KeychainCodableStore.load(service: service, account: account, as: BackendSession.self) {
                try? ProtectedFileCodableStore.save(session, service: service, account: account)
                return session
            }
        } catch { }
        return nil
    }

    func save(_ session: BackendSession) throws {
        try ProtectedFileCodableStore.save(session, service: service, account: account)
        try? KeychainCodableStore.save(session, service: service, account: account)
    }

    func clear() throws {
        try? KeychainCodableStore.clear(service: service, account: account)
        try ProtectedFileCodableStore.clear(service: service, account: account)
    }
}
