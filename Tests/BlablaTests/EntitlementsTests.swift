import Foundation
import Testing
@testable import Blabla

struct EntitlementsTests {

    private let entitlementsURL: URL? = {
        // The entitlements file is excluded from the bundle, so we locate it relative to the project root.
        // In tests the working directory is the package root.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // BlablaTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // project root
            .appendingPathComponent("Sources/Blabla/Resources/Blabla.entitlements")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }()

    private func loadEntitlements() throws -> [String: Any] {
        let url = try #require(entitlementsURL, "Blabla.entitlements file must exist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test func entitlementsFileExists() {
        #expect(entitlementsURL != nil, "Blabla.entitlements must exist at Sources/Blabla/Resources/")
    }

    @Test func containsAudioInputEntitlement() throws {
        let dict = try loadEntitlements()
        let value = dict["com.apple.security.device.audio-input"] as? Bool
        #expect(value == true, "audio-input entitlement must be true for AVAudioEngine mic capture")
    }

    @Test func containsMicrophoneEntitlement() throws {
        let dict = try loadEntitlements()
        let value = dict["com.apple.security.device.microphone"] as? Bool
        #expect(value == true, "microphone entitlement must be true for dictation")
    }

    @Test func containsScreenCaptureEntitlement() throws {
        let dict = try loadEntitlements()
        let value = dict["com.apple.security.screen-capture"] as? Bool
        #expect(value == true, "screen-capture entitlement must be true for system audio tap")
    }

    @Test func allRequiredEntitlementsPresent() throws {
        let dict = try loadEntitlements()
        let required = [
            "com.apple.security.device.audio-input",
            "com.apple.security.device.microphone",
            "com.apple.security.screen-capture",
        ]
        for key in required {
            #expect(dict[key] != nil, "Required entitlement '\(key)' is missing")
        }
    }
}
