import Foundation
import Observation

@MainActor @Observable
final class AppDependencies {
    private(set) var store: TaskStore?
    private(set) var startupError: String?
    let login = LoginItemService()
    private var persistence: PersistenceController?
    private var capture: QuickCapturePanel?
    private var hotkeys: HotkeyService?

    init() { load() }

    func load() {
        guard store == nil else { return }
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            let persistence = try PersistenceController(inMemory: testing)
            let repository = SwiftDataTaskRepository(context: persistence.container.mainContext)
            let store = TaskStore(service: TaskService(repository: repository))
            self.persistence = persistence
            self.store = store
            let capture = QuickCapturePanel(store: store)
            self.capture = capture
            if !testing { hotkeys = HotkeyService { [weak capture] in capture?.show() } }
            startupError = nil
        } catch {
            startupError = "Disciplina could not open your task database. Your existing data has not been replaced. \(error.localizedDescription)"
        }
    }

    func showCapture() { capture?.show() }
}
