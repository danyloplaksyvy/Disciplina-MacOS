import Foundation
import SwiftData

enum TaskSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [TaskRecord.self] }

    @Model
    final class TaskRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?

        init(_ item: TodoItem) {
            id = item.id
            title = item.title
            createdAt = item.createdAt
            updatedAt = item.updatedAt
            completedAt = item.completedAt
        }

        var item: TodoItem {
            TodoItem(id: id, title: title, createdAt: createdAt,
                     updatedAt: updatedAt, completedAt: completedAt)
        }
    }
}

enum TaskSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [TaskRecord.self, SessionRecord.self] }

    @Model final class TaskRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var statusRaw: String = "todo"
        var deletedAt: Date?
        init(_ item: TodoItem) {
            id = item.id; title = item.title; createdAt = item.createdAt; updatedAt = item.updatedAt
            completedAt = item.completedAt; statusRaw = item.status.rawValue; deletedAt = item.deletedAt
        }
        var item: TodoItem {
            TodoItem(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt,
                     completedAt: completedAt, status: TaskStatus(rawValue: statusRaw), deletedAt: deletedAt)
        }
        func apply(_ item: TodoItem) {
            title = item.title; updatedAt = item.updatedAt; completedAt = item.completedAt
            statusRaw = item.status.rawValue; deletedAt = item.deletedAt
        }
    }
    @Model final class SessionRecord {
        @Attribute(.unique) var id: UUID
        var taskID: UUID
        var startedAt: Date
        var endedAt: Date?
        var accumulatedMilliseconds: Int64
        var lastCheckpointAt: Date?
        var endReasonRaw: String?
        init(_ item: WorkSession) {
            id = item.id; taskID = item.taskID; startedAt = item.startedAt
            endedAt = item.endedAt; accumulatedMilliseconds = item.accumulatedMilliseconds
            lastCheckpointAt = item.lastCheckpointAt; endReasonRaw = item.endReason?.rawValue
        }
        var item: WorkSession {
            WorkSession(id: id, taskID: taskID, startedAt: startedAt, endedAt: endedAt,
                        accumulatedMilliseconds: accumulatedMilliseconds, lastCheckpointAt: lastCheckpointAt,
                        endReason: endReasonRaw.flatMap(SessionEndReason.init(rawValue:)))
        }
        func apply(_ item: WorkSession) {
            endedAt = item.endedAt; accumulatedMilliseconds = item.accumulatedMilliseconds
            lastCheckpointAt = item.lastCheckpointAt; endReasonRaw = item.endReason?.rawValue
        }
    }
}

enum TaskSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(3, 0, 0) }
    static var models: [any PersistentModel.Type] { [TaskRecord.self, SessionRecord.self] }

    @Model final class TaskRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var statusRaw: String = "todo"
        var deletedAt: Date?
        init(_ item: TodoItem) {
            id = item.id; title = item.title; createdAt = item.createdAt; updatedAt = item.updatedAt
            completedAt = item.completedAt; statusRaw = item.status.rawValue; deletedAt = item.deletedAt
        }
        var item: TodoItem {
            TodoItem(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt,
                     completedAt: completedAt, status: TaskStatus(rawValue: statusRaw), deletedAt: deletedAt)
        }
        func apply(_ item: TodoItem) {
            title = item.title; updatedAt = item.updatedAt; completedAt = item.completedAt
            statusRaw = item.status.rawValue; deletedAt = item.deletedAt
        }
    }
    @Model final class SessionRecord {
        @Attribute(.unique) var id: UUID
        var taskID: UUID
        var startedAt: Date
        var endedAt: Date?
        var accumulatedMilliseconds: Int64
        var lastCheckpointAt: Date?
        var endReasonRaw: String?
        var originRaw: String = "timer"
        var durationEditedAt: Date?
        init(_ item: WorkSession) {
            id = item.id; taskID = item.taskID; startedAt = item.startedAt
            endedAt = item.endedAt; accumulatedMilliseconds = item.accumulatedMilliseconds
            lastCheckpointAt = item.lastCheckpointAt; endReasonRaw = item.endReason?.rawValue
            originRaw = item.origin.rawValue; durationEditedAt = item.durationEditedAt
        }
        var item: WorkSession {
            WorkSession(id: id, taskID: taskID, startedAt: startedAt, endedAt: endedAt,
                        accumulatedMilliseconds: accumulatedMilliseconds, lastCheckpointAt: lastCheckpointAt,
                        endReason: endReasonRaw.flatMap(SessionEndReason.init(rawValue:)),
                        origin: SessionOrigin(rawValue: originRaw) ?? .timer, durationEditedAt: durationEditedAt)
        }
        func apply(_ item: WorkSession) {
            endedAt = item.endedAt; accumulatedMilliseconds = item.accumulatedMilliseconds
            lastCheckpointAt = item.lastCheckpointAt; endReasonRaw = item.endReason?.rawValue
            originRaw = item.origin.rawValue; durationEditedAt = item.durationEditedAt
        }
    }
}

