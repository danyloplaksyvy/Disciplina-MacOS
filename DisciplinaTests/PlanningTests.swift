import Foundation
import Testing
@testable import Disciplina

@Suite @MainActor struct PlanningTests {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    var day: LocalDay { LocalDay(date) }
    func task(_ title: String) -> TodoItem {
        TodoItem(id: UUID(), title: title, createdAt: date, updatedAt: date, completedAt: nil)
    }
    @Test func assignmentOrderingAndRemovalPreserveTaskHistory() throws {
        let repo = MemoryRepository(); repo.items = [task("A"), task("B"), task("C")]
        let original = repo.items; let service = PlanningService(repository: repo)
        for item in original { try service.assign(item.id, day: day) }
        try service.assign(original[0].id, day: day)
        #expect(DailyPlan(tasks: repo.items, day: day).today.map(\.id) == original.map(\.id))
        try service.reorder(day: day, ids: original.reversed().map(\.id))
        #expect(DailyPlan(tasks: repo.items, day: day).today.map(\.id) == original.reversed().map(\.id))
        try service.assign(original[1].id, day: nil)
        #expect(repo.items[1].plannedDay == nil && repo.items[1].planOrder == nil)
        #expect(repo.items.map(\.updatedAt) == original.map(\.updatedAt))
        #expect(repo.items.map(\.createdAt) == original.map(\.createdAt))
        #expect(repo.items.map(\.status) == original.map(\.status))
        #expect(Set(repo.items.compactMap(\.planOrder)) == [0, 1])
    }
    @Test func createIsAtomicAndCaptureRemainsUnplanned() throws {
        let repo = MemoryRepository()
        let creator = TaskService(repository: repo, now: { date })
        repo.failWrite = true
        #expect(throws: (any Error).self) { try creator.create(title: "Planned", plannedDay: day) }
        #expect(repo.items.isEmpty)
        repo.failWrite = false
        try creator.create(title: "Planned", plannedDay: day); try creator.create(title: "Capture")
        #expect(repo.items[0].plannedDay == day && repo.items[0].planOrder == 0)
        #expect(repo.items[1].plannedDay == nil)
    }
    @Test func completionDeletionAndUndoPreservePlan() throws {
        let repo = MemoryRepository(); let store = TaskStore(service: TaskService(repository: repo))
        store.calendarChanged(now: date)
        #expect(store.createForToday(title: "Work"))
        let id = try #require(store.items.first?.id)
        #expect(store.setCompleted(id: id, isCompleted: true))
        #expect(store.dailyPlan.today.isEmpty && store.dailyPlan.completed.map(\.id) == [id])
        #expect(store.setCompleted(id: id, isCompleted: false))
        #expect(store.dailyPlan.today.map(\.id) == [id])
        #expect(store.delete(id: id)); #expect(store.dailyPlan.today.isEmpty)
        store.undoDelete(); #expect(store.dailyPlan.today.map(\.id) == [id])
        #expect(store.items.first?.plannedDay == day)
    }
    @Test func failuresKeepCommittedPlanAndRefreshRecoveryDoesNotRepeatMutation() throws {
        let repo = MemoryRepository(); let store = TaskStore(service: TaskService(repository: repo))
        store.calendarChanged(now: date); #expect(store.create(title: "Work"))
        let id = try #require(store.items.first?.id)
        repo.failWrite = true; #expect(!store.planToday(id)); #expect(store.dailyPlan.today.isEmpty)
        repo.failWrite = false; repo.failFetchAfterWrite = true
        #expect(store.planToday(id)); #expect(store.unavailable)
        repo.failFetch = false; repo.failFetchAfterWrite = false
        store.reload(); store.calendarChanged(now: date)
        #expect(store.dailyPlan.today.map(\.id) == [id]); #expect(repo.items.count == 1)
        repo.failWrite = true; #expect(!store.removeFromPlan(id)); #expect(store.dailyPlan.today.count == 1)
    }
    @Test func dayChangesUseCalendarDatesAndNeverRewriteAssignments() throws {
        var calendar = LocalDay.calendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let before = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0))!
        let repo = MemoryRepository(); let store = TaskStore(service: TaskService(repository: repo))
        store.calendarChanged(now: before, calendar: calendar); #expect(store.createForToday(title: "Work"))
        let saved = repo.items[0]
        store.calendarChanged(now: calendar.date(byAdding: .day, value: 1, to: before)!, calendar: calendar)
        #expect(store.dailyPlan.today.isEmpty); #expect(store.dailyPlan.earlier.first?.tasks == [saved])
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        store.calendarChanged(now: before, calendar: calendar)
        #expect(repo.items[0] == saved)
        let restarted = TaskStore(service: TaskService(repository: repo))
        #expect(restarted.items[0] == saved)
    }
    @Test func recurrenceMaterializesOnePlannedSuccessorOnLateReturn() throws {
        let repo = MemoryRepository(); repo.items = [task("Routine")]
        var state = try repo.snapshot()
        let seriesID = UUID(), nextID = UUID()
        state.tasks[0].status = .completed; state.tasks[0].completedAt = date; state.tasks[0].seriesID = seriesID
        let due = LocalDay(date.addingTimeInterval(86400))
        state.series = [RecurrenceSeries(id: seriesID, title: "Routine", weekdays: [1,2,3,4,5,6,7], currentTaskID: state.tasks[0].id, pendingTaskID: nextID, pendingDay: due, lastTriggerDay: day)]
        let late = date.addingTimeInterval(86400 * 5)
        let first = state.materializeDue(now: late, calendar: LocalDay.calendar(), makeID: UUID.init)
        let again = state.materializeDue(now: late, calendar: LocalDay.calendar(), makeID: UUID.init)
        #expect(first && !again)
        try state.validate()
        let next = try #require(state.tasks.first { $0.id == nextID })
        #expect(next.plannedDay == LocalDay(late) && next.scheduledDay == due && next.planOrder == 0)
        #expect(state.tasks[0].plannedDay == nil)
    }
    @Test func planDoesNotPauseOrModifyAnActiveTimer() throws {
        let repo = MemoryRepository(); let store = TaskStore(service: TaskService(repository: repo))
        #expect(store.create(title: "Timed")); let id = try #require(store.items.first?.id)
        #expect(store.start(id)); let sessions = repo.sessions
        #expect(store.planToday(id)); #expect(repo.sessions == sessions && store.timer.running?.taskID == id)
        #expect(store.removeFromPlan(id)); #expect(repo.sessions == sessions && store.timer.running?.taskID == id)
    }
    @Test func formatSixRoundTripAndLegacyDefaults() throws {
        var state = TaskSnapshot(tasks: [task("A")]); state.appendToPlan(id: state.tasks[0].id, day: day)
        let bytes = try BackupDocument(snapshot: state).encode()
        #expect(try BackupDocument.decode(bytes).validatedSnapshot() == state)
        for format in 1...5 {
            var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any]); json["formatVersion"] = format
            let legacy = try BackupDocument.decode(JSONSerialization.data(withJSONObject: json)).validatedSnapshot()
            #expect(legacy.tasks[0].plannedDay == nil && legacy.tasks[0].planOrder == nil)
        }
    }
    @Test func rejectsMalformedPlanningAndStaleReorders() throws {
        var state = TaskSnapshot(tasks: [task("A")]); state.tasks[0].plannedDay = day
        #expect(throws: (any Error).self) { try state.validate() }
        for order: Int64 in [-1, Int64.max] {
            state.tasks[0].planOrder = order
            #expect(throws: (any Error).self) { try state.validate() }
        }
        state.tasks[0].planOrder = 0
        state.tasks[0].plannedDay = try JSONDecoder().decode(LocalDay.self, from: Data("{\"year\":2026,\"month\":2,\"day\":30}".utf8))
        #expect(throws: (any Error).self) { try state.validate() }
        let repo = MemoryRepository(); repo.items = [task("A")]
        #expect(throws: (any Error).self) { try PlanningService(repository: repo).reorder(day: day, ids: [UUID()]) }
    }
    @Test func tenThousandTasksProjectWithoutDuplicates() {
        var tasks = (0..<10000).map { task("Task \($0)") }
        for i in tasks.indices { tasks[i].plannedDay = day; tasks[i].planOrder = Int64(i) }
        let plan = DailyPlan(tasks: tasks, day: day)
        #expect(plan.today.count == 10000 && Set(plan.today.map(\.id)).count == 10000)
        #expect(plan.today == tasks)
    }
}
