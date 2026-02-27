import Foundation

struct TranscriptEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let source: String   // "System Audio", "Dictation", "File: foo.mp4", …
    let text: String

    init(date: Date = .now, source: String, text: String) {
        id     = UUID()
        self.date   = date
        self.source = source
        self.text   = text
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 120
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}
