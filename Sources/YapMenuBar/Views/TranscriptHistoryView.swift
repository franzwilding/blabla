import SwiftUI

struct TranscriptHistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var expandedID: UUID?

    private var filtered: [TranscriptEntry] {
        guard !searchText.isEmpty else { return appState.history }
        return appState.history.filter {
            $0.text.localizedCaseInsensitiveContains(searchText) ||
            $0.source.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Search ─────────────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                TextField("Search transcripts…", text: $searchText)
                    .font(.caption)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))

            Divider()

            if filtered.isEmpty {
                emptyState
            } else {
                List(filtered) { entry in
                    HistoryRowView(entry: entry, isExpanded: expandedID == entry.id) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            expandedID = expandedID == entry.id ? nil : entry.id
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            appState.deleteHistoryEntry(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Copy") { appState.copyToClipboard(entry.text) }
                        Button("Delete", role: .destructive) { appState.deleteHistoryEntry(entry) }
                    }
                }
                .listStyle(.plain)
                .frame(height: 200)
            }

            if !appState.history.isEmpty {
                Divider()
                HStack {
                    Text("\(appState.history.count) transcripts")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Clear All") { appState.clearHistory() }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.quaternary)
            Text(searchText.isEmpty ? "No transcripts yet" : "No results")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - HistoryRowView

private struct HistoryRowView: View {
    let entry: TranscriptEntry
    let isExpanded: Bool
    let onTap: () -> Void
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: sourceIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.source)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Group {
                if isExpanded {
                    Text(entry.text)
                        .textSelection(.enabled)
                } else {
                    Text(entry.preview)
                        .lineLimit(2)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeInOut, value: isExpanded)

            if isExpanded {
                HStack(spacing: 8) {
                    Button {
                        appState.copyToClipboard(entry.text)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc").font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .padding(.vertical, 2)
    }

    private var sourceIcon: String {
        let s = entry.source.lowercased()
        if s.contains("file") { return "doc.waveform" }
        if s.contains("dictation") || s.contains("microphone") { return "mic" }
        return "speaker.wave.2"
    }
}
