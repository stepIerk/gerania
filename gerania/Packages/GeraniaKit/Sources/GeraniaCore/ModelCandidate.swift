import Foundation

/// One model a turn can run on: the Hermes provider and the model id.
///
/// The user writes it as `provider:model`, for example
/// `gemini:gemini-2.5-flash-lite` or `openrouter:google/gemma-4-31b-it:free`.
/// A string without a provider prefix keeps the provider from the settings, so
/// the lists saved before the router existed continue to work.
public struct ModelCandidate: Hashable, Sendable, Identifiable, Codable {
    public let provider: String
    public let model: String

    /// Stable key for caches, health records and SwiftUI lists.
    public var id: String {
        "\(provider):\(model)"
    }

    /// What the user sees when the provider is already clear from the context.
    public var displayName: String {
        model
    }

    /// `openrouter · gemma-4-31b-it:free` — for rows where both parts matter.
    public var fullName: String {
        "\(provider) · \(model)"
    }

    public init(provider: String, model: String) {
        self.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses `provider:model`.
    ///
    /// Only the first colon separates the provider: OpenRouter model ids carry
    /// their own colons (`...:free`) and local Ollama tags use one as well.
    /// A prefix with a slash is a model id, not a provider, so
    /// `google/gemma-4-31b-it:free` stays a model of the default provider.
    ///
    /// Without a known prefix the whole text is a model id. That keeps Ollama
    /// tags such as `qwen3:8b` working when the default provider is `ollama`.
    public init?(
        raw: String,
        defaultProvider: String,
        knownProviders: Set<String> = ModelCandidate.defaultProviderNames
    ) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        guard let colon = text.firstIndex(of: ":") else {
            guard let fallback = Self.wholeText(text, provider: defaultProvider) else { return nil }
            self = fallback
            return
        }

        let prefix = String(text[..<colon])
        let model = String(text[text.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = Self.normalizedProvider(prefix)
        let looksLikeProvider = Self.isProviderName(provider)
            && (knownProviders.contains(provider) || model.contains("/"))

        guard looksLikeProvider, !model.isEmpty else {
            guard let fallback = Self.wholeText(text, provider: defaultProvider) else { return nil }
            self = fallback
            return
        }
        self.init(provider: provider, model: model)
    }

    private static func wholeText(_ text: String, provider: String) -> ModelCandidate? {
        let provider = normalizedProvider(provider)
        guard !provider.isEmpty else { return nil }
        return ModelCandidate(provider: provider, model: text)
    }

    private static func normalizedProvider(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Provider ids are short, lowercase and have no path separators.
    static func isProviderName(_ value: String) -> Bool {
        guard (1 ... 32).contains(value.count) else { return false }
        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }

    /// Providers the router understands without asking the model catalog.
    ///
    /// A custom provider still works when its model id contains a slash, for
    /// example `my-gateway:org/model`.
    public static let defaultProviderNames: Set<String> = [
        "anthropic", "cerebras", "custom", "deepseek", "gemini", "google",
        "groq", "kimi", "lmstudio", "minimax", "moonshot", "nvidia",
        "ollama", "openai", "openrouter", "xai", "zai", "zhipu",
    ]
}
