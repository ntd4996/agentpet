import AppKit
import Foundation
@preconcurrency import UserNotifications
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
    /// Surfaced when an install/uninstall fails (e.g. an agent's settings file is
    /// not valid JSON), so the user sees why instead of a silent no-op.
    @Published var installError: String?

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

    /// Repairs hook entries whose embedded binary path no longer matches the
    /// current executable location. Runs on every launch so hooks stay valid
    /// after the app is moved, re-downloaded, or updated via a different channel
    /// (e.g. Homebrew vs DMG).  Idempotent — only rewrites when the path differs.
    func repairStaleHookPathsIfNeeded() {
        let currentPath = Bundle.main.executablePath ?? ""
        guard !currentPath.isEmpty else { return }
        let expectedCommand = "\"\(currentPath)\" hook"
        for agent in agents where agent.isSupported {
            guard let spec = AgentHooks.spec(for: agent.kind) else { continue }
            guard let settings = try? HookInstaller.readSettings(path: spec.settingsPath) else { continue }
            guard HookInstaller.isInstalledOnDisk(path: spec.settingsPath,
                                                  events: spec.events,
                                                  style: spec.style) else { continue }
            // Check if any stored hook command references a different binary path.
            let needsRepair: Bool = {
                guard let hooks = settings["hooks"] as? [String: Any] else { return false }
                for event in spec.events {
                    guard let groups = hooks[event] as? [[String: Any]] else { continue }
                    for group in groups {
                        guard let inner = group["hooks"] as? [[String: Any]] else { continue }
                        for entry in inner {
                            if let cmd = entry["command"] as? String,
                               cmd.contains("agentpet") && cmd.contains("hook"),
                               !cmd.hasPrefix(expectedCommand) {
                                return true
                            }
                        }
                    }
                }
                return false
            }()
            guard needsRepair else { continue }
            try? HookInstaller.installToDisk(command: hookCommand(for: agent.kind),
                                             path: spec.settingsPath,
                                             events: spec.events,
                                             style: spec.style)
        }
    }

    private func hookCommand(for kind: AgentKind) -> String {
        let path = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "agentpet"
        return "\"\(path)\" hook --agent \(kind.rawValue)"
    }

    func toggleInstall(_ kind: AgentKind) {
        guard let spec = AgentHooks.spec(for: kind) else { return }
        installError = nil
        do {
            if installedKinds.contains(kind) {
                try HookInstaller.uninstallFromDisk(path: spec.settingsPath, events: spec.events, style: spec.style)
            } else {
                try HookInstaller.installToDisk(command: hookCommand(for: kind), path: spec.settingsPath, events: spec.events, style: spec.style)
                // Codex ignores our hooks.json unless its hooks feature is on.
                if kind == .codex {
                    try CodexHookConfig.enableHooksOnDisk()
                }
            }
        } catch {
            installError = error.localizedDescription
        }
        refresh()
    }

    func enableNotifications() {
        guard NotificationManager.shared.isAvailable else { return }
        Task { @MainActor in
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            self.refreshNotificationState()
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
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
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
