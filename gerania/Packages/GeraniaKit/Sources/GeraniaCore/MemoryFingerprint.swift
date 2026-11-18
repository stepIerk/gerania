import Foundation

/// What the file looked like when Gerania read it.
///
/// Every save compares the current file with this value: if Hermes or a human
/// edited the memory in the meantime, Gerania refuses to overwrite the change
/// and asks to reload instead. Saving an old snapshot would silently drop
/// entries added by another writer.
public enum MemoryFingerprint: Sendable, Equatable {
    /// There was no file.
    case missing
    /// The file existed with this modification date, size and content digest.
    case file(modifiedAt: Date, size: Int, digest: UInt64)
}
