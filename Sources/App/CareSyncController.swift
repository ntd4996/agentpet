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
    /// True while a cloud restore is in flight (for the Care tab button).
    @Published private(set) var restoring = false

    private static let tokenKey = "agentpet.care.syncToken"
    private static let loginKey = "agentpet.care.syncLogin"
    static let base = URL(string: "https://agentpet.thenightwatcher.online")!

    private var debounce: Timer?
    private var failCount = 0

    init() {
        linked = UserDefaults.standard.string(forKey: Self.tokenKey) != nil
        linkedLogin = UserDefaults.standard.string(forKey: Self.loginKey)
    }

    func start() {
        guard linked else { return }
        scheduleSync(after: 5)
        if ProjectUsageStore.shared.hasPending { scheduleUsageSync(after: 8) }
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
        // A freshly linked machine pulls existing progress before pushing, so a
        // new device restores its pets instead of starting from scratch.
        Task { [weak self] in
            await self?.restore()
            self?.scheduleSync(after: 1)
            self?.scheduleUsageSync(after: 2)
        }
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

    /// First idle frame as a PNG data URL, so the web profile can show the
    /// actual sprite — including local custom pets the site has never seen.
    /// Rendered at a generous size with nearest-neighbour scaling so the pixel
    /// art stays crisp when the web shrinks it.
    private static func thumbDataURL(for petID: String) -> String? {
        guard let frame = ImagePetStore.shared.pack(id: petID)?.clip(0).first else { return nil }
        let size = frame.size
        guard size.width > 0, size.height > 0 else { return nil }
        // Integer upscale to ~128px so the sprite is sharp at any display size.
        let maxSide: CGFloat = 128
        let scale = max(1, floor(min(maxSide / size.width, maxSide / size.height)))
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx
        ctx?.imageInterpolation = .none   // keep the pixel art crisp
        frame.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]), png.count < 48_000 else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    func push() async {
        guard let token = UserDefaults.standard.string(forKey: Self.tokenKey) else { return }
        let states = PetCareController.shared.states
        guard !states.isEmpty else { return }

        let pets: [[String: Any]] = states.map { id, s in
            let name = ImagePetStore.shared.displayName(for: id)
            let week = PetCare.recentDays(state: s, now: Date()).map { $0.tokens }
            return [
                "id": id,
                "name": name,
                "xp": s.xp,
                "tokens": s.totalTokens,
                "meals": s.totalMeals,
                "streak": s.streakDays,
                "lastFedAt": s.lastFedAt.map { Int($0.timeIntervalSince1970) } as Any,
                "thumb": Self.thumbDataURL(for: id) as Any,
                "week": week,
                "achievements": Array(s.unlockedAchievements ?? []).map { $0.rawValue },
            ]
        }

        var request = URLRequest(url: Self.base.appendingPathComponent("api/care/sync"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["pets": pets])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                lastSyncAt = Date()
                lastError = nil
                failCount = 0
            } else if status == 401 {
                // Token revoked from the web side: unlink quietly.
                disconnect()
            } else {
                retryWithBackoff()
            }
        } catch {
            retryWithBackoff()
        }
    }

    private func retryWithBackoff() {
        failCount += 1
        if failCount >= 5 {
            lastError = NSLocalizedString("Sync failed repeatedly. Re-link to retry.", comment: "")
            return
        }
        let delays: [TimeInterval] = [30, 120, 300, 600]
        let delay = delays[min(failCount - 1, delays.count - 1)]
        lastError = NSLocalizedString("Sync failed, will retry.", comment: "")
        scheduleSync(after: delay)
    }

    // MARK: - Project usage sync

    private var usageDebounce: Timer?

    /// Debounced push of per-project usage rows. Safe to call freely.
    func scheduleUsageSync(after seconds: TimeInterval = 30) {
        guard linked else { return }
        usageDebounce?.invalidate()
        usageDebounce = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor [weak self] in await self?.pushUsage() }
        }
    }

    func pushUsage() async {
        guard let token = UserDefaults.standard.string(forKey: Self.tokenKey) else { return }
        let snapshot = ProjectUsageStore.shared.pendingRows()
        guard !snapshot.isEmpty else { return }
        let rows: [[String: Any]] = snapshot.map { r in
            ["projectId": r.projectId, "projectName": r.projectName, "agent": r.agent,
             "day": r.day, "tokens": r.tokens, "sessions": r.sessions]
        }
        var request = URLRequest(url: Self.base.appendingPathComponent("api/usage/sync"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["rows": rows])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                ProjectUsageStore.shared.markSynced(snapshot)
            } else if status == 401 {
                disconnect()
            }
        } catch {
            // Left dirty; the next record or launch retries.
        }
    }

    // MARK: - Restore

    /// One pet's care stats as stored in the cloud (see /api/care/restore).
    struct CloudPet: Decodable {
        let id: String
        let name: String?
        let xp: Int
        let tokens: Int
        let meals: Int
        let streak: Int
        let lastFedAt: Int?
        let achievements: [String]?
    }
    private struct RestoreResponse: Decodable { let pets: [CloudPet] }

    /// Pulls the user's cloud care stats and merges them into local pets so a new
    /// machine restores progress instead of starting over. Grow-only, so it never
    /// shrinks a pet that is further along on this machine. Returns pets changed.
    @discardableResult
    func restore(manual: Bool = false) async -> Int {
        guard let token = UserDefaults.standard.string(forKey: Self.tokenKey) else { return 0 }
        restoring = true
        defer { restoring = false }
        var request = URLRequest(url: Self.base.appendingPathComponent("api/care/restore"))
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 { disconnect(); return 0 }
            guard status == 200 else {
                if manual { lastError = NSLocalizedString("Restore failed, try again.", comment: "") }
                return 0
            }
            let decoded = try JSONDecoder().decode(RestoreResponse.self, from: data)
            let changed = PetCareController.shared.mergeFromCloud(decoded.pets)
            if manual { lastError = nil }
            return changed
        } catch {
            if manual { lastError = NSLocalizedString("Restore failed, try again.", comment: "") }
            return 0
        }
    }
}
