import AppKit

// Test companion for a real keyboard-focus check across two applications.
// The host must already be authorized to post events. Never request access.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let request = directory.appendingPathComponent("request")
let response = directory.appendingPathComponent("response")
let ready = directory.appendingPathComponent("ready")
guard CGPreflightPostEventAccess() else {
    fputs("Full-screen GUI test requires an event-authorized test host.\n", stderr)
    exit(1)
}
func key(_ code: CGKeyCode, unicode: String? = nil) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        if let unicode {
            let characters = Array(unicode.utf16)
            event?.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
        }
        event?.post(tap: .cghidEventTap)
    }
    Thread.sleep(forTimeInterval: 0.015)
}

try Data().write(to: ready)
while true {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    guard let action = try? String(contentsOf: request, encoding: .utf8) else { continue }
    try FileManager.default.removeItem(at: request)
    var result = "ok"
    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.TextEdit" {
        result = "TextEdit is no longer frontmost."
    } else if action == "escape" {
        key(53)
    } else if let id = UUID(uuidString: action) {
        for character in "Screen work " + id.uuidString.prefix(6) {
            key(0, unicode: String(character))
        }
        key(36)
    } else {
        result = "Unknown fixture request."
    }
    try result.write(to: response, atomically: true, encoding: .utf8)
}
