import Foundation
import GeraniaCore

/// A problem with the cron store, explained for the settings window.
public enum CronError: Error, LocalizedError, Equatable {
    case unreadable(String)
    case invalidFormat(String)
    case commandFailed(exitCode: Int32, message: String)
    case binaryNotFound

    public var errorDescription: String? {
        switch self {
        case let .unreadable(reason):
            "Не удалось прочитать задачи: \(reason)"
        case let .invalidFormat(reason):
            "Файл задач повреждён: \(reason)"
        case let .commandFailed(exitCode, message):
            message.isEmpty
                ? "Hermes завершился с кодом \(exitCode)."
                : message
        case .binaryNotFound:
            "Не найден hermes. Укажите путь в настройках."
        }
    }
}

/// A new job requested from the settings tab.
public struct CronJobRequest: Sendable, Equatable {
    public var name: String
    public var schedule: String
    public var prompt: String
    public var deliver: String
    public var timezone: String?

    public init(
        name: String,
        schedule: String,
        prompt: String,
        deliver: String = "local",
        timezone: String? = nil
    ) {
        self.name = name
        self.schedule = schedule
        self.prompt = prompt
        self.deliver = deliver
        self.timezone = timezone
    }

    public var isValid: Bool {
        !schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Arguments of `hermes cron create`, without shell quoting.
    public var arguments: [String] {
        var args = ["cron", "create", schedule]
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            args.append(trimmedPrompt)
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            args += ["--name", trimmedName]
        }
        args += ["--deliver", deliver.isEmpty ? "local" : deliver]
        if let timezone, !timezone.isEmpty {
            args += ["--timezone", timezone]
        }
        return args
    }
}

/// Result of one `hermes cron ...` invocation.
public struct CronCommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs the Hermes CLI; injectable so tests never touch the real scheduler.
public typealias CronCommandRunner = @Sendable ([String]) async throws -> CronCommandResult

/// Reads `~/.hermes/cron/jobs.json` and runs the `hermes cron` actions.
///
/// The store never writes the JSON file: every mutation goes through the CLI,
/// so Hermes keeps its locks, validation and repair logic. Reading is a plain
/// file read, which keeps the tab fast and works offline.
public actor CronJobsStore {
    /// `~/.hermes/cron`, or `<HERMES_HOME>/cron`.
    public nonisolated let directory: URL

    private let runner: CronCommandRunner

    public init(
        directory: URL? = nil,
        config: HermesConfig = HermesConfig(),
        timeout: TimeInterval = 60,
        runner: CronCommandRunner? = nil
    ) {
        self.directory = directory ?? Self.defaultDirectory(homeDirectory: config.homeDirectory)
        self.runner = runner ?? Self.liveRunner(config: config, timeout: timeout)
    }

    public nonisolated static func defaultDirectory(
        homeDirectory: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let home = environment["HERMES_HOME"], !home.isEmpty {
            let expanded = (home as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).appendingPathComponent("cron", isDirectory: true)
        }
        return URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".hermes/cron", isDirectory: true)
    }

    public nonisolated var jobsFileURL: URL {
        directory.appendingPathComponent("jobs.json")
    }

    /// Reads every job. A missing file is an empty list; a corrupt file throws.
    public func load() throws -> [CronJob] {
        let url = jobsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data: Data
        do {
            data = try Self.readWithoutBOM(url)
        } catch {
            throw CronError.unreadable(error.localizedDescription)
        }
        return try Self.parseJobs(data)
    }

    public func pause(_ id: String) async throws {
        _ = try await run(["cron", "pause", id])
    }

    public func resume(_ id: String, runNow: Bool = false) async throws {
        var arguments = ["cron", "resume"]
        if runNow {
            arguments.append("--run-now")
        }
        arguments.append(id)
        _ = try await run(arguments)
    }

    public func runNow(_ id: String) async throws {
        _ = try await run(["cron", "run", id])
    }

    public func remove(_ id: String) async throws {
        _ = try await run(["cron", "remove", id])
    }

    public func create(_ request: CronJobRequest) async throws {
        guard request.isValid else {
            throw CronError.commandFailed(
                exitCode: -1,
                message: "Заполните расписание и текст задачи."
            )
        }
        _ = try await run(request.arguments)
    }

    // MARK: - Parsing

    static func parseJobs(_ data: Data) throws -> [CronJob] {
        let root: JSONValue
        do {
            root = try JSONValue(from: data)
        } catch {
            throw CronError.invalidFormat(error.localizedDescription)
        }
        let list: [JSONValue]
        if let jobs = root["jobs"]?.arrayValue {
            list = jobs
        } else if let array = root.arrayValue {
            list = array
        } else {
            throw CronError.invalidFormat("ожидался объект с полем «jobs»")
        }
        return list.compactMap(CronJob.parse)
    }

    private static func readWithoutBOM(_ url: URL) throws -> Data {
        var data = try Data(contentsOf: url)
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            data.removeFirst(3)
        }
        return data
    }

    // MARK: - Process

    private func run(_ arguments: [String]) async throws -> CronCommandResult {
        let result = try await runner(arguments)
        guard result.exitCode == 0 else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw CronError.commandFailed(
                exitCode: result.exitCode,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }

    private static func liveRunner(config: HermesConfig, timeout: TimeInterval) -> CronCommandRunner {
        { arguments in
            let binary: URL
            do {
                binary = try config.hermesBinary()
            } catch {
                throw CronError.binaryNotFound
            }
            let process: ChildProcess
            do {
                process = try ChildProcess(
                    executable: binary,
                    arguments: arguments,
                    environment: config.processEnvironment()
                )
            } catch {
                throw CronError.commandFailed(exitCode: -1, message: error.localizedDescription)
            }
            let stdoutTask = Task { await readAll(process.stdout) }
            let stderrTask = Task { await readAll(process.stderr) }
            let watchdog = Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                process.terminate()
            }
            let exitCode = await process.wait()
            watchdog.cancel()
            let stdout = await stdoutTask.value
            let stderr = await stderrTask.value
            return CronCommandResult(
                exitCode: exitCode,
                stdout: String(bytes: stdout, encoding: .utf8) ?? "",
                stderr: String(bytes: stderr, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        var data = Data()
        for await chunk in FileHandleChunks.stream(handle) {
            data.append(chunk)
        }
        return data
    }
}
