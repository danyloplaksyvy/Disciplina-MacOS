import AppKit
import SwiftUI

/// Focus is requested on actual key-window activation, never on a delay.
struct CaptureTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder = "Add a task…"
    var identifier = "new-task"
    var focusToken: Int
    var submit: () -> Void
    var cancel: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.placeholderString = placeholder
        field.isBordered = true; field.isBezeled = true; field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 14)
        field.delegate = context.coordinator
        field.setAccessibilityLabel(identifier == "capture-task" ? "Capture task" : "New task")
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.setAccessibilityIdentifier(identifier)
        return field
    }
    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if field.focusToken != focusToken { field.focusToken = focusToken; field.requestFocus() }
    }
    final class Field: NSTextField {
        var focusToken = -1
        private var observer: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestFocus() }
            }
            requestFocus()
        }
        func requestFocus() {
            guard let window, window.isKeyWindow else { return }
            if window.firstResponder !== currentEditor() { window.makeFirstResponder(self) }
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CaptureTextField
        init(_ parent: CaptureTextField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.submit(); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.cancel(); return true }
            return false
        }
    }
}
