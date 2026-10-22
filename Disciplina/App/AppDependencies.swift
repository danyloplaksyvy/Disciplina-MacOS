import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class AppDependencies {
    private(set) var store: TaskStore?
    private(set) var startupError: String?
    var dataError: String?
    let login = LoginItemService()
    private var testingMode = false
    private var simulatedFailureConsumed = false
    private var persistence: PersistenceController?
    private var location: StoreLocation?
    private var capture: QuickCapturePanel?
    private var hotkeys: HotkeyService?
    private var menuBar: MenuBarCoordinator?
    private var mainWindow: NSWindowController?
    private var ticker: Task<Void, Never>?
    private var dayTimer: Timer?
    private var calendarObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var sleepObserver: NSObjectProtocol?
    private var openMain: (() -> Void)?
    private var openSettings: (() -> Void)?
    private var lastAnnouncement: String?
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
        AppCoordinator.showMain = { [weak self] in self?.showMain() }
        AppCoordinator.startServices = { [weak self] in self?.startServices() }
    }
    func startServices() {
        load()
        ensureMenu()
        if hotkeys == nil && (!testingMode || ProcessInfo.processInfo.arguments.contains("--enable-test-shortcut")) {
            hotkeys = HotkeyService { [weak self] in self?.showCapture() }
        }
    }
    func load() {
        guard store == nil else { return }
        defer { if store == nil, menuBar != nil { updateMenuContent() } }

        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                || ProcessInfo.processInfo.environment["DISCIPLINA_TESTING"] == "1"
            testingMode = testing
            if testing && !simulatedFailureConsumed && ProcessInfo.processInfo.arguments.contains("--simulate-storage-failure") {
                simulatedFailureConsumed = true
                throw CocoaError(.fileReadCorruptFile)
            }
            let persistence: PersistenceController
            if testing {
                location = try StoreLocation(root: FileManager.default.temporaryDirectory.appendingPathComponent("Disciplina-ui-\(UUID().uuidString)"))
                persistence = try PersistenceController(inMemory: true)
            }
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
        observeAnnouncements(store)
        self.capture?.invalidate()
        let capture = QuickCapturePanel(store: store); self.capture = capture
        if (!testing || ProcessInfo.processInfo.arguments.contains("--enable-test-shortcut")), hotkeys == nil {
            hotkeys = HotkeyService { [weak self] in self?.showCapture() }
        }
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
            guard store.timer.running != nil || store.timer.failure != nil else { return true }
            if store.unavailable { store.reload(); if store.unavailable { return false } }
            return store.pause(.appQuit)
        }
        observeCalendar()
        store.calendarChanged()
        if menuBar != nil { updateMenuContent() }
    }
    private func observeAnnouncements(_ store: TaskStore) {
        withObservationTracking {
            let message = store.timer.failure ?? store.errorMessage ?? store.notice
            if let message, message != lastAnnouncement {
                NSAccessibility.post(element: NSApp!, notification: .announcementRequested,
                                     userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
            lastAnnouncement = message
        } onChange: { [weak self, weak store] in
            Task { @MainActor in
                guard let self, let store, self.store === store else { return }
                self.observeAnnouncements(store)
            }
        }
    }

    func configureMenu(openMain: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.openMain = openMain; self.openSettings = openSettings
    }
    func showMain() {
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Disciplina"; window.identifier = NSUserInterfaceItemIdentifier("main")
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 760, height: 400)
            window.collectionBehavior = [.fullScreenPrimary]
            window.contentViewController = NSHostingController(rootView: MainWindowContent(dependencies: self,
                openSettings: { [weak self] in self?.openSettings?() }))
            // NSHostingController initially proposes its minimum size. Apply the
            // intended initial content size after installing it, once per window.
            let available = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1100, height: 700)
            window.setContentSize(NSSize(width: min(1100, available.width), height: min(700, available.height - 40)))
            window.center()
            mainWindow = NSWindowController(window: window)
        }
        mainWindow?.showWindow(nil)
        mainWindow?.window?.makeKeyAndOrderFront(nil)
        WindowCoordinator.activate()
    }
    private func ensureMenu() {
        guard menuBar == nil else { return }
        menuBar = MenuBarCoordinator(dependencies: self,
            openMain: { [weak self] in self?.openMain?() }, openSettings: { [weak self] in self?.openSettings?() })
    }
    private func updateMenuContent() {
        menuBar?.setContent(dependencies: self,
            openMain: { [weak self] in self?.openMain?() }, openSettings: { [weak self] in self?.openSettings?() })
    }
    func showCapture() {
        menuBar?.close()
        if let capture { capture.show() } else { openMain?() }
    }
    private func observeCalendar() {
        for (center, observer) in calendarObservers { center.removeObserver(observer) }
        calendarObservers = []
        let events: [(NotificationCenter, Notification.Name)] = [
            (.default, NSApplication.didBecomeActiveNotification),
            (.default, .NSSystemTimeZoneDidChange),
            (.default, .NSSystemClockDidChange),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)]
        for (center, name) in events {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.calendarEvent() }
            }
            calendarObservers.append((center, observer))
        }
        scheduleMidnight()
    }
    private func calendarEvent() { store?.calendarChanged(); scheduleMidnight() }
    private func scheduleMidnight() {
        dayTimer?.invalidate()
        let calendar = LocalDay.calendar()
        guard let next = calendar.dateInterval(of: .day, for: Date())?.end else { return }
        dayTimer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.calendarEvent() }
        }
        if let dayTimer { RunLoop.main.add(dayTimer, forMode: .common) }
    }
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
            install(replacement, testing: testingMode); startupError = nil; dataError = nil
        } catch { dataError = "Restore did not replace your current data. \(error.localizedDescription)" }
    }
}

import KeyboardShortcuts
import UniformTypeIdentifiers

private struct MainWindowContent: View {
    let dependencies: AppDependencies
    let openSettings: () -> Void
    var body: some View {
        Group {
            if let store = dependencies.store {
                MainNavigationView(store: store, openSettings: openSettings).id(ObjectIdentifier(store))
            } else { StartupFailureView(dependencies: dependencies) }
        }
    }
}
