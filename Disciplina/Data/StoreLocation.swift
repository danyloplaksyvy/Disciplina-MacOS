import Foundation
import SwiftData
import SQLite3

/// SQLite's backup API includes committed WAL content. Opening without CREATE
/// permits SQLite to initialize WAL bookkeeping, but never creates a missing source
/// or issues task/schema mutations against it.
enum DatabaseBackup {
    static func copy(from source: URL, to destination: URL) throws {
        var input: OpaquePointer?; var output: OpaquePointer?
        defer { sqlite3_close(input); sqlite3_close(output) }
        func failure(_ operation: String, _ code: Int32) -> NSError {
            let detail = [input, output].compactMap { handle -> String? in
                guard let handle else { return nil }
                return String(cString: sqlite3_errmsg(handle))
            }.joined(separator: "; ")
            return NSError(domain: "Disciplina.DatabaseBackup", code: Int(code),
                           userInfo: [NSLocalizedDescriptionKey: "Database snapshot failed during \(operation) (\(code)): \(detail)"])
        }
        let openedInput = sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READWRITE, nil)
        guard openedInput == SQLITE_OK else { throw failure("opening source", openedInput) }
        let openedOutput = sqlite3_open(destination.path, &output)
        guard openedOutput == SQLITE_OK else { throw failure("opening destination", openedOutput) }
        sqlite3_busy_timeout(input, 2000); sqlite3_busy_timeout(output, 2000)
        guard let backup = sqlite3_backup_init(output, "main", input, "main") else { throw failure("initializing", sqlite3_errcode(output)) }
        let result = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finish == SQLITE_OK else { throw failure("copying", result == SQLITE_DONE ? finish : result) }
        // Make the snapshot a standalone file. A copied WAL-mode header without
        // initialized sidecars cannot always be reopened read-only by Core Data.
        let journal = sqlite3_exec(output, "PRAGMA journal_mode=DELETE", nil, nil, nil)
        guard journal == SQLITE_OK else { throw failure("finalizing snapshot", journal) }

    }
}

