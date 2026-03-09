import Foundation
import Testing
@testable import Blabla

struct TranscriptEntryTests {

    @Test func codableRoundTrip() throws {
        let entry = TranscriptEntry(
            date: Date(timeIntervalSince1970: 1000),
            source: "Test",
            text: "Hello world"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TranscriptEntry.self, from: data)
        #expect(decoded.id == entry.id)
        #expect(decoded.source == entry.source)
        #expect(decoded.text == entry.text)
        #expect(decoded.date == entry.date)
    }
}
