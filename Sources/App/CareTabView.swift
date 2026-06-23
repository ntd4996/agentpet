import SwiftUI
import AgentPetCore

/// The tamagotchi panel: level + evolution stage, hunger, today's feeding,
/// lifetime totals, and where the food data comes from.
struct CareTabView: View {
    @ObservedObject private var care = PetCareController.shared
    @ObservedObject private var usage = OpenUsageClient.shared
    @ObservedObject private var probe = NativeUsageProbe.shared
    @ObservedObject private var sync = CareSyncController.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @Environment(\.openURL) private var openURL

    /// Ticks so hunger and "today" counters stay fresh while the panel is open.
    @State private var now = Date()
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let stageIcons = ["leaf.fill", "pawprint.fill", "binoculars.fill", "shield.fill", "crown.fill"]
    private static let stageColors: [Color] = [.green, .teal, .blue, .purple, .orange]

    private var currentPack: ImagePetPack? {
        pet.selectedPetID.flatMap { imagePets.pack(id: $0) }
    }

    private var currentName: String {
        currentPack?.displayName ?? NSLocalizedString("Your pet", comment: "")
    }

    var body: some View {
        Form {
            Section("Companion") {
                HStack(spacing: 14) {
                    Group {
                        if let frame = currentPack?.clip(0).first {
                            Image(nsImage: frame).resizable().interpolation(.none).scaledToFit()
                                .padding(5)
                        } else {
                            Image(systemName: stageIcon)
                                .font(.system(size: 22))
                                .foregroundStyle(stageColor)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(stageColor.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(verbatim: currentName)
                                .font(.title3).bold()
                            Text(verbatim: "Lv \(care.level)")
                                .font(.title3).foregroundStyle(.secondary)
                            StageBadge(stageIndex: care.stageIndex, size: 22)
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
                        Text(String(format: NSLocalizedString("≈ %@ tokens to Lv %d", comment: ""),
                                    Self.tokenString(PetCare.tokensToNextLevel(state: care.current)),
                                    care.level + 1))
                            .font(.caption).foregroundStyle(stageColor)
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
                    Text(verbatim: Self.plain(care.current.tokensToday))
                }
                LabeledContent("Sessions finished", value: "\(care.current.mealsToday)")
                LabeledContent("Streak") {
                    Text(care.current.streakDays == 1
                         ? NSLocalizedString("1 day", comment: "streak singular")
                         : String(format: NSLocalizedString("%d days", comment: "streak"), care.current.streakDays))
                }
            }

            Section("Lifetime") {
                LabeledContent("Total tokens eaten", value: Self.plain(care.current.totalTokens))
                LabeledContent("Total sessions", value: "\(care.current.totalMeals)")
            }

            Section {
                let unlocked = care.achievements
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 14) {
                    ForEach(Achievement.allCases, id: \.self) { a in
                        let on = unlocked.contains(a)
                        VStack(spacing: 4) {
                            Image(systemName: PetCare.achievementSymbol(a))
                                .font(.system(size: 18))
                                .foregroundStyle(on ? stageColor : Color.secondary.opacity(0.4))
                                .frame(height: 22)
                            Text(PetCare.achievementDisplayName(a))
                                .font(.system(size: 9))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(on ? .primary : .secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(on ? 1 : 0.5)
                        .help("\(PetCare.achievementDisplayName(a)) — \(PetCare.achievementDescription(a))")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Achievements")
            } footer: {
                Text(verbatim: "\(care.achievements.count) of \(Achievement.allCases.count) unlocked")
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

            Section {
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
            } header: {
                Text("Web profile")
            } footer: {
                Text("Connecting is optional. Your pet, its level and all stats live on this Mac whether or not you sign in, nothing leaves your machine until you connect.")
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
                        Text("Subscription limits")
                        Text(probe.providers.isEmpty
                             ? "Read directly from your Claude Code / Codex sign-ins. None found yet."
                             : "Read directly from your Claude Code / Codex sign-ins.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !probe.providers.isEmpty {
                        Text("Active").font(.caption).bold().foregroundStyle(.green)
                    }
                }
                ForEach(NativeUsageProbe.combined()) { p in
                    let used = 1 - (p.fractionLeft ?? 0)
                    let color: Color = used > 0.9 ? .red : (used > 0.75 ? .orange : stageColor)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(verbatim: p.displayName).font(.callout.weight(.medium))
                            if let w = p.windowLabel {
                                Text(verbatim: w).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: NSLocalizedString("%d%% used", comment: ""), Int((used * 100).rounded())))
                                .font(.caption.weight(.semibold)).foregroundStyle(color)
                            if let reset = PetStatsView.resetText(p.resetsAt) {
                                Text(verbatim: "· \(reset)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ProgressView(value: used).tint(color)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            care.refreshDay()
            probe.poll()
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
        let lv = PetCare.displayLevel(forXP: s.xp)
        let idx = PetCare.stageIndex(forLevel: PetCare.level(forXP: s.xp))
        let color = Self.stageColors[min(idx, Self.stageColors.count - 1)]
        HStack(spacing: 10) {
            Group {
                if let frame = imagePets.pack(id: id)?.clip(0).first {
                    Image(nsImage: frame).resizable().interpolation(.none).scaledToFit()
                } else {
                    Image(systemName: Self.stageIcons[min(idx, Self.stageIcons.count - 1)])
                        .font(.system(size: 13))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 24, height: 24)
            .overlay(alignment: .bottomTrailing) {
                StageBadge(stageIndex: idx, size: 13).offset(x: 3, y: 3)
            }
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
        let (inLevel, span) = PetCare.xpWithinLevel(forXP: care.current.xp)
        return String(format: NSLocalizedString("%@ / %@ XP to next level", comment: ""),
                      Self.plain(inLevel), Self.plain(span))
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
