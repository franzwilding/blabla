import Combine
import Foundation
import SwiftUI

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {

    // MARK: - Capture mode

    enum CaptureMode: String, Sendable {
        case idle
        case listening   // system audio
        case dictating   // microphone
        case both        // system audio + microphone
    }

    // MARK: Published state

    @Published var captureMode: CaptureMode = .idle
    @Published var liveText: String = ""
    @Published var errorMessage: String?
    @Published var isTranscribingFile = false

    // MARK: Persisted settings (UserDefaults via @AppStorage analogue)

    @Published var selectedLocaleIdentifier: String {
        didSet { UserDefaults.standard.set(selectedLocaleIdentifier, forKey: "selectedLocale") }
    }
    @Published var censorContent: Bool {
        didSet { UserDefaults.standard.set(censorContent, forKey: "censorContent") }
    }
    @Published var outputFormatRaw: String {
        didSet { UserDefaults.standard.set(outputFormatRaw, forKey: "outputFormat") }
    }
    @Published var maxSentenceLength: Int {
        didSet { UserDefaults.standard.set(maxSentenceLength, forKey: "maxSentenceLength") }
    }
    @Published var wordTimestamps: Bool {
        didSet { UserDefaults.standard.set(wordTimestamps, forKey: "wordTimestamps") }
    }
    @Published var hotkeyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled")
            if hotkeyEnabled { hotkeyService.enable() } else { hotkeyService.disable() }
        }
    }
    @Published var defaultFolderPath: String {
        didSet { UserDefaults.standard.set(defaultFolderPath, forKey: "defaultFolderPath") }
    }

    /// When true, prefix `[System]` / `[Mic]` labels in the combined transcript.
    @Published var labelSources: Bool = false

    // MARK: Computed settings

    var selectedLocale: Locale { Locale(identifier: selectedLocaleIdentifier) }
    var outputFormat: OutputFormat { OutputFormat(rawValue: outputFormatRaw) ?? .txt }

    var isCapturing: Bool { captureMode != .idle }

    var menuBarIcon: String {
        switch captureMode {
        case .idle: return "waveform"
        case .listening: return "speaker.wave.3.fill"
        case .dictating: return "mic.fill"
        case .both: return "waveform.badge.mic"
        }
    }

    // MARK: Computed — default folder

    var defaultFolderURL: URL? {
        guard !defaultFolderPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: defaultFolderPath, isDirectory: true)
        return FileManager.default.isWritableFile(atPath: url.path) ? url : nil
    }

    // MARK: - Services

    let listenService = ListenService()
    let dictateService = DictateService()
    let hotkeyService = GlobalHotkeyService()
    private var sessionRecorder: SessionRecorder?

    // MARK: - Transcript history

    @Published var history: [TranscriptEntry] = [] {
        didSet { saveHistory() }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        selectedLocaleIdentifier = defaults.string(forKey: "selectedLocale") ?? Locale.current.identifier
        censorContent            = defaults.bool(forKey: "censorContent")
        outputFormatRaw          = defaults.string(forKey: "outputFormat") ?? OutputFormat.txt.rawValue
        maxSentenceLength        = defaults.integer(forKey: "maxSentenceLength").nonzero(default: 40)
        wordTimestamps           = defaults.bool(forKey: "wordTimestamps")
        // Default to enabled; UserDefaults.bool returns false for missing keys
        hotkeyEnabled            = defaults.object(forKey: "hotkeyEnabled") == nil
                                     ? true
                                     : defaults.bool(forKey: "hotkeyEnabled")
        defaultFolderPath        = defaults.string(forKey: "defaultFolderPath") ?? ""
        loadHistory()
        observeServices()
        setupHotkeyService()
    }

    // MARK: - Capture actions

    func startListening() async {
        guard captureMode == .idle else { return }
        hotkeyService.resetToIdle()
        liveText = ""
        clearError()
        do {
            try await listenService.start(locale: selectedLocale, censor: censorContent)
            captureMode = .listening
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startDictating() async {
        guard captureMode == .idle else { return }
        hotkeyService.resetToIdle()
        liveText = ""
        clearError()
        do {
            try await dictateService.start(locale: selectedLocale, censor: censorContent)
            captureMode = .dictating
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startBoth(mode: String = "Diktat") async {
        guard captureMode == .idle else { return }
        liveText = ""
        labelSources = false
        clearError()
        do {
            startSessionRecording(mode: mode)
            try await listenService.start(locale: selectedLocale, censor: censorContent)
            try await dictateService.start(locale: selectedLocale, censor: censorContent)
            captureMode = .both
        } catch {
            errorMessage = error.localizedDescription
            stopSessionRecording()
            try? await listenService.stop()
        }
    }

    func stopCapture() async {
        let source = captureMode.label
        captureMode = .idle
        labelSources = false
        hotkeyService.resetToIdle()

        // Stop services — waits for all results to be fully processed
        async let l: () = (try? listenService.stop()) ?? ()
        async let d: () = (try? dictateService.stop()) ?? ()
        _ = await (l, d)

        stopSessionRecording()

        // Archive AFTER services have produced all results
        let combinedText = liveText
        if !combinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            archiveTranscript(combinedText, source: source)
        }
    }

    // MARK: - File transcription

    func transcribeFile(_ url: URL) async {
        isTranscribingFile = true
        clearError()
        defer { isTranscribingFile = false }
        do {
            let options = TranscriptionEngine.Options(
                locale: selectedLocale,
                censor: censorContent,
                outputFormat: outputFormat,
                maxLength: maxSentenceLength,
                wordTimestamps: wordTimestamps
            )
            let result = try await TranscriptionEngine.transcribe(file: url, options: options)
            archiveTranscript(result, source: "File: \(url.lastPathComponent)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clearError() { errorMessage = nil }

    func deleteHistoryEntry(_ entry: TranscriptEntry) {
        history.removeAll { $0.id == entry.id }
    }

    func clearHistory() { history.removeAll() }

    // MARK: - Private

    private func observeServices() {
        listenService.$liveFragment
            .combineLatest(dictateService.$liveFragment)
            .receive(on: RunLoop.main)
            .sink { [weak self] listenFrag, dictateFrag in
                guard let self else { return }
                var parts: [String] = []
                if !listenFrag.isEmpty {
                    parts.append(self.labelSources ? "[System] \(listenFrag)" : listenFrag)
                }
                if !dictateFrag.isEmpty {
                    parts.append(self.labelSources ? "[Mic] \(dictateFrag)" : dictateFrag)
                }
                guard !parts.isEmpty else { return }
                self.liveText = parts.joined(separator: "\n")
                self.sessionRecorder?.writeText(self.liveText)
            }
            .store(in: &cancellables)
    }

    private func setupHotkeyService() {
        hotkeyService.onStartBoth = { [weak self] in
            await self?.startBoth()
        }
        hotkeyService.onStopCapture = { [weak self] in
            await self?.stopCapture()
        }
        hotkeyService.onEnableSpeakerLabels = { [weak self] in
            self?.labelSources = true
        }
        if hotkeyEnabled { hotkeyService.enable() }
    }

    private func startSessionRecording(mode: String) {
        guard let folder = defaultFolderURL else { return }
        guard let recorder = try? SessionRecorder(folder: folder, mode: mode) else { return }
        sessionRecorder = recorder
        listenService.onAudioBuffer = { [recorder] buffer in
            recorder.writeAudio(buffer: buffer, source: .system)
        }
        dictateService.onAudioBuffer = { [recorder] buffer in
            recorder.writeAudio(buffer: buffer, source: .mic)
        }
    }

    private func stopSessionRecording() {
        sessionRecorder?.finalize()
        sessionRecorder = nil
    }

    private func archiveTranscript(_ text: String, source: String) {
        let entry = TranscriptEntry(date: .now, source: source, text: text)
        history.insert(entry, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: "transcriptHistory")
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "transcriptHistory"),
              let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data)
        else { return }
        history = decoded
    }

    private var cancellables = Set<AnyCancellable>()
}

// MARK: - Helpers

private extension Int {
    func nonzero(default value: Int) -> Int { self == 0 ? value : self }
}

private extension AppState.CaptureMode {
    var label: String {
        switch self {
        case .idle: return "Live"
        case .listening: return "System Audio"
        case .dictating: return "Dictation"
        case .both: return "System Audio + Dictation"
        }
    }
}
