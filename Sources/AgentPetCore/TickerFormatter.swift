import Foundation

/// Pure formatting and sorting logic for the desktop-pet ticker.
/// Lives in AgentPetCore so it can be unit-tested without AppKit.
public enum TickerFormatter {

    /// Short display label for an agent kind.
    public static func agentLabel(for kind: AgentKind) -> String {
        switch kind {
        case .claude:    return "Claude"
        case .cursor:    return "Cursor"
        case .codex:     return "Codex"
        case .gemini:    return "Gemini"
        case .opencode:  return "Opencode"
        case .windsurf:  return "Windsurf"
        case .antigravity: return "Antigravity"
        case .copilot:   return "Copilot"
        case .kiroCLI:   return "Kiro"
        case .droid:     return "Droid"
        case .pi:        return "Pi"
        case .cli:       return "Agent"
        case .unknown:   return "Agent"
        }
    }

    /// One ticker line for a single session.
    /// Format: `<AgentLabel> [<project>] → <message>`
    public static func line(for session: AgentSession) -> String {
        let label   = agentLabel(for: session.agentKind)
        let project = session.project.map { ($0 as NSString).lastPathComponent } ?? session.id
        let msg: String
        if let m = session.message, !m.trimmingCharacters(in: .whitespaces).isEmpty {
            msg = m
        } else {
            msg = session.state.rawValue.capitalized
        }
        return "\(label) [\(project)] → \(msg)"
    }

    /// Sort order for the ticker: waiting first, then working (most-recently
    /// updated first), then done. Idle and registered sessions are excluded
    /// before calling this — the caller is responsible for filtering.
    public static func sorted(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.sorted { a, b in
            let pa = priority(a.state)
            let pb = priority(b.state)
            if pa != pb { return pa < pb }
            return a.updatedAt > b.updatedAt
        }
    }

    // MARK: - Private

    private static func priority(_ state: AgentState) -> Int {
        switch state {
        case .waiting:    return 0
        case .working:    return 1
        case .done:       return 2
        case .idle:       return 3
        case .registered: return 4
        }
    }
}
