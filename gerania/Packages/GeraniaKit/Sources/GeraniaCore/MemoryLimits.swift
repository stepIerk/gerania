import Foundation

/// Character budgets of the two curated memory files.
///
/// Hermes keeps the limits in `~/.hermes/config.yaml` under `memory:`:
/// `memory_char_limit` (notes) and `user_char_limit` (profile). Gerania reads
/// those keys read-only and falls back to the Hermes defaults when the file is
/// missing or the keys are absent. The values are only refreshed when the store
/// is created, so a change in `config.yaml` is picked up on the next launch or
/// after pressing «Обновить» in the memory tab.
public struct MemoryLimits: Sendable, Equatable {
    /// Budget of `USER.md`.
    public var user: Int
    /// Budget of `MEMORY.md`.
    public var notes: Int

    /// Limits Hermes uses when `config.yaml` says nothing.
    public static let standard = MemoryLimits(user: 1375, notes: 2200)

    public init(user: Int, notes: Int) {
        self.user = user > 0 ? user : MemoryLimits.standard.user
        self.notes = notes > 0 ? notes : MemoryLimits.standard.notes
    }

    public func limit(for kind: MemoryKind) -> Int {
        switch kind {
        case .user: user
        case .notes: notes
        }
    }

    /// Reads the limits from `<HERMES_HOME>/config.yaml` or `~/.hermes/config.yaml`.
    public static func load(
        homeDirectory: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> MemoryLimits {
        let configURL = configURL(homeDirectory: homeDirectory, environment: environment)
        guard let raw = try? String(contentsOf: configURL, encoding: .utf8) else {
            return .standard
        }
        return parse(raw)
    }

    public nonisolated static func configURL(
        homeDirectory: String,
        environment: [String: String]
    ) -> URL {
        if let home = environment["HERMES_HOME"], !home.isEmpty {
            let expanded = (home as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).appendingPathComponent("config.yaml")
        }
        return URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".hermes/config.yaml")
    }

    /// Tolerant reader of the `memory:` mapping.
    ///
    /// Only two integer keys are needed, so a full YAML parser would be overkill.
    /// Comments and every other section are ignored; malformed values keep the
    /// fallback instead of breaking the settings tab.
    public static func parse(_ config: String, fallback: MemoryLimits = .standard) -> MemoryLimits {
        var user = fallback.user
        var notes = fallback.notes
        var section: String?
        for rawLine in config.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
            if indentation == 0 {
                guard let colon = trimmed.firstIndex(of: ":") else {
                    section = nil
                    continue
                }
                section = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard section == "memory", let colon = trimmed.firstIndex(of: ":") else {
                continue
            }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard let number = Int(value), number > 0 else { continue }
            switch key {
            case "user_char_limit": user = number
            case "memory_char_limit": notes = number
            default: break
            }
        }
        return MemoryLimits(user: user, notes: notes)
    }

    private static func stripComment(_ line: String) -> String {
        guard let hash = line.firstIndex(of: "#") else { return line }
        return String(line[..<hash])
    }
}
