import Foundation

/// What Gerania knows about a model without asking the provider.
///
/// The data comes from the read-only Hermes cache `~/.hermes/models_dev_cache.json`.
/// A model missing from the cache is still usable: the capabilities are just unknown.
public struct ModelCapabilities: Hashable, Sendable {
    public let provider: String
    public let model: String
    public let title: String?
    /// The provider does not charge per token: a `:free` model or a local one.
    public let isFree: Bool
    public let supportsTools: Bool
    public let supportsVision: Bool
    public let contextTokens: Int?
    public let isLocal: Bool

    public init(
        provider: String,
        model: String,
        title: String? = nil,
        isFree: Bool = false,
        supportsTools: Bool = false,
        supportsVision: Bool = false,
        contextTokens: Int? = nil,
        isLocal: Bool = false
    ) {
        self.provider = provider
        self.model = model
        self.title = title
        self.isFree = isFree
        self.supportsTools = supportsTools
        self.supportsVision = supportsVision
        self.contextTokens = contextTokens
        self.isLocal = isLocal
    }

    /// Compact context size for a badge: `1M`, `262K`.
    public var contextLabel: String? {
        guard let contextTokens, contextTokens > 0 else { return nil }
        if contextTokens >= 1_000_000 {
            let millions = Double(contextTokens) / 1_000_000
            let rounded = millions.rounded()
            return abs(millions - rounded) < 0.05
                ? "\(Int(rounded))M"
                : String(format: "%.1fM", millions)
        }
        if contextTokens >= 1000 {
            return "\(contextTokens / 1000)K"
        }
        return "\(contextTokens)"
    }
}

/// Loads `ModelCapabilities` from the Hermes model catalog.
///
/// The catalog is a few megabytes of JSON, so parsing happens off the main actor
/// once and stays in memory until the settings ask for a reload.
public actor ModelCapabilitiesStore {
    public static let catalogFileName = "models_dev_cache.json"

    private let homeDirectory: String
    private var catalog: [String: ModelCapabilities]?

    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    /// Path of the Hermes catalog. Read-only.
    public nonisolated func catalogURL() -> URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".hermes")
            .appendingPathComponent(Self.catalogFileName)
    }

    public func capabilities(for candidate: ModelCandidate) -> ModelCapabilities? {
        let all = loadIfNeeded()
        return all[Self.key(provider: candidate.provider, model: candidate.model)]
    }

    /// Every model of the catalog, sorted by provider and model.
    public func allCapabilities() -> [ModelCapabilities] {
        loadIfNeeded().values.sorted {
            ($0.provider, $0.model) < ($1.provider, $1.model)
        }
    }

    /// Drops the parsed catalog; the next request reads the file again.
    public func reload() {
        catalog = nil
    }

    private func loadIfNeeded() -> [String: ModelCapabilities] {
        if let catalog {
            return catalog
        }
        let parsed = Self.load(from: catalogURL())
        catalog = parsed
        return parsed
    }

    /// Reads and parses the catalog. A missing or broken file yields an empty map.
    public nonisolated static func load(from url: URL) -> [String: ModelCapabilities] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return parse(data)
    }

    /// Parses the `models.dev` catalog.
    ///
    /// The file is an object of providers; every provider keeps its models in a
    /// dictionary keyed by the model id.
    public nonisolated static func parse(_ data: Data) -> [String: ModelCapabilities] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: ModelCapabilities] = [:]
        for (providerID, rawProvider) in root {
            guard let provider = rawProvider as? [String: Any],
                  let models = provider["models"] as? [String: Any]
            else {
                continue
            }
            for (modelID, rawModel) in models {
                guard let model = rawModel as? [String: Any] else { continue }
                let capabilities = capabilities(provider: providerID, modelID: modelID, raw: model)
                result[key(provider: providerID, model: modelID)] = capabilities
            }
        }
        return result
    }

    private nonisolated static func capabilities(
        provider providerID: String,
        modelID: String,
        raw: [String: Any]
    ) -> ModelCapabilities {
        let provider = normalizeProvider(providerID)
        let local = isLocalProvider(provider)
        let cost = raw["cost"] as? [String: Any]
        let inputCost = number(cost?["input"]) ?? 0
        let outputCost = number(cost?["output"]) ?? 0
        let free = local
            || modelID.lowercased().hasSuffix(":free")
            || (cost != nil && inputCost == 0 && outputCost == 0)

        let modalities = (raw["modalities"] as? [String: Any])?["input"] as? [String] ?? []
        let context = (raw["limit"] as? [String: Any])?["context"].flatMap(number).map { Int($0) }

        return ModelCapabilities(
            provider: provider,
            model: modelID,
            title: raw["name"] as? String,
            isFree: free,
            supportsTools: raw["tool_call"] as? Bool ?? false,
            supportsVision: modalities.contains("image"),
            contextTokens: context,
            isLocal: local
        )
    }

    private nonisolated static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        default: nil
        }
    }

    /// Hermes provider ids and the catalog ids are not always the same.
    public nonisolated static func normalizeProvider(_ provider: String) -> String {
        switch provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "gemini", "google-ai": "google"
        case "kimi", "moonshot": "moonshotai"
        case "glm", "zhipu": "zai"
        case "local": "lmstudio"
        case let value: value
        }
    }

    /// Providers that run on the user's machine and never bill per token.
    public nonisolated static func isLocalProvider(_ provider: String) -> Bool {
        ["ollama", "lmstudio"].contains(provider.lowercased())
    }

    private nonisolated static func key(provider: String, model: String) -> String {
        "\(normalizeProvider(provider)):\(model.lowercased())"
    }
}
