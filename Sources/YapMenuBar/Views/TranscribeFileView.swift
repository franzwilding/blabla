import SwiftUI
import UniformTypeIdentifiers

struct TranscribeFileView: View {
    @EnvironmentObject var appState: AppState

    @State private var isTargeted = false
    @State private var selectedFile: URL?
    @State private var result: String = ""

    private static let supportedTypes: [UTType] = [
        .audio, .movie, .mpeg4Audio, .mp3,
        UTType("public.aifc-audio") ?? .audio,
        UTType("com.apple.m4a-audio") ?? .audio,
    ]

    var body: some View {
        VStack(spacing: 10) {
            // ── Drop zone ─────────────────────────────────────────────────────
            dropZone
                .padding(.horizontal, 14)
                .padding(.top, 12)

            // ── Result ────────────────────────────────────────────────────────
            if !result.isEmpty || appState.isTranscribingFile {
                resultArea
                    .padding(.horizontal, 14)
            }

            Spacer(minLength: 8)
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                )

            VStack(spacing: 10) {
                if let url = selectedFile {
                    // Selected file info
                    HStack(spacing: 8) {
                        Image(systemName: "doc.waveform.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            selectedFile = nil
                            result = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)

                    Button {
                        Task { await transcribe(url) }
                    } label: {
                        if appState.isTranscribingFile {
                            Label(String(localized: "Transcribing…", bundle: .module), systemImage: "ellipsis")
                        } else {
                            Label(String(localized: "Transcribe", bundle: .module), systemImage: "waveform")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(appState.isTranscribingFile)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "Drop an audio or video file", bundle: .module))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Choose File…", bundle: .module)) { openFilePicker() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(20)
        }
        .frame(height: 130)
        .onDrop(of: Self.supportedTypes, isTargeted: $isTargeted) { providers in
            guard let item = providers.first else { return false }
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    selectedFile = url
                    result = ""
                    Task { await transcribe(url) }
                }
            }
            return true
        }
    }

    // MARK: - Result area

    private var resultArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.isTranscribingFile {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Transcribing…", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if !result.isEmpty {
                ScrollView {
                    Text(result)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 110)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                HStack(spacing: 8) {
                    Button {
                        appState.copyToClipboard(result)
                    } label: {
                        Label(String(localized: "Copy", bundle: .module), systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Text(String(localized: "\(result.count) chars", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose audio or video file", bundle: .module)
        panel.allowedContentTypes = Self.supportedTypes
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            selectedFile = url
            result = ""
            Task { await transcribe(url) }
        }
    }

    private func transcribe(_ url: URL) async {
        await appState.transcribeFile(url)
        // Pull the latest transcript from history
        if let entry = appState.history.first {
            result = entry.text
        }
    }
}
