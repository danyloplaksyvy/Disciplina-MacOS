import Foundation

struct BackupDocument: Codable {
    let formatVersion: Int
    let exportedAt: Date
    var tasks: [TodoItem]
    var sessions: [WorkSession]
    init(snapshot: TaskSnapshot, date: Date = Date()) {
        formatVersion = 1; exportedAt = date; tasks = snapshot.tasks; sessions = snapshot.sessions
    }
    @MainActor func validatedSnapshot() throws -> TaskSnapshot {
        guard formatVersion == 1 else { throw DataError.unsupportedVersion }
        let snapshot = TaskSnapshot(tasks: tasks, sessions: sessions)
        try snapshot.validate()
        return snapshot
    }
    static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Self.self, from: data)
    }
    func encode() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
