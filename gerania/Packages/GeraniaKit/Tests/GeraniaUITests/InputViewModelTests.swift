import Foundation
import GeraniaCore
import GeraniaUI
import Testing

@Suite("Мини-окно ввода")
@MainActor
struct InputViewModelTests {
    private func model() -> InputViewModel {
        InputViewModel()
    }

    @Test("Отправка очищает поле и передаёт текст")
    func send() {
        let model = model()
        var sent: [(String, Bool)] = []
        model.onSend = { sent.append(($0, $1)) }

        model.text = "  привет  "
        model.handle(.send)

        #expect(sent.count == 1)
        #expect(sent.first?.0 == "привет")
        #expect(sent.first?.1 == false)
        #expect(model.text.isEmpty)
    }

    @Test("Пустой текст не отправляется")
    func emptyIsNotSent() {
        let model = model()
        var sent = 0
        model.onSend = { _, _ in sent += 1 }

        model.text = "   "
        model.handle(.send)

        #expect(sent == 0)
        #expect(!model.canSend)
    }

    @Test("Отправка в новый чат помечается флагом")
    func sendInNewChat() {
        let model = model()
        var isNew = false
        model.onSend = { _, new in isNew = new }

        model.text = "вопрос"
        model.handle(.sendInNewChat)

        #expect(isNew)
    }

    @Test("Shift+возврат добавляет строку в текст")
    func newline() {
        let model = model()

        model.text = "первая"
        model.handle(.newline)

        #expect(model.text == "первая\n")
    }

    @Test("История подставляется в пустое поле")
    func historyBrowsing() {
        let model = model()
        model.remember("старый вопрос")
        model.remember("новый вопрос")

        model.handle(.previousPrompt)
        #expect(model.text == "новый вопрос")

        model.handle(.previousPrompt)
        #expect(model.text == "старый вопрос")

        model.handle(.nextPrompt)
        #expect(model.text == "новый вопрос")

        model.handle(.nextPrompt)
        #expect(model.text.isEmpty)
    }

    @Test("История не мешает, когда в поле есть текст")
    func historyIgnoredWhenTyping() {
        let model = model()
        model.remember("старый вопрос")
        model.text = "свой текст"

        model.handle(.previousPrompt)

        #expect(model.text == "свой текст")
    }

    @Test("Escape закрывает окно")
    func escapeCloses() {
        let model = model()
        var closed = false
        model.onClose = { closed = true }

        model.handle(.close)

        #expect(closed)
    }

    @Test("Список чатов запрашивается по ⌘K")
    func chatList() {
        let model = model()
        var opened = false
        model.onOpenChatList = { opened = true }

        model.handle(.openChatList)
        #expect(opened)
    }

    @Test("Выбор чата меняет заголовок")
    func selectChat() {
        let model = model()
        var selected: String?
        model.onSelectChat = { selected = $0 }

        model.selectChat(id: "local-1", title: "Мой чат")

        #expect(model.chatTitle == "Мой чат")
        #expect(selected == "local-1")
    }

    @Test("Новый чат сбрасывает заголовок")
    func newChat() {
        let model = model()
        model.chatTitle = "Старый"
        var created = false
        model.onNewChat = { created = true }

        model.handle(.newChat)

        #expect(created)
        #expect(model.chatTitle == "Новый чат")
    }

    @Test("Окно ввода растёт с длиной строки и упирается в максимум")
    func preferredWidth() {
        let model = model()
        #expect(model.preferredWidth == InputViewModel.baseWidth)

        model.text = String(repeating: "а", count: 40)
        #expect(model.preferredWidth > InputViewModel.baseWidth)
        #expect(model.preferredWidth < InputViewModel.maximumWidth)

        model.text = String(repeating: "а", count: 200)
        #expect(model.preferredWidth == InputViewModel.maximumWidth)
        #expect(model.contentWidth == InputViewModel.maximumWidth - 12)
    }
}
