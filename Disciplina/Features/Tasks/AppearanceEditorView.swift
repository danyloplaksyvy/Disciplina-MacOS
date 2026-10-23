import SwiftUI

extension TaskAppearance {
    var color: Color {
        switch tint {
        case "Blue": .blue
        case "Teal": .teal
        case "Green": .green
        case "Orange": .orange
        case "Purple": .purple
        default: Theme.accent
        }
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
            Picker("Color", selection: $appearance.tint) {
                Text("App accent").tag(nil as String?)
                ForEach(TaskAppearance.tints, id: \.self) { tint in Text(tint).tag(Optional(tint)) }
            }
            if let symbol = appearance.symbol { Label(item.title, systemImage: symbol).foregroundStyle(appearance.color).lineLimit(2) }
            Text("The current recurring task also updates the appearance of future occurrences.").font(.caption).foregroundStyle(.secondary)
            StoreErrorView(store: store)
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if store.setAppearance(taskID: item.id, appearance: appearance.symbol == nil && appearance.tint == nil ? nil : appearance) { dismiss() } }.keyboardShortcut(.defaultAction).disabled(store.unavailable)
            }
        }.padding(24).frame(width: 400)
    }
}
