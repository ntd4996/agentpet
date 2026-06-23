import Foundation

/// Achievements the pet can unlock over its lifetime.
public enum Achievement: String, Codable, CaseIterable, Sendable {
    case firstMeal
    case sessions100
    case sessions500
    case tokens1M
    case tokens10M
    case tokens50M
    case level5
    case level10
    case level20
    case level35
    case streak7
    case streak14
    case streak30
    case nightOwl
}

/// How hungry the pet is, derived from the time since its last feeding.
public enum PetHunger: String, Codable, CaseIterable, Sendable {
    case full
    case satisfied
    case peckish
    case hungry
    case starving
}

/// Persistent tamagotchi state: the pet is fed by real agent work — tokens
/// consumed (Claude transcripts) and finished sessions ("meals").
public struct PetCareState: Codable, Equatable, Sendable {
    /// Lifetime experience. Never decreases.
    public var xp: Int
    /// Tokens left over below one-XP granularity, carried to the next feeding.
    public var tokenCarry: Int
    /// Tokens eaten today (counts toward the daily cap; resets at local midnight).
    public var tokensToday: Int
    /// Sessions finished today.
    public var mealsToday: Int
    /// Lifetime tokens eaten (uncapped, for bragging rights).
    public var totalTokens: Int
    /// Lifetime finished sessions.
    public var totalMeals: Int
    /// Last time the pet was fed anything (tokens or a meal).
    public var lastFedAt: Date?
    /// Local-calendar day the counters belong to ("2026-06-12").
    public var dayKey: String
    /// Consecutive days with at least one feeding.
    public var streakDays: Int
    /// Day of the most recent feeding, for streak bookkeeping.
    public var lastFedDayKey: String?
    /// Tokens eaten per day ("2026-06-12" → tokens), kept for the last 14 days
    /// to draw the weekly trend. Optional so states saved before this field
    /// existed still decode.
    public var days: [String: Int]?
    public var unlockedAchievements: Set<Achievement>?

    public init() {
        xp = 0
        tokenCarry = 0
        tokensToday = 0
        mealsToday = 0
        totalTokens = 0
        totalMeals = 0
        lastFedAt = nil
        dayKey = ""
        streakDays = 0
        lastFedDayKey = nil
        days = [:]
    }
}

/// Pure feeding/levelling rules. Deliberately free of wall-clock reads:
/// callers pass `now` so behaviour is deterministic and testable.
public enum PetCare {

    /// One XP per this many tokens eaten.
    public static let tokensPerXP = 5_000
    /// XP for finishing a session. Worth more per unit than raw burn so
    /// *completing* work beats merely consuming.
    public static let mealXP = 25

    // MARK: - Levels

    /// Levelling from `level` to `level + 1` costs `120 * level` XP, so the
    /// total XP to *reach* level `n` is `60·n·(n−1)`. Level 2 ≈ 5 finished
    /// sessions; level 10 needs 5 400 XP; level 35 (Legend) 71 400.
    public static func xpToReach(level: Int) -> Int {
        guard level > 1 else { return 0 }
        return 60 * level * (level - 1)
    }

    public static func level(forXP xp: Int) -> Int {
        var level = 1
        while xpToReach(level: level + 1) <= xp { level += 1 }
        return level
    }

    /// The level shown to the user. A brand-new pet (no XP) reads as Lv 0;
    /// feeding it one full bar (600k tokens) makes it Lv 1, and so on. This is
    /// just the internal level minus one, kept in one place so every surface
    /// (chooser, Care tab, HUD, web) agrees.
    public static func displayLevel(forXP xp: Int) -> Int {
        max(0, level(forXP: xp) - 1)
    }

    /// Progress within the current level, 0…1.
    public static func progress(forXP xp: Int) -> Double {
        let level = level(forXP: xp)
        let floor = xpToReach(level: level)
        let ceiling = xpToReach(level: level + 1)
        guard ceiling > floor else { return 0 }
        return Double(xp - floor) / Double(ceiling - floor)
    }

    /// XP earned within the current level, and the span to the next one — so a
    /// bar reads "141 / 720 XP" (matching the percentage) instead of an
    /// absolute total that looks inconsistent with the progress fill.
    public static func xpWithinLevel(forXP xp: Int) -> (inLevel: Int, span: Int) {
        let level = level(forXP: xp)
        let floor = xpToReach(level: level)
        let ceiling = xpToReach(level: level + 1)
        return (max(0, xp - floor), max(1, ceiling - floor))
    }

