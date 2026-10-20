import Foundation
import Observation

@MainActor @Observable
final class TaskStore {
    let service: TaskService
    let timer: TimerCoordinator
    private(set) var sessions: [WorkSession] = []
    private(set) var deleted: [TodoItem] = []
    private(set) var deletedIDs: [UUID] = []
    var notice: String?
    var unavailable: Bool { needsRefresh || timer.failure != nil }
    var featured: TodoItem? {
        if let id = timer.running?.taskID { return items.first { $0.id == id } }
        return inProgress.first
    }
    var inProgress: [TodoItem] { items.filter { $0.status == .inProgress }.sorted(by: recentlyUpdated) }
    var todo: [TodoItem] { active.filter { $0.status == .todo } }
    var relevant: [TodoItem] {
        Array((inProgress + todo.sorted(by: recentlyUpdated)).filter { $0.id != featured?.id }.prefix(5))
    }
    private func recentlyUpdated(_ a: TodoItem, _ b: TodoItem) -> Bool {
        a.updatedAt == b.updatedAt ? a.id.uuidString < b.id.uuidString : a.updatedAt > b.updatedAt
    }
    func total(_ id: UUID) -> Int64 {
        let saved = sessions.filter { $0.taskID == id }.reduce(Int64(0)) { $0 + $1.accumulatedMilliseconds }
        guard let running = timer.running, running.taskID == id else { return saved }
        return saved + max(0, timer.elapsedMilliseconds - running.accumulatedMilliseconds)
    }
    private(set) var items: [TodoItem] = []
    private(set) var errorMessage: String?
    private(set) var needsRefresh = false

    var menuBarStatus: MenuBarStatus {
        MenuBarStatus(activeCount: unavailable ? nil : items.reduce(0) { $0 + ($1.isCompleted ? 0 : 1) })
    }

    var active: [TodoItem] {
        items.filter { !$0.isCompleted }.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
        }
    }
    var completed: [TodoItem] {
        items.filter(\.isCompleted).sorted {
            $0.completedAt == $1.completedAt ? $0.id.uuidString < $1.id.uuidString : $0.completedAt! > $1.completedAt!
        }
    }

    init(service: TaskService, timer: TimerCoordinator? = nil) {
        self.service = service
        self.timer = timer ?? TimerCoordinator(repository: service.repository)
        self.timer.onCommit = { [weak self] in self?.refresh() }
        do { try self.timer.recover() } catch { errorMessage = error.localizedDescription; needsRefresh = true; return }
        refresh()
    }

    private func refresh() {
        do {
            let snapshot = try service.repository.snapshot()
            try snapshot.validate()
            items = snapshot.tasks.filter { $0.deletedAt == nil }
            deleted = snapshot.tasks.filter { $0.deletedAt != nil }
            sessions = snapshot.sessions
            needsRefresh = false; errorMessage = nil
        } catch {
            needsRefresh = true
            errorMessage = "Could not load tasks. \(error.localizedDescription)"
        }
    }

    func reload() {
        do {
            if timer.failure != nil { try timer.recover() }
            refresh()
        } catch { errorMessage = error.localizedDescription; needsRefresh = true }
    }

    @discardableResult func create(title: String) -> Bool { mutate { try service.create(title: title) } }
    @discardableResult func rename(id: UUID, title: String) -> Bool { mutate { try service.rename(id: id, title: title) } }
    @discardableResult func setCompleted(id: UUID, isCompleted: Bool) -> Bool {
        mutate { try timer.setStatus(id: id, status: isCompleted ? .completed : .todo) }
    }
    @discardableResult func delete(id: UUID) -> Bool {
        let saved = mutate { try timer.delete(id: id) }
        if saved { deletedIDs.append(id); notice = "Task moved to Recently Deleted." }
        return saved
    }
    @discardableResult func start(_ id: UUID) -> Bool {
        let previous = timer.running.flatMap { running in items.first { $0.id == running.taskID } }
        let result = mutate { try timer.start(taskID: id) }
        if result, let previous, previous.id != id { notice = "Paused \(previous.title) · Started \(items.first { $0.id == id }?.title ?? "task")" }
        return result
    }
    @discardableResult func pause(_ reason: SessionEndReason = .paused) -> Bool { mutate { try timer.pause(reason: reason) } }
    @discardableResult func setStatus(_ id: UUID, _ status: TaskStatus) -> Bool { mutate { try timer.setStatus(id: id, status: status) } }
    @discardableResult func restore(_ id: UUID) -> Bool {
        if items.contains(where: { $0.id == id }) { return true }
        let result = mutate {
            var snapshot = try service.repository.snapshot()
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == id && $0.deletedAt != nil }) else { throw TaskError.notFound }
            snapshot.tasks[index].deletedAt = nil
            snapshot.tasks[index].updatedAt = Date()
            try service.repository.commit(snapshot)
        }
        if result { deletedIDs.removeAll { $0 == id }; notice = "Task restored." }
        return result
    }
    func undoDelete() { if let id = deletedIDs.last { _ = restore(id) } }
    @discardableResult func permanentlyDelete(_ id: UUID) -> Bool {
        guard deleted.contains(where: { $0.id == id }) else { return false }
        let result = mutate { try service.repository.delete(id: id) }
        if result { deletedIDs.removeAll { $0 == id } }
        return result
    }
    func dismissError() { if !needsRefresh { errorMessage = nil } }

    private func mutate(_ action: () throws -> Void) -> Bool {
        guard !unavailable else { return false }
        do { try action() } catch {
            errorMessage = "Could not save the change. \(error.localizedDescription)"
            return false
        }
        do {
            let snapshot = try service.repository.snapshot()
            try snapshot.validate()
            items = snapshot.tasks.filter { $0.deletedAt == nil }
            deleted = snapshot.tasks.filter { $0.deletedAt != nil }
            sessions = snapshot.sessions
            errorMessage = nil
        } catch {
            needsRefresh = true
            errorMessage = "Your change was saved, but the list could not refresh. Retry loading; do not submit it again. \(error.localizedDescription)"
        }
        // True means committed, even when a subsequent refresh failed.
        return true
    }
}
