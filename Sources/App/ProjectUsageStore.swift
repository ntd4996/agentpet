import Foundation
import AgentPetCore

/// Logs per-project, per-agent token usage by day so the web dashboard can show
/// where your tokens go. Persisted locally; pushed to the profile by
/// CareSyncController when the app is linked. Fully offline until you connect.
@MainActor
final class ProjectUsageStore: ObservableObject {
    static let shared = ProjectUsageStore()

    struct Row: Codable, Equatable {
        var projectId: String
        var projectName: String
        var agent: String
        var day: String
        var tokens: Int
        var sessions: Int
        var costUSD: Double = 0

        init(projectId: String, projectName: String, agent: String, day: String, tokens: Int, sessions: Int, costUSD: Double = 0) {
            self.projectId = projectId
            self.projectName = projectName
            self.agent = agent
            self.day = day
            self.tokens = tokens
            self.sessions = sessions
            self.costUSD = costUSD
        }

        private enum CodingKeys: String, CodingKey {
            case projectId, projectName, agent, day, tokens, sessions, costUSD
        }

        /// Custom decode so rows persisted before costUSD existed still load, defaulting to 0.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            projectId = try c.decode(String.self, forKey: .projectId)
            projectName = try c.decode(String.self, forKey: .projectName)
            agent = try c.decode(String.self, forKey: .agent)
            day = try c.decode(String.self, forKey: .day)
            tokens = try c.decode(Int.self, forKey: .tokens)
            sessions = try c.decode(Int.self, forKey: .sessions)
            costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
        }
    }

    private static let storageKey = "agentpet.projectUsage"
    private static let dirtyKey = "agentpet.projectUsage.dirty"
    /// Keyed by "projectId|agent|day".
    private var rows: [String: Row]
    private var dirty: Set<String>

    @Published private(set) var todayCostUSD: Double = 0
    @Published private(set) var monthlyCostUSD: Double = 0

    init() {
        rows = (UserDefaults.standard.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: Row].self, from: $0) }) ?? [:]
        dirty = Set((UserDefaults.standard.array(forKey: Self.dirtyKey) as? [String]) ?? [])
        pruneOld()
        recomputeCostTotals()
    }

    // MARK: - Recording

    func recordTokens(_ tokens: Int, project: String?, agent: String, costUSD: Double = 0) {
        record(project: project, agent: agent, tokens: tokens, sessions: 0, costUSD: costUSD)
    }
    func recordSession(project: String?, agent: String) {
        record(project: project, agent: agent, tokens: 0, sessions: 1)
    }

    private func record(project: String?, agent: String, tokens: Int, sessions: Int, costUSD: Double = 0) {
        guard let project, !project.isEmpty, !agent.isEmpty, tokens > 0 || sessions > 0 else { return }
        let (pid, pname) = Self.projectIdentity(project)
        let day = Self.today()
        let key = "\(pid)|\(agent)|\(day)"
        var r = rows[key] ?? Row(projectId: pid, projectName: pname, agent: agent, day: day, tokens: 0, sessions: 0)
        r.tokens += tokens
        r.sessions += sessions
        r.costUSD += costUSD
        r.projectName = pname
        rows[key] = r
        dirty.insert(key)
        persist()
        recomputeCostTotals()
        CareSyncController.shared.scheduleUsageSync()
    }

    // MARK: - Sync support

    /// Projects seen so far as (id, folder name), most recently used first. Only
    /// those used in the last `withinDays` days, plus any id in `alwaysInclude`
    /// (projects that already have a name), so the Settings list stays short.
    func knownProjects(withinDays: Int = 7, alwaysInclude: Set<String> = []) -> [(id: String, folder: String)] {
        let cutoff = Self.dayString(daysAgo: withinDays)
        var latest: [String: (day: String, folder: String)] = [:]
        for r in rows.values where latest[r.projectId].map({ r.day > $0.day }) ?? true {
            latest[r.projectId] = (r.day, r.projectName)
        }
        return latest
            .filter { $0.value.day >= cutoff || alwaysInclude.contains($0.key) }
            .sorted { $0.value.day != $1.value.day ? $0.value.day > $1.value.day : $0.value.folder < $1.value.folder }
            .map { (id: $0.key, folder: $0.value.folder) }
    }

    /// Tokens and sessions per agent for today and this calendar month.
    func byAgent() -> [AgentUsageTotal] {
        AgentUsage.totals(
            rows.values.map { AgentUsage.Record(agent: $0.agent, day: $0.day, tokens: $0.tokens, sessions: $0.sessions) },
            today: Self.today())
    }

    /// Dirty rows to push. Grow-only + server MAX means re-pushing is harmless.
    func pendingRows() -> [Row] { dirty.compactMap { rows[$0] } }
    var hasPending: Bool { !dirty.isEmpty }

    /// Clears only rows unchanged since the snapshot, so tokens recorded during the
    /// push stay dirty and get sent next time.
    func markSynced(_ snapshot: [Row]) {
        for s in snapshot {
            let key = "\(s.projectId)|\(s.agent)|\(s.day)"
            if rows[key] == s { dirty.remove(key) }
        }
        UserDefaults.standard.set(Array(dirty), forKey: Self.dirtyKey)
    }

    // MARK: - Helpers

    static func projectIdentity(_ path: String) -> (id: String, name: String) {
        // One hash for the usage rows and the custom names (ProjectNames), so a
        // name can never stop matching its project.
        (ProjectNames.id(for: path), String(ProjectNames.folderName(path).prefix(60)))
    }
    private static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rows) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        UserDefaults.standard.set(Array(dirty), forKey: Self.dirtyKey)
    }

    /// Keep local storage bounded: drop day-rows older than ~120 days.
    private func pruneOld() {
        let cutoff = Self.dayString(daysAgo: 120)
        let stale = rows.filter { $0.value.day < cutoff }.map(\.key)
        guard !stale.isEmpty else { return }
        for k in stale { rows.removeValue(forKey: k); dirty.remove(k) }
        persist()
        recomputeCostTotals()
    }

    private func recomputeCostTotals() {
        let day = Self.today()
        let month = String(day.prefix(7))
        todayCostUSD = rows.values.filter { $0.day == day }.reduce(0) { $0 + $1.costUSD }
        monthlyCostUSD = rows.values.filter { $0.day.hasPrefix(month) }.reduce(0) { $0 + $1.costUSD }
    }
    private static func dayString(daysAgo: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}