    /// Evolution stages by level. Returned as a localization key.
    public static func stageName(forLevel level: Int) -> String {
        switch level {
        case ..<5: return "Hatchling"
        case 5..<10: return "Companion"
        case 10..<20: return "Scout"
        case 20..<35: return "Hero"
        default: return "Legend"
        }
    }

    /// Stage index 0…4 (for badge styling).
    public static func stageIndex(forLevel level: Int) -> Int {
        switch level {
        case ..<5: return 0
        case 5..<10: return 1
        case 10..<20: return 2
        case 20..<35: return 3
        default: return 4
        }
    }

    // MARK: - Hunger

    /// Hunger from the time since the last feeding. A pet that has never been
    /// fed starts merely peckish — not punishing on first launch.
    public static func hunger(state: PetCareState, now: Date) -> PetHunger {
        guard let last = state.lastFedAt else { return .peckish }
        let hours = now.timeIntervalSince(last) / 3600
        switch hours {
        case ..<4: return .full
        case ..<10: return .satisfied
        case ..<24: return .peckish
        case ..<48: return .hungry
        default: return .starving
        }
    }

    // MARK: - Feeding

    /// Feeds `tokens` (e.g. a Claude turn's usage delta). XP accrues at
    /// `tokensPerXP` with the sub-XP remainder carried. Returns the XP gained.
    @discardableResult
    public static func feedTokens(
        _ tokens: Int, state: inout PetCareState, now: Date, calendar: Calendar = .current
    ) -> Int {
        guard tokens > 0 else { return 0 }
        rollover(&state, now: now, calendar: calendar)

        state.totalTokens += tokens
        state.tokensToday += tokens

        // Daily history for the weekly trend, pruned to the most recent 14
        // entries. States saved before the field existed seed today's entry
        // from the running daily counter.
        let today = dayKey(for: now, calendar: calendar)
        var days = state.days ?? [today: max(0, state.tokensToday - tokens)]
        days[today, default: 0] += tokens
        if days.count > 14 {
            for key in days.keys.sorted().dropLast(14) { days.removeValue(forKey: key) }
        }
        state.days = days

        let pool = state.tokenCarry + tokens
        let gained = pool / tokensPerXP
        state.tokenCarry = pool % tokensPerXP
        state.xp += gained
        markFed(&state, now: now, calendar: calendar)
        return gained
    }

    /// Tokens still needed to reach the next level at the token-feeding rate
    /// (meals shorten this, but it's the honest "keep vibing" number).
    public static func tokensToNextLevel(state: PetCareState) -> Int {
        let xpNeeded = xpToReach(level: level(forXP: state.xp) + 1) - state.xp
        return max(0, xpNeeded * tokensPerXP - state.tokenCarry)
    }

    /// Records a finished session ("a proper meal"). Returns the XP gained.
    @discardableResult
    public static func recordMeal(
        state: inout PetCareState, now: Date, calendar: Calendar = .current
    ) -> Int {
        rollover(&state, now: now, calendar: calendar)
        state.totalMeals += 1
        state.mealsToday += 1
        state.xp += mealXP
        markFed(&state, now: now, calendar: calendar)
        return mealXP
    }

    /// Resets the daily counters when the local calendar day has changed.
    /// Public so observers (UI refresh timers) can roll the day over too.
    public static func rollover(
        _ state: inout PetCareState, now: Date, calendar: Calendar = .current
    ) {
        let today = dayKey(for: now, calendar: calendar)
        guard state.dayKey != today else { return }
        state.dayKey = today
        state.tokensToday = 0
        state.mealsToday = 0
    }

    /// Tokens per day for the trailing `count` days ending today, oldest first.
    /// Labels are the day-of-month, for compact trend axes.
    public static func recentDays(
        state: PetCareState, now: Date, count: Int = 7, calendar: Calendar = .current
    ) -> [(label: String, tokens: Int)] {
        var out: [(String, Int)] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let d = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = dayKey(for: d, calendar: calendar)
            let day = calendar.dateComponents([.day], from: d).day ?? 0
            out.append(("\(day)", state.days?[key] ?? 0))
        }
        return out
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Achievements

