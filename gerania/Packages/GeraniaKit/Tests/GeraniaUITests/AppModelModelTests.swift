import Foundation
import GeraniaCore
@testable import GeraniaUI
import Testing

@Suite("Модели в AppModel")
@MainActor
struct AppModelModelTests {
    private func model(candidates: [String] = [], primary: String = "gemini-2.5-flash-lite") -> AppModel {
        let defaults = UserDefaults(suiteName: "GeraniaUITests-\(UUID().uuidString)") ?? .standard
        let settings = GeraSettings(defaults: defaults)
        settings.model = primary
        settings.modelCandidates = candidates
        return AppModel(settings: settings)
    }

    @Test("Без списка используется основная модель")
    func singleModel() {
        let model = model()

        #expect(model.modelCandidates == ["gemini-2.5-flash-lite"])
    }

    @Test("Список моделей перебирается по порядку")
    func candidateOrder() {
        let model = model(candidates: ["gemini-3.5-flash", "gemini-3.8-flash"])

        #expect(model.modelCandidates == ["gemini-3.5-flash", "gemini-3.8-flash"])
    }

    @Test("Пустые строки в списке игнорируются")
    func emptyEntriesIgnored() {
        let model = model(candidates: ["  ", "gemini-3.5-flash", ""])

        #expect(model.modelCandidates == ["gemini-3.5-flash"])
    }

    @Test("Провайдер в строке переопределяет настройки")
    func providerPrefix() {
        let model = model(
            candidates: ["gemini:gemini-2.5-flash", "openrouter:google/gemma-4-31b-it:free"],
            primary: "ignored"
        )

        #expect(model.candidateModels.map(\.provider) == ["gemini", "openrouter"])
        #expect(model.candidateModels.map(\.model) == ["gemini-2.5-flash", "google/gemma-4-31b-it:free"])
        #expect(model.primaryCandidate.id == "gemini:gemini-2.5-flash")
    }

    @Test("Без списка основная модель берёт провайдера из настроек")
    func primaryFallsBackToSettings() {
        let model = model(primary: "gemini-2.5-flash-lite")

        #expect(model.primaryCandidate.provider == "gemini")
        #expect(model.primaryCandidate.model == "gemini-2.5-flash-lite")
    }

    @Test("Дубликаты не перебираются дважды")
    func duplicatesRemoved() {
        let model = model(
            candidates: ["gemini:gemini-2.5-flash", "gemini-2.5-flash"],
            primary: "ignored"
        )

        #expect(model.candidateModels.count == 1)
    }

    @Test("Ошибка ключа объясняется по-человечески")
    func authMessage() {
        let model = model()

        let message = model.friendlyMessage(for: .protocolError("401 invalid_api_key"))

        #expect(message.contains("ключ"))
        #expect(message.contains("~/.hermes/.env"))
    }

    @Test("Пропавшая модель объясняется по-человечески")
    func missingModelMessage() {
        let model = model()

        let message = model.friendlyMessage(for: .protocolError("model_not_found"))

        #expect(message.contains("модели нет"))
    }

    @Test("Остывающая модель уходит в конец списка")
    func coolingDownLast() async {
        let model = model(candidates: ["gemini:gemini-2.5-flash", "openrouter:openrouter/free"])
        let cooling = ModelCandidate(provider: "gemini", model: "gemini-2.5-flash")

        await model.modelHealth.markFailure(cooling, error: .protocolError("429 quota"))

        let ordered = await model.orderedCandidates()
        #expect(ordered.map(\.id) == ["openrouter:openrouter/free", "gemini:gemini-2.5-flash"])
    }

    @Test("Если остывают все, список не пустеет")
    func allCoolingKeepsCandidates() async {
        let model = model(candidates: ["gemini:gemini-2.5-flash", "openrouter:openrouter/free"])
        for candidate in model.candidateModels {
            await model.modelHealth.markFailure(candidate, error: .protocolError("invalid_api_key"))
        }

        let ordered = await model.orderedCandidates()
        #expect(ordered.map(\.id) == model.candidateModels.map(\.id))
    }
}
