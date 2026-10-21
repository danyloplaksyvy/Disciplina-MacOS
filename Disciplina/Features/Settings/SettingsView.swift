import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    let dependencies: AppDependencies
    @State private var shortcutWarning = false
    @State private var permanentID: UUID?
    private var login: LoginItemService { dependencies.login }
    var body: some View {
        Form {
            Section("Quick Capture") {
                KeyboardShortcuts.Recorder("Global shortcut:", name: .quickCapture) { _ in
                    Task { @MainActor in shortcutWarning = dependencies.shortcutUnavailable }
                }
                Text("Capture a task from any application while Disciplina is running.").font(.caption)
                if shortcutWarning { Label("Choose an available global shortcut.", systemImage: "exclamationmark.triangle") }
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                if login.status == .requiresApproval {
                    Text("Allow Disciplina in System Settings to finish enabling login launch.")
                    Button("Open Login Items") { login.openSystemSettings() }
                }
                if let error = login.errorMessage { Text(error).foregroundStyle(.red) }
            }
            if let store = dependencies.store { RecurringTasksSettings(store: store) }
            Section("Data & Recovery") {
                Button("Export Data…") { dependencies.exportData() }.disabled(dependencies.store == nil)
                Button("Restore Data…") { dependencies.chooseRestore() }
                Button("Show backup location") { dependencies.showBackups() }
                if let error = dependencies.dataError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if let store = dependencies.store {
                    Text("Recently Deleted").font(.headline)
                    if store.deleted.isEmpty { Text("No deleted tasks").foregroundStyle(.secondary) }
                    ForEach(store.deleted) { item in
                        HStack {
                            Text(item.title)
                            Spacer()
                            Button("Restore") { store.restore(item.id) }.accessibilityLabel("Restore \(item.title)")
                            Button("Delete permanently…", role: .destructive) { permanentID = item.id }
                        }
                    }
                    StoreErrorView(store: store)
                }
            }
            Text("Your tasks stay on this Mac. No account or internet connection required.").foregroundStyle(.secondary)
        }.formStyle(.grouped).padding().frame(width: 560, height: 580).tint(Theme.accent)
            .onAppear { login.refresh(); shortcutWarning = dependencies.shortcutUnavailable }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh(); shortcutWarning = dependencies.shortcutUnavailable }
            .alert("Permanently delete this task and its sessions?", isPresented: Binding(get: { permanentID != nil }, set: { if !$0 { permanentID = nil } })) {
                Button("Cancel", role: .cancel) { permanentID = nil }
                Button("Delete permanently", role: .destructive) {
                    if let id = permanentID, dependencies.store?.permanentlyDelete(id) == true { NSApp.windows.forEach { $0.undoManager?.removeAllActions() } }
                    permanentID = nil
                }
            } message: { Text("This action cannot be undone.") }
            .alert("Replace all local data?", isPresented: Binding(get: { dependencies.pendingRestore != nil }, set: { if !$0 { dependencies.pendingRestore = nil } })) {
                Button("Cancel", role: .cancel) { dependencies.pendingRestore = nil }
                Button("Restore", role: .destructive) { dependencies.restoreData() }
            } message: { Text("The running timer will pause. A local backup will be kept before the selected data replaces your tasks and sessions.") }
    }
}
