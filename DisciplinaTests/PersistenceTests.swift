import Foundation
import SwiftData
import Testing
@testable import Disciplina

@Suite @MainActor
struct PersistenceTests {
    @Test func crudMapping() throws {
        let persistence = try PersistenceController(inMemory: true)
        let repo = SwiftDataTaskRepository(context: persistence.container.mainContext)
        let service = TaskService(repository: repo)
        try service.create(title: "Persistent")
        let item = try #require(repo.fetchAll().first)
        try service.rename(id: item.id, title: "Renamed")
        try service.setCompleted(id: item.id, isCompleted: true)
        let saved = try #require(repo.fetchAll().first)
        #expect(saved.title == "Renamed")
        #expect(saved.completedAt != nil)
        #expect(saved.createdAt == item.createdAt)
        try service.delete(id: item.id)
        #expect(try repo.fetchAll().isEmpty)
        #expect(throws: TaskError.notFound) { try repo.delete(id: item.id) }
    }
    @Test func rollbackFailedInsertUpdateAndDelete() throws {
        let persistence = try PersistenceController(inMemory: true)
        var fail = false
        let repo = SwiftDataTaskRepository(context: persistence.container.mainContext) { context in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        }
        let service = TaskService(repository: repo)
        try service.create(title: "Original")
        let original = try #require(repo.fetchAll().first)
        fail = true
        #expect(throws: (any Error).self) { try service.create(title: "Fail") }
        #expect(throws: (any Error).self) { try service.rename(id: original.id, title: "Fail") }
        #expect(throws: (any Error).self) { try service.delete(id: original.id) }
        #expect(try repo.fetchAll() == [original])
    }
    @Test func diskReloadAndSchemaCompatibility() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let id = UUID()
        func write() throws {
            let persistence = try PersistenceController(url: url)
            let repo = SwiftDataTaskRepository(context: persistence.container.mainContext)
            try TaskService(repository: repo, makeID: { id }).create(title: "Across launches")
        }
        try write()
        let persistence = try PersistenceController(url: url)
        let repo = SwiftDataTaskRepository(context: persistence.container.mainContext)
        #expect(try repo.fetchAll().first?.id == id)
        try repo.delete(id: id)
        let reopened = try PersistenceController(url: url)
        #expect(try SwiftDataTaskRepository(context: reopened.container.mainContext).fetchAll().isEmpty)
        #expect(TaskMigrationPlan.schemas.count == 4)
    }
    @Test(arguments: [0, 2, 1000]) func migratesRealV1StoreAndKeepsOriginal(count: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("default.store")
        let date = Date(timeIntervalSince1970: 123)
        let items = (0..<count).map { index in
            TodoItem(id: UUID(), title: "Legacy \(index)", createdAt: date, updatedAt: date,
                     completedAt: index % 2 == 0 ? nil : date)
        }
        let schema = Schema(versionedSchema: TaskSchemaV1.self)
        let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: original, cloudKitDatabase: .none)])
        old.mainContext.autosaveEnabled = false
        for item in items { old.mainContext.insert(TaskSchemaV1.TaskRecord(item)) }
        try old.mainContext.save()
        // Keep the original container open to exercise committed WAL data.
        let location = try StoreLocation(root: root)
        let migrated = try location.open()
        let state = try SwiftDataTaskRepository(context: migrated.container.mainContext).snapshot()
        #expect(Set(state.tasks.map(\.id)) == Set(items.map(\.id)))
        if count > 1 { #expect(state.tasks.first { $0.completedAt != nil }?.status == .completed) }
        #expect(state.sessions.isEmpty)
        #expect(try old.mainContext.fetch(FetchDescriptor<TaskSchemaV1.TaskRecord>()).count == count)
        #expect(try location.open().url == migrated.url)
    }

    @Test func migratesManifestedV2WithoutChangingOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try StoreLocation(root: root)
        let original = try location.newURL()
        let date = Date(timeIntervalSince1970: 123)
        let item = TodoItem(id: UUID(), title: "V2 task", createdAt: date, updatedAt: date, completedAt: nil, status: .inProgress)
        let session = WorkSession(id: UUID(), taskID: item.id, startedAt: date, endedAt: date + 10,
            accumulatedMilliseconds: 9345, lastCheckpointAt: date + 10, endReason: .paused)
        let schema = Schema(versionedSchema: TaskSchemaV2.self)
        let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: original, cloudKitDatabase: .none)])
        old.mainContext.autosaveEnabled = false
        old.mainContext.insert(TaskSchemaV2.TaskRecord(item))
        old.mainContext.insert(TaskSchemaV2.SessionRecord(session))
        try old.mainContext.save()
        let manifest = root.appendingPathComponent("Disciplina-store.json")
        let manifestData = try JSONSerialization.data(withJSONObject: ["directory": original.deletingLastPathComponent().lastPathComponent])
        try manifestData.write(to: manifest)
        #expect(throws: (any Error).self) {
            _ = try location.open { throw CocoaError(.fileWriteOutOfSpace) }
        }
        #expect(try Data(contentsOf: manifest) == manifestData)
        let migrated = try location.open()
        #expect(migrated.url != original)
        let state = try SwiftDataTaskRepository(context: migrated.container.mainContext).snapshot()
        #expect(state == TaskSnapshot(tasks: [item], sessions: [session]))
        #expect(try old.mainContext.fetch(FetchDescriptor<TaskSchemaV2.SessionRecord>()).first?.item == session)
        #expect(try location.open().url == migrated.url)
        let repo = SwiftDataTaskRepository(context: migrated.container.mainContext)
        let timer = TimerCoordinator(repository: repo)
        try timer.editSession(taskID: item.id, sessionID: session.id, milliseconds: 12345)
        try timer.addSession(taskID: item.id, date: date, milliseconds: 1000)
        let reopened = try location.open()
        #expect(try SwiftDataTaskRepository(context: reopened.container.mainContext).snapshot() == repo.snapshot())
    }

    @Test func migratesManifestedV3WithoutChangingOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try StoreLocation(root: root)
        let original = try location.newURL()
        let date = Date(timeIntervalSince1970: 123)
        let item = TodoItem(id: UUID(), title: "V3 task", createdAt: date, updatedAt: date, completedAt: nil, status: .inProgress)
        let session = WorkSession(id: UUID(), taskID: item.id, startedAt: date, endedAt: date + 10,
            accumulatedMilliseconds: 9345, lastCheckpointAt: date + 10, endReason: .paused, durationEditedAt: date + 20)
        let schema = Schema(versionedSchema: TaskSchemaV3.self)
        let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: original, cloudKitDatabase: .none)])
        old.mainContext.autosaveEnabled = false
        old.mainContext.insert(TaskSchemaV3.TaskRecord(item))
        old.mainContext.insert(TaskSchemaV3.SessionRecord(session))
        try old.mainContext.save()
        let manifest = root.appendingPathComponent("Disciplina-store.json")
        let manifestData = try JSONSerialization.data(withJSONObject: ["directory": original.deletingLastPathComponent().lastPathComponent, "schemaVersion": 3])
        try manifestData.write(to: manifest)
        #expect(throws: (any Error).self) {
            _ = try location.open { throw CocoaError(.fileWriteOutOfSpace) }
        }
        #expect(try Data(contentsOf: manifest) == manifestData)
        let migrated = try location.open()
        #expect(migrated.url != original)
        let state = try SwiftDataTaskRepository(context: migrated.container.mainContext).snapshot()
        #expect(state == TaskSnapshot(tasks: [item], sessions: [session]))
        #expect(try old.mainContext.fetch(FetchDescriptor<TaskSchemaV3.SessionRecord>()).first?.item == session)
        #expect(try location.open().url == migrated.url)
        let repo = SwiftDataTaskRepository(context: migrated.container.mainContext)
        let timer = TimerCoordinator(repository: repo)
        try timer.editSession(taskID: item.id, sessionID: session.id, milliseconds: 12345)
        try timer.addSession(taskID: item.id, date: date, milliseconds: 1000)
        let reopened = try location.open()
        #expect(try SwiftDataTaskRepository(context: reopened.container.mainContext).snapshot() == repo.snapshot())
    }

    @Test func stagedRestoreFailurePreservesCurrentStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try StoreLocation(root: root)
        let current = try location.open()
        let repo = SwiftDataTaskRepository(context: current.container.mainContext)
        try TaskService(repository: repo).create(title: "Keep me")
        let original = try repo.snapshot()
        #expect(throws: (any Error).self) {
            _ = try location.restore(TaskSnapshot(), currentURL: current.url) { throw CocoaError(.fileWriteOutOfSpace) }
        }
        let reopened = try location.open()
        #expect(reopened.url == current.url)
        #expect(try SwiftDataTaskRepository(context: reopened.container.mainContext).snapshot() == original)
        let replacement = try location.restore(TaskSnapshot(), currentURL: current.url)
        #expect(replacement.url != current.url)
        #expect(try location.open().url == replacement.url)
        #expect(try repo.snapshot() == original)
    }

    @Test func corruptMigrationNeverPublishesEmptyStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("default.store")
        let bytes = Data("Not a database".utf8)
        try bytes.write(to: original)
        let location = try StoreLocation(root: root)
        #expect(throws: (any Error).self) { _ = try location.open() }
        #expect(try Data(contentsOf: original) == bytes)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Disciplina-store.json").path))
    }

    @Test func recurrenceRoundTripAndRollback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try StoreLocation(root: root)
        let persistence = try location.open()
        var fail = false
        let repo = SwiftDataTaskRepository(context: persistence.container.mainContext) { context in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        }
        try TaskService(repository: repo).create(title: "Repeat")
        let id = try #require(repo.snapshot().tasks.first?.id)
        let timer = TimerCoordinator(repository: repo)
        try timer.setRepeat(taskID: id, weekdays: [2, 4, 6])
        let original = try repo.snapshot()
        fail = true
        #expect(throws: (any Error).self) { try timer.setStatus(id: id, status: .completed) }
        #expect(try repo.snapshot() == original)
        fail = false
        try timer.setStatus(id: id, status: .completed)
        let pending = try repo.snapshot()
        let reopened = try location.open()
        #expect(try SwiftDataTaskRepository(context: reopened.container.mainContext).snapshot() == pending)
        let restored = try location.restore(pending, currentURL: persistence.url)
        #expect(try SwiftDataTaskRepository(context: restored.container.mainContext).snapshot() == pending)
    }

    @Test func thousandTasks() throws {
        let repo = MemoryRepository()
        let date = Date()
        repo.items = (0..<1000).map {
            TodoItem(id: UUID(), title: "Task \($0)", createdAt: date.addingTimeInterval(Double($0)),
                     updatedAt: date, completedAt: $0 % 2 == 0 ? date : nil)
        }
        let store = TaskStore(service: TaskService(repository: repo))
        #expect(store.active.count == 500)
        #expect(store.completed.count == 500)
        #expect(store.active.first?.title == "Task 999")
    }
}
