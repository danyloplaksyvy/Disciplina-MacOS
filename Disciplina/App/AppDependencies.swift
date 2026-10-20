import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class AppDependencies {
    private(set) var store: TaskStore?
    private(set) var startupError: String?
    var dataError: String?
    let login = LoginItemService()
    private var persistence: PersistenceController?
    private var location: StoreLocation?
    private var capture: QuickCapturePanel?
    private var hotkeys: HotkeyService?
    private var menuBar: MenuBarCoordinator?
    private var ticker: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?
    private var openMain: (() -> Void)?
    private var openSettings: (() -> Void)?
    var pendingRestore: BackupDocument?
    var shortcutUnavailable: Bool { !KeyboardShortcuts.isEnabled(for: .quickCapture) || KeyboardShortcuts.getShortcut(for: .quickCapture) == nil }

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--verify-migration-copy"), args.indices.contains(index + 1) {
            do {
                let location = try StoreLocation(root: URL(fileURLWithPath: args[index + 1]))
                let persistence = try location.open()
                let state = try SwiftDataTaskRepository(context: persistence.container.mainContext).snapshot()
                try state.validate()
                print("Migration verification passed: \(state.tasks.count) tasks; \(state.sessions.count) sessions")
                exit(EXIT_SUCCESS)
            } catch {
                print("Migration verification failed: \(error.localizedDescription)")
                exit(EXIT_FAILURE)
            }
        }
        load()
    }
    func load() {
        guard store == nil else { return }
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                || ProcessInfo.processInfo.environment["DISCIPLINA_TESTING"] == "1"
            let persistence: PersistenceController
            if testing { persistence = try PersistenceController(inMemory: true) }
            else {
                let location = try StoreLocation(); self.location = location
                persistence = try location.open()
            }
            install(persistence, testing: testing)
            startupError = nil
        } catch {
            startupError = "Disciplina could not open your task database. Your existing data has not been replaced. \(error.localizedDescription)"
        }
    }
    private func install(_ persistence: PersistenceController, testing: Bool = false) {
        ticker?.cancel()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        let repository = SwiftDataTaskRepository(context: persistence.container.mainContext)
        let store = TaskStore(service: TaskService(repository: repository))
        self.persistence = persistence; self.store = store
        let capture = QuickCapturePanel(store: store); self.capture = capture
        if !testing, hotkeys == nil { hotkeys = HotkeyService { [weak self] in self?.showCapture() } }
        ticker = Task { @MainActor [weak store] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                store?.timer.tick()
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { _ = store?.pause(.systemSleep) }
        }
        AppCoordinator.prepareToQuit = { [weak store] in
            guard let store else { return true }
            if store.timer.failure != nil { store.reload(); if store.timer.failure != nil { return false } }
            return store.pause(.appQuit)
        }
        if let openMain, let openSettings { configureMenu(openMain: openMain, openSettings: openSettings) }
    }
    func configureMenu(openMain: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.openMain = openMain; self.openSettings = openSettings
        guard let store else { return }
        menuBar = nil
        menuBar = MenuBarCoordinator(store: store, openMain: openMain, openSettings: openSettings)
    }
    func showCapture() { menuBar?.close(); capture?.show() }
    func showBackups() {
        if let root = location?.root { NSWorkspace.shared.open(root) }
    }
    func exportData() {
        guard let store else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Disciplina-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let state = try store.service.repository.snapshot(); try state.validate()
            try BackupDocument(snapshot: state).encode().write(to: url, options: .atomic)
            dataError = nil
        } catch { dataError = error.localizedDescription }
    }
    func chooseRestore() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = try BackupDocument.decode(Data(contentsOf: url))
            _ = try document.validatedSnapshot()
            pendingRestore = document; dataError = nil
        } catch { dataError = error.localizedDescription }
    }
    func restoreData() {
        guard let document = pendingRestore else { return }
        pendingRestore = nil
        do {
            var snapshot = try document.validatedSnapshot(); snapshot.closeInterrupted()
            if let store, !store.pause() { throw DataError.timerUnavailable }
            let location = try self.location ?? StoreLocation(); self.location = location
            let replacement = try location.restore(snapshot, currentURL: persistence?.url)
            NSApp.windows.forEach { $0.undoManager?.removeAllActions() }
            install(replacement); startupError = nil; dataError = nil
        } catch { dataError = "Restore did not replace your current data. \(error.localizedDescription)" }
    }
}

import KeyboardShortcuts
import UniformTypeIdentifiers