    public static func checkAchievements(state: PetCareState, hour: Int) -> Set<Achievement> {
        let dl = displayLevel(forXP: state.xp)

        let mealThresholds: [(Int, Achievement)] = [
            (1, .firstMeal), (100, .sessions100), (500, .sessions500),
        ]
        let tokenThresholds: [(Int, Achievement)] = [
            (1_000_000, .tokens1M), (10_000_000, .tokens10M), (50_000_000, .tokens50M),
        ]
        let levelThresholds: [(Int, Achievement)] = [
            (5, .level5), (10, .level10), (20, .level20), (35, .level35),
        ]
        let streakThresholds: [(Int, Achievement)] = [
            (7, .streak7), (14, .streak14), (30, .streak30),
        ]

        var result = Set<Achievement>()
        for (threshold, badge) in mealThresholds   where state.totalMeals  >= threshold { result.insert(badge) }
        for (threshold, badge) in tokenThresholds  where state.totalTokens >= threshold { result.insert(badge) }
        for (threshold, badge) in levelThresholds  where dl                >= threshold { result.insert(badge) }
        for (threshold, badge) in streakThresholds where state.streakDays  >= threshold { result.insert(badge) }
        if hour < 6, state.totalMeals >= 1 { result.insert(.nightOwl) }
        return result
    }

    @discardableResult
    public static func unlockNewAchievements(
        state: inout PetCareState, now: Date, calendar: Calendar = .current
    ) -> Set<Achievement> {
        let hour = calendar.component(.hour, from: now)
        let qualified = checkAchievements(state: state, hour: hour)
        let already = state.unlockedAchievements ?? []
        let newly = qualified.subtracting(already)
        state.unlockedAchievements = already.union(newly)
        return newly
    }

    /// Human-readable display name for an achievement, localised.
    public static func achievementDisplayName(_ a: Achievement) -> String {
        switch a {
        case .firstMeal:   return NSLocalizedString("First Meal", comment: "achievement name")
        case .sessions100: return NSLocalizedString("100 Sessions", comment: "achievement name")
        case .sessions500: return NSLocalizedString("500 Sessions", comment: "achievement name")
        case .tokens1M:    return NSLocalizedString("1M Tokens", comment: "achievement name")
        case .tokens10M:   return NSLocalizedString("10M Tokens", comment: "achievement name")
        case .tokens50M:   return NSLocalizedString("50M Tokens", comment: "achievement name")
        case .level5:      return NSLocalizedString("Level 5", comment: "achievement name")
        case .level10:     return NSLocalizedString("Level 10", comment: "achievement name")
        case .level20:     return NSLocalizedString("Level 20", comment: "achievement name")
        case .level35:     return NSLocalizedString("Level 35", comment: "achievement name")
        case .streak7:     return NSLocalizedString("7-Day Streak", comment: "achievement name")
        case .streak14:    return NSLocalizedString("14-Day Streak", comment: "achievement name")
        case .streak30:    return NSLocalizedString("30-Day Streak", comment: "achievement name")
        case .nightOwl:    return NSLocalizedString("Night Owl", comment: "achievement name")
        }
    }

    /// How to unlock an achievement, localised. Shown on hover so users know
    /// what each badge takes.
    public static func achievementDescription(_ a: Achievement) -> String {
        switch a {
        case .firstMeal:   return NSLocalizedString("Finish your first agent session", comment: "achievement hint")
        case .sessions100: return NSLocalizedString("Finish 100 agent sessions", comment: "achievement hint")
        case .sessions500: return NSLocalizedString("Finish 500 agent sessions", comment: "achievement hint")
        case .tokens1M:    return NSLocalizedString("Burn 1M tokens", comment: "achievement hint")
        case .tokens10M:   return NSLocalizedString("Burn 10M tokens", comment: "achievement hint")
        case .tokens50M:   return NSLocalizedString("Burn 50M tokens", comment: "achievement hint")
        case .level5:      return NSLocalizedString("Reach Level 5", comment: "achievement hint")
        case .level10:     return NSLocalizedString("Reach Level 10", comment: "achievement hint")
        case .level20:     return NSLocalizedString("Reach Level 20", comment: "achievement hint")
        case .level35:     return NSLocalizedString("Reach Level 35 (Legend)", comment: "achievement hint")
        case .streak7:     return NSLocalizedString("Feed your pet 7 days in a row", comment: "achievement hint")
        case .streak14:    return NSLocalizedString("Feed your pet 14 days in a row", comment: "achievement hint")
        case .streak30:    return NSLocalizedString("Feed your pet 30 days in a row", comment: "achievement hint")
        case .nightOwl:    return NSLocalizedString("Finish a session after midnight", comment: "achievement hint")
        }
    }

    private static func markFed(_ state: inout PetCareState, now: Date, calendar: Calendar) {
        state.lastFedAt = now
        let today = dayKey(for: now, calendar: calendar)
        if state.lastFedDayKey != today {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
                .map { dayKey(for: $0, calendar: calendar) }
            state.streakDays = (state.lastFedDayKey == yesterday) ? state.streakDays + 1 : 1
            state.lastFedDayKey = today
        }
    }
}
