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
            // ── Diktieren (≡ hotkey hold, push-to-talk) ──
            MenuRow(
                title: isDictating
                    ? String(localized: "Stop Dictation", bundle: .main)
                    : String(localized: "Dictation", bundle: .main),
                icon: "mic.fill",
                shortcut: appState.hotkeyShortcut,
                isDisabled: isTranscribing
            ) {
                dismissPopover()
                Task { @MainActor in
                    if isDictating {
                        await appState.stopCapture()
                    } else if !appState.isCapturing {
                        await appState.startDictating()
                    }
                }
            }

            // ── Transkript (nur über Menü) ──
            MenuRow(
                title: isTranscribing
                    ? String(localized: "Stop Transcript", bundle: .main)
                    : String(localized: "Start Transcript", bundle: .main),
                icon: "waveform",
                isDisabled: isDictating
            ) {
                dismissPopover()
                Task { @MainActor in
                    if isTranscribing {
                        await appState.stopCapture()
                    } else if !appState.isCapturing {
                        await appState.startBoth()
                        appState.labelSources = true
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            // ── Sprache ──
            LanguagePickerRow()
                .environmentObject(appState)

            // ── Transkript-Ordner öffnen ──
            MenuRow(
                title: String(localized: "Open Transcripts Folder", bundle: .main),
                icon: "folder"
            ) {
                appState.openTranscriptsFolder()
                dismissPopover()
            }

            Divider()
                .padding(.vertical, 4)

            // ── Einstellungen ──
            SettingsMenuRow(shortcut: "⌘,") {
                dismissPopover()
            }

            // ── Beenden ──
            MenuRow(
                title: String(localized: "Quit", bundle: .main),
                icon: "power",
                shortcut: "⌘Q"
            ) {
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

// MARK: - LanguagePickerRow

private struct LanguagePickerRow: View {
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "globe")
                .frame(width: 20)

            Picker(selection: $appState.selectedLocaleIdentifier) {
                ForEach(appState.supportedLocales, id: \.identifier) { locale in
                    Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                        .tag(locale.identifier)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .padding(.horizontal, 5)
    }
}

// MARK: - SettingsMenuRow

private struct SettingsMenuRow: View {
    var shortcut: String? = nil
    var onOpen: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        SettingsLink {
            HStack(spacing: 0) {
                Image(systemName: "gearshape")
                    .frame(width: 20)

                Text(String(localized: "Settings", bundle: .main))

                Spacer(minLength: 16)

                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(isHovered ? .white.opacity(0.7) : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor : .clear)
            )
            .foregroundStyle(isHovered ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 5)
        .simultaneousGesture(TapGesture().onEnded { onOpen?() })
    }
}
