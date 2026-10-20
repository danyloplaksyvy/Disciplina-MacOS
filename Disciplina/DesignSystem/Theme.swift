import AppKit
import SwiftUI

enum Theme {
    static let primary = NSColor(srgbRed: 122/255, green: 40/255, blue: 73/255, alpha: 1)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 231/255, green: 169/255, blue: 190/255, alpha: 1) : primary
    })
}
extension TaskStatus {
    var title: String { switch self { case .todo: "To Do"; case .inProgress: "In Progress"; case .completed: "Completed" } }
}
