import Foundation

@MainActor
final class TaskService {
    let repository: any TaskRepository
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
        var state = try repository.snapshot()
        guard let index = state.tasks.firstIndex(where: { $0.id == id }) else { throw TaskError.notFound }
        guard state.tasks[index].title != title else { return }
        state.tasks[index].title = title; state.tasks[index].updatedAt = now()
        if let seriesID = state.tasks[index].seriesID, let s = state.series.firstIndex(where: { $0.id == seriesID }) {
            state.series[s].title = title; state.series[s].revision = makeID()
        }
        try repository.commit(state)
    }

    func setCompleted(id: UUID, isCompleted: Bool) throws {
        var item = try find(id)
        guard item.isCompleted != isCompleted else { return }
        let date = now()
        item.status = isCompleted ? .completed : .todo
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