@MainActor
final class StoreLocation {
    let root: URL
    private var manifest: URL { root.appendingPathComponent("Disciplina-store.json") }
    init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }
    private struct Manifest: Codable { let directory: String; var schemaVersion: Int? = nil }
    func publish(_ url: URL) throws {
        let directory = url.deletingLastPathComponent().lastPathComponent
        guard UUID(uuidString: directory) != nil else { throw DataError.invalidSnapshot }
        try JSONEncoder().encode(Manifest(directory: directory, schemaVersion: 6)).write(to: manifest, options: .atomic)
    }
    func newURL() throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("default.store")
    }
    func backup(_ url: URL) throws -> URL {
        let directory = root.appendingPathComponent("Disciplina Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = directory.appendingPathComponent("\(UUID().uuidString).store")
        try DatabaseBackup.copy(from: url, to: backup)
        return backup
    }
    func open(beforePublish: () throws -> Void = {}) throws -> PersistenceController {
        if FileManager.default.fileExists(atPath: manifest.path) {
            let value = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifest))
            guard UUID(uuidString: value.directory) != nil else { throw DataError.invalidSnapshot }
            let url = root.appendingPathComponent(value.directory).appendingPathComponent("default.store")
            guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
            if value.schemaVersion == 6 {
                let persistence = try PersistenceController(url: url)
                try SwiftDataTaskRepository(context: persistence.container.mainContext).snapshot().validate()
                return persistence
            }
            guard value.schemaVersion == nil || value.schemaVersion == 2 || value.schemaVersion == 3 || value.schemaVersion == 4 || value.schemaVersion == 5 else { throw DataError.unsupportedVersion }
            let backup = try backup(url)
            let inspection = try newURL()
            try DatabaseBackup.copy(from: backup, to: inspection)
            let expected: TaskSnapshot
            switch value.schemaVersion {
            case 5: expected = try readV5(inspection)
            case 4: expected = try readV4(inspection)
            case 3: expected = try readV3(inspection)
            default: expected = try readV2(inspection)
            }
            let target = try newURL()
            try DatabaseBackup.copy(from: backup, to: target)
            let persistence = try PersistenceController(url: target)
            let actual = try SwiftDataTaskRepository(context: persistence.container.mainContext).snapshot()
            try verify(actual, matches: expected)
            try beforePublish()
            try publish(target)
            return persistence
        }
        let legacy = root.appendingPathComponent("default.store")
        let target = try newURL()
        var expected: [TodoItem]?
        if FileManager.default.fileExists(atPath: legacy.path) {
            let backup = try backup(legacy)
            // Core Data may create SQLite sidecars even for inspection. Give it a
            // disposable copy so the retained backup stays untouched.
            let inspection = try newURL()
            try DatabaseBackup.copy(from: backup, to: inspection)
            expected = try readV1(inspection)
            try DatabaseBackup.copy(from: backup, to: target)
        }
        let persistence = try PersistenceController(url: target)
        let state = try SwiftDataTaskRepository(context: persistence.container.mainContext).snapshot()
        try state.validate()
        if let expected {
            guard state.tasks.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == expected.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
                  state.sessions.isEmpty else { throw DataError.invalidSnapshot }
        }
        try beforePublish()
        try publish(target)
        return persistence
    }
    func restore(_ snapshot: TaskSnapshot, currentURL: URL?, beforePublish: () throws -> Void = {}) throws -> PersistenceController {
        try snapshot.validate()
        if let currentURL { _ = try backup(currentURL) }
        var normalized = snapshot
        normalized.closeInterrupted()
        let url = try newURL()
        let replacement = try PersistenceController(url: url)
        let repository = SwiftDataTaskRepository(context: replacement.container.mainContext)
        try repository.commit(normalized)
        let saved = try repository.snapshot()
        try saved.validate()
        guard saved.goals.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == normalized.goals.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
              saved.milestones.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == normalized.milestones.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
              saved.series.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == normalized.series.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
              saved.tasks.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == normalized.tasks.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
              saved.sessions.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == normalized.sessions.sorted(by: { $0.id.uuidString < $1.id.uuidString }) else { throw DataError.invalidSnapshot }
        try beforePublish()
        try publish(url)
        return replacement
    }

    private func verify(_ actual: TaskSnapshot, matches expected: TaskSnapshot) throws {
        try actual.validate()
        guard actual.goals.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == expected.goals.sorted(by: { $0.id.uuidString < $1.id.uuidString }), actual.milestones.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == expected.milestones.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
              actual.series.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == expected.series.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
              actual.tasks.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == expected.tasks.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
              actual.sessions.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == expected.sessions.sorted(by: { $0.id.uuidString < $1.id.uuidString }) else { throw DataError.invalidSnapshot }
    }
    private func readV2(_ url: URL) throws -> TaskSnapshot {
        let schema = Schema(versionedSchema: TaskSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let tasks = try container.mainContext.fetch(FetchDescriptor<TaskSchemaV2.TaskRecord>())
        let sessions = try container.mainContext.fetch(FetchDescriptor<TaskSchemaV2.SessionRecord>())
        guard tasks.allSatisfy({ TaskStatus(rawValue: $0.statusRaw) != nil }),
              sessions.allSatisfy({ $0.endReasonRaw == nil || SessionEndReason(rawValue: $0.endReasonRaw!) != nil }) else { throw DataError.invalidSnapshot }
        let state = TaskSnapshot(tasks: tasks.map(\.item), sessions: sessions.map(\.item))
        try state.validate()
        return state
    }

    private func readV3(_ url: URL) throws -> TaskSnapshot {
        let schema = Schema(versionedSchema: TaskSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let tasks = try container.mainContext.fetch(FetchDescriptor<TaskSchemaV3.TaskRecord>())
        let sessions = try container.mainContext.fetch(FetchDescriptor<TaskSchemaV3.SessionRecord>())
        guard sessions.allSatisfy({ SessionOrigin(rawValue: $0.originRaw) != nil }),
              tasks.allSatisfy({ TaskStatus(rawValue: $0.statusRaw) != nil }),
              sessions.allSatisfy({ $0.endReasonRaw == nil || SessionEndReason(rawValue: $0.endReasonRaw!) != nil }) else { throw DataError.invalidSnapshot }
        let state = TaskSnapshot(tasks: tasks.map(\.item), sessions: sessions.map(\.item))
        try state.validate()
        return state
    }

    private func readV4(_ url: URL) throws -> TaskSnapshot {
        let schema = Schema(versionedSchema: TaskSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let tasks = try container.mainContext.fetch(FetchDescriptor<TaskSchemaV4.TaskRecord>())
        let sessions = try container.mainContext.fetch(FetchDescriptor<TaskSchemaV4.SessionRecord>())
        guard sessions.allSatisfy({ SessionOrigin(rawValue: $0.originRaw) != nil }),
              tasks.allSatisfy({ TaskStatus(rawValue: $0.statusRaw) != nil }),
              sessions.allSatisfy({ $0.endReasonRaw == nil || SessionEndReason(rawValue: $0.endReasonRaw!) != nil }) else { throw DataError.invalidSnapshot }
        for task in tasks { if let data = task.scheduledDayData { _ = try JSONDecoder().decode(LocalDay.self, from: data) } }
        let series = try container.mainContext.fetch(FetchDescriptor<TaskSchemaV4.SeriesRecord>()).map { try $0.value() }
        let state = TaskSnapshot(tasks: tasks.map(\.item), sessions: sessions.map(\.item), series: series)
        try state.validate()
        return state
    }

    private func readV5(_ url: URL) throws -> TaskSnapshot {
        let schema = Schema(versionedSchema: TaskSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let tasks = try container.mainContext.fetch(FetchDescriptor<TaskSchemaV5.TaskRecord>())
        let sessions = try container.mainContext.fetch(FetchDescriptor<TaskSchemaV5.SessionRecord>())
        guard sessions.allSatisfy({ SessionOrigin(rawValue: $0.originRaw) != nil }),
              tasks.allSatisfy({ TaskStatus(rawValue: $0.statusRaw) != nil }),
              sessions.allSatisfy({ $0.endReasonRaw == nil || SessionEndReason(rawValue: $0.endReasonRaw!) != nil }) else { throw DataError.invalidSnapshot }
        for task in tasks { if let data = task.scheduledDayData { _ = try JSONDecoder().decode(LocalDay.self, from: data) } }
        let series = try container.mainContext.fetch(FetchDescriptor<TaskSchemaV5.SeriesRecord>()).map { try $0.value() }
        let state = TaskSnapshot(tasks: tasks.map(\.item), sessions: sessions.map(\.item), series: series, goals: try container.mainContext.fetch(FetchDescriptor<TaskSchemaV5.GoalRecord>()).map { try $0.value() }, milestones: try container.mainContext.fetch(FetchDescriptor<TaskSchemaV5.MilestoneRecord>()).map { try $0.value() })
        try state.validate()
        return state
    }

    private func readV1(_ url: URL) throws -> [TodoItem] {
        let schema = Schema(versionedSchema: TaskSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return try container.mainContext.fetch(FetchDescriptor<TaskSchemaV1.TaskRecord>()).map(\.item)
    }
}
