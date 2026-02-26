// ListenService — transcribes live system audio via ScreenCaptureKit + SpeechAnalyzer.
// The AudioCaptureDelegate below mirrors the AudioStreamDelegate class in yap's Listen.swift,
// adapted for use as a library service rather than a CLI command.

@preconcurrency import AVFoundation
import Combine
import CoreMedia
@preconcurrency import ScreenCaptureKit
import Speech

// MARK: - ListenService

@MainActor
final class ListenService: ObservableObject {

    enum State { case idle, preparing, running, stopping }

    @Published var state: State = .idle
    @Published var liveFragment: String = ""

    /// Called with the raw source-format PCM buffer for each audio chunk (before conversion).
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private var captureStream: SCStream?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    // MARK: - Start

    func start(locale: Locale, censor: Bool) async throws {
        guard state == .idle else { return }
        state = .preparing

        guard SpeechTranscriber.isAvailable else {
            state = .idle
            throw ListenError.speechNotAvailable
        }

        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            state = .idle
            throw ListenError.unsupportedLocale(locale.identifier)
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

        // Download language assets if not yet installed
        let installed = await SpeechTranscriber.installedLocales
        if !installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await req.downloadAndInstall()
            }
        }

        guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            state = .idle
            throw ListenError.noCompatibleAudioFormat
        }

        // ScreenCaptureKit for system audio
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            state = .idle
            throw ListenError.screenRecordingPermissionDenied
        }

        guard let display = content.displays.first else {
            state = .idle
            throw ListenError.screenRecordingPermissionDenied
        }

        let (inputSeq, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = continuation

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio            = true
        cfg.sampleRate               = Int(targetFormat.sampleRate)
        cfg.channelCount             = Int(targetFormat.channelCount)
        cfg.excludesCurrentProcessAudio = true
        cfg.width                    = 2
        cfg.height                   = 2
        cfg.minimumFrameInterval     = CMTime(value: 1, timescale: 1)

        let delegate = AudioCaptureDelegate(targetFormat: targetFormat, continuation: continuation)
        delegate.onSourceBuffer = self.onAudioBuffer
        let filter   = SCContentFilter(display: display, excludingWindows: [])
        let stream   = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try stream.addStreamOutput(delegate, type: .audio, sampleHandlerQueue: .global())

        do {
            try await stream.startCapture()
        } catch {
            state = .idle
            inputContinuation?.finish()
            throw ListenError.screenRecordingPermissionDenied
        }

        captureStream = stream

        let speechAnalyzer = SpeechAnalyzer(modules: modules)
        try await speechAnalyzer.start(inputSequence: inputSeq)
        analyzer    = speechAnalyzer
        transcriber = speechTranscriber
        state       = .running

        resultsTask = Task { [weak self] in
            // Track segments by start time to handle volatile→finalized transitions
            // without duplication. Volatile results update in-place, finalized results
            // replace their volatile predecessor for the same time range.
            var segments: [(start: CMTime, text: String)] = []

            do {
                guard let transcriber = self?.transcriber else { return }
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }

                    let start = result.range.start
                    if let idx = segments.firstIndex(where: { CMTimeCompare($0.start, start) == 0 }) {
                        segments[idx].text = text
                    } else {
                        segments.append((start, text))
                    }

                    let display = segments.map(\.text).joined(separator: " ")
                    await MainActor.run {
                        guard let self else { return }
                        self.liveFragment = display
                    }
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
        try? await captureStream?.stopCapture()
        inputContinuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        // Wait for the results task to finish processing (don't cancel it)
        await resultsTask?.value
        captureStream     = nil
        analyzer          = nil
        transcriber       = nil
        inputContinuation = nil
        onAudioBuffer     = nil
        state             = .idle
    }
}

// MARK: - AudioCaptureDelegate
// Mirrors yap's AudioStreamDelegate — converts ScreenCaptureKit audio buffers to the
// format expected by SpeechAnalyzer and forwards them via the async stream continuation.

private final class AudioCaptureDelegate: NSObject, SCStreamOutput, @unchecked Sendable {
    let targetFormat: AVAudioFormat
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    var converter: AVAudioConverter?
    var onSourceBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    init(targetFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.targetFormat = targetFormat
        self.continuation = continuation
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              sampleBuffer.isValid,
              sampleBuffer.numSamples > 0 else { return }

        guard let desc = sampleBuffer.formatDescription,
              let asbd = desc.audioStreamBasicDescription,
              let sourceFormat = AVAudioFormat(
                  standardFormatWithSampleRate: asbd.mSampleRate,
                  channels: asbd.mChannelsPerFrame
              ) else { return }

        if converter == nil || converter?.inputFormat != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        guard let converter else { return }

        do {
            try sampleBuffer.withAudioBufferList { abl, _ in
                guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, bufferListNoCopy: abl.unsafePointer) else { return }
                onSourceBuffer?(source)
                let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate))
                guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

                var err: NSError?
                nonisolated(unsafe) var consumed = false
                nonisolated(unsafe) let buf = source
                converter.convert(to: converted, error: &err) { _, status in
                    if consumed { status.pointee = .noDataNow; return nil }
                    consumed = true; status.pointee = .haveData; return buf
                }
                if err == nil, converted.frameLength > 0 {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            }
        } catch {}
    }
}

// MARK: - Errors

enum ListenError: LocalizedError {
    case speechNotAvailable
    case unsupportedLocale(String)
    case noCompatibleAudioFormat
    case screenRecordingPermissionDenied

    var errorDescription: String? {
        switch self {
        case .speechNotAvailable:
            return "Speech transcription is not available on this device."
        case .unsupportedLocale(let id):
            return "Locale \"\(id)\" is not supported for transcription."
        case .noCompatibleAudioFormat:
            return "No compatible audio format available for speech recognition."
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission required. Enable it in System Settings → Privacy & Security → Screen Recording, then relaunch YapBar."
        }
    }
}
