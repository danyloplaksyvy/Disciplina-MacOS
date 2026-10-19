import Foundation
import Testing
@testable import Disciplina

@MainActor
final class MemoryRepository: TaskRepository {
    var items: [TodoItem] = []
    var failFetch = false
    var failWrite = false
    var failFetchAfterWrite = false
    var writes = 0
    func fetchAll() throws -> [TodoItem] {
        if failFetch { throw CocoaError(.fileReadUnknown) }
        return items
    }
    func insert(_ item: TodoItem) throws { try writing(); items.append(item) }
    func update(_ item: TodoItem) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { throw TaskError.notFound }
        try writing(); items[index] = item
    }
    func delete(id: UUID) throws {
        guard items.contains(where: { $0.id == id }) else { throw TaskError.notFound }
        try writing(); items.removeAll { $0.id == id }
    }
    private func writing() throws {
        if failWrite { throw CocoaError(.fileWriteOutOfSpace) }
        writes += 1
        if failFetchAfterWrite { failFetch = true }
    }
}

@Suite @MainActor
struct DomainTests {
    @Test(arguments: ["", "   ", "\n\t"])
    func rejectsBlank(title: String) {
        #expect(throws: TaskError.emptyTitle) { try TaskService.validatedTitle(title) }
    }
    @Test func titleRules() throws {
        #expect(try TaskService.validatedTitle("  Buy milk \n") == "Buy milk")
        #expect(throws: TaskError.multilineTitle) { try TaskService.validatedTitle("One\nTwo") }
        #expect(throws: TaskError.multilineTitle) { try TaskService.validatedTitle("One\u{2028}Two") }
        #expect(try TaskService.validatedTitle(String(repeating: "👨‍👩‍👧‍👦", count: 200)).count == 200)
        #expect(throws: TaskError.titleTooLong) { try TaskService.validatedTitle(String(repeating: "a", count: 201)) }
    }
    @Test func lifecycleAndTimestamps() throws {
        let repo = MemoryRepository()
        var date = Date(timeIntervalSince1970: 1)
        let id = UUID()
        let service = TaskService(repository: repo, now: { date }, makeID: { id })
        try service.create(title: "  First  ")
        #expect(repo.items[0].title == "First")
        #expect(repo.items[0].createdAt == date)
        date = Date(timeIntervalSince1970: 2)
        try service.setCompleted(id: id, isCompleted: true)
        #expect(repo.items[0].completedAt == date)
        #expect(repo.items[0].updatedAt == date)
        let writes = repo.writes
        try service.setCompleted(id: id, isCompleted: true)
        #expect(repo.writes == writes)
        date = Date(timeIntervalSince1970: 3)
        try service.rename(id: id, title: "Changed")
        #expect(repo.items[0].updatedAt == date)
        #expect(repo.items[0].createdAt == Date(timeIntervalSince1970: 1))
        try service.setCompleted(id: id, isCompleted: false)
        #expect(repo.items[0].completedAt == nil)
        try service.delete(id: id)
        #expect(repo.items.isEmpty)
        #expect(throws: TaskError.notFound) { try service.rename(id: id, title: "Missing") }
    }
    @Test func duplicatesAllowed() throws {
        let repo = MemoryRepository()
        let service = TaskService(repository: repo)
        try service.create(title: "Same"); try service.create(title: "Same")
        #expect(repo.items.count == 2)
        #expect(repo.items[0].id != repo.items[1].id)
    }
}

@Suite @MainActor
struct StoreTests {
    @Test func sortsAndSharesUpdates() throws {
        let repo = MemoryRepository()
        var date = Date(timeIntervalSince1970: 1)
        let service = TaskService(repository: repo, now: { date })
        let store = TaskStore(service: service)
        #expect(store.create(title: "First"))
        date = Date(timeIntervalSince1970: 2)
        #expect(store.create(title: "Second"))
        #expect(store.active.map(\.title) == ["Second", "First"])
        let first = store.active[1]
        let second = store.active[0]
        #expect(store.setCompleted(id: second.id, isCompleted: true))
        date = Date(timeIntervalSince1970: 3)
        #expect(store.setCompleted(id: first.id, isCompleted: true))
        #expect(store.completed.map(\.title) == ["First", "Second"])
        #expect(store.active.isEmpty)
    }
    @Test func stableTies() {
        let repo = MemoryRepository()
        let date = Date()
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        repo.items = [b, a].map { TodoItem(id: $0, title: "Tie", createdAt: date, updatedAt: date, completedAt: nil) }
        let store = TaskStore(service: TaskService(repository: repo))
        #expect(store.active.map(\.id) == [a, b])
    }
    @Test func failedSavePreservesPublishedState() {
        let repo = MemoryRepository()
        let store = TaskStore(service: TaskService(repository: repo))
        repo.failWrite = true
        #expect(!store.create(title: "Keep this draft"))
        #expect(store.items.isEmpty)
        #expect(store.errorMessage != nil)
    }
    @Test func savedButRefreshFailedDoesNotDuplicate() {
        let repo = MemoryRepository()
        let store = TaskStore(service: TaskService(repository: repo))
        repo.failFetchAfterWrite = true
        #expect(store.create(title: "Saved"))
        #expect(store.needsRefresh)
        #expect(store.errorMessage?.contains("was saved") == true)
        #expect(!store.create(title: "Saved"))
        #expect(repo.items.count == 1)
        repo.failFetch = false
        store.reload()
        #expect(!store.needsRefresh)
        #expect(store.items.count == 1)
    }
    @Test func failedInitialFetchCanRetry() {
        let repo = MemoryRepository(); repo.failFetch = true
        let store = TaskStore(service: TaskService(repository: repo))
        #expect(store.needsRefresh)
        repo.failFetch = false; store.reload()
        #expect(store.errorMessage == nil)
    }
}

