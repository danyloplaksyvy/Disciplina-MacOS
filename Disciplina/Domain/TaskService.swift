import Foundation

@MainActor
final class TaskService {
    private let repository: any TaskRepository
    private let now: () -> Date
    private let makeID: () -> UUID

    init(repository: any TaskRepository, now: @escaping () -> Date = Date.init,
         makeID: @escaping () -> UUID = UUID.init) {
        self.repository = repository
        self.now = now
        self.makeID = makeID
    }

    static func validatedTitle(_ raw: String) throws -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TaskError.emptyTitle }
        guard title.rangeOfCharacter(from: .newlines) == nil else { throw TaskError.multilineTitle }
        guard title.count <= 200 else { throw TaskError.titleTooLong }
        return title
    }

    func fetchAll() throws -> [TodoItem] { try repository.fetchAll() }

    func create(title: String) throws {
        let title = try Self.validatedTitle(title)
        let date = now()
        try repository.insert(TodoItem(id: makeID(), title: title, createdAt: date,
                                       updatedAt: date, completedAt: nil))
    }

    func rename(id: UUID, title: String) throws {
        let title = try Self.validatedTitle(title)
        var item = try find(id)
        guard item.title != title else { return }
        item.title = title
        item.updatedAt = now()
        try repository.update(item)
    }

    func setCompleted(id: UUID, isCompleted: Bool) throws {
        var item = try find(id)
        guard item.isCompleted != isCompleted else { return }
        let date = now()
        item.completedAt = isCompleted ? date : nil
        item.updatedAt = date
        try repository.update(item)
    }

    func delete(id: UUID) throws { try repository.delete(id: id) }

    private func find(_ id: UUID) throws -> TodoItem {
        guard let item = try repository.fetchAll().first(where: { $0.id == id }) else {
            throw TaskError.notFound
        }
        return item
    }
}
