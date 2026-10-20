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
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            guard let window else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey),
                                                   name: NSWindow.didBecomeKeyNotification, object: window)
            requestFocus()
        }
        @objc private func windowBecameKey(_ notification: Notification) { requestFocus() }
        func requestFocus() {
            guard let window, window.isKeyWindow else { return }
            if currentEditor() == nil || window.firstResponder !== currentEditor() { window.makeFirstResponder(self) }
        }
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
