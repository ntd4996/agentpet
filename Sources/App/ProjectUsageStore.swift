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
    }

    private static let storageKey = "agentpet.projectUsage"
    private static let dirtyKey = "agentpet.projectUsage.dirty"
    /// Keyed by "projectId|agent|day".
    private var rows: [String: Row]
    private var dirty: Set<String>

    init() {
        rows = (UserDefaults.standard.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: Row].self, from: $0) }) ?? [:]
        dirty = Set((UserDefaults.standard.array(forKey: Self.dirtyKey) as? [String]) ?? [])
        pruneOld()
    }

    // MARK: - Recording

    func recordTokens(_ tokens: Int, project: String?, agent: String) {
        record(project: project, agent: agent, tokens: tokens, sessions: 0)
    }
    func recordSession(project: String?, agent: String) {
        record(project: project, agent: agent, tokens: 0, sessions: 1)
    }

    private func record(project: String?, agent: String, tokens: Int, sessions: Int) {
        guard let project, !project.isEmpty, !agent.isEmpty, tokens > 0 || sessions > 0 else { return }
        let (pid, pname) = Self.projectIdentity(project)
        let day = Self.today()
        let key = "\(pid)|\(agent)|\(day)"
        var r = rows[key] ?? Row(projectId: pid, projectName: pname, agent: agent, day: day, tokens: 0, sessions: 0)
        r.tokens += tokens
        r.sessions += sessions
        r.projectName = pname
        rows[key] = r
        dirty.insert(key)
        persist()
        CareSyncController.shared.scheduleUsageSync()
    }

    // MARK: - Sync support

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
        let last = (path as NSString).lastPathComponent
        let name = last.isEmpty ? path : last
        return ("p" + String(format: "%08x", fnv1a(path)), String(name.prefix(60)))
    }
    private static func fnv1a(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h ^= UInt32(b); h = h &* 16777619 }
        return h
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
    }
    private static func dayString(daysAgo: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}
