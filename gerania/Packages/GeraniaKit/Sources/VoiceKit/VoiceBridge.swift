import Darwin
import Foundation
import GeraniaCore

/// Runs the voice front-end and turns its NDJSON stream into events.
///
/// The script is restarted after a crash with an increasing delay (1, 2, 4, …, 30 seconds).
public actor VoiceBridge {
    /// How the voice front-end is started.
    public struct Configuration: Sendable {
        /// Python from the settings.
        public var pythonPath: String
        /// Script from the settings.
        public var scriptOverridePath: String
        /// Home directory of the user.
        public var homeDirectory: String

        public init(
            pythonPath: String = "",
            scriptOverridePath: String = "",
            homeDirectory: String = NSHomeDirectory()
        ) {
            self.pythonPath = pythonPath
            self.scriptOverridePath = scriptOverridePath
            self.homeDirectory = homeDirectory
        }
    }

    private let configuration: Configuration
    private var process: Process?
    private var inputHandle: FileHandle?
    private var continuation: AsyncStream<VoiceEvent>.Continuation?
    private var restartTask: Task<Void, Never>?
    private var restartDelay: TimeInterval = 1
    private var isRunning = false

    /// Number of the restarts since the launch (diagnostics).
    public private(set) var restartCount = 0
    /// Whether the script reached the ready state at least once.
    private var didBecomeReady = false

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Whether the script is running.
    public var isActive: Bool {
        isRunning
    }

    /// The stream of the events of the script.
    public func events() -> AsyncStream<VoiceEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// Starts the script.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        restartDelay = 1
        launch()
    }

    /// Stops the script: `shutdown`, then a signal.
    public func stop() async {
        isRunning = false
        restartTask?.cancel()
        restartTask = nil
        guard let process else { return }
        self.process = nil
        if let inputHandle {
            try? inputHandle.write(contentsOf: Data((VoiceCommand.shutdown.payload + "\n").utf8))
        }
        try? await Task.sleep(for: .seconds(2))
        if process.isRunning {
            process.terminate()
        }
        try? await Task.sleep(for: .seconds(1))
        if process.isRunning {
            killProcess(process.processIdentifier)
        }
    }

    /// Sends a command to the script.
    public func send(_ command: VoiceCommand) {
        guard let inputHandle else { return }
        let line = command.payload + "\n"
        try? inputHandle.write(contentsOf: Data(line.utf8))
    }

    private func launch() {
        guard let script = VoicePaths.script(
            override: configuration.scriptOverridePath,
            scriptDirectory: nil
        ) else {
            Log.voice.error("voice script not found")
            return
        }
        let directory = VoicePaths.scriptDirectory(scriptPath: script)
        guard let python = VoicePaths.python(
            configured: configuration.pythonPath,
            scriptDirectory: directory,
            homeDirectory: configuration.homeDirectory
        ) else {
            Log.voice.error("python for the voice script not found")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script, "--ipc"]
        process.environment = VoicePaths.environment(homeDirectory: configuration.homeDirectory)
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let input = Pipe()
        process.standardInput = input
        inputHandle = input.fileHandleForWriting

        do {
            try process.run()
        } catch {
            Log.voice.error("cannot start the voice script: \(error.localizedDescription, privacy: .public)")
            scheduleRestart()
            return
        }
        self.process = process
        Log.voice.info("voice script started")

        readOutput(output.fileHandleForReading)
        readErrors(errors.fileHandleForReading)
        waitForExit(process)
    }

    private func readOutput(_ handle: FileHandle) {
        Task.detached { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    guard let event = VoiceEvent.decode(line) else {
                        if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Log.voice.debug("voice: unknown line \(line, privacy: .public)")
                        }
                        continue
                    }
                    await self?.handle(event)
                }
            } catch {
                await self?.logError("stdout: \(error.localizedDescription)")
            }
        }
    }

    private func readErrors(_ handle: FileHandle) {
        Task.detached { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    await self?.logError(line)
                }
            } catch {
                await self?.logError("stderr: \(error.localizedDescription)")
            }
        }
    }

    private func logError(_ line: String) {
        guard !line.isEmpty else { return }
        // Обычные сообщения скрипта — это отладочный шум; ошибками считаем только сбои.
        let isFailure = line.contains("Traceback")
            || line.contains("Error")
            || line.contains("error:")
        if isFailure {
            Log.voice.error("voice: \(line, privacy: .public)")
        } else {
            Log.voice.debug("voice: \(line, privacy: .public)")
        }
    }

    private func waitForExit(_ process: Process) {
        Task.detached { [weak self] in
            process.waitUntilExit()
            await self?.handleExit()
        }
    }

    private func handle(_ event: VoiceEvent) {
        switch event {
        case let .ready(model):
            didBecomeReady = true
            Log.voice.info("voice ready: \(model, privacy: .public)")
        case .bye:
            Log.voice.info("voice script finished")
        default:
            break
        }
        continuation?.yield(event)
    }

    private func handleExit() {
        process = nil
        inputHandle = nil
        guard isRunning else { return }
        restartCount += 1
        if !didBecomeReady, restartCount >= 3 {
            isRunning = false
            Log.voice.error(
                "voice script fails to start — check the dependencies: scripts/setup_voice.sh"
            )
            return
        }
        Log.voice.error("voice script exited, restart #\(self.restartCount, privacy: .public)")
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard isRunning else { return }
        let delay = restartDelay
        restartDelay = min(30, restartDelay * 2)
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.launch()
        }
    }

    private func killProcess(_ pid: Int32) {
        Darwin.kill(pid, SIGKILL)
    }
}
