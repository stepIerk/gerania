import Foundation
@testable import RealtimeKit
import Testing

@Suite("Лимиты Gemini Live")
struct LiveQuotaTests {
    @Test("Выбранная модель первая, остальные — запасные по порядку")
    func chain() {
        let chain = LiveModelCatalog.chain(startingWith: "gemini-3.8-live-extended-thinking")

        #expect(chain.first == "gemini-3.8-live-extended-thinking")
        #expect(chain.dropFirst().first == "gemini-3.8-live")
        #expect(Set(chain).count == chain.count)
        #expect(LiveModelCatalog.chain(startingWith: "  ").first == LiveModelCatalog.defaultModel)
        #expect(LiveModelCatalog.chain(startingWith: "custom-live").count == LiveModelCatalog.entries.count + 1)
    }

    @Test("Кончился лимит — берём следующую модель, через минуту возвращаемся")
    func fallbackAndRecover() {
        var guardian = LiveQuotaGuard()
        let now = Date(timeIntervalSince1970: 1000)

        guardian.markExhausted("gemini-3.8-live", now: now)

        #expect(guardian.pick(preferred: "gemini-3.8-live", now: now) == "gemini-3.8-live-extended-thinking")
        #expect(guardian.pick(preferred: "gemini-3.8-live", now: now.addingTimeInterval(61)) == "gemini-3.8-live")
        #expect(guardian.nextAvailableDate(preferred: "gemini-3.8-live") == now.addingTimeInterval(60))
    }

    @Test("Повторный лимит удлиняет паузу, успех её сбрасывает")
    func strikes() {
        var guardian = LiveQuotaGuard()
        let now = Date(timeIntervalSince1970: 0)
        guardian.markExhausted("m", now: now)
        guardian.markExhausted("m", now: now)
        #expect(!guardian.isAvailable("m", now: now.addingTimeInterval(599)))
        #expect(guardian.isAvailable("m", now: now.addingTimeInterval(601)))

        guardian.markExhausted("m", now: now)
        guardian.markExhausted("m", now: now)
        #expect(!guardian.isAvailable("m", now: now.addingTimeInterval(3599)))

        guardian.markWorking("m")
        #expect(guardian.isAvailable("m", now: now))
    }

    @Test("Все модели на паузе — выбора нет")
    func allExhausted() {
        var guardian = LiveQuotaGuard()
        let now = Date(timeIntervalSince1970: 0)
        for entry in LiveModelCatalog.entries {
            guardian.markExhausted(entry.id, now: now)
        }

        #expect(guardian.pick(preferred: LiveModelCatalog.defaultModel, now: now) == nil)
    }

    @Test("Причина закрытия сокета распознаётся как лимит или ключ")
    func closeReason() {
        #expect(LiveError(closeReason: "You exceeded your current quota, please check your plan") == .quotaExceeded)
        #expect(LiveError(closeReason: "RESOURCE_EXHAUSTED") == .quotaExceeded)
        #expect(LiveError(closeReason: "API key not valid. Please pass a valid API key.") == .unauthorized)
        #expect(LiveError(closeReason: "  ") == nil)
        #expect(LiveError(closeReason: nil) == nil)
    }
}
