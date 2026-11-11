import AppKit
import Observation

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    static var launchedAtLogin: Bool {
        ProcessInfo.processInfo.arguments.contains("--simulate-login-launch") || NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
    static var showMain: (() -> Void)?
    static var startServices: (() -> Void)?
    private var quietLaunch = false
    static var prepareToQuit: (() -> Bool)?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.prepareToQuit?() == false else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Could not save the final timer checkpoint"
        alert.informativeText = "Retry saving, or quit using the last saved checkpoint. Unsaved time will not be recovered."
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Quit with saved time")
        if alert.runModal() == .alertSecondButtonReturn { return .terminateNow }
        return Self.prepareToQuit?() == true ? .terminateNow : .terminateCancel
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        quietLaunch = Self.launchedAtLogin
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.startServices?()
        if !quietLaunch { Self.showMain?() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        quietLaunch = false
        Self.showMain?()
        return false
    }
}

@MainActor
enum WindowCoordinator {
    static func activate() { NSApp.activate() }
}


/// The main window handles Find before a focused control can consume the shortcut.
@MainActor
final class TaskWindow: NSWindow {
    weak var taskSearch: TaskSearchField.Field?
    private var protectsSearchEditor = false

    func findTasks() {
        guard isKeyWindow, attachedSheet == nil else { return }
        NotificationCenter.default.post(name: .focusTaskSearch, object: nil)
        contentView?.layoutSubtreeIfNeeded()
        protectsSearchEditor = true
        taskSearch?.requestFocus()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .shift, .option])
        if isKeyWindow, attachedSheet == nil, modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            findTasks()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            protectsSearchEditor = false
        case .keyDown where [36, 48, 53, 76].contains(event.keyCode):
            // Return, Tab, Escape and keypad Enter can explicitly leave search.
            protectsSearchEditor = false
        default: break
        }
        super.sendEvent(event)
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        // Restoring a retained list's selection can request outline focus after
        // Find has already selected the field editor. Honor the user's Find.
        if protectsSearchEditor, responder is NSOutlineView,
           let editor = taskSearch?.currentEditor(), firstResponder === editor {
            return false
        }
        return super.makeFirstResponder(responder)
    }
}

/// Commands must observe native focus; reading NSApp.keyWindow in a SwiftUI body
/// alone can leave a shortcut disabled after a sheet or another window closes.
@MainActor @Observable
final class WindowCommandState: NSObject {
    private(set) var canFindTasks = false

    override init() {
        super.init()
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification,
                     NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            center.addObserver(self, selector: #selector(focusChanged(_:)), name: name, object: nil)
        }
        refresh()
    }

    @objc private func focusChanged(_ notification: Notification) {
        if notification.name == NSWindow.didBecomeKeyNotification {
            let window = notification.object as? NSWindow
            canFindTasks = window?.identifier?.rawValue == "main" && window?.attachedSheet == nil
        } else if notification.name == NSApplication.didResignActiveNotification
                    || notification.name == NSWindow.willBeginSheetNotification
                    || notification.name == NSWindow.didResignKeyNotification {
            canFindTasks = false
        } else {
            refresh()
        }
    }

    private func refresh() {
        let app = NSApplication.shared
        canFindTasks = app.isActive && app.keyWindow?.identifier?.rawValue == "main"
            && app.keyWindow?.attachedSheet == nil
    }
}
