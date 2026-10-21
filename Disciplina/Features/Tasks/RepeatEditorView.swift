import SwiftUI

struct RepeatEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: Int
    @State private var selected: Set<Int>
    @State private var failed = false
    let save: ([Int]) -> Bool
    init(weekdays: [Int], save: @escaping ([Int]) -> Bool) {
        _rule = State(initialValue: weekdays.isEmpty ? 0 : weekdays.sorted() == Array(1...7) ? 1 : weekdays.sorted() == Array(2...6) ? 2 : 3)
        _selected = State(initialValue: Set(weekdays)); self.save = save
    }
    private var weekdays: [Int] { rule == 0 ? [] : rule == 1 ? Array(1...7) : rule == 2 ? Array(2...6) : selected.sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Repeat task").font(.headline)
            Picker("Repeat", selection: $rule) {
                Text("Never").tag(0); Text("Every day").tag(1)
                Text("Weekdays").tag(2); Text("Selected weekdays").tag(3)
            }
            if rule == 3 {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { selected.contains(day) }, set: {
                        if $0 { selected.insert(day) } else { selected.remove(day) }
                    }))
                }
            }
            Text("The next task appears on the next eligible day after completion. Unfinished tasks do not repeat.").font(.caption).foregroundStyle(.secondary)
            if failed { Text("Could not save the repeat rule. Close this sheet and check the task error before retrying.").foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { if save(weekdays) { dismiss() } else { failed = true } }
                    .keyboardShortcut(.defaultAction).disabled(rule == 3 && selected.isEmpty)
            }
        }.padding(24).frame(width: 380)
    }
}

struct RecurringTasksSettings: View {
    let store: TaskStore
    @State private var editing: RecurrenceSeries?
    var body: some View {
        Section("Recurring Tasks") {
            let active = store.series.filter(\.enabled).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if active.isEmpty { Text("No repeating tasks").foregroundStyle(.secondary) }
            ForEach(active) { series in
                VStack(alignment: .leading, spacing: 6) {
                    Text(series.title).font(.headline)
                    Text(series.scheduleDescription)
                    if let day = series.pendingDay { Text("Next: \(day.formatted)") }
                    else if let task = store.items.first(where: { $0.id == series.currentTaskID }) { Text("Current: \(task.title)") }
                    HStack {
                        Button("Change schedule…") { editing = series }
                        Button("Stop repeating") { store.changeSeries(series.id, weekdays: nil) }
                    }.disabled(store.unavailable)
                }
            }
        }.sheet(item: $editing) { series in
            RepeatEditorView(weekdays: series.weekdays) { days in store.changeSeries(series.id, weekdays: days.isEmpty ? nil : days) }
        }
    }
}
