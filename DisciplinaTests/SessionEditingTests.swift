import Foundation
import Testing
@testable import Disciplina

@Suite @MainActor struct SessionEditingTests {
    @Test func durationValidation() throws {
        var value = SessionDuration()
        value.hours = "100"; value.minutes = "59"; value.seconds = "59"
        #expect(try value.milliseconds() == 363599000)
        for invalid in ["-1", "1.5", "", "999999999999999999999", " 1"] {
            value.hours = invalid
            #expect(throws: (any Error).self) { try value.milliseconds() }
        }
        value.hours = "2562047788015"; value.minutes = "59"; value.seconds = "59"
        #expect(throws: (any Error).self) { try value.milliseconds() }
        value.hours = "0"; value.minutes = "60"
        #expect(throws: (any Error).self) { try value.milliseconds() }
    }
    @Test func manualEditingPreservesStatusAndIdentity() throws {
        let (repo, clock, timer, a, _) = try TimerTests().fixture()
        try timer.setStatus(id: a, status: .completed)
        try timer.addSession(taskID: a, date: clock.date, milliseconds: 1500)
        let original = repo.sessions[0]
        #expect(original.origin == .manual)
        #expect(original.startedAt == original.endedAt)
        #expect(repo.items[0].status == .completed)
        let writes = repo.writes
        try timer.editSession(taskID: a, sessionID: original.id, milliseconds: 1500)
        #expect(repo.writes == writes)
        clock.advance(2)
        try timer.editSession(taskID: a, sessionID: original.id, milliseconds: 0)
        #expect(repo.sessions[0].id == original.id)
        #expect(repo.sessions[0].startedAt == original.startedAt)
        #expect(repo.sessions[0].endReason == original.endReason)
        #expect(repo.sessions[0].durationEditedAt == clock.date)
        try timer.deleteSession(taskID: a, sessionID: original.id)
        #expect(repo.sessions.isEmpty)
        #expect(repo.items[0].status == .completed)
    }
    @Test func editorPausesOnlyItsTaskAndDoesNotResume() throws {
        let (repo, clock, timer, a, b) = try TimerTests().fixture()
        let store = TaskStore(service: TaskService(repository: repo), timer: timer)
        #expect(store.start(a)); clock.advance(2)
        #expect(store.prepareSessionEditor(taskID: b))
        #expect(timer.running?.taskID == a)
        #expect(store.addSession(taskID: b, date: clock.date, milliseconds: 5000))
        #expect(timer.running?.taskID == a)
        #expect(store.prepareSessionEditor(taskID: a))
        #expect(timer.running == nil)
        #expect(store.total(a) == 2000)
        #expect(store.deletedIDs.isEmpty)
    }
    @Test func failedSessionWritesAreAtomicAndKeepTotals() throws {
        let (repo, clock, timer, a, _) = try TimerTests().fixture()
        let store = TaskStore(service: TaskService(repository: repo), timer: timer)
        #expect(store.addSession(taskID: a, date: clock.date, milliseconds: 2000))
        let id = repo.sessions[0].id
        let before = try repo.snapshot()
        repo.failWrite = true
        #expect(!store.editSession(taskID: a, sessionID: id, milliseconds: 1000))
        #expect(!store.deleteSession(taskID: a, sessionID: id))
        #expect(!store.addSession(taskID: a, date: clock.date, milliseconds: 500))
        #expect(try repo.snapshot() == before)
        #expect(store.total(a) == 2000)
    }
    @Test func pauseRefreshFailureDoesNotOpenEditorOrRepeatMutation() throws {
        let (repo, clock, timer, a, _) = try TimerTests().fixture()
        let store = TaskStore(service: TaskService(repository: repo), timer: timer)
        #expect(store.start(a)); clock.advance(2)
        repo.failFetchAfterWrite = true
        #expect(!store.prepareSessionEditor(taskID: a))
        #expect(timer.running == nil)
        #expect(store.unavailable)
        repo.failFetch = false; repo.failFetchAfterWrite = false
        store.reload()
        #expect(store.prepareSessionEditor(taskID: a))
        #expect(store.total(a) == 2000)
        #expect(repo.sessions.count == 1)
    }
    @Test func rejectsOverflowAndRunningSessionEdits() throws {
        let (repo, clock, timer, a, _) = try TimerTests().fixture()
        #expect(throws: (any Error).self) { try timer.addSession(taskID: a, date: clock.date, milliseconds: 0) }
        try timer.start(taskID: a)
        #expect(throws: (any Error).self) { try timer.editSession(taskID: a, sessionID: repo.sessions[0].id, milliseconds: 10) }
        try timer.pause()
        try timer.addSession(taskID: a, date: clock.date, milliseconds: Int64.max)
        #expect(throws: (any Error).self) { try timer.addSession(taskID: a, date: clock.date, milliseconds: 1) }
    }
    @Test func importsLegacyJSONAndRoundTripsProvenance() throws {
        let (repo, clock, timer, a, _) = try TimerTests().fixture()
        try timer.start(taskID: a); clock.advance(1); try timer.pause()
        let document = BackupDocument(snapshot: try repo.snapshot(), date: clock.date)
        var json = try #require(JSONSerialization.jsonObject(with: document.encode()) as? [String: Any])
        json["formatVersion"] = 1
        var sessions = try #require(json["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "origin"); sessions[0].removeValue(forKey: "durationEditedAt")
        json["sessions"] = sessions
        let old = try BackupDocument.decode(JSONSerialization.data(withJSONObject: json)).validatedSnapshot()
        #expect(old.sessions[0].origin == .timer)
        #expect(old.sessions[0].durationEditedAt == nil)
        try timer.addSession(taskID: a, date: clock.date, milliseconds: 1000)
        try timer.editSession(taskID: a, sessionID: repo.sessions[1].id, milliseconds: 2000)
        let current = try repo.snapshot()
        let decoded = try BackupDocument.decode(BackupDocument(snapshot: current).encode())
        #expect(decoded.formatVersion == 5)
        #expect(try decoded.validatedSnapshot() == current)
    }
    @Test func structureRevisionIgnoresTicksAndFailedMutations() throws {
        let (repo, clock, timer, a, _) = try TimerTests().fixture()
        let store = TaskStore(service: TaskService(repository: repo), timer: timer)
        #expect(store.start(a))
        let revision = store.structureRevision
        clock.advance(5); timer.tick()
        #expect(store.structureRevision == revision)
        repo.failWrite = true
        #expect(!store.delete(id: a))
        #expect(store.structureRevision == revision)
        repo.failWrite = false
        #expect(store.setCompleted(id: a, isCompleted: true))
        #expect(store.structureRevision == revision + 1)
    }
}
