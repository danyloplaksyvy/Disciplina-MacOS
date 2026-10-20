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
        #expect(TaskMigrationPlan.schemas.count == 2)
    }
    @Test func migratesRealV1StoreAndKeepsOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("default.store")
        let date = Date(timeIntervalSince1970: 123)
        let items = [TodoItem(id: UUID(), title: "Legacy active", createdAt: date, updatedAt: date, completedAt: nil),
                     TodoItem(id: UUID(), title: "Legacy completed", createdAt: date, updatedAt: date, completedAt: date)]
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
        #expect(state.tasks.first { $0.completedAt != nil }?.status == .completed)
        #expect(state.sessions.isEmpty)
        #expect(try old.mainContext.fetch(FetchDescriptor<TaskSchemaV1.TaskRecord>()).count == 2)
        #expect(try location.open().url == migrated.url)
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
