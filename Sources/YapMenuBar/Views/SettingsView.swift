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
