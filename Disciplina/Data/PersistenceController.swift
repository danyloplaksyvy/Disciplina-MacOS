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

typealias TaskRecord = TaskSchemaV3.TaskRecord
typealias SessionRecord = TaskSchemaV3.SessionRecord

enum TaskMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TaskSchemaV1.self, TaskSchemaV2.self, TaskSchemaV3.self] }
    static var stages: [MigrationStage] {
        [.custom(fromVersion: TaskSchemaV1.self, toVersion: TaskSchemaV2.self,
                 willMigrate: nil, didMigrate: { context in
            for record in try context.fetch(FetchDescriptor<TaskSchemaV2.TaskRecord>()) {
                record.statusRaw = record.completedAt == nil ? "todo" : "completed"
            }
            try context.save()
        }), .lightweight(fromVersion: TaskSchemaV2.self, toVersion: TaskSchemaV3.self)]
    }
}

@MainActor
final class PersistenceController {
    let container: ModelContainer
    let url: URL?

    init(inMemory: Bool = false, url: URL? = nil) throws {
        let schema = Schema(versionedSchema: TaskSchemaV3.self)
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        self.url = url
        container = try ModelContainer(for: schema, migrationPlan: TaskMigrationPlan.self, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
    }
}
