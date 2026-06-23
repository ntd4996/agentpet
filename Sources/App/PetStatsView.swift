import AppKit
import SwiftUI
import AgentPetCore

/// The pet's right-click HUD: the companion's stats plus a compact footer with
/// Settings / Updates / Quit (the same actions as the menu bar popover).
struct PetStatsView: View {
    @ObservedObject private var care = PetCareController.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject private var usage = OpenUsageClient.shared
    @ObservedObject private var updater = UpdaterController.shared
    @State private var updateLabel: String?
    @State private var hoveredAchievement: Achievement?

    private static let stageColors: [Color] = [.green, .teal, .blue, .purple, .orange]

    private var pack: ImagePetPack? {
        pet.selectedPetID.flatMap { imagePets.pack(id: $0) }
    }

    private var stageColor: Color { Self.stageColors[min(care.stageIndex, Self.stageColors.count - 1)] }

    var body: some View {
        let state = care.current
        VStack(alignment: .leading, spacing: 12) {
            header(state)
            xpBlock(state)
            achievementBlock
            statGrid(state)
            trendBlock(state)
            usageBlock
            if let last = state.lastFedAt {
                HStack {
                    Text("Last fed").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text(verbatim: last.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial)
        .environment(\.colorScheme, .dark)
        .textSelection(.enabled)
        .noFocusRing()
    }

    // MARK: - Footer (Settings / Updates / Quit)

    private var footer: some View {
        VStack(spacing: 8) {
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                footButton(icon: "gearshape", label: "Settings") {
                    PetWindowController.shared.closeStatsPopover()
                    SettingsWindowController.shared.show()
                }
                footButton(icon: "arrow.triangle.2.circlepath",
                           label: updateLabel ?? NSLocalizedString("Updates", comment: ""),
                           badge: updater.updatePending) {
                    updateLabel = NSLocalizedString("Checking…", comment: "")
                    UpdaterController.shared.checkForUpdates()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { updateLabel = nil }
                }
                Spacer()
                footButton(icon: "power", label: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func footButton(icon: String, label: String, badge: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                    if badge {
                        Circle().fill(Color.orange).frame(width: 5, height: 5).offset(x: 3, y: -3)
                    }
                }
                Text(verbatim: label)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private func header(_ state: PetCareState) -> some View {
        HStack(spacing: 10) {
            Group {
                if let frame = pack?.clip(0).first {
                    Image(nsImage: frame).resizable().interpolation(.none).scaledToFit().padding(4)
                } else {
                    Image(systemName: "pawprint.fill").foregroundStyle(.secondary)
                }
            }
            .frame(width: 46, height: 46)
            .background(RoundedRectangle(cornerRadius: 10).fill(stageColor.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                Text(pack?.displayName ?? NSLocalizedString("Your pet", comment: ""))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text(verbatim: "Lv \(care.level)")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(stageColor)
                    StageBadge(stageIndex: care.stageIndex, size: 16)
                    Text(NSLocalizedString(care.stageKey, comment: "stage"))
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(stageColor.opacity(0.2)))
                        .foregroundStyle(stageColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(hungerText)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                ProgressView(value: fullness)
                    .tint(fullness > 0.5 ? .green : (fullness > 0.25 ? .orange : .red))
                    .controlSize(.small)
                    .frame(width: 64)
            }
        }
    }

    // MARK: - XP

    private func xpBlock(_ state: PetCareState) -> some View {
        let (inLevel, span) = PetCare.xpWithinLevel(forXP: state.xp)
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: care.levelProgress).tint(stageColor).controlSize(.small)
            HStack {
                Text(verbatim: "\(Self.plain(inLevel)) / \(Self.plain(span)) XP")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text(verbatim: "\(Int((care.levelProgress * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(stageColor)
            }
            Text(String(format: NSLocalizedString("≈ %@ tokens to Lv %d", comment: ""),
                        Self.tokenString(PetCare.tokensToNextLevel(state: state)), care.level + 1))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(stageColor.opacity(0.9))
        }
    }

    // MARK: - Achievements

    private static let achievementSymbols: [Achievement: String] = [
        .firstMeal:   "fork.knife",
        .sessions100: "trophy",
        .sessions500: "trophy.fill",
        .tokens1M:    "flame",
        .tokens10M:   "flame.fill",
        .tokens50M:   "bolt.fill",
        .level5:      "star",
        .level10:     "star.fill",
        .level20:     "shield.fill",
        .level35:     "crown.fill",
        .streak7:     "calendar",
        .streak14:    "calendar.badge.clock",
        .streak30:    "calendar.badge.checkmark",
        .nightOwl:    "moon.fill",
    ]

    private var achievementBlock: some View {
        let unlocked = care.achievements
        let total = Achievement.allCases.count
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Achievements")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Text(verbatim: "\(unlocked.count) / \(total)")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            }
            HStack(spacing: 2) {
                ForEach(Achievement.allCases, id: \.self) { a in
                    let symbol = Self.achievementSymbols[a] ?? "star"
                    let isUnlocked = unlocked.contains(a)
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(isUnlocked ? stageColor : Color.white.opacity(0.15))
                        // Distribute evenly across the card width so 14 badges
                        // never overflow the fixed 300pt popover (the overflow
                        // clipped the whole HUD's left edge).
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(hoveredAchievement == a ? Color.white.opacity(0.08) : .clear)
                        )
                        .help(PetCare.achievementDisplayName(a))
                        .onHover { inside in
                            hoveredAchievement = inside ? a : (hoveredAchievement == a ? nil : hoveredAchievement)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            achievementHint(unlocked: unlocked)
        }
    }

    /// A single line under the badge row: hovering a badge shows its name, how to
    /// unlock it, and whether it's done. Reliable in the floating HUD where the
    /// system `.help` tooltip can be slow or suppressed.
    @ViewBuilder private func achievementHint(unlocked: Set<Achievement>) -> some View {
        HStack(spacing: 5) {
            if let a = hoveredAchievement {
                let done = unlocked.contains(a)
                Image(systemName: done ? "checkmark.circle.fill" : "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(done ? stageColor : .white.opacity(0.35))
                Text(PetCare.achievementDisplayName(a))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                Text(verbatim: "·").font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
                Text(PetCare.achievementDescription(a))
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            } else {
                Text("Hover a badge to see how to unlock it")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 12)
    }

    // MARK: - Stat grid

    private func statGrid(_ state: PetCareState) -> some View {
        let cells: [(String, String, String)] = [
            (NSLocalizedString("Today", comment: ""), Self.tokenString(state.tokensToday),
             mealText(state.mealsToday)),
            (NSLocalizedString("Streak", comment: ""), streakValue(state),
             NSLocalizedString("days fed", comment: "")),
            (NSLocalizedString("Lifetime", comment: ""), Self.tokenString(state.totalTokens),
             NSLocalizedString("tokens eaten", comment: "")),
            (NSLocalizedString("Sessions", comment: ""), "\(state.totalMeals)",
             NSLocalizedString("completed", comment: "")),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(cells, id: \.0) { cell in
                VStack(alignment: .leading, spacing: 1) {
                    Text(cell.0.uppercased())
                        .font(.system(size: 8, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(.white.opacity(0.35))
                    Text(verbatim: cell.1)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Text(verbatim: cell.2)
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
        }
    }

    // MARK: - 7-day trend

    private func trendBlock(_ state: PetCareState) -> some View {
        let series = PetCare.recentDays(state: state, now: Date())
        let peak = max(series.map(\.tokens).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Burn, last 7 days")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Text(verbatim: Self.tokenString(series.map(\.tokens).reduce(0, +)))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(series.enumerated()), id: \.offset) { i, day in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i == series.count - 1 ? stageColor : stageColor.opacity(0.4))
                            .frame(height: max(3, CGFloat(day.tokens) / CGFloat(peak) * 34))
                            .frame(maxWidth: .infinity)
                        Text(verbatim: day.label)
                            .font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .frame(height: 48, alignment: .bottom)
        }
    }

    // MARK: - Usage / limits

    @ObservedObject private var probe = NativeUsageProbe.shared

    @ViewBuilder private var usageBlock: some View {
        let providers = NativeUsageProbe.combined()
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("Limits")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.35))
                ForEach(providers) { p in
                    let used = 1 - (p.fractionLeft ?? 0)      // bar fills as you spend
                    // Match the level bar's stage colour; only flip to a warning
                    // tint when a budget is nearly spent.
                    let color: Color = used > 0.9 ? .red : (used > 0.75 ? .orange : stageColor)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(verbatim: p.displayName)
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                            if let w = p.windowLabel {
                                Text(verbatim: w).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                            Text(String(format: NSLocalizedString("%d%% used", comment: ""), Int((used * 100).rounded())))
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
                            if let reset = Self.resetText(p.resetsAt) {
                                Text(verbatim: "· \(reset)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.1))
                                Capsule().fill(color).frame(width: max(2, geo.size.width * used))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
    }

    /// "resets in 3h" / "in 12m" from a reset timestamp.
    static func resetText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let secs = date.timeIntervalSinceNow
        guard secs > 0 else { return nil }
        if secs >= 86400 { return String(format: NSLocalizedString("resets in %dd", comment: ""), Int(secs / 86400)) }
        if secs >= 3600 { return String(format: NSLocalizedString("resets in %dh", comment: ""), Int(secs / 3600)) }
        return String(format: NSLocalizedString("resets in %dm", comment: ""), max(1, Int(secs / 60)))
    }

    // MARK: - Derived

    /// Continuous fullness 0…1 (48h since the last feeding → empty).
    private var fullness: Double {
        guard let last = care.current.lastFedAt else { return 0.5 }
        let hours = Date().timeIntervalSince(last) / 3600
        return max(0, min(1, 1 - hours / 48))
    }

    private func mealText(_ meals: Int) -> String {
        meals == 1
            ? NSLocalizedString("1 meal", comment: "")
            : String(format: NSLocalizedString("%d meals", comment: ""), meals)
    }

    private func streakValue(_ s: PetCareState) -> String {
        "\(s.streakDays)"
    }

    private var hungerText: String {
        switch care.hunger {
        case .full: return NSLocalizedString("Full", comment: "hunger")
        case .satisfied: return NSLocalizedString("Satisfied", comment: "hunger")
        case .peckish: return NSLocalizedString("Peckish", comment: "hunger")
        case .hungry: return NSLocalizedString("Hungry", comment: "hunger")
        case .starving: return NSLocalizedString("Starving", comment: "hunger")
        }
    }

    private static func tokenString(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    private static func plain(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
