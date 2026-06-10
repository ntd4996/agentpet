import AppKit
import SwiftUI
import AgentPetCore

/// Timing for `AnimatedStatusText`'s erase/retype/ellipsis-cycle phases.
private let ERASE_INTERVAL: TimeInterval = 0.080
private let TYPE_INTERVAL: TimeInterval = 0.045
private let DOT_CYCLE_INTERVAL: TimeInterval = 0.400

/// The pet sprite alone (imported pack, reacting to mood). Shows a paw
/// placeholder if no pet is selected yet.
struct PetView: View {
    var size: CGFloat = 120
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject private var bindings = PetBindingsStore.shared

    var body: some View {
        content
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        if let id = pet.selectedPetID, let pack = imagePets.pack(id: id) {
            let clip = bindings.clipIndex(packId: pack.id, clipCount: pack.clipCount, mood: pet.mood)
            ImageSpriteView(frames: pack.clip(clip), mood: pet.mood, size: size)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.secondary)
        }
    }
}

/// Reports the natural size of the pet + bubble so the window can hug its content.
private struct PetContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}

/// The full floating window content: a chat bubble above the pet.
struct FloatingPetView: View {
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var bubbleSettings = BubbleSettings.shared
    @ObservedObject private var appLang = AppLanguage.shared

