import CoreMedia
import Testing
@testable import Blabla

struct OutputFormatTests {

    // MARK: - srtTime / vttTime

    @Test func srtTimeFormatsZero() {
        #expect(OutputFormat.srtTime(0) == "00:00:00,000")
    }

    @Test func srtTimeFormatsMinutesAndMilliseconds() {
        #expect(OutputFormat.srtTime(61.5) == "00:01:01,500")
    }

    @Test func srtTimeFormatsHours() {
        #expect(OutputFormat.srtTime(3661.123) == "01:01:01,123")
    }

    @Test func vttTimeFormatsZero() {
        #expect(OutputFormat.vttTime(0) == "00:00:00.000")
    }

    @Test func vttTimeFormatsMinutesAndMilliseconds() {
        #expect(OutputFormat.vttTime(61.5) == "00:01:01.500")
    }

    @Test func vttTimeFormatsHours() {
        #expect(OutputFormat.vttTime(3661.123) == "01:01:01.123")
    }

    @Test func srtUsesCommaVttUsesDot() {
        let t: TimeInterval = 1.234
        let srt = OutputFormat.srtTime(t)
        let vtt = OutputFormat.vttTime(t)
        #expect(srt.contains(","))
        #expect(vtt.contains("."))
        #expect(!srt.contains("."))
    }

    // MARK: - formatSegment

    private func makeRange(start: Double, end: Double) -> CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 1000),
            end: CMTime(seconds: end, preferredTimescale: 1000)
        )
    }

    @Test func formatSegmentTxtReturnsPlainText() {
        let range = makeRange(start: 0, end: 1)
        let result = OutputFormat.txt.formatSegment(index: 1, timeRange: range, text: "Hello")
        #expect(result == "Hello")
    }

    @Test func formatSegmentSrtContainsIndexAndTimestamps() {
        let range = makeRange(start: 1.0, end: 2.5)
        let result = OutputFormat.srt.formatSegment(index: 1, timeRange: range, text: "Hello")
        #expect(result.contains("1\n"))
        #expect(result.contains("00:00:01,000"))
        #expect(result.contains("00:00:02,500"))
        #expect(result.contains("Hello"))
    }

    @Test func formatSegmentVttContainsTimestamps() {
        let range = makeRange(start: 1.0, end: 2.5)
        let result = OutputFormat.vtt.formatSegment(index: 1, timeRange: range, text: "Hello")
        #expect(result.contains("00:00:01.000"))
        #expect(result.contains("00:00:02.500"))
        #expect(result.contains("Hello"))
    }

    @Test func formatSegmentJsonContainsFields() {
        let range = makeRange(start: 1.0, end: 2.5)
        let result = OutputFormat.json.formatSegment(index: 1, timeRange: range, text: "Hello")
        #expect(result.contains("\"text\""))
        #expect(result.contains("Hello"))
        #expect(result.contains("\"id\""))
        #expect(result.contains("\"start\""))
        #expect(result.contains("\"end\""))
    }

    @Test func formatSegmentSrtWithSpeaker() {
        let range = makeRange(start: 0, end: 1)
        let result = OutputFormat.srt.formatSegment(index: 1, timeRange: range, text: "Hello", speaker: "Alice")
        #expect(result.contains("Alice: Hello"))
    }

    @Test func formatSegmentVttWithSpeaker() {
        let range = makeRange(start: 0, end: 1)
        let result = OutputFormat.vtt.formatSegment(index: 1, timeRange: range, text: "Hello", speaker: "Alice")
        #expect(result.contains("<v Alice>Hello"))
    }
}
