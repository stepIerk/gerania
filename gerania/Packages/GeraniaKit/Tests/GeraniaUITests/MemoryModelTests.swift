import Foundation
import GeraniaCore
import GeraniaUI
import Testing

@Suite("Модель памяти")
@MainActor
struct MemoryModelTests {
    private func setup() -> (MemoryModel, MemoryFileStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gerania-memory-model-\(UUID().uuidString)", isDirectory: true)
        let store = MemoryFileStore(directory: directory)
        return (MemoryModel(store: store), store)
    }

    @Test("Загрузка читает оба файла")
    func load() async throws {
        let (model, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        _ = try await store.add("Студент", to: .user, ifUnchanged: nil)
        _ = try await store.add("Любит Swift", to: .notes, ifUnchanged: nil)

        await model.load()

        #expect(model.document(for: .user)?.entries == ["Студент"])
        #expect(model.document(for: .notes)?.entries == ["Любит Swift"])
        #expect(model.errorMessage == nil)
    }

    @Test("Добавление обновляет документ без перезагрузки")
    func addFact() async {
        let (model, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        await model.load()

        let added = await model.addFact("Пары по средам в 10:00", to: .user)

        #expect(added)
        #expect(model.document(for: .user)?.entries == ["Пары по средам в 10:00"])
        #expect(model.errorMessage == nil)
    }

    @Test("Пакетная запись обновляет профиль")
    func addFacts() async {
        let (model, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        await model.load()

        let added = await model.addFacts(["Обращаться: Степан.", "Город: Москва."], to: .user)

        #expect(added)
        #expect(model.document(for: .user)?.entries == ["Обращаться: Степан.", "Город: Москва."])
    }

    @Test("Удаление убирает ровно одну запись")
    func removeEntry() async {
        let (model, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        await model.load()
        _ = await model.addFact("Первая", to: .notes)
        _ = await model.addFact("Вторая", to: .notes)

        let removed = await model.removeEntry(at: 0, in: .notes)

        #expect(removed)
        #expect(model.document(for: .notes)?.entries == ["Вторая"])
    }

    @Test("Внешнее изменение не затирается и объясняется")
    func externalChange() async throws {
        let (model, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        await model.load()
        try Data("Запись, добавленная извне".utf8).write(to: store.url(for: .user))

        let added = await model.addFact("Моя запись", to: .user)

        #expect(!added)
        #expect(model.errorMessage?.contains("изменили извне") == true)
        #expect(model.document(for: .user)?.entries == ["Запись, добавленная извне"])
    }

    @Test("Очистка освобождает файл")
    func clear() async {
        let (model, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        await model.load()
        _ = await model.addFact("Временная", to: .user)

        let cleared = await model.clear(.user)

        #expect(cleared)
        #expect(model.document(for: .user)?.entries.isEmpty == true)
    }
}
