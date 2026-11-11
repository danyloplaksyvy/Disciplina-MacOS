import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class PopoverMetrics {
    var maximumHeight: CGFloat = 600
    var focusToken = 0
}

@MainActor
final class MenuBarCoordinator: NSObject, NSWindowDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = StatusPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
    private var anchor: NSRect?
    private var display: NSScreen?
    private var localMouse: Any?
    private var outsideMouse: Any?
    private let metrics = PopoverMetrics()
    private var store: TaskStore?
    private var appearanceObserver: NSKeyValueObservation?
    init(dependencies: AppDependencies, openMain: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.store = dependencies.store
        super.init()
        panel.identifier = .init("status-panel")
        panel.title = "Disciplina menu"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        setContent(dependencies: dependencies, openMain: openMain, openSettings: openSettings)
        item.button?.target = self; item.button?.action = #selector(toggle)
        item.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
        item.button?.imagePosition = .imageRight
        appearanceObserver = item.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.update() }
        }
        observe()
    }
    func setContent(dependencies: AppDependencies, openMain: @escaping () -> Void, openSettings: @escaping () -> Void) {
        close()
        store = dependencies.store
        if let store {
            host(MenuBarTaskView(store: store, metrics: metrics,
                openMain: { [weak self] in self?.close(); openMain() }, openSettings: { [weak self] in self?.close(); openSettings() }, close: { [weak self] in self?.close() }))
        } else {
            host(StartupFailureView(dependencies: dependencies).frame(width: 380))
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
    private func host<Content: View>(_ content: Content) {
        let view = StatusContent(rootView: content.background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 10)))
        view.sizingOptions = [.intrinsicContentSize]
        view.sizeChanged = { [weak self] in self?.positionPanel() }
        panel.contentView = view
    }

    private var buttonRect: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @objc private func toggle() {
        if panel.isVisible { close(); return }
        guard let rect = buttonRect,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }) else { return }
        display = screen
        anchor = rect
        metrics.maximumHeight = min(600, screen.visibleFrame.height - 32)
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        item.button?.highlight(true)
        observeOutsideClicks()
    }

    private func positionPanel() {
        guard let anchor, let display, let content = panel.contentView else { return }
        let available = display.visibleFrame
        let width = min(380, available.width)
        let top = min(anchor.minY - 2, available.maxY)
        let height = min(max(1, ceil(content.fittingSize.height)), metrics.maximumHeight, max(1, top - available.minY))
        let x = min(max(available.minX, anchor.midX - width / 2), available.maxX - width)
        let frame = NSRect(x: x.rounded(), y: top - height, width: width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    func windowDidBecomeKey(_ notification: Notification) { metrics.focusToken += 1 }

    private func observeOutsideClicks() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouse = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            if let self, event.window !== self.panel, event.window?.parent !== self.panel,
               self.buttonRect?.contains(NSEvent.mouseLocation) != true { self.close() }
            return event
        }
        outsideMouse = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            guard let self, self.buttonRect?.contains(NSEvent.mouseLocation) != true else { return }
            self.close()
        }
    }

    @objc private func spaceChanged() { close() }
    func close() {
        if let localMouse { NSEvent.removeMonitor(localMouse) }
        if let outsideMouse { NSEvent.removeMonitor(outsideMouse) }
        localMouse = nil
        outsideMouse = nil
        anchor = nil
        display = nil
        panel.orderOut(nil)
        item.button?.highlight(false)
    }
    func invalidate() {
        close()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NSStatusBar.system.removeStatusItem(item)
    }
}

private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// SwiftUI changes its intrinsic height when a task or Undo row appears.
private final class StatusContent<Content: View>: NSHostingView<Content> {
    var sizeChanged: (() -> Void)?
    private var pendingResize = false
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !pendingResize, sizeChanged != nil else { return }
        pendingResize = true
        DispatchQueue.main.async { [weak self] in
            self?.pendingResize = false
            self?.sizeChanged?()
        }
    }
}
