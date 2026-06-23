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
    private var failCount = 0

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
            let name = ImagePetStore.shared.pack(id: id)?.displayName ?? id
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
}
