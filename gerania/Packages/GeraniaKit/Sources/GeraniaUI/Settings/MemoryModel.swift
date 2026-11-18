import Foundation
import GeraniaCore
import Observation

/// State of the «Память» tab.
///
/// The model keeps the last read documents together with their fingerprints.
/// A save passes the fingerprint back to the store: if Hermes wrote something
/// in the meantime, the store refuses and the model reloads the fresh file.
@MainActor
@Observable
public final class MemoryModel {
    /// Documents by file, filled after `load()`.
    public private(set) var documents: [MemoryKind: MemoryDocument] = [:]
    /// Whether the initial read is in flight.
    public private(set) var isLoading = false
    /// A write is in flight; buttons are disabled meanwhile.
    public private(set) var isBusy = false
    /// Russian explanation of the last failure.
    public private(set) var errorMessage: String?

    private let store: MemoryFileStore
    /// Folder with `USER.md` and `MEMORY.md`; shown at the bottom of the tab.
    public nonisolated let directory: URL

    public init(store: MemoryFileStore = MemoryFileStore(limits: MemoryLimits.load())) {
        self.store = store
        directory = store.directory
    }

    public func document(for kind: MemoryKind) -> MemoryDocument? {
        documents[kind]
    }

    /// Reads both files. One unreadable file does not hide the other.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let failure = await reloadSilently()
        errorMessage = failure.map(message(for:))
    }

    /// Adds one fact to the end of the file.
    public func addFact(_ text: String, to kind: MemoryKind) async -> Bool {
        await addFacts([text], to: kind)
    }

    /// Adds several facts in one atomic write, used by the acquaintance form.
    public func addFacts(_ texts: [String], to kind: MemoryKind) async -> Bool {
        guard let fingerprint = documents[kind]?.fingerprint else { return false }
        return await run {
            try await self.store.add(texts, to: kind, ifUnchanged: fingerprint)
        }
    }

    /// Replaces one entry after the editor sheet.
    public func replaceEntry(_ text: String, at index: Int, in kind: MemoryKind) async -> Bool {
        guard let fingerprint = documents[kind]?.fingerprint else { return false }
        return await run {
            try await self.store.replace(at: index, with: text, in: kind, ifUnchanged: fingerprint)
        }
    }

    /// Forgets exactly one entry.
    public func removeEntry(at index: Int, in kind: MemoryKind) async -> Bool {
        guard let fingerprint = documents[kind]?.fingerprint else { return false }
        return await run {
            try await self.store.remove(at: index, in: kind, ifUnchanged: fingerprint)
        }
    }

    /// Forgets everything in one file.
    public func clear(_ kind: MemoryKind) async -> Bool {
        guard let fingerprint = documents[kind]?.fingerprint else { return false }
        return await run {
            try await self.store.clear(kind, ifUnchanged: fingerprint)
        }
    }

    /// Dismisses the error banner.
    public func dismissError() {
        errorMessage = nil
    }

    private func run(_ operation: () async throws -> MemoryDocument) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await operation()
            documents[updated.kind] = updated
            errorMessage = nil
            return true
        } catch {
            await handle(error)
            return false
        }
    }

    private func handle(_ error: Error) async {
        if case MemoryFileError.changedExternally = error {
            await reloadSilently()
        }
        if case MemoryFileError.missingEntry = error {
            await reloadSilently()
        }
        errorMessage = message(for: error)
    }

    @discardableResult
    private func reloadSilently() async -> Error? {
        var failure: Error?
        var loaded: [MemoryKind: MemoryDocument] = [:]
        for kind in MemoryKind.allCases {
            do {
                loaded[kind] = try await store.load(kind)
            } catch {
                failure = failure ?? error
            }
        }
        documents.merge(loaded) { _, new in new }
        return failure
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
