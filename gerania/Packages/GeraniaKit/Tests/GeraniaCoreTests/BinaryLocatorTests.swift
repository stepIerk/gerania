import GeraniaCore
import Testing

@Suite("BinaryLocator")
struct BinaryLocatorTests {
    private func locator(existing: Set<String>, shell: String? = nil) -> BinaryLocator {
        BinaryLocator(
            homeDirectory: "/Users/test",
            isExecutable: { existing.contains($0) },
            shellLookup: { _ in shell }
        )
    }

    @Test("Explicit setting wins over standard directories")
    func configuredPathWins() {
        let locator = locator(existing: ["/custom/hermes", "/opt/homebrew/bin/hermes"])

        let found = locator.locateHermes(configuredPath: "/custom/hermes")

        #expect(found?.path == "/custom/hermes")
    }

    @Test("Homebrew is preferred over Intel and local bins")
    func standardOrder() {
        let locator = locator(existing: [
            "/opt/homebrew/bin/hermes",
            "/usr/local/bin/hermes",
            "/Users/test/.local/bin/hermes",
        ])

        #expect(locator.locateHermes()?.path == "/opt/homebrew/bin/hermes")
    }

    @Test("Falls back to ~/.local/bin")
    func localBin() {
        let locator = locator(existing: ["/Users/test/.local/bin/hermes"])

        #expect(locator.locateHermes()?.path == "/Users/test/.local/bin/hermes")
    }

    @Test("Falls back to the login shell lookup")
    func shellLookup() {
        let locator = locator(existing: ["/shell/hermes"], shell: "/shell/hermes\n")

        #expect(locator.locateHermes()?.path == "/shell/hermes")
    }

    @Test("Returns nil when nothing is found")
    func missing() {
        let locator = locator(existing: [])

        #expect(locator.locateHermes() == nil)
    }

    @Test("Expands tilde in a configured path")
    func tildeExpansion() {
        let locator = locator(existing: ["/Users/test/bin/hermes"])

        #expect(locator.locateHermes(configuredPath: "~/bin/hermes")?.path == "/Users/test/bin/hermes")
    }

    @Test("Python uses its own configured path")
    func pythonConfigured() {
        let locator = locator(existing: ["/venv/bin/python3"])

        #expect(locator.locatePython(configuredPath: "/venv/bin/python3")?.path == "/venv/bin/python3")
    }

    @Test("Environment prepends GUI-friendly directories")
    func environment() {
        let locator = locator(existing: [])
        let environment = locator.environment(base: ["PATH": "/usr/bin:/bin", "HOME": "/Users/test"])

        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/Users/test/.local/bin:/usr/bin:/bin")
        #expect(environment["HOME"] == "/Users/test")
    }
}
