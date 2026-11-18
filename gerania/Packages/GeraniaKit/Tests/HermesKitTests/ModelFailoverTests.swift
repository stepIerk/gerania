import Foundation
import GeraniaCore
import HermesKit
import Testing

@Suite("Перебор моделей")
struct ModelFailoverTests {
    @Test("Исчерпанная квота распознаётся")
    func quotaErrors() {
        let errors: [HermesError] = [
            .protocolError("PERMISSION_DENIED: quota exceeded for gemini-2.5-pro"),
            .protocolError("429 Too Many Requests"),
            .protocolError("RESOURCE_EXHAUSTED: rate limit reached"),
            .connectionFailed("insufficient_quota: выберите другую модель"),
            .processFailed(exitCode: 1, message: "billing hard limit"),
        ]

        for error in errors {
            #expect(error.isModelUnavailable, "ожидалось, что лимит распознаётся: \(error)")
        }
    }

    @Test("Обычные ошибки моделью не считаются")
    func ordinaryErrors() {
        let errors: [HermesError] = [
            .binaryNotFound,
            .timeout("prompt.submit"),
            .protocolError("unexpected token"),
            .notConfigured("нет ключа"),
        ]

        for error in errors {
            #expect(!error.isModelUnavailable, "ожидалось, что лимит НЕ распознаётся: \(error)")
        }
    }

    @Test("Список моделей Hermes читается из кеша")
    func catalogIsRead() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gerania-catalog-\(UUID().uuidString)")
        let home = directory.appendingPathComponent(".hermes")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = """
        {"gemini": {"at": 1, "models": ["gemini-3.5-flash", "gemini-2.5-pro"]}}
        """
        try Data(payload.utf8).write(to: HermesModelCatalog.cacheURL(homeDirectory: directory.path))

        let models = HermesModelCatalog.models(homeDirectory: directory.path, provider: "gemini")

        #expect(models == ["gemini-2.5-pro", "gemini-3.5-flash"])
    }

    @Test("Пустой кеш не ломает выбор моделей")
    func emptyCatalog() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gerania-catalog-\(UUID().uuidString)")

        #expect(HermesModelCatalog.models(homeDirectory: directory.path, provider: "gemini").isEmpty)
    }
}
