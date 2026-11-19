import Foundation
import GeraniaCore
import HermesKit

/// The free-model router: which model answers, which one is skipped and why.
extension AppModel {
    /// Модели, которые перебираются по очереди.
    var modelCandidates: [String] {
        let candidates = settings.modelCandidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return candidates.isEmpty ? [settings.model] : candidates
    }

    /// The same list parsed into provider and model, without duplicates.
    var candidateModels: [ModelCandidate] {
        var seen: Set<String> = []
        let parsed = modelCandidates.compactMap {
            ModelCandidate(raw: $0, defaultProvider: settings.provider)
        }
        return parsed.filter { seen.insert($0.id).inserted }
    }

    var primaryCandidate: ModelCandidate {
        candidateModels.first ?? ModelCandidate(provider: settings.provider, model: settings.model)
    }

    /// Healthy models first, cooling ones last.
    ///
    /// When every candidate is cooling down the list is still returned in order:
    /// a stale cooldown must not leave the user without an answer.
    func orderedCandidates() async -> [ModelCandidate] {
        let all = candidateModels
        var healthy: [ModelCandidate] = []
        var cooling: [ModelCandidate] = []
        for candidate in all {
            if await modelHealth.isCoolingDown(candidate) {
                cooling.append(candidate)
            } else {
                healthy.append(candidate)
            }
        }
        return healthy + cooling
    }

    /// Clears the partial answer of the failed model before the next attempt.
    func prepareFallback(to candidate: ModelCandidate) {
        hud.reset()
        hud.modelLabel = candidate.model
        hud.showsModel = settings.showActiveModelInHUD
        apply(state: .thinking(tools: []))
        showHint("Запасная модель: \(candidate.model)")
    }

    func makeTransport(_ candidate: ModelCandidate? = nil) async throws -> TransportManager {
        let wanted = candidate ?? primaryCandidate
        if let transport, transportKind == settings.transport, activeCandidate?.id == wanted.id {
            return transport
        }
        await transport?.close()
        let manager = TransportManager(config: makeConfig(wanted), kind: settings.transport)
        transport = manager
        transportKind = settings.transport
        activeCandidate = wanted
        return manager
    }

    func makeConfig(_ candidate: ModelCandidate) -> HermesConfig {
        HermesConfig(
            hermesPath: settings.hermesPath,
            provider: candidate.provider,
            model: candidate.model,
            workdir: settings.workdir,
            voicePromptPrefix: settings.voicePromptPrefix,
            textPromptPrefix: settings.textPromptPrefix
        )
    }

    /// Человеческое сообщение об ошибке вместо технического текста провайдера.
    func friendlyMessage(for error: HermesError) -> String {
        if NetworkStatus.shared.isOffline {
            return NetworkStatus.offlineMessage
        }
        let models = modelCandidates
        let list = models.isEmpty ? "" : " Проверено: \(models.joined(separator: " → "))."
        if error.isAuthFailure {
            return "Провайдер не принял ключ. Проверьте ключ в ~/.hermes/.env или выберите другую модель." + list
        }
        if error.isModelMissing {
            return "Такой модели нет у провайдера — проверьте имя или выберите другую модель." + list
        }
        if error.isModelUnavailable {
            return "Лимит модели закончился — провайдер больше не отвечает на запросы."
                + " Добавьте запасную модель в настройках: Hermes → Модели." + list
        }
        return error.localizedDescription
    }
}
