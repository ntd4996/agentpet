import Foundation
import AgentPetCore

/// Display strings shared by the care views (Settings tab, stats popover, menu bar).
enum CareFormat {
    static func hunger(_ hunger: PetHunger) -> String {
        switch hunger {
        case .full: return NSLocalizedString("Full", comment: "hunger")
        case .satisfied: return NSLocalizedString("Satisfied", comment: "hunger")
        case .peckish: return NSLocalizedString("Peckish", comment: "hunger")
        case .hungry: return NSLocalizedString("Hungry", comment: "hunger")
        case .starving: return NSLocalizedString("Starving", comment: "hunger")
        }
    }

    /// Compact token count: `999`, `12k`, `2.5M`.
    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    /// Full count with locale grouping separators.
    static func plain(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

extension CareFormat {
    /// The value cell of a "By agent" row: `today · month` tokens, or the number
    /// of finished sessions for an agent whose hook carries no token counts.
    static func agentUsage(_ total: AgentUsageTotal) -> String {
        guard AgentUsage.isSessionOnly(total) else {
            return "\(tokens(total.today)) · \(tokens(total.month))"
        }
        return total.sessions == 1
            ? NSLocalizedString("1 session", comment: "By agent row, no token counts")
            : String(format: NSLocalizedString("%d sessions", comment: "By agent row, no token counts"), total.sessions)
    }
}
