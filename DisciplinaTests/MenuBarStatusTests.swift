import Foundation
import Testing
@testable import Disciplina

@Suite @MainActor
struct MenuBarStatusTests {
    @Test func labelStates() {
        #expect(MenuBarStatus(activeCount: nil).text == "—")
        #expect(MenuBarStatus(activeCount: nil).accessibilityLabel == "Disciplina: Task count unavailable")
        #expect(MenuBarStatus(activeCount: 0).text == "All clear")
        #expect(MenuBarStatus(activeCount: 0).accessibilityLabel == "Disciplina: All clear")
        #expect(MenuBarStatus(activeCount: 1).text == "1 left")
        #expect(MenuBarStatus(activeCount: 1).accessibilityLabel == "Disciplina: 1 active task")
        #expect(MenuBarStatus(activeCount: 3).accessibilityLabel == "Disciplina: 3 active tasks")
    }

    @Test(arguments: [9, 10, 99, 100, 1000])
    func exactCounts(count: Int) {
        #expect(MenuBarStatus(activeCount: count).text == "\(count) left")
        let repository = MemoryRepository()
        let date = Date(timeIntervalSince1970: 0)
        repository.items = (1..<count).map {
            TodoItem(id: UUID(), title: "Task \($0)", createdAt: date, updatedAt: date, completedAt: nil)
        }
        let store = TaskStore(service: TaskService(repository: repository))
        #expect(store.menuBarStatus.text == "\(count - 1) left")
        #expect(store.create(title: "Cross the digit boundary"))
        #expect(store.menuBarStatus.text == "\(count) left")
    }

    @Test func mutationsUpdateCount() throws {
        let repository = MemoryRepository()
        let store = TaskStore(service: TaskService(repository: repository))
        #expect(store.menuBarStatus.text == "All clear")
        #expect(store.create(title: "One"))
        let id = try #require(store.items.first?.id)
        #expect(store.menuBarStatus.text == "1 left")
        #expect(store.rename(id: id, title: "Renamed"))
        #expect(store.menuBarStatus.text == "1 left")
        #expect(store.create(title: "Two"))
        #expect(store.menuBarStatus.text == "2 left")
        #expect(store.setCompleted(id: id, isCompleted: true))
        #expect(store.menuBarStatus.text == "1 left")
        #expect(store.setCompleted(id: id, isCompleted: false))
        #expect(store.menuBarStatus.text == "2 left")
        #expect(store.delete(id: id))
        #expect(store.menuBarStatus.text == "1 left")
        #expect(store.delete(id: try #require(store.items.first?.id)))
        #expect(store.menuBarStatus.text == "All clear")
    }

    @Test func failuresAndRecovery() {
        let repository = MemoryRepository()
        let store = TaskStore(service: TaskService(repository: repository))
        #expect(store.create(title: "One"))
        repository.failWrite = true
        #expect(!store.create(title: "Rejected"))
        #expect(store.menuBarStatus.text == "1 left")
        repository.failWrite = false
        repository.failFetchAfterWrite = true
        #expect(store.create(title: "Saved"))
        #expect(store.menuBarStatus.activeCount == nil)
        repository.failFetch = false
        store.reload()
        #expect(store.menuBarStatus.text == "2 left")
    }

    @Test func initialLoadAndReload() {
        let repository = MemoryRepository()
        let date = Date(timeIntervalSince1970: 0)
        repository.items = [
            TodoItem(id: UUID(), title: "Old active task", createdAt: date, updatedAt: date, completedAt: nil),
            TodoItem(id: UUID(), title: "Completed task", createdAt: date, updatedAt: date, completedAt: date)
        ]
        repository.failFetch = true
        let store = TaskStore(service: TaskService(repository: repository))
        #expect(store.menuBarStatus.activeCount == nil)
        repository.failFetch = false
        store.reload()
        #expect(store.menuBarStatus.text == "1 left")
    }
}
