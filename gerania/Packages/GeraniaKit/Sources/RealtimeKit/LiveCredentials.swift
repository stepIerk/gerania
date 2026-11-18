import Foundation
import Security

/// Storage of the Gemini API key: the Keychain first, the environment for CLI probes.
public enum LiveCredentials {
    /// Service name of the Keychain item.
    public static let service = "Gerania.GeminiLive"
    /// Account name of the Keychain item.
    public static let account = "api-key"

    /// Returns the key from the environment or the Keychain.
    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        try? loadAPIKey(environment: environment)
    }

    /// Loads the key and reports why it is unavailable.
    public static func loadAPIKey(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        if let value = environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty
        {
            return value
        }
        return try readFromKeychain()
    }

    /// Stores the key in the Keychain.
    public static func saveAPIKey(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            try deleteAPIKey()
            return
        }
        guard let data = value.data(using: .utf8) else {
            throw LiveCredentialError.invalidValue
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw LiveCredentialError.keychain(status)
        }
        var item = query
        item.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw LiveCredentialError.keychain(addStatus)
        }
    }

    /// Removes the key from the Keychain.
    public static func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LiveCredentialError.keychain(status)
        }
    }

    /// Whether a key is configured.
    public static var isConfigured: Bool {
        apiKey()?.isEmpty == false
    }

    private static func readFromKeychain() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw LiveCredentialError.notConfigured
        default:
            throw LiveCredentialError.keychain(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw LiveCredentialError.notConfigured
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LiveCredentialError.notConfigured
        }
        return trimmed
    }
}

/// Errors of the API key storage.
public enum LiveCredentialError: Error, LocalizedError, Sendable, Equatable {
    case invalidValue
    case notConfigured
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidValue:
            "Некорректный ключ Gemini API"
        case .notConfigured:
            "Ключ Gemini не задан"
        case let .keychain(status):
            "Keychain не отдал ключ Gemini (\(status))"
        }
    }
}
