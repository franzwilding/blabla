import SwiftUI

// MARK: - MenuBarContentView

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState

    private var isDictating: Bool {
        appState.isCapturing && !appState.labelSources
    }

    private var isTranscribing: Bool {
        appState.isCapturing && appState.labelSources
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // ── Diktieren (≡ Fn hold) ──
            MenuRow(
                title: isDictating ? "Diktieren beenden" : "Diktieren",
                shortcut: "fn HOLD",
                isDisabled: isTranscribing
            ) {
                dismissPopover()
                Task { @MainActor in
                    if isDictating {
                        await appState.stopCapture()
                    } else if !appState.isCapturing {
                        await appState.startBoth()
                    }
                }
            }

            // ── Transkript (≡ Fn tap/toggle) ──
            MenuRow(
                title: isTranscribing ? "Transkript beenden" : "Transkript starten",
                shortcut: "fn PRESS",
                isDisabled: isDictating
            ) {
                dismissPopover()
                Task { @MainActor in
                    if isTranscribing {
                        await appState.stopCapture()
                    } else if !appState.isCapturing {
                        await appState.startBoth(mode: "Transkript")
                        appState.labelSources = true
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            // ── Einstellungen ──
            MenuRow(title: "Einstellungen", icon: "gearshape", shortcut: "⌘,") {
                dismissPopover()
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            // ── Beenden ──
            MenuRow(title: "Beenden", icon: "power", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 5)
        .frame(width: 260)
    }

    private func dismissPopover() {
        NSApp.keyWindow?.close()
    }
}

// MARK: - MenuRow

private struct MenuRow: View {
    let title: String
    var icon: String? = nil
    var shortcut: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if let icon {
                    Image(systemName: icon)
                        .frame(width: 20)
                }

                Text(title)

                Spacer(minLength: 16)

                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(isHovered && !isDisabled ? .white.opacity(0.7) : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered && !isDisabled ? Color.accentColor : .clear)
            )
            .foregroundStyle(isHovered && !isDisabled ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 5)
    }
}
