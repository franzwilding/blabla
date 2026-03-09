import AppKit
import AVFoundation
import CoreAudio
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
    @State private var micPermission = false
    @State private var audioTapPermission = false
    @State private var accessibilityPermission = false
    @State private var audioTapRequested = false

    var body: some View {
        Form {
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
                // Microphone
                PermissionRow(
                    label: String(localized: "Microphone", bundle: .main),
                    icon: "mic.fill",
                    granted: micPermission
                ) {
                    Task {
                        _ = await AVAudioApplication.requestRecordPermission()
                        checkPermissions()
                    }
                }

                // System Audio
                PermissionRow(
                    label: String(localized: "System Audio", bundle: .main),
                    icon: "speaker.wave.2.fill",
                    granted: audioTapPermission
                ) {
                    audioTapRequested = true
                    requestAudioTap()
                    // Check after a delay to give the user time to grant
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        checkPermissions()
                    }
                }
                if audioTapRequested && !audioTapPermission {
                    Text(String(localized: "After granting permission in System Settings, Blabla must be relaunched.", bundle: .main))
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(String(localized: "Relaunch Blabla", bundle: .main)) {
                        relaunchApp()
                    }
                    .controlSize(.small)
                }

                // Accessibility
                PermissionRow(
                    label: String(localized: "Accessibility", bundle: .main),
                    icon: "accessibility",
                    granted: accessibilityPermission
                ) {
                    requestAccessibility()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { checkPermissions() }
        .task { await pollLightPermissions() }
    }

    private func checkPermissions() {
        micPermission = AVAudioApplication.shared.recordPermission == .granted
        audioTapPermission = checkAudioTapPermission()
        accessibilityPermission = AXIsProcessTrusted()
    }

    /// Polls only lightweight permission checks (no hardware tap creation).
    /// Audio tap permission is only checked on-demand via button or on appear.
    private func pollLightPermissions() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            micPermission = AVAudioApplication.shared.recordPermission == .granted
            accessibilityPermission = AXIsProcessTrusted()
        }
    }

    /// Check if we have audio tap permission by trying to create a tap.
    /// Only called on-demand (view appear, after grant button), never in a tight poll loop.
    private nonisolated func checkAudioTapPermission() -> Bool {
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.name = "BlablaPermCheck"
        tapDesc.uuid = NSUUID() as UUID
        tapDesc.muteBehavior = .unmuted
        tapDesc.isPrivate = true

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        if status == noErr {
            AudioHardwareDestroyProcessTap(tapID)
            return true
        }
        return false
    }

    /// Request audio tap permission by creating a tap (triggers the OS permission dialog).
    private nonisolated func requestAudioTap() {
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.name = "BlablaPermReq"
        tapDesc.uuid = NSUUID() as UUID
        tapDesc.muteBehavior = .unmuted
        tapDesc.isPrivate = true

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        if status == noErr {
            AudioHardwareDestroyProcessTap(tapID)
        }
    }

    private func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: kCFBooleanTrue!] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Relaunches the app to pick up newly granted permissions.
    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()
        NSApplication.shared.terminate(nil)
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
    @EnvironmentObject var appState: AppState
    @State private var isRecording = false
    @State private var monitor: Any?

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
                        Text(String(localized: "Press a key combination…", bundle: .main))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(appState.hotkeyDisplayName)
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
        appState.hotkeyService.disable()
        var pendingModifier: GlobalHotkeyService.HotkeyKey?

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            // Escape cancels recording
            if event.type == .keyDown && event.keyCode == 53 {
                isRecording = false
                return event
            }

            // Regular key pressed while a modifier is held → save as combo
            if event.type == .keyDown {
                for key in GlobalHotkeyService.HotkeyKey.allCases {
                    if event.modifierFlags.contains(key.modifierFlag) {
                        hotkeyKeyRaw = "\(key.rawValue)+\(event.keyCode)"
                        pendingModifier = nil
                        isRecording = false
                        return event
                    }
                }
                return event
            }

            // Modifier key pressed or released
            if event.type == .flagsChanged {
                // Check if a modifier was pressed
                for key in GlobalHotkeyService.HotkeyKey.allCases {
                    if event.modifierFlags.contains(key.modifierFlag) {
                        pendingModifier = key
                        return event
                    }
                }
                // All modifiers released — save modifier-only if one was pending
                if let modifier = pendingModifier {
                    hotkeyKeyRaw = modifier.rawValue
                    pendingModifier = nil
                    isRecording = false
                }
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            appState.hotkeyService.enable()
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
        }
    }
}
