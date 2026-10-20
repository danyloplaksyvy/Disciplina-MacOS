import Foundation
import Testing
@testable import Disciplina

@MainActor final class FakeTime {
    var awake: Double = 0
    var continuous: Double = 0
    var date = Date(timeIntervalSince1970: 100)
    func advance(_ seconds: Double) { awake += seconds; continuous += seconds; date += seconds }
    func sample() -> TimeSample { TimeSample(awake: awake, continuous: continuous, date: date) }
}

@Suite @MainActor struct TimerTests {
    func fixture() throws -> (MemoryRepository, FakeTime, TimerCoordinator, UUID, UUID) {
        let repository = MemoryRepository()
        let clock = FakeTime()
        let service = TaskService(repository: repository, now: { clock.date })
        try service.create(title: "A"); try service.create(title: "B")
        let timer = TimerCoordinator(repository: repository, sample: clock.sample)
        return (repository, clock, timer, repository.items[0].id, repository.items[1].id)
    }
    @Test func startPauseResumeSwitchComplete() throws {
        let (repo, clock, timer, a, b) = try fixture()
        try timer.start(taskID: a); try timer.start(taskID: a)
        #expect(repo.sessions.count == 1)
        clock.advance(2); try timer.pause(); try timer.pause()
        #expect(repo.sessions[0].accumulatedMilliseconds == 2000)
        try timer.start(taskID: a); clock.advance(3); try timer.start(taskID: b)
        #expect(repo.sessions.count == 3)
        #expect(repo.sessions[1].endReason == .switchedTask)
        #expect(repo.items[0].status == .inProgress)
        clock.advance(1); try timer.setStatus(id: b, status: .completed)
        #expect(timer.running == nil)
        #expect(repo.sessions[2].endReason == .completed)
        #expect(repo.sessions.reduce(0) { $0 + $1.accumulatedMilliseconds } == 6000)
        try timer.setStatus(id: b, status: .inProgress)
        #expect(timer.running == nil)
        #expect(repo.items[1].completedAt == nil)
    }
    @Test func failedHandoffIsAtomic() throws {
        let (repo, clock, timer, a, b) = try fixture()
        try timer.start(taskID: a); clock.advance(2)
        let before = try repo.snapshot(); repo.failWrite = true
        #expect(throws: (any Error).self) { try timer.start(taskID: b) }
        #expect(try repo.snapshot() == before)
        #expect(timer.running?.taskID == a)
        repo.failWrite = false; try timer.start(taskID: b)
        #expect(repo.sessions[0].accumulatedMilliseconds == 2000)
    }
    @Test func ticksCheckpointWithoutDoubleCounting() throws {
        let (repo, clock, timer, a, _) = try fixture()
        try timer.start(taskID: a)
        let writes = repo.writes
        clock.advance(1); timer.tick()
        #expect(repo.writes == writes)
        #expect(timer.elapsedMilliseconds == 1000)
        clock.advance(4); timer.tick(); timer.tick()
        #expect(repo.sessions[0].accumulatedMilliseconds == 5000)
        #expect(repo.writes == writes + 1)
        clock.advance(2); try timer.pause()
        #expect(repo.sessions[0].accumulatedMilliseconds == 7000)
    }
    @Test func wallClockChangesDoNotChangeDuration() throws {
        let (repo, clock, timer, a, _) = try fixture()
        try timer.start(taskID: a)
        clock.advance(5); clock.date += 36000; timer.tick()
        clock.advance(3); clock.date -= 72000; try timer.pause()
        #expect(repo.sessions[0].accumulatedMilliseconds == 8000)
        #expect(repo.sessions[0].endedAt! < repo.sessions[0].startedAt)
    }
    @Test func missedSleepAndWatchdogDiscardUntrustedTime() throws {
        for sleeping in [true, false] {
            let (repo, clock, timer, a, _) = try fixture()
            try timer.start(taskID: a); clock.advance(5); timer.tick()
            if sleeping { clock.continuous += 3600 } else { clock.advance(16) }
            timer.tick()
            #expect(timer.running == nil)
            #expect(repo.sessions[0].accumulatedMilliseconds == 5000)
            #expect(repo.sessions[0].endReason == .interrupted)
        }
    }
    @Test func failedCheckpointFreezesUntilRecovery() throws {
        let (repo, clock, timer, a, _) = try fixture()
        try timer.start(taskID: a); clock.advance(5); timer.tick()
        repo.failWrite = true; clock.advance(5); timer.tick()
        #expect(timer.failure != nil)
        #expect(timer.elapsedMilliseconds == 5000)
        clock.advance(100); timer.tick()
        #expect(timer.elapsedMilliseconds == 5000)
        #expect(throws: (any Error).self) { try timer.pause() }
        repo.failWrite = false; try timer.recover()
        #expect(timer.failure == nil)
        #expect(repo.sessions[0].accumulatedMilliseconds == 5000)
        #expect(repo.sessions[0].endReason == .interrupted)
    }
    @Test func restartDoesNotInventTime() throws {
        let (repo, clock, timer, a, _) = try fixture()
        try timer.start(taskID: a); clock.advance(5); timer.tick(); clock.advance(5000)
        let restarted = TimerCoordinator(repository: repo, sample: clock.sample)
        try restarted.recover()
        #expect(restarted.running == nil)
        #expect(repo.sessions[0].accumulatedMilliseconds == 5000)
        #expect(repo.sessions[0].endedAt == repo.sessions[0].lastCheckpointAt)
    }
    @Test func deleteUndoKeepsHistoryAndIdentity() throws {
        let (repo, clock, timer, a, _) = try fixture()
        let store = TaskStore(service: TaskService(repository: repo), timer: timer)
        #expect(store.start(a)); clock.advance(3)
        #expect(store.delete(id: a)); #expect(store.deleted.count == 1)
        #expect(repo.sessions[0].endReason == .deleted)
        store.undoDelete()
        #expect(store.items.first { $0.id == a }?.status == .inProgress)
        #expect(store.total(a) == 3000)
        #expect(timer.running == nil)
    }
    @Test func exportRoundTripAndValidation() throws {
        let (repo, clock, timer, a, _) = try fixture()
        try timer.start(taskID: a); clock.advance(5); timer.tick()
        let snapshot = try repo.snapshot()
        let document = try BackupDocument.decode(BackupDocument(snapshot: snapshot).encode())
        #expect(try document.validatedSnapshot() == snapshot)
        var duplicate = snapshot; duplicate.tasks.append(snapshot.tasks[0])
        #expect(throws: (any Error).self) { try duplicate.validate() }
        var negative = snapshot; negative.sessions[0].accumulatedMilliseconds = -1
        #expect(throws: (any Error).self) { try negative.validate() }
        var orphan = snapshot; orphan.tasks.removeAll()
        #expect(throws: (any Error).self) { try orphan.validate() }
    }
    @Test func sleepQuitAndResetPreserveHistory() throws {
        for reason in [SessionEndReason.systemSleep, .appQuit] {
            let (repo, clock, timer, a, _) = try fixture()
            try timer.start(taskID: a); clock.advance(2); try timer.pause(reason: reason)
            #expect(repo.sessions[0].endReason == reason)
            #expect(repo.sessions[0].accumulatedMilliseconds == 2000)
        }
        let (repo, clock, timer, a, _) = try fixture()
        try timer.start(taskID: a); clock.advance(3); try timer.setStatus(id: a, status: .todo)
        #expect(repo.sessions[0].endReason == .movedToTodo)
        #expect(repo.sessions[0].accumulatedMilliseconds == 3000)
        #expect(repo.items[0].status == .todo)
        #expect(timer.running == nil)
    }
    @Test func snapshotRejectsTwoTimersAndOverflow() throws {
        let (repo, _, timer, a, b) = try fixture()
        try timer.start(taskID: a)
        var state = try repo.snapshot()
        state.tasks[1].status = .inProgress
        state.sessions.append(WorkSession(id: UUID(), taskID: b, startedAt: Date(), lastCheckpointAt: Date()))
        #expect(throws: (any Error).self) { try state.validate() }
        state.closeInterrupted()
        state.sessions[0].accumulatedMilliseconds = Int64.max
        state.sessions.append(WorkSession(id: UUID(), taskID: a, startedAt: Date(), endedAt: Date(),
                                          accumulatedMilliseconds: 1, lastCheckpointAt: Date(), endReason: .paused))
        #expect(throws: (any Error).self) { try state.validate() }
        #expect(throws: (any Error).self) { _ = try BackupDocument.decode(Data("{}".utf8)) }
    }

    @Test func expandedHours() {
        #expect(DurationText.precise(360000000) == "100:00:00")
        #expect(DurationText.precise(0) == "00:00:00")
    }
}
