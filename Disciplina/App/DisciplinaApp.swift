import SwiftUI

@main
struct DisciplinaApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var coordinator
    @State private var dependencies = AppDependencies()
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        let _ = dependencies.configureMenu(openMain: showMain, openSettings: { openSettings(); WindowCoordinator.activate() })
        Window("Disciplina", id: "main") {
            Group {
            if let store = dependencies.store {
                MainTaskWindowView(store: store)
                    .id(ObjectIdentifier(store))

            } else {
                StartupFailureView(dependencies: dependencies)
            }
            }
        }
        .loginLaunchBehavior()
        .defaultSize(width: 860, height: 600)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
                        editor.undoManager?.undo()
                    } else { dependencies.store?.undoDelete() }
                }.keyboardShortcut("z")
                Button("Redo") {
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
                        editor.undoManager?.redo()
                    }
                }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    showMain()
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .focusNewTask, object: nil) }
                }.keyboardShortcut("n")
                Button("Open Task Window", action: showMain).keyboardShortcut("o")
                Button("Quick Capture") { dependencies.showCapture() }
            }
        }
        Settings { SettingsView(dependencies: dependencies) }
    }

    private func showMain() {
        openWindow(id: "main")
        WindowCoordinator.activate()
    }
}

struct StartupFailureView: View {
    let dependencies: AppDependencies
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Unable to open tasks", systemImage: "exclamationmark.triangle").font(.headline)
            Text(dependencies.startupError ?? "Please retry opening the database.")
                .textSelection(.enabled)
            Button("Retry") { dependencies.load() }
            Button("Show backup location") { dependencies.showBackups() }
            Button("Restore from JSON…") { dependencies.chooseRestore() }
            if let error = dependencies.dataError { Text(error).foregroundStyle(.red) }
            Button("Quit Disciplina") { NSApp.terminate(nil) }
        }.padding(24).frame(minWidth: 300, minHeight: 220)
            .alert("Replace local data?", isPresented: Binding(get: { dependencies.pendingRestore != nil }, set: { if !$0 { dependencies.pendingRestore = nil } })) {
                Button("Cancel", role: .cancel) { dependencies.pendingRestore = nil }
                Button("Restore", role: .destructive) { dependencies.restoreData() }
            } message: { Text("The validated backup will replace local data. Existing store files remain available for recovery.") }
    }
}

private extension Scene {
    @SceneBuilder func loginLaunchBehavior() -> some Scene {
        if #available(macOS 15, *) {
            self.defaultLaunchBehavior(AppCoordinator.launchedAtLogin ? .suppressed : .automatic)
        } else { self }
    }
}
