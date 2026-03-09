// GlobalHotkeyService — state machine for modifier-key global hotkey control.
// Detects modifier press/release via NSEvent monitors (both global and local)
// and drives push-to-talk / toggle recording modes.

import AppKit
import Combine
import Foundation

@MainActor
final class GlobalHotkeyService: ObservableObject {

    // MARK: - Hotkey key selection

    enum HotkeyKey: String, CaseIterable, Identifiable {
        case fn       = "fn"
        case control  = "control"
        case option   = "option"
        case command  = "command"
        case shift    = "shift"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .fn:      return "Fn"
            case .control: return "Control"
            case .option:  return "Option"
            case .command: return "Command"
            case .shift:   return "Shift"
            }
        }

        /// Compact macOS-style symbol for use in menu shortcut labels.
        var symbol: String {
            switch self {
            case .fn:      return "🌐"
            case .control: return "⌃"
            case .option:  return "⌥"
            case .command: return "⌘"
            case .shift:   return "⇧"
            }
        }

        var modifierFlag: NSEvent.ModifierFlags {
            switch self {
            case .fn:      return .function
            case .control: return .control
            case .option:  return .option
            case .command: return .command
            case .shift:   return .shift
            }
        }
    }

    // MARK: - State machine

    enum HotkeyState: Equatable {
        case idle
        case held   // key held down, dictation active
    }

    @Published var hotkeyState: HotkeyState = .idle

    // MARK: - Callbacks (set by AppState)

    var onStartDictation: (() async -> Void)?
    var onStopDictation: (() async -> Void)?

    // MARK: - Configuration

    /// Which modifier key triggers the hotkey.
    var hotkeyKey: HotkeyKey = .fn

    /// Optional regular key code for a modifier+key combination (e.g. Ctrl+D).
    /// When nil, the hotkey triggers on the modifier key alone.
    var hotkeyKeyCode: UInt16?

    // MARK: - Private state

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isEnabled = false

    // MARK: - Init

    init() {}

    // MARK: - Enable / Disable

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        installMonitors()
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        removeMonitors()

        // If we were in the middle of a hotkey action, cancel it
        if hotkeyState != .idle {
            hotkeyState = .idle
            Task { await onStopDictation?() }
        }
    }

    // MARK: - Monitor installation

    private func installMonitors() {
        // When a key combo is set, also monitor keyDown/keyUp (requires Accessibility).
        // When modifier-only, just flagsChanged is enough.
        let eventMask: NSEvent.EventTypeMask = hotkeyKeyCode != nil
            ? [.flagsChanged, .keyDown, .keyUp]
            : .flagsChanged

        // Global monitor — fires when app is NOT focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }

        // Local monitor — fires when app IS focused (e.g. popover open)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // MARK: - Event handling

    private func handleEvent(_ event: NSEvent) {
        if let keyCode = hotkeyKeyCode {
            // Combo mode: modifier + regular key
            if event.type == .keyDown && event.keyCode == keyCode
                && event.modifierFlags.contains(hotkeyKey.modifierFlag) {
                processKeyState(pressed: true)
            } else if event.type == .keyUp && event.keyCode == keyCode {
                processKeyState(pressed: false)
            }
        } else {
            // Modifier-only mode (original behavior)
            if event.type == .flagsChanged {
                let keyPressed = event.modifierFlags.contains(hotkeyKey.modifierFlag)
                processKeyState(pressed: keyPressed)
            }
        }
    }

    /// Processes a key press/release event through the state machine.
    /// Hold = push-to-talk dictation. Release = stop.
    func processKeyState(pressed: Bool) {
        switch hotkeyState {
        case .idle:
            if pressed {
                hotkeyState = .held
                Task { await onStartDictation?() }
            }

        case .held:
            if !pressed {
                hotkeyState = .idle
                Task { await onStopDictation?() }
            }
        }
    }

    // MARK: - Reset (called when capture is started/stopped via UI)

    func resetToIdle() {
        hotkeyState = .idle
    }

    // MARK: - Key display names

    /// Human-readable name for a virtual key code.
    static func displayName(forKeyCode keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[keyCode] ?? "Key \(keyCode)"
    }

    // No deinit needed — this service lives for the app's lifetime.
    // Monitors are removed via disable() if the user toggles the hotkey off.
}
