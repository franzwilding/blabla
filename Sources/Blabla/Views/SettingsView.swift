import AppKit
import AVFoundation
import ScreenCaptureKit
import Speech
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralTab()
                .environmentObject(appState)
                .tabItem { Label(String(localized: "General", bundle: .main), systemImage: "gearshape") }

            DictationTab()
                .environmentObject(appState)
                .tabItem { Label(String(localized: "Dictation", bundle: .main), systemImage: "mic.fill") }

            TranscriptionTab()
                .environmentObject(appState)
                .tabItem { Label(String(localized: "Transcription", bundle: .main), systemImage: "waveform") }
        }
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @EnvironmentObject var appState: AppState
    @State private var supportedLocales: [Locale] = []
    @State private var micPermission = false
    @State private var screenPermission = false
    @State private var accessibilityPermission = false

    var body: some View {
        Form {
            // ── Language ─────────────────────────────────────────────────────
            Section(String(localized: "Language", bundle: .main)) {
                Picker(String(localized: "Transcription language", bundle: .main), selection: $appState.selectedLocaleIdentifier) {
                    ForEach(supportedLocales, id: \.identifier) { locale in
                        Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
                .pickerStyle(.menu)

                Text(String(localized: "Languages must be downloaded by the system. Open System Settings → Accessibility → Live Speech to manage installed voices.", bundle: .main))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Content ─────────────────────────────────────────────────────
            Section(String(localized: "Content", bundle: .main)) {
                Toggle(String(localized: "Censor sensitive words", bundle: .main), isOn: $appState.censorContent)
            }

            // ── Hotkey ──────────────────────────────────────────────────────
            Section(String(localized: "Hotkey", bundle: .main)) {
                HotkeyRecorderView(hotkeyKeyRaw: $appState.hotkeyKeyRaw)
            }

            // ── Permissions ─────────────────────────────────────────────────
            Section(String(localized: "Permissions", bundle: .main)) {
                PermissionRow(
                    label: String(localized: "Microphone", bundle: .main),
                    icon: "mic.fill",
                    granted: micPermission
                ) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                }
                PermissionRow(
                    label: String(localized: "Screen Recording", bundle: .main),
                    icon: "display",
                    granted: screenPermission
                ) {
                    Task {
                        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    }
                }
                PermissionRow(
                    label: String(localized: "Accessibility", bundle: .main),
                    icon: "accessibility",
                    granted: accessibilityPermission
                ) {
                    requestAccessibility()
                }
            }

            // ── About ───────────────────────────────────────────────────────
            Section(String(localized: "About", bundle: .main)) {
                HStack {
                    Text(String(localized: "Core transcription engine", bundle: .main))
                    Spacer()
                    Link("finnvoor/yap", destination: URL(string: "https://github.com/finnvoor/yap")!)
                        .font(.subheadline)
                }
                HStack {
                    Text(String(localized: "Version", bundle: .main))
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await loadSupportedLocales() }
        .task { await pollPermissions() }
    }

    private func checkPermissions() {
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        screenPermission = CGPreflightScreenCaptureAccess()
        accessibilityPermission = AXIsProcessTrusted()
    }

    private func pollPermissions() async {
        while !Task.isCancelled {
            checkPermissions()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: kCFBooleanTrue!] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
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

// MARK: - Dictation Tab

private struct DictationTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section(String(localized: "Dictation", bundle: .main)) {
                Toggle(String(localized: "Automatic punctuation", bundle: .main), isOn: $appState.dictationPunctuation)

                Text(String(localized: "Hold the hotkey for push-to-talk. Dictation inserts the transcribed text at the current cursor position.", bundle: .main))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Transcription Tab

private struct TranscriptionTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            // ── Output format ───────────────────────────────────────────────
            Section(String(localized: "Output Format", bundle: .main)) {
                Picker(String(localized: "Format", bundle: .main), selection: $appState.outputFormatRaw) {
                    ForEach(OutputFormat.allCases, id: \.rawValue) { fmt in
                        Text(fmt.displayName).tag(fmt.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(
                    String(localized: "Max sentence length: \(appState.maxSentenceLength) chars", bundle: .main),
                    value: $appState.maxSentenceLength,
                    in: 10...200,
                    step: 10
                )
                .font(.subheadline)

                Toggle(String(localized: "Word-level timestamps (JSON only)", bundle: .main), isOn: $appState.wordTimestamps)
            }

            // ── Recording folder ────────────────────────────────────────────
            Section(String(localized: "Recording Folder", bundle: .main)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.defaultFolderURL.lastPathComponent)
                        Text(appState.defaultFolderURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if appState.defaultFolderPath.isEmpty {
                            Text(String(localized: "(Default)", bundle: .main))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
                    Button(String(localized: "Choose…", bundle: .main)) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        panel.prompt = String(localized: "Choose folder", bundle: .main)
                        if panel.runModal() == .OK, let url = panel.url {
                            appState.defaultFolderPath = url.path
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text(String(localized: "Text and audio files are written live to this folder. In case of a crash, existing data is preserved.", bundle: .main))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Help ────────────────────────────────────────────────────────
            Section {
                Text(String(localized: "Tap the hotkey to toggle transcription with speaker labels. Tap again to stop.", bundle: .main))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - HotkeyRecorderView

private struct HotkeyRecorderView: View {
    @Binding var hotkeyKeyRaw: String
    @State private var isRecording = false
    @State private var monitor: Any?

    private var currentKey: GlobalHotkeyService.HotkeyKey {
        GlobalHotkeyService.HotkeyKey(rawValue: hotkeyKeyRaw) ?? .fn
    }

    var body: some View {
        HStack {
            Text(String(localized: "Hotkey", bundle: .main))
            Spacer()
            Button {
                isRecording = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.caption)
                    if isRecording {
                        Text(String(localized: "Press a modifier key…", bundle: .main))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(currentKey.displayName)
                            .font(.subheadline.bold())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isRecording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isRecording ? Color.accentColor : .clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                installMonitor()
            } else {
                removeMonitor()
            }
        }
        .onDisappear {
            removeMonitor()
        }
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            for key in GlobalHotkeyService.HotkeyKey.allCases {
                if event.modifierFlags.contains(key.modifierFlag) {
                    hotkeyKeyRaw = key.rawValue
                    isRecording = false
                    return event
                }
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// MARK: - PermissionRow

private struct PermissionRow: View {
    let label: String
    let icon: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Button(String(localized: "Grant", bundle: .main)) {
                    request()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
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
