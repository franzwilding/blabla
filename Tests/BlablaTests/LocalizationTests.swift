import Foundation
import Testing
@testable import Blabla

struct LocalizationTests {

    /// Resolves to the SPM package root by walking up from this test file.
    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // BlablaTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // package root
    }

    private static func loadStrings(localization: String) throws -> [String: String] {
        let url = packageRoot
            .appendingPathComponent("Sources/Blabla/Resources/\(localization).lproj/Localizable.strings")
        let dict = NSDictionary(contentsOf: url) as? [String: String]
        return try #require(dict, "Could not load \(localization).lproj/Localizable.strings")
    }

    @Test func allEnglishKeysExistInGerman() throws {
        let enDict = try Self.loadStrings(localization: "en")
        let deDict = try Self.loadStrings(localization: "de")

        let missingInDe = Set(enDict.keys).subtracting(Set(deDict.keys))
        #expect(missingInDe.isEmpty, "Keys missing in de.lproj: \(missingInDe.sorted())")
    }

    @Test func allGermanKeysExistInEnglish() throws {
        let enDict = try Self.loadStrings(localization: "en")
        let deDict = try Self.loadStrings(localization: "de")

        let missingInEn = Set(deDict.keys).subtracting(Set(enDict.keys))
        #expect(missingInEn.isEmpty, "Keys missing in en.lproj: \(missingInEn.sorted())")
    }

    @Test func noEmptyValuesInEnglish() throws {
        let enDict = try Self.loadStrings(localization: "en")
        let emptyKeys = enDict.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.key)
        #expect(emptyKeys.isEmpty, "Empty values in en.lproj: \(emptyKeys.sorted())")
    }

    @Test func noEmptyValuesInGerman() throws {
        let deDict = try Self.loadStrings(localization: "de")
        let emptyKeys = deDict.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.key)
        #expect(emptyKeys.isEmpty, "Empty values in de.lproj: \(emptyKeys.sorted())")
    }
}
