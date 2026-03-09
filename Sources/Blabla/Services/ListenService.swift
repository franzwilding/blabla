// ListenService — transcribes live system audio via Core Audio taps + SpeechAnalyzer.
// Uses CATapDescription to capture system audio, which triggers the "System Audio Only"
// permission instead of "Screen & System Audio Recording".

@preconcurrency import AVFoundation
import Combine
import CoreAudio
import CoreMedia
import Speech

// MARK: - ListenService

@MainActor
final class ListenService: ObservableObject {

    enum State { case idle, preparing, running, stopping }

    @Published var state: State = .idle
    @Published var liveFragment: String = ""
    @Published var liveSegments: [OutputFormat.Segment] = []

    /// Called with the raw source-format PCM buffer for each audio chunk (before conversion).
    /// Can be set after `start()` — the tap reads it dynamically via the shared box.
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? {
        get { audioCallbackBox.callback }
        set { audioCallbackBox.callback = newValue }
    }
    private let audioCallbackBox = SendableCallbackBox()

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var audioTap: SystemAudioTap?

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

        let (inputSeq, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = continuation

        // Create Core Audio tap for system audio capture
        let tap: SystemAudioTap
        do {
            tap = try SystemAudioTap(targetFormat: targetFormat)
        } catch {
            state = .idle
            inputContinuation?.finish()
            throw ListenError.audioTapCreationFailed
        }

        let callbackBox = self.audioCallbackBox
        tap.onBuffer = { buffer, converted in
            callbackBox.callback?(buffer)
            continuation.yield(AnalyzerInput(buffer: converted))
        }

        do {
            try tap.start()
        } catch {
            state = .idle
            inputContinuation?.finish()
            throw ListenError.audioTapCreationFailed
        }

        audioTap = tap

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

                    if let idx = segments.firstIndex(where: { CMTimeCompare($0.range.start, result.range.start) == 0 }) {
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
        audioTap?.stop()
        inputContinuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        audioTap          = nil
        analyzer          = nil
        transcriber       = nil
        inputContinuation = nil
        onAudioBuffer     = nil
        state             = .idle
    }
}

// MARK: - SystemAudioTap
// Captures system audio using Core Audio's CATapDescription API.
// This triggers the "System Audio Only" permission instead of "Screen & System Audio Recording".

/// Context passed through the IOProc's clientData pointer.
private final class TapIOContext {
    let sourceFormat: AVAudioFormat
    let targetFormat: AVAudioFormat
    let converter: AVAudioConverter
    var onBuffer: ((_ source: AVAudioPCMBuffer, _ converted: AVAudioPCMBuffer) -> Void)?

    init(sourceFormat: AVAudioFormat, targetFormat: AVAudioFormat, converter: AVAudioConverter) {
        self.sourceFormat = sourceFormat
        self.targetFormat = targetFormat
        self.converter = converter
    }
}

private final class SystemAudioTap: @unchecked Sendable {
    let targetFormat: AVAudioFormat
    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var ioContext: TapIOContext?
    private var retainedContext: Unmanaged<TapIOContext>?
    private let tapUUID = UUID()

    /// Called with (sourceBuffer, convertedBuffer) for each audio chunk.
    var onBuffer: ((_ source: AVAudioPCMBuffer, _ converted: AVAudioPCMBuffer) -> Void)?

    init(targetFormat: AVAudioFormat) throws {
        self.targetFormat = targetFormat

        // Create a global stereo tap excluding the current process
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.name = "BlablaTap"
        tapDesc.uuid = NSUUID(uuidString: tapUUID.uuidString)! as UUID
        tapDesc.muteBehavior = .unmuted
        tapDesc.isPrivate = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard status == noErr else {
            throw ListenError.audioTapCreationFailed
        }
        tapID = newTapID

        // Create aggregate device that includes the tap
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "BlablaAggregateDevice",
            kAudioAggregateDeviceUIDKey: "com.blabla.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceSubDeviceListKey: [] as [Any],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID.uuidString]
            ],
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceIsPrivateKey: true,
        ]

