import AppKit
import Foundation
import UserNotifications
import AgentPetCore

/// Backs the onboarding/Settings window: notification permission status and
/// per-agent hook install state, with the actions to change them.
@MainActor
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    enum NotificationState: Equatable {
        case unavailable   // running as bare binary, no bundle
        case notDetermined
        case enabled
        case denied
    }

    @Published private(set) var notificationState: NotificationState = .notDetermined
    @Published private(set) var installedKinds: Set<AgentKind> = []

    /// Why the last install/uninstall failed (e.g. an unwritable or corrupt
    /// settings file), shown next to the agent list. Cleared on success.
    @Published private(set) var lastHookError: String?

    /// In-app notification toggle: lets users mute alerts even after granting
    /// the macOS permission. Defaults to on.
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: NotificationManager.enabledKey) }
    }

    let agents = AgentCatalog.all

    init() {
        notificationsEnabled = (UserDefaults.standard.object(forKey: NotificationManager.enabledKey) as? Bool) ?? true
    }

    func refresh() {
        var set: Set<AgentKind> = []
        for agent in agents where agent.isSupported {
            if let spec = AgentHooks.spec(for: agent.kind),
               HookInstaller.isInstalledOnDisk(path: spec.settingsPath, events: spec.events, style: spec.style) {
                set.insert(agent.kind)
            }
        }
        installedKinds = set
        refreshNotificationState()
    }

    func isInstalled(_ kind: AgentKind) -> Bool {
        installedKinds.contains(kind)
    }

    /// Re-applies hooks for already-installed agents once per app version, so
    /// existing users pick up newly-added events (e.g. SessionEnd for instant
    /// clear on quit) without manually re-installing. Idempotent and only
    /// touches our own hook entries.
    func migrateInstalledHooksIfNeeded() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let key = "agentpet.hookMigration.\(version)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        for agent in agents where agent.isSupported {
            guard let spec = AgentHooks.spec(for: agent.kind),
                  HookInstaller.isInstalledOnDisk(path: spec.settingsPath, events: spec.events, style: spec.style)
            else { continue }
            try? HookInstaller.installToDisk(command: hookCommand(for: agent.kind),
                                             path: spec.settingsPath, events: spec.events, style: spec.style)
        }
    }

    private func hookCommand(for kind: AgentKind) -> String {
        let path = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "agentpet"
        return "\"\(path)\" hook --agent \(kind.rawValue)"
    }

    func toggleInstall(_ kind: AgentKind) {
        guard let spec = AgentHooks.spec(for: kind) else { return }
        do {
            if installedKinds.contains(kind) {
                try HookInstaller.uninstallFromDisk(path: spec.settingsPath, events: spec.events, style: spec.style)
            } else {
                try HookInstaller.installToDisk(command: hookCommand(for: kind), path: spec.settingsPath, events: spec.events, style: spec.style)
            }
            lastHookError = nil
        } catch {
            lastHookError = error.localizedDescription
        }
        refresh()
    }

    func enableNotifications() {
        guard NotificationManager.shared.isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in self.refreshNotificationState() }
        }
    }

    /// Opens System Settings to AgentPet's notification pane (used when denied).
    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshNotificationState() {
        guard NotificationManager.shared.isAvailable else {
            notificationState = .unavailable
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .authorized, .provisional, .ephemeral:
                    self.notificationState = .enabled
                case .denied:
                    self.notificationState = .denied
                default:
                    self.notificationState = .notDetermined
                }
            }
        }
    }
}
