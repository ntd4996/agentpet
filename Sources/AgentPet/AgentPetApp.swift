import SwiftUI
import AppKit

@main
struct AgentPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("AgentPet", systemImage: "pawprint.fill") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Runs the app as a menu bar accessory (no Dock icon), replacing the
/// LSUIElement Info.plist key that a bare SwiftPM executable lacks.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
