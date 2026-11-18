import Foundation
import GeraniaCore

/// One check of the cua-driver health report.
public struct ComputerUseCheck: Sendable, Equatable, Identifiable {
    public let name: String
    /// `pass`, `warn`, `fail` or `skip`, as reported by cua-driver.
    public let status: String
    public let message: String

    public var id: String {
        name
    }

    public var isFailure: Bool {
        status == "fail"
    }

    public init(name: String, status: String, message: String) {
        self.name = name
        self.status = status
        self.message = message
    }
}

/// Whether the `computer_use` toolset can drive this Mac right now.
///
/// The checks come from `hermes computer-use doctor --json`: the driver bundle,
/// the TCC grants and the platform. The grants belong to `CuaDriver.app`
/// (`com.trycua.driver`), not to Gerania: the driver does the clicking and the
/// screen capture, so macOS asks the driver for permission.
public struct ComputerUseStatus: Sendable, Equatable {
    public let platform: String
    public let driverVersion: String?
    public let overall: String
    public let checks: [ComputerUseCheck]
    public let bundleIdentifier: String?
    /// Human-readable reason when the report could not be read at all.
    public let error: String?

    public var isReady: Bool {
        error == nil && overall == "ok"
    }

    public var isInstalled: Bool {
        checks.contains { $0.name == "binary_version" && $0.status == "pass" }
    }

    public var accessibility: Bool? {
        granted("tcc_accessibility")
    }

    public var screenRecording: Bool? {
        granted("tcc_screen_recording")
    }

    /// Grants that are explicitly missing, with names for the UI.
    public var missingPermissions: [String] {
        var missing: [String] = []
        if accessibility == false {
            missing.append("Универсальный доступ")
        }
        if screenRecording == false {
            missing.append("Запись экрана")
        }
        return missing
    }

    public var driverLabel: String {
        guard isInstalled else { return "не установлен" }
        return driverVersion.map { "cua-driver \($0)" } ?? "cua-driver"
    }

    public var summary: String {
        if let error {
            return error
        }
        if isReady {
            return "Готово к управлению компьютером"
        }
        if !isInstalled {
            return "cua-driver не установлен"
        }
        let missing = missingPermissions
        if !missing.isEmpty {
            return "Нет прав: \(missing.joined(separator: ", "))"
        }
        return "Драйвер сообщает о проблеме"
    }

    public init(
        platform: String = "darwin",
        driverVersion: String? = nil,
        overall: String = "unknown",
        checks: [ComputerUseCheck] = [],
        bundleIdentifier: String? = nil,
        error: String? = nil
    ) {
        self.platform = platform
        self.driverVersion = driverVersion
        self.overall = overall
        self.checks = checks
        self.bundleIdentifier = bundleIdentifier
        self.error = error
    }

    public static func failed(_ message: String) -> ComputerUseStatus {
        ComputerUseStatus(error: message)
    }

    /// Parses the JSON of `hermes computer-use doctor --json`.
    public static func parse(_ data: Data) throws -> ComputerUseStatus {
        let root = try JSONValue(from: data)
        guard root.objectValue != nil else {
            throw HermesError.protocolError("computer-use doctor: ожидался JSON-объект")
        }
        let checks = root["checks"]?.arrayValue?.compactMap { raw -> ComputerUseCheck? in
            guard let name = raw["name"]?.stringValue else { return nil }
            return ComputerUseCheck(
                name: name,
                status: raw["status"]?.stringValue ?? "unknown",
                message: raw["message"]?.stringValue ?? ""
            )
        } ?? []
        let identity = root["checks"]?.arrayValue?
            .first { $0["name"]?.stringValue == "bundle_identity" }
        let bundle = identity?["data"]?["bundle_identifier"]?.stringValue
        return ComputerUseStatus(
            platform: root["platform"]?.stringValue ?? "unknown",
            driverVersion: root["driver_version"]?.stringValue
                ?? root["hermes_identity"]?["health_report_driver_version"]?.stringValue,
            overall: root["overall"]?.stringValue ?? "unknown",
            checks: checks,
            bundleIdentifier: bundle,
            error: nil
        )
    }

    private func check(_ name: String) -> ComputerUseCheck? {
        checks.first { $0.name == name }
    }

    private func granted(_ name: String) -> Bool? {
        guard let check = check(name) else { return nil }
        switch check.status {
        case "pass": return true
        case "fail": return false
        default: return nil
        }
    }
}

/// Runs the cua-driver health report and the permission grant through Hermes.
public actor ComputerUseInspector {
    private let config: HermesConfig

    public init(config: HermesConfig) {
        self.config = config
    }

    /// Reads the health report. A missing binary or a broken report yields a
    /// status with `error` instead of throwing: the settings card always renders.
    public func inspect(timeout: TimeInterval = 30) async -> ComputerUseStatus {
        do {
            let result = try await run(
                arguments: ["computer-use", "doctor", "--json"],
                timeout: timeout
            )
            guard !result.stdout.isEmpty else {
                let reason = result.stderr.isEmpty
                    ? "hermes не вернул отчёт о драйвере"
                    : result.stderr
                return .failed(reason)
            }
            return try ComputerUseStatus.parse(result.stdout)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Asks macOS for the Accessibility and Screen Recording grants.
    ///
    /// Hermes launches `CuaDriver.app` through LaunchServices, so the system
    /// dialogs are attributed to the driver, not to Gerania. Returns the error
    /// text, or nil when the request command finished.
    public func requestPermissions(timeout: TimeInterval = 120) async -> String? {
        do {
            let result = try await run(
                arguments: ["computer-use", "permissions", "grant"],
                timeout: timeout
            )
            if result.exitCode == 0 {
                return nil
            }
            let output = result.stderr.isEmpty
                ? String(data: result.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                : result.stderr
            return output.isEmpty
                ? "Не удалось запросить разрешения (код \(result.exitCode))"
                : output
        } catch {
            return error.localizedDescription
        }
    }

    private struct CommandResult {
        let exitCode: Int32
        let stdout: Data
        let stderr: String
    }

    private func run(arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        let binary = try config.hermesBinary()
        let process = try ChildProcess(
            executable: binary,
            arguments: arguments,
            environment: config.processEnvironment()
        )
        let stdoutTask = Task { await Self.readAll(process.stdout) }
        let stderrTask = Task { await Self.readAll(process.stderr) }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            process.terminate()
        }
        let exitCode = await process.wait()
        watchdog.cancel()
        let stdout = await stdoutTask.value
        let stderr = await stderrTask.value
        return CommandResult(
            exitCode: exitCode,
            stdout: stdout,
            stderr: String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        var data = Data()
        for await chunk in FileHandleChunks.stream(handle) {
            data.append(chunk)
        }
        return data
    }
}
