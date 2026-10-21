import AppKit

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    static var launchedAtLogin: Bool {
        ProcessInfo.processInfo.arguments.contains("--simulate-login-launch") || NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
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
        if quietLaunch {
            DispatchQueue.main.async {
                NSApp.windows.filter { $0.identifier?.rawValue == "main" }.forEach { $0.close() }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        quietLaunch = false
        return true // SwiftUI's unique Window scene handles Dock reopen.
    }
}

@MainActor
enum WindowCoordinator {
    static func activate() { NSApp.activate() }
}
