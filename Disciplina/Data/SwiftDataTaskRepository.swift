import Foundation
import SwiftData

@MainActor
final class SwiftDataTaskRepository: TaskRepository {
    private let context: ModelContext
    private let save: (ModelContext) throws -> Void
    init(context: ModelContext, save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context; self.save = save
    }
    func fetchAll() throws -> [TodoItem] { try snapshot().tasks }
    func snapshot() throws -> TaskSnapshot {
        let tasks = try context.fetch(FetchDescriptor<TaskRecord>())
        let sessions = try context.fetch(FetchDescriptor<SessionRecord>())
        guard tasks.allSatisfy({ TaskStatus(rawValue: $0.statusRaw) != nil }),
              sessions.allSatisfy({ $0.endReasonRaw == nil || SessionEndReason(rawValue: $0.endReasonRaw!) != nil })
        else { throw DataError.invalidSnapshot }
        return TaskSnapshot(tasks: tasks.map(\.item), sessions: sessions.map(\.item))
    }
    func insert(_ item: TodoItem) throws {
        var state = try snapshot()
        guard !state.tasks.contains(where: { $0.id == item.id }) else { throw DataError.invalidSnapshot }
        state.tasks.append(item); try commit(state)
    }
    func update(_ item: TodoItem) throws {
        var state = try snapshot()
        guard let index = state.tasks.firstIndex(where: { $0.id == item.id }) else { throw TaskError.notFound }
        state.tasks[index] = item; try commit(state)
    }
    func delete(id: UUID) throws {
        var state = try snapshot()
        guard state.tasks.contains(where: { $0.id == id }) else { throw TaskError.notFound }
        state.tasks.removeAll { $0.id == id }; state.sessions.removeAll { $0.taskID == id }
        try commit(state)
    }
    func commit(_ snapshot: TaskSnapshot) throws {
        try snapshot.validate()
        do {
            let tasks = try context.fetch(FetchDescriptor<TaskRecord>())
            let sessions = try context.fetch(FetchDescriptor<SessionRecord>())
            let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            let sessionMap = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
            let ids = Set(snapshot.tasks.map(\.id)); let sessionIDs = Set(snapshot.sessions.map(\.id))
            for record in tasks where !ids.contains(record.id) { context.delete(record) }
            for record in sessions where !sessionIDs.contains(record.id) { context.delete(record) }
            for item in snapshot.tasks {
                if let record = taskMap[item.id] { if record.item != item { record.apply(item) } }
                else { context.insert(TaskRecord(item)) }
            }
            for item in snapshot.sessions {
                if let record = sessionMap[item.id] { if record.item != item { record.apply(item) } }
                else { context.insert(SessionRecord(item)) }
            }
            try save(context)
        } catch { context.rollback(); throw error }
    }
}
