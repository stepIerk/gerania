import Foundation
import GeraniaCore

/// Turns the JSON a tool returned into one human line for the answer window.
///
/// Hermes sends the whole result in `tool.complete`: page content, search hits,
/// terminal output. The window needs «5 результатов · Swift 6», not the payload.
/// Unknown shapes yield `nil`: an empty line is better than a wall of JSON.
public enum ToolResultSummary {
    public static func text(name: String, result: JSONValue?) -> String? {
        guard let result else { return nil }
        let value = decoded(result)
        let tool = normalize(name)

        if let error = value["error"]?.stringValue, !error.isEmpty {
            return clean("не удалось: \(error)")
        }
        if tool.contains("web_search") {
            return searchSummary(value)
        }
        if tool.contains("web_extract") {
            return extractSummary(value)
        }
        if tool.contains("terminal") || tool.contains("shell") {
            if let code = value["exit_code"]?.intValue, code != 0 {
                return "код \(code)"
            }
            if let output = value["output"]?.stringValue, let line = firstLine(output) {
                return clean(line)
            }
            return nil
        }
        if tool.contains("read_file") || tool.contains("write_file") {
            if let bytes = value["size"]?.intValue ?? value["bytes"]?.intValue {
                return "\(bytes) байт"
            }
            return nil
        }
        if let title = value["title"]?.stringValue, !title.isEmpty {
            return clean(title)
        }
        if let text = value["text_summary"]?.stringValue, let line = firstLine(text) {
            return clean(line)
        }
        if let url = value["url"]?.stringValue {
            return clean(location(url))
        }
        return nil
    }

    private static func searchSummary(_ value: JSONValue) -> String? {
        guard let results = value["data"]?["web"]?.arrayValue else {
            return value["success"]?.boolValue == false ? "ничего не найдено" : nil
        }
        guard let first = results.first else { return "ничего не найдено" }
        let count = results.count
        let noun = plural(count, "результат", "результата", "результатов")
        return join("\(count) \(noun)", first["title"]?.stringValue)
    }

    private static func extractSummary(_ value: JSONValue) -> String? {
        guard let results = value["results"]?.arrayValue, let first = results.first else {
            return value["success"]?.boolValue == false ? "страница недоступна" : nil
        }
        let count = results.count
        let noun = plural(count, "страница", "страницы", "страниц")
        let title = first["title"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        return join("\(count) \(noun)", title ?? location(first["url"]?.stringValue))
    }

    private static func join(_ first: String?, _ second: String?) -> String? {
        let parts = [first, second].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Hermes sends `result` as a JSON string in gateway events and as an object
    /// in newer payloads; both shapes are read the same way.
    private static func decoded(_ result: JSONValue) -> JSONValue {
        guard let text = result.stringValue, text.hasPrefix("{") || text.hasPrefix("[") else {
            return result
        }
        return (try? JSONValue(from: Data(text.utf8))) ?? result
    }

    private static func firstLine(_ text: String) -> String? {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    private static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let tail = count % 100
        if (11 ... 14).contains(tail) {
            return many
        }
        return switch count % 10 {
        case 1: one
        case 2 ... 4: few
        default: many
        }
    }

    /// A site host or a file name instead of a full URL or path.
    private static func location(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("data:") {
            return "изображение"
        }
        if let url = URL(string: value), let host = url.host, !host.isEmpty {
            return host
        }
        return URL(fileURLWithPath: value).lastPathComponent
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > 140 ? String(collapsed.prefix(139)) + "…" : collapsed
    }

    private static func normalize(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["functions.", "mcp__", "tool:"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        return value
    }
}
