import AppKit
import SwiftUI

/// Uses the native search editor, including its clear button and text Undo.
struct TaskSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    var escape: () -> Void
    var enter: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.placeholderString = "Search tasks"
        field.setAccessibilityLabel("Search tasks")
        field.setAccessibilityIdentifier("task-search")
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }
    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if field.focusToken != focusToken {
            field.focusToken = focusToken
            if focusToken > 0 { field.requestFocus() }
        }
    }
    final class Field: NSSearchField {
        var focusToken = 0
        private var wantsFocus = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(becameKey), name: NSWindow.didBecomeKeyNotification, object: window)
            }
            applyFocus()
        }
        @objc private func becameKey(_ notification: Notification) { applyFocus() }
        func requestFocus() { wantsFocus = true; applyFocus() }
        private func applyFocus() {
            guard wantsFocus, !isHiddenOrHasHiddenAncestor, let window, window.isKeyWindow else { return }
            if window.makeFirstResponder(self) { wantsFocus = false }
        }
    }
    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: TaskSearchField
        init(_ parent: TaskSearchField) { self.parent = parent }
        @objc func changed(_ field: NSSearchField) {
            guard parent.text != field.stringValue else { return }
            #if DEBUG
            SearchLatency.begin()
            #endif
            parent.text = field.stringValue
        }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { changed(field) }
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            if let field = notification.object as? NSSearchField,
               let editor = field.currentEditor() as? NSTextView { editor.allowsUndo = true }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.escape(); return true }
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.enter(); return true }
            return false
        }
    }
}

#if DEBUG
/// Opt-in local test instrumentation. Records durations only, never queries or task data.
@MainActor private enum SearchLatency {
    static var started: ContinuousClock.Instant?
    static var milliseconds: [Double] = []
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
        ProcessInfo.processInfo.arguments.contains("--seed-goals-performance")
    }
    static func begin() { if enabled { started = .now } }
    static func drewResults() {
        guard let start = started else { return }
        started = nil
        let duration = start.duration(to: .now).components
        milliseconds.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Disciplina-search-latency.json")
        if let data = try? JSONEncoder().encode(milliseconds) { try? data.write(to: url, options: .atomic) }
    }
}
struct SearchResultDrawProbe: NSViewRepresentable {
    let revision: Int
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        if view.revision != revision { view.revision = revision; view.needsDisplay = true }
    }
    final class Probe: NSView {
        var revision = -1
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if window?.isVisible == true { SearchLatency.drewResults() }
        }
    }
}
#endif
