import Foundation
import GeraniaCore
import Testing

@Suite("Кандидаты моделей")
struct ModelCandidateTests {
    @Test("Провайдер и модель делятся по первому двоеточию")
    func providerAndModel() {
        let candidate = ModelCandidate(raw: "gemini:gemini-2.5-flash-lite", defaultProvider: "openrouter")

        #expect(candidate?.provider == "gemini")
        #expect(candidate?.model == "gemini-2.5-flash-lite")
        #expect(candidate?.id == "gemini:gemini-2.5-flash-lite")
    }

    @Test("Двоеточие в модели OpenRouter остаётся в модели")
    func openRouterFreeSuffix() {
        let candidate = ModelCandidate(
            raw: "openrouter:google/gemma-4-31b-it:free",
            defaultProvider: "gemini"
        )

        #expect(candidate?.provider == "openrouter")
        #expect(candidate?.model == "google/gemma-4-31b-it:free")
    }

    @Test("Тег Ollama остаётся в модели")
    func ollamaTag() {
        let candidate = ModelCandidate(raw: "ollama:qwen3:8b", defaultProvider: "gemini")

        #expect(candidate?.provider == "ollama")
        #expect(candidate?.model == "qwen3:8b")
    }

    @Test("Без провайдера берётся провайдер из настроек")
    func defaultProvider() {
        let candidate = ModelCandidate(raw: "gemini-2.5-flash", defaultProvider: "gemini")

        #expect(candidate?.provider == "gemini")
        #expect(candidate?.model == "gemini-2.5-flash")
    }

    @Test("Модель со слэшем не считается провайдером")
    func slashIsNotProvider() {
        let candidate = ModelCandidate(
            raw: "google/gemma-4-31b-it:free",
            defaultProvider: "openrouter"
        )

        #expect(candidate?.provider == "openrouter")
        #expect(candidate?.model == "google/gemma-4-31b-it:free")
    }

    @Test("Неизвестный провайдер без слэша не угадывается")
    func unknownPrefixStaysModel() {
        let candidate = ModelCandidate(raw: "qwen3:8b", defaultProvider: "ollama")

        #expect(candidate?.provider == "ollama")
        #expect(candidate?.model == "qwen3:8b")
    }

    @Test("Неизвестный провайдер со слэшем в модели работает")
    func customProvider() {
        let candidate = ModelCandidate(raw: "my-gateway:org/model", defaultProvider: "gemini")

        #expect(candidate?.provider == "my-gateway")
        #expect(candidate?.model == "org/model")
    }

    @Test("Пробелы и регистр провайдера нормализуются")
    func whitespaceAndCase() {
        let candidate = ModelCandidate(raw: "  GEMINI : Gemini-2.5-Flash-Lite ", defaultProvider: "openrouter")

        #expect(candidate?.provider == "gemini")
        #expect(candidate?.model == "Gemini-2.5-Flash-Lite")
    }

    @Test("Пустая строка не даёт кандидата")
    func emptyText() {
        #expect(ModelCandidate(raw: "   ", defaultProvider: "gemini") == nil)
        #expect(ModelCandidate(raw: "model", defaultProvider: "  ") == nil)
    }
}