        var newAggID = AudioObjectID(kAudioObjectUnknown)
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAggID)
        guard aggStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw ListenError.audioTapCreationFailed
        }
        aggregateDeviceID = newAggID
    }

    func start() throws {
        // Get the tap's stream format
        let sourceFormat = getTapStreamFormat() ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw ListenError.noCompatibleAudioFormat
        }

        let context = TapIOContext(sourceFormat: sourceFormat, targetFormat: targetFormat, converter: converter)
        context.onBuffer = onBuffer
        ioContext = context

        // Retain context for the C callback
        let retained = Unmanaged.passRetained(context)
        retainedContext = retained
        let clientData = retained.toOpaque()

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcID(aggregateDeviceID, systemAudioIOProc, clientData, &procID)
        guard status == noErr, let procID else {
            retained.release()
            retainedContext = nil
            throw ListenError.audioTapCreationFailed
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateDeviceID, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            retained.release()
            retainedContext = nil
            throw ListenError.audioTapCreationFailed
        }
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        if let retainedContext {
            retainedContext.release()
            self.retainedContext = nil
        }
        ioContext = nil
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit {
        stop()
    }

    private func getTapStreamFormat() -> AVAudioFormat? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioObjectGetPropertyData(aggregateDeviceID, &address, 0, nil, &size, &asbd)
        guard status == noErr else { return nil }

        return AVAudioFormat(streamDescription: &asbd)
    }
}

/// C-compatible IOProc callback for the aggregate audio device.
private func systemAudioIOProc(
    _: AudioObjectID,
    _: UnsafePointer<AudioTimeStamp>,
    inInputData: UnsafePointer<AudioBufferList>,
    _: UnsafePointer<AudioTimeStamp>,
    _: UnsafeMutablePointer<AudioBufferList>,
    _: UnsafePointer<AudioTimeStamp>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inClientData else { return noErr }
    let ctx = Unmanaged<TapIOContext>.fromOpaque(inClientData).takeUnretainedValue()

    let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
    guard abl.count > 0, abl[0].mDataByteSize > 0 else { return noErr }

    guard let source = AVAudioPCMBuffer(pcmFormat: ctx.sourceFormat, bufferListNoCopy: inInputData) else { return noErr }

    let ratio = ctx.targetFormat.sampleRate / ctx.sourceFormat.sampleRate
    let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio))
    guard capacity > 0, let converted = AVAudioPCMBuffer(pcmFormat: ctx.targetFormat, frameCapacity: capacity) else { return noErr }

    var err: NSError?
    nonisolated(unsafe) var consumed = false
    nonisolated(unsafe) let buf = source
    ctx.converter.convert(to: converted, error: &err) { _, status in
        if consumed { status.pointee = .noDataNow; return nil }
        consumed = true; status.pointee = .haveData; return buf
    }

    if err == nil, converted.frameLength > 0 {
        ctx.onBuffer?(source, converted)
    }

    return noErr
}

// MARK: - SendableCallbackBox

/// Thread-safe box so audio callbacks can be set after the tap has started.
final class SendableCallbackBox: @unchecked Sendable {
    var callback: (@Sendable (AVAudioPCMBuffer) -> Void)?
}

// MARK: - Errors

enum ListenError: LocalizedError {
    case speechNotAvailable
    case unsupportedLocale(String)
    case noCompatibleAudioFormat
    case audioTapCreationFailed
    case screenRecordingPermissionDenied

    var errorDescription: String? {
        switch self {
        case .speechNotAvailable:
            return String(localized: "Speech transcription is not available on this device.", bundle: .main)
        case .unsupportedLocale(let id):
            return String(localized: "Locale \"\(id)\" is not supported for transcription.", bundle: .main)
        case .noCompatibleAudioFormat:
            return String(localized: "No compatible audio format available for speech recognition.", bundle: .main)
        case .audioTapCreationFailed:
            return String(localized: "System Audio permission required. Enable it in System Settings → Privacy & Security → System Audio Recording, then relaunch Blabla.", bundle: .main)
        case .screenRecordingPermissionDenied:
            return String(localized: "Screen Recording permission required. Enable it in System Settings → Privacy & Security → Screen Recording, then relaunch Blabla.", bundle: .main)
        }
    }
}
