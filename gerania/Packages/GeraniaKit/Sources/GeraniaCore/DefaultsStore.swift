import Foundation

/// Small typed wrapper around `UserDefaults` so settings code does not repeat casting.
struct DefaultsStore {
    let defaults: UserDefaults

    func string(_ key: String) -> String? {
        defaults.object(forKey: key) as? String
    }

    func bool(_ key: String) -> Bool? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    func int(_ key: String) -> Int? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    func double(_ key: String) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    func stringArray(_ key: String) -> [String]? {
        defaults.object(forKey: key) as? [String]
    }

    func set(_ value: Any?, for key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
