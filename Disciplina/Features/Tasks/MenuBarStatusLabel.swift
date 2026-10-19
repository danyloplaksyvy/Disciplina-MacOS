import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    let status: MenuBarStatus

    var body: some View {
        Image(nsImage: MenuBarStatusImage.make(status))
            .accessibilityLabel(status.accessibilityLabel)
            .help(status.accessibilityLabel)
    }
}

/// MenuBarExtra's native bridge reorders separate Text/Image views to image-first.
/// A single resolution-independent template image preserves text-first ordering
/// while macOS supplies the correct tint for light, dark, and selected appearances.
@MainActor
enum MenuBarStatusImage {
    static func make(_ status: MenuBarStatus) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
                                                   weight: .regular)
        let title = NSAttributedString(string: status.text, attributes: [
            .font: font, .foregroundColor: NSColor.black
        ])
        let textSize = title.size()
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
            .applying(.init(paletteColors: [.black]))
        let symbol = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let symbolSize = symbol?.size ?? .zero
        let gap: CGFloat = symbol == nil ? 0 : 4
        let textWidth = ceil(textSize.width)
        let height = ceil(max(textSize.height, symbolSize.height))
        let size = NSSize(width: textWidth + gap + ceil(symbolSize.width), height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            title.draw(at: NSPoint(x: 0, y: (height - textSize.height) / 2))
            symbol?.draw(in: NSRect(x: textWidth + gap, y: (height - symbolSize.height) / 2,
                                   width: symbolSize.width, height: symbolSize.height))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = status.accessibilityLabel
        return image
    }
}
