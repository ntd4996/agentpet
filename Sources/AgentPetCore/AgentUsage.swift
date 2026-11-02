import Foundation

/// Per-agent token totals for the stats card and the Care tab ("By agent").
/// Pure so it can be tested without the usage store or any UI.
public struct AgentUsageTotal: Equatable, Sendable {
    public var agent: String
    public var today: Int
    public var month: Int
    public var sessions: Int

    public init(agent: String, today: Int, month: Int, sessions: Int) {
        self.agent = agent; self.today = today; self.month = month; self.sessions = sessions
    }
}

public enum AgentUsage {
    /// One (agent, day) usage record. `day` is `yyyy-MM-dd`.
    public struct Record: Sendable {
        public var agent: String
        public var day: String
        public var tokens: Int
        public var sessions: Int

        public init(agent: String, day: String, tokens: Int, sessions: Int) {
            self.agent = agent; self.day = day; self.tokens = tokens; self.sessions = sessions
        }
    }

    /// Tokens and finished sessions per agent for `today` and the calendar month
    /// it falls in, most tokens this month first (ties by name). An agent with
    /// nothing this month is left out.
    public static func totals(_ records: [Record], today: String) -> [AgentUsageTotal] {
        let month = String(today.prefix(7))
        var byAgent: [String: AgentUsageTotal] = [:]
        for r in records where r.day.hasPrefix(month) {
            var t = byAgent[r.agent] ?? AgentUsageTotal(agent: r.agent, today: 0, month: 0, sessions: 0)
            t.month += r.tokens
            t.sessions += r.sessions
            if r.day == today { t.today += r.tokens }
            byAgent[r.agent] = t
        }
        return byAgent.values
            .filter { $0.month > 0 || $0.sessions > 0 }
            .sorted { $0.month != $1.month ? $0.month > $1.month : $0.agent < $1.agent }
    }

    /// The id a session's usage is stored under: the kind for a known agent, the
    /// raw name for a custom (`.unknown`) one so two custom agents don't merge
    /// into one "Unknown" row.
    public static func key(kind: AgentKind, agentName: String?) -> String {
        guard kind == .unknown else { return kind.rawValue }
        let name = agentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? kind.rawValue : name
    }

    /// Display name for a stored agent id: the catalog label for a known kind,
    /// else the id with its first letter capitalised (custom agents).
    public static func label(for agent: String) -> String {
        if let kind = AgentKind(rawValue: agent), kind != .unknown, kind != .cli {
            return TickerFormatter.agentLabel(for: kind)
        }
        if agent == "cli" { return "Agent" }
        if agent == AgentKind.unknown.rawValue { return "Other" }
        return agent.prefix(1).uppercased() + agent.dropFirst()
    }

    /// What to show next to an agent: tokens when it has any, else its finished
    /// sessions, so an agent whose hook carries no token counts isn't "0 · 0".
    public static func isSessionOnly(_ total: AgentUsageTotal) -> Bool {
        total.month == 0 && total.sessions > 0
    }
}
