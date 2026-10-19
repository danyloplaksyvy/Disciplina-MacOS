import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    let login: LoginItemService
    var body: some View {
        Form {
            Section("Quick Capture") {
                KeyboardShortcuts.Recorder("Global shortcut:", name: .quickCapture)
                Text("Capture a task from any application while Disciplina is running.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                if login.status == .requiresApproval {
                    Text("Allow Disciplina in System Settings to finish enabling login launch.")
                    Button("Open Login Items") { login.openSystemSettings() }
                }
                if let error = login.errorMessage { Text(error).foregroundStyle(.red) }
            }
            Section {
                Text("Your tasks stay on this Mac. No account or internet connection required.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding().frame(width: 460)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }
}
