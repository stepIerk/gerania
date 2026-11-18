import Foundation
import GeraniaCore
import GeraniaUI
import HermesKit
import Testing

/// Record of a rename request.
private struct Rename {
    let id: String
    let title: String
}

/// Fake source of the chat list.
@MainActor
private final class FakeChatsService: ChatsService {
    var sessions: [SessionSummary] = []
    var supportsRenaming = true
    var renamed: [Rename] = []
    var listCount = 0

    func listSessions() async -> [SessionSummary] {
        listCount += 1
        return sessions
    }

    func renameSession(id: String, title: String) async throws {
        renamed.append(Rename(id: id, title: title))
        sessions = sessions.map { session in
            guard session.id == id else { return session }
            return SessionSummary(
                id: session.id,
                title: title,
                preview: session.preview,
                updatedAt: session.updatedAt,
                source: session.source,
                cwd: session.cwd,
                startedAt: session.startedAt,
                messageCount: session.messageCount,
                isRunning: session.isRunning
            )
        }
    }
}

@Suite("ChatsModel")
@MainActor
struct ChatsModelTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Everything the tests need.
    private struct Fixture {
        let model: ChatsModel
        let service: FakeChatsService
        let settings: GeraSettings
    }

    private func makeModel() -> Fixture {
        let defaults = UserDefaults(suiteName: "GeraniaUITests-\(UUID().uuidString)") ?? .standard
        let settings = GeraSettings(defaults: defaults)
        let model = ChatsModel(settings: settings, now: { self.now })
        let service = FakeChatsService()
        model.attach(service: service)
        return Fixture(model: model, service: service, settings: settings)
    }

    private func session(
        _ id: String,
        title: String = "Чат",
        preview: String = "",
        daysAgo: Double = 0
    ) -> SessionSummary {
        SessionSummary(
            id: id,
            title: title,
            preview: preview,
            updatedAt: now.addingTimeInterval(-daysAgo * 86400),
            source: "cli"
        )
    }

    @Test("Список загружается и текущая сессия сохраняется")
    func loadsAndPersistsCurrentSession() async {
        let fixture = makeModel()
        let model = fixture.model
        let service = fixture.service
        let settings = fixture.settings
        service.sessions = [session("local-1"), session("local-2")]

        await model.refresh()
        model.select(sessionID: "local-2")

        #expect(model.sessions.count == 2)
        #expect(model.currentSessionID == "local-2")
        #expect(settings.lastSessionID == "local-2")
    }

    @Test("Новый чат забывает текущую сессию")
    func newChatForgetsSession() {
        let fixture = makeModel()
        let model = fixture.model
        let settings = fixture.settings
        settings.lastSessionID = "local-1"

        model.newChat()

        #expect(model.currentSessionID.isEmpty)
    }

    @Test("Поиск ищет по названию, превью и идентификатору")
    func search() async {
        let fixture = makeModel()
        let model = fixture.model
        let service = fixture.service
        service.sessions = [
            session("local-1", title: "Погода в Москве", preview: "дождь"),
            session("local-2", title: "Рецепт", preview: "борщ"),
        ]
        await model.refresh()

        model.query = "москв"
        #expect(model.filteredSessions.map(\.id) == ["local-1"])

        model.query = "борщ"
        #expect(model.filteredSessions.map(\.id) == ["local-2"])

        model.query = "local-2"
        #expect(model.filteredSessions.map(\.id) == ["local-2"])

        model.query = ""
        #expect(model.filteredSessions.count == 2)
    }

    @Test("Чаты делятся на сегодня, вчера и ранее")
    func groupsByDate() async {
        let fixture = makeModel()
        let model = fixture.model
        let service = fixture.service
        service.sessions = [
            session("a", daysAgo: 0),
            session("b", daysAgo: 1),
            session("c", daysAgo: 10),
        ]
        await model.refresh()

        let sections = model.sections

        #expect(sections.map(\.kind) == [.today, .yesterday, .earlier])
        #expect(sections[0].sessions.map(\.id) == ["a"])
        #expect(sections[1].sessions.map(\.id) == ["b"])
        #expect(sections[2].sessions.map(\.id) == ["c"])
    }

    @Test("Переименование идёт через сервис")
    func renamesSession() async {
        let fixture = makeModel()
        let model = fixture.model
        let service = fixture.service
        service.sessions = [session("local-1", title: "Было")]
        await model.refresh()

        await model.rename(sessionID: "local-1", title: "Стало")

        #expect(service.renamed.count == 1)
        #expect(service.renamed.first?.title == "Стало")
        #expect(model.sessions.first?.title == "Стало")
    }

    @Test("Выделение двигается в границах списка")
    func movesSelection() async {
        let fixture = makeModel()
        let model = fixture.model
        let service = fixture.service
        service.sessions = [session("a"), session("b")]
        await model.refresh()

        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 1)

        model.moveSelection(by: 5)
        #expect(model.selectedIndex == 1)

        model.moveSelection(by: -5)
        #expect(model.selectedIndex == 0)
    }
}
