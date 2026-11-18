import GeraniaCore
import Testing

@Suite("Подписи действий")
struct ToolActivityTests {
    @Test("Поиск в интернете")
    func webSearch() {
        let activity = ToolActivityFormatter.activity(name: "web_search", detail: "swift 6 concurrency")

        #expect(activity.title == "Ищу в интернете")
        #expect(activity.detail == "swift 6 concurrency")
        #expect(activity.symbol == "magnifyingglass")
    }

    @Test("Открытие сайта в браузере")
    func browserOpen() {
        let activity = ToolActivityFormatter.activity(name: "browser_exec", detail: "open · example.com")

        #expect(activity.title == "Открываю сайт")
        #expect(activity.detail == "example.com")
        #expect(activity.symbol == "safari")
    }

    @Test("Заполнение поля в браузере")
    func browserFill() {
        let activity = ToolActivityFormatter.activity(name: "browser_exec", detail: "fill · input[name=q]")

        #expect(activity.title == "Заполняю поле")
        #expect(activity.detail == "input[name=q]")
    }

    @Test("Клик по элементу компьютера")
    func computerClick() {
        let activity = ToolActivityFormatter.activity(name: "computer_use", detail: "click · Safari")

        #expect(activity.title == "Кликаю")
        #expect(activity.detail == "Safari")
        #expect(activity.symbol == "macwindow.on.rectangle")
    }

    @Test("Запись в память")
    func memoryAdd() {
        let activity = ToolActivityFormatter.activity(name: "memory", detail: "add · user")

        #expect(activity.title == "Запоминаю")
        #expect(activity.detail == "профиль")
        #expect(activity.symbol == "brain")
    }

    @Test("Создание плана")
    func planCreate() {
        let activity = ToolActivityFormatter.activity(name: "cronjob_manage", detail: "create · Утренний план")

        #expect(activity.title == "Создаю план")
        #expect(activity.detail == "Утренний план")
        #expect(activity.symbol == "calendar.badge.clock")
    }

    @Test("Команда в терминале")
    func terminal() {
        let activity = ToolActivityFormatter.activity(name: "terminal", detail: "date -u")

        #expect(activity.title == "Выполняю команду")
        #expect(activity.detail == "date -u")
        #expect(activity.symbol == "terminal")
    }

    @Test("Префикс функции не мешает")
    func prefixedName() {
        let activity = ToolActivityFormatter.activity(name: "functions.web_search", detail: "weather")

        #expect(activity.title == "Ищу в интернете")
    }

    @Test("Чип отдаёт ту же подпись")
    func chipMapping() {
        let chip = ToolChip(id: "1", name: "read_file", detail: "Package.swift")
        let activity = ToolActivityFormatter.activity(for: chip)

        #expect(activity.title == "Читаю файл")
        #expect(activity.detail == "Package.swift")
    }

    @Test("Неизвестный инструмент остаётся читаемым")
    func unknownTool() {
        let activity = ToolActivityFormatter.activity(name: "mystery_tool", detail: nil)

        #expect(activity.title == "Mystery tool")
        #expect(activity.detail == nil)
        #expect(activity.symbol == "gearshape")
    }
}
