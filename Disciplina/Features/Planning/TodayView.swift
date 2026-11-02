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

struct TodayView: View {
    let store: TaskStore
    @State private var selection: UUID?
    @State private var detailID: UUID?
    @State private var completedExpanded = false
    @State private var picker = false
    @State private var drafts = TaskTitleDrafts()
    @FocusState private var listFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var visibleIDs: Set<UUID> {
        Set(store.dailyPlan.today.map(\.id) + store.dailyPlan.earlier.flatMap { $0.tasks.map(\.id) }
            + (completedExpanded ? store.dailyPlan.completed.map(\.id) : []))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Today").font(.largeTitle.bold())
                    Text(store.today.formatted).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add existing task…") { picker = true }.disabled(store.unavailable)
            }
            TaskInputView(store: store, focusToken: 0, planForToday: true)
            StoreErrorView(store: store)
            TaskDetailSplit(showsDetails: store.items.contains { $0.id == detailID }) {
                List(selection: Binding(get: { selection.flatMap { visibleIDs.contains($0) ? $0 : nil } }, set: { id in
                    if let id { selection = id; detailID = id }
                })) {
                    if !store.unavailable {
                        Section("Today · \(store.dailyPlan.today.count)") {
                            if store.dailyPlan.today.isEmpty { Text("Choose a task or add one above.").foregroundStyle(.secondary) }
                            ForEach(store.dailyPlan.today) { item in
                                row(item)
                                    .accessibilityAction(named: "Move Up") { move(item.id, by: -1) }
                                    .accessibilityAction(named: "Move Down") { move(item.id, by: 1) }

                            }.onMove { indices, destination in
                                var ids = store.dailyPlan.today.map(\.id); ids.move(fromOffsets: indices, toOffset: destination)
                                store.reorderToday(ids)
                            }
                        }
                        if !store.dailyPlan.earlier.isEmpty {
                            Section("Earlier plans") {
                                ForEach(store.dailyPlan.earlier) { day in
                                    Text(day.day.formatted).font(.caption).foregroundStyle(.secondary)
                                    ForEach(day.tasks) { item in row(item) }
                                }
                            }
                        }
                        if !store.dailyPlan.completed.isEmpty {
                            Section {
                                if completedExpanded { ForEach(store.dailyPlan.completed) { item in row(item) } }
                            } header: {
                                Button { completedExpanded.toggle() } label: {
                                    Label("Completed · \(store.dailyPlan.completed.count)", systemImage: completedExpanded ? "chevron.down" : "chevron.right")
                                }.buttonStyle(.plain).accessibilityLabel(completedExpanded ? "Collapse planned completed" : "Expand planned completed")
                            }
                        }
                    }
                }.listStyle(.inset).focused($listFocused).accessibilityIdentifier("today-task-list")
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.structureRevision)
                    .overlay { if store.unavailable { Text("Your plan is unavailable until recovery succeeds.").foregroundStyle(.secondary) } }
                    .onKeyPress(.space) {
                        guard listFocused, !store.unavailable, (NSApp.keyWindow?.firstResponder as? NSTextView)?.isEditable != true,
                              let selection, visibleIDs.contains(selection), let item = store.items.first(where: { $0.id == selection }) else { return .ignored }
                        store.setCompleted(id: item.id, isCompleted: !item.isCompleted); return .handled
                    }
                    .onKeyPress(.return) {
                        guard listFocused, !store.unavailable, (NSApp.keyWindow?.firstResponder as? NSTextView)?.isEditable != true,
                              let selection, visibleIDs.contains(selection) else { return .ignored }
                        detailID = selection; return .handled
                    }
            } details: {
                if let item = store.items.first(where: { $0.id == detailID }) {
                    VStack(alignment: .leading) {
                        if !visibleIDs.contains(item.id) { Text("This task is outside the visible plan.").font(.callout).foregroundStyle(.secondary) }
                        TaskDetailsView(item: item, store: store, close: { detailID = nil }).id(item.id)
                    }
                }
            }
        }.padding(24).frame(minWidth: 760, minHeight: 400)
            .sheet(isPresented: $picker) { PlanTaskPicker(store: store) }
            .onChange(of: ObjectIdentifier(store)) { _, _ in selection = nil; detailID = nil; drafts = TaskTitleDrafts(); picker = false }
    }
    private func row(_ item: TodoItem) -> some View {
        let index = store.dailyPlan.today.firstIndex { $0.id == item.id }
        return TaskRowView(item: item, store: store, selected: selection == item.id, selectionFocused: listFocused,
                    details: { selection = item.id; detailID = item.id }, preservedDraft: drafts.draft(for: item.id),
                    moveUp: index.map { $0 > 0 } == true ? { move(item.id, by: -1) } : nil,
                    moveDown: index.map { $0 < store.dailyPlan.today.count - 1 } == true ? { move(item.id, by: 1) } : nil).tag(item.id)
    }
    private func move(_ id: UUID, by offset: Int) {
        var ids = store.dailyPlan.today.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset); store.reorderToday(ids)
    }
}

private struct PlanTaskPicker: View {
    let store: TaskStore
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
                        if store.planToday(item.id) { dismiss() }
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
