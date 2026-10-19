import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let quickCapture = Self("quickCapture", initial: .init(.space, modifiers: [.control, .option]))
}

@MainActor
final class HotkeyService {
    init(onCapture: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .quickCapture) { onCapture() }
    }
}
