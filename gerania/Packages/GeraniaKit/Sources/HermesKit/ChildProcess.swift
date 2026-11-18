import Darwin
import Foundation

public final class ChildProcess: @unchecked Sendable {
    public let pid: pid_t
    public let stdin: FileHandle
    public let stdout: FileHandle
    public let stderr: FileHandle

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String? = nil
    ) throws {
        var stdinPipe: [Int32] = [0, 0]
        var stdoutPipe: [Int32] = [0, 0]
        var stderrPipe: [Int32] = [0, 0]
        guard pipe(&stdinPipe) == 0, pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else {
            throw HermesError.processFailed(exitCode: -1, message: "не удалось создать pipe")
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdinPipe[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO)
        for descriptor in stdinPipe + stdoutPipe + stderrPipe {
            posix_spawn_file_actions_addclose(&actions, descriptor)
        }
        if let currentDirectory, !currentDirectory.isEmpty {
            posix_spawn_file_actions_addchdir_np(&actions, currentDirectory)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        let argumentPointers = Self.cStringArray([executable.path] + arguments)
        defer { argumentPointers.forEach { free($0) } }
        let environmentPointers = Self.cStringArray(
            environment.map { "\($0.key)=\($0.value)" }
        )
        defer { environmentPointers.forEach { free($0) } }

        var childPID: pid_t = 0
        let status = posix_spawn(
            &childPID,
            executable.path,
            &actions,
            &attributes,
            argumentPointers,
            environmentPointers
        )
        guard status == 0 else {
            for descriptor in stdinPipe + stdoutPipe + stderrPipe {
                close(descriptor)
            }
            throw HermesError.processFailed(
                exitCode: status,
                message: String(cString: strerror(status))
            )
        }

        close(stdinPipe[0])
        close(stdoutPipe[1])
        close(stderrPipe[1])
        pid = childPID
        stdin = FileHandle(fileDescriptor: stdinPipe[1], closeOnDealloc: true)
        stdout = FileHandle(fileDescriptor: stdoutPipe[0], closeOnDealloc: true)
        stderr = FileHandle(fileDescriptor: stderrPipe[0], closeOnDealloc: true)
    }

    public func signal(_ signal: Int32) {
        if Darwin.kill(-pid, signal) != 0 {
            Darwin.kill(pid, signal)
        }
    }

    public func terminate() {
        signal(SIGTERM)
    }

    public func forceKill() {
        signal(SIGKILL)
    }

    public func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var status: Int32 = 0
                while waitpid(self.pid, &status, 0) == -1, errno == EINTR {}
                let signalNumber = status & 0x7F
                if signalNumber == 0 {
                    continuation.resume(returning: (status >> 8) & 0xFF)
                } else {
                    continuation.resume(returning: 128 + signalNumber)
                }
            }
        }
    }

    private static func cStringArray(_ strings: [String]) -> [UnsafeMutablePointer<CChar>?] {
        var pointers = strings.map { strdup($0) }
        pointers.append(nil)
        return pointers
    }
}
