import Foundation
import Testing
@testable import Blabla

@MainActor
struct GlobalHotkeyServiceTests {

    @Test func idleTransitionsToHeldOnPress() {
        let sut = GlobalHotkeyService()
        sut.processKeyState(pressed: true)
        #expect(sut.hotkeyState == .held)
    }

    @Test func heldTransitionsToIdleOnRelease() {
        let sut = GlobalHotkeyService()
        sut.processKeyState(pressed: true)
        #expect(sut.hotkeyState == .held)
        sut.processKeyState(pressed: false)
        #expect(sut.hotkeyState == .idle)
    }

    @Test func resetToIdleResetsState() {
        let sut = GlobalHotkeyService()
        sut.processKeyState(pressed: true)
        #expect(sut.hotkeyState == .held)
        sut.resetToIdle()
        #expect(sut.hotkeyState == .idle)
    }

    @Test func startDictationCallbackCalledOnPress() async {
        let sut = GlobalHotkeyService()
        var startCalled = false
        sut.onStartDictation = { startCalled = true }
        sut.processKeyState(pressed: true)
        await Task.yield()
        #expect(startCalled)
    }

    @Test func stopDictationCallbackCalledOnRelease() async {
        let sut = GlobalHotkeyService()
        var stopCalled = false
        sut.onStartDictation = {}
        sut.onStopDictation = { stopCalled = true }
        sut.processKeyState(pressed: true)
        sut.processKeyState(pressed: false)
        await Task.yield()
        #expect(stopCalled)
    }

    @Test func noTransitionOnReleaseInIdle() {
        let sut = GlobalHotkeyService()
        sut.processKeyState(pressed: false)
        #expect(sut.hotkeyState == .idle)
    }

    @Test func duplicatePressStaysHeld() {
        let sut = GlobalHotkeyService()
        sut.processKeyState(pressed: true)
        sut.processKeyState(pressed: true) // duplicate press
        #expect(sut.hotkeyState == .held)
    }

    @Test func fullCyclePressRelease() async {
        let sut = GlobalHotkeyService()
        var started = false
        var stopped = false
        sut.onStartDictation = { started = true }
        sut.onStopDictation = { stopped = true }

        // Press → held, start dictation
        sut.processKeyState(pressed: true)
        #expect(sut.hotkeyState == .held)
        await Task.yield()
        #expect(started)

        // Release → idle, stop dictation
        sut.processKeyState(pressed: false)
        #expect(sut.hotkeyState == .idle)
        await Task.yield()
        #expect(stopped)
    }
}
