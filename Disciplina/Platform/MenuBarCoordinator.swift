import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class PopoverMetrics {
    var maximumHeight: CGFloat = 600
    var focusToken = 0
}

@MainActor
final class MenuBarCoordinator: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let metrics = PopoverMetrics()
    private let store: TaskStore?
    private var appearanceObserver: NSKeyValueObservation?
    init(dependencies: AppDependencies, openMain: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.store = dependencies.store
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        if let store {
            popover.contentViewController = PopoverHostingController(rootView: MenuBarTaskView(store: store, metrics: metrics,
                openMain: { [weak self] in self?.close(); openMain() }, openSettings: { [weak self] in self?.close(); openSettings() }, close: { [weak self] in self?.close() }))
        } else {
            popover.contentViewController = PopoverHostingController(rootView: StartupFailureView(dependencies: dependencies).frame(width: 380))
        }
        item.button?.target = self; item.button?.action = #selector(toggle)
        item.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
        item.button?.imagePosition = .imageRight
        appearanceObserver = item.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.update() }
        }
        observe()
    }
    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }
    private func update() {
        guard let button = item.button else { return }
        guard let store else {
            button.title = "—"
            button.setAccessibilityLabel("Disciplina: Task count unavailable")
            button.toolTip = "Disciplina: Task count unavailable"
            return
        }
        let running = !store.unavailable ? store.timer.running : nil
        let title = running == nil ? store.menuBarStatus.text : DurationText.precise(store.timer.elapsedMilliseconds)
        let value = NSMutableAttributedString(string: running == nil ? title : "● \(title)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ])
        if running != nil {
            let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            value.addAttribute(.foregroundColor, value: dark ? NSColor(srgbRed: 231/255, green: 169/255, blue: 190/255, alpha: 1) : Theme.primary,
                               range: NSRange(location: 0, length: 1))
        }
        button.attributedTitle = value
        let name = running.flatMap { session in store.items.first { $0.id == session.taskID }?.title }
        let label = name.map { "Disciplina: Timing \($0)" } ?? store.menuBarStatus.accessibilityLabel
        button.setAccessibilityLabel(label)
        button.toolTip = name.map { "Timing \($0): \(title)" } ?? label
    }
    @objc private func toggle() {
        if popover.isShown { close(); return }
        guard let button = item.button else { return }
        metrics.maximumHeight = min(600, (button.window?.screen?.visibleFrame.height ?? 800) - 32)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    func popoverWillShow(_ notification: Notification) {
        configurePopoverWindow(popover.contentViewController?.view.window)
    }
    func popoverDidShow(_ notification: Notification) {
        guard let window = popover.contentViewController?.view.window else { return }
        configurePopoverWindow(window)
        window.orderFrontRegardless()
        window.makeKey()
        metrics.focusToken += 1
    }
    func close() { popover.performClose(nil) }
    func invalidate() { close(); NSStatusBar.system.removeStatusItem(item) }
}

/// Configure only the popover's window; never activate or order the task window.
@MainActor private func configurePopoverWindow(_ window: NSWindow?) {
    guard let window else { return }
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
    window.hidesOnDeactivate = false
}

@MainActor private final class PopoverHostingController<Content: View>: NSHostingController<Content> {
    override func viewWillAppear() {
        super.viewWillAppear()
        configurePopoverWindow(view.window)
    }
}
