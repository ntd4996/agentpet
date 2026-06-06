import SwiftUI
import AppKit
import AgentPetCore

/// Rich menu bar popover: a blurred dark card with an arrow pointing at the
/// status item, a live agent list, and a footer bar.
struct MenuContentView: View {
    @ObservedObject private var daemon = AppDaemon.shared
    @ObservedObject private var petWindow = PetWindowController.shared
    @ObservedObject private var statusBar = StatusBarController.shared
    @ObservedObject private var pet = PetController.shared
    var dismiss: () -> Void

    /// Show agents that are doing something or just finished. Idle and merely
    /// `registered` (open but not working) sessions are hidden, so an idle
    /// terminal doesn't sit in the list; they reappear the moment they work.
    private var agents: [AgentSession] {
        daemon.sessions.filter { $0.state != .idle && $0.state != .registered }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            agentSection
            divider
            controls
            divider
            footer
        }
        .frame(width: 300)
        .background(.regularMaterial)
        .environment(\.colorScheme, .dark)
        .noFocusRing()
    }

    private var divider: some View { Divider().overlay(Color.white.opacity(0.08)) }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "pawprint.fill").font(.system(size: 13)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text("AgentPet").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(14)
    }

    private var subtitle: String {
        let total = agents.count
        if total == 0 { return "No agents running" }
        let running = agents.filter { $0.state == .working }.count
        let label = "\(total) agent\(total == 1 ? "" : "s")"
        return running > 0 ? "\(label) · \(running) running" : label
    }

    // MARK: Agents

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("Agents")
                Spacer()
                if !agents.isEmpty {
                    Button("Clear all") { daemon.clearSessions() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.trailing, 14).padding(.top, 12).padding(.bottom, 6)
                }
            }
            if agents.isEmpty {
                Text("Nothing running right now.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 14).padding(.bottom, 12)
            } else {
                ForEach(agents) { session in
                    AgentRow(session: session, onClear: { daemon.removeSession(session.id) })
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(1.4)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            controlRow(icon: "pawprint", label: "Show pet", isOn: $petWindow.isVisible)
            controlRow(icon: "number", label: "Show count on menu bar", isOn: $statusBar.showCount)
            controlRow(icon: "bubble.left", label: "Show chat on menu bar", isOn: $statusBar.showChatOnMenuBar)
            controlRow(icon: "list.bullet.rectangle", label: "Show bubble on menu bar", isOn: $statusBar.showBubbleOnMenuBar)
            sizeRow
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .foregroundStyle(.white.opacity(0.8)).frame(width: 16)
            Text("Pet size").font(.system(size: 13)).foregroundStyle(.white)
            Slider(value: $pet.petPoint, in: PetController.minPoint...PetController.maxPoint)
                .controlSize(.mini)
                .tint(Color.systemAccent)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func controlRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.white.opacity(0.8)).frame(width: 16)
            Text(label).font(.system(size: 13)).foregroundStyle(.white)
            Spacer()
            ColorSwitch(isOn: isOn)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Footer

    @ObservedObject private var updater = UpdaterController.shared

    private var footer: some View {
        HStack {
            FooterButton(icon: "gearshape", label: "Settings") {
                // Use closeAndThen so the window appears only after the popover
                // animation fully completes — no race, no overlap.
                StatusBarController.shared.closeAndThen {
                    SettingsWindowController.shared.show()
                }
            }
            FooterButton(
                icon: "arrow.triangle.2.circlepath",
                label: "Updates",
                badge: updater.updatePending
            ) {
                StatusBarController.shared.closeAndThen {
                    UpdaterController.shared.checkForUpdates()
                }
            }
            Spacer()
            FooterButton(icon: "power", label: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - Menu bar hanging bubble

/// Thin wrapper so the agent bubble shown below the menu bar icon
/// auto-refreshes via @ObservedObject without re-creating the NSPanel.
struct MenuBarBubbleView: View {
    @ObservedObject private var pet = PetController.shared

    var body: some View {
        AgentBubble(sessions: pet.activeAgentSessions, tailEdge: .top)
            .environment(\.colorScheme, .dark)
    }
}

private struct FooterButton: View {
    let icon: String
    let label: String
    var badge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                    if badge {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(label)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct AgentRow: View {
    let session: AgentSession
    var onClear: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(project).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if hovering {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timeString(now: context.date))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var project: String {
        session.project.map { ($0 as NSString).lastPathComponent } ?? session.id
    }

    /// The agent's context (waiting reason / running tool) when known, else its state.
    private var subtitle: String {
        if let message = session.message, !message.isEmpty { return message }
        return session.state.rawValue.capitalized
    }

    private var dotColor: Color {
        switch session.state {
        case .working, .registered: return .blue
        case .waiting: return .orange
        case .done: return .green
        case .idle: return .gray
        }
    }

    private func timeString(now: Date) -> String {
        switch session.state {
        case .done, .idle:
            return session.updatedAt.formatted(date: .omitted, time: .shortened)
        default:
            let s = max(0, Int(now.timeIntervalSince(session.stateSince)))
            return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
        }
    }
}
