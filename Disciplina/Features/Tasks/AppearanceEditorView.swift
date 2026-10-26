import SwiftUI

extension TaskAppearance {
    var color: Color {
        guard let tint, tint != "Burgundy" else { return Theme.accent }
        let pairs: [String: (UInt32, UInt32)] = ["Blue": (0x005AA7, 0x81BEFF), "Teal": (0x006D70, 0x74D6D3), "Green": (0x246B35, 0x8CD89D), "Orange": (0x994800, 0xFFC17A), "Purple": (0x7040A0, 0xCBA7F5)]
        guard let pair = pairs[tint] else { return Theme.accent }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? pair.1 : pair.0
            return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
        })
    }
}

struct AppearanceEditorView: View {
    let item: TodoItem
    let store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var appearance: TaskAppearance
    init(item: TodoItem, store: TaskStore) {
        self.item = item; self.store = store
        _appearance = State(initialValue: item.appearance ?? TaskAppearance())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Task appearance").font(.headline)
            Picker("Symbol", selection: $appearance.symbol) {
                Text("None").tag(nil as String?)
                ForEach(TaskAppearance.symbols, id: \.self) { symbol in
                    Label(symbol.replacingOccurrences(of: ".", with: " ").capitalized, systemImage: symbol).tag(Optional(symbol))
                }
            }
            .accessibilityIdentifier("appearance-symbol")
            Picker("Color", selection: $appearance.tint) {
                Text("App accent").tag(nil as String?)
                ForEach(TaskAppearance.tints, id: \.self) { tint in Text(tint).tag(Optional(tint)) }
            }.accessibilityIdentifier("appearance-color").disabled(appearance.symbol == nil)
            if let symbol = appearance.symbol { Label(item.title, systemImage: symbol).foregroundStyle(appearance.color).lineLimit(2) }
            Text("The current recurring task also updates the appearance of future occurrences.").font(.caption).foregroundStyle(.secondary)
            StoreErrorView(store: store)
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if store.setAppearance(taskID: item.id, appearance: appearance.symbol == nil ? nil : appearance) { dismiss() } }.keyboardShortcut(.defaultAction).disabled(store.unavailable)
            }
        }.padding(24).frame(width: 400)
    }
}
