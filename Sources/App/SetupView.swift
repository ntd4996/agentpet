import SwiftUI
import AgentPetCore

/// Native macOS-style settings: a preferences-style toolbar of tabs over
/// grouped forms (dark).
struct SetupView: View {
    @ObservedObject private var model = SettingsModel.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    var onClose: () -> Void

    enum Tab { case general, pet, about }
    @State private var tab: Tab = .general

    private var selectedPack: ImagePetPack? {
        pet.selectedPetID.flatMap { imagePets.pack(id: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch tab {
                case .general:
                    GeneralTab(model: model, pet: pet)
                case .pet:
                    PetTab(pet: pet, imagePets: imagePets, model: model, selectedPack: selectedPack)
                case .about:
                    AboutTab()
                }
            }
        }
        .frame(width: 560, height: 600)
        .preferredColorScheme(.dark)
        .noFocusRing()
        .onAppear { model.refresh() }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            TabButton(icon: "gearshape.fill", label: "General", selected: tab == .general) { tab = .general }
            TabButton(icon: "pawprint.fill", label: "Pet", selected: tab == .pet) { tab = .pet }
            TabButton(icon: "heart.fill", label: "About", selected: tab == .about) { tab = .about }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct TabButton: View {
    let icon: String
    let label: String
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
    let title: String
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
    @ObservedObject private var chat = ChatSettings.shared
    @ObservedObject private var sound = SoundSettings.shared
    // Local mirror of the system login-item state so the toggle re-renders
    // reliably (the SMAppService status isn't observable on its own).
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
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

            Section("Pet chat") {
                HStack {
                    Text("Show chat bubble")
                    Spacer()
                    ColorSwitch(isOn: $pet.showChat)
                }
                Picker("Messages", selection: $chat.source) {
                    Text("System").tag(ChatSettings.Source.system)
                    Text("Custom").tag(ChatSettings.Source.custom)
                }
                .pickerStyle(.segmented)
                if chat.source == .custom {
                    ForEach(ChatSettings.editableMoods, id: \.self) { mood in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(moodLabel(mood)).font(.caption).foregroundStyle(.secondary)
                            GrowingTextEditor(text: Binding(
                                get: { chat.text(for: mood) },
                                set: { chat.setText($0, for: mood) }
                            ))
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.16)))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    HStack {
                        Text("One message per line; a random one is shown.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset to defaults") { chat.resetToDefaults() }
                            .controlSize(.small)
                    }
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
                            if let note = agent.note {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            } else if model.isInstalled(agent.kind) {
                                Text("Hook installed").font(.caption).foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        if agent.isSupported {
                            Button(model.isInstalled(agent.kind) ? "Remove" : "Install") {
                                model.toggleInstall(agent.kind)
                            }
                        } else {
                            Text("Coming soon").foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = model.lastHookError {
                    Text(error).font(.caption).foregroundStyle(.red)
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
    }

    private func moodLabel(_ mood: PetMood) -> String {
        switch mood {
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .done: return "Done"
        case .celebrate: return "Celebrate"
        case .idle: return "Idle"
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var notificationTitle: String {
        switch model.notificationState {
        case .enabled: return model.notificationsEnabled ? "Notifications on" : "Notifications muted"
        case .denied: return "Notifications denied"
        case .unavailable: return "Notifications unavailable"
        case .notDetermined: return "Enable notifications"
        }
    }

    private var notificationDetail: String {
        switch model.notificationState {
        case .unavailable: return "Available once installed as AgentPet.app"
        case .denied: return "Turn on in System Settings to get alerts"
        case .enabled: return model.notificationsEnabled
            ? "Alerts when an agent finishes or needs input"
            : "Muted, the toggle turns alerts back on"
        case .notDetermined: return "Alerts when an agent finishes or needs input"
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
                Button { browsing = true } label: {
                    Label("Browse pets…", systemImage: "square.grid.2x2")
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
        case .idle: return "Idle"
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .done: return "Done"
        case .celebrate: return "Celebrate"
        }
    }
}
