import SwiftUI

struct SessionEditorRequest: Identifiable {
    let id = UUID()
    let session: WorkSession?
}

struct SessionEditorView: View {
    let taskID: UUID
    let session: WorkSession?
    let store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var duration: SessionDuration
    @State private var date = Date()
    @State private var daily: [SessionDuration]
    @State private var validationError: String?
    init(taskID: UUID, session: WorkSession?, store: TaskStore) {
        self.taskID = taskID; self.session = session; self.store = store
        _daily = State(initialValue: (session?.allocations ?? []).map { SessionDuration(milliseconds: $0.milliseconds) })
        _duration = State(initialValue: SessionDuration(milliseconds: session?.accumulatedMilliseconds ?? 0))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(session == nil ? "Add time" : "Edit duration").font(.headline)
            if session == nil { DatePicker("Work date", selection: $date) }
            if let values = session?.allocations, values.count > 1 {
                ScrollView {
                    ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                        VStack(alignment: .leading) {
                            Text(value.day.formatted + " · " + value.timeZoneID).font(.caption)
                            HStack { field("Hours", text: $daily[index].hours); field("Minutes", text: $daily[index].minutes); field("Seconds", text: $daily[index].seconds) }
                        }
                    }
                }.frame(maxHeight: 300)
                Text("Total: " + dailyTotal).monospacedDigit()
            } else { HStack {
                field("Hours", text: $duration.hours)
                field("Minutes", text: $duration.minutes)
                field("Seconds", text: $duration.seconds)
            } }
            Text(session == nil ? "This records a manually entered duration, not a measured interval." : "Recorded dates stay unchanged. The timer will remain paused.")
                .font(.caption).foregroundStyle(.secondary)
            if let validationError { Text(validationError).foregroundStyle(.red).accessibilityIdentifier("duration-error") }
            StoreErrorView(store: store)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(store.unavailable)
            }
        }.padding(24).frame(width: 420).tint(Theme.accent)
    }
    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("duration-\(label.lowercased())")
        }
    }
    private var dailyTotal: String {
        do {
            var total: Int64 = 0
            for value in daily { let sum = total.addingReportingOverflow(try value.milliseconds()); guard !sum.overflow else { return "Invalid duration" }; total = sum.partialValue }
            return DurationText.precise(total)
        } catch { return "Invalid duration" }
    }
    private func save() {
        do {
            if let session, let values = session.allocations, values.count > 1 {
                var amounts: [UUID: Int64] = [:]
                for (i, value) in values.enumerated() { amounts[value.id] = daily[i] == SessionDuration(milliseconds: value.milliseconds) ? value.milliseconds : try daily[i].milliseconds() }
                if store.editDailySession(taskID: taskID, sessionID: session.id, amounts: amounts) { dismiss() }
                return
            }
            let parsed = try duration.milliseconds()
            let saved: Bool
            if let session {
                let value = duration == SessionDuration(milliseconds: session.accumulatedMilliseconds) ? session.accumulatedMilliseconds : parsed
                saved = store.editSession(taskID: taskID, sessionID: session.id, milliseconds: value)
            } else {
                guard parsed > 0 else { throw SessionEditError.invalidDuration }
                saved = store.addSession(taskID: taskID, date: date, milliseconds: parsed)
            }
            if saved { dismiss() }
        } catch { validationError = error.localizedDescription }
    }
}

/// Explicit constraints prevent AppKit's split sizing from compressing task rows.
struct TaskDetailSplit<ListContent: View, DetailContent: View>: View {
    let showsDetails: Bool
    @ViewBuilder let list: () -> ListContent
    @ViewBuilder let details: () -> DetailContent
    @State private var fraction: CGFloat = 0.55
    @State private var dragOrigin: CGFloat?
    var body: some View {
        GeometryReader { geometry in
            let usable = max(660, geometry.size.width - 9)
            let width = min(max(360, usable * fraction), usable - 300)
            HStack(spacing: 0) {
                list().frame(width: showsDetails ? width : geometry.size.width)
                if showsDetails {
                    Divider().frame(width: 9).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            if dragOrigin == nil { dragOrigin = width }
                            fraction = min(max(360, (dragOrigin ?? width) + value.translation.width), usable - 300) / usable
                        }.onEnded { _ in dragOrigin = nil })
                        .accessibilityLabel("Task list width")
                        .accessibilityValue("\(Int(width)) points")
                        .accessibilityAdjustableAction { direction in
                            let delta: CGFloat = direction == .increment ? 20 : -20
                            fraction = min(max(360, width + delta), usable - 300) / usable
                        }
                    details().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
