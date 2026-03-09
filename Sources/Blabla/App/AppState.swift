import Combine
import CoreGraphics
import Foundation
import Speech
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
            hotkeyService.hotkeyKeyCode = hotkeyKeyCode
        }
    }

    var hotkeyKey: GlobalHotkeyService.HotkeyKey {
        let parts = hotkeyKeyRaw.split(separator: "+")
        return GlobalHotkeyService.HotkeyKey(rawValue: String(parts.first ?? "fn")) ?? .fn
    }

    var hotkeyKeyCode: UInt16? {
        let parts = hotkeyKeyRaw.split(separator: "+")
        guard parts.count > 1, let code = UInt16(parts[1]) else { return nil }
        return code
    }

    var hotkeyDisplayName: String {
        var name = hotkeyKey.displayName
        if let keyCode = hotkeyKeyCode {
            name += " + " + GlobalHotkeyService.displayName(forKeyCode: keyCode)
        }
        return name
    }

    /// Compact symbol-style shortcut string for menu display (e.g. "🌐", "⌃D").
    var hotkeyShortcut: String {
        var s = hotkeyKey.symbol
        if let keyCode = hotkeyKeyCode {
            s += GlobalHotkeyService.displayName(forKeyCode: keyCode)
        }
        return s
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
    let liveTextOverlay = LiveTextOverlayController()
    private var sessionRecorder: SessionRecorder?
    private var startTask: Task<Void, Never>?

    // MARK: - Transcript history

    @Published var supportedLocales: [Locale] = []

    @Published var history: [TranscriptEntry] = [] {
        didSet { saveHistory() }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        selectedLocaleIdentifier = defaults.string(forKey: "selectedLocale") ?? "de_DE"
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
        liveTextOverlay.attach(to: self)
        Task { await loadSupportedLocales() }
    }

    // MARK: - Supported locales

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
        liveText = ""
        clearError()
        let task = Task { @MainActor in
            do {
                try await dictateService.start(locale: selectedLocale, censor: censorContent)
                captureMode = .dictating
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        startTask = task
        await task.value
        startTask = nil
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
        // Wait for any in-flight start to complete before stopping
        await startTask?.value

        let wasDictating = !labelSources && (captureMode == .both || captureMode == .dictating)
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
            let folder = transcriptURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: transcriptURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([transcriptURL])
            } else {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
            }
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

    func openTranscriptsFolder() {
        let folder = defaultFolderURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func clearError() { errorMessage = nil }

    func deleteHistoryEntry(_ entry: TranscriptEntry) {
        history.removeAll { $0.id == entry.id }
    }

    func clearHistory() { history.removeAll() }

    // MARK: - Private

    private func observeServices() {
        // Plain text for UI display, dictation, and history
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
                // For plain text format, write directly
                if self.outputFormat == .txt {
                    self.sessionRecorder?.writeText(self.liveText)
                }
            }
            .store(in: &cancellables)

        // Formatted segments for SRT/VTT/JSON file output (with timestamps)
        listenService.$liveSegments
            .combineLatest(dictateService.$liveSegments)
            .receive(on: RunLoop.main)
            .sink { [weak self] listenSegs, dictateSegs in
                guard let self, self.outputFormat != .txt else { return }
                guard !(listenSegs.isEmpty && dictateSegs.isEmpty) else { return }

                var allSegments: [OutputFormat.Segment] = []
                for seg in listenSegs {
                    var s = seg
                    if self.labelSources { s.speaker = "System" }
                    allSegments.append(s)
                }
                for seg in dictateSegs {
                    var s = seg
                    if self.labelSources { s.speaker = "Mic" }
                    allSegments.append(s)
                }
                allSegments.sort { $0.timeRange.start.seconds < $1.timeRange.start.seconds }

                let formatted = self.outputFormat.formatSegments(allSegments, locale: self.selectedLocale)
                self.sessionRecorder?.writeText(formatted)
            }
            .store(in: &cancellables)
    }

    private func setupHotkeyService() {
        hotkeyService.hotkeyKey = hotkeyKey
        hotkeyService.hotkeyKeyCode = hotkeyKeyCode
        hotkeyService.onStartDictation = { [weak self] in
            await self?.startDictating()
        }
        hotkeyService.onStopDictation = { [weak self] in
            await self?.stopCapture()
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

extension AppState.CaptureMode {
    var label: String {
        switch self {
        case .idle: return String(localized: "Live", bundle: .main)
        case .listening: return String(localized: "System Audio", bundle: .main)
        case .dictating: return String(localized: "Dictation", bundle: .main)
        case .both: return String(localized: "System Audio + Dictation", bundle: .main)
        }
    }
}
