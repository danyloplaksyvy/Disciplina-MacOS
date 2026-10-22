import Foundation

enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case todo, inProgress, completed
}

struct TodoItem: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var status: TaskStatus
    var deletedAt: Date?
    var seriesID: UUID?
    var scheduledDay: LocalDay?
    var goalID: UUID?
    var isCompleted: Bool { status == .completed }

    init(id: UUID, title: String, createdAt: Date, updatedAt: Date, completedAt: Date?,
         status: TaskStatus? = nil, deletedAt: Date? = nil, seriesID: UUID? = nil, scheduledDay: LocalDay? = nil, goalID: UUID? = nil) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.status = status ?? (completedAt == nil ? .todo : .completed)
        self.deletedAt = deletedAt
        self.seriesID = seriesID; self.scheduledDay = scheduledDay; self.goalID = goalID
    }
}

enum TaskError: LocalizedError, Equatable {
    case emptyTitle, multilineTitle, titleTooLong, notFound
    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Enter a task title."
        case .multilineTitle: "Use a single line for your task."
        case .titleTooLong: "Keep task titles to 200 characters or fewer."
        case .notFound: "This task no longer exists. Refresh the list and try again."
        }
    }
}
