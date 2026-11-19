import Foundation
import Security

/// Files and key of the Picovoice wake word («Гера») and of the owner voice.
///
/// The AccessKey lives in the Keychain; the keyword (`.ppn`), the Russian model
/// (`.pv`) and the voice profile live in `~/Library/Application Support/Gerania/Wake`.
/// The ears get them through the environment, never through argv.
public enum WakeEngine {
    public static let keychainService = "Gerania.Picovoice"
    public static let keychainAccount = "access-key"

    public static let keywordFileName = "gera.ppn"
    public static let modelFileName = "porcupine_params_ru.pv"
    public static let ownerProfileFileName = "owner.eagle"

    public static func directory(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent("Library/Application Support/Gerania/Wake", isDirectory: true)
    }

    public static func keywordURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        directory(homeDirectory: homeDirectory).appendingPathComponent(keywordFileName)
    }

    public static func modelURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        directory(homeDirectory: homeDirectory).appendingPathComponent(modelFileName)
    }

    public static func ownerProfileURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        directory(homeDirectory: homeDirectory).appendingPathComponent(ownerProfileFileName)
    }

    /// What is ready, for the settings and the wizard.
    public struct Status: Sendable, Equatable {
        public var hasKey: Bool
        public var hasKeyword: Bool
        public var hasModel: Bool
        public var hasOwnerProfile: Bool

        public var keywordReady: Bool {
            hasKey && hasKeyword && hasModel
        }

        /// What is missing for the wake word, in the words of the settings.
        public var missing: [String] {
            var items: [String] = []
            if !hasKey {
                items.append("ключ Picovoice")
            }
            if !hasKeyword {
                items.append("файл слова «Гера» (.ppn)")
            }
            if !hasModel {
                items.append("русская модель (.pv)")
            }
            return items
        }
    }

    public static func status(homeDirectory: String = NSHomeDirectory()) -> Status {
        let files = FileManager.default
        return Status(
            hasKey: accessKey() != nil,
            hasKeyword: files.fileExists(atPath: keywordURL(homeDirectory: homeDirectory).path),
            hasModel: files.fileExists(atPath: modelURL(homeDirectory: homeDirectory).path),
            hasOwnerProfile: files.fileExists(atPath: ownerProfileURL(homeDirectory: homeDirectory).path)
        )
    }

    /// Copies a file the person picked into the wake folder under its fixed name.
    public static func install(_ source: URL, as destination: URL) throws {
        let files = FileManager.default
        try files.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if files.fileExists(atPath: destination.path) {
            try files.removeItem(at: destination)
        }
        try files.copyItem(at: source, to: destination)
    }

    /// Environment of the ears: the key and the paths of the files that exist.
    public static func environment(
        sensitivity: Double,
        ownerThreshold: Double,
        homeDirectory: String = NSHomeDirectory()
    ) -> [String: String] {
        var values: [String: String] = [
            "GERA_WAKE_SENSITIVITY": String(format: "%.2f", sensitivity),
            "GERA_OWNER_THRESHOLD": String(format: "%.2f", ownerThreshold),
        ]
        if let key = accessKey() {
            values["GERA_PV_ACCESS_KEY"] = key
        }
        let files = FileManager.default
        let paths = [
            ("GERA_WAKE_KEYWORD", keywordURL(homeDirectory: homeDirectory)),
            ("GERA_WAKE_MODEL", modelURL(homeDirectory: homeDirectory)),
            ("GERA_OWNER_PROFILE", ownerProfileURL(homeDirectory: homeDirectory)),
        ]
        for (name, url) in paths where files.fileExists(atPath: url.path) {
            values[name] = url.path
        }
        return values
    }

    // MARK: - Keychain

    public static func accessKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else {
            return nil
        }
        return key
    }

    public static func saveAccessKey(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        _ = SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WakeEngineError.keychain(status)
        }
    }
}

public enum WakeEngineError: Error, LocalizedError, Equatable {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .keychain(status):
            "Не удалось сохранить ключ Picovoice в Связке ключей (код \(status))."
        }
    }
}
