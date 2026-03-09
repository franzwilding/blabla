import Foundation
import Testing
@testable import Blabla

struct HotkeyDisplayTests {

    // MARK: - HotkeyKey.displayName (verbose, for settings UI)

    @Test func displayNameFn() {
        #expect(GlobalHotkeyService.HotkeyKey.fn.displayName == "Fn")
    }

    @Test func displayNameControl() {
        #expect(GlobalHotkeyService.HotkeyKey.control.displayName == "Control")
    }

    @Test func displayNameOption() {
        #expect(GlobalHotkeyService.HotkeyKey.option.displayName == "Option")
    }

    @Test func displayNameCommand() {
        #expect(GlobalHotkeyService.HotkeyKey.command.displayName == "Command")
    }

    @Test func displayNameShift() {
        #expect(GlobalHotkeyService.HotkeyKey.shift.displayName == "Shift")
    }

    // MARK: - HotkeyKey.symbol (compact macOS-style, for menu shortcuts)

    @Test func symbolFnIsGlobe() {
        #expect(GlobalHotkeyService.HotkeyKey.fn.symbol == "Fn")
    }

    @Test func symbolControlIsCaret() {
        #expect(GlobalHotkeyService.HotkeyKey.control.symbol == "⌃")
    }

    @Test func symbolOptionIsAlt() {
        #expect(GlobalHotkeyService.HotkeyKey.option.symbol == "⌥")
    }

    @Test func symbolCommandIsClover() {
        #expect(GlobalHotkeyService.HotkeyKey.command.symbol == "⌘")
    }

    @Test func symbolShiftIsArrow() {
        #expect(GlobalHotkeyService.HotkeyKey.shift.symbol == "⇧")
    }

    // MARK: - All keys have distinct symbols

    @Test func allSymbolsAreDistinct() {
        let symbols = GlobalHotkeyService.HotkeyKey.allCases.map(\.symbol)
        #expect(Set(symbols).count == symbols.count, "All modifier symbols must be unique")
    }

    @Test func allDisplayNamesAreDistinct() {
        let names = GlobalHotkeyService.HotkeyKey.allCases.map(\.displayName)
        #expect(Set(names).count == names.count, "All display names must be unique")
    }

    // MARK: - displayName(forKeyCode:) static helper

    @Test func keyCodeDisplayNameForLetters() {
        // keyCode 0 = A, 2 = D
        #expect(GlobalHotkeyService.displayName(forKeyCode: 0) == "A")
        #expect(GlobalHotkeyService.displayName(forKeyCode: 2) == "D")
    }

    @Test func keyCodeDisplayNameForFunctionKeys() {
        #expect(GlobalHotkeyService.displayName(forKeyCode: 122) == "F1")
        #expect(GlobalHotkeyService.displayName(forKeyCode: 111) == "F12")
    }

    @Test func keyCodeDisplayNameForArrows() {
        #expect(GlobalHotkeyService.displayName(forKeyCode: 123) == "←")
        #expect(GlobalHotkeyService.displayName(forKeyCode: 124) == "→")
        #expect(GlobalHotkeyService.displayName(forKeyCode: 125) == "↓")
        #expect(GlobalHotkeyService.displayName(forKeyCode: 126) == "↑")
    }

    @Test func keyCodeDisplayNameForUnknownKeyCode() {
        let name = GlobalHotkeyService.displayName(forKeyCode: 999)
        #expect(name.contains("999"), "Unknown key code should include the code number")
    }

    @Test func keyCodeDisplayNameForSpecialKeys() {
        #expect(GlobalHotkeyService.displayName(forKeyCode: 36) == "Return")
        #expect(GlobalHotkeyService.displayName(forKeyCode: 48) == "Tab")
        #expect(GlobalHotkeyService.displayName(forKeyCode: 49) == "Space")
        #expect(GlobalHotkeyService.displayName(forKeyCode: 51) == "Delete")
        #expect(GlobalHotkeyService.displayName(forKeyCode: 53) == "Escape")
    }
}
