import AppKit
import SwiftUI
import Observation

@MainActor
final class MenuBarCoordinator: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: TaskStore
    private var appearanceObserver: NSKeyValueObservation?
    init(store: TaskStore, openMain: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.store = store
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarTaskView(store: store,
            openMain: { [weak self] in self?.close(); openMain() }, openSettings: { [weak self] in self?.close(); openSettings() }))
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func close() { popover.performClose(nil) }
    deinit {
        let item = item
        MainActor.assumeIsolated { NSStatusBar.system.removeStatusItem(item) }
    }
}
