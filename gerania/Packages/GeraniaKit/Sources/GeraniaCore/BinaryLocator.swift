import Foundation

/// Finds `hermes` / `python3` the way the legacy script did, but without relying on the
/// launchd environment of a GUI app (which has no shell `PATH`).
public struct BinaryLocator: Sendable {
    public typealias ExecutableCheck = @Sendable (String) -> Bool
    public typealias ShellLookup = @Sendable (String) -> String?

    private let isExecutable: ExecutableCheck
    private let shellLookup: ShellLookup
    private let homeDirectory: String

    public init(
        homeDirectory: String = NSHomeDirectory(),
        isExecutable: @escaping ExecutableCheck,
        shellLookup: @escaping ShellLookup
    ) {
        self.homeDirectory = homeDirectory
        self.isExecutable = isExecutable
        self.shellLookup = shellLookup
    }

    public static let live = BinaryLocator.live(homeDirectory: NSHomeDirectory())

    public static func live(homeDirectory: String) -> BinaryLocator {
        BinaryLocator(
            homeDirectory: homeDirectory,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
            shellLookup: { command in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    Log.app.debug("zsh lookup failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let value = (String(data: data, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        )
    }

    /// Search order: explicit setting → Homebrew/Intel/local bin → login shell.
    public func locate(_ name: String, configuredPath: String = "") -> URL? {
        if let configured = executable(at: configuredPath) {
            return configured
        }
        for directory in standardDirectories {
            if let candidate = executable(at: directory + "/" + name) {
                return candidate
            }
        }
        if let found = shellLookup("command -v \(name)") {
            let trimmed = found.trimmingCharacters(in: .whitespacesAndNewlines)
            return executable(at: trimmed)
        }
        return nil
    }

    public func locateHermes(configuredPath: String = "") -> URL? {
        locate("hermes", configuredPath: configuredPath)
    }

    public func locatePython(configuredPath: String = "") -> URL? {
        if let configured = executable(at: configuredPath) {
            return configured
        }
        return locate("python3")
    }

    /// Adds the directories a GUI process usually lacks, preserving the inherited `PATH` last.
    public func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        var parts = standardDirectories
        if let inherited = base["PATH"], !inherited.isEmpty {
            parts.append(inherited)
        }
        environment["PATH"] = parts.joined(separator: ":")
        environment["HOME"] = base["HOME"] ?? homeDirectory
        return environment
    }

    private var standardDirectories: [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", homeDirectory + "/.local/bin"]
    }

    private func executable(at path: String) -> URL? {
        let expanded = expandTilde(path)
        guard !expanded.isEmpty else { return nil }
        return isExecutable(expanded) ? URL(fileURLWithPath: expanded) : nil
    }

    private func expandTilde(_ path: String) -> String {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return homeDirectory + path.dropFirst()
        }
        return path
    }
}
