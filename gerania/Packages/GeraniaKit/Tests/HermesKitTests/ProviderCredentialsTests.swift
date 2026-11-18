import Foundation
import HermesKit
import Testing

@Suite("Ключи провайдеров")
struct ProviderCredentialsTests {
    @Test("Имена переменных читаются, значения нет")
    func envNames() throws {
        let home = try makeHome(env: """
        # comment
        export GEMINI_API_KEY=secret
        OPENROUTER_API_KEY=
        ZHIPU_API_KEY="value"
        IGNORED_SETTING=value
        """)
        defer { try? FileManager.default.removeItem(at: home) }

        let names = ProviderCredentials.configuredNames(homeDirectory: home.path, environment: [:])

        #expect(names.contains("GEMINI_API_KEY"))
        #expect(names.contains("ZHIPU_API_KEY"))
        #expect(!names.contains("OPENROUTER_API_KEY"))
        #expect(!names.contains("IGNORED_SETTING"))
    }

    @Test("Ключ Gemini найден в .env")
    func geminiConfigured() throws {
        let home = try makeHome(env: "GEMINI_API_KEY=secret\n")
        defer { try? FileManager.default.removeItem(at: home) }

        let status = ProviderCredentials.status(
            provider: "gemini",
            homeDirectory: home.path,
            environment: [:]
        )

        #expect(status.isConfigured)
        #expect(status.requiredNames.contains("GEMINI_API_KEY"))
    }

    @Test("Пустой ключ OpenRouter не считается настроенным")
    func emptyOpenRouter() throws {
        let home = try makeHome(env: "OPENROUTER_API_KEY=\n")
        defer { try? FileManager.default.removeItem(at: home) }

        let status = ProviderCredentials.status(
            provider: "openrouter",
            homeDirectory: home.path,
            environment: [:]
        )

        #expect(!status.isConfigured)
        #expect(status.missingLabel == "OPENROUTER_API_KEY")
    }

    @Test("Ключ из окружения тоже работает")
    func environmentFallback() throws {
        let home = try makeHome(env: "")
        defer { try? FileManager.default.removeItem(at: home) }

        let status = ProviderCredentials.status(
            provider: "openrouter",
            homeDirectory: home.path,
            environment: ["OPENROUTER_API_KEY": "value"]
        )

        #expect(status.isConfigured)
    }

    @Test("Локальной модели ключ не нужен")
    func localProvider() throws {
        let home = try makeHome(env: "")
        defer { try? FileManager.default.removeItem(at: home) }

        let status = ProviderCredentials.status(provider: "ollama", homeDirectory: home.path, environment: [:])

        #expect(status.isConfigured)
        #expect(status.requiredNames.isEmpty)
        #expect(status.missingLabel == nil)
    }

    private func makeHome(env: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeraniaCredentials-\(UUID().uuidString)")
        let hermes = home.appendingPathComponent(".hermes")
        try FileManager.default.createDirectory(at: hermes, withIntermediateDirectories: true)
        try env.write(to: hermes.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        return home
    }
}
