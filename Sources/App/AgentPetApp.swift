import SwiftUI
import AppKit

struct AgentPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The UI lives in a status-item popover and floating windows managed by
        // AppDelegate; this empty scene just satisfies the App protocol.
        Settings { EmptyView() }
    }
}

/// Runs the app as a menu bar accessory (no Dock icon) and boots the daemon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Held strongly so the Sparkle updater delegate and background timers are
    // never deallocated for the lifetime of the app.
    private var updater: UpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ImagePetStore.shared.reload()
        if PetController.shared.selectedPetID == nil {
            PetController.shared.selectedPetID = ImagePetStore.shared.packs.first?.id
        }
        AgentIcons.prewarm()
        PetController.shared.start()
        PetWindowController.shared.start()
        AppDaemon.shared.start()
        SettingsModel.shared.migrateInstalledHooksIfNeeded()
        SettingsModel.shared.repairStaleHookPathsIfNeeded()
        updater = UpdaterController.shared
        StatusBarController.shared.start()
        DefaultPetBootstrap.installIfNeeded()
        SettingsWindowController.shared.showOnFirstLaunch()
    }
}
