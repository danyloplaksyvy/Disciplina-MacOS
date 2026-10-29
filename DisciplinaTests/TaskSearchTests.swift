import Foundation
import Testing
@testable import Disciplina

@Suite @MainActor struct TaskSearchTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func task(_ title: String, status: TaskStatus = .todo, goal: UUID? = nil, deleted: Bool = false) -> TodoItem {
        TodoItem(id: UUID(), title: title, createdAt: now, updatedAt: now,
                 completedAt: status == .completed ? now : nil, status: status,
                 deletedAt: deleted ? now : nil, goalID: goal)
    }
    private func groups(_ tasks: [TodoItem]) -> [TaskDayGroup] {
        TaskDayGroup.make(inProgress: tasks.filter { $0.status == .inProgress }, todo: tasks.filter { $0.status == .todo },
                          completed: tasks.filter { $0.status == .completed }, now: now, calendar: LocalDay.calendar())
    }
    @Test func titleMatchingUsesTrimmedLiteralUnicodeSubstring() {
        let value = task("École — Café ☕️")
        #expect(TaskQuery(text: "  ECOLE \n").matches(value))
        #expect(TaskQuery(text: "cafe").matches(value))
        #expect(TaskQuery(text: "☕️").matches(value))
        #expect(TaskQuery(text: " \n ").matches(value))
        #expect(!TaskQuery(text: "ecole cafe").matches(value))
        #expect(!TaskQuery(text: "c*f").matches(value))
        #expect(TaskQuery(text: "cafe\u{301}").matches(value))
    }
    @Test func combinesStatusAndGoalWithText() {
        let goal = UUID(), other = UUID()
        let values = [task("Read café", status: .inProgress, goal: goal), task("Read café", goal: other),
                      task("Read café", status: .completed, goal: goal), task("Read café"), task("Read café", goal: goal, deleted: true)]
        let result = TaskQuery(text: "CAFE", status: .incomplete, goal: .goal(goal)).project(groups(values))
        #expect(result.visibleIDs == [values[0].id]); #expect(result.totalCount == 4)
        #expect(TaskQuery(goal: .unassigned).project(groups(values)).visibleIDs == [values[3].id])
        #expect(TaskQuery(status: .completed).project(groups(values)).visibleIDs == [values[2].id])
        #expect(TaskQuery(status: .todo).project(groups(values)).visibleIDs == [values[1].id, values[3].id])
        #expect(TaskQuery(status: .inProgress).project(groups(values)).visibleIDs == [values[0].id])
    }
    @Test func projectionPreservesDayAndStatusOrderingAndRemovesEmptyDays() {
        let a = task("Match one"), b = task("Match two"), c = task("Other", status: .completed)
        let today = LocalDay(now), old = LocalDay(now.addingTimeInterval(-86400))
        let input = [TaskDayGroup(id: today, title: "Today", inProgress: [], todo: [b, a], completed: []),
                     TaskDayGroup(id: old, title: "Yesterday", inProgress: [], todo: [], completed: [c])]
        let result = TaskQuery(text: "match").project(input)
        #expect(result.groups.map(\.id) == [today]); #expect(result.groups[0].todo.map(\.id) == [b.id, a.id])
        #expect(result.countLabel == "2 of 3 tasks")
        #expect(input[1].completed == [c])
    }
    @Test func unavailableResultsAreNotPresentedAsCurrentCounts() {
        let input = groups([task("Work")])
        let unavailable = TaskQuery().project(input, unavailable: true)
        #expect(unavailable.groups.isEmpty && unavailable.visibleIDs.isEmpty)
        #expect(unavailable.countLabel == "Task results unavailable")
        #expect(TaskQuery().project(input).countLabel == "1 of 1 tasks")
    }
    @Test func committedChangesRefreshMatchesWhileFailedSavesDoNot() throws {
        let repo = MemoryRepository(), store = TaskStore(service: TaskService(repository: repo))
        #expect(store.create(title: "First")); let id = try #require(store.items.first?.id)
        let query = TaskQuery(text: "second")
        #expect(query.project(store.dayGroups).visibleIDs.isEmpty)
        repo.failWrite = true; #expect(!store.rename(id: id, title: "Second"))
        #expect(query.project(store.dayGroups).visibleIDs.isEmpty)
        repo.failWrite = false; #expect(store.rename(id: id, title: "Second"))
        #expect(query.project(store.dayGroups).visibleIDs == [id])
        #expect(store.delete(id: id)); #expect(query.project(store.dayGroups).visibleIDs.isEmpty)
        store.undoDelete(); #expect(query.project(store.dayGroups).visibleIDs == [id])
    }
    @Test func goalIdentityAndRecurringOccurrenceAreIndependentOfTitles() {
        let id = UUID(), other = UUID(), series = UUID()
        var first = task("Routine", goal: id); first.seriesID = series
        var successor = task("Routine", goal: id); successor.seriesID = series
        let query = TaskQuery(goal: .goal(id))
        #expect(query.project(groups([first, successor])).visibleIDs == [first.id, successor.id])
        first.goalID = other
        #expect(query.project(groups([first, successor])).visibleIDs == [successor.id])
        // Goal names are not search terms, and renaming a goal cannot change UUID matching.
        #expect(TaskQuery(text: "Goal title", goal: .goal(id)).project(groups([successor])).visibleIDs.isEmpty)
    }
    @Test func goalRenameReassignmentAndRefreshRecoveryKeepSearchAuthoritative() throws {
        let repo = MemoryRepository(), store = TaskStore(service: TaskService(repository: repo))
        let goal = try #require(store.saveGoal(id: nil, title: "Original goal", criteria: "An outcome", targetDay: nil))
        #expect(store.create(title: "Linked work", goalID: goal))
        let taskID = try #require(store.items.first?.id)
        let query = TaskQuery(goal: .goal(goal))
        #expect(store.saveGoal(id: goal, title: "Renamed goal", criteria: "An outcome", targetDay: nil) == goal)
        #expect(query.project(store.dayGroups).visibleIDs == [taskID])
        #expect(store.assignGoal(taskID: taskID, goalID: nil))
        #expect(query.project(store.dayGroups).visibleIDs.isEmpty)
        repo.failFetchAfterWrite = true
        #expect(store.rename(id: taskID, title: "Committed title"))
        #expect(store.unavailable)
        #expect(TaskQuery(text: "Committed").project(store.dayGroups, unavailable: store.unavailable).unavailable)
        repo.failFetch = false; repo.failFetchAfterWrite = false; store.reload()
        #expect(TaskQuery(text: "Committed").project(store.dayGroups, unavailable: store.unavailable).visibleIDs == [taskID])
    }
    @Test func tenThousandTaskProjectionHasExactCounts() {
        let goals = (0..<100).map { _ in UUID() }
        let values = (0..<10000).map { task("Work \($0)", goal: goals[$0 % 100]) }
        let input = groups(values)
        #expect(TaskQuery(goal: .goal(goals[42])).project(input).visibleIDs.count == 100)
        #expect(TaskQuery(text: "Work 9999").project(input).visibleIDs.count == 1)
        let start = ContinuousClock.now
        for _ in 0..<20 { _ = TaskQuery(text: "work 99").project(input) }
        print("SEARCH_BENCHMARK 10000 tasks, 20 projections: \(start.duration(to: .now))")
    }
}
