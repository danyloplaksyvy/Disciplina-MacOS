import Foundation

enum SessionEndReason: String, Codable, Sendable {
    case paused, switchedTask, completed, movedToTodo, deleted, systemSleep, appQuit, interrupted
}

struct WorkSession: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let taskID: UUID
    let startedAt: Date
    var endedAt: Date?
    var accumulatedMilliseconds: Int64 = 0
    var lastCheckpointAt: Date?
    var endReason: SessionEndReason?
}

struct TaskSnapshot: Equatable, Codable, Sendable {
    var tasks: [TodoItem] = []
    var sessions: [WorkSession] = []

    @MainActor func validate() throws {
        guard Set(tasks.map(\.id)).count == tasks.count,
              Set(sessions.map(\.id)).count == sessions.count,
              sessions.filter({ $0.endedAt == nil }).count <= 1 else { throw DataError.invalidSnapshot }
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var totals: [UUID: Int64] = [:]
        for task in tasks {
            guard (task.status == .completed) == (task.completedAt != nil),
                  task.createdAt.timeIntervalSince1970.isFinite,
                  task.updatedAt.timeIntervalSince1970.isFinite else { throw DataError.invalidSnapshot }
            _ = try TaskService.validatedTitle(task.title)
        }
        for session in sessions {
            guard let task = byID[session.taskID], session.accumulatedMilliseconds >= 0,
                  (session.endedAt == nil) == (session.endReason == nil),
                  session.lastCheckpointAt != nil,
                  session.endedAt != nil || (task.status == .inProgress && task.deletedAt == nil)
            else { throw DataError.invalidSnapshot }
            let sum = (totals[task.id] ?? 0).addingReportingOverflow(session.accumulatedMilliseconds)
            guard !sum.overflow else { throw DataError.invalidSnapshot }
            totals[task.id] = sum.partialValue
        }
    }

    mutating func closeInterrupted() {
        for index in sessions.indices where sessions[index].endedAt == nil {
            sessions[index].endedAt = sessions[index].lastCheckpointAt ?? sessions[index].startedAt
            sessions[index].endReason = .interrupted
        }
    }
}

enum DataError: LocalizedError {
    case invalidSnapshot, unsupportedVersion, timerUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidSnapshot: "The data contains invalid or inconsistent records. Nothing was replaced."
        case .unsupportedVersion: "This backup format is not supported."
        case .timerUnavailable: "Timing is stopped until the saved state can be recovered. Retry loading."
        }
    }
}

enum DurationText {
    static func precise(_ milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds) / 1000
        return String(format: "%02lld:%02lld:%02lld", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    static func concise(_ milliseconds: Int64) -> String {
        let minutes = max(0, milliseconds) / 60000
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
