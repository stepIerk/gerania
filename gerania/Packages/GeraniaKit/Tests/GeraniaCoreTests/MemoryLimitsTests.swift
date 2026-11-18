import Foundation
import GeraniaCore
import Testing

@Suite("Лимиты памяти")
struct MemoryLimitsTests {
    @Test("По умолчанию — лимиты Hermes")
    func defaults() {
        let limits = MemoryLimits.parse("")
        #expect(limits.user == 1375)
        #expect(limits.notes == 2200)
        #expect(limits.limit(for: .user) == 1375)
        #expect(limits.limit(for: .notes) == 2200)
    }

    @Test("Читает оба лимита из секции memory")
    func readsKeys() {
        let config = """
        memory:
          memory_enabled: true
          memory_char_limit: 4000   # notes
          user_char_limit: 2000     # profile
        """
        let limits = MemoryLimits.parse(config)
        #expect(limits.notes == 4000)
        #expect(limits.user == 2000)
    }

    @Test("Комментарии и чужие секции не мешают")
    func ignoresCommentsAndOtherSections() {
        let config = """
        # memory_char_limit: 9999
        agent:
          memory_char_limit: 5000
        memory:
          # user_char_limit: 1
          memory_char_limit: 3000
        """
        let limits = MemoryLimits.parse(config)
        #expect(limits.notes == 3000)
        #expect(limits.user == 1375)
    }

    @Test("Некорректные и нулевые значения сохраняют запасные")
    func invalidValuesKeepFallback() {
        let config = """
        memory:
          memory_char_limit: nope
          user_char_limit: 0
        """
        let limits = MemoryLimits.parse(config)
        #expect(limits.notes == 2200)
        #expect(limits.user == 1375)
    }

    @Test("Путь конфига учитывает HERMES_HOME")
    func configURL() {
        let custom = MemoryLimits.configURL(
            homeDirectory: "/Users/test",
            environment: ["HERMES_HOME": "/tmp/hermes"]
        )
        #expect(custom.path == "/tmp/hermes/config.yaml")

        let standard = MemoryLimits.configURL(
            homeDirectory: "/Users/test",
            environment: [:]
        )
        #expect(standard.path == "/Users/test/.hermes/config.yaml")
    }
}
