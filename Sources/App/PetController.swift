import AppKit
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
    /// Whether the pet shows a chat line while idle (the "doing nothing" chatter).
    @Published var showIdleMessage: Bool {
        didSet {
            UserDefaults.standard.set(showIdleMessage, forKey: Self.idleMsgKey)
            refreshChat()
        }
    }
    /// When enabled, spawns one pet window per active project instead of a single shared pet.
    @Published var splitPet: Bool = UserDefaults.standard.bool(forKey: "agentpet.splitPet") {
        didSet {
            UserDefaults.standard.set(splitPet, forKey: "agentpet.splitPet")
            update(sessions: latestSessions)   // re-evaluate windows when toggled
        }
    }
    /// In split mode: hide a configured project's pet while it has no active work
    /// (it reappears when the project runs again). Off = the project pet stays put.
    @Published var hideIdleProjectPets: Bool = UserDefaults.standard.bool(forKey: "agentpet.hideIdleProjectPets") {
        didSet {
            UserDefaults.standard.set(hideIdleProjectPets, forKey: "agentpet.hideIdleProjectPets")
            update(sessions: latestSessions)
        }
    }
    /// When disabled, freezes all continuous/perpetual pet and bubble animation so
    /// the SwiftUI render loop can go idle (lower CPU, reduce-motion option).
    @Published var animationsEnabled: Bool =
        (UserDefaults.standard.object(forKey: "agentpet.animationsEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(animationsEnabled, forKey: "agentpet.animationsEnabled") }
    }
    /// User-adjustable sprite frame rate (1–12 fps). Active moods animate at this
    /// rate; idle is capped at 2 fps regardless of the slider (idle CPU win).
    @Published var animationFPS: Double =
        ((UserDefaults.standard.object(forKey: "agentpet.animationFPS") as? Double) ?? 8).clampedFPS {
        didSet {
            let v = animationFPS.clampedFPS
            if v != animationFPS { animationFPS = v; return }   // re-entrancy guard for clamp
            UserDefaults.standard.set(animationFPS, forKey: "agentpet.animationFPS")
        }
    }
    /// Sprite point size, freely adjustable via a slider.
    @Published var petPoint: Double {
        didSet { UserDefaults.standard.set(petPoint, forKey: Self.sizeKey) }
    }

    static let minPoint: Double = 60
    static let maxPoint: Double = 240
    static let presets: [(String, Double)] = [("S", 84), ("M", 120), ("L", 168)]

    private var lastResolved: PetMood = .idle
    private var latestSessions: [AgentSession] = []

    /// Number of active agent lines currently shown; drives window height.
    @Published private(set) var chatLineCount: Int = 0
    /// Sorted active sessions for the structured desktop bubble. Empty when idle/done/celebrate.
    @Published private(set) var activeAgentSessions: [AgentSession] = []

    private static let petKey = "agentpet.selectedPetID"
    private static let chatKey = "agentpet.showChat"
    private static let idleMsgKey = "agentpet.showIdleMessage"
    private static let sizeKey = "agentpet.petSize"
    private static let celebrateDuration: TimeInterval = 3

    init() {
        selectedPetID = UserDefaults.standard.string(forKey: Self.petKey)
        showChat = (UserDefaults.standard.object(forKey: Self.chatKey) as? Bool) ?? true
        showIdleMessage = (UserDefaults.standard.object(forKey: Self.idleMsgKey) as? Bool) ?? true
        let saved = UserDefaults.standard.object(forKey: Self.sizeKey) as? Double ?? 120
        petPoint = min(max(saved, Self.minPoint), Self.maxPoint)
    }

    func start() {
        // Ticker drives chatLine updates; no separate chat timer needed.
        // Re-plan windows when project→pet mappings change so adding/removing a
        // configured project takes effect immediately (no need to wait for the
        // next session event).
        ProjectPetSettings.shared.onChange = { [weak self] in
            guard let self else { return }
            self.update(sessions: self.latestSessions)
        }
    }

    /// Returns the effective sprite fps for a given mood, honouring the slider.
    /// Idle and sleepy are capped at 2 fps regardless of the slider value (calm CPU win).
    func spriteFPS(forMood mood: PetMood) -> Double {
        (mood == .idle || mood == .sleepy) ? min(animationFPS, 2) : animationFPS
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
            let celebrateLine = chatLine(forMood: .celebrate)
            celebratingKeys[PetWindowPlanner.defaultKey] = CelebrateFlash(line: celebrateLine, mood: .celebrate)
            let key = PetWindowPlanner.defaultKey
            Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
                Task { @MainActor [weak self] in
                    self?.celebratingKeys.removeValue(forKey: key)
                    self?.syncWindows()
                }
            }
            syncWindows()
            return
        }
        setMood(resolved)

        if resolved == .working || resolved == .waiting {
            if BubbleSettings.shared.multiAgentBubbleEnabled {
                buildAgentChatLine(sessions: sessions)
            } else {
                chatLineCount = 0
                activeAgentSessions = []
                refreshChat()
            }
        } else {
            chatLineCount = 0
            activeAgentSessions = []
        }
        syncWindows()
    }

    /// Rebuilds chat state when the user toggles multi-agent bubble mode.
    func applyBubbleModeChange() {
        guard mood == .working || mood == .waiting else { return }
        if BubbleSettings.shared.multiAgentBubbleEnabled {
            buildAgentChatLine(sessions: latestSessions)
        } else {
            chatLineCount = 0
            activeAgentSessions = []
            refreshChat()
        }
        syncWindows()
    }

    private func settleAfterCelebrate() {
        celebratingKeys.removeAll()
        setMood(MoodResolver.aggregate(latestSessions))
        syncWindows()
    }

    /// Plays a short celebrate burst with a custom line (e.g. an achievement
    /// unlock), then settles back to the aggregate mood. Sets `chatLine`
    /// directly — `setMood` would re-roll it from the message pools.
    func flashCelebrate(line: String, petID: String? = nil) {
        let resolvedPetID = petID ?? selectedPetID
        let keys: [String]
        if let pid = resolvedPetID {
            keys = PetWindowPlanner.windowKeys(forPetID: pid, split: splitPet,
                                               mappings: ProjectPetSettings.shared.mappings,
                                               selectedPetID: selectedPetID)
        } else {
            keys = [PetWindowPlanner.defaultKey]
        }
        for key in keys {
            celebratingKeys[key] = CelebrateFlash(line: line, mood: .celebrate)
            let k = key
            Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
                Task { @MainActor [weak self] in
                    self?.celebratingKeys.removeValue(forKey: k)
                    self?.syncWindows()
                }
            }
        }
        StatusBarController.shared.refreshTitle()
        syncWindows()
    }

    /// Plays a short level-up burst with a custom line, using the dedicated
    /// `.levelup` mood (a distinct clip from the done-celebrate), then settles
    /// back to the aggregate mood. Sets `chatLine` directly — `setMood` would
    /// re-roll it from the message pools.
    func flashLevelUp(line: String, petID: String? = nil) {
        let resolvedPetID = petID ?? selectedPetID
        let keys: [String]
        if let pid = resolvedPetID {
            keys = PetWindowPlanner.windowKeys(forPetID: pid, split: splitPet,
                                               mappings: ProjectPetSettings.shared.mappings,
                                               selectedPetID: selectedPetID)
        } else {
            keys = [PetWindowPlanner.defaultKey]
        }
        for key in keys {
            celebratingKeys[key] = CelebrateFlash(line: line, mood: .levelup)
            let k = key
            Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
                Task { @MainActor [weak self] in
                    self?.celebratingKeys.removeValue(forKey: k)
                    self?.syncWindows()
                }
            }
        }
        StatusBarController.shared.refreshTitle()
        syncWindows()
    }

    func flashReactiveLine(_ line: String) {
        guard showChat else { return }
        chatLine = line
        StatusBarController.shared.refreshTitle()
        syncWindows()
    }

    private func setMood(_ newMood: PetMood) {
        let changed = newMood != mood
        mood = newMood
        // Only re-pick the line when the mood actually changes, so a periodic
        // refresh (e.g. the 10s prune) doesn't keep swapping the idle line and
        // resize/jump the pet. `reroll` forces a new pick on real transitions.
        refreshChat(reroll: changed)
    }

    /// Re-pick the chat line so it adopts a newly chosen app language at once.
    func relocalize() { refreshChat() }

    private func refreshChat(reroll: Bool = true) {
        guard showChat else {
            chatLine = ""
            StatusBarController.shared.refreshTitle()
            syncWindows()
            return
        }
        if mood == .idle {
            guard showIdleMessage else {
                chatLine = ""
                StatusBarController.shared.refreshTitle()
                syncWindows()
                return
            }
            if reroll || chatLine.isEmpty {
                chatLine = idleLine()
            }
            StatusBarController.shared.refreshTitle()
            syncWindows()
            return
        }
        // Multi-agent mode owns chatLine during working/waiting; otherwise use PetChat.
        if (mood == .working || mood == .waiting)
            && BubbleSettings.shared.multiAgentBubbleEnabled
            && chatLineCount > 0 {
            StatusBarController.shared.refreshTitle()
            syncWindows()
            return
        }
        if reroll || chatLine.isEmpty {
            chatLine = chatLine(forMood: mood)
        }
        StatusBarController.shared.refreshTitle()
        syncWindows()
    }

    // MARK: - Chat line (reusable per-mood line picker)

    /// The idle "doing nothing" chatter, care-coloured (hunger / budget anxiety).
    /// Shared by the aggregate `refreshChat` and per-project home windows.
    private func idleLine(petID: String? = nil) -> String {
        let pool = BubbleSettings.shared.multiAgentBubbleEnabled
            ? BubbleMessages.shared.lines(for: nil, mood: .idle)
            : ChatSettings.shared.lines(for: .idle)
        let hunger = PetCare.hunger(state: PetCareController.shared.state(for: petID), now: Date())
        return CareChat.idlePool(base: pool, hunger: hunger).randomElement() ?? IdleBoost.line()
    }

    /// A fresh chat line for a non-idle mood, honouring the bubble source.
    /// Reused for both the aggregate pet and per-project split windows.
    private func chatLine(forMood mood: PetMood) -> String {
        let pool = BubbleSettings.shared.multiAgentBubbleEnabled
            ? BubbleMessages.shared.lines(for: nil, mood: mood)
            : ChatSettings.shared.lines(for: mood)
        return pool.randomElement() ?? ""
    }

    /// The chat line shown for a planned window. For working/waiting in
    /// multi-agent mode the structured `AgentBubble` carries the rows, so the
    /// `chatLine` is only the plain-text fallback (and stays empty so the
    /// bubble isn't double-drawn); otherwise a per-mood pool pick.
    private func chatLine(forMood mood: PetMood, sessions: [AgentSession], petID: String? = nil) -> String {
        switch mood {
        case .idle, .sleepy:
            guard showIdleMessage else { return "" }
            return idleLine(petID: petID)
        case .working, .waiting:
            if BubbleSettings.shared.multiAgentBubbleEnabled && !sessions.isEmpty {
                return sessions.map { "• \(TickerFormatter.line(for: $0))" }.joined(separator: "\n")
            }
            return chatLine(forMood: mood)
        case .done, .celebrate, .levelup:
            return chatLine(forMood: mood)
        }
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
        syncWindows()
    }

    // MARK: - Window coordination (planner → PetWindowController)

    private struct CelebrateFlash {
        let line: String
        let mood: PetMood
    }

    private var lastMoodByKey: [String: PetMood] = [:]
    private var celebratingKeys: [String: CelebrateFlash] = [:]

    // MARK: - Break reminder (home pet rests)

    /// Transient override shown on the home/default pet during a break.
    private enum BreakDisplay {
        case resting(line: String)
        case perkUp(line: String)
    }
    private var breakState: BreakDisplay?
    private var breakPerkTimer: Timer?

    /// Puts the home/default pet into a resting state until `endBreakRest`.
    /// Only the `default` window is affected; project pets keep their mood.
    func beginBreakRest(line: String) {
        breakPerkTimer?.invalidate()
        breakState = .resting(line: line)
        syncWindows()
    }

    /// Clears any in-progress break rest immediately (e.g. the user disabled the
    /// reminder mid-break). Without this the home pet would stay "resting", since
    /// only the break-over path clears `breakState`.
    func cancelBreakRest() {
        breakPerkTimer?.invalidate()
        breakPerkTimer = nil
        guard breakState != nil else { return }
        breakState = nil
        syncWindows()
    }

    /// Wakes the home/default pet: a short "back to work" line, then clears.
    func endBreakRest(line: String) {
        breakPerkTimer?.invalidate()
        breakState = .perkUp(line: line)
        syncWindows()
        breakPerkTimer = Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
            Task { @MainActor [weak self] in
                self?.breakState = nil
                self?.syncWindows()
            }
        }
    }

    /// Plans the per-project pet windows from the current sessions and reconciles
    /// the window registry. Single-pet mode (Split OFF) yields exactly one
    /// "default" window whose state mirrors today's aggregate behaviour.
    private var syncScheduled = false

    private func syncWindows() {
        guard !syncScheduled else { return }
        syncScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.syncScheduled = false
            self.performWindowSync()
        }
    }

    private func performWindowSync() {
        let specs = PetWindowPlanner.plan(
            sessions: latestSessions,
            split: splitPet,
            mappings: ProjectPetSettings.shared.mappings,
            defaultPetID: selectedPetID,
            forceDefault: breakState != nil,
            hideIdleProjects: hideIdleProjectPets
        )

        let liveKeys = Set(specs.map(\.key))
        // Drop tracking for windows that no longer exist.
        lastMoodByKey = lastMoodByKey.filter { liveKeys.contains($0.key) }
        celebratingKeys = celebratingKeys.filter { liveKeys.contains($0.key) }

        // Fire a celebrate burst when a window's group newly enters `.done`.
        // In Split-ON mode the defaultKey window is a real project-less group and
        // must also get per-key celebrate; in Split-OFF the defaultKey celebrates
        // via the global mood mirror, so we exclude it here to avoid doubling.
        for spec in specs {
            let prev = lastMoodByKey[spec.key]
            if spec.mood == .done && prev != nil && prev != .done {
                let line = chatLine(forMood: .celebrate)
                celebratingKeys[spec.key] = CelebrateFlash(line: line, mood: .celebrate)
                let key = spec.key
                Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
                    Task { @MainActor [weak self] in
                        self?.celebratingKeys.removeValue(forKey: key)
                        self?.syncWindows()
                    }
                }
            }
            lastMoodByKey[spec.key] = spec.mood
        }

        PetWindowController.shared.sync(specs: specs) { [weak self] spec in
            self?.windowState(for: spec)
                ?? PetWindowController.WindowState(petID: spec.petID, mood: spec.mood,
                                                   sessions: [], count: spec.count, chatLine: "")
        }
    }

    /// Resolves the displayed state for one planned window.
    private func windowState(for spec: PetWindowSpec) -> PetWindowController.WindowState {
        // Substitute the selected pet when the configured pet was deleted, so a
        // missing sprite falls back to the default instead of the paw placeholder.
        let petID: String? = {
            if let id = spec.petID, ImagePetStore.shared.pack(id: id) != nil { return id }
            return selectedPetID
        }()

        // A break nudge overrides the home/default pet (rest visual + line) in
        // both split modes. Project pets keep their own mood — this nudges the
        // user, not the agents. `.sleepy` is the rest visual; `.idle` on perk-up.
        if spec.key == PetWindowPlanner.defaultKey, let bs = breakState {
            let mood: PetMood
            let line: String
            switch bs {
            case .resting(let l): mood = .sleepy; line = l
            case .perkUp(let l): mood = .idle; line = l
            }
            return PetWindowController.WindowState(
                petID: petID, mood: mood, sessions: [], count: 0, chatLine: line)
        }

        if let flash = celebratingKeys[spec.key] {
            return PetWindowController.WindowState(
                petID: petID, mood: flash.mood, sessions: [], count: spec.count, chatLine: flash.line
            )
        }

        let ids = Set(spec.sessionIDs)
        let groupSessions: [AgentSession]
        let lineCount: Int
        let resolvedLine: String
        if !splitPet && spec.key == PetWindowPlanner.defaultKey {
            groupSessions = activeAgentSessions
            lineCount = chatLineCount
            resolvedLine = chatLine
        } else {
            groupSessions = TickerFormatter.sorted(
                latestSessions.filter { ids.contains($0.id) && $0.state != .idle && $0.state != .registered }
            )
            lineCount = spec.count
            resolvedLine = chatLine(forMood: spec.mood, sessions: groupSessions, petID: spec.petID)
        }
        return PetWindowController.WindowState(
            petID: petID,
            mood: spec.mood,
            sessions: groupSessions,
            count: lineCount,
            chatLine: resolvedLine
        )
    }
}

// MARK: - FPS helpers

private extension Double {
    /// Clamps a frame-rate value to the valid 1–12 fps slider range.
    var clampedFPS: Double { min(max(self, 1), 12) }
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
