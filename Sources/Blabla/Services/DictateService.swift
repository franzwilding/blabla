// DictateService — transcribes live microphone input via AVAudioEngine + SpeechAnalyzer.

@preconcurrency import AVFoundation
import Combine
import CoreMedia
import Speech

// MARK: - DictateService

@MainActor
final class DictateService: ObservableObject {

    enum State { case idle, preparing, running, stopping }

    @Published var state: State = .idle
    @Published var liveFragment: String = ""
    @Published var liveSegments: [OutputFormat.Segment] = []

    /// Final transcript captured before clearing liveFragment on stop.
    /// Read this after `stop()` returns to get the complete dictated text.
    var finalTranscript: String = ""

    /// Called with the raw source-format PCM buffer for each mic chunk (before conversion).
    /// Can be set after `start()` — MicCapture reads it dynamically via the shared box.
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? {
        get { audioCallbackBox.callback }
        set { audioCallbackBox.callback = newValue }
    }
    private let audioCallbackBox = SendableCallbackBox()

    private var micCapture: MicCapture?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var resultsTask: Task<Void, Never>?

    // MARK: - Start

    func start(locale: Locale, censor: Bool) async throws {
        guard state == .idle else { return }
        state = .preparing

        // Request microphone access
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            state = .idle
            throw DictateError.microphonePermissionDenied
        }

        guard SpeechTranscriber.isAvailable else {
            state = .idle
            throw DictateError.speechNotAvailable
        }

        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            state = .idle
            throw DictateError.unsupportedLocale(locale.identifier)
        }

        for l in await AssetInventory.reservedLocales { await AssetInventory.release(reservedLocale: l) }
        try await AssetInventory.reserve(locale: locale)

        let speechTranscriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: censor ? [.etiquetteReplacements] : [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        let modules: [any SpeechModule] = [speechTranscriber]

        // Download language assets if needed
        let installed = await SpeechTranscriber.installedLocales
        if !installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await req.downloadAndInstall()
            }
        }

        guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            state = .idle
            throw DictateError.noCompatibleAudioFormat
        }

        let (inputSeq, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)

        // Set up microphone capture
        let capture = try MicCapture(targetFormat: targetFormat, continuation: continuation)
        capture.audioCallbackBox = self.audioCallbackBox
        micCapture = capture
        try capture.start()

        let speechAnalyzer = SpeechAnalyzer(modules: modules)
        try await speechAnalyzer.start(inputSequence: inputSeq)
        analyzer    = speechAnalyzer
        transcriber = speechTranscriber
        state       = .running

        resultsTask = Task { [weak self] in
            var segments: [(range: CMTimeRange, text: String)] = []

            do {
                guard let transcriber = self?.transcriber else { return }
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }

                    let resultStart = result.range.start.seconds
                    let resultEnd   = resultStart + result.range.duration.seconds
                    if let idx = segments.lastIndex(where: {
                        let segStart = $0.range.start.seconds
                        let segEnd   = segStart + $0.range.duration.seconds
                        return segStart < resultEnd && resultStart < segEnd
                    }) {
                        segments[idx].text = text
                        segments[idx].range = result.range
                    } else {
                        segments.append((result.range, text))
                    }

                    let display = segments.map(\.text).joined(separator: " ")
                    let segs = segments.map { OutputFormat.Segment(timeRange: $0.range, text: $0.text) }
                    await MainActor.run {
                        guard let self else { return }
                        self.liveFragment = display
                        self.liveSegments = segs
                    }
                }
            } catch {
                // Stream ended (normal on stop or error)
            }
            await MainActor.run {
                // Save final text before clearing — stopCapture() reads this.
                self?.finalTranscript = self?.liveFragment ?? ""
                self?.liveFragment = ""
                self?.liveSegments = []
                if self?.state == .stopping { self?.state = .idle }
            }
        }
    }

    // MARK: - Stop

    func stop() async throws {
        guard state == .running else { return }
        state = .stopping
        // Brief delay so the speech recognizer can finish processing the last word
        try? await Task.sleep(for: .milliseconds(300))
        micCapture?.stop()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        // Wait for the results task to finish processing (don't cancel it)
        await resultsTask?.value
        micCapture    = nil
        analyzer      = nil
        transcriber   = nil
        onAudioBuffer = nil
        state         = .idle
    }
}

// MARK: - MicCapture

private final class MicCapture: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let targetFormat: AVAudioFormat
    /// Shared box so the callback can be set after capture has started.
    var audioCallbackBox: SendableCallbackBox?

    init(targetFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        self.targetFormat = targetFormat
        self.continuation = continuation
        engine = AVAudioEngine()

        let inputNode = engine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        audioCallbackBox?.callback?(buffer)
        let sourceFormat = buffer.format
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate))
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var err: NSError?
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let src = buffer
        converter.convert(to: converted, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true; status.pointee = .haveData; return src
        }
        if err == nil, converted.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }
}

// MARK: - Errors

enum DictateError: LocalizedError {
    case microphonePermissionDenied
    case speechNotAvailable
    case unsupportedLocale(String)
    case noCompatibleAudioFormat

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return String(localized: "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone.", bundle: .main)
        case .speechNotAvailable:
            return String(localized: "Speech transcription is not available on this device.", bundle: .main)
        case .unsupportedLocale(let id):
            return String(localized: "Locale \"\(id)\" is not supported for transcription.", bundle: .main)
        case .noCompatibleAudioFormat:
            return String(localized: "No compatible audio format available for speech recognition.", bundle: .main)
        }
    }
}
