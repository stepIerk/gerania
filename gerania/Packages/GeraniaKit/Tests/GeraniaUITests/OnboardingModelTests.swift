import Foundation
import GeraniaCore
@testable import GeraniaUI
import Testing

@Suite("Мастер настройки: модель")
@MainActor
struct OnboardingModelTests {
    @Test("Быстрые проверки не трогают модель и показывают статусы")
    func checkAll() async throws {
        let calls = StepLog()
        let model = try makeModel(calls: calls) { step in
            step == .hermes ? .failed("нет") : .ok("ок")
        }

        await model.checkAll()

        #expect(await !calls.steps.contains(.model))
        #expect(await !calls.steps.contains(.tryIt))
        #expect(model.status(of: .hermes) == .failed("нет"))
        #expect(model.status(of: .scheduler) == .ok("ок"))
        #expect(model.status(of: .model) == .unknown)
        #expect(model.progress.blockers == [.hermes])
    }

    @Test("«Готово» запоминается и закрывает мастер")
    func finish() throws {
        let defaults = try #require(UserDefaults(suiteName: "GeraniaUITests-setup-\(UUID().uuidString)"))
        let model = OnboardingModel(
            settings: GeraSettings(defaults: defaults),
            probes: SetupProbes { _ in .ok("ок") },
            defaults: defaults
        )
        var finished = false
        model.onFinish = { finished = true }
        #expect(!OnboardingModel.isCompleted(defaults: defaults))

        model.finish()

        #expect(finished)
        #expect(OnboardingModel.isCompleted(defaults: defaults))
    }

    @Test("Пропуск шага двигает мастер дальше")
    func skip() throws {
        let model = try makeModel(calls: StepLog()) { _ in .ok("ок") }

        model.skip()

        #expect(model.status(of: .hermes) == .skipped)
        #expect(model.progress.current == .model)
    }

    private func makeModel(
        calls: StepLog,
        result: @escaping @Sendable (SetupStep) -> SetupStatus
    ) throws -> OnboardingModel {
        let defaults = try #require(UserDefaults(suiteName: "GeraniaUITests-setup-\(UUID().uuidString)"))
        return OnboardingModel(
            settings: GeraSettings(defaults: defaults),
            probes: SetupProbes { step in
                await calls.append(step)
                return result(step)
            },
            defaults: defaults
        )
    }
}

private actor StepLog {
    private(set) var steps: [SetupStep] = []

    func append(_ step: SetupStep) {
        steps.append(step)
    }
}
