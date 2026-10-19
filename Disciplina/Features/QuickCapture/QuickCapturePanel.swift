import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class CaptureDraft {
    var title = ""
    var focusToken = 0
}

struct QuickCaptureView: View {
    let store: TaskStore
    @Bindable var draft: CaptureDraft
    let save: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Quick Capture", systemImage: "plus.circle").font(.headline)
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            }
            TextField("What needs to get done?", text: $draft.title)
                .font(.title2).textFieldStyle(.plain)
                .focused($focused).onSubmit(save)
                .accessibilityLabel("Capture task").accessibilityIdentifier("capture-task")
            StoreErrorView(store: store)
            HStack {
                Text("↵ Save task   ·   Esc Cancel").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save task", action: save)
                    .disabled(store.needsRefresh || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 500)
            .onAppear { focused = true }
            .onChange(of: draft.focusToken) { focused = true }
            .onExitCommand(perform: cancel)
    }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickCapturePanel: NSObject, NSWindowDelegate {
    private let store: TaskStore
    private let draft = CaptureDraft()
    private var panel: CapturePanel?
    private var previousApp: NSRunningApplication?

    init(store: TaskStore) { self.store = store }

    func show() {
        if panel?.isVisible != true {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        if panel == nil {
            let panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 180),
                                     styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.title = "Quick Capture"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: QuickCaptureView(store: store, draft: draft,
                save: { [weak self] in self?.submit() }, cancel: { [weak self] in self?.cancel() }))
            self.panel = panel
        }
        guard let panel else { return }
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        }
        draft.focusToken += 1
        panel.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        panel?.orderOut(nil) // Preserve the draft when clicking away.
    }

    private func submit() {
        guard store.create(title: draft.title) else { return }
        draft.title = ""
        dismissAndRestoreFocus()
    }
    private func cancel() { draft.title = ""; dismissAndRestoreFocus() }
    private func dismissAndRestoreFocus() {
        panel?.orderOut(nil)
        if let previousApp, !previousApp.isTerminated { previousApp.activate(options: []) }
        previousApp = nil
    }
}
