import Foundation

struct TaskQuery: Equatable {
    enum Status: String, CaseIterable, Identifiable {
        case all = "All", incomplete = "Incomplete", inProgress = "In Progress", todo = "To Do", completed = "Completed"
        var id: Self { self }
    }
    enum GoalFilter: Hashable { case all, unassigned, goal(UUID) }
    var text = ""
    var status: Status = .all
    var goal: GoalFilter = .all
    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isActive: Bool { !trimmedText.isEmpty || status != .all || goal != .all }

    func matches(title: String, status taskStatus: TaskStatus, goalID: UUID?, locale: Locale = .current) -> Bool {
        matches(title: title, status: taskStatus, goalID: goalID, query: trimmedText, locale: locale)
    }
    private func matches(title: String, status taskStatus: TaskStatus, goalID: UUID?, query: String, locale: Locale) -> Bool {
        switch status {
        case .all: break
        case .incomplete: if taskStatus == .completed { return false }
        case .inProgress: if taskStatus != .inProgress { return false }
        case .todo: if taskStatus != .todo { return false }
        case .completed: if taskStatus != .completed { return false }
        }
        switch goal {
        case .all: break
        case .unassigned: if goalID != nil { return false }
        case .goal(let id): if goalID != id { return false }
        }
        return query.isEmpty || title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
    }
    func matches(_ task: TodoItem, locale: Locale = .current) -> Bool {
        task.deletedAt == nil && matches(title: task.title, status: task.status, goalID: task.goalID, locale: locale)
    }
    func project(_ groups: [TaskDayGroup], unavailable: Bool = false, locale: Locale = .current) -> TaskSearchResult {
        guard !unavailable else { return TaskSearchResult(groups: [], visibleIDs: [], totalCount: 0, unavailable: true) }
        let query = trimmedText
        var ids: Set<UUID> = [], total = 0
        let filtered = groups.compactMap { group -> TaskDayGroup? in
            var result = group
            func filter(_ items: [TodoItem]) -> [TodoItem] {
                items.filter { item in
                    guard item.deletedAt == nil else { return false }
                    total += 1
                    guard matches(title: item.title, status: item.status, goalID: item.goalID, query: query, locale: locale) else { return false }
                    ids.insert(item.id); return true
                }
            }
            result.inProgress = filter(group.inProgress)
            result.todo = filter(group.todo)
            result.completed = filter(group.completed)
            return result.inProgress.isEmpty && result.todo.isEmpty && result.completed.isEmpty ? nil : result
        }
        return TaskSearchResult(groups: filtered, visibleIDs: ids, totalCount: total, unavailable: false)
    }
}

struct TaskSearchResult: Equatable {
    var groups: [TaskDayGroup]
    var visibleIDs: Set<UUID>
    var totalCount: Int
    var unavailable: Bool
    var countLabel: String { unavailable ? "Task results unavailable" : "\(visibleIDs.count) of \(totalCount) tasks" }
}