enum TaskSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(4, 0, 0) }
    static var models: [any PersistentModel.Type] { [TaskRecord.self, SessionRecord.self, SeriesRecord.self] }

    @Model final class TaskRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var statusRaw: String = "todo"
        var deletedAt: Date?
        var seriesID: UUID?
        var scheduledDayData: Data?
        init(_ item: TodoItem) {
            id = item.id; title = item.title; createdAt = item.createdAt; updatedAt = item.updatedAt
            completedAt = item.completedAt; statusRaw = item.status.rawValue; deletedAt = item.deletedAt
            seriesID = item.seriesID; scheduledDayData = item.scheduledDay.flatMap { try? JSONEncoder().encode($0) }
        }
        var item: TodoItem {
            TodoItem(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt,
                     completedAt: completedAt, status: TaskStatus(rawValue: statusRaw), deletedAt: deletedAt, seriesID: seriesID,
                     scheduledDay: scheduledDayData.flatMap { try? JSONDecoder().decode(LocalDay.self, from: $0) })
        }
        func apply(_ item: TodoItem) {
            title = item.title; updatedAt = item.updatedAt; completedAt = item.completedAt
            statusRaw = item.status.rawValue; deletedAt = item.deletedAt
            seriesID = item.seriesID; scheduledDayData = item.scheduledDay.flatMap { try? JSONEncoder().encode($0) }
        }
    }
    @Model final class SessionRecord {
        @Attribute(.unique) var id: UUID
        var taskID: UUID
        var startedAt: Date
        var endedAt: Date?
        var accumulatedMilliseconds: Int64
        var lastCheckpointAt: Date?
        var endReasonRaw: String?
        var originRaw: String = "timer"
        var durationEditedAt: Date?
        init(_ item: WorkSession) {
            id = item.id; taskID = item.taskID; startedAt = item.startedAt
            endedAt = item.endedAt; accumulatedMilliseconds = item.accumulatedMilliseconds
            lastCheckpointAt = item.lastCheckpointAt; endReasonRaw = item.endReason?.rawValue
            originRaw = item.origin.rawValue; durationEditedAt = item.durationEditedAt
        }
        var item: WorkSession {
            WorkSession(id: id, taskID: taskID, startedAt: startedAt, endedAt: endedAt,
                        accumulatedMilliseconds: accumulatedMilliseconds, lastCheckpointAt: lastCheckpointAt,
                        endReason: endReasonRaw.flatMap(SessionEndReason.init(rawValue:)),
                        origin: SessionOrigin(rawValue: originRaw) ?? .timer, durationEditedAt: durationEditedAt)
        }
        func apply(_ item: WorkSession) {
            endedAt = item.endedAt; accumulatedMilliseconds = item.accumulatedMilliseconds
            lastCheckpointAt = item.lastCheckpointAt; endReasonRaw = item.endReason?.rawValue
            originRaw = item.origin.rawValue; durationEditedAt = item.durationEditedAt
        }
    }
    @Model final class SeriesRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(_ item: RecurrenceSeries) throws {
            id = item.id; payload = try JSONEncoder().encode(item)
        }
        func value() throws -> RecurrenceSeries {
            let value = try JSONDecoder().decode(RecurrenceSeries.self, from: payload)
            guard value.id == id else { throw DataError.invalidSnapshot }
            return value
        }
    }
}

