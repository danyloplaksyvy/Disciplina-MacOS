import SwiftUI

struct StoreErrorView: View {
    let store: TaskStore
    var body: some View {
        if let message = store.errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                if store.needsRefresh {
                    Button("Retry loading") { store.reload() }
                } else {
                    Button("Dismiss") { store.dismissError() }
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("store-error")
        }
    }
}

struct TaskInputView: View {
    let store: TaskStore
    let focusToken: Int
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            TextField("Add a task…", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused).onSubmit(add)
                .accessibilityLabel("New task").accessibilityIdentifier("new-task")
            Button(action: add) { Image(systemName: "plus") }
                .help("Add task").accessibilityLabel("Add task")
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.needsRefresh)
        }
        .onAppear { focused = true }
        .onChange(of: focusToken) { focused = true }
    }

    private func add() {
        if store.create(title: title) { title = "" }
        focused = true
    }
}

struct TaskRowView: View {
    let item: TodoItem
    let store: TaskStore
    @State private var editing = false
    @State private var draft = ""
    @State private var confirmingDelete = false
    @FocusState private var editingFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.setCompleted(id: item.id, isCompleted: !item.isCompleted)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.isCompleted ? "Reopen" : "Complete") \(item.title)")
            .accessibilityIdentifier("toggle-\(item.id)")
            .disabled(store.needsRefresh)
            if editing {
                TextField("Task title", text: $draft)
                    .focused($editingFocused).onSubmit(save)
                    .onExitCommand { editing = false }
                    .accessibilityIdentifier("edit-task")
                Button("Save", action: save)
                Button("Cancel") { editing = false }
            } else {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2, perform: edit)
                Menu {
                    Button("Edit title", action: edit)
                    Button("Delete…", role: .destructive) { confirmingDelete = true }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Actions for \(item.title)")
            }
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("Edit title", action: edit)
            Button("Delete…", role: .destructive) { confirmingDelete = true }
        }
        .alert("Delete this task?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { store.delete(id: item.id) }
        } message: { Text("“\(item.title)” will be permanently removed.") }
    }

    private func edit() { draft = item.title; editing = true; editingFocused = true }
    private func save() { if store.rename(id: item.id, title: draft) { editing = false } }
}

struct TaskListView: View {
    let store: TaskStore
    var compact = false
    @State private var selection: UUID?
    @State private var completedExpanded = false
    @FocusState private var listFocused: Bool

    var body: some View {
        List(selection: $selection) {
            Section("Active · \(store.active.count)") {
                if store.active.isEmpty {
                    Text("All clear. Add a task whenever you’re ready.")
                        .foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach(store.active) { item in
                    TaskRowView(item: item, store: store).tag(item.id)
                }
            }
            if compact {
                DisclosureGroup("Completed · \(store.completed.count)", isExpanded: $completedExpanded) {
                    ForEach(store.completed) { item in
                        TaskRowView(item: item, store: store).tag(item.id)
                    }
                }
            } else {
                Section("Completed · \(store.completed.count)") {
                    ForEach(store.completed) { item in
                        TaskRowView(item: item, store: store).tag(item.id)
                    }
                    if store.completed.isEmpty { Text("Completed tasks will appear here.").foregroundStyle(.secondary) }
                }
            }
        }
        .listStyle(.inset).focused($listFocused)
        .onKeyPress(.space) {
            guard listFocused, let item = store.items.first(where: { $0.id == selection }) else { return .ignored }
            store.setCompleted(id: item.id, isCompleted: !item.isCompleted)
            return .handled
        }
        .accessibilityIdentifier(compact ? "popover-task-list" : "main-task-list")
    }
}

struct MainTaskWindowView: View {
    let store: TaskStore
    @State private var focusToken = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Tasks").font(.largeTitle.bold())
                    Text("\(store.active.count) remaining").foregroundStyle(.secondary)
                }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
            }
            TaskInputView(store: store, focusToken: focusToken)
            StoreErrorView(store: store)
            TaskListView(store: store)
            HStack {
                Text("\(store.items.count) tasks in total")
                Spacer()
                Label("Local storage", systemImage: "internaldrive")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(minWidth: 520, minHeight: 360)
        .onReceive(NotificationCenter.default.publisher(for: .focusNewTask)) { _ in focusToken += 1 }
    }
}

struct MenuBarTaskView: View {
    let store: TaskStore
    @Binding var isPresented: Bool
    let openMain: () -> Void
    @State private var focusToken = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disciplina").font(.headline)
            TaskInputView(store: store, focusToken: focusToken)
            StoreErrorView(store: store)
            TaskListView(store: store, compact: true).frame(height: 300)
            Divider()
            HStack {
                Button("Open full app") { isPresented = false; openMain() }
                    .keyboardShortcut("o")
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .help("Settings")
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(16).frame(width: 360)
        .onChange(of: isPresented) { if isPresented { focusToken += 1 } }
        .onExitCommand { isPresented = false }
    }
}

extension Notification.Name {
    static let focusNewTask = Notification.Name("Disciplina.focusNewTask")
}
