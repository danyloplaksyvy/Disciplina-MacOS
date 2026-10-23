import Foundation
import Testing
@testable import Disciplina

@Suite @MainActor struct ActivityTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func fixture(_ start: String = "2026-10-23T21:59:58Z") throws -> (MemoryRepository, FakeTime, TimerCoordinator, UUID) {
        let repo = MemoryRepository(), clock = FakeTime(); clock.date = date(start)
        try TaskService(repository: repo, now: { clock.date }).create(title: "Work")
        let timer = TimerCoordinator(repository: repo, sample: clock.sample, calendar: { LocalDay.calendar(timeZone: TimeZone(identifier: "Europe/Berlin")!) })
        return (repo, clock, timer, repo.items[0].id)
    }
    @Test func midnightCheckpointIsAtomicAndConservesMilliseconds() throws {
        let (repo, clock, timer, id) = try fixture()
        try timer.start(taskID: id); clock.advance(5); timer.tick()
        let session = repo.sessions[0], allocations = try #require(session.allocations)
        #expect(allocations.map(\.milliseconds) == [2000, 3000])
        #expect(allocations.map { $0.day.day } == [23, 24])
        try session.validateAllocation()
        let before = try repo.snapshot(); repo.failWrite = true
        clock.advance(5); timer.tick()
        #expect(try repo.snapshot() == before)
        #expect(timer.elapsedMilliseconds == 5000 && timer.failure != nil)
        repo.failWrite = false; try timer.recover()
        #expect(repo.sessions[0].endReason == .interrupted)
        #expect(repo.sessions[0].allocations == allocations)
    }
    @Test func dstAndYearBoundariesUseCalendarDays() throws {
        let cal = LocalDay.calendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        for start in ["2026-03-28T23:00:00Z", "2026-10-24T22:00:00Z", "2026-12-31T23:00:00Z"] {
            let begin = date(start), day = cal.dateInterval(of: .day, for: begin)!
            let duration = Int64(day.duration * 1000) + 123
            var session = WorkSession(id: UUID(), taskID: UUID(), startedAt: begin, accumulatedMilliseconds: duration, allocations: [])
            try session.allocate(milliseconds: duration, from: begin, calendar: cal, makeID: UUID.init)
            #expect(session.allocations?.count == 2)
            #expect(session.allocations?.last?.milliseconds == 123)
            try session.validateAllocation()
        }
    }
    @Test func dailyCorrectionPreservesIdentityAndOtherDates() throws {
        let (repo, clock, timer, id) = try fixture()
        try timer.start(taskID: id); clock.advance(5); try timer.pause()
        let before = repo.sessions[0], values = try #require(before.allocations)
        #expect(throws: SessionEditError.self) { try timer.editSession(taskID: id, sessionID: before.id, milliseconds: 10) }
        try timer.editDailySession(taskID: id, sessionID: before.id, amounts: [values[0].id: 0, values[1].id: 1234])
        let after = repo.sessions[0]
        #expect(after.accumulatedMilliseconds == 1234 && after.id == before.id && after.startedAt == before.startedAt)
        #expect(after.allocations?.map(\.day) == values.map(\.day))
        #expect(after.allocations?.allSatisfy { $0.provenance == .corrected } == true)
        let edited = try repo.snapshot(); repo.failWrite = true
        #expect(throws: (any Error).self) { try timer.editDailySession(taskID: id, sessionID: before.id, amounts: [values[0].id: 9, values[1].id: 99]) }
        #expect(try repo.snapshot() == edited)
    }
    @Test func travelInterruptsUncertainIntervalAndKeepsRecordedDay() throws {
        let repo = MemoryRepository(), clock = FakeTime()
        clock.date = date("2026-10-23T22:00:00Z")
        try TaskService(repository: repo).create(title: "Travel")
        var cal = LocalDay.calendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let timer = TimerCoordinator(repository: repo, sample: clock.sample, calendar: { cal })
        try timer.start(taskID: repo.items[0].id); clock.advance(5); timer.tick()
        let values = repo.sessions[0].allocations
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        timer.timeEnvironmentChanged()
        #expect(repo.sessions[0].allocations == values && timer.running == nil)
        let summary = ActivitySummary(sessions: repo.sessions, legacyCalendar: cal)
        #expect(summary.days.keys.first?.day == 24)
    }
    @Test func manualLegacyAndBackupCompatibility() throws {
        let (repo, _, timer, id) = try fixture()
        try timer.addSession(taskID: id, date: date("2026-10-01T10:00:00Z"), milliseconds: 1234)
        #expect(repo.sessions[0].allocations?.first?.provenance == .manual)
        let snapshot = try repo.snapshot()
        let document = try BackupDocument.decode(BackupDocument(snapshot: snapshot).encode())
        #expect(document.formatVersion == 5)
        #expect(try document.validatedSnapshot() == snapshot)
        let old = try document.encode()
        var json = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any]); json["formatVersion"] = 4
        let imported = try BackupDocument.decode(JSONSerialization.data(withJSONObject: json)).validatedSnapshot()
        #expect(imported.sessions[0].allocations == nil)
        var invalid = snapshot; invalid.sessions[0].allocations![0].milliseconds += 1
        #expect(throws: DataError.self) { try invalid.validate() }
    }
    @Test func appearanceRecurrenceAndUndoFeedback() throws {
        let (repo, _, timer, id) = try fixture()
        try timer.setRepeat(taskID: id, weekdays: Array(1...7))
        let appearance = TaskAppearance(symbol: "book", tint: "Blue")
        try timer.setAppearance(taskID: id, appearance: appearance)
        #expect(repo.items[0].appearance == appearance && repo.series[0].futureAppearance == appearance)
        let store = TaskStore(service: TaskService(repository: repo), timer: timer)
        #expect(store.delete(id: id))
        let feedback = store.deletionFeedback
        #expect(feedback?.contains("Work") == true && store.undoActionName == "Undo Delete Task")
        store.notice = "Timer paused."
        #expect(store.deletionFeedback == feedback)
        store.deletionFeedback = nil
        #expect(store.canUndoDeletion)
        store.undoDelete()
        #expect(store.deletionFeedback?.contains("Restored") == true)
        #expect(repo.items[0].appearance == appearance)
    }
}
