import SwiftUI

struct GoalPicker: View {
    let goals: [Goal]
    @Binding var selection: UUID?
    var body: some View {
        Picker("Goal", selection: $selection) {
            Text("Unassigned").tag(UUID?.none)
            ForEach(GoalStatus.allCases, id: \.self) { status in
                Section(status.title) {
                    ForEach(goals.filter { $0.status == status }.sorted {
                        $0.title == $1.title ? $0.id.uuidString < $1.id.uuidString : $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }) { goal in Text(goal.title).tag(Optional(goal.id)) }
                }
            }
        }.accessibilityIdentifier("goal-picker")
    }
}

struct GoalEditorView: View {
    let store: TaskStore
    let goal: Goal?
    var saved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var criteria: String
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var error: String?
    @FocusState private var titleFocused: Bool
    init(store: TaskStore, goal: Goal?, saved: @escaping (UUID) -> Void) {
        self.store = store; self.goal = goal; self.saved = saved
        _title = State(initialValue: goal?.title ?? "")
        _criteria = State(initialValue: goal?.successCriteria ?? "")
        _hasDate = State(initialValue: goal?.targetDay != nil)
        _date = State(initialValue: (try? goal?.targetDay?.date()) ?? Date())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(goal == nil ? "New Goal" : "Edit Goal").font(.title2.bold())
            TextField("Goal title", text: $title).focused($titleFocused).accessibilityIdentifier("goal-title")
            Text("Success criterion").font(.headline)
            Text("What will be true when this goal is achieved?").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $criteria).frame(height: 100).border(Color.secondary.opacity(0.3))
                .accessibilityLabel("Success criterion").accessibilityIdentifier("goal-criteria")
            Toggle("Target date", isOn: $hasDate)
            if hasDate { DatePicker("Target date", selection: $date, displayedComponents: .date) }
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("goal-editor-error") }
            StoreErrorView(store: store)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(store.unavailable)
            }
        }.padding(24).frame(width: 440).tint(Theme.accent).onAppear { titleFocused = true }
    }
    private func save() {
        do {
            _ = try GoalService.title(title); _ = try GoalService.criteria(criteria)
            if let id = store.saveGoal(id: goal?.id, title: title, criteria: criteria, targetDay: hasDate ? LocalDay(date) : nil) {
                saved(id); dismiss()
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct MilestoneEditorView: View {
    let store: TaskStore
    let goalID: UUID
    let milestone: Milestone?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var error: String?
    @FocusState private var focused: Bool
    init(store: TaskStore, goalID: UUID, milestone: Milestone?) {
        self.store = store; self.goalID = goalID; self.milestone = milestone
        _title = State(initialValue: milestone?.title ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(milestone == nil ? "Add Milestone" : "Rename Milestone").font(.title2)
            TextField("Milestone title", text: $title).focused($focused).accessibilityIdentifier("milestone-title")
            if let error { Text(error).foregroundStyle(.red) }
            StoreErrorView(store: store)
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        _ = try GoalService.milestoneTitle(title)
                        if store.saveMilestone(goalID: goalID, id: milestone?.id, title: title) { dismiss() }
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(store.unavailable)
            }
        }.padding(24).frame(width: 380).onAppear { focused = true }
    }
}

struct TaskGoalEditorView: View {
    let store: TaskStore
    let taskID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var confirmPause = false
    init(store: TaskStore, task: TodoItem) {
        self.store = store; taskID = task.id; _selection = State(initialValue: task.goalID)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Task Goal").font(.title2)
            GoalPicker(goals: store.goals, selection: $selection)
            Text("Recorded time keeps its original goal. New sessions use this assignment.").font(.callout).foregroundStyle(.secondary)
            if let item = store.items.first(where: { $0.id == taskID }), store.currentSeries(for: item) != nil {
                Text("This also sets the goal for future recurring occurrences.").font(.callout)
            }
            StoreErrorView(store: store)
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if store.items.first(where: { $0.id == taskID })?.goalID == selection { dismiss() }
                    else if store.timer.running?.taskID == taskID { confirmPause = true }
                    else { save() }
                }.keyboardShortcut(.defaultAction).disabled(store.unavailable)
            }
        }.padding(24).frame(width: 420)
            .alert("Pause before changing goal?", isPresented: $confirmPause) {
                Button("Cancel", role: .cancel) {}
                Button("Pause and Continue") {
                    if store.prepareGoalAssignment(taskID: taskID) { save() }
                }
            } message: { Text("The current session will keep its original goal. Timing stays paused until you resume it.") }
    }
    private func save() { if store.assignGoal(taskID: taskID, goalID: selection) { dismiss() } }
}

struct LinkTaskView: View {
    let store: TaskStore
    let goalID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pendingTask: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link Existing Task").font(.title2)
            TextField("Search tasks", text: $query).accessibilityIdentifier("link-task-search")
            List {
                ForEach(store.items.filter { $0.goalID != goalID && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
                    .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }) { task in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(task.title).lineLimit(2)
                            Text(task.status.title + " · " + (store.goals.first { $0.id == task.goalID }?.title ?? "Unassigned")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Link") {
                            if store.timer.running?.taskID == task.id { pendingTask = task.id }
                            else { link(task.id) }
                        }.accessibilityLabel("Link \(task.title)")
                    }
                }
            }.frame(height: 260)
            StoreErrorView(store: store)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 480)
            .alert("Pause before changing goal?", isPresented: Binding(get: { pendingTask != nil }, set: { if !$0 { pendingTask = nil } })) {
                Button("Cancel", role: .cancel) { pendingTask = nil }
                Button("Pause and Continue") {
                    if let id = pendingTask, store.prepareGoalAssignment(taskID: id) { link(id) }
                    pendingTask = nil
                }
            } message: { Text("Recorded time keeps its original goal. Timing stays paused until you resume it.") }
    }
    private func link(_ id: UUID) { _ = store.assignGoal(taskID: id, goalID: goalID) }
}
