import Darwin
import Foundation
import GeraniaCore

struct GatewayEndpoint: Sendable {
    let apiOrigin: String
    let profileID: String
    let instanceID: String
    let controlHome: String

    static func ensure(_ config: HermesConfig) async throws -> GatewayEndpoint {
        let binary = try config.hermesBinary()
        let result = try await ProcessRunner.run(
            executable: binary,
            arguments: ["gateway", "ensure", "--json", "--timeout", "\(config.gatewayTimeout)"],
            environment: config.processEnvironment(),
            timeout: .seconds(config.gatewayTimeout + 30)
        )
        guard result.status == 0 else {
            throw HermesError.connectionFailed(
                result.stderr.isEmpty ? "gateway ensure exited \(result.status)" : result.stderr
            )
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw HermesError.protocolError("gateway ensure returned no JSON")
        }
        let payload = try JSONValue(from: data)
        guard payload["state"]?.stringValue == "ready" else {
            throw HermesError.connectionFailed("gateway is not ready")
        }
        let endpoint = payload["endpoint"] ?? payload
        guard let origin = endpoint["api_origin"]?.stringValue,
              let profileID = endpoint["profile_id"]?.stringValue,
              let instanceID = endpoint["instance_id"]?.stringValue
        else {
            throw HermesError.protocolError("gateway ensure returned an incomplete endpoint")
        }
        let controlHome = endpoint["control_home"]?.stringValue
            ?? (profileID.hasPrefix("/") ? profileID : config.homeDirectory)
        return GatewayEndpoint(
            apiOrigin: origin,
            profileID: profileID,
            instanceID: instanceID,
            controlHome: controlHome
        )
    }

    func mintTicket() throws -> String {
        let socketURL = try controlSocketURL()
        let request: JSONValue = [
            "protocol": 1,
            "id": 1,
            "verb": "session-ticket",
            "params": [
                "profile_id": .string(profileID),
                "instance_id": .string(instanceID),
                "purpose": "interactive",
            ],
        ]
        let payload = try request.data()
        let response = try UnixSocket.send(payload + Data([0x0A]), path: socketURL.path)
        let answer = try JSONValue(from: response)
        guard answer["ok"]?.boolValue == true,
              let grant = answer["result"],
              let ticket = grant["ticket"]?.stringValue
        else {
            throw HermesError.connectionFailed("gateway refused the session ticket")
        }
        guard grant["profile_id"]?.stringValue == profileID,
              grant["instance_id"]?.stringValue == instanceID
        else {
            throw HermesError.connectionFailed("gateway ticket identity mismatch")
        }
        return ticket
    }

    var webSocketURL: URL? {
        let origin = apiOrigin
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: origin + "/api/ws")
    }

    private func controlSocketURL() throws -> URL {
        let home = URL(fileURLWithPath: controlHome)
        let direct = home.appendingPathComponent("gateway.sock")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        let pointer = home.appendingPathComponent("gateway.sock.path")
        if let path = try? String(contentsOf: pointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty
        {
            return URL(fileURLWithPath: path)
        }
        throw HermesError.connectionFailed("gateway control socket not found")
    }
}

enum ProcessRunner {
    struct Result: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String? = nil,
        timeout: Duration
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory, !currentDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withThrowingTaskGroup(of: Result.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        do {
                            try process.run()
                        } catch {
                            continuation.resume(throwing: error)
                            return
                        }
                        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()
                        continuation.resume(returning: Result(
                            status: process.terminationStatus,
                            stdout: String(data: stdout, encoding: .utf8) ?? "",
                            stderr: String(data: stderr, encoding: .utf8) ?? ""
                        ))
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw HermesError.timeout("gateway ensure")
            }
            guard let result = try await group.next() else {
                throw HermesError.connectionFailed("gateway ensure failed")
            }
            group.cancelAll()
            return result
        }
    }
}

private enum UnixSocket {
    static func send(_ payload: Data, path: String) throws -> Data {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw HermesError.connectionFailed("cannot create control socket")
        }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw HermesError.connectionFailed("gateway control socket path is too long")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
                for (index, byte) in pathBytes.enumerated() {
                    destination[index] = byte
                }
            }
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw HermesError.connectionFailed("cannot connect to the gateway control socket")
        }

        var remaining = [UInt8](payload)
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes {
                write(descriptor, $0.baseAddress, $0.count)
            }
            guard written > 0 else {
                throw HermesError.connectionFailed("cannot write to the gateway control socket")
            }
            remaining.removeFirst(written)
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !response.contains(0x0A) {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            response.append(buffer, count: count)
        }
        guard let newline = response.firstIndex(of: 0x0A) else {
            throw HermesError.connectionFailed("gateway control socket returned no answer")
        }
        return response[..<newline]
    }
}
