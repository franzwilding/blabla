import Foundation
import Testing
@testable import Blabla

struct SessionRecorderTests {

    private func makeTempFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BlablaTests_\(UUID().uuidString)")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func writeTextCreatesFileAndFolder() throws {
        let tmp = makeTempFolder()
        defer { cleanup(tmp) }

        let recorder = SessionRecorder(folder: tmp, mode: "Test", fileExtension: "txt")
        recorder.writeText("Hello")

        let content = try String(contentsOf: recorder.transcriptFileURL, encoding: .utf8)
        #expect(content == "Hello")
    }

    @Test func writeTextOverwritesPreviousContent() throws {
        let tmp = makeTempFolder()
        defer { cleanup(tmp) }

        let recorder = SessionRecorder(folder: tmp, mode: "Test", fileExtension: "txt")
        recorder.writeText("First")
        recorder.writeText("Second")

        let content = try String(contentsOf: recorder.transcriptFileURL, encoding: .utf8)
        #expect(content == "Second")
    }

    @Test func nestedFolderIsCreatedAutomatically() {
        let tmp = makeTempFolder().appendingPathComponent("nested")
        defer { cleanup(tmp.deletingLastPathComponent()) }

        let recorder = SessionRecorder(folder: tmp, mode: "Test", fileExtension: "txt")
        recorder.writeText("test")

        #expect(FileManager.default.fileExists(atPath: tmp.path))
    }

    @Test func transcriptFileURLHasCorrectExtension() {
        let tmp = makeTempFolder()
        let recorder = SessionRecorder(folder: tmp, mode: "Test", fileExtension: "vtt")
        #expect(recorder.transcriptFileURL.pathExtension == "vtt")
    }
}
