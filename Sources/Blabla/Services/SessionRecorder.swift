// SessionRecorder — writes live text and audio files to a configurable folder.
// Text is atomically overwritten on each update (crash-safe). Audio is appended
// as WAV via AVAudioFile (header updated on each write, so partial files are valid).
// All files are created lazily on first write to avoid empty files when
// permissions are missing or capture never produces data.

@preconcurrency import AVFoundation
import Foundation

final class SessionRecorder: @unchecked Sendable {

    enum AudioSource { case system, mic }

    // MARK: - Private state

    private let folder: URL
    let transcriptFileURL: URL
    private let systemAudioURL: URL
    private let micAudioURL: URL

    private let audioQueue = DispatchQueue(label: "SessionRecorder.audio")
    private var systemAudioFile: AVAudioFile?
    private var micAudioFile: AVAudioFile?

    // MARK: - Init

    /// Creates a new session recorder. All files (text + audio) are created lazily
    /// on the first actual write to avoid empty files.
    init(folder: URL, mode: String, fileExtension: String) {
        self.folder = folder
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: Date())
        let base = "\(stamp)_\(mode)"

        transcriptFileURL = folder.appendingPathComponent("\(base).\(fileExtension)")
        systemAudioURL  = folder.appendingPathComponent("\(base)_system.wav")
        micAudioURL     = folder.appendingPathComponent("\(base)_mic.wav")
    }

    // MARK: - Write text (call from main thread)

    func writeText(_ text: String) {
        ensureFolderExists()
        guard let data = text.data(using: .utf8) else { return }
        try? data.write(to: transcriptFileURL, options: .atomic)
    }

    // MARK: - Write audio (call from any thread)

    func writeAudio(buffer: AVAudioPCMBuffer, source: AudioSource) {
        guard buffer.frameLength > 0 else { return }
        audioQueue.sync {
            ensureFolderExists()
            do {
                switch source {
                case .system:
                    if systemAudioFile == nil {
                        systemAudioFile = try AVAudioFile(
                            forWriting: systemAudioURL,
                            settings: buffer.format.settings
                        )
                    }
                    if buffer.format == systemAudioFile?.processingFormat {
                        try systemAudioFile?.write(from: buffer)
                    }
                case .mic:
                    if micAudioFile == nil {
                        micAudioFile = try AVAudioFile(
                            forWriting: micAudioURL,
                            settings: buffer.format.settings
                        )
                    }
                    if buffer.format == micAudioFile?.processingFormat {
                        try micAudioFile?.write(from: buffer)
                    }
                }
            } catch {
                // Best-effort — dropping a buffer is acceptable
            }
        }
    }

    // MARK: - Folder creation

    private func ensureFolderExists() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
