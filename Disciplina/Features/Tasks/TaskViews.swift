import SwiftUI

struct StoreErrorView: View {
    let store: TaskStore
    var body: some View {
        if let message = store.timer.failure ?? store.errorMessage {
            VStack(alignment: .leading) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                if store.unavailable { Button("Retry loading") { store.reload() } }
                else { Button("Dismiss") { store.dismissError() } }
            }.font(.callout).accessibilityIdentifier("store-error")
        }
    }
}

struct TaskInputView: View {
    let store: TaskStore
    let focusToken: Int
    @State private var title = ""
    var body: some View {
        HStack {
            CaptureTextField(text: $title, focusToken: focusToken, submit: add).frame(height: 26)
            Button(action: add) { Image(systemName: "plus") }
                .help("Add task").accessibilityLabel("Add task")
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.unavailable)
        }
    }
    private func add() { if store.create(title: title) { title = "" } }
}

struct TimerControls: View {
    let item: TodoItem
    let store: TaskStore
    var body: some View {
        if !item.isCompleted {
            if store.timer.running?.taskID == item.id {
                Button { store.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    .accessibilityLabel("Pause \(item.title)")
            } else {
                Button { store.start(item.id) } label: {
                    Label(item.status == .inProgress ? "Resume" : "Start", systemImage: "play.fill")
                }.accessibilityLabel("\(item.status == .inProgress ? "Resume" : "Start") \(item.title)")
            }
        }
    }
}

struct TaskRowView: View {
    let item: TodoItem
    let store: TaskStore
    var compact = false
    var details: () -> Void = {}
    @Environment(\.undoManager) private var undoManager
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editingFocused: Bool
    var body: some View {
        HStack(spacing: 10) {
            Button { store.setCompleted(id: item.id, isCompleted: !item.isCompleted) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle").font(.title3)
            }.buttonStyle(.plain)
                .accessibilityLabel("\(item.isCompleted ? "Reopen" : "Complete") \(item.title)")
                .accessibilityIdentifier("toggle-\(item.id)")
            if editing {
                TextField("Task title", text: $draft).focused($editingFocused).onSubmit(save)
                    .onExitCommand { editing = false }.accessibilityIdentifier("edit-task")
                Button("Save", action: save)
                Button("Cancel") { editing = false }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).strikethrough(item.isCompleted)
                        .onTapGesture(count: 2) { if !compact { draft = item.title; editing = true; editingFocused = true } }
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .lineLimit(compact ? 2 : nil)
                    if !compact {
                        HStack {
                            Label(store.timer.running?.taskID == item.id ? "Running" : item.status == .inProgress ? "Paused" : item.status.title,
                                  systemImage: store.timer.running?.taskID == item.id ? "play.fill" : item.status == .inProgress ? "pause" : "circle")
                            Text(DurationText.concise(store.total(item.id))).monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                TimerControls(item: item, store: store)
                if !compact {
                    Menu { actions } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for \(item.title)")
                }
            }
        }.padding(.vertical, 5).disabled(store.unavailable)
            .contextMenu { if !compact { actions } }
    }
    @ViewBuilder private var actions: some View {
        Button("Open details", action: details)
        Button("Edit title") { draft = item.title; editing = true; editingFocused = true }
        Menu("Change status") {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Button(status.title) { store.setStatus(item.id, status) }
            }
        }
        Button("Delete", role: .destructive) {
            if store.delete(id: item.id) {
                let id = item.id
                undoManager?.registerUndo(withTarget: store) { target in
                    MainActor.assumeIsolated { _ = target.restore(id) }
                }
                undoManager?.setActionName("Delete Task")
            }
        }
    }
    private func save() { if store.rename(id: item.id, title: draft) { editing = false } }
}

struct TaskDetailsView: View {
    let item: TodoItem
    let store: TaskStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.title).font(.title2).textSelection(.enabled)
                Text(item.status.title)
                Text("Created \(item.createdAt.formatted())")
                if let date = item.completedAt { Text("Completed \(date.formatted())") }
                Text(DurationText.precise(store.total(item.id))).font(.title.monospacedDigit())
                    .accessibilityLabel("Total time \(DurationText.precise(store.total(item.id)))")
                TimerControls(item: item, store: store)
                Divider()
                Text("Work sessions").font(.headline)
                let sessions = store.sessions.filter { $0.taskID == item.id }.sorted {
                    $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt
                }
                if sessions.isEmpty { Text("No work sessions yet.").foregroundStyle(.secondary) }
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.startedAt.formatted())
                        Text(session.endedAt.map { "Ended \($0.formatted())" } ?? "Running")
                        Text(DurationText.precise(session.id == store.timer.running?.id ? store.timer.elapsedMilliseconds : session.accumulatedMilliseconds))
                        if let reason = session.endReason { Text(reason.rawValue).foregroundStyle(.secondary) }
                    }.font(.caption).padding(.vertical, 5)
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 220, idealWidth: 280)
    }
}

