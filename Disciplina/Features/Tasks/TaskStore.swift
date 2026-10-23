import Foundation
import Observation

@MainActor @Observable
final class TaskStore {
    private(set) var structureRevision = 0
    private var structure: [[UUID]] { [inProgress.map(\.id), todo.map(\.id), completed.map(\.id)] }
    let service: TaskService
    let timer: TimerCoordinator
    let goalService: GoalService
    private(set) var goals: [Goal] = []
    private(set) var milestones: [Milestone] = []
    private(set) var goalProgress = GoalProgressService()
    private enum DeletedEntry { case task(UUID), milestone(Milestone) }
    private var deletionUndo: [DeletedEntry] = []
    var canUndoDeletion: Bool { !deletionUndo.isEmpty && !unavailable }
    private var goalStructure: [[UUID]] {
        GoalStatus.allCases.map { status in goals.filter { $0.status == status }.map(\.id) }
        + [milestones.filter { !$0.isCompleted }.map(\.id), milestones.filter(\.isCompleted).map(\.id)]
    }
    func goals(in status: GoalStatus) -> [Goal] {
        goals.filter { $0.status == status }.sorted {
            let a = status == .active ? $0.updatedAt : (status == .achieved ? $0.achievedAt! : $0.archivedAt!)
            let b = status == .active ? $1.updatedAt : (status == .achieved ? $1.achievedAt! : $1.archivedAt!)
            return a == b ? $0.id.uuidString < $1.id.uuidString : a > b
        }
    }
    func milestones(for id: UUID) -> [Milestone] {
        milestones.filter { $0.goalID == id }.sorted {
            $0.sortOrder == $1.sortOrder ? $0.id.uuidString < $1.id.uuidString : $0.sortOrder < $1.sortOrder
        }
    }
    func goalTotal(_ id: UUID, taskID: UUID? = nil) -> Int64 {
        let saved = taskID.map { goalProgress.taskContributions[id]?[$0] ?? 0 } ?? (goalProgress.durations[id] ?? 0)
        guard !unavailable, let running = timer.running, running.goalIDAtStart == id,
              taskID == nil || taskID == running.taskID else { return saved }
        let sum = saved.addingReportingOverflow(max(0, timer.elapsedMilliseconds - running.accumulatedMilliseconds))
        return sum.overflow ? saved : sum.partialValue
    }
    private(set) var series: [RecurrenceSeries] = []
    private var deletionSeries: [UUID: (before: RecurrenceSeries, after: UUID)] = [:]
    private(set) var dayGroups: [TaskDayGroup] = []
    private var groupingDate = Date()
    private var groupingCalendar = LocalDay.calendar()
    private(set) var sessions: [WorkSession] = []
    private(set) var activity = ActivitySummary()
    private(set) var deleted: [TodoItem] = []
    private(set) var deletedIDs: [UUID] = []
    var notice: String?
    var deletionFeedback: String?
    private var undoTitles: [UUID: String] = [:]
    var undoActionName: String {
        guard let entry = deletionUndo.last else { return "Undo" }
        switch entry { case .task: return "Undo Delete Task"; case .milestone: return "Undo Delete Milestone" }
    }
    var undoItemTitle: String? {
        guard let entry = deletionUndo.last else { return nil }
        switch entry { case .task(let id): return undoTitles[id] ?? deleted.first { $0.id == id }?.title ?? "Task"
        case .milestone(let value): return value.title }
    }
    var unavailable: Bool { needsRefresh || timer.failure != nil }
    var featured: TodoItem? {
        if let id = timer.running?.taskID { return items.first { $0.id == id } }
        return inProgress.first
    }
    private(set) var inProgress: [TodoItem] = []
    private(set) var todo: [TodoItem] = []
    private(set) var active: [TodoItem] = []
    private(set) var completed: [TodoItem] = []
    private var relevantCandidates: [TodoItem] = []
    private var totals: [UUID: Int64] = [:]
    var relevant: [TodoItem] {
        Array(relevantCandidates.filter { $0.id != featured?.id }.prefix(5))
    }
    private func recentlyUpdated(_ a: TodoItem, _ b: TodoItem) -> Bool {
        a.updatedAt == b.updatedAt ? a.id.uuidString < b.id.uuidString : a.updatedAt > b.updatedAt
    }
    func total(_ id: UUID) -> Int64 {
        let saved = totals[id] ?? 0
        guard let running = timer.running, running.taskID == id else { return saved }
        let sum = saved.addingReportingOverflow(max(0, timer.elapsedMilliseconds - running.accumulatedMilliseconds))
        return sum.overflow ? Int64.max : sum.partialValue
    }
    private(set) var items: [TodoItem] = []
    private(set) var errorMessage: String?
    private(set) var needsRefresh = false

