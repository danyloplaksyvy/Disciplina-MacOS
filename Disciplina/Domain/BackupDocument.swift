import Foundation

struct BackupDocument: Codable {
    let formatVersion: Int
    let exportedAt: Date
    var tasks: [TodoItem]
    var sessions: [WorkSession]
    var goals: [Goal]
    var milestones: [Milestone]
    var series: [RecurrenceSeries]
    init(snapshot: TaskSnapshot, date: Date = Date()) {
        formatVersion = 4; goals = snapshot.goals; milestones = snapshot.milestones; series = snapshot.series; exportedAt = date; tasks = snapshot.tasks; sessions = snapshot.sessions
    }
    @MainActor func validatedSnapshot() throws -> TaskSnapshot {
        guard (1...4).contains(formatVersion) else { throw DataError.unsupportedVersion }
        var snapshot = TaskSnapshot(tasks: tasks, sessions: sessions, series: formatVersion >= 3 ? series : [], goals: formatVersion >= 4 ? goals : [], milestones: formatVersion >= 4 ? milestones : [])
        if formatVersion < 3 { for i in snapshot.tasks.indices { snapshot.tasks[i].seriesID = nil; snapshot.tasks[i].scheduledDay = nil } }
        if formatVersion < 4 {
            for i in snapshot.tasks.indices { snapshot.tasks[i].goalID = nil }
            for i in snapshot.sessions.indices { snapshot.sessions[i].goalIDAtStart = nil }
            for i in snapshot.series.indices { snapshot.series[i].futureGoalID = nil }
        }
        try snapshot.validate()
        return snapshot
    }
    enum CodingKeys: String, CodingKey { case formatVersion, exportedAt, tasks, sessions, series, goals, milestones }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        tasks = try values.decode([TodoItem].self, forKey: .tasks)
        sessions = try values.decode([WorkSession].self, forKey: .sessions)
        goals = formatVersion >= 4 ? try values.decode([Goal].self, forKey: .goals) : []
        milestones = formatVersion >= 4 ? try values.decode([Milestone].self, forKey: .milestones) : []
        series = formatVersion >= 3 ? try values.decode([RecurrenceSeries].self, forKey: .series) : []
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