    var body: some View {
        VStack(spacing: 2) {
            if pet.showChat && pet.selectedPetID != nil {
                if bubbleSettings.multiAgentBubbleEnabled && !pet.activeAgentSessions.isEmpty {
                    AgentBubble(sessions: pet.activeAgentSessions)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .transition(AnyTransition.scale(scale: 0.6).combined(with: .opacity))
                } else if !pet.chatLine.isEmpty {
                    ChatBubble(text: pet.chatLine)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .transition(AnyTransition.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            PetView(size: pet.petPoint)
        }
        .fixedSize(horizontal: true, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PetContentSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PetContentSizeKey.self) { size in
            PetWindowController.shared.resizeToContent(size)
        }
        .animation(.easeInOut(duration: 0.22), value: pet.chatLine)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pet.activeAgentSessions.count)
        .animation(.easeInOut, value: pet.showChat)
        // Re-resolve bubble text when the app language changes at runtime.
        .environment(\.locale, appLang.locale)
    }
}

// MARK: - Agent Bubble (structured rows for working/waiting)

/// Sessions sharing an agent kind collapse into one row when enabled.
private struct GroupedSession: Identifiable {
    let session: AgentSession   // highest-priority session in the group
    let count: Int              // total sessions sharing this agent kind
    var id: String { "\(session.agentKind.rawValue)-\(session.id)" }
}

/// Speech bubble listing one row per (agentKind, project) group.
/// Applies filter/sort/cap from `BubbleSettings` before rendering.
/// `tailEdge` controls whether the pointer arrow points down (pet) or up (menu bar).
struct AgentBubble: View {
    let sessions: [AgentSession]
    var tailEdge: Edge = .bottom
    @ObservedObject private var settings = BubbleSettings.shared

    // attentionPriority is internal to AgentPetCore — use local rank
    private func rank(_ s: AgentState) -> Int {
        switch s { case .working: 4; case .waiting: 3; case .done: 2; case .registered: 1; case .idle: 0 }
    }

    private var groupedSessions: [GroupedSession] {
        // 1. Filter
        let filtered = sessions
            .filter { !settings.hiddenKinds.contains($0.agentKind) }
            .filter { settings.minStateFilter.includes($0.state) }

        // 2. Sort (grouped mode always sorts by kind first)
        var sorted = filtered
        let sortByKind = settings.sessionGrouping == .byKind || settings.groupByKind
        if sortByKind {
            sorted.sort {
                if $0.agentKind.rawValue != $1.agentKind.rawValue {
                    return $0.agentKind.rawValue < $1.agentKind.rawValue
                }
                if rank($0.state) != rank($1.state) { return rank($0.state) > rank($1.state) }
                return $0.updatedAt > $1.updatedAt
            }
        } else {
            sorted.sort {
                if rank($0.state) != rank($1.state) { return rank($0.state) > rank($1.state) }
                return $0.updatedAt > $1.updatedAt
            }
        }

        // 3. Collapse by agent kind when grouped (highest-priority session per kind).
        var result: [GroupedSession]
        if settings.sessionGrouping == .byKind {
            var seen: [AgentKind: Int] = [:]
            result = []
            for s in sorted {
                if let idx = seen[s.agentKind] {
                    result[idx] = GroupedSession(session: result[idx].session, count: result[idx].count + 1)
                } else {
                    seen[s.agentKind] = result.count
                    result.append(GroupedSession(session: s, count: 1))
                }
            }
        } else {
            result = sorted.map { GroupedSession(session: $0, count: 1) }
        }

        // 4. Cap to maxSessions (list/compact); carousel shows all groups.
        if settings.displayMode == .carousel {
            return result
        }
        return Array(result.prefix(settings.maxSessions))
    }

    private var totalSessionCount: Int {
        groupedSessions.reduce(0) { $0 + $1.count }
    }

    private var isPetChat: Bool { tailEdge == .bottom }
    // Capsule for single visible row; rounded rect when taller or carousel dots are shown.
    private var useCapsule: Bool {
        isPetChat && groupedSessions.count <= 1 && settings.displayMode != .compact
    }

    var body: some View {
        let fill = bubbleFill
        let stroke = borderColor

        VStack(spacing: 0) {
            if tailEdge == .top {
                Triangle()
                    .fill(fill)
                    .frame(width: 12, height: 7)
                    .scaleEffect(x: 1, y: -1)
            }
            VStack(alignment: .leading, spacing: isPetChat ? 4 : 5) {
                bubbleContent
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isPetChat ? 7 : 9)
            .background {
                if useCapsule {
                    Capsule().fill(fill)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill)
                }
            }
            .overlay {
                if useCapsule {
                    Capsule().strokeBorder(stroke, lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(stroke, lineWidth: 1)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            if tailEdge == .bottom {
                Triangle()
                    .fill(fill)
                    .frame(width: 12, height: 7)
            }
        }
        .fixedSize(horizontal: isPetChat, vertical: true)
        .frame(maxWidth: 420, alignment: .leading)
    }

    /// Inner content width cap (bubble max minus horizontal padding).
    static let contentMaxWidth: CGFloat = 396
    /// Pet chat bubble hugs content; still capped for very long lines.
    static let petContentMaxWidth: CGFloat = 320

    private var bubbleFill: Color {
        switch settings.theme {
        case .light:  return Color.white.opacity(settings.opacity)
        case .dark:   return Color(nsColor: .windowBackgroundColor).opacity(settings.opacity)
        case .system: return Color(nsColor: .textBackgroundColor).opacity(settings.opacity)
        }
    }

    private var borderColor: Color {
        switch settings.theme {
        case .light:  return .black.opacity(0.06)
        case .dark:   return .white.opacity(0.12)
        case .system: return Color.primary.opacity(0.08)
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch settings.displayMode {
        case .list:
            ForEach(groupedSessions) { group in
                AgentRow(session: group.session, count: group.count, chatStyle: isPetChat)
            }
        case .carousel:
            BubbleCarousel(groups: groupedSessions, chatStyle: isPetChat)
        case .compact:
            BubbleCompactLayout(
                groups: groupedSessions,
                totalCount: totalSessionCount,
                chatStyle: isPetChat,
                textColor: textColor
            )
        }
    }

    private func textColor(_ opacity: Double) -> Color {
        switch settings.theme {
        case .light:  return .black.opacity(opacity)
        case .dark:   return .white.opacity(opacity)
        case .system: return Color.primary.opacity(opacity)
        }
    }
}

// MARK: - Carousel (one agent at a time)

private struct BubbleCarousel: View {
    let groups: [GroupedSession]
    var chatStyle: Bool = false
    @ObservedObject private var settings = BubbleSettings.shared
    @State private var index = 0
    @State private var timer: Timer?
    @State private var dragOffset: CGFloat = 0

    private static let interval: TimeInterval = 3.0
    private static let swipeThreshold: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: chatStyle ? 4 : 5) {
            Group {
                if let group = groups[safe: index] {
                    AgentRow(session: group.session, count: group.count, chatStyle: chatStyle)
                        .id(group.id)
                        .transition(.opacity)
                }
            }
            .offset(x: dragOffset)
            .animation(.easeInOut(duration: 0.35), value: index)
            .clipped()

            if groups.count > 1 {
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    ForEach(0..<groups.count, id: \.self) { i in
                        Circle()
                            .fill(i == index ? dotActive : dotInactive)
                            .frame(width: 4, height: 4)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .contentShape(Rectangle())
        .background {
            if groups.count > 1 {
                HorizontalSwipeReader(
                    onSwipeLeft: { step(by: 1) },
                    onSwipeRight: { step(by: -1) }
                )
            }
        }
        .highPriorityGesture(swipeGesture)
        .onAppear { syncTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: groups.map(\.id)) { _ in
            index = 0
            dragOffset = 0
            syncTimer()
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard groups.count > 1 else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard groups.count > 1 else {
                    dragOffset = 0
                    return
                }
                let tx = value.translation.width
                if tx <= -Self.swipeThreshold {
                    step(by: 1)
                } else if tx >= Self.swipeThreshold {
                    step(by: -1)
                }
                withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
            }
    }

    private func dotColor(_ opacity: Double) -> Color {
        switch settings.theme {
        case .light:  return .black.opacity(opacity)
        case .dark:   return .white.opacity(opacity)
        case .system: return Color.primary.opacity(opacity)
        }
    }

    private var dotActive: Color { dotColor(0.7) }
    private var dotInactive: Color { dotColor(0.25) }

    private func step(by delta: Int) {
        guard groups.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            index = (index + delta + groups.count) % groups.count
        }
        syncTimer()
    }

    private func syncTimer() {
        stopTimer()
        guard groups.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in step(by: 1) }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Trackpad horizontal swipe (scroll wheel)

/// Captures two-finger horizontal trackpad swipes inside the carousel bubble.
private struct HorizontalSwipeReader: NSViewRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeNSView(context: Context) -> HorizontalSwipeNSView {
        let view = HorizontalSwipeNSView()
        view.onSwipeLeft = onSwipeLeft
        view.onSwipeRight = onSwipeRight
        return view
    }

    func updateNSView(_ nsView: HorizontalSwipeNSView, context: Context) {
        nsView.onSwipeLeft = onSwipeLeft
        nsView.onSwipeRight = onSwipeRight
    }
}

private final class HorizontalSwipeNSView: NSView {
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    private var accumulatedX: CGFloat = 0
    private var lastFireAt: TimeInterval = 0

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) else { return }

        accumulatedX += event.scrollingDeltaX
        let ended = event.phase == .ended || event.phase == .cancelled
            || event.momentumPhase == .ended || event.momentumPhase == .cancelled
        guard ended else { return }

        let threshold: CGFloat = 28
        if accumulatedX <= -threshold {
            fireSwipe(left: true)
        } else if accumulatedX >= threshold {
            fireSwipe(left: false)
        }
        accumulatedX = 0
    }

    private func fireSwipe(left: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFireAt > 0.35 else { return }
        lastFireAt = now
        Task { @MainActor in
            if left { onSwipeLeft?() } else { onSwipeRight?() }
        }
    }
}

// MARK: - Compact (summary header + 2 rows + fold)

private struct BubbleCompactLayout: View {
    let groups: [GroupedSession]
    let totalCount: Int
    var chatStyle: Bool = false
    let textColor: (Double) -> Color
    @ObservedObject private var settings = BubbleSettings.shared
    @State private var expanded = false

    private let visibleRows = 2

    var body: some View {
        VStack(alignment: .leading, spacing: chatStyle ? 4 : 5) {
            Text(summaryLabel)
                .font(.system(size: settings.fontSize.secondaryPt, weight: .semibold))
                .foregroundStyle(textColor(0.45))

            ForEach(visibleGroups) { group in
                AgentRow(session: group.session, count: group.count, chatStyle: chatStyle)
            }

            if hiddenCount > 0 {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                    Text(expanded ? "Show less" : "+\(hiddenCount) more")
                        .font(.system(size: settings.fontSize.secondaryPt, weight: .medium))
                        .foregroundStyle(textColor(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: groups.map(\.id)) { _ in expanded = false }
    }

    private var summaryLabel: String {
        let n = totalCount
        let kinds = groups.count
        if kinds <= 1 {
            return "\(n) agent\(n == 1 ? "" : "s")"
        }
        return "\(n) agent\(n == 1 ? "" : "s") · \(kinds) kind\(kinds == 1 ? "" : "s")"
    }

    private var visibleGroups: [GroupedSession] {
        expanded ? groups : Array(groups.prefix(visibleRows))
    }

    private var hiddenCount: Int {
        max(0, groups.count - visibleRows)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Animated status text

/// Renders a status message that erases-then-retypes on change, then settles
/// into either an ellipsis cycle (`Brewing…`) or a shimmer sweep (plain text).
///
/// Erase: drop the trailing word every `ERASE_INTERVAL` until empty.
/// Type: append one char of the new message every `TYPE_INTERVAL`.
/// Stable: ellipsis-suffixed messages cycle `.`/`..`/`...`; others shimmer.
private struct AnimatedStatusText: View {
    let message: String
    let font: Font
    let color: Color
    /// When false, render the message plainly with no erase/retype, ellipsis
    /// cycle, or shimmer — used for terminal states like "Shipped!" where the
    /// dot alone should carry the motion.
    var animated: Bool = true

    private static let ellipsisFrames = [".", "..", "..."]

    @State private var displayed = ""
    /// Widest of the outgoing/incoming text — reserved (invisibly) so the
    /// erase/retype animation never shrinks or grows the bubble mid-flight.
    @State private var reserveText = ""
    @State private var baseText = ""
    @State private var hasEllipsis = false
    @State private var isStable = false
    @State private var dotFrame = 0

    @State private var typeTarget: [Character] = []
    @State private var typeIndex = 0

    @State private var eraseTimer: Timer?
    @State private var typeTimer: Timer?
    @State private var dotTimer: Timer?

    var body: some View {
        if !animated {
            Text(message)
                .font(font)
                .foregroundStyle(color)
        } else {
            animatedBody
        }
    }

    private var animatedBody: some View {
        ZStack(alignment: .leading) {
            if !isStable {
                // Reserved-width ghost: holds the bubble at the wider of the
                // outgoing/incoming text for the whole erase→type transition.
                Text(reserveText).font(font).opacity(0)
            }
            content
        }
        .onAppear { restart(to: message) }
        .onChange(of: message) { restart(to: $0) }
        .onDisappear { cancelAll() }
    }

    @ViewBuilder
    private var content: some View {
        if isStable && hasEllipsis {
            ZStack(alignment: .leading) {
                // Reserves width for the longest frame ("...") so the
                // cycling suffix never resizes the bubble.
                Text(baseText + "...").font(font).opacity(0)
                Text(baseText + Self.ellipsisFrames[dotFrame])
                    .font(font)
                    .foregroundStyle(color)
            }
        } else if isStable {
            ShimmeringText(text: displayed, font: font, color: color)
        } else {
            Text(displayed)
                .font(font)
                .foregroundStyle(color)
        }
    }

    // MARK: Phase transitions

    private func restart(to newMessage: String) {
        reserveText = newMessage.count >= displayed.count ? newMessage : displayed
        cancelAll()
        isStable = false
        if displayed.isEmpty {
            startTyping(newMessage)
        } else {
            startErasing(to: newMessage)
        }
    }

    private func startErasing(to newMessage: String) {
        eraseTimer = Timer.scheduledTimer(withTimeInterval: ERASE_INTERVAL, repeats: true) { _ in
            Task { @MainActor in eraseStep(to: newMessage) }
        }
    }

    private func eraseStep(to newMessage: String) {
        var words = displayed.split(separator: " ", omittingEmptySubsequences: false)
        words.removeLast()
        displayed = words.joined(separator: " ")
        if displayed.isEmpty {
            eraseTimer?.invalidate()
            eraseTimer = nil
            startTyping(newMessage)
        }
    }

    private func startTyping(_ newMessage: String) {
        let stripped = Self.stripEllipsis(newMessage)
        baseText = stripped.text
        hasEllipsis = stripped.hasEllipsis
        typeTarget = Array(hasEllipsis ? stripped.text : newMessage)
        typeIndex = 0
        displayed = ""
        typeTimer = Timer.scheduledTimer(withTimeInterval: TYPE_INTERVAL, repeats: true) { _ in
            Task { @MainActor in typeStep() }
        }
    }

    private func typeStep() {
        guard typeIndex < typeTarget.count else {
            typeTimer?.invalidate()
            typeTimer = nil
            enterStablePhase()
            return
        }
        displayed.append(typeTarget[typeIndex])
        typeIndex += 1
    }

    private func enterStablePhase() {
        isStable = true
        guard hasEllipsis else { return }
        dotFrame = 0
        dotTimer = Timer.scheduledTimer(withTimeInterval: DOT_CYCLE_INTERVAL, repeats: true) { _ in
            Task { @MainActor in
                dotFrame = (dotFrame + 1) % Self.ellipsisFrames.count
            }
        }
    }

    private func cancelAll() {
        eraseTimer?.invalidate(); eraseTimer = nil
        typeTimer?.invalidate(); typeTimer = nil
        dotTimer?.invalidate(); dotTimer = nil
    }

    private static func stripEllipsis(_ text: String) -> (text: String, hasEllipsis: Bool) {
        if text.hasSuffix("…") {
            return (String(text.dropLast()).trimmingCharacters(in: .whitespaces), true)
        }
        if text.hasSuffix("...") {
            return (String(text.dropLast(3)).trimmingCharacters(in: .whitespaces), true)
        }
        return (text, false)
    }
}

/// Bright band sweeping left-to-right over text via gradient mask, repeating
/// every 2.5s. Pure SwiftUI animation — no timers — mirrors a CSS
/// `background-clip: text` shimmer.
private struct ShimmeringText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var sweep = false

    var body: some View {
        let label = Text(text).font(font)
        ZStack {
            label.foregroundStyle(color.opacity(0.55))
            label
                .foregroundStyle(color)
                .mask(
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        LinearGradient(
                            colors: [.clear, .white, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: w * 0.5)
                        .offset(x: sweep ? w : -w * 0.5)
                    }
                )
        }
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
    }
}

/// One row per agent session. Iterates `BubbleSettings.effectiveLayout` tokens
/// in order on a single line; project/title shrink before the message does.
private struct AgentRow: View {
    let session: AgentSession
    var count: Int = 1
    var chatStyle: Bool = false
    @ObservedObject private var settings = BubbleSettings.shared
    @ObservedObject private var bubbleMsgs = BubbleMessages.shared

    private var primaryPt: CGFloat { settings.fontSize.primaryPt }
    private var secondaryPt: CGFloat { settings.fontSize.secondaryPt }
    private var iconPt: CGFloat { settings.fontSize.iconPt }
    private var rowMaxWidth: CGFloat {
        chatStyle ? AgentBubble.petContentMaxWidth : AgentBubble.contentMaxWidth
    }

    private var isWaiting: Bool { session.state == .waiting }

    /// Same orange used for the waiting state dot — applied to the message
    /// text too, so "waiting for input" reads as urgent at a glance.
    private static let waitingColor = Color(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0)

    var body: some View {
        let visible = settings.effectiveLayout.tokens.filter { $0.isVisible && tokenHasValue($0.token) }

        HStack(alignment: .center, spacing: 4) {
            if visible.contains(where: { $0.token == .dot }) {
                tokenView(for: .dot)
            }
            HStack(alignment: .center, spacing: 4) {
                ForEach(visible.filter { $0.token != .dot }) { item in
                    tokenView(for: item.token)
                }
                if count > 1 {
                    Text("×\(count)")
                        .font(.system(size: settings.fontSize.secondaryPt, weight: .semibold))
                        .foregroundStyle(textColor(0.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(textColor(0.08))
                        )
                }
            }
        }
        .frame(maxWidth: rowMaxWidth, alignment: .leading)
    }

    @ViewBuilder
    private func tokenView(for token: BubbleToken) -> some View {
        switch token {
        case .dot:
            StateDot(color: stateDotColor, spins: dotSpins, style: settings.dotStyle)
        case .icon:
            ResolvedIconView(
                choice: settings.iconChoice(for: session.agentKind),
                size: iconPt
            )
        case .title:
            if let title = session.title {
                Text(title)
                    .font(.system(size: primaryPt, weight: .semibold))
                    .foregroundStyle(textColor(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }
        case .project:
            Text(projectName)
                .font(.system(size: primaryPt, weight: .medium))
                .foregroundStyle(textColor(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
        case .separator:
            Text(settings.separatorChar)
                .font(.system(size: primaryPt, weight: .regular))
                .foregroundStyle(textColor(0.35))
        case .message:
            AnimatedStatusText(
                message: messageText,
                font: .system(size: primaryPt, weight: isWaiting ? .semibold : .medium),
                color: isWaiting ? Self.waitingColor : textColor(0.82),
                animated: session.state != .done
            )
            .modifier(WaitingTextFlash(active: isWaiting))
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(1)
            .fixedSize(horizontal: false, vertical: true)
        case .stateLabel:
            Text(session.state.rawValue.capitalized)
                .font(.system(size: secondaryPt, weight: .regular))
                .foregroundStyle(textColor(0.55))
        case .model:
            if let model = session.model {
                Text(model)
                    .font(.system(size: secondaryPt, weight: .regular))
                    .foregroundStyle(textColor(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        case .elapsed:
            // Tick every second so the elapsed time counts up live instead of
            // freezing at the value sampled when the row was last re-rendered.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsedString(since: session.stateSince, now: context.date))
                    .font(.system(size: secondaryPt, weight: .regular))
                    .foregroundStyle(textColor(0.45))
                    .monospacedDigit()
            }
        }
    }

    private func tokenHasValue(_ token: BubbleToken) -> Bool {
        if token == .title { return session.title != nil }
        if token == .model { return session.model != nil }
        return true
    }

    private func textColor(_ opacity: Double) -> Color {
        switch settings.theme {
        case .light:  return .black.opacity(opacity)
        case .dark:   return .white.opacity(opacity)
        case .system: return Color.primary.opacity(opacity)
        }
    }

    private var projectName: String {
        session.project.map { ($0 as NSString).lastPathComponent } ?? session.id
    }

    private var messageText: String {
        let mood = moodFor(session.state)
        // Working shows the live activity from the hook ("Editing X…"); a custom
        // working line, if set, still overrides it.
        if mood == .working {
            if bubbleMsgs.source == .custom {
                let custom = bubbleMsgs.line(for: session.agentKind, mood: .working, seed: session.id)
                if !custom.isEmpty { return custom }
            }
            let m = session.message?.trimmingCharacters(in: .whitespaces) ?? ""
            if !m.isEmpty { return m }
            return ActivityFormatter.stateMessage(for: session.state)
                ?? session.state.rawValue.capitalized
        }
        // done / waiting / idle: always use the bubble message (custom when set,
        // otherwise the localized built-in default). The hook's own message is
        // unlocalized (a separate process), so we never fall back to it here.
        let line = bubbleMsgs.line(for: session.agentKind, mood: mood, seed: session.id)
        if !line.isEmpty { return line }
        return ActivityFormatter.stateMessage(for: session.state)
            ?? session.state.rawValue.capitalized
    }

    private func moodFor(_ state: AgentState) -> PetMood {
        switch state {
        case .working, .registered: return .working
        case .waiting:              return .waiting
        case .done:                 return .done
        case .idle:                 return .idle
        }
    }

    private var dotSpins: Bool {
        switch session.state {
        case .working, .waiting, .registered, .done: return true
        case .idle:                                  return false
        }
    }

    private var stateDotColor: Color {
        switch session.state {
        case .working, .registered: return Color(red: 0x3B / 255.0, green: 0x82 / 255.0, blue: 0xF6 / 255.0)
        case .waiting:              return Color(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0)
        case .done:                 return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .idle:                 return Color(red: 0x6B / 255.0, green: 0x72 / 255.0, blue: 0x80 / 255.0)
        }
    }

    private func elapsedString(since date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60  { return "\(s)s" }
        let m = s / 60
        if m < 60  { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }
}

// MARK: - Simple Chat Bubble (celebrate / done / waiting fallback)

/// A plain speech bubble with a downward tail, used for celebrate/done lines.
/// Theme-aware (light/dark/system); reused by the Settings live preview.
struct ChatBubble: View {
    let text: String
    @ObservedObject private var settings = BubbleSettings.shared

    private var fill: Color {
        switch settings.theme {
        case .light:  return Color.white.opacity(settings.opacity)
        case .dark:   return Color(nsColor: .windowBackgroundColor).opacity(settings.opacity)
        case .system: return Color(nsColor: .textBackgroundColor).opacity(settings.opacity)
        }
    }

    private var textColor: Color {
        switch settings.theme {
        case .light:  return .black.opacity(0.85)
        case .dark:   return .white.opacity(0.85)
        case .system: return Color.primary.opacity(0.85)
        }
    }

    private var borderColor: Color {
        switch settings.theme {
        case .light:  return .black.opacity(0.06)
        case .dark:   return .white.opacity(0.12)
        case .system: return Color.primary.opacity(0.08)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: settings.fontSize.primaryPt, weight: .medium))
                .foregroundStyle(textColor)
                .contentTransition(.opacity)   // cross-fade text changes instead of a hard swap (no flicker)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                // Flatten to one layer so the shadow traces the capsule's
                // rounded silhouette instead of its rectangular bounding box
                // (SwiftUI draws boxy shadows on composed views otherwise).
                .compositingGroup()
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            Triangle()
                .fill(fill)
                .frame(width: 12, height: 7)
        }
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: 420)
    }
}

// MARK: - State dot

/// State dot — either a flat color-coded circle, or a Claude-style asterisk
/// that spins smoothly while the agent is active (continuous rotation, not
/// frame substitution, which reads as flashing since glyph shapes differ in
/// weight/size). Idle/done sit still.
private struct StateDot: View {
    let color: Color
    let spins: Bool
    let style: BubbleSettings.DotStyle

    private static let frames = ["✶", "✳", "✢", "✻", "✽", "✺"]
    private static let frameInterval: TimeInterval = 0.15

    var body: some View {
        Group {
            switch style {
            case .plain:
                if spins {
                    BloomingDot(color: color)
                } else {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
            case .claude:
                if spins {
                    TimelineView(.periodic(from: .now, by: Self.frameInterval)) { context in
                        let i = Int(context.date.timeIntervalSinceReferenceDate / Self.frameInterval) % Self.frames.count
                        glyph(Self.frames[i])
                    }
                } else {
                    glyph("✻")
                }
            }
        }
        // The active↔idle/done switch swaps to a wholly different view
        // (spinner ↔ static glyph/circle); never let an ambient animation
        // cross-fade that swap into a flash.
        .animation(nil, value: spins)
        .frame(width: 14, height: 14)
    }

    private func glyph(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
    }
}

/// Original plain-dot pulse: glow blooms outward from the dot and fades,
/// repeating every 1.5s — the box-shadow-style animation for `.plain`.
private struct BloomingDot: View {
    let color: Color
    @State private var blooming = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .blur(radius: 3)
                .scaleEffect(blooming ? 2.4 : 1)
                .opacity(blooming ? 0 : 0.55)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                blooming = true
            }
        }
    }
}

// MARK: - Waiting text flash

/// Gently pulses row text opacity when waiting for input (no strikethrough).
private struct WaitingTextFlash: ViewModifier {
    let active: Bool
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (dimmed ? 0.65 : 1.0) : 1.0)
            .onAppear { sync() }
            .onChange(of: active) { _ in sync() }
    }

    private func sync() {
        if active {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        } else {
            dimmed = false
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
