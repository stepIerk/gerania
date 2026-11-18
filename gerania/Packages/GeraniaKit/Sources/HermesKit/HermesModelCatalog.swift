import Foundation

/// Models the Hermes agent knows about.
///
/// Hermes caches the live model list of every provider in
/// `~/.hermes/provider_models_cache.json`; Gerania reads it (read-only) to offer a list
/// in the settings instead of asking the user to type the model ids by hand.
public enum HermesModelCatalog {
    /// Models of one provider.
    public struct Provider: Sendable, Equatable {
        public let name: String
        public let models: [String]

        public init(name: String, models: [String]) {
            self.name = name
            self.models = models
        }
    }

    /// Path of the cache file.
    public static func cacheURL(homeDirectory: String) -> URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".hermes")
            .appendingPathComponent("provider_models_cache.json")
    }

    /// All providers with their models.
    public static func providers(homeDirectory: String) -> [Provider] {
        let url = cacheURL(homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }
        return payload.compactMap { name, entry -> Provider? in
            guard let entry = entry as? [String: Any],
                  let models = entry["models"] as? [String],
                  !models.isEmpty
            else {
                return nil
            }
            return Provider(name: name, models: models.sorted())
        }
        .sorted { $0.name < $1.name }
    }

    /// Models of the given provider; when the provider is unknown — all of them.
    public static func models(homeDirectory: String, provider: String) -> [String] {
        let all = providers(homeDirectory: homeDirectory)
        let wanted = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !wanted.isEmpty, wanted != "auto", let match = all.first(where: { $0.name.lowercased() == wanted }) {
            return match.models
        }
        var models = all.flatMap(\.models)
        models = Array(Set(models)).sorted()
        return models
    }
}
