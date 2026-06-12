import SwiftUI
import AgentPetCore

/// Native macOS-style settings: a preferences-style toolbar of tabs over
/// grouped forms (dark).
struct SetupView: View {
    @ObservedObject private var model = SettingsModel.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject private var appLang = AppLanguage.shared
    var onClose: () -> Void
    /// Asks the window to resize to a target content width so the live-preview
    /// panel can slide in on the right. Provided by SettingsWindowController.
    var onResize: (CGFloat) -> Void = { _ in }

    enum Tab { case general, pet, care, bubble, about }
    @State private var tab: Tab = .general
    @State private var demoOpen = false

    private let baseWidth: CGFloat = 640
    private let demoWidth: CGFloat = 740

    private var selectedPack: ImagePetPack? {
        pet.selectedPetID.flatMap { imagePets.pack(id: $0) }
    }

    private func setDemo(_ open: Bool) {
        demoOpen = open
        onResize(open ? baseWidth + demoWidth : baseWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsColumn.frame(width: baseWidth)
            if demoOpen {
                Divider()
                SettingsDemoPanel(onClose: { setDemo(false) }).frame(width: demoWidth)
            }
        }
        .frame(width: demoOpen ? baseWidth + demoWidth : baseWidth, height: 600)
        .preferredColorScheme(.dark)
        .noFocusRing()
        .environment(\.locale, appLang.locale)
        .id(appLang.lang.rawValue)   // recreate the tree so every Text re-resolves on language change
        .onAppear { model.refresh() }
    }

