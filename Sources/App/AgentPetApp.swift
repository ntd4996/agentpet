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
        _ = AppLanguage.shared   // apply the saved language before any UI renders
        ImagePetStore.shared.reload()
        if PetController.shared.selectedPetID == nil {
            PetController.shared.selectedPetID = ImagePetStore.shared.packs.first?.id
        }
        AgentIcons.prewarm()
        PetController.shared.start()
        PetWindowController.shared.start()
        AppDaemon.shared.start()
        OpenUsageClient.shared.start()
        CareSyncController.shared.start()
        SettingsModel.shared.migrateInstalledHooksIfNeeded()
        SettingsModel.shared.repairStaleHookPathsIfNeeded()
        updater = UpdaterController.shared
        StatusBarController.shared.start()
        DefaultPetBootstrap.installIfNeeded()
        SettingsWindowController.shared.showOnFirstLaunch()
    }

    /// Handles `agentpet://link?token=…&login=…` — the tail of the web's
    /// GitHub sign-in, which links this app to the user's profile with no
    /// manual code entry.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "agentpet" && url.host == "link" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let token = items.first(where: { $0.name == "token" })?.value ?? ""
            let login = items.first(where: { $0.name == "login" })?.value ?? ""
            guard !token.isEmpty else { continue }
            CareSyncController.shared.adopt(token: token, login: login)
        }
    }
}
