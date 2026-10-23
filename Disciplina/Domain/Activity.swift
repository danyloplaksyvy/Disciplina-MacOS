import Foundation

enum ActivityProvenance: String, Codable, Sendable { case measured, manual, corrected }
struct DailyAllocation: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let sessionID: UUID
    let day: LocalDay
    let timeZoneID: String
    var milliseconds: Int64
    var provenance: ActivityProvenance
}

struct TaskAppearance: Codable, Equatable, Sendable {
    var symbol: String?
    var tint: String?
    static let symbols = ["book", "briefcase", "house", "heart", "figure.walk", "bicycle", "graduationcap", "paintbrush", "music.note", "leaf", "wrench.and.screwdriver", "cup.and.saucer"]
    static let tints = ["Burgundy", "Blue", "Teal", "Green", "Orange", "Purple"]
    var normalized: Self { Self(symbol: symbol.flatMap { Self.symbols.contains($0) ? $0 : nil }, tint: tint.flatMap { Self.tints.contains($0) ? $0 : nil }) }
}

extension WorkSession {
    func validateAllocation() throws {
        guard let allocations else { return }
        var keys = Set<String>(), ids = Set<UUID>(), sum: Int64 = 0
        for value in allocations {
            guard value.sessionID == id, value.milliseconds >= 0,
                  TimeZone(identifier: value.timeZoneID) != nil, ids.insert(value.id).inserted,
                  keys.insert("\(value.day.year)-\(value.day.month)-\(value.day.day):\(value.timeZoneID)").inserted else { throw DataError.invalidSnapshot }
            _ = try value.day.date()
            let next = sum.addingReportingOverflow(value.milliseconds)
            guard !next.overflow else { throw DataError.invalidSnapshot }; sum = next.partialValue
        }
        guard sum == accumulatedMilliseconds else { throw DataError.invalidSnapshot }
    }
    mutating func allocate(milliseconds: Int64, from start: Date, calendar: Calendar, makeID: () -> UUID) throws {
        guard milliseconds >= 0, allocations != nil else { throw DataError.invalidSnapshot }
        var remaining = milliseconds, cursor = start
        while remaining > 0 {
            guard let interval = calendar.dateInterval(of: .day, for: cursor) else { throw DataError.invalidSnapshot }
            let untilBoundary = max(1, Int64((interval.end.timeIntervalSince(cursor) * 1000).rounded(.up)))
            let part = min(remaining, untilBoundary)
            let day = LocalDay(cursor, calendar: calendar), zone = calendar.timeZone.identifier
            if let i = allocations!.firstIndex(where: { $0.day == day && $0.timeZoneID == zone }) {
                let sum = allocations![i].milliseconds.addingReportingOverflow(part)
                guard !sum.overflow else { throw DataError.invalidSnapshot }
                allocations![i].milliseconds = sum.partialValue
            } else {
                allocations!.append(DailyAllocation(id: makeID(), sessionID: id, day: day, timeZoneID: zone, milliseconds: part, provenance: .measured))
            }
            remaining -= part
            cursor = remaining > 0 ? interval.end : cursor.addingTimeInterval(Double(part) / 1000)
        }
    }
}

struct ActivitySummary {
    struct Entry: Identifiable {
        let id: UUID
        let sessionID: UUID
        let taskID: UUID
        let goalID: UUID?
        let startedAt: Date
        let milliseconds: Int64
        let provenance: ActivityProvenance?
        let legacy: Bool
    }
    private(set) var days: [LocalDay: [Entry]] = [:]
    init(sessions: [WorkSession] = [], legacyCalendar: Calendar = LocalDay.calendar()) {
        for session in sessions {
            if let allocations = session.allocations {
                for value in allocations {
                    days[value.day, default: []].append(Entry(id: value.id, sessionID: session.id, taskID: session.taskID, goalID: session.goalIDAtStart, startedAt: session.startedAt, milliseconds: value.milliseconds, provenance: value.provenance, legacy: false))
                }
            } else {
                let day = session.legacyDay ?? LocalDay(session.startedAt, calendar: legacyCalendar)
                days[day, default: []].append(Entry(id: session.id, sessionID: session.id, taskID: session.taskID, goalID: session.goalIDAtStart, startedAt: session.startedAt, milliseconds: session.accumulatedMilliseconds, provenance: session.origin == .manual ? .manual : nil, legacy: session.origin != .manual))
            }
        }
        for day in Array(days.keys) { days[day]!.sort { $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt } }
    }
}
