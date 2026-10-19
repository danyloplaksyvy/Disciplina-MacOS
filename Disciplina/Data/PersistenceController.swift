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

typealias TaskRecord = TaskSchemaV1.TaskRecord

enum TaskMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TaskSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@MainActor
final class PersistenceController {
    let container: ModelContainer

    init(inMemory: Bool = false, url: URL? = nil) throws {
        let schema = Schema(versionedSchema: TaskSchemaV1.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory,
                                                 cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, migrationPlan: TaskMigrationPlan.self,
                                        configurations: [configuration])
        container.mainContext.autosaveEnabled = false
    }
}
