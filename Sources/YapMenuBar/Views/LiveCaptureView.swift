import SwiftUI

struct LiveCaptureView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // ── Mode selector ──────────────────────────────────────────────────
            modeSelector
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // ── Live transcript ────────────────────────────────────────────────
            transcriptArea
                .padding(.horizontal, 14)

            // ── Actions ────────────────────────────────────────────────────────
            actionBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Mode selector

    @State private var selectedMode: CaptureMode = .listen

    enum CaptureMode: String, CaseIterable {
        case listen  = "System Audio"
        case dictate = "Microphone"
        case both    = "Both"

        var icon: String {
            switch self {
            case .listen:  return "speaker.wave.2.fill"
            case .dictate: return "mic.fill"
            case .both:    return "waveform.badge.mic"
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 8) {
            if appState.hotkeyService.hotkeyState != .idle {
                hotkeyBadge
            } else {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Button {
                        if !appState.isCapturing { selectedMode = mode }
                    } label: {
                        Label(mode.rawValue, systemImage: mode.icon)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedMode == mode ? Color.accentColor : Color.secondary.opacity(0.12))
                            .foregroundStyle(selectedMode == mode ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isCapturing && selectedMode != mode)
                }
            }
            Spacer()
            startStopButton
        }
    }

    private var hotkeyBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "keyboard")
                .font(.caption2)
            Text(appState.hotkeyService.hotkeyState == .activeUndecided ? "Fn Hold" : "Fn Toggle")
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.orange)
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }

    private var startStopButton: some View {
        Button {
            Task {
                if appState.isCapturing {
                    await appState.stopCapture()
                } else {
                    switch selectedMode {
                    case .listen:  await appState.startListening()
                    case .dictate: await appState.startDictating()
                    case .both:    await appState.startBoth()
                    }
                }
            }
        } label: {
            Label(
                appState.isCapturing ? "Stop" : "Start",
                systemImage: appState.isCapturing ? "stop.fill" : "play.fill"
            )
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(appState.isCapturing ? Color.red : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: [.command])
    }

    // MARK: - Transcript area

    @State private var scrollProxy: ScrollViewProxy? = nil

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if appState.liveText.isEmpty && !appState.isCapturing {
                        placeholderText
                    } else {
                        Text(appState.liveText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .id("transcript")

                        if appState.isCapturing {
                            // Blinking cursor to indicate active recording
                            HStack(spacing: 3) {
                                Spacer()
                                    .frame(width: 10)
                                BlinkingCursor()
                            }
                            .padding(.horizontal, 10)
                            .id("cursor")
                        }
                    }
                }
            }
            .frame(height: 160)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .onChange(of: appState.liveText) {
                withAnimation { proxy.scrollTo("cursor", anchor: .bottom) }
            }
        }
    }

    private var placeholderText: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.quaternary)
            Text("Select a mode and press Start")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            if !appState.liveText.isEmpty {
                Button {
                    appState.copyToClipboard(appState.liveText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button {
                    withAnimation { appState.liveText = "" }
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
            Spacer()
            if !appState.liveText.isEmpty {
                Text("\(appState.liveText.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - BlinkingCursor

private struct BlinkingCursor: View {
    @State private var visible = true
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: 14)
            .opacity(visible ? 1 : 0)
            .onReceive(timer) { _ in visible.toggle() }
    }
}
