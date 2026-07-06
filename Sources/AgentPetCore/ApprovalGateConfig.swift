import Foundation

/// Opt-in whitelist for the bubble approval gate: the gate stays OFF unless
/// `~/.agentpet/approval-gate.json` exists with `{"tools": ["Bash", ...]}`.
public enum ApprovalGateConfig {
    public static var defaultPath: String {
        (AgentPetPaths.baseDir as NSString).appendingPathComponent("approval-gate.json")
    }

    /// Tools whose `PreToolUse` gates the session on a user decision.
    /// Missing or unreadable config means the feature is disabled.
    public static func gatedTools(path: String? = nil) -> Set<String> {
        let file = path ?? defaultPath
        guard let data = FileManager.default.contents(atPath: file),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return [] }
        return Set(config.tools)
    }

    private struct Config: Decodable {
        let tools: [String]
    }
}
