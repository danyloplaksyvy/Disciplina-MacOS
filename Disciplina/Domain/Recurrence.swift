import Foundation

/// A Gregorian calendar date, deliberately independent of an absolute time or time zone.
struct LocalDay: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = timeZone; return value
    }
    init(_ date: Date, calendar: Calendar = Self.calendar()) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year!; month = parts.month!; day = parts.day!
    }
    func date(calendar: Calendar = Self.calendar()) throws -> Date {
        guard (1...9999).contains(year), let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              Self(date, calendar: calendar) == self else { throw DataError.invalidSnapshot }
        return date
    }
    func next(weekdays: [Int], calendar: Calendar = Self.calendar()) throws -> LocalDay {
        guard !weekdays.isEmpty, weekdays.allSatisfy({ (1...7).contains($0) }) else { throw DataError.invalidSnapshot }
        var date = try date(calendar: calendar)
        for _ in 0..<7 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { throw DataError.invalidSnapshot }
            date = next
            if weekdays.contains(calendar.component(.weekday, from: date)) { return Self(date, calendar: calendar) }
        }
        throw DataError.invalidSnapshot
    }
    var formatted: String { (try? date().formatted(date: .abbreviated, time: .omitted)) ?? "Invalid date" }
}

struct RecurrenceSeries: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var weekdays: [Int]
    var enabled = true
    var currentTaskID: UUID?
    var pendingTaskID: UUID?
    var pendingDay: LocalDay?
    var lastTriggerDay: LocalDay?
    var revision: UUID = UUID()
    var scheduleDescription: String {
        if weekdays.sorted() == Array(1...7) { return "Every day" }
        if weekdays.sorted() == Array(2...6) { return "Weekdays" }
        let names = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().filter { (1...7).contains($0) }.map { names[$0 - 1] }.joined(separator: ", ")
    }
}

enum RecurringDeletion { case skip, stop }

extension TaskSnapshot {
    @MainActor func validateRecurrence() throws {
        guard Set(series.map(\.id)).count == series.count else { throw DataError.invalidSnapshot }
        let seriesByID = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var reserved = Set<UUID>()
        for task in tasks {
            if let id = task.seriesID {
                guard let linked = seriesByID[id] else { throw DataError.invalidSnapshot }
                if linked.enabled && !task.isCompleted && task.deletedAt == nil && linked.currentTaskID != task.id {
                    throw DataError.invalidSnapshot
                }
            }
            if let day = task.scheduledDay { _ = try day.date() }
        }
        for value in series {
            _ = try TaskService.validatedTitle(value.title)
            guard !value.weekdays.isEmpty, Set(value.weekdays).count == value.weekdays.count,
                  value.weekdays.allSatisfy({ (1...7).contains($0) }),
                  (value.pendingTaskID == nil) == (value.pendingDay == nil) else { throw DataError.invalidSnapshot }
            if let id = value.currentTaskID {
                guard let task = tasksByID[id], task.seriesID == value.id else { throw DataError.invalidSnapshot }
            }
            if let trigger = value.lastTriggerDay { _ = try trigger.date() }
            if let day = value.pendingDay, let id = value.pendingTaskID {
                _ = try day.date()
                guard value.enabled, let trigger = value.lastTriggerDay, day > trigger,
                      try trigger.next(weekdays: value.weekdays) == day,
                      tasksByID[id] == nil, reserved.insert(id).inserted else { throw DataError.invalidSnapshot }
                if let current = value.currentTaskID.flatMap({ tasksByID[$0] }), !current.isCompleted && current.deletedAt == nil {
                    throw DataError.invalidSnapshot
                }
            } else if value.enabled {
                guard let id = value.currentTaskID, let current = tasksByID[id], !current.isCompleted, current.deletedAt == nil else { throw DataError.invalidSnapshot }
            }
        }
    }

    mutating func stopSeries(at index: Int, revision: UUID) {
        series[index].enabled = false; series[index].pendingTaskID = nil
        series[index].pendingDay = nil; series[index].revision = revision
    }

    mutating func schedule(seriesIndex: Int, after day: LocalDay, calendar: Calendar, makeID: () -> UUID) throws {
        series[seriesIndex].lastTriggerDay = day
        series[seriesIndex].pendingDay = try day.next(weekdays: series[seriesIndex].weekdays, calendar: calendar)
        series[seriesIndex].pendingTaskID = makeID()
        series[seriesIndex].revision = makeID()
    }

    mutating func recurrenceStatusChanged(taskIndex: Int, status: TaskStatus, now: Date, calendar: Calendar, makeID: () -> UUID) throws {
        guard let id = tasks[taskIndex].seriesID, let index = series.firstIndex(where: { $0.id == id }) else { return }
        if series[index].currentTaskID != tasks[taskIndex].id || !series[index].enabled {
            if status != .completed { detachTask(at: taskIndex) }
            return
        }
        if status == .completed {
            try schedule(seriesIndex: index, after: LocalDay(now, calendar: calendar), calendar: calendar, makeID: makeID)
        } else {
            series[index].pendingDay = nil; series[index].pendingTaskID = nil
            series[index].lastTriggerDay = nil; series[index].revision = makeID()
        }
    }

    mutating func detachTask(at index: Int) {
        if let id = tasks[index].seriesID, let s = series.firstIndex(where: { $0.id == id && $0.currentTaskID == tasks[index].id }) {
            series[s].currentTaskID = nil
            if series[s].pendingTaskID == nil { series[s].enabled = false }
            series[s].revision = UUID()
        }
        tasks[index].seriesID = nil
    }

    mutating func materializeDue(now: Date, calendar: Calendar, makeID: () -> UUID) -> Bool {
        let today = LocalDay(now, calendar: calendar)
        var changed = false
        for index in series.indices {
            guard series[index].enabled, let day = series[index].pendingDay, day <= today,
                  let id = series[index].pendingTaskID else { continue }
            tasks.append(TodoItem(id: id, title: series[index].title, createdAt: now, updatedAt: now,
                                  completedAt: nil, seriesID: series[index].id, scheduledDay: day))
            series[index].currentTaskID = id
            series[index].pendingTaskID = nil; series[index].pendingDay = nil
            series[index].revision = makeID(); changed = true
        }
        return changed
    }
}
