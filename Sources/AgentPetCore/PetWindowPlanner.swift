import Foundation

public struct PetWindowSpec: Equatable, Sendable {
    public var key: String
    public var projectName: String?
    public var petID: String?
    public var sessionIDs: [String]
    public var mood: PetMood
    public var count: Int
}

public enum PetWindowPlanner {
    public static let defaultKey = "default"

    private static func isActive(_ s: AgentState) -> Bool {
        s == .working || s == .waiting || s == .done
    }

    /// Plans the per-project pet windows. `forceDefault` guarantees a home
    /// ("default") window in the result even in split mode — used so a break
    /// nudge always has a pet to show.
    public static func plan(sessions: [AgentSession], split: Bool,
                            mappings: [ProjectPetMapping], defaultPetID: String?,
                            forceDefault: Bool = false, hideIdleProjects: Bool = false) -> [PetWindowSpec] {
        let specs = planCore(sessions: sessions, split: split, mappings: mappings,
                             defaultPetID: defaultPetID, hideIdleProjects: hideIdleProjects)
        guard forceDefault, !specs.contains(where: { $0.key == defaultKey }) else { return specs }
        return specs + [PetWindowSpec(key: defaultKey, projectName: nil, petID: defaultPetID,
                                      sessionIDs: [], mood: .idle, count: 0)]
    }

    private static func planCore(sessions: [AgentSession], split: Bool,
                                 mappings: [ProjectPetMapping], defaultPetID: String?,
                                 hideIdleProjects: Bool) -> [PetWindowSpec] {
        let active = sessions.filter { isActive($0.state) }

        func defaultWindow(_ s: [AgentSession]) -> PetWindowSpec {
            PetWindowSpec(key: defaultKey, projectName: nil, petID: defaultPetID,
                          sessionIDs: s.map(\.id),
                          mood: s.isEmpty ? .idle : MoodResolver.aggregate(s),
                          count: s.count)
        }

        if !split {
            return [defaultWindow(active)]
        }

        // Split mode: ONE persistent window per *configured* project (kept even
        // when idle), plus a single "default" window that aggregates everything
        // not assigned to a configured project. Removing a project's mapping
        // therefore folds it back into the main pet on the next sync.
        let configured = ProjectPetResolver.dedupedByKey(mappings)

        // Bucket each active session under its configured mapping (longest-prefix
        // match), or the default bucket if it belongs to no configured project.
        var byKey: [String: [AgentSession]] = [:]
        var rest: [AgentSession] = []
        for s in active {
            if let m = ProjectPetResolver.mapping(forProject: s.project, mappings: configured) {
                byKey[ProjectPetResolver.normalize(m.projectPath), default: []].append(s)
            } else {
                rest.append(s)
            }
        }

        var specs = configured.compactMap { m -> PetWindowSpec? in
            let key = ProjectPetResolver.normalize(m.projectPath)
            let mine = byKey[key] ?? []
            // With "hide idle project pets" on, a configured project shows only
            // while it has active work; otherwise it stays put even when idle.
            if mine.isEmpty && hideIdleProjects { return nil }
            return PetWindowSpec(
                key: key,
                projectName: (m.projectPath as NSString).lastPathComponent,
                petID: m.petID,
                sessionIDs: mine.map(\.id),
                mood: mine.isEmpty ? .idle : MoodResolver.aggregate(mine),
                count: mine.count)
        }
        specs.append(defaultWindow(rest))
        return specs
    }

    public static func windowKeys(forPetID petID: String, split: Bool,
                                  mappings: [ProjectPetMapping],
                                  selectedPetID: String?) -> [String] {
        guard split else { return [defaultKey] }
        var keys = mappings
            .filter { $0.petID == petID }
            .map { ProjectPetResolver.normalize($0.projectPath) }
        if petID == selectedPetID {
            keys.append(defaultKey)
        }
        return keys.isEmpty ? [defaultKey] : keys
    }
}
