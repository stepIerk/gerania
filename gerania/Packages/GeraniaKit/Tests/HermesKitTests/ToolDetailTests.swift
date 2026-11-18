import Foundation
import GeraniaCore
import HermesKit
import Testing

@Suite("Детали инструментов")
struct ToolDetailTests {
    @Test("Поисковый запрос")
    func webSearch() {
        let args: JSONValue = ["query": "swift 6"]

        let detail = ToolDetail.text(name: "web_search", args: args, context: nil)

        #expect(detail == "swift 6")
    }

    @Test("Открытие сайта из кода browser_exec")
    func browserOpen() {
        let code = "new_tab('https://example.com/docs')\nwait_for_load()"
        let args: JSONValue = ["code": .string(code)]

        let detail = ToolDetail.text(name: "browser_exec", args: args, context: nil)

        #expect(detail == "open · example.com")
    }

    @Test("Скриншот из кода browser_exec")
    func browserScreenshot() {
        let args: JSONValue = ["code": "capture_screenshot()"]

        let detail = ToolDetail.text(name: "browser_exec", args: args, context: nil)

        #expect(detail == "screenshot")
    }

    @Test("Команда из аргументов")
    func terminalCommand() {
        let args: JSONValue = ["command": "date -u +%FT%TZ"]

        let detail = ToolDetail.text(name: "terminal", args: args, context: nil)

        #expect(detail == "date -u +%FT%TZ")
    }

    @Test("Действие компьютера и приложение")
    func computerUse() {
        let args: JSONValue = ["action": "click", "app": "Safari"]

        let detail = ToolDetail.text(name: "computer_use", args: args, context: nil)

        #expect(detail == "click · Safari")
    }

    @Test("Память: действие и цель")
    func memory() {
        let args: JSONValue = [
            "target": "user",
            "operations": [["action": "add", "content": "любит Swift"]],
        ]

        let detail = ToolDetail.text(name: "memory", args: args, context: nil)

        #expect(detail == "add · любит Swift")
    }

    @Test("Путь файла")
    func filePath() {
        let args: JSONValue = ["path": "/tmp/note.md"]

        let detail = ToolDetail.text(name: "read_file", args: args, context: nil)

        #expect(detail == "/tmp/note.md")
    }

    @Test("Контекст используется, когда аргументов нет")
    func contextFallback() {
        let args: JSONValue = ["unrelated": "value"]

        let detail = ToolDetail.text(
            name: "custom_tool",
            args: args,
            context: "  что-то   полезное "
        )

        #expect(detail == "что-то полезное")
    }

    @Test("Длинная деталь обрезается")
    func truncation() {
        let long = String(repeating: "a", count: 300)
        let args: JSONValue = ["query": .string(long)]

        let detail = ToolDetail.text(name: "web_search", args: args, context: nil)

        #expect(detail?.count == 140)
        #expect(detail?.hasSuffix("…") == true)
    }

    @Test("Итог поиска — число результатов и первый заголовок")
    func searchSummary() {
        let result: JSONValue = .string(#"""
        {"success": true, "data": {"web": [
          {"title": "Swift 6 concurrency", "url": "https://example.com"},
          {"title": "Second result", "url": "https://example.org"}
        ]}}
        """#)

        let summary = ToolResultSummary.text(name: "web_search", result: result)

        #expect(summary == "2 результата · Swift 6 concurrency")
    }

    @Test("Пустой поиск говорит об этом прямо")
    func emptySearchSummary() {
        let result: JSONValue = ["success": true, "data": ["web": []]]

        let summary = ToolResultSummary.text(name: "web_search", result: result)

        #expect(summary == "ничего не найдено")
    }

    @Test("Итог чтения страницы — число страниц и заголовок")
    func extractSummary() {
        let result: JSONValue = [
            "results": [
                ["url": "https://developer.apple.com/swift", "title": "Swift", "content": "..."],
            ],
        ]

        let summary = ToolResultSummary.text(name: "web_extract", result: result)

        #expect(summary == "1 страница · Swift")
    }

    @Test("Ошибка инструмента объясняется")
    func errorSummary() {
        let result: JSONValue = ["success": false, "error": "No web search provider configured"]

        let summary = ToolResultSummary.text(name: "web_search", result: result)

        #expect(summary?.contains("не удалось") == true)
        #expect(summary?.contains("No web search provider") == true)
    }

    @Test("Терминал показывает код ошибки или первую строку")
    func terminalSummary() {
        let failure: JSONValue = ["output": "boom", "exit_code": 2]
        let success: JSONValue = ["output": "line one\nline two", "exit_code": 0]

        #expect(ToolResultSummary.text(name: "terminal", result: failure) == "код 2")
        #expect(ToolResultSummary.text(name: "terminal", result: success) == "line one")
    }

    @Test("Неизвестный JSON не превращается в стену текста")
    func unknownSummary() {
        #expect(ToolResultSummary.text(name: "custom_tool", result: ["ok": true]) == nil)
        #expect(ToolResultSummary.text(name: "custom_tool", result: nil) == nil)
    }
}
