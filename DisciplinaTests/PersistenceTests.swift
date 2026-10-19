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
        #expect(TaskMigrationPlan.schemas.count == 1)
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
