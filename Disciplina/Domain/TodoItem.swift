import Foundation

struct TodoItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isCompleted: Bool { completedAt != nil }
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
