import Foundation
import GeraniaCore

/// Records the owner voice profile with the ears script (`--enroll-voice`).
///
/// A separate short-lived process: the running ears are suspended by the app
/// meanwhile, so «Гера» in the sample phrases does not wake anything.
public final class VoiceEnrollment: @unchecked Sendable {
    private let configuration: VoiceBridge.Configuration
    private let lock = NSLock()
    private var process: Process?

    public init(configuration: VoiceBridge.Configuration) {
        self.configuration = configuration
    }

    /// Events of the recording: `enrollProgress`, then `enrollDone` or `error`.
    public func run(outputPath: String) -> AsyncStream<VoiceEvent> {
        AsyncStream { continuation in
            guard let script = VoicePaths.script(override: configuration.scriptOverridePath, scriptDirectory: nil),
                  let python = VoicePaths.python(
                      configured: configuration.pythonPath,
                      scriptDirectory: VoicePaths.scriptDirectory(scriptPath: script),
                      homeDirectory: configuration.homeDirectory
                  )
            else {
                continuation.yield(.error(message: "Окружение распознавания речи не установлено."))
                continuation.finish()
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [script, "--enroll-voice", outputPath, "--ipc"]
            process.environment = VoicePaths.environment(homeDirectory: configuration.homeDirectory)
                .merging(configuration.environment) { _, extra in extra }
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = Pipe()
            let reader = LineReader()
            let readHandle = output.fileHandleForReading
            readHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                for line in reader.append(data) {
                    if let event = VoiceEvent.decode(line) {
                        continuation.yield(event)
                    }
                }
            }
            process.terminationHandler = { _ in
                readHandle.readabilityHandler = nil
                continuation.finish()
            }
            do {
                try process.run()
                lock.withLock { self.process = process }
            } catch {
                continuation.yield(.error(message: "Не удалось начать запись: \(error.localizedDescription)"))
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in
                self?.cancel()
            }
        }
    }

    public func cancel() {
        let running = lock.withLock { () -> Process? in
            let current = process
            process = nil
            return current
        }
        if let running, running.isRunning {
            running.terminate()
        }
    }
}

/// Splits a byte stream into lines; the tail waits for the next chunk.
final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.withLock {
            buffer.append(data)
            var lines: [String] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex ..< newline]
                buffer.removeSubrange(buffer.startIndex ... newline)
                if let text = String(data: line, encoding: .utf8) {
                    lines.append(text)
                }
            }
            return lines
        }
    }
}
