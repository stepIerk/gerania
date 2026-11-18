import Foundation
import GeraniaCore
import Testing

@Suite("Хранилище памяти")
struct MemoryFileStoreTests {
    private func temporaryStore() -> (MemoryFileStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gerania-memory-\(UUID().uuidString)", isDirectory: true)
        return (MemoryFileStore(directory: directory), directory)
    }

    @Test("Пустой каталог читается как пустая память")
    func missingFile() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let document = try await store.load(.user)

        #expect(document.entries.isEmpty)
        #expect(document.fingerprint == .missing)
        #expect(document.url.lastPathComponent == "USER.md")
        #expect(store.url(for: .notes).lastPathComponent == "MEMORY.md")
    }

    @Test("Добавление пишет формат Hermes и перечитывается")
    func addWritesFile() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try await store.add("Люблю Swift", to: .user, ifUnchanged: nil)
        _ = try await store.add("Пары по средам", to: .user, ifUnchanged: first.fingerprint)

        let reloaded = try await store.load(.user)
        let raw = try String(contentsOf: store.url(for: .user), encoding: .utf8)

        #expect(reloaded.entries == ["Люблю Swift", "Пары по средам"])
        #expect(raw == "Люблю Swift\n§\nПары по средам")
    }

    @Test("Пакетная запись добавляет всё одной операцией")
    func addBatch() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let added = try await store.add(
            ["Первая", "Вторая", "Третья"],
            to: .user,
            ifUnchanged: nil
        )

        #expect(added.entries == ["Первая", "Вторая", "Третья"])
        let reloaded = try await store.load(.user)
        #expect(reloaded.entries == added.entries)
    }

    @Test("Переполнение пакета не меняет файл")
    func addBatchLimit() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let added = try await store.add("Первая", to: .user, ifUnchanged: nil)
        let oversized = String(repeating: "я", count: 1400)

        do {
            _ = try await store.add(
                ["Вторая", oversized],
                to: .user,
                ifUnchanged: added.fingerprint
            )
            Issue.record("ожидали отказ по лимиту")
        } catch let error as MemoryFileError {
            guard case .overLimit = error else {
                Issue.record("другая ошибка: \(error)")
                return
            }
        }

        let reloaded = try await store.load(.user)
        #expect(reloaded.entries == ["Первая"])
    }

    @Test("Файл памяти доступен только владельцу")
    func filePermissions() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.add("Секрет", to: .notes, ifUnchanged: nil)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: store.url(for: .notes).path
        )
        let permissions = attributes[.posixPermissions] as? NSNumber

        #expect(permissions?.intValue == 0o600)
    }

    @Test("Внешнее изменение не перезаписывается")
    func externalChange() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await store.load(.user)
        try Data("Запись из Hermes".utf8).write(to: store.url(for: .user))

        do {
            _ = try await store.add("Моя запись", to: .user, ifUnchanged: loaded.fingerprint)
            Issue.record("ожидали отказ из-за внешнего изменения")
        } catch let error as MemoryFileError {
            #expect(error == .changedExternally(fileName: "USER.md"))
        }

        let raw = try String(contentsOf: store.url(for: .user), encoding: .utf8)
        #expect(raw == "Запись из Hermes")
    }

    @Test("Очистка оставляет пустой файл, а не удаляет его")
    func clear() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let added = try await store.add("Временная запись", to: .notes, ifUnchanged: nil)

        _ = try await store.clear(.notes, ifUnchanged: added.fingerprint)

        let reloaded = try await store.load(.notes)
        #expect(reloaded.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.url(for: .notes).path))
    }

    @Test("Переполнение не меняет файл")
    func limitRefusal() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let big = String(repeating: "я", count: 1370)
        let added = try await store.add(big, to: .user, ifUnchanged: nil)

        do {
            _ = try await store.add("ещё", to: .user, ifUnchanged: added.fingerprint)
            Issue.record("ожидали отказ по лимиту")
        } catch let error as MemoryFileError {
            guard case let .overLimit(_, limit, characters) = error else {
                Issue.record("другая ошибка: \(error)")
                return
            }
            #expect(limit == 1375)
            #expect(characters > limit)
        }

        let reloaded = try await store.load(.user)
        #expect(reloaded.entries == [big])
    }
}
