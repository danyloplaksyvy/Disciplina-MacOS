import SwiftUI

struct ActivityView: View {
    let store: TaskStore
    var isVisible = true
    @State private var hasOpened = false
    @State private var selection = LocalDay(Date())
    @State private var weekly = false
    @State private var taskID: UUID?
    @State private var goalID: UUID?
    @State private var goalEditor = false
    @FocusState private var calendarFocused: Bool
    private var calendar: Calendar {
        var cal = LocalDay.calendar(); cal.firstWeekday = Calendar.current.firstWeekday
        cal.minimumDaysInFirstWeek = Calendar.current.minimumDaysInFirstWeek
        return cal
    }
    private var selectedDate: Date { (try? selection.date(calendar: calendar)) ?? Date() }
    private var period: DateInterval { calendar.dateInterval(of: weekly ? .weekOfYear : .month, for: selectedDate)! }
    private var selectedDays: [LocalDay] {
        if !weekly { return [selection] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: period.start) }.map { LocalDay($0, calendar: calendar) }
    }
    private var entries: [ActivitySummary.Entry] { selectedDays.flatMap { store.activity.days[$0] ?? [] } }
    var body: some View {
        let _ = store.calendarRevision
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if taskID != nil || goalID != nil {
                    Button("Back to Activity") { taskID = nil; goalID = nil }
                }
                Text("Activity").font(.largeTitle.bold()).accessibilityIdentifier("activity-heading"); Spacer()
            }
            StoreErrorView(store: store)
            if let id = taskID, let task = (store.items + store.deleted).first(where: { $0.id == id }) {
                if task.deletedAt == nil { TaskDetailsView(item: task, store: store, close: { taskID = nil }) }
                else { Text("This task is in Recently Deleted. Its recorded work is retained."); Spacer() }
            } else if let id = goalID, let goal = store.goals.first(where: { $0.id == id }) {
                GoalDetailView(goal: goal, store: store, edit: { goalEditor = true }, openTask: { taskID = $0 })
                    .sheet(isPresented: $goalEditor) { GoalEditorView(store: store, goal: goal) { _ in } }
            } else {
                Picker("Activity view", selection: $weekly) { Text("Calendar").tag(false); Text("Weekly Review").tag(true) }.pickerStyle(.segmented).frame(maxWidth: 360)
                HStack {
                    Button { movePeriod(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel(weekly ? "Previous week" : "Previous month")
                    Text(weekly ? "\(period.start.formatted(date: .abbreviated, time: .omitted)) – \(period.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))" : selectedDate.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Button { movePeriod(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel(weekly ? "Next week" : "Next month")
                    Spacer(); Button(weekly ? "This Week" : "Today") { selection = LocalDay(Date(), calendar: calendar) }
                }
                if weekly {
                    ScrollView { detail; weeklySummary }.accessibilityIdentifier("weekly-review")
                } else {
                    GeometryReader { geometry in
                        if geometry.size.width >= 900 {
                            HStack(alignment: .top, spacing: 24) { monthGrid.frame(width: geometry.size.width * 0.52); ScrollView { detail }.frame(maxWidth: .infinity) }
                        } else { ScrollView { monthGrid; Divider().padding(.vertical); detail } }
                    }
                }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: isVisible, initial: true) { _, visible in
                if visible && !hasOpened { selection = LocalDay(Date(), calendar: calendar); hasOpened = true }
            }
    }
    private func movePeriod(_ amount: Int) {
        if let date = calendar.date(byAdding: weekly ? .weekOfYear : .month, value: amount, to: selectedDate) { selection = LocalDay(date, calendar: calendar) }
    }
    private var monthGrid: some View {
        let month = calendar.dateInterval(of: .month, for: selectedDate)!
        let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: selectedDate)!.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recorded totals; legacy time uses session start dates.").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                Text(calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(0..<((offset + count + 6) / 7 * 7), id: \.self) { cell in
                if cell >= offset && cell < offset + count {
                    let date = calendar.date(byAdding: .day, value: cell - offset, to: month.start)!
                    let day = LocalDay(date, calendar: calendar)
                    let values = store.activity.days[day] ?? []
                    Button { selection = day; calendarFocused = true } label: {
                        VStack(spacing: 4) {
                            Text("\(day.day)").fontWeight(calendar.isDateInToday(date) ? .bold : .regular)
                            if !values.isEmpty { Text(store.unavailable ? "—" : totalText(values)).font(.caption2).lineLimit(1).minimumScaleFactor(0.7) }
                            else { Text(" ").font(.caption2) }
                            Circle().fill(values.isEmpty ? Color.clear : Theme.accent).frame(width: 4, height: 4)
                        }.frame(maxWidth: .infinity, minHeight: 58)
                            .background(selection == day ? Theme.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(calendar.isDateInToday(date) ? Theme.accent : .clear))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(day.formatted), \(store.unavailable ? "time unavailable" : totalText(values))\(selection == day ? ", selected" : "")")
                } else { Color.clear.frame(height: 58).accessibilityHidden(true) }
            }
        } }.focusable().focused($calendarFocused)
            .onKeyPress(.leftArrow) { moveDay(-1); return .handled }
            .onKeyPress(.rightArrow) { moveDay(1); return .handled }
            .onKeyPress(.upArrow) { moveDay(-7); return .handled }
            .onKeyPress(.downArrow) { moveDay(7); return .handled }
    }
    private func moveDay(_ delta: Int) { if let date = calendar.date(byAdding: .day, value: delta, to: selectedDate) { selection = LocalDay(date, calendar: calendar) } }
    private func totalText(_ values: [ActivitySummary.Entry]) -> String {
        var total: Int64 = 0
        for value in values { let sum = total.addingReportingOverflow(value.milliseconds); if sum.overflow { return "Duration exceeds display range" }; total = sum.partialValue }
        return total > 0 && total < 60000 ? "<1m" : DurationText.concise(total)
    }
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !weekly { Text(selection.formatted).font(.title3.bold()) }
            if store.unavailable { Text("Activity totals are unavailable until recovery succeeds.") }
            else {
                summaryLine("Measured", entries.filter { !$0.legacy && $0.provenance == .measured })
                summaryLine("Manual or corrected", entries.filter { !$0.legacy && $0.provenance != .measured })
                if entries.contains(where: \.legacy) {
                    summaryLine("Legacy time", entries.filter(\.legacy))
                    Text("Legacy time is assigned to the session start date. Its daily distribution was not recorded.").font(.caption).foregroundStyle(.secondary)
                }
                ActivityLiveDelta(store: store, days: selectedDays)
            }
            Text(store.unavailable ? "Tasks worked on unavailable" : "\(Set(entries.map(\.taskID)).count) tasks worked on").font(.caption)
            if entries.isEmpty && !store.unavailable { Text("No recorded work for this period.").foregroundStyle(.secondary) }
            goalBreakdown
            ForEach(entries.sorted { $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt }) { entry in
                let task = (store.items + store.deleted).first { $0.id == entry.taskID }
                VStack(alignment: .leading, spacing: 4) {
                    Button(task?.title ?? "Task") { taskID = entry.taskID }.buttonStyle(.link).accessibilityIdentifier("activity-task-\(entry.id)")
                    if task?.deletedAt != nil { Text("Deleted task").font(.caption) }
                    Text("\(entry.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(store.unavailable ? "—" : DurationText.precise(entry.milliseconds))").font(.caption)
                    Text(entry.legacy ? "Legacy · session start date" : entry.provenance == .manual ? "Manually added" : entry.provenance == .corrected ? "Corrected duration" : "Measured work").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func summaryLine(_ title: String, _ values: [ActivitySummary.Entry]) -> some View {
        HStack { Text(title); Spacer(); Text(totalText(values)).monospacedDigit() }
    }
    private var goalBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Work by goal").font(.headline)
            ForEach(store.goals.filter { goal in entries.contains { $0.goalID == goal.id } }) { goal in
                HStack { Button(goal.title) { goalID = goal.id }; Spacer(); Text(store.unavailable ? "—" : totalText(entries.filter { $0.goalID == goal.id })) }
            }
            HStack { Text("Unassigned"); Spacer(); Text(store.unavailable ? "—" : totalText(entries.filter { $0.goalID == nil })) }
            Text("Goal totals include any separately labeled legacy time above.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            let tasks = store.items.filter { $0.completedAt.map { $0 >= period.start && $0 < period.end } ?? false }.count
            let milestones = store.milestones.filter { $0.completedAt.map { $0 >= period.start && $0 < period.end } ?? false }.count
            Text("Currently completed during this week").font(.headline)
            Text(store.unavailable ? "Completion counts unavailable" : "\(tasks) tasks · \(milestones) milestones")
            Text("Reopening or deleting records changes these counts. Completion dates use your current local time zone.").font(.caption).foregroundStyle(.secondary)
            Text("Current active-goal progress").font(.headline)
            ForEach(store.goals(in: .active)) { goal in
                Button(goal.title) { goalID = goal.id }
                if !store.unavailable { GoalProgressView(progress: store.goalProgress.progress[goal.id] ?? .init()) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top)
    }
}

/// Observe presentation time in isolation; the calendar and historical review only
/// recompute when committed records or the selected period change.
private struct ActivityLiveDelta: View {
    let store: TaskStore
    let days: [LocalDay]
    var body: some View {
        let pending = days.reduce(Int64(0)) { $0 + (store.timer.pendingActivity[$1] ?? 0) }
        if !store.unavailable && pending > 0 {
            Text("Running · +\(DurationText.precise(pending)) since checkpoint").font(.caption).foregroundStyle(Theme.accent)
        }
    }
}
