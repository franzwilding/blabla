import SwiftUI

/// The icon that lives in the macOS menu bar.
/// Shows a colored dot: orange = dictating, red = transcribing.
struct MenuBarLabel: View {
    let isCapturing: Bool
    let labelSources: Bool
    let mode: AppState.CaptureMode

    var body: some View {
        Image(nsImage: buildIcon())
    }

    private func buildIcon() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let waveform = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Blabla")!
            .withSymbolConfiguration(config)!

        guard isCapturing else {
            waveform.isTemplate = true
            return waveform
        }

        let dotDiameter: CGFloat = 5
        let wSize = waveform.size

        let combined = NSImage(size: wSize, flipped: false) { rect in
            // Draw waveform, then tint with system label color for light/dark support
            waveform.draw(in: rect)
            NSColor.labelColor.setFill()
            rect.fill(using: .sourceAtop)

            // Draw colored dot overlaid at bottom-right corner
            let dotColor: NSColor = self.labelSources ? .systemRed : .systemOrange
            dotColor.setFill()
            let dotX = rect.width - dotDiameter
            let dotY: CGFloat = 0
            NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: dotDiameter, height: dotDiameter)).fill()

            return true
        }
        combined.isTemplate = false
        return combined
    }
}