enum TaskSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(5, 0, 0) }
    static var models: [any PersistentModel.Type] { [TaskRecord.self, SessionRecord.self, SeriesRecord.self, GoalRecord.self, MilestoneRecord.self] }

    @Model final class TaskRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var statusRaw: String = "todo"
        var deletedAt: Date?
        var seriesID: UUID?
        var scheduledDayData: Data?
        var goalID: UUID?
        init(_ item: TodoItem) {
            id = item.id; title = item.title; createdAt = item.createdAt; updatedAt = item.updatedAt
            completedAt = item.completedAt; statusRaw = item.status.rawValue; deletedAt = item.deletedAt
            goalID = item.goalID; seriesID = item.seriesID; scheduledDayData = item.scheduledDay.flatMap { try? JSONEncoder().encode($0) }
        }
        var item: TodoItem {
            TodoItem(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt,
                     completedAt: completedAt, status: TaskStatus(rawValue: statusRaw), deletedAt: deletedAt, seriesID: seriesID,
                     scheduledDay: scheduledDayData.flatMap { try? JSONDecoder().decode(LocalDay.self, from: $0) }, goalID: goalID)
        }
        func apply(_ item: TodoItem) {
            title = item.title; updatedAt = item.updatedAt; completedAt = item.completedAt
            statusRaw = item.status.rawValue; deletedAt = item.deletedAt
            goalID = item.goalID; seriesID = item.seriesID; scheduledDayData = item.scheduledDay.flatMap { try? JSONEncoder().encode($0) }
        }
    }
    @Model final class SessionRecord {
        @Attribute(.unique) var id: UUID
        var taskID: UUID
        var startedAt: Date
        var endedAt: Date?
        var accumulatedMilliseconds: Int64
        var lastCheckpointAt: Date?
        var endReasonRaw: String?
        var originRaw: String = "timer"
        var durationEditedAt: Date?
        var goalIDAtStart: UUID?
        init(_ item: WorkSession) {
            id = item.id; taskID = item.taskID; startedAt = item.startedAt
            endedAt = item.endedAt; accumulatedMilliseconds = item.accumulatedMilliseconds
            lastCheckpointAt = item.lastCheckpointAt; endReasonRaw = item.endReason?.rawValue
            originRaw = item.origin.rawValue; durationEditedAt = item.durationEditedAt; goalIDAtStart = item.goalIDAtStart
        }
        var item: WorkSession {
            WorkSession(id: id, taskID: taskID, startedAt: startedAt, endedAt: endedAt,
                        accumulatedMilliseconds: accumulatedMilliseconds, lastCheckpointAt: lastCheckpointAt,
                        endReason: endReasonRaw.flatMap(SessionEndReason.init(rawValue:)),
                        origin: SessionOrigin(rawValue: originRaw) ?? .timer, durationEditedAt: durationEditedAt, goalIDAtStart: goalIDAtStart)
        }
        func apply(_ item: WorkSession) {
            endedAt = item.endedAt; accumulatedMilliseconds = item.accumulatedMilliseconds
            lastCheckpointAt = item.lastCheckpointAt; endReasonRaw = item.endReason?.rawValue
            originRaw = item.origin.rawValue; durationEditedAt = item.durationEditedAt; goalIDAtStart = item.goalIDAtStart
        }
    }
    @Model final class SeriesRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(_ item: RecurrenceSeries) throws {
            id = item.id; payload = try JSONEncoder().encode(item)
        }
        func value() throws -> RecurrenceSeries {
            let value = try JSONDecoder().decode(RecurrenceSeries.self, from: payload)
            guard value.id == id else { throw DataError.invalidSnapshot }
            return value
        }
    }
    @Model final class GoalRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(_ item: Goal) throws { id = item.id; payload = try JSONEncoder().encode(item) }
        func value() throws -> Goal {
            let item = try JSONDecoder().decode(Goal.self, from: payload)
            guard item.id == id else { throw DataError.invalidSnapshot }
            return item
        }
    }
    @Model final class MilestoneRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(_ item: Milestone) throws { id = item.id; payload = try JSONEncoder().encode(item) }
        func value() throws -> Milestone {
            let item = try JSONDecoder().decode(Milestone.self, from: payload)
            guard item.id == id else { throw DataError.invalidSnapshot }
            return item
        }
    }
}

