import Foundation
import Testing
@testable import Disciplina

@Suite @MainActor
struct RecurrenceTests {
    private let calendar = LocalDay.calendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func fixture() -> (MemoryRepository, TodoItem) {
        let repo = MemoryRepository()
        let now = date("2026-10-23T10:00:00Z") // Friday
        let item = TodoItem(id: UUID(), title: "Practice", createdAt: now, updatedAt: now, completedAt: nil)
        repo.items = [item]; return (repo, item)
    }
    @Test func completionLateReturnAndHistoricalReopen() throws {
        let (repo, item) = fixture()
        var now = item.createdAt
        let timer = TimerCoordinator(repository: repo, sample: { TimeSample(awake: 0, continuous: 0, date: now) }, calendar: { calendar })
        try timer.setRepeat(taskID: item.id, weekdays: Array(2...6))
        now = date("2026-11-02T10:00:00Z")
        try timer.reconcileRecurrence()
        #expect(repo.items.count == 1) // incomplete tasks never generate a backlog
        try timer.setStatus(id: item.id, status: .completed)
        let next = try #require(repo.series.first?.pendingTaskID)
        let scheduled = repo.series[0].pendingDay
        let writes = repo.writes
        try timer.setStatus(id: item.id, status: .completed)
        try timer.reconcileRecurrence()
        #expect(repo.writes == writes)
        now = date("2026-12-10T10:00:00Z")
        try timer.reconcileRecurrence(); try timer.reconcileRecurrence()
        #expect(repo.items.count == 2)
        #expect(repo.items[1].id == next && repo.items[1].createdAt == now)
        #expect(repo.items[1].scheduledDay == scheduled && repo.items[1].status == .todo)
        #expect(repo.sessions.isEmpty)
        try timer.setStatus(id: item.id, status: .todo)
        #expect(repo.items[0].seriesID == nil)
        #expect(repo.series[0].currentTaskID == next)
        try repo.snapshot().validate()
    }
    @Test func cancelPendingRenameAndChangeSchedule() throws {
        let (repo, item) = fixture()
        var now = item.createdAt
        let timer = TimerCoordinator(repository: repo, sample: { TimeSample(awake: 0, continuous: 0, date: now) }, calendar: { calendar })
        try timer.setRepeat(taskID: item.id, weekdays: Array(1...7))
        try timer.setStatus(id: item.id, status: .completed)
        try timer.setStatus(id: item.id, status: .todo)
        #expect(repo.series[0].pendingTaskID == nil)
        try TaskService(repository: repo).rename(id: item.id, title: "Renamed")
        #expect(repo.series[0].title == "Renamed")
        try timer.setStatus(id: item.id, status: .completed)
        try timer.changeSeries(id: repo.series[0].id, weekdays: [2])
        #expect(repo.series[0].pendingDay == LocalDay(date("2026-10-26T10:00:00Z"), calendar: calendar))
        now = date("2026-10-24T10:00:00Z")
        try timer.changeSeries(id: repo.series[0].id, weekdays: Array(1...7))
        #expect(repo.items.count == 2 && repo.items[1].title == "Renamed")
        try TaskService(repository: repo).rename(id: repo.items[1].id, title: "Future")
        #expect(repo.items[0].title == "Renamed" && repo.series[0].title == "Future")
        try timer.changeSeries(id: repo.series[0].id, weekdays: nil)
        #expect(!repo.series[0].enabled && repo.items.count == 2)
    }
    @Test func timerCompletionAndMaterializationRollback() throws {
        let (repo, item) = fixture()
        var now = item.createdAt
        var seconds = 0.0
        let timer = TimerCoordinator(repository: repo, sample: { TimeSample(awake: seconds, continuous: seconds, date: now) }, calendar: { calendar })
        try timer.setRepeat(taskID: item.id, weekdays: [2, 4, 6])
        try timer.start(taskID: item.id)
        seconds = 3
        let original = try repo.snapshot()
        repo.failWrite = true
        #expect(throws: (any Error).self) { try timer.setStatus(id: item.id, status: .completed) }
        #expect(try repo.snapshot() == original && timer.running != nil)
        repo.failWrite = false
        try timer.setStatus(id: item.id, status: .completed)
        #expect(repo.sessions[0].endReason == .completed && repo.sessions[0].accumulatedMilliseconds == 3000)
        let pending = try repo.snapshot()
        now = date("2026-10-30T10:00:00Z")
        repo.failWrite = true
        #expect(throws: (any Error).self) { try timer.reconcileRecurrence() }
        #expect(try repo.snapshot() == pending)
        repo.failWrite = false
        let restarted = TimerCoordinator(repository: repo, sample: { TimeSample(awake: 0, continuous: 0, date: now) }, calendar: { calendar })
        try restarted.recover(); try restarted.reconcileRecurrence(); try restarted.reconcileRecurrence()
        #expect(repo.items.count == 2 && repo.items[1].id == pending.series[0].pendingTaskID)
    }
    @Test func skipUndoAndIndependentRecovery() throws {
        let (repo, item) = fixture()
        var now = item.createdAt
        let timer = TimerCoordinator(repository: repo, sample: { TimeSample(awake: 0, continuous: 0, date: now) }, calendar: { calendar })
        let store = TaskStore(service: TaskService(repository: repo), timer: timer)
        #expect(store.setRepeat(item.id, weekdays: Array(1...7)))
        #expect(store.delete(id: item.id, disposition: .skip))
        #expect(repo.series[0].pendingTaskID != nil)
        store.undoDelete()
        #expect(repo.items[0].deletedAt == nil && repo.series[0].pendingTaskID == nil)
        #expect(store.delete(id: item.id, disposition: .stop))
        #expect(!repo.series[0].enabled)
        store.undoDelete()
        #expect(repo.series[0].enabled)
        #expect(store.delete(id: item.id, disposition: .skip))
        now = date("2026-10-30T10:00:00Z")
        store.calendarChanged(now: now, calendar: calendar)
        store.undoDelete()
        #expect(repo.items.count == 2 && repo.items[0].seriesID == nil)
        #expect(store.notice?.contains("independently") == true)
        let current = repo.items[1].id
        #expect(store.delete(id: current, disposition: .skip))
        #expect(store.restore(current))
        #expect(repo.items[1].seriesID == nil && repo.series[0].pendingTaskID != nil)
        try repo.snapshot().validate()
    }
    @Test func interveningSeriesChangePreventsUndoRevertingSchedule() throws {
        let (repo, item) = fixture()
        let timer = TimerCoordinator(repository: repo, sample: { TimeSample(awake: 0, continuous: 0, date: item.createdAt) }, calendar: { calendar })
        let store = TaskStore(service: TaskService(repository: repo), timer: timer)
        #expect(store.setRepeat(item.id, weekdays: [2]))
        #expect(store.delete(id: item.id, disposition: .skip))
        #expect(store.changeSeries(repo.series[0].id, weekdays: [4]))
        store.undoDelete()
        #expect(repo.items[0].seriesID == nil && repo.series[0].weekdays == [4])
    }
    @Test func backupCompatibilityAndInvalidReferences() throws {
        let (repo, item) = fixture()
        let timer = TimerCoordinator(repository: repo, sample: { TimeSample(awake: 0, continuous: 0, date: item.createdAt) })
        try timer.setRepeat(taskID: item.id, weekdays: [2, 6])
        try timer.setStatus(id: item.id, status: .completed)
        let snapshot = try repo.snapshot()
        let data = try BackupDocument(snapshot: snapshot).encode()
        #expect(try BackupDocument.decode(data).validatedSnapshot() == snapshot)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for version in [1, 2] {
            json["formatVersion"] = version; json.removeValue(forKey: "series")
            let legacy = try BackupDocument.decode(JSONSerialization.data(withJSONObject: json)).validatedSnapshot()
            #expect(legacy.series.isEmpty && legacy.tasks[0].seriesID == nil)
        }
        var invalid = snapshot
        invalid.series[0].pendingTaskID = item.id
        #expect(throws: (any Error).self) { try invalid.validate() }
        invalid = snapshot; invalid.series[0].weekdays = []
        #expect(throws: (any Error).self) { try invalid.validate() }
        invalid = snapshot; invalid.tasks[0].seriesID = UUID()
        #expect(throws: (any Error).self) { try invalid.validate() }
        invalid = snapshot; invalid.series.append(invalid.series[0])
        #expect(throws: (any Error).self) { try invalid.validate() }
    }
    @Test func committedCompletionRefreshFailureDoesNotReschedule() throws {
        let (repo, item) = fixture()
        let timer = TimerCoordinator(repository: repo, sample: { TimeSample(awake: 0, continuous: 0, date: item.createdAt) })
        let store = TaskStore(service: TaskService(repository: repo), timer: timer)
        #expect(store.setRepeat(item.id, weekdays: Array(1...7)))
        repo.failFetchAfterWrite = true
        #expect(store.setCompleted(id: item.id, isCompleted: true))
        let reserved = repo.series[0].pendingTaskID
        #expect(store.unavailable)
        #expect(!store.setCompleted(id: item.id, isCompleted: true))
        repo.failFetch = false; repo.failFetchAfterWrite = false
        store.reload()
        #expect(!store.unavailable && repo.series[0].pendingTaskID == reserved && repo.items.count == 1)
    }

    @Test func dayGroupingDSTMidnightTimezoneAndYear() throws {
        let now = date("2026-10-25T23:30:00Z") // DST has ended; Monday local midnight passed
        let yesterday = date("2026-10-25T00:30:00Z")
        let old = date("2025-12-31T12:00:00Z")
        let tasks = [now, yesterday, old].map { TodoItem(id: UUID(), title: "Day", createdAt: $0, updatedAt: now, completedAt: nil) }
        let groups = TaskDayGroup.make(inProgress: [], todo: tasks, completed: [], now: now, calendar: calendar)
        #expect(groups.map(\.title).prefix(2) == ["Today", "Yesterday"])
        #expect(groups[2].title.contains("2025"))
        var changed = tasks[1]; changed.status = .completed; changed.completedAt = now
        let regrouped = TaskDayGroup.make(inProgress: [], todo: [tasks[0], tasks[2]], completed: [changed], now: now, calendar: calendar)
        #expect(regrouped[1].id == groups[1].id)
        let utc = LocalDay.calendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(TaskDayGroup.make(inProgress: [], todo: tasks, completed: [], now: now, calendar: utc).count == 2)
        let friday = LocalDay(date("2026-10-23T10:00:00Z"), calendar: calendar)
        #expect(try friday.next(weekdays: Array(2...6), calendar: calendar) == groups[0].id)
        let dec31 = LocalDay(old, calendar: calendar)
        #expect(try dec31.next(weekdays: Array(1...7), calendar: calendar).year == 2026)
    }
}
