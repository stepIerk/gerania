import Foundation
import GeraniaCore
import HermesKit
import Testing

@Suite("Здоровье моделей")
struct ModelHealthStoreTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("Исчерпанная квота остывает десять минут")
    func quotaCooldown() async {
        let clock = TestClock(now: start)
        let store = ModelHealthStore(now: { clock.now })
        let candidate = ModelCandidate(provider: "gemini", model: "gemini-2.5-flash-lite")

        let record = await store.markFailure(candidate, error: .protocolError("429 Too Many Requests"))

        #expect(record?.issue == .quota)
        #expect(record?.until == start.addingTimeInterval(600))
        #expect(await store.isCoolingDown(candidate))
    }

    @Test("Отклонённый ключ остывает сутки")
    func authCooldown() async {
        let clock = TestClock(now: start)
        let store = ModelHealthStore(now: { clock.now })
        let candidate = ModelCandidate(provider: "openrouter", model: "openrouter/free")

        let record = await store.markFailure(candidate, error: .protocolError("401 Unauthorized: invalid API key"))

        #expect(record?.issue == .auth)
        #expect(record?.until == start.addingTimeInterval(86400))
    }

    @Test("Пропавшая модель остывает полчаса")
    func missingCooldown() async {
        let clock = TestClock(now: start)
        let store = ModelHealthStore(now: { clock.now })
        let candidate = ModelCandidate(provider: "zai", model: "glm-4.7-flash")

        let record = await store.markFailure(candidate, error: .protocolError("404 model_not_found"))

        #expect(record?.issue == .missing)
        #expect(record?.until == start.addingTimeInterval(1800))
    }

    @Test("Обычная ошибка не включает кулдаун")
    func ordinaryError() async {
        let clock = TestClock(now: start)
        let store = ModelHealthStore(now: { clock.now })
        let candidate = ModelCandidate(provider: "gemini", model: "gemini-2.5-flash")

        let record = await store.markFailure(candidate, error: .timeout("prompt.submit"))

        #expect(record == nil)
        #expect(await store.isCoolingDown(candidate) == false)
    }

    @Test("Кулдаун истекает сам")
    func cooldownExpires() async {
        let clock = TestClock(now: start)
        let store = ModelHealthStore(now: { clock.now })
        let candidate = ModelCandidate(provider: "gemini", model: "gemini-2.5-flash")

        await store.markFailure(candidate, error: .protocolError("quota exceeded"))
        clock.now = start.addingTimeInterval(601)

        #expect(await store.isCoolingDown(candidate) == false)
        #expect(await store.record(for: candidate) == nil)
    }

    @Test("Успех снимает кулдаун")
    func successClears() async {
        let clock = TestClock(now: start)
        let store = ModelHealthStore(now: { clock.now })
        let candidate = ModelCandidate(provider: "gemini", model: "gemini-2.5-flash")

        await store.markFailure(candidate, error: .protocolError("429"))
        await store.markHealthy(candidate)

        #expect(await store.isCoolingDown(candidate) == false)
    }

    @Test("Классификация ошибок")
    func classification() {
        #expect(ModelHealthStore.issue(for: .protocolError("429 rate limit")) == .quota)
        #expect(ModelHealthStore.issue(for: .protocolError("invalid_api_key")) == .auth)
        #expect(ModelHealthStore.issue(for: .protocolError("model_not_found")) == .missing)
        #expect(ModelHealthStore.issue(for: .binaryNotFound) == nil)
    }
}

/// Mutable clock for the cooldown tests.
private final class TestClock: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
