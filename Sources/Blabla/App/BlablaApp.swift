import SwiftUI

@main
struct BlablaApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel(isCapturing: appState.isCapturing, mode: appState.captureMode)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 500, height: 440)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}
