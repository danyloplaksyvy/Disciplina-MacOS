import SwiftUI

struct DeletionNoticeView: View {
    let store: TaskStore
    var body: some View {
        if let notice = store.notice {
            HStack {
                Text(notice).font(.callout)
                if store.canUndoDeletion { Button("Undo") { store.undoDelete() } }
                Spacer()
                Button("Dismiss") { store.notice = nil }
            }
        }
    }
}

private struct GoalEditorRequest: Identifiable { let id = UUID(); var goal: Goal? }
private struct MilestoneEditorRequest: Identifiable { let id = UUID(); var milestone: Milestone? }

struct GoalsView: View {
    let store: TaskStore
    @State private var selectedGoal: UUID?
    @State private var selectedTask: UUID?
    @State private var showArchived = false
    @State private var editor: GoalEditorRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if selectedGoal != nil {
                    Button { if selectedTask != nil { selectedTask = nil } else { selectedGoal = nil } } label: {
                        Label(selectedTask == nil ? "Goals" : "Goal details", systemImage: "chevron.left")
                    }.accessibilityIdentifier("goals-back")
                }
                Text(selectedGoal == nil ? "Goals" : "Goal details").font(.largeTitle.bold())
                Spacer()
                Button("New Goal") { editor = GoalEditorRequest() }.disabled(store.unavailable)
            }
            StoreErrorView(store: store)
            DeletionNoticeView(store: store)
            if let id = selectedGoal, let goal = store.goals.first(where: { $0.id == id }) {
                if let taskID = selectedTask, let task = store.items.first(where: { $0.id == taskID }) {
                    TaskDetailsView(item: task, store: store, close: { selectedTask = nil }).id(taskID)
                } else {
                    GoalDetailView(goal: goal, store: store, edit: { editor = GoalEditorRequest(goal: goal) }, openTask: { selectedTask = $0 }).id(id)
                }
            } else if store.goals.isEmpty {
                ContentUnavailableView {
                    Label("No goals yet", systemImage: "target")
                } description: {
                    Text("Create a goal to connect your tasks with something you want to achieve.")
                } actions: {
                    Button("Create Goal") { editor = GoalEditorRequest() }.disabled(store.unavailable)
                }
            } else {
                List {
                    goalSection(.active)
                    goalSection(.achieved)
                    Section {
                        if showArchived { goalRows(.archived) }
                    } header: {
                        Button { showArchived.toggle() } label: {
                            Label("Archived Goals · \(store.goals(in: .archived).count)", systemImage: showArchived ? "chevron.down" : "chevron.right")
                        }.buttonStyle(.plain)
                    }
                }.accessibilityIdentifier("goals-list")
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.structureRevision)
            }
        }.padding(24).tint(Theme.accent)
            .sheet(item: $editor) { request in
                GoalEditorView(store: store, goal: request.goal) { selectedGoal = $0; selectedTask = nil }
            }
    }
    @ViewBuilder private func goalSection(_ status: GoalStatus) -> some View {
        if !store.goals(in: status).isEmpty { Section(status.title) { goalRows(status) } }
    }
    private func goalRows(_ status: GoalStatus) -> some View {
        ForEach(store.goals(in: status)) { goal in
            Button { selectedGoal = goal.id; selectedTask = nil } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goal.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                        if let day = goal.targetDay { Text("Target: \(day.formatted)").font(.caption).foregroundStyle(.secondary) }
                        GoalProgressView(progress: store.goalProgress.progress[goal.id] ?? .init())
                    }
                    Spacer(minLength: 24)
                    Text(store.unavailable ? "—" : DurationText.concise(store.goalTotal(goal.id))).monospacedDigit()
                    Image(systemName: "chevron.right")
                }.padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open goal \(goal.title)").help(goal.title)
        }
    }
}

struct GoalProgressView: View {
    let progress: GoalProgressService.Progress
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let fraction = progress.fraction { ProgressView(value: fraction).accessibilityLabel(progress.description) }
            Text(progress.description).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel(progress.description)
    }
}

