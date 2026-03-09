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

}
