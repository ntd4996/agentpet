import SwiftUI
import AgentPetCore

/// The tamagotchi panel: level + evolution stage, hunger, today's feeding,
/// lifetime totals, and where the food data comes from.
struct CareTabView: View {
    @ObservedObject private var care = PetCareController.shared
    @ObservedObject private var usage = OpenUsageClient.shared
    @ObservedObject private var sync = CareSyncController.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @Environment(\.openURL) private var openURL

    /// Ticks so hunger and "today" counters stay fresh while the panel is open.
    @State private var now = Date()
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let stageIcons = ["leaf.fill", "pawprint.fill", "binoculars.fill", "shield.fill", "crown.fill"]
    private static let stageColors: [Color] = [.green, .teal, .blue, .purple, .orange]

    private var currentName: String {
        pet.selectedPetID.flatMap { imagePets.pack(id: $0)?.displayName } ?? NSLocalizedString("Your pet", comment: "")
    }

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
                            Text(verbatim: currentName)
                                .font(.title3).bold()
                            Text(verbatim: "Lv \(care.level)")
                                .font(.title3).foregroundStyle(.secondary)
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
                Text("Every pet levels up on its own: experience belongs to the companion you raise it with.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Hunger") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(hungerLabel)
                        Spacer()
                        if let last = care.current.lastFedAt {
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
                        Text(verbatim: Self.tokenString(care.current.tokensToday))
                        if care.current.tokensToday >= PetCare.dailyTokenCap {
                            Text("Full! The daily bowl is empty.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                LabeledContent("Sessions finished", value: "\(care.current.mealsToday)")
                LabeledContent("Streak") {
                    Text(care.current.streakDays == 1
                         ? NSLocalizedString("1 day", comment: "streak singular")
                         : String(format: NSLocalizedString("%d days", comment: "streak"), care.current.streakDays))
                }
            }

            Section("Lifetime") {
                LabeledContent("Total tokens eaten", value: Self.tokenString(care.current.totalTokens))
                LabeledContent("Total sessions", value: "\(care.current.totalMeals)")
            }

            if care.raisedPetIDs.count > 1 {
                Section("All companions") {
                    ForEach(care.raisedPetIDs, id: \.self) { id in
                        companionRow(id: id)
                    }
                    Text("Each companion keeps its own experience. Switch pets in the Pet tab to raise another one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Web profile") {
                if sync.linked {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if let login = sync.linkedLogin, !login.isEmpty {
                                Text(String(format: NSLocalizedString("Connected as %@", comment: ""), login))
                            } else {
                                Text("Connected to your profile")
                            }
                            if let at = sync.lastSyncAt {
                                Text(String(format: NSLocalizedString("Last synced %@", comment: ""),
                                            at.formatted(.relative(presentation: .named))))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Your companions appear on your profile page.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Open profile") {
                            openURL(URL(string: "https://agentpet.thenightwatcher.online/profile")!)
                        }
                        .controlSize(.small)
                        Button("Disconnect") { sync.disconnect() }.controlSize(.small)
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show your companions on your web profile")
                            Text("Your browser opens GitHub sign-in; the app links automatically.")
                                .font(.caption).foregroundStyle(.secondary)
                            if let err = sync.lastError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        Button {
                            sync.beginLink()
                        } label: {
                            Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                }
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
                             ? "Connected: subscription limits below."
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

    // MARK: - Companions

    @ViewBuilder
    private func companionRow(id: String) -> some View {
        let s = care.state(for: id)
        let lv = PetCare.level(forXP: s.xp)
        let idx = PetCare.stageIndex(forLevel: lv)
        let color = Self.stageColors[min(idx, Self.stageColors.count - 1)]
        HStack(spacing: 10) {
            Image(systemName: Self.stageIcons[min(idx, Self.stageIcons.count - 1)])
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: imagePets.pack(id: id)?.displayName ?? id)
                        .font(.system(size: 13, weight: .semibold))
                    if id == care.currentPetID {
                        Text("Raising").font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.systemAccent.opacity(0.2)))
                            .foregroundStyle(Color.systemAccent)
                    }
                }
                ProgressView(value: PetCare.progress(forXP: s.xp))
                    .tint(color)
                    .controlSize(.small)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "Lv \(lv)").font(.system(size: 12, weight: .bold))
                Text(verbatim: "\(Self.plain(s.xp)) XP")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Derived display

    private var stageIcon: String { Self.stageIcons[min(care.stageIndex, Self.stageIcons.count - 1)] }
    private var stageColor: Color { Self.stageColors[min(care.stageIndex, Self.stageColors.count - 1)] }

    private var xpCaption: String {
        let xp = care.current.xp
        let next = PetCare.xpToReach(level: care.level + 1)
        return String(format: NSLocalizedString("%@ / %@ XP to next level", comment: ""),
                      Self.plain(xp), Self.plain(next))
    }

    /// Continuous fullness 0…1 from the time since the last feeding (48h → empty).
    private var fullness: Double {
        guard let last = care.current.lastFedAt else { return 0.5 }
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
