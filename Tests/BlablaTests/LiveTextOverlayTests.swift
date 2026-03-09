import Foundation
import Testing
@testable import Blabla

struct LiveTextOverlayTests {

    // MARK: - OverlayTextModel

    @MainActor
    @Test func overlayTextModelInitiallyEmpty() {
        let model = OverlayTextModel()
        #expect(model.text == "")
    }

    @MainActor
    @Test func overlayTextModelUpdatesText() {
        let model = OverlayTextModel()
        model.text = "Hello World"
        #expect(model.text == "Hello World")
    }

    @MainActor
    @Test func overlayTextModelCanBeCleared() {
        let model = OverlayTextModel()
        model.text = "Some transcript"
        model.text = ""
        #expect(model.text == "")
    }

    // MARK: - LiveTextOverlayController

    @MainActor
    @Test func controllerCanBeCreated() {
        // Verify the controller can be instantiated without crashing
        let controller = LiveTextOverlayController()
        _ = controller // suppress unused warning
    }
}