struct GoalDetailView: View {
    let goal: Goal
    let store: TaskStore
    let edit: () -> Void
    let openTask: (UUID) -> Void
    @State private var milestoneEditor: MilestoneEditorRequest?
    @State private var linking = false
    @State private var confirmAchieve = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var milestones: [Milestone] { store.milestones(for: goal.id) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Milestones").font(.title3.bold()); Spacer()
                        Button("Add Milestone") { milestoneEditor = MilestoneEditorRequest() }.disabled(store.unavailable)
                    }
                    GoalProgressView(progress: store.goalProgress.progress[goal.id] ?? .init())
                    ForEach(milestones) { milestone in milestoneRow(milestone) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Related Tasks").font(.title3.bold()); Spacer()
                        Button("Link Existing Task…") { linking = true }.disabled(store.unavailable)
                    }
                    TaskInputView(store: store, focusToken: 0, goalID: goal.id)
                    relatedGroup("In Progress", store.inProgress)
                    relatedGroup("To Do", store.todo)
                    relatedGroup("Completed", store.completed)
                    if !store.items.contains(where: { $0.goalID == goal.id }) { Text("No linked tasks yet.").foregroundStyle(.secondary) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recorded Work").font(.title3.bold())
                    Text(store.unavailable ? "—" : DurationText.precise(store.goalTotal(goal.id))).font(.title.monospacedDigit()).accessibilityIdentifier("goal-total")
                    if !store.unavailable, store.timer.running?.goalIDAtStart == goal.id { Label("Running", systemImage: "play.fill").foregroundStyle(Theme.accent) }
                    Text("Time from sessions attributed to this goal when recorded. Older unassigned sessions and time recorded for other goals are excluded.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.padding(.trailing, 8).frame(maxWidth: .infinity, alignment: .leading)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.structureRevision)
        }.accessibilityIdentifier("goal-details")
            .sheet(item: $milestoneEditor) { request in MilestoneEditorView(store: store, goalID: goal.id, milestone: request.milestone) }
            .sheet(isPresented: $linking) { LinkTaskView(store: store, goalID: goal.id) }
            .alert("Mark goal achieved?", isPresented: $confirmAchieve) {
                Button("Cancel", role: .cancel) {}
                Button("Mark Achieved") { store.goalTransition(goal.id, .achieve) }
            } message: { Text("Unfinished milestones and tasks will remain unchanged. Any running timer will continue.") }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(goal.title).font(.title).textSelection(.enabled)
            Text(goal.status.title).font(.headline).foregroundStyle(Theme.accent)
            Text(goal.successCriteria).textSelection(.enabled)
            if let day = goal.targetDay { Text("Target: \(day.formatted)").font(.callout) }
            HStack {
                Button("Edit Goal", action: edit)
                switch goal.status {
                case .active:
                    Button("Mark Achieved") {
                        if milestones.contains(where: { !$0.isCompleted }) { confirmAchieve = true }
                        else { store.goalTransition(goal.id, .achieve) }
                    }
                case .achieved: Button("Reopen Goal") { store.goalTransition(goal.id, .reopen) }
                case .archived: Button("Restore Goal") { store.goalTransition(goal.id, .restore) }
                }
                if goal.status != .archived { Button("Archive Goal") { store.goalTransition(goal.id, .archive) } }
            }.disabled(store.unavailable)
        }
    }
    private func milestoneRow(_ item: Milestone) -> some View {
        HStack {
            Button { store.completeMilestone(item.id, completed: !item.isCompleted) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
            }.buttonStyle(.plain).accessibilityLabel("\(item.isCompleted ? "Reopen" : "Complete") milestone \(item.title)")
            Text(item.title).strikethrough(item.isCompleted).foregroundStyle(item.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Rename") { milestoneEditor = MilestoneEditorRequest(milestone: item) }
                Button("Move Up") { move(item, by: -1) }.disabled(item.sortOrder == 0)
                Button("Move Down") { move(item, by: 1) }.disabled(item.sortOrder == milestones.count - 1)
                Button("Delete Milestone", role: .destructive) {
                    if store.deleteMilestone(item.id) { NSApp.keyWindow?.makeFirstResponder(nil) }
                }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for milestone \(item.title)")
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).help("Drag to reorder")
        }.padding(.vertical, 6).contentShape(Rectangle()).disabled(store.unavailable)
            .draggable(item.id.uuidString) { Text(item.title).padding(8) }
            .dropDestination(for: String.self) { values, _ in
                guard !store.unavailable, let value = values.first, let id = UUID(uuidString: value),
                      let from = milestones.firstIndex(where: { $0.id == id }), let to = milestones.firstIndex(where: { $0.id == item.id }), from != to else { return false }
                var ids = milestones.map(\.id); ids.remove(at: from); ids.insert(id, at: to)
                return store.reorderMilestones(goalID: goal.id, ids: ids)
            }
    }
    private func move(_ item: Milestone, by delta: Int) {
        var ids = milestones.map(\.id)
        guard let from = ids.firstIndex(of: item.id), ids.indices.contains(from + delta) else { return }
        ids.swapAt(from, from + delta); store.reorderMilestones(goalID: goal.id, ids: ids)
    }
    @ViewBuilder private func relatedGroup(_ title: String, _ values: [TodoItem]) -> some View {
        let tasks = values.filter { $0.goalID == goal.id }
        if !tasks.isEmpty {
            Text(title).font(.headline)
            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 2) {
                    TaskRowView(item: task, store: store, details: { openTask(task.id) })
                    Text("\(DurationText.concise(store.total(task.id))) task total · \(DurationText.concise(store.goalTotal(goal.id, taskID: task.id))) to this goal")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
