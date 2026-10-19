import SwiftUI

struct MenuBarStatusLabel: View {
    let status: MenuBarStatus

    var body: some View {
        HStack(spacing: 4) {
            Text(status.text).monospacedDigit()
            Image(systemName: "checkmark.circle")
        }
        .fixedSize()
        .accessibilityLabel(status.accessibilityLabel)
        .help(status.accessibilityLabel)
    }
}
