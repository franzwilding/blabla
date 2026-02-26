import SwiftUI

@main
struct YapMenuBarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
                .frame(width: 400)
        } label: {
            MenuBarLabel(isCapturing: appState.isCapturing, mode: appState.captureMode)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 480, height: 320)
        }
    }
}
