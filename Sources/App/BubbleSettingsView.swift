import SwiftUI
import AgentPetCore
import UniformTypeIdentifiers

// MARK: - BubbleSettingsView

struct BubbleSettingsView: View {
    @ObservedObject private var settings = BubbleSettings.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var chat = ChatSettings.shared
    @ObservedObject private var bubbleMsgs = BubbleMessages.shared
    @State private var editingAgentKey = BubbleMessages.allKey
    @State private var dragging: BubbleToken?
    @State private var iconPickerKind: AgentKind?

    var body: some View {
        Form {
            modeSection
            appearanceSection
            if settings.multiAgentBubbleEnabled {
                agentsSection
                rowLayoutSection
                iconsSection
                styleSection
                activitySection
                bubbleMessagesSection
            } else {
                defaultBubbleSection
            }
        }
        .formStyle(.grouped)
        .popover(item: $iconPickerKind) { kind in
            IconPickerPopover(kind: kind)
        }
    }

    // MARK: - 1. Mode

    private var modeSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Multi-agent bubble")
                    Text("Structured rows with icons, state dots, and activity messages.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ColorSwitch(isOn: $settings.multiAgentBubbleEnabled)
            }
        } header: {
            Text("Bubble mode")
        }
    }

    /// Global look of the bubble (both simple and multi-agent): theme, opacity,
    /// font size. Always shown, independent of the multi-agent toggle.
    private var appearanceSection: some View {
        Section {
            HStack {
                Text("Theme")
                Spacer()
                Picker("Theme", selection: $settings.theme) {
                    ForEach(BubbleSettings.Theme.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }

            HStack {
                Text("Font size")
                Spacer()
                Picker("Font size", selection: $settings.fontSize) {
                    Text("S").tag(BubbleSettings.FontSize.small)
                    Text("M").tag(BubbleSettings.FontSize.medium)
                    Text("L").tag(BubbleSettings.FontSize.large)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }

            HStack {
                Text("Opacity")
                Slider(value: $settings.opacity, in: 0.6...1.0)
                Text("\(Int(settings.opacity * 100))%")
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show idle message")
                    Text("The pet's chatter while no agent is running.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ColorSwitch(isOn: $pet.showIdleMessage)
            }
        } header: {
            Text("Appearance")
        }
    }

    private var defaultBubbleSection: some View {
        Section {
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
        } header: {
            Text("Simple bubble")
        } footer: {
            Text("Turn on multi-agent bubble above for per-agent rows with icons and activity.")
        }
    }

    /// Custom messages for the multi-agent bubble, editable per agent kind (or
    /// "All agents"). A custom line OVERRIDES the live/theme text in the row;
    /// leaving Working empty keeps live activity. Done/celebrate is the line
    /// shown when every agent finishes. Independent of the simple bubble.
    private var bubbleMessagesSection: some View {
        Section {
            Picker("Messages", selection: $bubbleMsgs.source) {
                Text("System").tag(BubbleMessages.Source.system)
                Text("Custom").tag(BubbleMessages.Source.custom)
            }
            .pickerStyle(.segmented)
            if bubbleMsgs.source == .custom {
                Picker("Agent", selection: $editingAgentKey) {
                    Text("All agents").tag(BubbleMessages.allKey)
                    ForEach(BubbleMessages.editableAgents, id: \.self) { kind in
                        Text(TickerFormatter.agentLabel(for: kind)).tag(kind.rawValue)
                    }
                }
                .pickerStyle(.menu)
                ForEach(BubbleMessages.editableMoods, id: \.self) { mood in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(moodLabel(mood) + (mood == .working ? " (blank = live activity)" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                        GrowingTextEditor(text: Binding(
                            get: { bubbleMsgs.text(for: editingAgentKey, mood: mood) },
                            set: { bubbleMsgs.setText($0, for: editingAgentKey, mood: mood) }
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
                    Button("Reset to defaults") { bubbleMsgs.resetToDefaults(for: editingAgentKey) }
                        .controlSize(.small)
                }
            }
        } header: {
            Text("Bubble messages")
        } footer: {
            Text("Per-agent overrides win over \"All agents\". A custom line replaces the live/theme text and the real pet honours it.")
        }
    }

    private func moodLabel(_ mood: PetMood) -> String {
        switch mood {
        case .working:   return NSLocalizedString("Working", comment: "pet mood")
        case .waiting:   return NSLocalizedString("Waiting", comment: "pet mood")
        case .done:      return NSLocalizedString("Done", comment: "pet mood")
        case .celebrate: return NSLocalizedString("Celebrate", comment: "pet mood")
        case .idle:      return NSLocalizedString("Idle", comment: "pet mood")
        }
    }

    // MARK: - 2. Agents — what to show

    private var agentsSection: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rows")
                        .font(.subheadline)
                    Picker("Rows", selection: $settings.displayMode) {
                        ForEach(BubbleDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(settings.displayMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sessions")
                        .font(.subheadline)
                    Picker("Sessions", selection: $settings.sessionGrouping) {
                        ForEach(BubbleSessionGrouping.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(settings.sessionGrouping.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if settings.displayMode != .carousel {
                    Stepper(maxRowsLabel, value: $settings.maxSessions, in: 1...10)
                }

                if settings.sessionGrouping == .allSessions {
                    Toggle("Sort by agent kind", isOn: $settings.groupByKind)
                }
            } header: {
                Text("Display")
            }

            Section {
                Picker("Include states", selection: $settings.minStateFilter) {
                    ForEach(MinStateFilter.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
            } header: {
                Text("Filter")
            } footer: {
                Text("Which session states appear in the bubble.")
            }

            Section {
                ForEach(AgentCatalog.all, id: \.kind) { agent in
                    Toggle(agent.displayName, isOn: Binding(
                        get: { !settings.hiddenKinds.contains(agent.kind) },
                        set: { show in
                            if show { settings.hiddenKinds.remove(agent.kind) }
                            else    { settings.hiddenKinds.insert(agent.kind) }
                        }
                    ))
                }
            } header: {
                Text("Visible agents")
            }
        }
    }

    private var maxRowsLabel: String {
        let noun = settings.sessionGrouping == .byKind ? "agent kinds" : "sessions"
        return "Max \(noun): \(settings.maxSessions)"
    }

    // MARK: - 3. Row layout — preview + tokens

    private var inactiveTokens: [BubbleToken] {
        BubbleToken.allCases.filter { token in
            !settings.customLayout.tokens.contains { $0.token == token && $0.isVisible }
        }
    }

    private var activeTokenItems: [BubbleTokenItem] {
        settings.customLayout.tokens.filter { $0.isVisible }
    }

    private var rowLayoutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                BubbleRowPreview()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)

            if inactiveTokens.isEmpty {
                Text("All tokens are in use")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(inactiveTokens, id: \.self) { token in
                            PaletteChip(token: token) { addToken(token) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if activeTokenItems.isEmpty {
                        Text("Tap a chip above to add tokens")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(height: 36)
                    } else {
                        ForEach(activeTokenItems) { item in
                            CanvasChip(
                                token: item.token,
                                isDragging: dragging == item.token
                            ) {
                                removeToken(item.token)
                            }
                            .onDrag {
                                dragging = item.token
                                return NSItemProvider(object: item.token.rawValue as NSString)
                            }
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: ChipDropDelegate(
                                    target: item.token,
                                    tokens: $settings.customLayout.tokens,
                                    dragging: $dragging
                                )
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                Text("Presets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Original") { settings.customLayout = .original }
                    .controlSize(.small)
                Button("Standard") { settings.customLayout = .standard }
                    .controlSize(.small)
                Button("Detailed") { settings.customLayout = .detailed }
                    .controlSize(.small)
                Spacer()
            }
        } header: {
            Text("Row content")
        } footer: {
            Text("Preview updates as you add, remove, or reorder tokens below.")
        }
    }

    private func addToken(_ token: BubbleToken) {
        withAnimation(.easeOut(duration: 0.18)) {
            if let idx = settings.customLayout.tokens.firstIndex(where: { $0.token == token }) {
                settings.customLayout.tokens[idx].isVisible = true
            } else {
                settings.customLayout.tokens.append(BubbleTokenItem(token: token, isVisible: true))
            }
        }
    }

    private func removeToken(_ token: BubbleToken) {
        withAnimation(.easeOut(duration: 0.18)) {
            if let idx = settings.customLayout.tokens.firstIndex(where: { $0.token == token }) {
                settings.customLayout.tokens[idx].isVisible = false
            }
        }
    }

    // MARK: - 4. Icons

    private var iconsSection: some View {
        Section {
            ForEach(AgentCatalog.all, id: \.kind) { agent in
                HStack(spacing: 10) {
                    ResolvedIconView(choice: settings.iconChoice(for: agent.kind), size: 20)
                    Text(agent.displayName)
                    Spacer()
                    Button("Change…") { iconPickerKind = agent.kind }
                        .controlSize(.small)
                }
            }
        } header: {
            Text("Agent icons")
        }
    }

    // MARK: - 5. Style

    private var styleSection: some View {
        Section {
            HStack {
                Text("Separator")
                Spacer()
                Picker("Separator", selection: $settings.separatorChar) {
                    Text("·").tag("·")
                    Text("→").tag("→")
                    Text("|").tag("|")
                    Text("space").tag(" ")
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }

            HStack {
                Text("State dot")
                Spacer()
                Picker("State dot", selection: $settings.dotStyle) {
                    ForEach(BubbleSettings.DotStyle.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }
        } header: {
            Text("Style")
        }
    }

    // MARK: - 6. Activity phrases

    private var activitySection: some View {
        Section {
            Picker("Vocabulary", selection: $settings.activityTheme) {
                ForEach(ActivityTheme.allCases, id: \.self) { theme in
                    Text("\(theme.emoji) \(theme.displayName)").tag(theme)
                }
            }
        } header: {
            Text("Activity messages")
        } footer: {
            Text("Whimsical phrases shown while agents work, e.g. \"Brewing…\" or \"Compiling…\".")
        }
    }
}

// MARK: - Palette Chip

private struct PaletteChip: View {
    let token: BubbleToken
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 5) {
                Image(systemName: token.chipSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(token.chipColor)
                Text(token.shortName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.75))
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(token.chipColor.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(token.chipColor.opacity(0.10)))
            .overlay(Capsule().strokeBorder(token.chipColor.opacity(0.30), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Canvas Chip

private struct CanvasChip: View {
    let token: BubbleToken
    let isDragging: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: token.chipSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(token.chipColor)
            Text(token.shortName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(token.chipColor.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(
                isDragging
                    ? token.chipColor.opacity(0.25)
                    : token.chipColor.opacity(0.13)
            )
        )
        .overlay(
            Capsule().strokeBorder(
                isDragging ? token.chipColor : token.chipColor.opacity(0.45),
                lineWidth: isDragging ? 1.5 : 1
            )
        )
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isDragging)
    }
}

// MARK: - Drag & Drop Delegate

private struct ChipDropDelegate: DropDelegate {
    let target: BubbleToken
    @Binding var tokens: [BubbleTokenItem]
    @Binding var dragging: BubbleToken?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        .init(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let source = dragging, source != target else { return }
        let visibleIndices = tokens.indices.filter { tokens[$0].isVisible }
        guard let fromPos = visibleIndices.first(where: { tokens[$0].token == source }),
              let toPos   = visibleIndices.first(where: { tokens[$0].token == target })
        else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            tokens.move(
                fromOffsets: IndexSet(integer: fromPos),
                toOffset: toPos > fromPos ? toPos + 1 : toPos
            )
        }
    }
}

// MARK: - Live Preview Row

/// Renders a mock agent row using the current BubbleSettings, so the user
/// can see exactly how the bubble will look as they edit the layout.
private struct BubbleRowPreview: View {
    @ObservedObject private var settings = BubbleSettings.shared

    private let mockTitle    = "Fix login bug"
    private let mockProject  = "agentpet"
    private let mockMessage  = "Editing SettingsModel.swift"
    private let mockElapsed  = "3m"
    private let mockModel    = "Sonnet 4.6"

    var body: some View {
        let visible = settings.effectiveLayout.tokens.filter { $0.isVisible }

        HStack(alignment: .center, spacing: 4) {
            ForEach(visible) { item in
                tokenView(for: item.token)
            }
            if visible.isEmpty {
                Text("(empty)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: AgentBubble.contentMaxWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(settings.opacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tokenView(for token: BubbleToken) -> some View {
        switch token {
        case .dot:
            Circle()
                .fill(Color(red: 0.22, green: 0.53, blue: 1.0))
                .frame(width: 6, height: 6)
        case .icon:
            ResolvedIconView(
                choice: settings.iconChoice(for: .claude),
                size: settings.fontSize.iconPt
            )
        case .title:
            Text(mockTitle)
                .font(.system(size: settings.fontSize.primaryPt, weight: .semibold))
                .lineLimit(1)
        case .project:
            Text(mockProject)
                .font(.system(size: settings.fontSize.primaryPt, weight: .medium))
                .lineLimit(1)
        case .separator:
            Text(settings.separatorChar)
                .font(.system(size: settings.fontSize.primaryPt))
                .foregroundStyle(.secondary)
        case .message:
            Text(mockMessage)
                .font(.system(size: settings.fontSize.primaryPt, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        case .stateLabel:
            Text("Working")
                .font(.system(size: settings.fontSize.secondaryPt))
                .foregroundStyle(.secondary)
        case .model:
            Text(mockModel)
                .font(.system(size: settings.fontSize.secondaryPt, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )
        case .elapsed:
            Text(mockElapsed)
                .font(.system(size: settings.fontSize.secondaryPt))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }
}

// MARK: - Icon Picker Popover

struct IconPickerPopover: View {
    let kind: AgentKind
    @ObservedObject private var settings = BubbleSettings.shared
    @State private var search = ""

    private var filteredSymbols: [String] {
        search.isEmpty
            ? AgentIcons.curatedSymbols
            : AgentIcons.curatedSymbols.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private var kindName: String {
        AgentCatalog.all.first { $0.kind == kind }?.displayName ?? kind.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Icon for \(kindName)")
                .font(.headline)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    brandSection
                    symbolSection
                }
                .padding(.vertical, 12)
            }

            Divider()

            HStack {
                Button("Reset to default") {
                    settings.resetIconChoice(for: kind)
                }
                .controlSize(.small)
                Spacer()
            }
            .padding()
        }
        .frame(width: 320, height: 380)
        .preferredColorScheme(.dark)
    }

    private var brandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Brand logos")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                spacing: 8
            ) {
                ForEach(AgentIcons.brandKinds, id: \.self) { logoKind in
                    iconCell(choice: .brandLogo(logoKind)) {
                        ResolvedIconView(choice: .brandLogo(logoKind), size: 22)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var symbolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SF Symbols")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 110)
            }
            .padding(.horizontal)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                spacing: 8
            ) {
                ForEach(filteredSymbols, id: \.self) { sym in
                    iconCell(choice: .sfSymbol(sym)) {
                        Image(systemName: sym)
                            .font(.system(size: 18))
                            .frame(width: 22, height: 22)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func iconCell<Content: View>(
        choice: IconChoice,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let selected = settings.iconChoice(for: kind) == choice
        Button {
            settings.setIconChoice(choice, for: kind)
        } label: {
            content()
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
