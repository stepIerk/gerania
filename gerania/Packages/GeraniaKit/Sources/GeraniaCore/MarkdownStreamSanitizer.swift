import Foundation

/// Makes a partially received markdown document safe to render.
///
/// The sanitizer never rewrites the finished part of the text: it only closes markup
/// that is still open at the very end (code fence, `**`, `_`, `` ` ``) and drops a table
/// row that is still being typed.
public enum MarkdownStreamSanitizer {
    /// Returns the text with all open markup closed.
    public static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = dropDanglingTableRow(text)
        result = closeOpenCodeFence(result)
        result = closeOpenInlineMarkup(result)
        return result
    }

    // MARK: - Line classification

    /// A source line together with the fence state it belongs to.
    private struct Line {
        let text: String
        let isInsideFence: Bool
        let isFenceDelimiter: Bool
        let fenceMarker: String?
    }

    /// Splits the text into lines and marks the ones inside a code fence.
    private static func classifiedLines(of text: String) -> [Line] {
        var result: [Line] = []
        var marker: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            var fenceMarker: String?
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let current = String(trimmed.prefix(while: { $0 == "`" || $0 == "~" }))
                if marker == nil {
                    marker = current
                    fenceMarker = current
                } else if marker == current {
                    marker = nil
                    fenceMarker = current
                }
            }
            result.append(Line(
                text: String(raw),
                isInsideFence: marker != nil,
                isFenceDelimiter: fenceMarker != nil,
                fenceMarker: fenceMarker
            ))
        }
        return result
    }

    // MARK: - Code fences

    /// Appends the closing fence when the document ends inside a code block.
    private static func closeOpenCodeFence(_ text: String) -> String {
        var marker: String?
        for line in classifiedLines(of: text) {
            guard let fence = line.fenceMarker else { continue }
            marker = marker == nil ? fence : nil
        }
        guard let marker else { return text }
        return text + "\n" + marker
    }

    // MARK: - Inline markup

    /// Closes bold, italic and inline code that is still open in the last paragraph.
    private static func closeOpenInlineMarkup(_ text: String) -> String {
        let paragraph = lastParagraph(of: text)
        guard !paragraph.isEmpty, let closing = openInlineMarker(in: paragraph) else { return text }
        return text + closing
    }

    /// Returns the marker that closes the last unclosed inline element.
    private static func openInlineMarker(in paragraph: String) -> String? {
        var backtickRun = 0
        var boldCount = 0
        var starItalicCount = 0
        var underscoreItalicCount = 0

        for line in paragraph.split(separator: "\n", omittingEmptySubsequences: false) {
            var isEscaped = false
            var previous: Character?
            var isLineStart = true
            var index = line.startIndex

            while index < line.endIndex {
                let character = line[index]
                defer { index = line.index(after: index) }

                if isEscaped {
                    isEscaped = false
                    previous = character
                    isLineStart = false
                    continue
                }
                if character == "\\" {
                    isEscaped = true
                    previous = character
                    isLineStart = false
                    continue
                }

                if character == "`" {
                    var run = 1
                    var cursor = line.index(after: index)
                    while cursor < line.endIndex, line[cursor] == "`" {
                        run += 1
                        cursor = line.index(after: cursor)
                    }
                    if backtickRun == 0 {
                        backtickRun = run
                    } else if backtickRun == run {
                        backtickRun = 0
                    }
                    previous = "`"
                    isLineStart = false
                    continue
                }

                if backtickRun > 0 {
                    previous = character
                    isLineStart = false
                    continue
                }

                if character == "*" {
                    var run = 1
                    var cursor = line.index(after: index)
                    while cursor < line.endIndex, line[cursor] == "*" {
                        run += 1
                        cursor = line.index(after: cursor)
                    }
                    let isListMarker = run == 1 && isLineStart && isFollowedBySpace(line, cursor)
                    if !isListMarker {
                        if run >= 2 {
                            boldCount += 1
                        } else {
                            starItalicCount += 1
                        }
                    }
                    previous = "*"
                    isLineStart = false
                    continue
                }

                if character == "_" {
                    var run = 1
                    var cursor = line.index(after: index)
                    while cursor < line.endIndex, line[cursor] == "_" {
                        run += 1
                        cursor = line.index(after: cursor)
                    }
                    let opensItalic = !isWordCharacter(previous)
                    if opensItalic {
                        if run >= 2 {
                            boldCount += 1
                        } else {
                            underscoreItalicCount += 1
                        }
                    }
                    previous = "_"
                    isLineStart = false
                    continue
                }

                if !character.isWhitespace {
                    isLineStart = false
                }
                previous = character
            }
        }

        if backtickRun > 0 {
            return String(repeating: "`", count: backtickRun)
        }
        if boldCount % 2 == 1 {
            return "**"
        }
        if starItalicCount % 2 == 1 {
            return "*"
        }
        if underscoreItalicCount % 2 == 1 {
            return "_"
        }
        return nil
    }

    private static func isFollowedBySpace(_ line: Substring, _ index: Substring.Index) -> Bool {
        guard index < line.endIndex else { return true }
        return line[index].isWhitespace
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }

    /// Text after the last empty line, ignoring code fences: the paragraph being typed.
    private static func lastParagraph(of text: String) -> String {
        let lines = classifiedLines(of: text)
        var result: [String] = []
        for line in lines.reversed() where !line.isInsideFence && !line.isFenceDelimiter {
            if line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            result.append(line.text)
        }
        return result.reversed().joined(separator: "\n")
    }

    // MARK: - Tables

    /// Removes the last table row when it does not match the header yet.
    private static func dropDanglingTableRow(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3 else { return text }

        let last = lines[lines.count - 1].trimmingCharacters(in: .whitespaces)
        guard last.hasPrefix("|"), last.count > 1 else { return text }

        let separator = lines[lines.count - 2].trimmingCharacters(in: .whitespaces)
        guard isSeparatorRow(separator) else { return text }

        let header = lines[lines.count - 3].trimmingCharacters(in: .whitespaces)
        guard header.hasPrefix("|") else { return text }

        let headerCells = cellCount(header)
        let rowCells = cellCount(last)
        guard headerCells > 0, rowCells != headerCells else { return text }
        lines.removeLast()
        return lines.joined(separator: "\n")
    }

    private static func isSeparatorRow(_ text: String) -> Bool {
        guard text.hasPrefix("|") else { return false }
        let cells = text.split(separator: "|", omittingEmptySubsequences: false)
        guard cells.count > 2 else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func cellCount(_ row: String) -> Int {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return 0 }
        let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
        return max(0, parts.count - 2)
    }
}
