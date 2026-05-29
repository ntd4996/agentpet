import SwiftUI
import AppKit
import AgentPetCore

struct MenuBarContentView: View {
    @ObservedObject private var daemon = AppDaemon.shared
    @ObservedObject private var petWindow = PetWindowController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AgentPet")
                .font(.headline)

            if daemon.sessions.isEmpty {
                Text("No agents running")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(daemon.sessions) { session in
                    SessionRow(session: session)
                }
            }

            Divider()

            Toggle("Show pet", isOn: $petWindow.isVisible)

            Button("Choose Pet...") {
                SettingsWindowController.shared.show()
            }

            Divider()

            Button("Settings...") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",")

            Button("Quit AgentPet") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }
}

private struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.state.displayColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(projectName)
                    .font(.subheadline)
                Text(session.state.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            timeLabel
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Active states count up (how long running/waiting); finished states show a
    /// fixed finish time so they don't keep ticking.
    @ViewBuilder private var timeLabel: some View {
        switch session.state {
        case .done, .idle:
            Text(session.updatedAt.formatted(date: .omitted, time: .shortened))
        default:
            Text(session.updatedAt, style: .relative)
        }
    }

    private var projectName: String {
        guard let project = session.project, !project.isEmpty else { return session.id }
        return (project as NSString).lastPathComponent
    }
}

private extension AgentState {
    var displayColor: Color {
        switch self {
        case .waiting: return .orange
        case .working: return .blue
        case .done: return .green
        case .registered: return .gray
        case .idle: return .secondary
        }
    }
}
