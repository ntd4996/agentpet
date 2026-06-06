import Foundation
import AgentPetCore

/// Resolves the aggregate session mood, plays a short `celebrate` burst when
/// work finishes, owns the selected (imported) pet, and drives the chat bubble.
@MainActor
final class PetController: ObservableObject {
    static let shared = PetController()

    @Published private(set) var mood: PetMood = .idle
    @Published private(set) var chatLine: String = ""

    @Published var selectedPetID: String? {
        didSet { UserDefaults.standard.set(selectedPetID, forKey: Self.petKey) }
    }
    @Published var showChat: Bool {
        didSet {
            UserDefaults.standard.set(showChat, forKey: Self.chatKey)
            refreshChat()
        }
    }
    /// Sprite point size, freely adjustable via a slider.
    @Published var petPoint: Double {
        didSet { UserDefaults.standard.set(petPoint, forKey: Self.sizeKey) }
    }

    static let minPoint: Double = 60
    static let maxPoint: Double = 240
    static let presets: [(String, Double)] = [("S", 84), ("M", 120), ("L", 168)]

    /// Floating window size. Width is wide enough for agent-ticker lines;
    /// height grows with the number of lines in the bubble.
    static func windowSize(forPoint point: Double, lineCount: Int = 1) -> CGSize {
        let count = max(lineCount, 1)
        let bubbleH = CGFloat(count) * 22 + 16   // 22pt per line + top/bottom padding
        return CGSize(
            width: max(point + 110, 320),         // 320pt fits typical agent lines
            height: point + bubbleH + 28          // 28pt for triangle + spacing + margin
        )
    }
    var windowSize: CGSize { Self.windowSize(forPoint: petPoint, lineCount: max(chatLineCount, 1)) }

    private var lastResolved: PetMood = .idle
    private var latestSessions: [AgentSession] = []
    private var celebrateTimer: Timer?

    /// Number of active agent lines currently shown; drives window height.
    @Published private(set) var chatLineCount: Int = 0
    /// Sorted active sessions for the structured desktop bubble. Empty when idle/done/celebrate.
    @Published private(set) var activeAgentSessions: [AgentSession] = []

    private static let petKey = "agentpet.selectedPetID"
    private static let chatKey = "agentpet.showChat"
    private static let sizeKey = "agentpet.petSize"
    private static let celebrateDuration: TimeInterval = 3

    init() {
        selectedPetID = UserDefaults.standard.string(forKey: Self.petKey)
        showChat = (UserDefaults.standard.object(forKey: Self.chatKey) as? Bool) ?? true
        let saved = UserDefaults.standard.object(forKey: Self.sizeKey) as? Double ?? 120
        petPoint = min(max(saved, Self.minPoint), Self.maxPoint)
    }

    func start() {
        // Ticker drives chatLine updates; no separate chat timer needed.
    }

    private var sizeAnimTimer: Timer?
    private var sizeAnimStep = 0
    private var sizeAnimStart = 0.0
    private var sizeAnimTarget = 0.0
    private static let sizeAnimSteps = 14

    /// Eases `petPoint` to a target so a preset tap resizes as smoothly as a
    /// slider drag (each step drives the same smooth window resize).
    func animateSize(to target: Double) {
        sizeAnimTimer?.invalidate()
        sizeAnimTarget = min(max(target, Self.minPoint), Self.maxPoint)
        sizeAnimStart = petPoint
        sizeAnimStep = 0
        sizeAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tickSize() }
        }
    }

    private func tickSize() {
        sizeAnimStep += 1
        let t = min(Double(sizeAnimStep) / Double(Self.sizeAnimSteps), 1)
        let eased = t * t * (3 - 2 * t)   // smoothstep
        petPoint = sizeAnimStart + (sizeAnimTarget - sizeAnimStart) * eased
        if sizeAnimStep >= Self.sizeAnimSteps {
            petPoint = sizeAnimTarget
            sizeAnimTimer?.invalidate()
        }
    }

    /// Called by the daemon whenever the session list changes.
    func update(sessions: [AgentSession]) {
        latestSessions = sessions
        let resolved = MoodResolver.aggregate(sessions)
        defer { lastResolved = resolved }

        if resolved == .done && lastResolved != .done {
            chatLineCount = 0
            activeAgentSessions = []
            setMood(.celebrate)
            celebrateTimer?.invalidate()
            celebrateTimer = Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
                Task { @MainActor [weak self] in self?.settleAfterCelebrate() }
            }
            return
        }
        if mood == .celebrate {
            return  // let the 3-second celebration finish regardless of new state
        }
        celebrateTimer?.invalidate()
        setMood(resolved)

        if resolved == .working || resolved == .waiting {
            buildAgentChatLine(sessions: sessions)
        } else {
            chatLineCount = 0
            activeAgentSessions = []
        }
    }

    private func settleAfterCelebrate() {
        setMood(MoodResolver.aggregate(latestSessions))
    }

    private func setMood(_ newMood: PetMood) {
        mood = newMood
        refreshChat()
    }

    private func refreshChat() {
        guard showChat, mood != .idle else {
            chatLine = ""
            StatusBarController.shared.refreshTitle()
            return
        }
        // During working/waiting the agent list owns chatLine; fall back to
        // PetChat for celebrate/done.
        if (mood == .working || mood == .waiting) && chatLineCount > 0 {
            // chatLine already set by buildAgentChatLine — just refresh status bar
            StatusBarController.shared.refreshTitle()
            return
        }
        let pool = ChatSettings.shared.lines(for: mood)
        guard !pool.isEmpty else {
            chatLine = ""
            StatusBarController.shared.refreshTitle()
            return
        }
        chatLine = pool.randomElement() ?? ""
        StatusBarController.shared.refreshTitle()
    }

    // MARK: - Agent list

    /// Builds the structured session list and a plain-text fallback chatLine.
    private func buildAgentChatLine(sessions: [AgentSession]) {
        let active = TickerFormatter.sorted(
            sessions.filter { $0.state != .idle && $0.state != .registered }
        )
        activeAgentSessions = active
        chatLineCount = active.count
        if active.isEmpty {
            chatLine = ""
        } else {
            // Plain-text fallback used by the menu bar chat pill (lineLimit(1) shows first line).
            chatLine = active.map { "• \(TickerFormatter.line(for: $0))" }.joined(separator: "\n")
        }
        StatusBarController.shared.refreshTitle()
    }
}

/// Built-in (system) chat lines per mood.
enum PetChat {
    static let lines: [PetMood: [String]] = [
        .working: [
            "Thinking…", "Working on it…", "On it!", "Crunching code…",
            "Hmm, let me see…", "Cooking something up…", "Deep in thought…",
            "Brain go brrr…", "Almost there…", "Wiring it up…",
        ],
        .waiting: [
            "I need you!", "Your turn 👀", "Waiting on you…", "Can you check this?",
            "Psst, need input!", "Awaiting orders…", "Help me out?", "Stuck, need you!",
        ],
        .done: [
            "All done! ✅", "Finished!", "Ta-da!", "Done and dusted!",
            "Nailed it!", "That's a wrap!", "Mission complete!",
        ],
        .celebrate: [
            "🎉 Woohoo!", "We did it!", "Victory!", "Yesss!", "High five! 🙌", "Champion!",
        ],
    ]
}
