import Foundation
import GeraniaCore
import Testing

@Suite("Возможности моделей")
struct ModelCapabilitiesTests {
    private let fixture = """
    {
      "google": {
        "models": {
          "gemini-2.5-flash-lite": {
            "name": "Gemini 2.5 Flash Lite",
            "tool_call": true,
            "modalities": { "input": ["text", "image"] },
            "limit": { "context": 1048576 },
            "cost": { "input": 0.1, "output": 0.4 }
          }
        }
      },
      "openrouter": {
        "models": {
          "google/gemma-4-31b-it:free": {
            "name": "Gemma 4",
            "tool_call": true,
            "modalities": { "input": ["text"] },
            "limit": { "context": 262144 },
            "cost": { "input": 0, "output": 0 }
          },
          "paid/model": {
            "cost": { "input": 1, "output": 2 }
          }
        }
      },
      "lmstudio": {
        "models": {
          "qwen/qwen3-30b": { "tool_call": false }
        }
      }
    }
    """

    @Test("Каталог разбирается в возможности")
    func parseCatalog() throws {
        let catalog = ModelCapabilitiesStore.parse(Data(fixture.utf8))
        let gemini = try #require(catalog["google:gemini-2.5-flash-lite"])

        #expect(gemini.title == "Gemini 2.5 Flash Lite")
        #expect(gemini.supportsTools)
        #expect(gemini.supportsVision)
        #expect(gemini.contextTokens == 1_048_576)
        #expect(gemini.contextLabel == "1M")
        #expect(!gemini.isFree)
    }

    @Test("Бесплатная модель OpenRouter распознаётся")
    func freeModel() throws {
        let catalog = ModelCapabilitiesStore.parse(Data(fixture.utf8))
        let gemma = try #require(catalog["openrouter:google/gemma-4-31b-it:free"])
        let paid = try #require(catalog["openrouter:paid/model"])

        #expect(gemma.isFree)
        #expect(gemma.supportsTools)
        #expect(!gemma.supportsVision)
        #expect(gemma.contextLabel == "262K")
        #expect(!paid.isFree)
    }

    @Test("Локальная модель считается бесплатной")
    func localModel() throws {
        let catalog = ModelCapabilitiesStore.parse(Data(fixture.utf8))
        let local = try #require(catalog["lmstudio:qwen/qwen3-30b"])

        #expect(local.isFree)
        #expect(local.isLocal)
        #expect(!local.supportsTools)
    }

    @Test("Провайдер gemini ищется в каталоге google")
    func providerAlias() async throws {
        let home = try makeHome(catalog: fixture)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = ModelCapabilitiesStore(homeDirectory: home.path)
        let candidate = ModelCandidate(provider: "gemini", model: "gemini-2.5-flash-lite")

        let capabilities = await store.capabilities(for: candidate)

        #expect(capabilities?.provider == "google")
        #expect(capabilities?.supportsVision == true)
    }

    @Test("Битый каталог не роняет загрузку")
    func brokenCatalog() async throws {
        let home = try makeHome(catalog: "{ not json")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = ModelCapabilitiesStore(homeDirectory: home.path)

        let capabilities = await store.capabilities(
            for: ModelCandidate(provider: "gemini", model: "gemini-2.5-flash-lite")
        )

        #expect(capabilities == nil)
        #expect(await store.allCapabilities().isEmpty)
    }

    @Test("Алиасы провайдеров")
    func providerNormalization() {
        #expect(ModelCapabilitiesStore.normalizeProvider("gemini") == "google")
        #expect(ModelCapabilitiesStore.normalizeProvider("kimi") == "moonshotai")
        #expect(ModelCapabilitiesStore.normalizeProvider("moonshot") == "moonshotai")
        #expect(ModelCapabilitiesStore.normalizeProvider("zhipu") == "zai")
        #expect(ModelCapabilitiesStore.normalizeProvider("openrouter") == "openrouter")
        #expect(ModelCapabilitiesStore.isLocalProvider("ollama"))
        #expect(!ModelCapabilitiesStore.isLocalProvider("openrouter"))
    }

    private func makeHome(catalog: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeraniaCapabilities-\(UUID().uuidString)")
        let hermes = home.appendingPathComponent(".hermes")
        try FileManager.default.createDirectory(at: hermes, withIntermediateDirectories: true)
        try catalog.write(
            to: hermes.appendingPathComponent(ModelCapabilitiesStore.catalogFileName),
            atomically: true,
            encoding: .utf8
        )
        return home
    }
}