enum TaskSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(6, 0, 0) }
    static var models: [any PersistentModel.Type] { [TaskRecord.self, SessionRecord.self, SeriesRecord.self, GoalRecord.self, MilestoneRecord.self] }

    @Model final class TaskRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var statusRaw: String = "todo"
        var deletedAt: Date?
        var seriesID: UUID?
        var scheduledDayData: Data?
        var goalID: UUID?
        var appearanceData: Data?
        init(_ item: TodoItem) {
            id = item.id; title = item.title; createdAt = item.createdAt; updatedAt = item.updatedAt
            completedAt = item.completedAt; statusRaw = item.status.rawValue; deletedAt = item.deletedAt
            appearanceData = item.appearance.flatMap { try? JSONEncoder().encode($0) }; goalID = item.goalID; seriesID = item.seriesID; scheduledDayData = item.scheduledDay.flatMap { try? JSONEncoder().encode($0) }
        }
        var item: TodoItem {
            TodoItem(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt,
                     completedAt: completedAt, status: TaskStatus(rawValue: statusRaw), deletedAt: deletedAt, seriesID: seriesID,
                     scheduledDay: scheduledDayData.flatMap { try? JSONDecoder().decode(LocalDay.self, from: $0) }, goalID: goalID, appearance: appearanceData.flatMap { try? JSONDecoder().decode(TaskAppearance.self, from: $0) })
        }
        func apply(_ item: TodoItem) {
            title = item.title; updatedAt = item.updatedAt; completedAt = item.completedAt
            statusRaw = item.status.rawValue; deletedAt = item.deletedAt
            appearanceData = item.appearance.flatMap { try? JSONEncoder().encode($0) }; goalID = item.goalID; seriesID = item.seriesID; scheduledDayData = item.scheduledDay.flatMap { try? JSONEncoder().encode($0) }
        }
    }
    @Model final class SessionRecord {
        @Attribute(.unique) var id: UUID
        var taskID: UUID
        var startedAt: Date
        var endedAt: Date?
        var accumulatedMilliseconds: Int64
        var lastCheckpointAt: Date?
        var endReasonRaw: String?
        var originRaw: String = "timer"
        var durationEditedAt: Date?
        var goalIDAtStart: UUID?
        var allocationData: Data?
        var legacyDayData: Data?
        init(_ item: WorkSession) {
            id = item.id; taskID = item.taskID; startedAt = item.startedAt
            endedAt = item.endedAt; accumulatedMilliseconds = item.accumulatedMilliseconds
            lastCheckpointAt = item.lastCheckpointAt; endReasonRaw = item.endReason?.rawValue
            allocationData = item.allocations.flatMap { try? JSONEncoder().encode($0) }; legacyDayData = item.legacyDay.flatMap { try? JSONEncoder().encode($0) }; originRaw = item.origin.rawValue; durationEditedAt = item.durationEditedAt; goalIDAtStart = item.goalIDAtStart
        }
        var item: WorkSession {
            WorkSession(id: id, taskID: taskID, startedAt: startedAt, endedAt: endedAt,
                        accumulatedMilliseconds: accumulatedMilliseconds, lastCheckpointAt: lastCheckpointAt,
                        endReason: endReasonRaw.flatMap(SessionEndReason.init(rawValue:)),
                        origin: SessionOrigin(rawValue: originRaw) ?? .timer, durationEditedAt: durationEditedAt, goalIDAtStart: goalIDAtStart, allocations: allocationData.flatMap { try? JSONDecoder().decode([DailyAllocation].self, from: $0) }, legacyDay: legacyDayData.flatMap { try? JSONDecoder().decode(LocalDay.self, from: $0) })
        }
        func apply(_ item: WorkSession) {
            endedAt = item.endedAt; accumulatedMilliseconds = item.accumulatedMilliseconds
            lastCheckpointAt = item.lastCheckpointAt; endReasonRaw = item.endReason?.rawValue
            allocationData = item.allocations.flatMap { try? JSONEncoder().encode($0) }; legacyDayData = item.legacyDay.flatMap { try? JSONEncoder().encode($0) }; originRaw = item.origin.rawValue; durationEditedAt = item.durationEditedAt; goalIDAtStart = item.goalIDAtStart
        }
    }
    @Model final class SeriesRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(_ item: RecurrenceSeries) throws {
            id = item.id; payload = try JSONEncoder().encode(item)
        }
        func value() throws -> RecurrenceSeries {
            let value = try JSONDecoder().decode(RecurrenceSeries.self, from: payload)
            guard value.id == id else { throw DataError.invalidSnapshot }
            return value
        }
    }
    @Model final class GoalRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(_ item: Goal) throws { id = item.id; payload = try JSONEncoder().encode(item) }
        func value() throws -> Goal {
            let item = try JSONDecoder().decode(Goal.self, from: payload)
            guard item.id == id else { throw DataError.invalidSnapshot }
            return item
        }
    }
    @Model final class MilestoneRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(_ item: Milestone) throws { id = item.id; payload = try JSONEncoder().encode(item) }
        func value() throws -> Milestone {
            let item = try JSONDecoder().decode(Milestone.self, from: payload)
            guard item.id == id else { throw DataError.invalidSnapshot }
            return item
        }
    }
}