struct MainTaskWindowView: View {
    let store: TaskStore
    @State private var focusToken = 0
    @State private var selection: UUID?
    @State private var detailID: UUID?
    @FocusState private var listFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My Tasks").font(.largeTitle.bold())
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
            }
            TaskInputView(store: store, focusToken: focusToken)
            StoreErrorView(store: store)
            if let notice = store.notice {
                HStack {
                    Text(notice).font(.callout)
                    if !store.deletedIDs.isEmpty { Button("Undo") { store.undoDelete() } }
                    Spacer()
                    Button("Dismiss") { store.notice = nil }
                }
            }
            HSplitView {
                List(selection: $selection) {
                    group("In Progress", store.inProgress)
                    group("To Do", store.todo)
                    group("Completed", store.completed)
                }.listStyle(.inset).focused($listFocused).accessibilityIdentifier("main-task-list")
                    .onKeyPress(.space) {
                        guard listFocused, let item = store.items.first(where: { $0.id == selection }) else { return .ignored }
                        store.setCompleted(id: item.id, isCompleted: !item.isCompleted); return .handled
                    }
                    .onKeyPress(.return) {
                        guard listFocused, selection != nil else { return .ignored }
                        detailID = selection; return .handled
                    }
                    .onChange(of: selection) { detailID = selection }
                if let item = store.items.first(where: { $0.id == detailID }) { TaskDetailsView(item: item, store: store) }
            }
            Text("\(store.items.count) tasks · Local storage").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 600, minHeight: 400).tint(Theme.accent)
            .onReceive(NotificationCenter.default.publisher(for: .focusNewTask)) { _ in focusToken += 1 }
    }
    @ViewBuilder private func group(_ title: String, _ items: [TodoItem]) -> some View {
        Section("\(title) · \(items.count)") {
            ForEach(items) { item in
                TaskRowView(item: item, store: store, details: { detailID = item.id }).tag(item.id)
            }
            if items.isEmpty { Text("No tasks").foregroundStyle(.secondary) }
        }
    }
}

struct MenuBarTaskView: View {
    let store: TaskStore
    let openMain: () -> Void
    let openSettings: () -> Void
    @State private var focusToken = 0
    private var maximumHeight: CGFloat { min(600, (NSScreen.main?.visibleFrame.height ?? 800) - 32) }
    var body: some View {
        QuickActionsLayout(maximumHeight: maximumHeight - 32,
                           desiredListHeight: min(CGFloat(store.relevant.count) * 70, 260)) {
            VStack(alignment: .leading, spacing: 12) {
                TaskInputView(store: store, focusToken: focusToken)
                StoreErrorView(store: store)
                if let item = store.featured {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(store.timer.running == nil ? "Paused" : "Running", systemImage: store.timer.running == nil ? "pause" : "play.fill")
                            .foregroundStyle(store.timer.running == nil ? Color.secondary : Theme.accent)
                        Text(item.title).font(.headline).lineLimit(2)
                        if store.timer.running != nil { Text(DurationText.precise(store.timer.elapsedMilliseconds)).font(.title.monospacedDigit()) }
                        Text("Total \(DurationText.concise(store.total(item.id)))").font(.caption)
                        HStack {
                            TimerControls(item: item, store: store)
                            Button("Complete") { store.setCompleted(id: item.id, isCompleted: true) }
                        }
                    }
                } else { Text("Ready when you are").foregroundStyle(.secondary) }
            }.fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack { ForEach(store.relevant) { TaskRowView(item: $0, store: store, compact: true) } }
            }.accessibilityIdentifier("popover-task-list")
            VStack(alignment: .leading, spacing: 8) {
                if let notice = store.notice { Text(notice).font(.caption).lineLimit(2) }
                Divider()
                HStack {
                    Button("Open Disciplina", action: openMain)
                    Spacer()
                    Button(action: openSettings) { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(width: 380).tint(Theme.accent)
            .onAppear { focusToken += 1 }
    }
}

/// Reserve measured chrome first; only the task region receives the remaining height.
private struct QuickActionsLayout: Layout {
    let maximumHeight: CGFloat
    let desiredListHeight: CGFloat
    private let spacing: CGFloat = 12
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 348
        let fixed = subviews[0].sizeThatFits(.init(width: width, height: nil)).height
            + subviews[2].sizeThatFits(.init(width: width, height: nil)).height
        let gaps = desiredListHeight == 0 ? spacing : spacing * 2
        return CGSize(width: width, height: min(maximumHeight, fixed + gaps + desiredListHeight))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        let top = subviews[0].sizeThatFits(.init(width: width, height: nil)).height
        let bottom = subviews[2].sizeThatFits(.init(width: width, height: nil)).height
        let gaps = desiredListHeight == 0 ? spacing : spacing * 2
        let list = max(0, bounds.height - top - bottom - gaps)
        subviews[0].place(at: bounds.origin, proposal: .init(width: width, height: top))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + top + spacing), proposal: .init(width: width, height: list))
        subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - bottom), proposal: .init(width: width, height: bottom))
    }
}

extension Notification.Name {
    static let focusNewTask = Notification.Name("Disciplina.focusNewTask")
}
