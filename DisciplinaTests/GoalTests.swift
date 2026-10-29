import Foundation
import Testing
@testable import Disciplina

@Suite @MainActor struct GoalTests {
    func fixture() throws -> (MemoryRepository, FakeTime, TimerCoordinator, TaskStore, UUID, UUID) {
        let (repo, clock, timer, task, _) = try TimerTests().fixture()
        let service = GoalService(repository: repo, now: { clock.date })
        let store = TaskStore(service: TaskService(repository: repo, now: { clock.date }), timer: timer, goalService: service)
        let goal = try #require(store.saveGoal(id: nil, title: "Goal", criteria: "A measurable outcome", targetDay: LocalDay(clock.date)))
        return (repo, clock, timer, store, task, goal)
    }
    @Test func validationAndLifecycleNoOps() throws {
        #expect(throws: (any Error).self) { try GoalService.title("  ") }
        #expect(throws: (any Error).self) { try GoalService.title("a\nb") }
        #expect(throws: (any Error).self) { try GoalService.criteria("\n ") }
        #expect(try GoalService.criteria(" A\nB ") == "A\nB")
        #expect(try GoalService.title(String(repeating: "👨‍👩‍👧‍👦", count: 120)).count == 120)
        #expect(throws: (any Error).self) { try GoalService.title(String(repeating: "a", count: 121)) }
        #expect(throws: (any Error).self) { try GoalService.criteria(String(repeating: "a", count: 501)) }
        #expect(throws: (any Error).self) { try GoalService.milestoneTitle(String(repeating: "a", count: 201)) }
        let (repo, clock, timer, store, task, goal) = try fixture()
        #expect(store.assignGoal(taskID: task, goalID: goal)); #expect(store.start(task))
        clock.advance(1)
        #expect(store.goalTransition(goal, .achieve))
        let achieved = try #require(repo.goals[0].achievedAt)
        let writes = repo.writes
        #expect(store.goalTransition(goal, .achieve)); #expect(repo.writes == writes)
        #expect(store.goalTransition(goal, .archive)); #expect(store.goalTransition(goal, .restore))
        #expect(repo.goals[0].status == .achieved); #expect(repo.goals[0].achievedAt == achieved)
        #expect(timer.running?.taskID == task)
        #expect(store.goalTransition(goal, .reopen)); #expect(repo.goals[0].achievedAt == nil)
        #expect(store.goalTransition(goal, .archive)); #expect(store.goalTransition(goal, .restore))
        #expect(repo.goals[0].status == .active)
        let unchanged = repo.goals[0]
        let count = repo.writes
        #expect(store.saveGoal(id: goal, title: unchanged.title, criteria: unchanged.successCriteria, targetDay: unchanged.targetDay) == goal)
        #expect(repo.writes == count)
    }
    @Test func milestoneProgressOrderingAndUnifiedUndo() throws {
        let (repo, clock, _, store, task, goal) = try fixture()
        #expect(store.goalProgress.progress[goal] == nil)
        for title in ["First", "Second", "Third"] { #expect(store.saveMilestone(goalID: goal, id: nil, title: title)) }
        let ids = store.milestones(for: goal).map(\.id)
        clock.advance(1)
        #expect(store.completeMilestone(ids[0], completed: true))
        #expect(store.goalProgress.progress[goal]?.fraction == 1.0 / 3)
        #expect(repo.goals[0].updatedAt == clock.date)
        #expect(store.reorderMilestones(goalID: goal, ids: ids.reversed()))
        let original = try #require(store.milestones.first { $0.id == ids[0] })
        #expect(store.deleteMilestone(ids[0]))
        #expect(store.delete(id: task))
        store.undoDelete(); #expect(store.items.contains { $0.id == task })
        #expect(!store.milestones.contains { $0.id == ids[0] })
        #expect(store.saveMilestone(goalID: goal, id: nil, title: "Intervening"))
        store.undoDelete()
        #expect(store.milestones.first { $0.id == ids[0] } == original)
        #expect(store.milestones(for: goal).map(\.sortOrder) == [0,1,2,3])
        #expect(!store.canUndoDeletion)
        #expect(store.goals[0].status == .active)
        try repo.snapshot().validate()
    }
    @Test func attributionIsImmutableAndManualUsesCurrentGoal() throws {
        let (repo, clock, timer, store, task, first) = try fixture()
        #expect(store.start(task)); clock.advance(1); #expect(store.pause())
        #expect(repo.sessions[0].goalIDAtStart == nil)
        #expect(store.assignGoal(taskID: task, goalID: first))
        #expect(store.start(task)); clock.advance(2); timer.tick()
        #expect(store.goalTotal(first) == 2000)
        #expect(!store.assignGoal(taskID: task, goalID: nil))
        #expect(store.prepareGoalAssignment(taskID: task))
        let second = try #require(store.saveGoal(id: nil, title: "Second", criteria: "Outcome", targetDay: nil))
        #expect(store.assignGoal(taskID: task, goalID: second))
        #expect(store.addSession(taskID: task, date: clock.date.addingTimeInterval(-100000), milliseconds: 3000))
        #expect(store.goalTotal(first) == 2000); #expect(store.goalTotal(second) == 3000)
        #expect(store.total(task) == 6000)
        #expect(store.goalTransition(second, .archive))
        #expect(store.start(task)); clock.advance(1); #expect(store.pause())
        #expect(store.goalTotal(second) == 4000)
        #expect(repo.goals.first { $0.id == second }?.status == .archived)
        let manual = repo.sessions[2]
        #expect(store.editSession(taskID: task, sessionID: manual.id, milliseconds: 5000))
        #expect(store.goalTotal(second) == 6000)
        #expect(store.deleteSession(taskID: task, sessionID: manual.id)); #expect(store.goalTotal(second) == 1000)
        #expect(store.delete(id: task)); #expect(store.goalTotal(first) == 2000)
        #expect(store.permanentlyDelete(task)); #expect(store.goalTotal(first) == 0); #expect(store.goalTotal(second) == 0)
    }
    @Test func failureRollbackAndReloadOnlyRecovery() throws {
        let (repo, clock, timer, store, task, goal) = try fixture()
        #expect(store.start(task)); clock.advance(2)
        repo.failWrite = true
        #expect(!store.prepareGoalAssignment(taskID: task)); #expect(timer.running != nil)
        #expect(!store.goalTransition(goal, .archive)); #expect(repo.goals[0].status == .active)
        repo.failWrite = false
        #expect(store.prepareGoalAssignment(taskID: task)); #expect(timer.running == nil)
        repo.failWrite = true
        #expect(!store.assignGoal(taskID: task, goalID: goal)); #expect(repo.items[0].goalID == nil)
        repo.failWrite = false; repo.failFetchAfterWrite = true
        #expect(store.assignGoal(taskID: task, goalID: goal)); #expect(store.unavailable)
        #expect(!store.assignGoal(taskID: task, goalID: goal))
        repo.failFetchAfterWrite = false; repo.failFetch = false
        let writes = repo.writes
        store.reload(); #expect(!store.unavailable); #expect(repo.writes == writes)
        #expect(repo.items[0].goalID == goal)
        #expect(repo.sessions[0].accumulatedMilliseconds == 2000); #expect(repo.sessions[0].goalIDAtStart == nil)
    }
    @Test func cancellationAndUnrelatedRunningTaskKeepTimerAndHistory() throws {
        let (repo, clock, timer, store, task, goal) = try fixture()
        #expect(store.start(task)); clock.advance(2)
        let other = repo.items[1].id
        #expect(store.assignGoal(taskID: other, goalID: goal)); #expect(timer.running?.taskID == task)
        #expect(store.prepareGoalAssignment(taskID: task))
        // Cancelling after a required pause performs no assignment and never resumes.
        #expect(timer.running == nil); #expect(repo.items.first { $0.id == task }?.goalID == nil)
        #expect(repo.sessions[0].accumulatedMilliseconds == 2000)
        #expect(store.setCompleted(id: other, isCompleted: true))
        #expect(store.assignGoal(taskID: other, goalID: nil))
        #expect(repo.items.first { $0.id == other }?.isCompleted == true)
        let before = try repo.snapshot()
        repo.failWrite = true
        #expect(store.saveGoal(id: nil, title: "Fails", criteria: "Result", targetDay: nil) == nil)
        #expect(!store.saveMilestone(goalID: goal, id: nil, title: "Fails"))
        #expect(try repo.snapshot() == before)
    }

    @Test func milestoneDeletionRefreshFailureStillSupportsUndo() throws {
        let (repo, _, _, store, _, goal) = try fixture()
        #expect(store.saveMilestone(goalID: goal, id: nil, title: "M"))
        let item = store.milestones[0]
        repo.failFetchAfterWrite = true
        #expect(store.deleteMilestone(item.id)); #expect(store.unavailable)
        repo.failFetchAfterWrite = false; repo.failFetch = false; store.reload()
        store.undoDelete(); #expect(store.milestones == [item])
    }
    @Test func recurringGoalTemplateAndHistory() throws {
        let (repo, clock, _, store, task, goal) = try fixture()
        #expect(store.assignGoal(taskID: task, goalID: goal))
        #expect(store.setRepeat(task, weekdays: Array(1...7)))
        #expect(repo.series[0].futureGoalID == goal)
        #expect(store.setCompleted(id: task, isCompleted: true))
        #expect(store.assignGoal(taskID: task, goalID: nil))
        let nextDay = clock.date.addingTimeInterval(86400)
        clock.advance(86400)
        store.calendarChanged(now: nextDay)
        let successor = try #require(repo.series[0].currentTaskID)
        #expect(successor != task); #expect(repo.items.first { $0.id == successor }?.goalID == nil)
        #expect(store.assignGoal(taskID: task, goalID: goal))
        #expect(repo.series[0].futureGoalID == nil)
        #expect(store.assignGoal(taskID: successor, goalID: goal))
        #expect(store.delete(id: successor, disposition: .skip))
        store.undoDelete(); #expect(repo.series[0].futureGoalID == goal)
        #expect(repo.items.first { $0.id == successor }?.goalID == goal)
    }
    @Test func exportCompatibilityValidationAndOverflow() throws {
        let (repo, clock, _, store, task, goal) = try fixture()
        #expect(store.assignGoal(taskID: task, goalID: goal))
        #expect(store.addSession(taskID: task, date: clock.date, milliseconds: 42))
        #expect(store.saveMilestone(goalID: goal, id: nil, title: "M"))
        let snapshot = try repo.snapshot()
        let document = BackupDocument(snapshot: snapshot)
        #expect(document.formatVersion == 5)
        #expect(try BackupDocument.decode(document.encode()).validatedSnapshot() == snapshot)
        for version in 1...3 {
            var json = try #require(JSONSerialization.jsonObject(with: document.encode()) as? [String: Any])
            json["formatVersion"] = version; json.removeValue(forKey: "goals"); json.removeValue(forKey: "milestones")
            let old = try BackupDocument.decode(JSONSerialization.data(withJSONObject: json)).validatedSnapshot()
            #expect(old.goals.isEmpty); #expect(old.milestones.isEmpty)
            #expect(old.tasks.allSatisfy { $0.goalID == nil }); #expect(old.sessions.allSatisfy { $0.goalIDAtStart == nil })
        }
        var bad = snapshot; bad.goals = []
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = snapshot; bad.milestones[0].sortOrder = 3
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = snapshot; bad.goals[0].status = .archived
        #expect(throws: (any Error).self) { try bad.validate() }
        let other = repo.items[1].id
        #expect(store.assignGoal(taskID: other, goalID: goal))
        #expect(!store.addSession(taskID: other, date: clock.date, milliseconds: Int64.max))
        #expect(store.goalTotal(goal) == 42)
    }
    @Test func hundredGoalsAndTenThousandTasksAggregateWithoutTickWrites() throws {
        let repo = MemoryRepository(), clock = FakeTime()
        let date = clock.date
        for g in 0..<100 {
            let goal = Goal(id: UUID(), title: "Goal \(g)", successCriteria: "Done", createdAt: date, updatedAt: date)
            repo.goals.append(goal)
            for t in 0..<100 {
                let task = TodoItem(id: UUID(), title: "Task \(g)-\(t)", createdAt: date, updatedAt: date, completedAt: nil, goalID: goal.id)
                repo.items.append(task)
                repo.sessions.append(WorkSession(id: UUID(), taskID: task.id, startedAt: date, endedAt: date,
                    accumulatedMilliseconds: 1000, lastCheckpointAt: date, endReason: .manuallyAdded, origin: .manual, goalIDAtStart: goal.id))
            }
        }
        let timer = TimerCoordinator(repository: repo, sample: { clock.sample() })
        let store = TaskStore(service: TaskService(repository: repo), timer: timer)
        #expect(store.items.count == 10000); #expect(store.goals.count == 100)
        #expect(store.goalTotal(repo.goals[0].id) == 100000)
        #expect(store.start(repo.items[0].id))
        let writes = repo.writes
        clock.advance(1); timer.tick()
        #expect(repo.writes == writes); #expect(store.goalTotal(repo.goals[0].id) == 101000)
    }

    @Test func checkpointDoesNotReorderGoalsAndFailureFreezesEffort() throws {
        let (repo, clock, timer, store, task, goal) = try fixture()
        let updated = store.goals[0].updatedAt
        #expect(store.assignGoal(taskID: task, goalID: goal)); #expect(store.start(task))
        let revision = store.structureRevision
        clock.advance(5); timer.tick()
        #expect(store.goalTotal(goal) == 5000); #expect(store.goals[0].updatedAt == updated)
        #expect(store.structureRevision == revision)
        repo.failWrite = true; clock.advance(5); timer.tick()
        #expect(store.unavailable); #expect(store.goalTotal(goal) == 5000)
        repo.failWrite = false; store.reload()
        #expect(timer.running == nil); #expect(store.goalTotal(goal) == 5000)
    }
}
