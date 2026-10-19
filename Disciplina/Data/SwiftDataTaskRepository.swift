import Foundation
import SwiftData

@MainActor
final class SwiftDataTaskRepository: TaskRepository {
    private let context: ModelContext
    private let save: (ModelContext) throws -> Void

    init(context: ModelContext, save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.save = save
    }

    func fetchAll() throws -> [TodoItem] {
        try context.fetch(FetchDescriptor<TaskRecord>()).map(\.item)
    }

    func insert(_ item: TodoItem) throws {
        // Do not rely on SwiftData's unique-attribute upsert behavior.
        guard try record(item.id) == nil else { throw CocoaError(.validationMultipleErrors) }
        try transaction { context.insert(TaskRecord(item)) }
    }

    func update(_ item: TodoItem) throws {
        guard let record = try record(item.id) else { throw TaskError.notFound }
        try transaction {
            record.title = item.title
            record.updatedAt = item.updatedAt
            record.completedAt = item.completedAt
        }
    }

    func delete(id: UUID) throws {
        guard let record = try record(id) else { throw TaskError.notFound }
        try transaction { context.delete(record) }
    }

    private func record(_ id: UUID) throws -> TaskRecord? {
        var descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func transaction(_ mutation: () -> Void) throws {
        do {
            mutation()
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}
