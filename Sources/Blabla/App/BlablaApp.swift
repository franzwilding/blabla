import SwiftUI

@main
struct BlablaApp: App {
    @StateObject private var appState = AppState()

    private var isDictating: Bool {
        appState.isCapturing && !appState.labelSources
    }

    private var isTranscribing: Bool {
        appState.isCapturing && appState.labelSources
    }

    var body: some Scene {
        MenuBarExtra {
            // ── Diktieren ──
            Button {
                Task { @MainActor in
                    if isDictating {
                        await appState.stopCapture()
                    } else if !appState.isCapturing {
                        await appState.startDictating()
                    }
                }
            } label: {
                Text(isDictating
                     ? String(localized: "Stop Dictation", bundle: .main)
                     : "\(String(localized: "Dictation", bundle: .main))  ⌨ \(appState.hotkeyDisplayName) \(String(localized: "Hold", bundle: .main))")
            }
            .disabled(isTranscribing)

            // ── Transkript ──
            Button {
                Task { @MainActor in
                    if isTranscribing {
                        await appState.stopCapture()
                    } else if !appState.isCapturing {
                        await appState.startBoth()
                        appState.labelSources = true
                    }
                }
            } label: {
                Text(isTranscribing
                     ? String(localized: "Stop Transcript", bundle: .main)
                     : String(localized: "Start Transcript", bundle: .main))
            }
            .disabled(isDictating)

            Divider()

            // ── Sprache ──
            Picker(selection: $appState.selectedLocaleIdentifier) {
                ForEach(appState.supportedLocales, id: \.identifier) { locale in
                    Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                        .tag(locale.identifier)
                }
            } label: {
                Text(String(localized: "Language", bundle: .main))
            }

            // ── Ordner öffnen ──
            Button(String(localized: "Open Transcripts Folder", bundle: .main)) {
                appState.openTranscriptsFolder()
            }

            Divider()

            // ── Einstellungen ──
            SettingsLink {
                Text(String(localized: "Settings…", bundle: .main))
            }
            .keyboardShortcut(",")

            // ── Beenden ──
            Button(String(localized: "Quit", bundle: .main)) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            MenuBarLabel(isCapturing: appState.isCapturing, labelSources: appState.labelSources, mode: appState.captureMode)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 500, height: 440)
                .onAppear {
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.first { $0.isVisible && $0.canBecomeKey }?
                            .makeKeyAndOrderFront(nil)
                    }
                }
        }
    }
}
