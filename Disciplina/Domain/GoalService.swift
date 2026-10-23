import Foundation

@MainActor
final class GoalService {
    private let repository: any TaskRepository
    private let now: () -> Date
    private let makeID: () -> UUID
    init(repository: any TaskRepository, now: @escaping () -> Date = Date.init, makeID: @escaping () -> UUID = UUID.init) {
        self.repository = repository; self.now = now; self.makeID = makeID
    }
    static func title(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 120, value.rangeOfCharacter(from: .newlines) == nil else { throw GoalError.invalidTitle }
        return value
    }
    static func criteria(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 500 else { throw GoalError.invalidCriteria }
        return value
    }
    static func milestoneTitle(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 200, value.rangeOfCharacter(from: .newlines) == nil else { throw GoalError.invalidMilestone }
        return value
    }
    @discardableResult func save(id: UUID?, title: String, criteria: String, targetDay: LocalDay?) throws -> UUID {
        let title = try Self.title(title), criteria = try Self.criteria(criteria)
        if let targetDay { _ = try targetDay.date() }
        var state = try repository.snapshot()
        let date = now()
        if let id {
            guard let i = state.goals.firstIndex(where: { $0.id == id }) else { throw GoalError.missing }
            guard state.goals[i].title != title || state.goals[i].successCriteria != criteria || state.goals[i].targetDay != targetDay else { return id }
            state.goals[i].title = title; state.goals[i].successCriteria = criteria
            state.goals[i].targetDay = targetDay; state.goals[i].updatedAt = date
            try repository.commit(state); return id
        }
        let id = makeID()
        state.goals.append(Goal(id: id, title: title, successCriteria: criteria, targetDay: targetDay, createdAt: date, updatedAt: date))
        try repository.commit(state); return id
    }
    enum Lifecycle { case achieve, reopen, archive, restore }
    func transition(_ id: UUID, _ action: Lifecycle) throws {
        try change(id) { state, index, date in
            switch action {
            case .achieve:
                guard state.goals[index].status == .active else { return }
                state.goals[index].status = .achieved; state.goals[index].achievedAt = date
            case .reopen:
                guard state.goals[index].status == .achieved else { return }
                state.goals[index].status = .active; state.goals[index].achievedAt = nil
            case .archive:
                guard state.goals[index].status != .archived else { return }
                state.goals[index].statusBeforeArchive = state.goals[index].status
                state.goals[index].status = .archived; state.goals[index].archivedAt = date
            case .restore:
                guard state.goals[index].status == .archived, let prior = state.goals[index].statusBeforeArchive else { return }
                state.goals[index].status = prior; state.goals[index].statusBeforeArchive = nil; state.goals[index].archivedAt = nil
            }
        }
    }
    private func change(_ id: UUID, action: (inout TaskSnapshot, Int, Date) throws -> Void) throws {
        var state = try repository.snapshot()
        guard let index = state.goals.firstIndex(where: { $0.id == id }) else { throw GoalError.missing }
        let original = state, date = now()
        try action(&state, index, date)
        guard state != original else { return }
        state.goals[index].updatedAt = date
        try repository.commit(state)
    }
    func saveMilestone(goalID: UUID, id: UUID?, title: String) throws {
        let title = try Self.milestoneTitle(title)
        try change(goalID) { state, _, date in
            if let id {
                guard let i = state.milestones.firstIndex(where: { $0.id == id && $0.goalID == goalID }) else { throw GoalError.missing }
                guard state.milestones[i].title != title else { return }
                state.milestones[i].title = title; state.milestones[i].updatedAt = date
            } else {
                state.milestones.append(Milestone(id: makeID(), goalID: goalID, title: title,
                    sortOrder: state.milestones.filter { $0.goalID == goalID }.count, createdAt: date, updatedAt: date))
            }
        }
    }
    func completeMilestone(_ id: UUID, completed: Bool) throws {
        let existing = try milestone(id)
        try change(existing.goalID) { state, _, date in
            guard let i = state.milestones.firstIndex(where: { $0.id == id }) else { throw GoalError.missing }
            guard state.milestones[i].isCompleted != completed else { return }
            state.milestones[i].completedAt = completed ? date : nil; state.milestones[i].updatedAt = date
        }
    }
    func reorder(goalID: UUID, ids: [UUID]) throws {
        try change(goalID) { state, _, date in
            let existing = state.milestones.filter { $0.goalID == goalID }
            guard Set(ids).count == ids.count, Set(ids) == Set(existing.map(\.id)) else { throw DataError.invalidSnapshot }
            let positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
            for i in state.milestones.indices where state.milestones[i].goalID == goalID {
                let order = positions[state.milestones[i].id]!
                if state.milestones[i].sortOrder != order { state.milestones[i].sortOrder = order; state.milestones[i].updatedAt = date }
            }
        }
    }
    @discardableResult func deleteMilestone(_ id: UUID) throws -> Milestone {
        let existing = try milestone(id)
        try change(existing.goalID) { state, _, _ in
            state.milestones.removeAll { $0.id == id }
            for i in state.milestones.indices where state.milestones[i].goalID == existing.goalID && state.milestones[i].sortOrder > existing.sortOrder {
                state.milestones[i].sortOrder -= 1
            }
        }
        return existing
    }
    func restoreMilestone(_ item: Milestone) throws {
        try change(item.goalID) { state, _, _ in
            guard !state.milestones.contains(where: { $0.id == item.id }) else { return }
            var restored = item
            restored.sortOrder = min(item.sortOrder, state.milestones.filter { $0.goalID == item.goalID }.count)
            for i in state.milestones.indices where state.milestones[i].goalID == item.goalID && state.milestones[i].sortOrder >= restored.sortOrder {
                state.milestones[i].sortOrder += 1
            }
            state.milestones.append(restored)
        }
    }
    private func milestone(_ id: UUID) throws -> Milestone {
        guard let item = try repository.snapshot().milestones.first(where: { $0.id == id }) else { throw GoalError.missing }
        return item
    }
}
