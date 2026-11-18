import Foundation

/// Whether a provider has the key Hermes needs for it.
///
/// Gerania never reads the values: only the variable names of `~/.hermes/.env`
/// and the process environment are compared with the known names of a provider.
public struct ProviderCredentialStatus: Sendable, Equatable {
    public let provider: String
    /// Environment variables any of which Hermes accepts for this provider.
    public let requiredNames: [String]
    public let isConfigured: Bool

    public init(provider: String, requiredNames: [String], isConfigured: Bool) {
        self.provider = provider
        self.requiredNames = requiredNames
        self.isConfigured = isConfigured
    }

    /// Names to show when the key is missing.
    public var missingLabel: String? {
        guard !isConfigured, let first = requiredNames.first else { return nil }
        return requiredNames.count == 1 ? first : "\(first) или \(requiredNames.dropFirst().joined(separator: " / "))"
    }
}

public enum ProviderCredentials {
    /// Path of the Hermes environment file. Read-only.
    public static func envFileURL(homeDirectory: String) -> URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".hermes")
            .appendingPathComponent(".env")
    }

    /// Names of the non-empty variables in the Hermes environment.
    ///
    /// Values are dropped during parsing and never leave this function.
    public static func configuredNames(
        homeDirectory: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Set<String> {
        var names = processNames(environment)
        guard let contents = try? String(
            contentsOf: envFileURL(homeDirectory: homeDirectory),
            encoding: .utf8
        ) else {
            return names
        }
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("export ") {
                text.removeFirst("export ".count)
            }
            guard !text.hasPrefix("#"), let equals = text.firstIndex(of: "=") else { continue }
            let name = text[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = text[text.index(after: equals)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !name.isEmpty, !value.isEmpty,
                  name.hasSuffix("_API_KEY") || name.hasSuffix("_KEY") || name.hasSuffix("_TOKEN")
            else {
                continue
            }
            names.insert(name)
        }
        return names
    }

    /// The status of one provider.
    public static func status(
        provider: String,
        homeDirectory: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProviderCredentialStatus {
        let name = normalize(provider)
        let required = requiredNames(for: name)
        if required.isEmpty {
            return ProviderCredentialStatus(provider: name, requiredNames: [], isConfigured: true)
        }
        let configured = configuredNames(homeDirectory: homeDirectory, environment: environment)
        return ProviderCredentialStatus(
            provider: name,
            requiredNames: required,
            isConfigured: required.contains { configured.contains($0) }
        )
    }

    /// Variables any of which Hermes accepts for the provider.
    ///
    /// An empty list means no key is needed: an unknown provider is not nagged
    /// about, and local models never have one.
    public static func requiredNames(for provider: String) -> [String] {
        switch normalize(provider) {
        case "gemini", "google":
            ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GENERATIVE_AI_API_KEY"]
        case "openrouter":
            ["OPENROUTER_API_KEY"]
        case "zai", "zhipu", "glm":
            ["ZHIPU_API_KEY", "ZAI_API_KEY", "GLM_API_KEY"]
        case "kimi", "moonshot":
            ["MOONSHOT_API_KEY", "KIMI_API_KEY"]
        case "nvidia":
            ["NVIDIA_API_KEY"]
        case "deepseek":
            ["DEEPSEEK_API_KEY"]
        case "xai":
            ["XAI_API_KEY"]
        case "groq":
            ["GROQ_API_KEY"]
        case "cerebras":
            ["CEREBRAS_API_KEY"]
        case "minimax":
            ["MINIMAX_API_KEY"]
        case "openai":
            ["OPENAI_API_KEY"]
        case "anthropic":
            ["ANTHROPIC_API_KEY"]
        default:
            []
        }
    }

    private static func normalize(_ provider: String) -> String {
        provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func processNames(_ environment: [String: String]) -> Set<String> {
        var names: Set<String> = []
        for (name, value) in environment where !value.isEmpty {
            guard name.hasSuffix("_API_KEY") || name.hasSuffix("_KEY") || name.hasSuffix("_TOKEN") else {
                continue
            }
            names.insert(name)
        }
        return names
    }
}