    var menuBarStatus: MenuBarStatus {
        MenuBarStatus(activeCount: unavailable ? nil : items.reduce(0) { $0 + ($1.isCompleted ? 0 : 1) })
    }

    private func publish(_ snapshot: TaskSnapshot) {
        let previousGroups = [inProgress, todo, completed]
        items = snapshot.tasks.filter { $0.deletedAt == nil }
        deleted = snapshot.tasks.filter { $0.deletedAt != nil }
        if sessions != snapshot.sessions || milestones != snapshot.milestones {
            goalProgress = GoalProgressService(milestones: snapshot.milestones, sessions: snapshot.sessions)
        }
        if sessions != snapshot.sessions { activity = ActivitySummary(sessions: snapshot.sessions) }
        goals = snapshot.goals
        milestones = snapshot.milestones
        sessions = snapshot.sessions
        series = snapshot.series
        active = items.filter { !$0.isCompleted }.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
        }
        completed = items.filter(\.isCompleted).sorted {
            $0.completedAt == $1.completedAt ? $0.id.uuidString < $1.id.uuidString : $0.completedAt! > $1.completedAt!
        }
        inProgress = items.filter { $0.status == .inProgress }.sorted(by: recentlyUpdated)
        todo = active.filter { $0.status == .todo }
        relevantCandidates = inProgress + todo.sorted(by: recentlyUpdated)
        if previousGroups != [inProgress, todo, completed] { rebuildDays() }
        totals = [:]
        for session in sessions { totals[session.taskID, default: 0] += session.accumulatedMilliseconds }
    }

    init(service: TaskService, timer: TimerCoordinator? = nil, goalService: GoalService? = nil) {
        self.service = service
        self.goalService = goalService ?? GoalService(repository: service.repository)
        self.timer = timer ?? TimerCoordinator(repository: service.repository)
        self.timer.onCommit = { [weak self] in self?.refresh() }
        do { try self.timer.recover() } catch { errorMessage = error.localizedDescription; needsRefresh = true; return }
        refresh()
    }

    private func refresh() {
        do {
            let snapshot = try service.repository.snapshot()
            try snapshot.validate()
            publish(snapshot)
            needsRefresh = false; errorMessage = nil
        } catch {
            needsRefresh = true
            errorMessage = "Could not load tasks. \(error.localizedDescription)"
        }
    }

    func reload() {
        do {
            if timer.failure != nil { try timer.recover() }
            refresh()
            if !unavailable { calendarChanged() }
        } catch { errorMessage = error.localizedDescription; needsRefresh = true }
    }

    @discardableResult func create(title: String, goalID: UUID? = nil) -> Bool { mutate { try service.create(title: title, goalID: goalID) } }
    @discardableResult func rename(id: UUID, title: String) -> Bool { mutate { try service.rename(id: id, title: title) } }
    @discardableResult func setCompleted(id: UUID, isCompleted: Bool) -> Bool {
        mutate { try timer.setStatus(id: id, status: isCompleted ? .completed : .todo) }
    }
    @discardableResult func delete(id: UUID, disposition: RecurringDeletion = .stop) -> Bool {
        let title = items.first { $0.id == id }?.title ?? "Task"
        var ticket: (RecurrenceSeries, UUID)?
        let saved = mutate {
            ticket = try timer.delete(id: id, disposition: disposition)
        }
        if let ticket { deletionSeries[id] = ticket }
        if saved { deletedIDs.append(id); deletionUndo.append(.task(id)); undoTitles[id] = title; deletionFeedback = "Deleted “\(title)”" }
        return saved
    }
    @discardableResult func start(_ id: UUID) -> Bool {
        let previous = timer.running.flatMap { running in items.first { $0.id == running.taskID } }
        let result = mutate { try timer.start(taskID: id) }
        if result {
            let title = items.first { $0.id == id }?.title ?? "task"
            notice = previous != nil && previous?.id != id ? "Paused \(previous!.title) · Started \(title)" : "Started \(title)"
        }
        return result
    }
    @discardableResult func pause(_ reason: SessionEndReason = .paused) -> Bool {
        let wasRunning = timer.running != nil
        let result = mutate { try timer.pause(reason: reason) }
        if result && wasRunning { notice = "Timer paused." }
        return result
    }
    @discardableResult func setStatus(_ id: UUID, _ status: TaskStatus) -> Bool { mutate { try timer.setStatus(id: id, status: status) } }
    @discardableResult func restore(_ id: UUID, undo: Bool = false) -> Bool {
        var independent = false
        let result = mutate {
            var snapshot = try service.repository.snapshot()
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == id }) else { throw TaskError.notFound }
            guard snapshot.tasks[index].deletedAt != nil else { return }
            if undo, let ticket = deletionSeries[id],
               let s = snapshot.series.firstIndex(where: { $0.id == ticket.before.id && $0.revision == ticket.after }) {
                snapshot.series[s] = ticket.before
            } else {
                independent = snapshot.tasks[index].seriesID != nil
                snapshot.detachTask(at: index)
            }
            snapshot.tasks[index].deletedAt = nil
            snapshot.tasks[index].updatedAt = Date()
            try service.repository.commit(snapshot)
        }
        if result { removeTaskUndo(id); deletionSeries[id] = nil; notice = independent ? "Task restored independently; recurrence was left unchanged." : "Task restored." }
        return result
    }
    private func removeTaskUndo(_ id: UUID) {
        deletedIDs.removeAll { $0 == id }
        deletionUndo.removeAll { if case .task(let value) = $0 { return value == id }; return false }
    }
    func undoDelete() {
        guard let entry = deletionUndo.last else { return }
        switch entry {
        case .task(let id):
            let title = undoItemTitle ?? "Task"
            if restore(id, undo: true) { deletionFeedback = "Restored “\(title)”" }
        case .milestone(let value):
            if mutate({ try goalService.restoreMilestone(value) }) { deletionUndo.removeLast(); deletionFeedback = "Restored “\(value.title)”" }
        }
    }
    @discardableResult func permanentlyDelete(_ id: UUID) -> Bool {
        guard deleted.contains(where: { $0.id == id }) else { return false }
        let result = mutate { try service.repository.delete(id: id) }
        if result { removeTaskUndo(id); deletionSeries[id] = nil }
        return result
    }
    func prepareSessionEditor(taskID: UUID) -> Bool {
        guard !unavailable else { return false }
        if timer.running?.taskID == taskID, !pause() { return false }
        return !unavailable && items.contains { $0.id == taskID }
    }
    @discardableResult func addSession(taskID: UUID, date: Date, milliseconds: Int64) -> Bool {
        mutate { try timer.addSession(taskID: taskID, date: date, milliseconds: milliseconds) }
    }
    @discardableResult func editSession(taskID: UUID, sessionID: UUID, milliseconds: Int64) -> Bool {
        mutate { try timer.editSession(taskID: taskID, sessionID: sessionID, milliseconds: milliseconds) }
    }
    @discardableResult func deleteSession(taskID: UUID, sessionID: UUID) -> Bool {
        mutate { try timer.deleteSession(taskID: taskID, sessionID: sessionID) }
    }

    func currentSeries(for item: TodoItem) -> RecurrenceSeries? {
        series.first { $0.id == item.seriesID && $0.enabled && $0.currentTaskID == item.id }
    }
    @discardableResult func setRepeat(_ id: UUID, weekdays: [Int]) -> Bool {
        mutate { try timer.setRepeat(taskID: id, weekdays: weekdays) }
    }
    @discardableResult func changeSeries(_ id: UUID, weekdays: [Int]?) -> Bool {
        mutate { try timer.changeSeries(id: id, weekdays: weekdays) }
    }
    func calendarChanged(now: Date = Date(), calendar: Calendar = LocalDay.calendar()) {
        groupingDate = now; groupingCalendar = calendar; rebuildDays()
        if !unavailable { _ = mutate { try timer.reconcileRecurrence() } }
    }
    private func rebuildDays() {
        dayGroups = TaskDayGroup.make(inProgress: inProgress, todo: todo, completed: completed,
                                     now: groupingDate, calendar: groupingCalendar)
    }

    @discardableResult func saveGoal(id: UUID?, title: String, criteria: String, targetDay: LocalDay?) -> UUID? {
        var result: UUID?
        let saved = mutate { result = try goalService.save(id: id, title: title, criteria: criteria, targetDay: targetDay) }
        return saved ? result : nil
    }
    @discardableResult func goalTransition(_ id: UUID, _ action: GoalService.Lifecycle) -> Bool {
        mutate { try goalService.transition(id, action) }
    }
    @discardableResult func saveMilestone(goalID: UUID, id: UUID?, title: String) -> Bool {
        mutate { try goalService.saveMilestone(goalID: goalID, id: id, title: title) }
    }
    @discardableResult func completeMilestone(_ id: UUID, completed: Bool) -> Bool {
        mutate { try goalService.completeMilestone(id, completed: completed) }
    }
    @discardableResult func reorderMilestones(goalID: UUID, ids: [UUID]) -> Bool {
        mutate { try goalService.reorder(goalID: goalID, ids: ids) }
    }
    @discardableResult func deleteMilestone(_ id: UUID) -> Bool {
        var deleted: Milestone?
        let saved = mutate { deleted = try goalService.deleteMilestone(id) }
        if saved, let deleted { deletionUndo.append(.milestone(deleted)); deletionFeedback = "Deleted “\(deleted.title)”" }
        return saved
    }
    @discardableResult func assignGoal(taskID: UUID, goalID: UUID?) -> Bool {
        mutate { try timer.assignGoal(taskID: taskID, goalID: goalID) }
    }
    @discardableResult func setAppearance(taskID: UUID, appearance: TaskAppearance?) -> Bool {
        mutate { try timer.setAppearance(taskID: taskID, appearance: appearance) }
    }
    @discardableResult func editDailySession(taskID: UUID, sessionID: UUID, amounts: [UUID: Int64]) -> Bool {
        mutate { try timer.editDailySession(taskID: taskID, sessionID: sessionID, amounts: amounts) }
    }
    func prepareGoalAssignment(taskID: UUID) -> Bool { prepareSessionEditor(taskID: taskID) }

    func dismissError() { if !needsRefresh { errorMessage = nil } }

    private func mutate(_ action: () throws -> Void) -> Bool {
        guard !unavailable else { return false }
        let previousStructure = structure
        let previousGoals = goalStructure
        do { try action() } catch {
            errorMessage = "Could not save the change. \(error.localizedDescription)"
            return false
        }
        do {
            let snapshot = try service.repository.snapshot()
            try snapshot.validate()
            publish(snapshot)
            if structure != previousStructure || goalStructure != previousGoals { structureRevision += 1 }
            errorMessage = nil
        } catch {
            needsRefresh = true
            errorMessage = "Your change was saved, but the list could not refresh. Retry loading; do not submit it again. \(error.localizedDescription)"
        }
        // True means committed, even when a subsequent refresh failed.
        return true
    }
}
