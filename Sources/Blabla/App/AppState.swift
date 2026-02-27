import Combine
import CoreGraphics
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
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    @Published var hotkeyKeyRaw: String {
        didSet {
            UserDefaults.standard.set(hotkeyKeyRaw, forKey: "hotkeyKey")
            hotkeyService.hotkeyKey = hotkeyKey
        }
    }

    var hotkeyKey: GlobalHotkeyService.HotkeyKey {
        GlobalHotkeyService.HotkeyKey(rawValue: hotkeyKeyRaw) ?? .fn
    }
    @Published var dictationPunctuation: Bool {
        didSet { UserDefaults.standard.set(dictationPunctuation, forKey: "dictationPunctuation") }
    }
    @Published var defaultFolderPath: String {
        didSet { UserDefaults.standard.set(defaultFolderPath, forKey: "defaultFolderPath") }
    }

    /// When true, prefix `[System]` / `[Mic]` labels in the combined transcript.
    /// Setting this to true while capturing starts the session recorder (transcript files).
    @Published var labelSources: Bool = false {
        didSet {
            if labelSources && captureMode == .both && sessionRecorder == nil {
                startSessionRecording()
            }
        }
    }

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

    var defaultFolderURL: URL {
        let url: URL
        if defaultFolderPath.isEmpty {
            url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Blabla", isDirectory: true)
        } else {
            url = URL(fileURLWithPath: defaultFolderPath, isDirectory: true)
        }
        return url
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
        outputFormatRaw          = defaults.string(forKey: "outputFormat") ?? OutputFormat.vtt.rawValue
        maxSentenceLength        = defaults.integer(forKey: "maxSentenceLength").nonzero(default: 40)
        wordTimestamps           = defaults.bool(forKey: "wordTimestamps")
        // Default to enabled; UserDefaults.bool returns false for missing keys
        hotkeyEnabled            = defaults.object(forKey: "hotkeyEnabled") == nil
                                     ? true
                                     : defaults.bool(forKey: "hotkeyEnabled")
        hotkeyKeyRaw             = defaults.string(forKey: "hotkeyKey") ?? GlobalHotkeyService.HotkeyKey.fn.rawValue
        // Default to true (keep punctuation); UserDefaults.bool returns false for missing keys
        dictationPunctuation     = defaults.object(forKey: "dictationPunctuation") == nil
                                     ? true
                                     : defaults.bool(forKey: "dictationPunctuation")
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

    func startBoth() async {
        guard captureMode == .idle else { return }
        liveText = ""
        labelSources = false
        clearError()
        do {
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
        let wasDictating = !labelSources && captureMode == .both
        let wasTranscribing = labelSources
        let source = captureMode.label
        captureMode = .idle
        labelSources = false
        hotkeyService.resetToIdle()

        // Stop services — waits for all results to be fully processed
        async let l: () = (try? listenService.stop()) ?? ()
        async let d: () = (try? dictateService.stop()) ?? ()
        _ = await (l, d)

        let transcriptURL = stopSessionRecording()

        // Archive AFTER services have produced all results
        let combinedText = liveText
        if !combinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            archiveTranscript(combinedText, source: source)

            // Dictation mode: insert text at the focused cursor position
            if wasDictating {
                let textToInsert = dictationPunctuation
                    ? combinedText
                    : stripPunctuation(from: combinedText)
                insertTextAtCursor(textToInsert)
            }
        }

        // Reveal transcript file in Finder (only for transcript mode)
        if wasTranscribing, let transcriptURL {
            NSWorkspace.shared.activateFileViewerSelecting([transcriptURL])
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
        hotkeyService.hotkeyKey = hotkeyKey
        hotkeyService.onStartBoth = { [weak self] in
            await self?.startBoth()
        }
        hotkeyService.onStopCapture = { [weak self] in
            await self?.stopCapture()
        }
        hotkeyService.onEnableSpeakerLabels = { [weak self] in
            self?.labelSources = true
        }
        hotkeyService.enable()
    }

    private func startSessionRecording() {
        let folder = defaultFolderURL
        let recorder = SessionRecorder(
            folder: folder,
            mode: "Transkript",
            fileExtension: outputFormat.rawValue
        )
        sessionRecorder = recorder
        listenService.onAudioBuffer = { [recorder] buffer in
            recorder.writeAudio(buffer: buffer, source: .system)
        }
        dictateService.onAudioBuffer = { [recorder] buffer in
            recorder.writeAudio(buffer: buffer, source: .mic)
        }
    }

    @discardableResult
    private func stopSessionRecording() -> URL? {
        let url = sessionRecorder?.transcriptFileURL
        sessionRecorder?.finalize()
        sessionRecorder = nil
        listenService.onAudioBuffer = nil
        dictateService.onAudioBuffer = nil
        return url
    }

    /// Removes sentence punctuation added by the speech recognizer.
    private func stripPunctuation(from text: String) -> String {
        text.replacingOccurrences(of: "[.,!?;:]+(?=\\s|$)", with: "", options: .regularExpression)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Inserts text at the currently focused cursor position (any app) by
    /// temporarily placing it on the clipboard and simulating ⌘V.
    private func insertTextAtCursor(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Back up all current clipboard items (preserves images, files, etc.)
        let backup: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }

        // Place dictated text on the clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate ⌘V keystroke (virtual key 0x09 = 'v')
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Restore the previous clipboard after the paste has been processed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pasteboard.clearContents()
            for itemData in backup {
                let item = NSPasteboardItem()
                for (type, data) in itemData {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
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
