import Foundation

/// Human-readable description of a tool call for the HUD.
public struct ToolActivity: Equatable, Sendable {
    /// What the assistent is doing now, in Russian.
    public let title: String
    /// The object of the action: a query, a site, a file or an app.
    public let detail: String?
    /// SF Symbol that matches the action.
    public let symbol: String

    public init(title: String, detail: String?, symbol: String) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }
}

/// Turns the technical tool name and its arguments into a phrase a person understands.
///
/// Hermes reports names such as `browser_exec` or `computer_use`; the HUD should
/// say «Открываю сайт» and «Кликаю». The detail is produced by `ToolDetail` and
/// uses ` · ` to separate the verb from its object.
public enum ToolActivityFormatter {
    public static func activity(for chip: ToolChip) -> ToolActivity {
        activity(name: chip.name, detail: chip.detail)
    }

    public static func activity(name: String, detail: String?) -> ToolActivity {
        let tool = normalized(name)
        let (head, tail) = split(detail)
        let subtitle = tail ?? (head.isEmpty ? nil : head)

        if tool.contains("browser_exec") {
            return browser(head: head, subtitle: subtitle, symbol: "safari")
        }
        if tool.contains("browser_cdp") {
            return ToolActivity(title: "Работаю с браузером", detail: subtitle, symbol: "safari")
        }
        if tool.contains("browser_dialog") {
            return ToolActivity(title: "Отвечаю в диалоге браузера", detail: subtitle, symbol: "safari")
        }
        if tool.contains("browser_vault") {
            return ToolActivity(title: "Вхожу на сайт", detail: subtitle, symbol: "key")
        }
        if tool.contains("computer_use") {
            return computer(head: head, subtitle: subtitle)
        }
        if tool.contains("web_search") {
            return ToolActivity(title: "Ищу в интернете", detail: subtitle, symbol: "magnifyingglass")
        }
        if tool.contains("web_extract") {
            return ToolActivity(title: "Читаю страницу", detail: subtitle, symbol: "doc.text.magnifyingglass")
        }
        if tool.contains("vision") {
            return ToolActivity(title: "Смотрю изображение", detail: subtitle, symbol: "eye")
        }
        if tool.contains("image_generate") {
            return ToolActivity(title: "Рисую изображение", detail: subtitle, symbol: "photo")
        }
        if tool.contains("terminal") || tool.contains("shell") {
            return ToolActivity(title: "Выполняю команду", detail: subtitle, symbol: "terminal")
        }
        if tool.contains("process_manage") {
            return ToolActivity(title: "Управляю процессом", detail: subtitle, symbol: "terminal")
        }
        if tool.contains("read_file") {
            return ToolActivity(title: "Читаю файл", detail: subtitle, symbol: "doc.text")
        }
        if tool.contains("search_files") {
            return ToolActivity(title: "Ищу в файлах", detail: subtitle, symbol: "doc.text.magnifyingglass")
        }
        if tool.contains("write_file") {
            return ToolActivity(title: "Пишу файл", detail: subtitle, symbol: "square.and.pencil")
        }
        if tool.contains("patch") {
            return ToolActivity(title: "Правлю файл", detail: subtitle, symbol: "square.and.pencil")
        }
        if tool.contains("memory") {
            return memory(head: head, subtitle: subtitle)
        }
        if tool.contains("cronjob") {
            return plan(head: head, subtitle: subtitle)
        }
        if tool.contains("session_search") {
            return ToolActivity(title: "Ищу в прошлых разговорах", detail: subtitle, symbol: "clock.arrow.circlepath")
        }
        if tool.contains("delegate_task") {
            return ToolActivity(title: "Передаю подзадачу", detail: subtitle, symbol: "arrow.triangle.branch")
        }
        if tool.contains("clarify") {
            return ToolActivity(title: "Уточняю", detail: subtitle, symbol: "questionmark.bubble")
        }
        if tool.contains("skill_manage") {
            return ToolActivity(title: "Меняю навык", detail: subtitle, symbol: "book")
        }
        if tool.contains("skill_view") {
            return ToolActivity(title: "Открываю навык", detail: subtitle, symbol: "book")
        }
        if tool.contains("skills_list") {
            return ToolActivity(title: "Смотрю навыки", detail: subtitle, symbol: "book")
        }
        if tool.contains("todo_list") {
            return ToolActivity(title: "Планирую шаги", detail: subtitle, symbol: "checklist")
        }
        if tool.contains("execute_code") {
            return ToolActivity(
                title: "Выполняю код",
                detail: subtitle,
                symbol: "chevron.left.forwardslash.chevron.right"
            )
        }
        if tool.contains("text_to_speech") {
            return ToolActivity(title: "Готовлю озвучку", detail: subtitle, symbol: "speaker.wave.2")
        }
        if tool.contains("manage_connections") {
            return ToolActivity(title: "Проверяю подключения", detail: subtitle, symbol: "link")
        }

        return ToolActivity(title: title(for: name), detail: subtitle, symbol: "gearshape")
    }

