import Foundation
import AgentPetCore
import ApplicationServices

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
            refreshChat(force: true)
        }
    }
    /// Sprite point size, freely adjustable via a slider.
    @Published var petPoint: Double {
        didSet { UserDefaults.standard.set(petPoint, forKey: Self.sizeKey) }
    }
    /// Chat frequency/probability (0% to 100%).
    @Published var chatProbability: Double {
        didSet {
            UserDefaults.standard.set(chatProbability, forKey: Self.chatProbabilityKey)
            if chatLine.isEmpty {
                refreshChat(force: true)
            }
            scheduleChat()
        }
    }
    /// Whether the pet dodges the mouse cursor.
    @Published var dodgeMouse: Bool {
        didSet { UserDefaults.standard.set(dodgeMouse, forKey: Self.dodgeMouseKey) }
    }
    /// Whether the pet dodges the text cursor (caret).
    @Published var dodgeTextCursor: Bool {
        didSet {
            UserDefaults.standard.set(dodgeTextCursor, forKey: Self.dodgeTextCursorKey)
            if dodgeTextCursor {
                checkAndPromptAccessibility()
            }
        }
    }
    /// Sensitivity range for dodging (0% to 100%).
    @Published var dodgeSensitivity: Double {
        didSet { UserDefaults.standard.set(dodgeSensitivity, forKey: Self.dodgeSensitivityKey) }
    }

    static let minPoint: Double = 60
    static let maxPoint: Double = 240
    static let presets: [(String, Double)] = [("S", 84), ("M", 120), ("L", 168)]

    /// Floating window size for a sprite point size (room for the bubble above).
    static func windowSize(forPoint point: Double) -> CGSize {
        CGSize(width: point + 110, height: point + 64)
    }
    var windowSize: CGSize { Self.windowSize(forPoint: petPoint) }

    private var lastResolved: PetMood = .idle
    private var latestSessions: [AgentSession] = []
    private var celebrateTimer: Timer?
    private var chatTimer: Timer?
    private var chatClearTimer: Timer?
    private var chatCooldownUntil: Date = .distantPast

    private static let petKey = "agentpet.selectedPetID"
    private static let chatKey = "agentpet.showChat"
    private static let chatProbabilityKey = "agentpet.chatProbability"
    private static let sizeKey = "agentpet.petSize"
    private static let dodgeMouseKey = "agentpet.dodgeMouse"
    private static let dodgeTextCursorKey = "agentpet.dodgeTextCursor"
    private static let dodgeSensitivityKey = "agentpet.dodgeSensitivity"
    private static let celebrateDuration: TimeInterval = 3

    init() {
        selectedPetID = UserDefaults.standard.string(forKey: Self.petKey)
        showChat = (UserDefaults.standard.object(forKey: Self.chatKey) as? Bool) ?? true
        let savedProb = UserDefaults.standard.object(forKey: Self.chatProbabilityKey) as? Double ?? 50.0
        chatProbability = min(max(savedProb, 0.0), 100.0)
        let saved = UserDefaults.standard.object(forKey: Self.sizeKey) as? Double ?? 120
        petPoint = min(max(saved, Self.minPoint), Self.maxPoint)
        dodgeMouse = (UserDefaults.standard.object(forKey: Self.dodgeMouseKey) as? Bool) ?? true
        dodgeTextCursor = (UserDefaults.standard.object(forKey: Self.dodgeTextCursorKey) as? Bool) ?? false
        let savedSensitivity = UserDefaults.standard.object(forKey: Self.dodgeSensitivityKey) as? Double ?? 100.0
        dodgeSensitivity = min(max(savedSensitivity, 0.0), 100.0)
    }

    func start() {
        scheduleChat()
    }

    /// Fires at random intervals — may skip so chat isn't constant.
    private func scheduleChat() {
        chatTimer?.invalidate()
        let p = chatProbability / 100.0
        let minInterval: Double
        let maxInterval: Double
        if p >= 0.5 {
            let t = (p - 0.5) / 0.5
            minInterval = 10.0 - 7.0 * t
            maxInterval = 30.0 - 24.0 * t
        } else {
            let t = p / 0.5
            minInterval = 30.0 - 20.0 * t
            maxInterval = 60.0 - 30.0 * t
        }
        chatTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: minInterval...maxInterval), repeats: false) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Use user-configured chat probability.
                let prob = self.chatProbability / 100.0
                guard Double.random(in: 0...1) < prob else {
                    self.scheduleChat()
                    return
                }
                self.refreshChat(force: false)
                self.scheduleChat()
            }
        }
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
            setMood(.celebrate)
            celebrateTimer?.invalidate()
            celebrateTimer = Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
                Task { @MainActor [weak self] in self?.settleAfterCelebrate() }
            }
            return
        }
        if mood == .celebrate && resolved == .done {
            return  // let the celebration finish
        }
        celebrateTimer?.invalidate()
        setMood(resolved)
    }

    private func settleAfterCelebrate() {
        setMood(MoodResolver.aggregate(latestSessions))
    }

    private func speak(_ message: String, duration: TimeInterval, cooldown: TimeInterval) {
        chatLine = message
        StatusBarController.shared.refreshTitle()

        chatClearTimer?.invalidate()
        chatClearTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            Task { @MainActor [weak self] in
                self?.chatLine = ""
                StatusBarController.shared.refreshTitle()
            }
        }

        chatCooldownUntil = Date().addingTimeInterval(duration + cooldown)
    }

    private func setMood(_ newMood: PetMood) {
        let changed = (mood != newMood)
        mood = newMood
        if changed {
            if newMood == .idle {
                // Instantly clear the chat bubble when entering idle.
                chatLine = ""
                StatusBarController.shared.refreshTitle()
                chatClearTimer?.invalidate()
                // Scale initial cooldown based on chatProbability (from 0s at 100% to 60s at 0%)
                let factor = (100.0 - chatProbability) / 100.0
                chatCooldownUntil = Date().addingTimeInterval(60.0 * factor)
            } else {
                refreshChat(force: true)
            }
        } else {
            refreshChat(force: false)
        }
    }

    private func refreshChat(force: Bool = false) {
        guard showChat, selectedPetID != nil else {
            chatLine = ""
            StatusBarController.shared.refreshTitle()
            return
        }

        // Check for active live messages from hooks first.
        let liveMessage = latestSessions.first(where: {
            ($0.state == .working || $0.state == .waiting)
            && ($0.message?.isEmpty == false)
        })?.message

        if let liveMessage = liveMessage {
            // Show live hook events immediately without normal cooldowns.
            if liveMessage != chatLine {
                speak(liveMessage, duration: 6.0, cooldown: 0.5)
            }
            return
        }

        if !force {
            guard Date() >= chatCooldownUntil else { return }
        }

        var messageToSpeak = ""
        var speakDuration: TimeInterval = 5.0
        var speakCooldown: TimeInterval = 10.0

        let factor = (100.0 - chatProbability) / 100.0

        if mood == .idle {
            messageToSpeak = ChatSettings.shared.lines(for: .idle).randomElement() ?? ""
            // Scale cooldown based on chatProbability (from 0s at 100% to 60s at 0%)
            speakCooldown = 60.0 * factor
            speakDuration = 5.0
        } else {
            let pool = ChatSettings.shared.lines(for: mood)
            if !pool.isEmpty {
                messageToSpeak = pool.randomElement() ?? ""
            }
            // Scale cooldown based on chatProbability
            speakCooldown = Double.random(in: 15...30) * factor
            speakDuration = 5.0
        }

        guard !messageToSpeak.isEmpty else { return }
        speak(messageToSpeak, duration: speakDuration, cooldown: speakCooldown)
    }

    func checkAndPromptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

/// Built-in (system) chat lines per mood.
enum PetChat {
    static let lines: [PetMood: [String]] = [
        .idle: [
            "Dạo này code ngon không?",
            "Hmm, để nghĩ xem… 🤔",
            "Chán quá, có gì chơi không?",
            "Bấm phím đi, mình chờ!",
            "Pssst… ra lệnh gì đi!",
            "Coding gì chưa?",
            "Nằm dài chờ lệnh đây…",
            "Hôm nay code gì hay không?",
            "À lô, có ai hong?",
            "Chờ hoài, chờ mãi…",
            "Xem nhau qua màn hình này!",
            "Mình đi ăn kem đi?",
            "Bored… chưa có gì để làm.",
        ],
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
