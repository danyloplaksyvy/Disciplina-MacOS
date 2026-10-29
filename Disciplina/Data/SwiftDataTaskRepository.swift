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
              sessions.allSatisfy({ SessionOrigin(rawValue: $0.originRaw) != nil }),
              sessions.allSatisfy({ $0.endReasonRaw == nil || SessionEndReason(rawValue: $0.endReasonRaw!) != nil })
        else { throw DataError.invalidSnapshot }
        for task in tasks { if let data = task.scheduledDayData { _ = try JSONDecoder().decode(LocalDay.self, from: data) } }
        let series = try context.fetch(FetchDescriptor<SeriesRecord>()).map { try $0.value() }
        return TaskSnapshot(tasks: tasks.map(\.item), sessions: sessions.map(\.item), series: series,
                            goals: try context.fetch(FetchDescriptor<GoalRecord>()).map { try $0.value() },
                            milestones: try context.fetch(FetchDescriptor<MilestoneRecord>()).map { try $0.value() })
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
        if let index = state.tasks.firstIndex(where: { $0.id == id }) { state.detachTask(at: index) }
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
            let series = try context.fetch(FetchDescriptor<SeriesRecord>())
            let seriesMap = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
            let seriesIDs = Set(snapshot.series.map(\.id))
            for record in series where !seriesIDs.contains(record.id) { context.delete(record) }
            for item in snapshot.series {
                if let record = seriesMap[item.id] {
                    if try record.value() != item { record.payload = try JSONEncoder().encode(item) }
                } else { context.insert(try SeriesRecord(item)) }
            }
            let goals = try context.fetch(FetchDescriptor<GoalRecord>())
            let goalsMap = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
            let goalsIDs = Set(snapshot.goals.map(\.id))
            for record in goals where !goalsIDs.contains(record.id) { context.delete(record) }
            for item in snapshot.goals {
                if let record = goalsMap[item.id] {
                    if try record.value() != item { record.payload = try JSONEncoder().encode(item) }
                } else { context.insert(try GoalRecord(item)) }
            }
            let milestones = try context.fetch(FetchDescriptor<MilestoneRecord>())
            let milestonesMap = Dictionary(uniqueKeysWithValues: milestones.map { ($0.id, $0) })
            let milestonesIDs = Set(snapshot.milestones.map(\.id))
            for record in milestones where !milestonesIDs.contains(record.id) { context.delete(record) }
            for item in snapshot.milestones {
                if let record = milestonesMap[item.id] {
                    if try record.value() != item { record.payload = try JSONEncoder().encode(item) }
                } else { context.insert(try MilestoneRecord(item)) }
            }
            try save(context)
        } catch { context.rollback(); throw error }
    }
}