    private var settingsColumn: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch tab {
                case .general:
                    GeneralTab(model: model, pet: pet)
                case .pet:
                    PetTab(pet: pet, imagePets: imagePets, model: model, selectedPack: selectedPack)
                case .care:
                    CareTabView()
                case .bubble:
                    BubbleSettingsView()
                case .about:
                    AboutTab()
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            bottomBar
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { setDemo(!demoOpen) } label: {
                Label(demoOpen ? "Hide live preview" : "Live preview", systemImage: "sparkles.tv")
            }
            .buttonStyle(.borderedProminent).tint(Color.systemAccent).controlSize(.large)
            Text("Fire webhooks for many agents with your current settings")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            TabButton(icon: "gearshape.fill", label: "General", selected: tab == .general) { tab = .general }
            TabButton(icon: "pawprint.fill", label: "Pet", selected: tab == .pet) { tab = .pet }
            TabButton(icon: "fork.knife", label: "Care", selected: tab == .care) { tab = .care }
            TabButton(icon: "bubble.left.and.bubble.right.fill", label: "Bubble", selected: tab == .bubble) { tab = .bubble }
            TabButton(icon: "heart.fill", label: "About", selected: tab == .about) { tab = .about }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct TabButton: View {
    let icon: String
    let label: LocalizedStringKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19))
                Text(label).font(.system(size: 11))
            }
            .frame(width: 78, height: 48)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.systemAccent.opacity(0.22) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.systemAccent.opacity(0.55) : .clear, lineWidth: 1))
            .foregroundStyle(selected ? Color.systemAccent : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About

private struct AboutTab: View {
    @Environment(\.openURL) private var openURL

    private let repo = URL(string: "https://github.com/ntd4996/agentpet")!
    private let profile = URL(string: "https://github.com/ntd4996")!
    private let coffee = URL(string: "https://buymeacoffee.com/ntd4996")!
    private let discord = URL(string: "https://discord.gg/kzFJKsZav")!

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 40)).foregroundStyle(Color.systemAccent)
                    Text("AgentPet").font(.title2.bold())
                    Text("A desktop pet that watches your AI coding agents.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                Button { openURL(repo) } label: {
                    Label("Star on GitHub", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.systemAccent)
                .controlSize(.large)

                Button { openURL(discord) } label: {
                    Label("Join the Discord", systemImage: "bubble.left.and.bubble.right.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button { openURL(coffee) } label: {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } footer: {
                Text("If AgentPet helps your workflow, a star means a lot. Thank you!")
            }

            Section("Author") {
                Link(destination: profile) {
                    Label("Nguyễn Thành Đạt (@ntd4996)", systemImage: "person.crop.circle")
                }
                Link(destination: repo) {
                    Label("github.com/ntd4996/agentpet", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

private struct SoundRow: View {
    let title: LocalizedStringKey
    @Binding var enabled: Bool
    let customPath: String
    let onPlay: () -> Void
    let onUpload: () -> Void
    let onReset: () -> Void

    private var sourceLabel: String {
        customPath.isEmpty ? "Default" : (customPath as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                ColorSwitch(isOn: $enabled)
            }
            HStack(spacing: 8) {
                Text(sourceLabel)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { onPlay() } label: { Image(systemName: "play.circle") }.buttonStyle(.plain)
                Button("Upload…") { onUpload() }.controlSize(.small)
                if !customPath.isEmpty {
                    Button("Default") { onReset() }.controlSize(.small)
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
        }
    }
}

// MARK: - General (merged setup + general)

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var pet: PetController
    @ObservedObject private var sound = SoundSettings.shared
    @ObservedObject private var appLang = AppLanguage.shared
    // Local mirror of the system login-item state so the toggle re-renders
    // reliably (the SMAppService status isn't observable on its own).
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var showCodexHelp = false

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $appLang.lang) {
                    ForEach(AppLanguage.Lang.allCases) { l in
                        Text(l.label).tag(l)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Launch") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                        Text("AgentPet starts automatically when you sign in.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ColorSwitch(isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            LoginItem.setEnabled(newValue)
                            launchAtLogin = LoginItem.isEnabled
                        }))
}
            }

            Section("Notifications") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notificationTitle)
                        Text(notificationDetail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    notificationButton
                }
            }

            Section("Sounds") {
                SoundRow(title: "When an agent finishes",
                         enabled: $sound.doneEnabled,
                         customPath: sound.doneCustomPath,
                         onPlay: { sound.play(.done) },
                         onUpload: { sound.upload(for: .done) },
                         onReset: { sound.resetToDefault(.done) })
                SoundRow(title: "When an agent needs input",
                         enabled: $sound.waitingEnabled,
                         customPath: sound.waitingCustomPath,
                         onPlay: { sound.play(.waiting) },
                         onUpload: { sound.upload(for: .waiting) },
                         onReset: { sound.resetToDefault(.waiting) })
            }

            Section("Agent integrations") {
                ForEach(model.agents) { agent in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.displayName)
                            if agent.kind == .codex, model.isInstalled(.codex) {
                                Text("Installed , needs a one-time trust (tap ?)")
                                    .font(.caption).foregroundStyle(.orange)
                            } else if let note = agent.note {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            } else if model.isInstalled(agent.kind) {
                                Text("Hook installed").font(.caption).foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        if agent.kind == .codex {
                            Button { showCodexHelp = true } label: {
                                Image(systemName: "questionmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("How to connect Codex")
                        }
                        if agent.isSupported {
                            Button(model.isInstalled(agent.kind) ? "Remove" : "Install") {
                                model.toggleInstall(agent.kind)
                            }
                        } else {
                            Text("Coming soon").foregroundStyle(.secondary)
                        }
                    }
                }
                if let err = model.installError {
                    Text(err).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
            }

            Section {
                Button("Quit AgentPet") { NSApplication.shared.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCodexHelp) { CodexHelpView() }
    }



    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var notificationTitle: String {
        switch model.notificationState {
        case .enabled: return model.notificationsEnabled ? NSLocalizedString("Notifications on", comment: "") : NSLocalizedString("Notifications muted", comment: "")
        case .denied: return NSLocalizedString("Notifications denied", comment: "")
        case .unavailable: return NSLocalizedString("Notifications unavailable", comment: "")
        case .notDetermined: return NSLocalizedString("Enable notifications", comment: "")
        }
    }

    private var notificationDetail: String {
        switch model.notificationState {
        case .unavailable: return NSLocalizedString("Available once installed as AgentPet.app", comment: "")
        case .denied: return NSLocalizedString("Turn on in System Settings to get alerts", comment: "")
        case .enabled: return model.notificationsEnabled
            ? NSLocalizedString("Alerts when an agent finishes or needs input", comment: "")
            : NSLocalizedString("Muted, the toggle turns alerts back on", comment: "")
        case .notDetermined: return NSLocalizedString("Alerts when an agent finishes or needs input", comment: "")
        }
    }

    @ViewBuilder private var notificationButton: some View {
        switch model.notificationState {
        case .enabled:
            // Permission granted: an in-app toggle lets the user mute without
            // revoking the system permission.
            ColorSwitch(isOn: $model.notificationsEnabled)
        case .denied:
            Button("Open Settings") { model.openSystemNotificationSettings() }
        case .notDetermined:
            Button("Enable") { model.enableNotifications() }
        case .unavailable:
            EmptyView()
        }
    }
}

// MARK: - Pet tab

private struct PetTab: View {
    @ObservedObject var pet: PetController
    @ObservedObject var imagePets: ImagePetStore
    @ObservedObject var model: SettingsModel
    let selectedPack: ImagePetPack?
    @State private var browsing = false
    @State private var creating = false
    @State private var petQuery = ""

    private var filteredPacks: [ImagePetPack] {
        guard !petQuery.isEmpty else { return imagePets.packs }
        let q = petQuery.lowercased()
        return imagePets.packs.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    petPreview
                        .frame(width: 84, height: 84)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedPack?.displayName ?? "No pet selected")
                            .font(.title3.weight(.semibold))
                        if let desc = selectedPack?.description {
                            Text(desc).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                }
            }

            Section("Choose pet") {
                if imagePets.packs.isEmpty {
                    Text("No pets yet. Tap Browse to add one.").foregroundStyle(.secondary)
                } else {
                    if imagePets.packs.count > 4 {
                        NativeSearchField(text: $petQuery, placeholder: "Search your pets")
                    }
                    PetPager(packs: filteredPacks, selectedID: pet.selectedPetID,
                             onSelect: { pet.selectedPetID = $0 },
                             onDelete: { pack in
                                 let wasSelected = pet.selectedPetID == pack.id
                                 imagePets.delete(pack)
                                 if wasSelected { pet.selectedPetID = imagePets.packs.first?.id }
                             })
                }
                HStack {
                    Button { browsing = true } label: {
                        Label("Browse pets…", systemImage: "square.grid.2x2")
                    }
                    Button { creating = true } label: {
                        Label("Create pet…", systemImage: "square.and.pencil")
                    }
                }
            }

            if let pack = selectedPack {
                Section("Animations") {
                    AnimationPicker(pack: pack)
                }
            }

            Section("Size on screen") {
                HStack(spacing: 8) {
                    Slider(value: $pet.petPoint, in: PetController.minPoint...PetController.maxPoint)
                    Text("\(Int(pet.petPoint))")
                        .monospacedDigit().foregroundStyle(.secondary).fixedSize()
                    ForEach(PetController.presets, id: \.0) { preset in
                        Button(preset.0) { pet.animateSize(to: preset.1) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $browsing) {
            BrowsePetsView(onClose: { browsing = false })
        }
        .sheet(isPresented: $creating) {
            CreatePetView(
                onCreate: { id in
                    creating = false
                    imagePets.reload()
                    pet.selectedPetID = id
                },
                onCancel: { creating = false }
            )
        }
    }

    @ViewBuilder private var petPreview: some View {
        if let pack = selectedPack {
            ImageSpriteView(frames: pack.clip(0), mood: .idle, size: 78)
        } else {
            Image(systemName: "pawprint.fill").font(.system(size: 40)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Components

/// A single static sprite frame (no TimelineView), for grids where animating
/// every cell would be janky. Only the hero preview animates.
private struct StaticFrame: View {
    let image: NSImage?
    var size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "pawprint.fill").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct PetPager: View {
    let packs: [ImagePetPack]
    let selectedID: String?
    let onSelect: (String) -> Void
    let onDelete: (ImagePetPack) -> Void
    @State private var page = 0

    private let perPage = 8

    var body: some View {
        let pageCount = max(1, Int(ceil(Double(packs.count) / Double(perPage))))
        let current = min(page, pageCount - 1)

        VStack(spacing: 10) {
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { p in
                        grid(for: p).frame(width: geo.size.width, alignment: .top)
                    }
                }
                .offset(x: -CGFloat(current) * geo.size.width)
                .animation(.easeInOut(duration: 0.28), value: current)
            }
            .frame(height: 188)
            .clipped()

            if pageCount > 1 {
                HStack(spacing: 14) {
                    arrow("chevron.left", enabled: current > 0) { page = max(0, current - 1) }
                    HStack(spacing: 5) {
                        ForEach(0..<pageCount, id: \.self) { i in
                            Circle()
                                .fill(i == current ? Color.systemAccent : .secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                    arrow("chevron.right", enabled: current < pageCount - 1) { page = min(pageCount - 1, current + 1) }
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: packs.count) { _ in page = 0 }
    }

    private func grid(for pageIndex: Int) -> some View {
        let slice = Array(packs.dropFirst(pageIndex * perPage).prefix(perPage))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                         alignment: .leading, spacing: 12) {
            ForEach(slice) { pack in
                PetThumb(pack: pack, selected: selectedID == pack.id,
                         select: { onSelect(pack.id) },
                         onDelete: { onDelete(pack) })
            }
        }
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.3))
        .disabled(!enabled)
    }
}

private struct PetThumb: View {
    let pack: ImagePetPack
    let selected: Bool
    let select: () -> Void
    var onDelete: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                StaticFrame(image: pack.clip(0).first, size: 48)
                    .frame(width: 56, height: 48)
                Text(pack.displayName).font(.caption).lineLimit(1).frame(width: 64)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.systemAccent.opacity(0.2) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.systemAccent : .secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering = $0 }
    }
}

private struct AnimationPicker: View {
    let pack: ImagePetPack
    @ObservedObject private var store = PetBindingsStore.shared
    @State private var state: PetMood = .working
    @State private var hoveredClip: Int?

    private let states: [PetMood] = [.idle, .working, .waiting, .done, .celebrate]

    var body: some View {
        Picker("State", selection: $state) {
            ForEach(states, id: \.self) { Text(label($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        Text("Hover a clip to preview it.")
            .font(.caption2).foregroundStyle(.secondary)

        let current = store.clipIndex(packId: pack.id, clipCount: pack.clipCount, mood: state)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
            ForEach(0..<pack.clipCount, id: \.self) { i in
                Button {
                    store.setClip(i, mood: state, packId: pack.id, clipCount: pack.clipCount)
                } label: {
                    VStack(spacing: 3) {
                        Group {
                            if hoveredClip == i {
                                ImageSpriteView(frames: pack.clip(i), mood: .working, size: 44)
                            } else {
                                StaticFrame(image: pack.clip(i).first, size: 44)
                            }
                        }
                        .frame(width: 54, height: 44)
                        Text("Clip \(i + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 9).fill(i == current ? Color.systemAccent.opacity(0.2) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(i == current ? Color.systemAccent : .secondary.opacity(0.25), lineWidth: i == current ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredClip = $0 ? i : (hoveredClip == i ? nil : hoveredClip) }
            }
        }
        .padding(.vertical, 4)
    }

    private func label(_ mood: PetMood) -> String {
        switch mood {
        case .idle: return NSLocalizedString("Idle", comment: "pet mood")
        case .working: return NSLocalizedString("Working", comment: "pet mood")
        case .waiting: return NSLocalizedString("Waiting", comment: "pet mood")
        case .done: return NSLocalizedString("Done", comment: "pet mood")
        case .celebrate: return NSLocalizedString("Celebrate", comment: "pet mood")
        }
    }
}

// MARK: - Codex connection help

/// Explains the one-time `/hooks` trust step Codex requires before AgentPet's
/// hook runs (Codex blocks unknown command hooks for security). Other agents
/// need no such step.
private struct CodexHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable { let n: Int; let text: String; var id: Int { n } }
    private let steps: [Step] = [
        .init(n: 1, text: NSLocalizedString("Open Terminal and run: codex (launches the Codex CLI)", comment: "codex help step")),
        .init(n: 2, text: NSLocalizedString("Type /hooks and press Enter to list the hooks.", comment: "codex help step")),
        .init(n: 3, text: NSLocalizedString("Press t to Trust all hooks.", comment: "codex help step")),
        .init(n: 4, text: NSLocalizedString("Quit and reopen Codex (both the CLI and the desktop app).", comment: "codex help step")),
        .init(n: 5, text: NSLocalizedString("Run any prompt , your pet now shows the Codex session.", comment: "codex help step")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.title2).foregroundStyle(.blue)
                Text("Connect Codex").font(.title3.bold())
                Spacer()
            }

            Text("The hook is installed. Codex blocks unknown command hooks until you trust them once , a Codex security feature, not an AgentPet bug. Do this one time:")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { s in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(s.n)")
                            .font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(.blue))
                        Text(s.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            Text("Trust is shared, so trusting once in the CLI also covers the Codex desktop app. If /hooks shows nothing, add  [features] hooks = true  to ~/.codex/config.toml, then retry.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link("Codex hooks docs", destination: URL(string: "https://developers.openai.com/codex/hooks")!)
                    .font(.caption)
                Spacer()
                Button("Got it") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
