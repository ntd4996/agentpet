import Foundation

/// A coding agent AgentPet can integrate with, and whether that integration is
/// available yet. Drives the Settings/onboarding agent list.
public struct AgentIntegration: Identifiable, Sendable, Equatable {
    public let kind: AgentKind
    public let displayName: String
    public let isSupported: Bool
    public let note: String?

    public var id: String { kind.rawValue }

    public init(kind: AgentKind, displayName: String, isSupported: Bool, note: String? = nil) {
        self.kind = kind
        self.displayName = displayName
        self.isSupported = isSupported
        self.note = note
    }
}

public enum AgentCatalog {
    public static let all: [AgentIntegration] = [
        AgentIntegration(kind: .claude, displayName: "Claude Code", isSupported: true),
        AgentIntegration(kind: .codex, displayName: "Codex", isSupported: true),
        AgentIntegration(kind: .gemini, displayName: "Gemini CLI", isSupported: true),
        AgentIntegration(kind: .cursor, displayName: "Cursor", isSupported: true),
        AgentIntegration(kind: .opencode, displayName: "opencode", isSupported: true),
        AgentIntegration(kind: .windsurf, displayName: "Windsurf", isSupported: true,
                         note: "No \"needs input\" alerts (Windsurf has no such hook)"),
        AgentIntegration(kind: .antigravity, displayName: "Antigravity", isSupported: true,
                         note: "No \"needs input\" alerts (Antigravity has no notification hook)"),
        AgentIntegration(kind: .hermes, displayName: "Hermes", isSupported: true,
                         note: "No \"needs input\" alerts (Hermes has no notification hook)"),
    ]
}
