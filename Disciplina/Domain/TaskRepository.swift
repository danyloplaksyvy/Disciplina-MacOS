import Foundation

@MainActor
protocol TaskRepository {
    func fetchAll() throws -> [TodoItem]
    func insert(_ item: TodoItem) throws
    func update(_ item: TodoItem) throws
    func delete(id: UUID) throws
    func snapshot() throws -> TaskSnapshot
    /// One transaction across tasks and sessions; rollback every staged change on failure.
    func commit(_ snapshot: TaskSnapshot) throws
}
