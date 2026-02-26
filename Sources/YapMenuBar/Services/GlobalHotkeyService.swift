// GlobalHotkeyService — state machine for Fn-key global hotkey control.
// Detects Fn press/release via NSEvent monitors (both global and local)
// and drives push-to-talk / toggle recording modes.

import AppKit
import Combine
import Foundation

@MainActor
final class GlobalHotkeyService: ObservableObject {

    // MARK: - State machine

    enum HotkeyState: Equatable {
        case idle
        case activeUndecided   // Fn pressed, capture started, waiting to see tap vs hold
        case toggleActive      // Tap detected, recording with speaker labels
    }

    @Published var hotkeyState: HotkeyState = .idle

    // MARK: - Callbacks (set by AppState)

    var onStartBoth: (() async -> Void)?
    var onStopCapture: (() async -> Void)?
    var onEnableSpeakerLabels: (() -> Void)?

    // MARK: - Configuration

    /// Minimum hold duration (seconds) to distinguish hold from tap.
    private let holdThreshold: TimeInterval = 0.3

    // MARK: - Private state

    private var fnPressTimestamp: Date?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isEnabled = false

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
            Task { await onStopCapture?() }
        }
    }

    // MARK: - Monitor installation

    private func installMonitors() {
        // Global monitor — fires when app is NOT focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        // Local monitor — fires when app IS focused (e.g. popover open)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
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

    private func handleFlagsChanged(_ event: NSEvent) {
        let fnPressed = event.modifierFlags.contains(.function)

        switch hotkeyState {
        case .idle:
            if fnPressed {
                // Fn key down while idle → start capture, enter undecided state
                fnPressTimestamp = Date()
                hotkeyState = .activeUndecided
                Task { await onStartBoth?() }
            }

        case .activeUndecided:
            if !fnPressed {
                // Fn key released — check hold duration
                let holdDuration = Date().timeIntervalSince(fnPressTimestamp ?? Date())
                fnPressTimestamp = nil

                if holdDuration >= holdThreshold {
                    // Long hold → push-to-talk, stop capture
                    hotkeyState = .idle
                    Task { await onStopCapture?() }
                } else {
                    // Short tap → toggle mode with speaker labels
                    hotkeyState = .toggleActive
                    onEnableSpeakerLabels?()
                }
            }

        case .toggleActive:
            if fnPressed {
                // Fn pressed again while toggle-active → stop capture
                hotkeyState = .idle
                Task { await onStopCapture?() }
            }
        }
    }

    // MARK: - Reset (called when capture is started/stopped via UI)

    func resetToIdle() {
        hotkeyState = .idle
        fnPressTimestamp = nil
    }

    // No deinit needed — this service lives for the app's lifetime.
    // Monitors are removed via disable() if the user toggles the hotkey off.
}
