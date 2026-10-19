import SwiftUI

@main
struct DisciplinaApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var coordinator
    @State private var dependencies = AppDependencies()
    @State private var popoverPresented = false
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Disciplina", id: "main") {
            if let store = dependencies.store {
                MainTaskWindowView(store: store)
            } else {
                StartupFailureView(dependencies: dependencies)
            }
        }
        .defaultSize(width: 860, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    showMain()
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .focusNewTask, object: nil) }
                }.keyboardShortcut("n")
                Button("Open Task Window", action: showMain).keyboardShortcut("o")
                Button("Quick Capture") { dependencies.showCapture() }
            }
        }
        MenuBarExtra("Disciplina", systemImage: "checkmark.circle", isInserted: .constant(true)) {
            if let store = dependencies.store {
                MenuBarTaskView(store: store, isPresented: $popoverPresented, openMain: showMain)
                    .onAppear { popoverPresented = true }
                    .onDisappear { popoverPresented = false }
            } else {
                StartupFailureView(dependencies: dependencies).frame(width: 360)
            }
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsView(login: dependencies.login) }
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
            Button("Quit Disciplina") { NSApp.terminate(nil) }
        }.padding(24).frame(minWidth: 300, minHeight: 220)
    }
}