typealias TaskRecord = TaskSchemaV6.TaskRecord
typealias SessionRecord = TaskSchemaV6.SessionRecord

typealias SeriesRecord = TaskSchemaV6.SeriesRecord
typealias GoalRecord = TaskSchemaV6.GoalRecord
typealias MilestoneRecord = TaskSchemaV6.MilestoneRecord

enum TaskMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TaskSchemaV1.self, TaskSchemaV2.self, TaskSchemaV3.self, TaskSchemaV4.self, TaskSchemaV5.self, TaskSchemaV6.self] }
    static var stages: [MigrationStage] {
        [.custom(fromVersion: TaskSchemaV1.self, toVersion: TaskSchemaV2.self,
                 willMigrate: nil, didMigrate: { context in
            for record in try context.fetch(FetchDescriptor<TaskSchemaV2.TaskRecord>()) {
                record.statusRaw = record.completedAt == nil ? "todo" : "completed"
            }
            try context.save()
        }), .lightweight(fromVersion: TaskSchemaV2.self, toVersion: TaskSchemaV3.self),
         .lightweight(fromVersion: TaskSchemaV3.self, toVersion: TaskSchemaV4.self),
         .lightweight(fromVersion: TaskSchemaV4.self, toVersion: TaskSchemaV5.self),
         .lightweight(fromVersion: TaskSchemaV5.self, toVersion: TaskSchemaV6.self)]
    }
}

@MainActor
final class PersistenceController {
    let container: ModelContainer
    let url: URL?

    init(inMemory: Bool = false, url: URL? = nil) throws {
        let schema = Schema(versionedSchema: TaskSchemaV6.self)
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        self.url = url
        container = try ModelContainer(for: schema, migrationPlan: TaskMigrationPlan.self, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
    }
}
