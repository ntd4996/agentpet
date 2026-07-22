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

    /// Whether `tool` is currently gated.
    public static func isEnabled(tool: String = "Bash", path: String? = nil) -> Bool {
        gatedTools(path: path).contains(tool)
    }

    /// Turns the gate for `tool` on (writes the config file) or off (removes
    /// it). Mirrors the opt-in default: no file on disk means disabled.
    public static func setEnabled(_ enabled: Bool, tool: String = "Bash", path: String? = nil) {
        let file = path ?? defaultPath
        guard enabled else {
            try? FileManager.default.removeItem(atPath: file)
            return
        }
        let dir = (file as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Config(tools: [tool])) else { return }
        try? data.write(to: URL(fileURLWithPath: file))
    }

    private struct Config: Codable {
        let tools: [String]
    }
}

/// Timeouts for the approval handoff. The daemon MUST resolve strictly before
/// the client gives up, so the reply always lands on a still-open fd. Keep the
/// two coupled here; do not set them independently at the call sites.
public enum ApprovalTimeouts {
    /// Daemon auto-resolves a pending approval to `.ask` after this long.
    public static let daemon: TimeInterval = 10
    /// Client (hook CLI) stops waiting for a reply after this long. Must be > `daemon`.
    public static let client: TimeInterval = 12
}
