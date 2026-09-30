import CoreGraphics
import Foundation

/// Keeps a pet window on-screen across resolution / monitor changes (issue #47).
public enum PetWindowGeometry {
    /// Clamps a bottom-left `origin` so a window of `size` sits fully inside the
    /// screen's `visible` frame. If the window is larger than the visible area on
    /// an axis, it pins to that axis's minimum edge. Pure (no AppKit) so it's unit
    /// testable without a display.
    public static func clampOrigin(_ origin: CGPoint, size: CGSize, into visible: CGRect) -> CGPoint {
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        return CGPoint(x: origin.x.clamped(visible.minX, maxX),
                       y: origin.y.clamped(visible.minY, maxY))
    }

    /// Horizontal placement for a pet window of `width` whose pet (`petWidth`
    /// wide) should stay centred at `anchorX`. The window is kept inside
    /// `[visibleMinX, visibleMaxX]` so a wide bubble never spills onto another
    /// display; the pet is then shifted inside the window by `petOffset` so it
    /// doesn't move on screen. The offset is limited so the pet stays inside the
    /// window (it only moves if the pet itself was dragged past the edge).
    public static func horizontalLayout(anchorX: CGFloat, width: CGFloat, petWidth: CGFloat,
                                        visibleMinX: CGFloat, visibleMaxX: CGFloat)
        -> (originX: CGFloat, petOffset: CGFloat) {
        let maxOriginX = max(visibleMinX, visibleMaxX - width)
        let originX = (anchorX - width / 2).clamped(visibleMinX, maxOriginX)
        let limit = max(0, (width - petWidth) / 2)
        let offset = (anchorX - (originX + width / 2)).clamped(-limit, limit)
        return (originX, offset)
    }

    /// Keeps a pet's speech bubble over the pet when the pet is offset inside
    /// its window by `petOffset` (see `horizontalLayout`). The bubble moves
    /// toward the pet as far as the window allows (`windowWidth`, the real
    /// window, which lags a content resize); the tail covers the rest, kept
    /// `tailClearance` away from the rounded corners. `bubbleWidth` includes
    /// `bubbleInset` of padding on each side.
    public static func bubbleLayout(petOffset: CGFloat, windowWidth: CGFloat, bubbleWidth: CGFloat,
                                    bubbleInset: CGFloat, tailClearance: CGFloat)
        -> (bubbleShift: CGFloat, tailShift: CGFloat) {
        let room = max(0, (windowWidth - bubbleWidth) / 2)
        let bubbleShift = petOffset.clamped(-room, room)
        let tailLimit = max(0, (bubbleWidth - 2 * bubbleInset) / 2 - tailClearance)
        return (bubbleShift, (petOffset - bubbleShift).clamped(-tailLimit, tailLimit))
    }
}

extension Comparable {
    /// `self` limited to `lo...hi` (returns `hi` if `lo > hi`, like `min(max())`).
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

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
