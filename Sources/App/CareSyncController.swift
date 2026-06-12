import AppKit
import Foundation
import AgentPetCore

/// Pushes per-pet care stats to the community site so the user's web profile
/// shows their companions' levels. Linked once by signing in with GitHub in
/// the browser (the site bounces back via `agentpet://link`); afterwards stats
/// sync in the background (debounced after each feeding, and on launch).
@MainActor
final class CareSyncController: ObservableObject {
    static let shared = CareSyncController()

    /// True when a device token is stored (the app is linked to a profile).
    @Published private(set) var linked: Bool
    /// GitHub login of the linked profile, for the Care tab caption.
    @Published private(set) var linkedLogin: String?
    /// Last sync result, for the Care tab's status caption.
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?

    private static let tokenKey = "agentpet.care.syncToken"
    private static let loginKey = "agentpet.care.syncLogin"
    static let base = URL(string: "https://agentpet.thenightwatcher.online")!

    private var debounce: Timer?

    init() {
        linked = UserDefaults.standard.string(forKey: Self.tokenKey) != nil
        linkedLogin = UserDefaults.standard.string(forKey: Self.loginKey)
    }

    func start() {
        guard linked else { return }
        scheduleSync(after: 5)
    }

    // MARK: - Linking

    /// Opens the site's sign-in flow; it ends with an `agentpet://link` bounce
    /// handled by the app delegate, which calls `adopt`.
    func beginLink() {
        NSWorkspace.shared.open(Self.base.appendingPathComponent("link-app"))
    }

    /// Stores the device token delivered by the `agentpet://link` URL.
    func adopt(token: String, login: String) {
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        if login.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.loginKey)
            linkedLogin = nil
        } else {
            UserDefaults.standard.set(login, forKey: Self.loginKey)
            linkedLogin = login
        }
        linked = true
        lastError = nil
        scheduleSync(after: 1)
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.loginKey)
        linked = false
        linkedLogin = nil
        lastSyncAt = nil
        lastError = nil
    }

    // MARK: - Sync

    /// Debounced push — call freely after every feeding.
    func scheduleSync(after seconds: TimeInterval = 30) {
        guard linked else { return }
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor [weak self] in await self?.push() }
        }
    }

    func push() async {
        guard let token = UserDefaults.standard.string(forKey: Self.tokenKey) else { return }
        let states = PetCareController.shared.states
        guard !states.isEmpty else { return }

        let pets: [[String: Any]] = states.map { id, s in
            let name = ImagePetStore.shared.pack(id: id)?.displayName ?? id
            return [
                "id": id,
                "name": name,
                "xp": s.xp,
                "tokens": s.totalTokens,
                "meals": s.totalMeals,
                "streak": s.streakDays,
                "lastFedAt": s.lastFedAt.map { Int($0.timeIntervalSince1970) } as Any,
            ]
        }

        var request = URLRequest(url: Self.base.appendingPathComponent("api/care/sync"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["pets": pets])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                lastSyncAt = Date()
                lastError = nil
            } else if status == 401 {
                // Token revoked from the web side: unlink quietly.
                disconnect()
            } else {
                lastError = NSLocalizedString("Sync failed, will retry.", comment: "")
                scheduleSync(after: 300)
            }
        } catch {
            lastError = NSLocalizedString("Sync failed, will retry.", comment: "")
            scheduleSync(after: 300)
        }
    }
}
