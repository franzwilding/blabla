import AppKit
import Speech
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var supportedLocales: [Locale] = []

    var body: some View {
        Form {
            // ── Language ─────────────────────────────────────────────────────
            Section("Language") {
                Picker("Transcription language", selection: $appState.selectedLocaleIdentifier) {
                    ForEach(supportedLocales, id: \.identifier) { locale in
                        Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
                .pickerStyle(.menu)

                Text("Languages must be downloaded by the system. Open System Settings → Accessibility → Live Speech to manage installed voices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Output format ─────────────────────────────────────────────────
            Section("Output Format") {
                Picker("Format", selection: $appState.outputFormatRaw) {
                    ForEach(OutputFormat.allCases, id: \.rawValue) { fmt in
                        Text(fmt.displayName).tag(fmt.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(
                    "Max sentence length: \(appState.maxSentenceLength) chars",
                    value: $appState.maxSentenceLength,
                    in: 10...200,
                    step: 10
                )
                .font(.subheadline)

                Toggle("Word-level timestamps (JSON only)", isOn: $appState.wordTimestamps)
            }

            // ── Content ───────────────────────────────────────────────────────
            Section("Content") {
                Toggle("Censor sensitive words", isOn: $appState.censorContent)
            }

            // ── Aufnahmen ────────────────────────────────────────────────────
            Section("Aufnahmen") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if appState.defaultFolderPath.isEmpty {
                            Text("Kein Ordner ausgewählt")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(URL(fileURLWithPath: appState.defaultFolderPath).lastPathComponent)
                            Text(appState.defaultFolderPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    if !appState.defaultFolderPath.isEmpty {
                        Button {
                            appState.defaultFolderPath = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Ausw\u{00E4}hlen\u{2026}") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        panel.prompt = "Ordner ausw\u{00E4}hlen"
                        if panel.runModal() == .OK, let url = panel.url {
                            appState.defaultFolderPath = url.path
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text("Text- und Audiodateien werden live in diesen Ordner geschrieben. Bei einem Absturz bleiben die bisherigen Daten erhalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Global Hotkey ─────────────────────────────────────────────────
            Section("Global Hotkey") {
                Toggle("Enable Fn key hotkey", isOn: $appState.hotkeyEnabled)

                Text("Hold Fn for push-to-talk (both sources). Tap Fn to toggle recording with speaker labels. Tap again to stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Permissions ───────────────────────────────────────────────────
            Section("Permissions") {
                HStack {
                    Label("Microphone", systemImage: "mic.fill")
                    Spacer()
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                HStack {
                    Label("Screen Recording", systemImage: "display")
                    Spacer()
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // ── About ─────────────────────────────────────────────────────────
            Section("About") {
                HStack {
                    Text("Core transcription engine")
                    Spacer()
                    Link("finnvoor/yap", destination: URL(string: "https://github.com/finnvoor/yap")!)
                        .font(.subheadline)
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("YapBar Settings")
        .task { await loadSupportedLocales() }
    }

    private func loadSupportedLocales() async {
        let locales = await SpeechTranscriber.supportedLocales
        supportedLocales = Array(locales).sorted {
            let a = $0.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
            let b = $1.localizedString(forIdentifier: $1.identifier) ?? $1.identifier
            return a < b
        }
        if supportedLocales.isEmpty {
            supportedLocales = [.current]
        }
    }
}

// MARK: - OutputFormat display helpers

extension OutputFormat {
    var displayName: String {
        switch self {
        case .txt:  return "Text"
        case .srt:  return "SRT"
        case .vtt:  return "VTT"
        case .json: return "JSON"
        @unknown default: return rawValue.uppercased()
        }
    }
}
