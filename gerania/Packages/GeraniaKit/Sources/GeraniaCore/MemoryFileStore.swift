import Darwin
import Foundation

/// Reads and writes the curated Hermes memory files.
///
/// The store speaks the same format as `MemoryStore` in Hermes: entries joined
/// by `\n§\n`, UTF-8, atomic replacement, and the same `USER.md.lock` /
/// `MEMORY.md.lock` files, so the agent and the settings window never write at
/// the same time. Every save compares the file fingerprint taken at load: if
/// Hermes or a human changed the file, the save is refused instead of silently
/// dropping the other side's entries.
public actor MemoryFileStore {
    /// `~/.hermes/memories`, or `<HERMES_HOME>/memories`.
    public nonisolated let directory: URL
    /// Character budgets, read from `config.yaml` or Hermes defaults.
    public nonisolated let limits: MemoryLimits

    public init(directory: URL? = nil, limits: MemoryLimits = .standard) {
        self.directory = directory ?? Self.defaultDirectory()
        self.limits = limits
    }

    public nonisolated static func defaultDirectory() -> URL {
        if let home = ProcessInfo.processInfo.environment["HERMES_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath)
                .appendingPathComponent("memories", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".hermes/memories", isDirectory: true)
    }

    public nonisolated func url(for kind: MemoryKind) -> URL {
        directory.appendingPathComponent(kind.fileName)
    }

    public func load(_ kind: MemoryKind) throws -> MemoryDocument {
        try withLock(kind) {
            try readLocked(kind)
        }
    }

    public func add(
        _ text: String,
        to kind: MemoryKind,
        ifUnchanged fingerprint: MemoryFingerprint?
    ) throws -> MemoryDocument {
        try add([text], to: kind, ifUnchanged: fingerprint)
    }

    public func add(
        _ texts: [String],
        to kind: MemoryKind,
        ifUnchanged fingerprint: MemoryFingerprint?
    ) throws -> MemoryDocument {
        try mutate(kind, expected: fingerprint) { document in
            try document.adding(contentsOf: texts)
        }
    }

    public func replace(
        at index: Int,
        with text: String,
        in kind: MemoryKind,
        ifUnchanged fingerprint: MemoryFingerprint?
    ) throws -> MemoryDocument {
        try mutate(kind, expected: fingerprint) { document in
            try document.replacing(at: index, with: text)
        }
    }

    public func remove(
        at index: Int,
        in kind: MemoryKind,
        ifUnchanged fingerprint: MemoryFingerprint?
    ) throws -> MemoryDocument {
        try mutate(kind, expected: fingerprint) { document in
            try document.removing(at: index)
        }
    }

    public func clear(
        _ kind: MemoryKind,
        ifUnchanged fingerprint: MemoryFingerprint?
    ) throws -> MemoryDocument {
        try mutate(kind, expected: fingerprint) { document in
            document.cleared()
        }
    }

    private func mutate(
        _ kind: MemoryKind,
        expected: MemoryFingerprint?,
        change: (MemoryDocument) throws -> MemoryDocument
    ) throws -> MemoryDocument {
        try withLock(kind) {
            let current = try readLocked(kind)
            if let expected, expected != current.fingerprint {
                throw MemoryFileError.changedExternally(fileName: kind.fileName)
            }
            let updated = try change(current)
            try writeLocked(updated)
            return try readLocked(kind)
        }
    }

    private func readLocked(_ kind: MemoryKind) throws -> MemoryDocument {
        let path = url(for: kind)
        let exists = FileManager.default.fileExists(atPath: path.path)
        var data = Data()
        if exists {
            do {
                data = try Data(contentsOf: path)
            } catch {
                throw MemoryFileError.unreadable(fileName: kind.fileName)
            }
        }
        guard var raw = String(data: data, encoding: .utf8) else {
            throw MemoryFileError.unreadable(fileName: kind.fileName)
        }
        if raw.hasPrefix("\u{FEFF}") {
            raw.removeFirst()
        }
        let fingerprint = exists ? Self.fingerprint(data: data, path: path) : .missing
        return MemoryDocument.parse(
            kind: kind,
            url: path,
            raw: raw,
            limit: limits.limit(for: kind),
            fingerprint: fingerprint
        )
    }

    private func writeLocked(_ document: MemoryDocument) throws {
        let path = url(for: document.kind)
        do {
            try prepareDirectory()
            try Data(document.serialized.utf8).write(to: path, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path.path
            )
        } catch {
            throw MemoryFileError.writeFailed(
                fileName: document.kind.fileName,
                reason: error.localizedDescription
            )
        }
    }

    private func prepareDirectory() throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? manager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        }
    }

    /// Exclusive lock on `USER.md.lock` / `MEMORY.md.lock`, the same files Hermes uses.
    /// Ten short attempts instead of a blocking wait: the settings window must not
    /// freeze behind a long memory write.
    private func withLock<T>(_ kind: MemoryKind, _ body: () throws -> T) throws -> T {
        try prepareDirectory()
        let lockPath = url(for: kind).path + ".lock"
        let fd = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else {
            throw MemoryFileError.writeFailed(
                fileName: kind.fileName,
                reason: String(cString: strerror(errno))
            )
        }
        defer {
            _ = flock(fd, LOCK_UN)
            close(fd)
        }
        var attempts = 0
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else {
                throw MemoryFileError.busy(fileName: kind.fileName)
            }
            attempts += 1
            guard attempts < 10 else {
                throw MemoryFileError.busy(fileName: kind.fileName)
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return try body()
    }

    private nonisolated static func fingerprint(data: Data, path: URL) -> MemoryFingerprint {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path.path)
        let modified = attributes?[.modificationDate] as? Date ?? .distantPast
        return .file(modifiedAt: modified, size: data.count, digest: digest(data))
    }

    /// FNV-1a: a cheap content check that does not need a crypto dependency.
    private nonisolated static func digest(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
