import Foundation
import GeraniaCore

/// Extracts the useful part of a tool call for the activity line.
///
/// Hermes sends the full arguments and result with every `tool.start`. The HUD
/// needs one short phrase instead: the query, the site, the command, the app.
/// The result uses ` · ` to separate the verb from its object.
public enum ToolDetail {
    public static func text(name: String, args: JSONValue?, context: String?) -> String? {
        let tool = normalize(name)
        let explicit = explicit(tool: tool, args: args)
        return clean(explicit ?? context)
    }

    private static func explicit(tool: String, args: JSONValue?) -> String? {
        if tool.contains("web_search") {
            return args?["query"]?.stringValue
        }
        if tool.contains("web_extract") {
            return args?["url"]?.stringValue ?? args?["urls"]?[0]?.stringValue
        }
        if tool.contains("browser_exec") {
            return browserCode(args?["code"]?.stringValue)
        }
        if tool.contains("browser_cdp") {
            return args?["method"]?.stringValue
        }
        if tool.contains("browser_dialog") {
            return args?["action"]?.stringValue
        }
        if tool.contains("browser_vault") {
            return args?["action"]?.stringValue ?? args?["service"]?.stringValue
        }
        if tool.contains("computer_use") {
            return computer(args)
        }
        if tool.contains("vision") {
            return location(args?["image_url"]?.stringValue) ?? args?["question"]?.stringValue
        }
        if tool.contains("image_generate") {
            return args?["prompt"]?.stringValue
        }
        if tool.contains("terminal") || tool.contains("shell") {
            return args?["command"]?.stringValue
        }
        if tool.contains("process_manage") {
            return join(args?["action"]?.stringValue, args?["pid"]?.intValue.map(String.init))
        }
        if tool.contains("search_files") {
            return args?["query"]?.stringValue
                ?? args?["pattern"]?.stringValue
                ?? args?["path"]?.stringValue
        }
        if tool.contains("read_file") || tool.contains("write_file") || tool.contains("patch") {
            return args?["path"]?.stringValue ?? args?["file_path"]?.stringValue
        }
        if tool.contains("memory") {
            let first = args?["operations"]?[0]
            let action = first?["action"]?.stringValue
                ?? args?["action"]?.stringValue
                ?? "add"
            let content = first?["content"]?.stringValue
                ?? args?["content"]?.stringValue
                ?? args?["new_text"]?.stringValue
                ?? first?["old_text"]?.stringValue
                ?? args?["old_text"]?.stringValue
            if let content {
                let extra = max(0, (args?["operations"]?.arrayValue?.count ?? 1) - 1)
                return join(action, extra > 0 ? "\(content) +\(extra)" : content)
            }
            let target = args?["target"]?.stringValue ?? "memory"
            return join(action, target)
        }
        if tool.contains("cronjob") {
            let action = args?["action"]?.stringValue
            let object = args?["name"]?.stringValue
                ?? args?["schedule"]?.stringValue
                ?? args?["job_id"]?.stringValue
            return join(action, object)
        }
        if tool.contains("session_search") {
            return args?["query"]?.stringValue
        }
        if tool.contains("delegate_task") {
            return args?["goal"]?.stringValue
                ?? args?["task"]?.stringValue
                ?? args?["prompt"]?.stringValue
        }
        if tool.contains("skill_view") || tool.contains("skill_manage") {
            return args?["name"]?.stringValue ?? args?["skill"]?.stringValue
        }
        if tool.contains("clarify") {
            return args?["question"]?.stringValue
        }
        if tool.contains("execute_code") {
            let code = args?["code"]?.stringValue ?? args?["script"]?.stringValue
            return code?.split(separator: "\n").first.map(String.init)
        }
        if tool.contains("text_to_speech") {
            return args?["text"]?.stringValue
        }
        if tool.contains("manage_connections") {
            return args?["action"]?.stringValue ?? args?["service"]?.stringValue
        }

        for key in ["query", "command", "path", "file_path", "url", "prompt", "name", "goal", "task"] {
            if let value = args?[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func computer(_ args: JSONValue?) -> String? {
        let action = args?["action"]?.stringValue ?? "capture"
        var parts = [action]

        if let app = args?["app"]?.stringValue, !app.isEmpty {
            parts.append(app)
        } else if let element = args?["element"]?.intValue {
            parts.append("#\(element)")
        } else if let key = args?["key"]?.stringValue, !key.isEmpty {
            parts.append(key)
        } else if let value = args?["value"]?.stringValue, !value.isEmpty {
            parts.append(value)
        } else if let text = args?["text"]?.stringValue, !text.isEmpty {
            parts.append(String(text.prefix(40)))
        } else if let coordinate = args?["coordinate"]?.arrayValue {
            let values = coordinate.compactMap(\.intValue)
            if values.count == 2 {
                parts.append("\(values[0]),\(values[1])")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Reads the intent out of the Python snippet `browser_exec` receives.
    private static func browserCode(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }

        if let url = firstMatch(#"(?:new_tab|goto_url)\s*\(\s*["']([^"']+)"#, in: code) {
            return "open · \(location(url) ?? url)"
        }
        if code.contains("capture_screenshot") {
            return "screenshot"
        }
        if let selector = firstMatch(#"fill_input\s*\(\s*["']([^"']*)"#, in: code) {
            return "fill · \(selector)"
        }
        if code.contains("click_at_xy") {
            return "click"
        }
        if code.contains("page_info(") {
            return "page"
        }
        if code.contains("cdp(") {
            return "cdp"
        }
        if code.contains("js(") {
            return "js"
        }
        return code
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[valueRange])
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

    private static func join(_ first: String?, _ second: String?) -> String? {
        let parts = [first, second].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
