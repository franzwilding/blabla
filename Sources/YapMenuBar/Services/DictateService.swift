// DictateService — transcribes live microphone input via AVAudioEngine + SpeechAnalyzer.
// The MicCapture class below mirrors yap's MicrophoneCapture in Dictate.swift,
// adapted for use as a library service rather than a CLI command.

@preconcurrency import AVFoundation
import Combine
import Speech

// MARK: - DictateService

@MainActor
final class DictateService: ObservableObject {

    enum State { case idle, preparing, running, stopping }

    @Published var state: State = .idle
    @Published var liveFragment: String = ""

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
            reportingOptions: [],
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

        // Set up microphone capture (mirrors yap's MicrophoneCapture)
        let capture = try MicCapture(targetFormat: targetFormat, continuation: continuation)
        micCapture = capture
        try capture.start()

        let speechAnalyzer = SpeechAnalyzer(modules: modules)
        try await speechAnalyzer.start(inputSequence: inputSeq)
        analyzer    = speechAnalyzer
        transcriber = speechTranscriber
        state       = .running

        resultsTask = Task { [weak self] in
            do {
                guard let transcriber = self?.transcriber else { return }
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    await MainActor.run { self?.liveFragment = text }
                }
            } catch {
                // Stream ended (normal on stop or error)
            }
            await MainActor.run {
                self?.liveFragment = ""
                if self?.state == .stopping { self?.state = .idle }
            }
        }
    }

    // MARK: - Stop

    func stop() async throws {
        guard state == .running else { return }
        state = .stopping
        micCapture?.stop()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        micCapture  = nil
        analyzer    = nil
        transcriber = nil
        state       = .idle
    }
}

// MARK: - MicCapture
// Mirrors yap's MicrophoneCapture — taps the AVAudioEngine input node and
// converts buffers to the SpeechAnalyzer's expected format.

private final class MicCapture: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let targetFormat: AVAudioFormat

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
            return "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."
        case .speechNotAvailable:
            return "Speech transcription is not available on this device."
        case .unsupportedLocale(let id):
            return "Locale \"\(id)\" is not supported for transcription."
        case .noCompatibleAudioFormat:
            return "No compatible audio format available for speech recognition."
        }
    }
}
