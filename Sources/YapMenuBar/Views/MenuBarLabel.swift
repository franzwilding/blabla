import SwiftUI

/// The icon that lives in the macOS menu bar.
/// Animates while any capture is active.
struct MenuBarLabel: View {
    let isCapturing: Bool
    let mode: AppState.CaptureMode

    @State private var phase: Double = 0

    var body: some View {
        Image(systemName: iconName)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: isCapturing)
            .symbolRenderingMode(.hierarchical)
    }

    private var iconName: String {
        switch mode {
        case .idle:      return "waveform"
        case .listening: return "speaker.wave.3.fill"
        case .dictating: return "mic.fill"
        case .both:      return "waveform.badge.mic"
        }
    }
}
