import Foundation

struct DailyPlan: Equatable {
    struct Earlier: Equatable, Identifiable {
        let day: LocalDay
        var tasks: [TodoItem]
        var id: LocalDay { day }
    }
    var today: [TodoItem] = []
    var earlier: [Earlier] = []
    var completed: [TodoItem] = []
    static func ordered(_ a: TodoItem, _ b: TodoItem) -> Bool {
        a.planOrder == b.planOrder ? a.id.uuidString < b.id.uuidString : (a.planOrder ?? 0) < (b.planOrder ?? 0)
    }
    init(tasks: [TodoItem] = [], day: LocalDay? = nil) {
        guard let day else { return }
        let planned = tasks.filter { $0.deletedAt == nil && $0.plannedDay != nil }.sorted(by: Self.ordered)
        today = planned.filter { $0.plannedDay == day && !$0.isCompleted }
        completed = planned.filter { $0.plannedDay == day && $0.isCompleted }
        let past = Dictionary(grouping: planned.filter { $0.plannedDay! < day && !$0.isCompleted }, by: { $0.plannedDay! })
        earlier = past.keys.sorted(by: >).map { Earlier(day: $0, tasks: past[$0]!) }
    }
}

extension TaskSnapshot {
    func validatePlanning() throws {
        for task in tasks {
            guard (task.plannedDay == nil) == (task.planOrder == nil) else { throw DataError.invalidSnapshot }
            if let day = task.plannedDay {
                _ = try day.date()
                guard let order = task.planOrder, order >= 0, order < Int64.max else { throw DataError.invalidSnapshot }
            }
        }
    }
    /// Includes hidden/deleted and completed records so their positions survive restoration.
    mutating func normalizePlan(_ day: LocalDay) {
        let indices = tasks.indices.filter { tasks[$0].plannedDay == day }.sorted { DailyPlan.ordered(tasks[$0], tasks[$1]) }
        for (order, index) in indices.enumerated() { tasks[index].planOrder = Int64(order) }
    }
    mutating func appendToPlan(id: UUID, day: LocalDay) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].plannedDay != day else { return }
        let old = tasks[index].plannedDay
        tasks[index].plannedDay = nil; tasks[index].planOrder = nil
        if let old { normalizePlan(old) }
        normalizePlan(day)
        let order = Int64(tasks.filter { $0.plannedDay == day }.count)
        tasks[index].plannedDay = day; tasks[index].planOrder = order
    }
}

@MainActor
final class PlanningService {
    let repository: any TaskRepository
    init(repository: any TaskRepository) { self.repository = repository }
    func assign(_ id: UUID, day: LocalDay?) throws {
        var state = try repository.snapshot()
        guard let index = state.tasks.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { throw TaskError.notFound }
        guard state.tasks[index].plannedDay != day else { return }
        if let day {
            guard !state.tasks[index].isCompleted else { throw DataError.invalidSnapshot }
            _ = try day.date(); state.appendToPlan(id: id, day: day)
        } else if let old = state.tasks[index].plannedDay {
            state.tasks[index].plannedDay = nil; state.tasks[index].planOrder = nil; state.normalizePlan(old)
        }
        try repository.commit(state)
    }
    func reorder(day: LocalDay, ids: [UUID]) throws {
        var state = try repository.snapshot()
        let current = DailyPlan(tasks: state.tasks, day: day).today.map(\.id)
        guard ids.count == current.count, Set(ids) == Set(current) else { throw DataError.invalidSnapshot }
        guard ids != current else { return }
        state.normalizePlan(day)
        let selected = Set(ids)
        let slots = state.tasks.filter { selected.contains($0.id) }.compactMap(\.planOrder).sorted()
        let byID = Dictionary(uniqueKeysWithValues: state.tasks.indices.map { (state.tasks[$0].id, $0) })
        for (position, id) in ids.enumerated() { state.tasks[byID[id]!].planOrder = slots[position] }
        try repository.commit(state)
    }
}

/// A read-only scope projection; planning remains owned by the committed snapshot.
struct PlannedTaskResults: Equatable {
    var plan = DailyPlan()
    var totalCount = 0
    var unavailable = false
    var matchedIDs: Set<UUID> {
        Set(plan.today.map(\.id) + plan.earlier.flatMap { $0.tasks.map(\.id) } + plan.completed.map(\.id))
    }
    var countLabel: String { unavailable ? "Task results unavailable" : "\(matchedIDs.count) of \(totalCount) tasks" }
    func visibleIDs(earlierExpanded: Bool, completedExpanded: Bool, searching: Bool) -> Set<UUID> {
        Set(plan.today.map(\.id)
            + (earlierExpanded || searching ? plan.earlier.flatMap { $0.tasks.map(\.id) } : [])
            + (completedExpanded || searching ? plan.completed.map(\.id) : []))
    }
    init(plan source: DailyPlan = DailyPlan(), query: TaskQuery = TaskQuery(), unavailable: Bool = false) {
        self.unavailable = unavailable
        guard !unavailable else { return }
        totalCount = source.today.count + source.earlier.reduce(0) { $0 + $1.tasks.count } + source.completed.count
        plan.today = source.today.filter { query.matches($0) }
        plan.completed = source.completed.filter { query.matches($0) }
        plan.earlier = source.earlier.compactMap { group in
            let tasks = group.tasks.filter { query.matches($0) }
            return tasks.isEmpty ? nil : DailyPlan.Earlier(day: group.day, tasks: tasks)
        }
    }
}
