import Foundation

/// Splits a markdown document into finished blocks and the block that is still growing.
///
/// Finished blocks never change, so the UI renders them once and only the tail is
/// re-rendered while the answer is streaming.
public enum MarkdownBlockSplitter {
    /// Result of the split: the finished blocks and the trailing block.
    public struct Split: Equatable, Sendable {
        /// Blocks that will not change any more.
        public var completed: [String]
        /// The block that is still being written (may be empty).
        public var tail: String

        public init(completed: [String], tail: String) {
            self.completed = completed
            self.tail = tail
        }
    }

    /// Splits the text at the last empty line outside a code fence.
    public static func split(_ text: String) -> Split {
        guard !text.isEmpty else { return Split(completed: [], tail: "") }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var insideFence = false
        var fenceMarker = ""
        var lastBreakIndex: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(while: { $0 == "`" || $0 == "~" }))
                if !insideFence {
                    insideFence = true
                    fenceMarker = marker
                } else if marker == fenceMarker {
                    insideFence = false
                }
                continue
            }
            if insideFence {
                continue
            }
            if trimmed.isEmpty {
                lastBreakIndex = index
            }
        }

        guard let lastBreakIndex else {
            return Split(completed: [], tail: text)
        }

        let finished = Array(lines[0 ... lastBreakIndex])
        let tail = lines[(lastBreakIndex + 1)...].joined(separator: "\n")
        return Split(completed: blocks(in: finished), tail: tail)
    }

    /// Stable hash of a block, used as the identity of the rendered view.
    public static func stableHash(_ text: String) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01B3
        }
        return Int(hash & 0x0000_0000_FFFF_FFFF)
    }

    /// Groups the finished lines into separate markdown blocks.
    private static func blocks(in lines: [String]) -> [String] {
        var result: [String] = []
        var current: [String] = []
        var insideFence = false
        var fenceMarker = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(while: { $0 == "`" || $0 == "~" }))
                if !insideFence {
                    insideFence = true
                    fenceMarker = marker
                } else if marker == fenceMarker {
                    insideFence = false
                }
            }
            current.append(line)
            if !insideFence, trimmed.isEmpty {
                let block = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !block.isEmpty {
                    result.append(block)
                }
                current = []
            }
        }

        let rest = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty {
            result.append(rest)
        }
        return result
    }
}
