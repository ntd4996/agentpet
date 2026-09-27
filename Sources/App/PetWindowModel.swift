import Foundation
import AppKit
import AgentPetCore

/// Per-window pet state. One instance backs each pet window (single window for
/// now; the registry in later tasks owns one per active project). Holds only
/// the fields that vary per window — global toggles (showChat, petPoint…) still
/// live on `PetController.shared`.
@MainActor
final class PetWindowModel: ObservableObject {
    /// Stable grouping key: a project path or `"default"` for the home pet.
    let key: String

    @Published var petID: String?
    @Published var mood: PetMood
    @Published var projectName: String?
    @Published var sessions: [AgentSession]
    @Published var count: Int
    @Published var chatLine: String
    /// False while this pet's panel is fully occluded or the displays are
    /// asleep/locked. Views pause every animation and timer while false so an
    /// unseen pet costs ~no CPU. Driven by `PetWindowController`.
    @Published var isOnScreen = true
    /// Horizontal shift of the pet inside its window. Non-zero when the window
    /// was pushed back onto the pet's screen (wide bubble near an edge), so the
    /// pet stays put on screen. Driven by `PetWindowController`.
    @Published var petOffset: CGFloat = 0
    /// Current width of this pet's window (content is centred in it).
    @Published var windowWidth: CGFloat = 0

    init(
        key: String,
        petID: String? = nil,
        mood: PetMood = .idle,
        projectName: String? = nil,
        sessions: [AgentSession] = [],
        count: Int = 0,
        chatLine: String = ""
    ) {
        self.key = key
        self.petID = petID
        self.mood = mood
        self.projectName = projectName
        self.sessions = sessions
        self.count = count
        self.chatLine = chatLine
    }

    // MARK: - Pet tap interaction (per window)
    // Lives here, not on the shared controller, so tapping one pet in split
    // mode only bounces THAT pet (a shared state flickered every window).

    @Published private(set) var isPetted = false
    @Published private(set) var petReactionLine: String = ""
    @Published private(set) var petTapCount: Int = 0

    private var petBounceTimer: Timer?
    private var petLineTimer: Timer?
    private var petCooldown = false
    private var consecutivePets = 0
    private var lastPetTime: Date?

    private static let petReactions: [[String]] = [
        ["Hehe~", "That tickles!", "Hi there! 👋", "Oh! Hello~", "*purrs*", "Nyaa~"],
        ["I love you! 💕", "More pets please!", "Best human ever!", "So happy~ ✨"],
        ["MAXIMUM LOVE! 💖", "Can't stop smiling! 🥰", "I'm gonna melt~"],
    ]

    func petTap() {
        guard !petCooldown else { return }
        petCooldown = true

        let now = Date()
        if let last = lastPetTime, now.timeIntervalSince(last) < 3.0 {
            consecutivePets += 1
        } else {
            consecutivePets = 1
        }
        lastPetTime = now

        let tier = consecutivePets >= 6 ? 2 : consecutivePets >= 3 ? 1 : 0
        petReactionLine = Self.petReactions[tier].randomElement() ?? "Hehe~"
        petTapCount += 1

        isPetted = true
        petBounceTimer?.invalidate()
        petBounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.isPetted = false }
        }

        petLineTimer?.invalidate()
        petLineTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.petReactionLine = "" }
        }

        NSSound(named: "Pop")?.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.petCooldown = false
        }
    }
}
