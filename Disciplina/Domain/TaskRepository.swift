import Foundation

@MainActor
protocol TaskRepository {
    func fetchAll() throws -> [TodoItem]
    func insert(_ item: TodoItem) throws
    func update(_ item: TodoItem) throws
    func delete(id: UUID) throws
}