    private static func browser(head: String, subtitle: String?, symbol: String) -> ToolActivity {
        switch head.lowercased() {
        case "open", "new_tab", "goto":
            ToolActivity(title: "Открываю сайт", detail: subtitle, symbol: symbol)
        case "fill", "type":
            ToolActivity(title: "Заполняю поле", detail: subtitle, symbol: symbol)
        case "click":
            ToolActivity(title: "Кликаю на странице", detail: subtitle, symbol: symbol)
        case "screenshot":
            ToolActivity(title: "Делаю скриншот", detail: subtitle, symbol: "camera.viewfinder")
        case "page", "page_info":
            ToolActivity(title: "Смотрю страницу", detail: subtitle, symbol: symbol)
        case "js", "cdp":
            ToolActivity(title: "Выполняю скрипт на странице", detail: subtitle, symbol: symbol)
        default:
            ToolActivity(title: "Работаю в браузере", detail: subtitle, symbol: symbol)
        }
    }

    private static func computer(head: String, subtitle: String?) -> ToolActivity {
        let title = switch head.lowercased() {
        case "capture": "Смотрю экран"
        case "click", "double_click", "right_click", "middle_click": "Кликаю"
        case "type": "Печатаю"
        case "set_value": "Выбираю значение"
        case "key": "Нажимаю клавиши"
        case "scroll": "Прокручиваю"
        case "drag": "Перетаскиваю"
        case "wait": "Жду"
        case "list_apps": "Смотрю приложения"
        case "list_windows": "Смотрю окна"
        case "focus_app": "Переключаю приложение"
        default: "Управляю компьютером"
        }
        return ToolActivity(title: title, detail: subtitle, symbol: "macwindow.on.rectangle")
    }

    private static func memory(head: String, subtitle: String?) -> ToolActivity {
        let title = switch head.lowercased() {
        case "remove": "Удаляю из памяти"
        case "patch": "Уточняю в памяти"
        default: "Запоминаю"
        }
        let target: String? = switch subtitle?.lowercased() {
        case "user": "профиль"
        case "memory": "заметки"
        default: subtitle
        }
        return ToolActivity(title: title, detail: target, symbol: "brain")
    }

    private static func plan(head: String, subtitle: String?) -> ToolActivity {
        let title = switch head.lowercased() {
        case "create", "add": "Создаю план"
        case "list": "Смотрю планы"
        case "update", "edit": "Меняю план"
        case "pause": "Ставлю план на паузу"
        case "resume": "Возобновляю план"
        case "remove", "rm", "delete": "Удаляю план"
        case "run": "Запускаю план"
        case "cancel": "Останавливаю план"
        default: "Работаю с планами"
        }
        return ToolActivity(title: title, detail: subtitle, symbol: "calendar.badge.clock")
    }

    private static func normalized(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["functions.", "mcp__", "tool:"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        return value
    }

    /// Splits `verb · object`; both parts are trimmed and empty parts are dropped.
    private static func split(_ detail: String?) -> (head: String, tail: String?) {
        guard let detail else { return ("", nil) }
        let text = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ("", nil) }
        let parts = text.components(separatedBy: " · ")
        guard parts.count > 1 else { return (text, nil) }
        let head = parts[0].trimmingCharacters(in: .whitespaces)
        let tail = parts.dropFirst().joined(separator: " · ").trimmingCharacters(in: .whitespaces)
        return (head, tail.isEmpty ? nil : tail)
    }

    /// Turns `read_file` into «read file» for tools without a dedicated phrase.
    private static func title(for name: String) -> String {
        let text = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Инструмент" }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
