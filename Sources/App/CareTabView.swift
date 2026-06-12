import SwiftUI
import AgentPetCore

/// The tamagotchi panel: level + evolution stage, hunger, today's feeding,
/// lifetime totals, and where the food data comes from.
struct CareTabView: View {
    @ObservedObject private var care = PetCareController.shared
    @ObservedObject private var usage = OpenUsageClient.shared
    @Environment(\.openURL) private var openURL

    /// Ticks so hunger and "today" counters stay fresh while the panel is open.
    @State private var now = Date()
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let stageIcons = ["leaf.fill", "pawprint.fill", "binoculars.fill", "shield.fill", "crown.fill"]
    private static let stageColors: [Color] = [.green, .teal, .blue, .purple, .orange]

    var body: some View {
        Form {
            Section("Companion") {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(stageColor.opacity(0.18))
                            .frame(width: 52, height: 52)
                        Image(systemName: stageIcon)
                            .font(.system(size: 22))
                            .foregroundStyle(stageColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(verbatim: "Lv \(care.level)")
                                .font(.title3).bold()
                            Text(NSLocalizedString(care.stageKey, comment: "evolution stage"))
                                .font(.caption).bold()
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(stageColor.opacity(0.2)))
                                .foregroundStyle(stageColor)
                        }
                        ProgressView(value: care.levelProgress)
                            .tint(stageColor)
                        Text(xpCaption)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Hunger") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(hungerLabel)
                        Spacer()
                        if let last = care.state.lastFedAt {
                            Text(String(format: NSLocalizedString("Last fed %@", comment: ""),
                                        last.formatted(.relative(presentation: .named))))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: fullness)
                        .tint(fullness > 0.5 ? .green : (fullness > 0.25 ? .orange : .red))
                    Text("The pet eats real work: tokens burnt by your agents and finished sessions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("Today") {
                LabeledContent("Tokens eaten") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: Self.tokenString(care.state.tokensToday))
                        if care.state.tokensToday >= PetCare.dailyTokenCap {
                            Text("Full! The daily bowl is empty.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                LabeledContent("Sessions finished", value: "\(care.state.mealsToday)")
                LabeledContent("Streak") {
                    Text(String(format: NSLocalizedString("%d days", comment: "streak"), care.state.streakDays))
                }
            }

            Section("Lifetime") {
                LabeledContent("Total tokens eaten", value: Self.tokenString(care.state.totalTokens))
                LabeledContent("Total sessions", value: "\(care.state.totalMeals)")
            }

            Section("Food sources") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code transcripts")
                        Text("Token usage is read locally when a turn ends.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Active").font(.caption).bold().foregroundStyle(.green)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "OpenUsage")
                        Text(usage.available
                             ? "Connected , subscription limits below."
                             : "Optional: install OpenUsage to track every provider's limits.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if usage.available {
                        Text("Connected").font(.caption).bold().foregroundStyle(.green)
                    } else {
                        Button("Get it") { openURL(URL(string: "https://www.openusage.ai")!) }
                            .controlSize(.small)
                    }
                }
                if usage.available {
                    ForEach(usage.providers) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: p.displayName)
                                if let today = p.todayLabel {
                                    Text(verbatim: today).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let left = p.fractionLeft {
                                Text(verbatim: "\(Int((left * 100).rounded()))%")
                                    .font(.caption).bold()
                                    .foregroundStyle(left < 0.15 ? .red : (left < 0.4 ? .orange : .secondary))
                                Text("left").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            care.refreshDay()
            usage.poll()
        }
        .onReceive(tick) { date in
            now = date
            care.refreshDay()
        }
    }

    // MARK: - Derived display

    private var stageIcon: String { Self.stageIcons[min(care.stageIndex, Self.stageIcons.count - 1)] }
    private var stageColor: Color { Self.stageColors[min(care.stageIndex, Self.stageColors.count - 1)] }

    private var xpCaption: String {
        let xp = care.state.xp
        let next = PetCare.xpToReach(level: care.level + 1)
        return String(format: NSLocalizedString("%@ / %@ XP to next level", comment: ""),
                      Self.plain(xp), Self.plain(next))
    }

    /// Continuous fullness 0…1 from the time since the last feeding (48h → empty).
    private var fullness: Double {
        guard let last = care.state.lastFedAt else { return 0.5 }
        let hours = now.timeIntervalSince(last) / 3600
        return max(0, min(1, 1 - hours / 48))
    }

    private var hungerLabel: String {
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
