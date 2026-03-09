import Testing
@testable import Blabla

struct CaptureModeTests {

    @Test func allModesHaveNonEmptyLabels() {
        let modes: [AppState.CaptureMode] = [.idle, .listening, .dictating, .both]
        for mode in modes {
            #expect(!mode.label.isEmpty, "\(mode) should have a non-empty label")
        }
    }

    @Test func allModesHaveDistinctLabels() {
        let modes: [AppState.CaptureMode] = [.idle, .listening, .dictating, .both]
        let labels = modes.map(\.label)
        #expect(Set(labels).count == labels.count, "All mode labels should be distinct")
    }
}
