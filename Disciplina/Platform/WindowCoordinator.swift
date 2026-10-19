import AppKit

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    static var launchedAtLogin: Bool {
        NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
    private var quietLaunch = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        quietLaunch = Self.launchedAtLogin
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if quietLaunch {
            NSApp.hide(nil)
            DispatchQueue.main.async {
                NSApp.windows.filter { $0.identifier?.rawValue == "main" }.forEach { $0.close() }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true // SwiftUI's unique Window scene handles Dock reopen.
    }
}

@MainActor
enum WindowCoordinator {
    static func activate() { NSApp.activate(ignoringOtherApps: true) }
}
