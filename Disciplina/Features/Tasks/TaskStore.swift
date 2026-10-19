import Foundation
import Observation

@MainActor @Observable
final class TaskStore {
    private let service: TaskService
    private(set) var items: [TodoItem] = []
    private(set) var errorMessage: String?
    private(set) var needsRefresh = false

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

    init(service: TaskService) { self.service = service; reload() }

    func reload() {
        do {
            items = try service.fetchAll()
            needsRefresh = false
            errorMessage = nil
        } catch {
            needsRefresh = true
            errorMessage = "Could not load tasks. \(error.localizedDescription)"
        }
    }

    @discardableResult func create(title: String) -> Bool { mutate { try service.create(title: title) } }
    @discardableResult func rename(id: UUID, title: String) -> Bool { mutate { try service.rename(id: id, title: title) } }
    @discardableResult func setCompleted(id: UUID, isCompleted: Bool) -> Bool {
        mutate { try service.setCompleted(id: id, isCompleted: isCompleted) }
    }
    @discardableResult func delete(id: UUID) -> Bool { mutate { try service.delete(id: id) } }
    func dismissError() { if !needsRefresh { errorMessage = nil } }

    private func mutate(_ action: () throws -> Void) -> Bool {
        guard !needsRefresh else { return false }
        do { try action() } catch {
            errorMessage = "Could not save the change. \(error.localizedDescription)"
            return false
        }
        do {
            items = try service.fetchAll()
            errorMessage = nil
        } catch {
            needsRefresh = true
            errorMessage = "Your change was saved, but the list could not refresh. Retry loading; do not submit it again. \(error.localizedDescription)"
        }
        // True means committed, even when a subsequent refresh failed.
        return true
    }
}
