// SessionRecorder — writes live text and audio files to a configurable folder.
// Text is atomically overwritten on each update (crash-safe). Audio is appended
// as WAV via AVAudioFile (header updated on each write, so partial files are valid).

@preconcurrency import AVFoundation
import Foundation

final class SessionRecorder: @unchecked Sendable {

    enum AudioSource { case system, mic }

    // MARK: - Private state

    private let textFileURL: URL
    private let systemAudioURL: URL
    private let micAudioURL: URL

    private let audioQueue = DispatchQueue(label: "SessionRecorder.audio")
    private var systemAudioFile: AVAudioFile?
    private var micAudioFile: AVAudioFile?

    // MARK: - Init

    /// Creates a new session recorder. The text file is created immediately (empty);
    /// audio files are created lazily on the first buffer to avoid empty WAV files
    /// when a source never produces audio.
    init(folder: URL, mode: String) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: Date())
        let base = "\(stamp)_\(mode)"

        textFileURL     = folder.appendingPathComponent("\(base).txt")
        systemAudioURL  = folder.appendingPathComponent("\(base)_system.wav")
        micAudioURL     = folder.appendingPathComponent("\(base)_mic.wav")

        // Ensure folder exists
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Create empty text file immediately (proves session started)
        try Data().write(to: textFileURL, options: .atomic)
    }

    // MARK: - Write text (call from main thread)

    func writeText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        try? data.write(to: textFileURL, options: .atomic)
    }

    // MARK: - Write audio (call from any thread)

    func writeAudio(buffer: AVAudioPCMBuffer, source: AudioSource) {
        guard buffer.frameLength > 0 else { return }
        audioQueue.sync {
            do {
                switch source {
                case .system:
                    if systemAudioFile == nil {
                        systemAudioFile = try AVAudioFile(
                            forWriting: systemAudioURL,
                            settings: buffer.format.settings
                        )
                    }
                    try systemAudioFile?.write(from: buffer)
                case .mic:
                    if micAudioFile == nil {
                        micAudioFile = try AVAudioFile(
                            forWriting: micAudioURL,
                            settings: buffer.format.settings
                        )
                    }
                    try micAudioFile?.write(from: buffer)
                }
            } catch {
                // Best-effort — dropping a buffer is acceptable
            }
        }
    }

    // MARK: - Finalize

    /// Nils audio file references, flushing OS buffers. Call when session ends.
    func finalize() {
        audioQueue.sync {
            systemAudioFile = nil
            micAudioFile = nil
        }
    }
}
