import AppKit
import Sparkle

/// Owns the Sparkle updater: background checks against the appcast feed
/// (configured via SUFeedURL / SUPublicEDKey in Info.plist) plus a manual
/// "Check for Updates…" entry point from the menu bar.
@MainActor
final class UpdaterController: NSObject, ObservableObject {
    static let shared = UpdaterController()

    /// True while an update has been downloaded and is waiting to install.
    /// The menu bar footer "Updates" button can observe this to show a badge.
    @Published private(set) var updatePending = false

    // lazy so `self` is valid when SPUStandardUpdaterController captures the
    // delegate reference. init() triggers the lazy body immediately after
    // super.init() so the updater's background timer starts on first launch.
    private lazy var controller: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(startingUpdater: true,
                                     updaterDelegate: self,
                                     userDriverDelegate: nil)
    }()

    override init() {
        super.init()
        _ = controller  // trigger lazy init now that self is live
    }

    /// User-initiated check (shows "you're up to date" if nothing is newer).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdaterController: SPUUpdaterDelegate {
    /// Silently absorbs background-check errors (network offline, appcast
    /// unreachable, etc.) so they never surface as unexpected alerts.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let ns = error as NSError
        // SUNoUpdateError (1000) and user-cancellation (1001) are not real failures.
        guard ns.domain == "SUSparkleErrorDomain" && (ns.code == 1000 || ns.code == 1001) else {
            print("[AgentPet] Update check aborted (\(ns.domain) \(ns.code)): \(error.localizedDescription)")
            return
        }
    }

    /// Mark a pending update so the UI can show a badge.
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor [weak self] in self?.updatePending = true }
    }

    /// Clear the badge once an update is dismissed or applied.
    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor [weak self] in self?.updatePending = false }
    }

    /// Warn via notification if an update restarts the app while agents are active,
    /// so users understand why sessions disappeared.
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        Task { @MainActor in
            let busy = AppDaemon.shared.sessions.contains {
                $0.state == .working || $0.state == .waiting
            }
            guard busy else { return }
            NotificationManager.shared.notify(
                title: "AgentPet Updated",
                body: "Active agent sessions were cleared because the app restarted to apply an update."
            )
        }
    }
}
