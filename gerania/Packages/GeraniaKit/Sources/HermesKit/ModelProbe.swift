import Foundation
import GeraniaCore

/// Result of one test request to a model.
public struct ModelProbeResult: Sendable, Equatable {
    public let candidate: ModelCandidate
    public let isSuccess: Bool
    /// Short answer of the model or the human-readable reason of the failure.
    public let detail: String
    /// Cooldown class when the model refused, for the router and the badges.
    public let issue: ModelHealthIssue?

    public init(candidate: ModelCandidate, isSuccess: Bool, detail: String, issue: ModelHealthIssue? = nil) {
        self.candidate = candidate
        self.isSuccess = isSuccess
        self.detail = detail
        self.issue = issue
    }
}

/// Asks a model a tiny question through Hermes and reports whether it answered.
///
/// The probe is the same path as a real turn: `hermes -z` with the selected
/// provider and model. It creates a session titled `gerania-probe`, so the
/// Hermes history clearly marks these test turns.
public actor ModelProbe {
    private let config: HermesConfig

    public init(config: HermesConfig) {
        self.config = config
    }

    public func check(_ candidate: ModelCandidate, timeout: TimeInterval = 45) async -> ModelProbeResult {
        let transport = OneShotTransport(config: probeConfig(for: candidate))
        let started = Date()
        var streamed = ""

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await transport.close()
        }
        defer { timeoutTask.cancel() }

        do {
            for try await event in transport.send(
                "gerania-probe: проверка модели. Ответь одним словом: ок",
                session: nil,
                mode: .text
            ) {
                switch event {
                case let .textDelta(text):
                    streamed += text
                case let .completed(finalText):
                    let answer = (finalText ?? streamed)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return ModelProbeResult(
                        candidate: candidate,
                        isSuccess: true,
                        detail: answer.isEmpty ? "Модель ответила" : String(answer.prefix(80))
                    )
                case let .failed(error):
                    return failure(candidate: candidate, error: error)
                case .cancelled:
                    let elapsed = Date().timeIntervalSince(started)
                    let reason = elapsed >= timeout - 2
                        ? "Нет ответа за \(Int(timeout)) с"
                        : "Проверка отменена"
                    return ModelProbeResult(candidate: candidate, isSuccess: false, detail: reason)
                default:
                    break
                }
            }
        } catch {
            return ModelProbeResult(
                candidate: candidate,
                isSuccess: false,
                detail: error.localizedDescription
            )
        }

        let elapsed = Date().timeIntervalSince(started)
        let reason = elapsed >= timeout - 2
            ? "Нет ответа за \(Int(timeout)) с"
            : "Модель закрыла поток без ответа"
        return ModelProbeResult(candidate: candidate, isSuccess: false, detail: reason)
    }

    private func probeConfig(for candidate: ModelCandidate) -> HermesConfig {
        var probe = config
        probe.provider = candidate.provider
        probe.model = candidate.model
        probe.voicePromptPrefix = ""
        probe.textPromptPrefix = ""
        return probe
    }

    private func failure(candidate: ModelCandidate, error: HermesError) -> ModelProbeResult {
        ModelProbeResult(
            candidate: candidate,
            isSuccess: false,
            detail: error.localizedDescription,
            issue: ModelHealthStore.issue(for: error)
        )
    }
}
