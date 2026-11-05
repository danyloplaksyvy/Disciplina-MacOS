import SwiftUI

struct PlanningActions: View {
    let item: TodoItem
    let store: TaskStore
    var body: some View {
        if !item.isCompleted, item.plannedDay != store.today {
            Button(item.plannedDay == nil ? "Add to Today" : "Move to Today") { store.planToday(item.id) }
                .disabled(store.unavailable)
        }
        if item.plannedDay != nil {
            Button("Remove from plan") { store.removeFromPlan(item.id) }.disabled(store.unavailable)
        }
    }
}

struct PlanTaskPicker: View {
    let store: TaskStore
    var added: (UUID) -> Void = { _ in }
    @State private var query = ""
    @State private var candidates: [TodoItem] = []
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add existing task").font(.title2)
            TaskSearchField(text: $query, focusToken: 1, escape: { if query.isEmpty { dismiss() } else { query = "" } }, enter: {})
            StoreErrorView(store: store)
            List(candidates) { item in
                HStack {
                    Text(item.title).lineLimit(2).help(item.title)
                    Spacer()
                    Button(item.plannedDay == store.today ? "Added" : "Add to Today") {
                        if store.planToday(item.id), !store.unavailable { added(item.id); dismiss() }
                    }.disabled(store.unavailable || item.plannedDay == store.today)
                        .accessibilityLabel("Add \(item.title) to Today")
                }
            }.overlay { if candidates.isEmpty { Text(store.unavailable ? "Tasks unavailable" : "No unfinished tasks match.").foregroundStyle(.secondary) } }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(20).frame(width: 480, height: 440)
            .onChange(of: query, initial: true) { _, _ in refresh() }
            .onChange(of: store.items) { _, _ in refresh() }
            .onChange(of: store.unavailable) { _, _ in refresh() }
    }
    private func refresh() {
        candidates = store.unavailable ? [] : store.active.filter { TaskQuery(text: query).matches($0) }
    }
}
