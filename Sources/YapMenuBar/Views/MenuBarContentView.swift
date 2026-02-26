import SwiftUI

// MARK: - MenuBarContentView

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState

    enum Tab: String, CaseIterable {
        case capture = "Capture"
        case file    = "File"
        case history = "History"

        var icon: String {
            switch self {
            case .capture: return "waveform"
            case .file:    return "doc.badge.waveform"
            case .history: return "clock"
            }
        }
    }

    @State private var selectedTab: Tab = .capture

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────────
            header

            Divider()

            // ── Tab bar ─────────────────────────────────────────────────────────
            tabBar

            Divider()

            // ── Content ─────────────────────────────────────────────────────────
            Group {
                switch selectedTab {
                case .capture: LiveCaptureView()
                case .file:    TranscribeFileView()
                case .history: TranscriptHistoryView()
                }
            }
            .environmentObject(appState)

            // ── Error banner ─────────────────────────────────────────────────────
            if let msg = appState.errorMessage {
                errorBanner(msg)
            }

            // ── Footer ───────────────────────────────────────────────────────────
            footer
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Sub-views

    private var header: some View {
        HStack {
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            Text("YapBar")
                .font(.headline)
            Spacer()
            if appState.isCapturing {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .symbolEffect(.pulse)
                    Text(appState.captureMode.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            settingsButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(tab.rawValue)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.12) : .clear)
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var settingsButton: some View {
        Button {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            Image(systemName: "gear")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Open Settings (⌘,)")
        .keyboardShortcut(",", modifiers: [.command])
    }

    private var footer: some View {
        HStack {
            Text("YapBar")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                appState.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - AppState.CaptureMode helpers

extension AppState.CaptureMode {
    var displayName: String {
        switch self {
        case .idle:      return "Idle"
        case .listening: return "Listening"
        case .dictating: return "Dictating"
        case .both:      return "Listen & Dictate"
        }
    }
}
