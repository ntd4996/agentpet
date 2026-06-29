import Foundation
import AgentPetCore

/// Owns the persistent tamagotchi state — one `PetCareState` PER PET, so every
/// companion levels up on its own depending on how its owner raises it. Food
/// (finished sessions, Claude tokens) always goes to the currently selected
/// pet. Persists across launches and plays a celebrate burst on level-ups.
@MainActor
final class PetCareController: ObservableObject {
    static let shared = PetCareController()

    /// Care state per pet id. Only pets that have been fed at least once (or
    /// were selected while care ran) appear here.
    @Published private(set) var states: [String: PetCareState] = [:]

    private static let storageKey = "agentpet.care.v2"
    private static let legacyKey = "agentpet.care.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: PetCareState].self, from: data) {
            states = saved
        } else if let data = UserDefaults.standard.data(forKey: Self.legacyKey),
                  let old = try? JSONDecoder().decode(PetCareState.self, from: data) {
            // v1 kept a single global state: hand it to the selected pet.
            if let id = UserDefaults.standard.string(forKey: "agentpet.selectedPetID") {
                states = [id: old]
                persist()
            }
            UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        }
    }

    /// The pet currently being raised — feeding goes here.
    var currentPetID: String? { PetController.shared.selectedPetID }

    /// Care state of the selected pet (a fresh one if it was never fed).
    var current: PetCareState { state(for: currentPetID) }

    func state(for petID: String?) -> PetCareState {
        guard let petID else { return PetCareState() }
        return states[petID] ?? PetCareState()
    }

    // MARK: - Derived (selected pet)

    /// Level shown to the user (pet with no XP reads as Lv 0).
    var level: Int { PetCare.displayLevel(forXP: current.xp) }
    var stageKey: String { PetCare.stageName(forLevel: PetCare.level(forXP: current.xp)) }
    var stageIndex: Int { PetCare.stageIndex(forLevel: PetCare.level(forXP: current.xp)) }
    /// Progress through the current level, 0…1.
    var levelProgress: Double { PetCare.progress(forXP: current.xp) }
    var hunger: PetHunger { PetCare.hunger(state: current, now: Date()) }

    /// All raised pets, current first, then by XP.
    var raisedPetIDs: [String] {
        states.keys.sorted { a, b in
            if a == currentPetID { return true }
            if b == currentPetID { return false }
            return (states[a]?.xp ?? 0) > (states[b]?.xp ?? 0)
        }
    }

    // MARK: - Feeding

    /// A finished agent session — the pet's proper meal.
    /// Pass `petID` to feed a specific pet (Split ON); `nil` feeds the selected pet (back-compat).
    func recordMeal(petID: String? = nil) {
        mutate(petID: petID) { PetCare.recordMeal(state: &$0, now: Date()) }
    }

    /// Tokens consumed by a Claude turn (transcript usage delta).
    /// Pass `petID` to feed a specific pet (Split ON); `nil` feeds the selected pet (back-compat).
    func feedTokens(_ tokens: Int, petID: String? = nil) {
        guard tokens > 0 else { return }
        mutate(petID: petID) { PetCare.feedTokens(tokens, state: &$0, now: Date()) }
    }

    /// Rolls the daily counters over; UI refresh timers call this so "today"
    /// numbers reset at midnight even with no feeding events.
    func refreshDay() {
        mutate(petID: nil) { PetCare.rollover(&$0, now: Date()) }
    }

    /// Resolves which pet receives a feed: `requested` if it is an installed
    /// pack, otherwise falls back to `selectedPetID`.
    private func resolvedFeedTarget(_ requested: String?) -> String? {
        if let id = requested, ImagePetStore.shared.pack(id: id) != nil { return id }
        return currentPetID
    }

    private func mutate(petID requested: String?, _ change: (inout PetCareState) -> Void) {
        guard let petID = resolvedFeedTarget(requested) else { return }
        let stateBefore = state(for: petID)
        let levelBefore = PetCare.level(forXP: stateBefore.xp)
        let achievementsBefore = stateBefore.unlockedAchievements ?? []
        var s = stateBefore
        change(&s)
        // Reconcile achievements after every feed/meal/rollover: recordMeal and
        // feedTokens mutate the stats but don't unlock badges themselves, so
        // without this the unlock set stays empty forever (HUD showed 0/14).
        PetCare.unlockNewAchievements(state: &s, now: Date())
        guard s != states[petID] else { return }
        states[petID] = s
        persist()
        CareSyncController.shared.scheduleSync()
        let levelAfter = PetCare.level(forXP: s.xp)
        if levelAfter > levelBefore {
            let line = String(
                format: NSLocalizedString("Level up! Lv %d ⭐", comment: "pet level-up celebrate line"),
                levelAfter
            )
            PetController.shared.flashLevelUp(line: line, petID: petID)
        }
        let achievementsAfter = s.unlockedAchievements ?? []
        let newAchievements = achievementsAfter.subtracting(achievementsBefore)
        if newAchievements.count > 3 {
            // Bulk backfill (first run after the feature shipped, or a veteran
            // pet): one summary line instead of a burst of celebrate flashes.
            let line = String(
                format: NSLocalizedString("%d achievements unlocked! 🏆", comment: "bulk achievement unlock celebrate line"),
                newAchievements.count
            )
            PetController.shared.flashCelebrate(line: line, petID: petID)
        } else {
            for achievement in newAchievements {
                let name = PetCare.achievementDisplayName(achievement)
                let line = String(
                    format: NSLocalizedString("Achievement unlocked: %@ 🏆", comment: "achievement unlock celebrate line"),
                    name
                )
                PetController.shared.flashCelebrate(line: line, petID: petID)
            }
        }
    }

    /// All achievements unlocked by the currently selected pet.
    var achievements: Set<Achievement> { current.unlockedAchievements ?? [] }

    /// Merges cloud care stats (from another device) into local pets. Grow-only:
    /// counters take the max, achievements union, so a restore never undoes
    /// progress made on either machine. Silent (no celebrate flashes). Returns
    /// how many pets changed.
    @discardableResult
    func mergeFromCloud(_ pets: [CareSyncController.CloudPet]) -> Int {
        var changed = 0
        for c in pets {
            let original = states[c.id]
            var s = original ?? PetCareState()
            s.xp = max(s.xp, c.xp)
            s.totalTokens = max(s.totalTokens, c.tokens)
            s.totalMeals = max(s.totalMeals, c.meals)
            s.streakDays = max(s.streakDays, c.streak)
            if let lf = c.lastFedAt {
                let d = Date(timeIntervalSince1970: TimeInterval(lf))
                if let cur = s.lastFedAt { if d > cur { s.lastFedAt = d } } else { s.lastFedAt = d }
            }
            if let ach = c.achievements, !ach.isEmpty {
                let set = Set(ach.compactMap { Achievement(rawValue: $0) })
                s.unlockedAchievements = (s.unlockedAchievements ?? []).union(set)
            }
            // Reconcile any badges the higher stats now qualify for (no flashes).
            PetCare.unlockNewAchievements(state: &s, now: Date())
            if s != original {
                states[c.id] = s
                changed += 1
            }
            // Restore a custom name only when this machine hasn't named the pet.
            if let name = c.name, !name.isEmpty, ImagePetStore.shared.nameOverrides[c.id] == nil {
                ImagePetStore.shared.rename(c.id, to: name)
            }
        }
        if changed > 0 { persist() }
        return changed
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// Care-driven chatter: hunger and near-limit anxiety colour the idle pool.
enum CareChat {
    static let hungry = [
        "Getting hungry… run an agent?",
        "A little snack? One small task?",
        "My tummy is rumbling…",
        "Feed me some tokens, please.",
    ]

    static let starving = [
        "Starving… nothing to eat for days…",
        "So weak… one tiny session, please…",
        "No tokens… no energy…",
        "Remember me? Your pet? The hungry one?",
    ]

    static let anxious = [
        "Careful… your AI budget is almost gone.",
        "Low fuel: a usage limit is nearly reached!",
        "Maybe save some tokens for tomorrow…",
    ]

    /// Mixes care lines into the idle pool: starving replaces it entirely,
    /// hungry and limit-anxiety blend in.
    @MainActor
    static func idlePool(base: [String], hunger: PetHunger? = nil) -> [String] {
        var pool = base
        let h = hunger ?? PetCareController.shared.hunger
        switch h {
        case .starving:
            pool = starving.map { NSLocalizedString($0, comment: "starving pet line") }
        case .hungry:
            pool += hungry.map { NSLocalizedString($0, comment: "hungry pet line") }
        default:
            break
        }
        if OpenUsageClient.shared.limitLow || NativeUsageProbe.shared.limitLow {
            pool += anxious.map { NSLocalizedString($0, comment: "limit anxiety line") }
        }
        return pool
    }
}
