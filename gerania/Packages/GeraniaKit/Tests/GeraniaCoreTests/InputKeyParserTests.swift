import Foundation
import GeraniaCore
import Testing

@Suite("InputKeyParser")
struct InputKeyParserTests {
    @Test("Возврат отправляет текст")
    func returnSends() {
        #expect(InputKeyParser.command(for: .returnKey) == .send)
    }

    @Test("Shift+возврат добавляет строку")
    func shiftReturnAddsLine() {
        #expect(InputKeyParser.command(for: .returnKey, shift: true) == .newline)
    }

    @Test("Command+возврат отправляет в новый чат")
    func commandReturnSendsToNewChat() {
        #expect(InputKeyParser.command(for: .returnKey, command: true) == .sendInNewChat)
    }

    @Test("Escape закрывает окно")
    func escapeCloses() {
        #expect(InputKeyParser.command(for: .escape) == .close)
    }

    @Test("Стрелки листают историю")
    func arrowsBrowseHistory() {
        #expect(InputKeyParser.command(for: .up) == .previousPrompt)
        #expect(InputKeyParser.command(for: .down) == .nextPrompt)
    }

    @Test("Command+K открывает список чатов")
    func commandKOpensChatList() {
        #expect(InputKeyParser.command(for: .character("k"), command: true) == .openChatList)
        #expect(InputKeyParser.command(for: .character("K"), command: true) == .openChatList)
        #expect(InputKeyParser.command(for: .character("k")) == .none)
    }

    @Test("Command+N начинает новый чат")
    func commandNStartsNewChat() {
        #expect(InputKeyParser.command(for: .character("n"), command: true) == .newChat)
        #expect(InputKeyParser.command(for: .character("n")) == .none)
    }

    @Test("Остальные клавиши — не команды")
    func otherKeys() {
        #expect(InputKeyParser.command(for: .character("a")) == .none)
        #expect(InputKeyParser.command(for: .character("z"), shift: true) == .none)
    }
}
