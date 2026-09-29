import SwiftUI
import AppKit

struct AgentPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The UI lives in a status-item popover and floating windows managed by
        // AppDelegate; this scene only satisfies the App protocol. It used to be
        // `Settings { EmptyView() }`, which macOS 26 presents at launch (and on
        // ⌘,) as a blank "AgentPet Settings" window. A never-inserted
        // MenuBarExtra owns no window, so nothing blank can appear.
        // simplify: `.defaultLaunchBehavior(.suppressed)` is the direct fix once
        // the deployment target reaches macOS 15.
        MenuBarExtra("AgentPet", isInserted: .constant(false)) { EmptyView() }
            .commands {
                // Keep the app menu's "Settings…" (⌘,) and route it to the real
                // Settings window.
                CommandGroup(replacing: .appSettings) {
                    Button {
                        SettingsWindowController.shared.show()
                    } label: {
                        // Reuses the existing "Settings" translation.
                        Text(NSLocalizedString("Settings", comment: "app menu") + "…")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
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
        // Load only the selected pet up front so the menu bar + pet appear at
        // once; the rest of the library slices in on later run-loop ticks.
        ImagePetStore.shared.loadFast(priorityID: PetController.shared.selectedPetID)
        if PetController.shared.selectedPetID == nil {
            PetController.shared.selectedPetID = ImagePetStore.shared.packs.first?.id
        }
        // Agent brand icons aren't needed for first paint; warm them after launch.
        Task { @MainActor in AgentIcons.prewarm() }
        PetController.shared.start()
        PetWindowController.shared.start()
        AppDaemon.shared.start()
        OpenUsageClient.shared.start()
        NativeUsageProbe.shared.start()
        CareSyncController.shared.start()
        BreakReminderController.shared.start()
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
