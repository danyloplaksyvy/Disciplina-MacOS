import Foundation

enum GoalStatus: String, Codable, CaseIterable, Sendable {
    case active, achieved, archived
    var title: String { switch self { case .active: "Active"; case .achieved: "Achieved"; case .archived: "Archived" } }
}

struct Goal: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    var successCriteria: String
    var status: GoalStatus = .active
    var targetDay: LocalDay?
    let createdAt: Date
    var updatedAt: Date
    var achievedAt: Date?
    var archivedAt: Date?
    var statusBeforeArchive: GoalStatus?
}

struct Milestone: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let goalID: UUID
    var title: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isCompleted: Bool { completedAt != nil }
}

enum GoalError: LocalizedError {
    case invalidTitle, invalidCriteria, invalidMilestone, missing, running
    var errorDescription: String? {
        switch self {
        case .invalidTitle: "Enter a single-line goal title of 1–120 characters."
        case .invalidCriteria: "Enter a success criterion of 1–500 characters."
        case .invalidMilestone: "Enter a single-line milestone title of 1–200 characters."
        case .missing: "This goal or milestone is no longer available. Reload and try again."
        case .running: "Pause this task before changing its goal. Recorded time will keep its original attribution."
        }
    }
}

extension TaskSnapshot {
    @MainActor func validateGoals() throws {
        let ids = Set(goals.map(\.id))
        guard ids.count == goals.count, Set(milestones.map(\.id)).count == milestones.count else { throw DataError.invalidSnapshot }
        for goal in goals {
            guard try GoalService.title(goal.title) == goal.title,
                  try GoalService.criteria(goal.successCriteria) == goal.successCriteria,
                  [goal.createdAt, goal.updatedAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
                  [goal.achievedAt, goal.archivedAt].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else { throw DataError.invalidSnapshot }
            if let day = goal.targetDay { _ = try day.date() }
            switch goal.status {
            case .active:
                guard goal.achievedAt == nil, goal.archivedAt == nil, goal.statusBeforeArchive == nil else { throw DataError.invalidSnapshot }
            case .achieved:
                guard goal.achievedAt != nil, goal.archivedAt == nil, goal.statusBeforeArchive == nil else { throw DataError.invalidSnapshot }
            case .archived:
                guard goal.archivedAt != nil, let prior = goal.statusBeforeArchive, prior != .archived,
                      (prior == .achieved) == (goal.achievedAt != nil) else { throw DataError.invalidSnapshot }
            }
        }
        for milestone in milestones {
            guard ids.contains(milestone.goalID), try GoalService.milestoneTitle(milestone.title) == milestone.title,
                  milestone.sortOrder >= 0,
                  [milestone.createdAt, milestone.updatedAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
                  milestone.completedAt?.timeIntervalSince1970.isFinite != false else { throw DataError.invalidSnapshot }
        }
        for group in Dictionary(grouping: milestones, by: \.goalID).values {
            guard group.map(\.sortOrder).sorted() == Array(0..<group.count) else { throw DataError.invalidSnapshot }
        }
        for id in tasks.compactMap(\.goalID) + sessions.compactMap(\.goalIDAtStart) + series.compactMap(\.futureGoalID) {
            guard ids.contains(id) else { throw DataError.invalidSnapshot }
        }
        var totals: [UUID: Int64] = [:]
        for session in sessions {
            if let id = session.goalIDAtStart {
                let sum = (totals[id] ?? 0).addingReportingOverflow(session.accumulatedMilliseconds)
                guard session.accumulatedMilliseconds >= 0, !sum.overflow else { throw DataError.invalidSnapshot }
                totals[id] = sum.partialValue
            }
        }
    }
}

struct GoalProgressService {
    struct Progress: Equatable {
        var completed = 0
        var count = 0
        var fraction: Double? { count == 0 ? nil : Double(completed) / Double(count) }
        var description: String { count == 0 ? "No milestones defined" : "\(completed) of \(count) milestones completed" }
    }
    private(set) var progress: [UUID: Progress] = [:]
    private(set) var durations: [UUID: Int64] = [:]
    private(set) var taskContributions: [UUID: [UUID: Int64]] = [:]
    // Only called with a validated committed snapshot, never on presentation ticks.
    init(milestones: [Milestone] = [], sessions: [WorkSession] = []) {
        for item in milestones {
            progress[item.goalID, default: Progress()].count += 1
            if item.isCompleted { progress[item.goalID, default: Progress()].completed += 1 }
        }
        for session in sessions {
            guard let goalID = session.goalIDAtStart else { continue }
            durations[goalID, default: 0] += session.accumulatedMilliseconds
            taskContributions[goalID, default: [:]][session.taskID, default: 0] += session.accumulatedMilliseconds
        }
    }
}
