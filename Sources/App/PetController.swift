import Foundation
import AgentPetCore

/// Drives the pet's animation: turns the aggregate session mood into a frame
/// loop, and plays a short `celebrate` burst when work just finished.
@MainActor
final class PetController: ObservableObject {
    static let shared = PetController()

    @Published private(set) var currentFrame: String = "🐾"
    @Published private(set) var currentPackName: String = ""

    private var pack: PetPack
    private var displayMood: PetMood = .idle
    private var lastResolved: PetMood = .idle
    private var latestSessions: [AgentSession] = []
    private var frameIndex = 0
    private var frameTimer: Timer?
    private var celebrateTimer: Timer?

    private static let celebrateDuration: TimeInterval = 3

    init() {
        pack = PetPackLoader.loadBuiltins().first
            ?? PetPack(name: "Paw", version: 1, kind: .emoji,
                       states: ["idle": PetAnimation(frames: ["🐾"], fps: 1)])
        currentPackName = pack.name
    }

    func start() {
        applyMood(.idle)
    }

    func selectPack(named name: String) {
        guard let p = PetPackLoader.loadBuiltins().first(where: { $0.name == name }) else { return }
        pack = p
        currentPackName = p.name
        applyMood(displayMood)
    }

    /// Called by the daemon whenever the session list changes.
    func update(sessions: [AgentSession]) {
        latestSessions = sessions
        let resolved = MoodResolver.aggregate(sessions)
        defer { lastResolved = resolved }

        if resolved == .done && lastResolved != .done {
            applyMood(.celebrate)
            celebrateTimer?.invalidate()
            celebrateTimer = Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
                Task { @MainActor [weak self] in self?.settleAfterCelebrate() }
            }
            return
        }
        if displayMood == .celebrate && resolved == .done {
            return  // let the celebration finish
        }
        celebrateTimer?.invalidate()
        applyMood(resolved)
    }

    private func settleAfterCelebrate() {
        applyMood(MoodResolver.aggregate(latestSessions))
    }

    private func applyMood(_ mood: PetMood) {
        displayMood = mood
        frameIndex = 0
        startFrameTimer()
    }

    private func startFrameTimer() {
        frameTimer?.invalidate()
        let anim = pack.animation(for: displayMood)
        currentFrame = anim.frames.first ?? "🐾"
        guard anim.frames.count > 1 else { return }
        let interval = anim.fps > 0 ? 1.0 / anim.fps : 1.0
        frameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.advanceFrame() }
        }
    }

    private func advanceFrame() {
        let anim = pack.animation(for: displayMood)
        guard !anim.frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % anim.frames.count
        currentFrame = anim.frames[frameIndex]
    }
}
