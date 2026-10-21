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
    @State private var validationError: String?
    init(taskID: UUID, session: WorkSession?, store: TaskStore) {
        self.taskID = taskID; self.session = session; self.store = store
        _duration = State(initialValue: SessionDuration(milliseconds: session?.accumulatedMilliseconds ?? 0))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(session == nil ? "Add time" : "Edit duration").font(.headline)
            if session == nil { DatePicker("Work date", selection: $date) }
            HStack {
                field("Hours", text: $duration.hours)
                field("Minutes", text: $duration.minutes)
                field("Seconds", text: $duration.seconds)
            }
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
    private func save() {
        do {
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
