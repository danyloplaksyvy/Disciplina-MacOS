import Foundation

struct BackupDocument: Codable {
    let formatVersion: Int
    let exportedAt: Date
    var tasks: [TodoItem]
    var sessions: [WorkSession]
    var series: [RecurrenceSeries]
    init(snapshot: TaskSnapshot, date: Date = Date()) {
        formatVersion = 3; series = snapshot.series; exportedAt = date; tasks = snapshot.tasks; sessions = snapshot.sessions
    }
    @MainActor func validatedSnapshot() throws -> TaskSnapshot {
        guard (1...3).contains(formatVersion) else { throw DataError.unsupportedVersion }
        var snapshot = TaskSnapshot(tasks: tasks, sessions: sessions, series: formatVersion == 3 ? series : [])
        if formatVersion < 3 { for i in snapshot.tasks.indices { snapshot.tasks[i].seriesID = nil; snapshot.tasks[i].scheduledDay = nil } }
        try snapshot.validate()
        return snapshot
    }
    enum CodingKeys: String, CodingKey { case formatVersion, exportedAt, tasks, sessions, series }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        tasks = try values.decode([TodoItem].self, forKey: .tasks)
        sessions = try values.decode([WorkSession].self, forKey: .sessions)
        series = try values.decodeIfPresent([RecurrenceSeries].self, forKey: .series) ?? []
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
