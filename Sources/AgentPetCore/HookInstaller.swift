import Foundation

/// Installs/removes AgentPet's hook entries in an agent's config. Claude Code,
/// Codex, and Gemini share the nested `{"hooks": {...}}` shape; Cursor and
/// Windsurf use flatter JSON shapes; opencode uses a JS plugin file. The shape
/// is selected by `HookStyle`.
///
/// The dictionary transforms are pure (and tested); the `*OnDisk` helpers wrap
/// them with file IO. Our entries are identified by their command string, so
/// install is idempotent and foreign hooks are never touched.
public enum HookInstaller {
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SubagentStop",
    ]

    public static func defaultSettingsPath() -> String {
        NSHomeDirectory() + "/.claude/settings.json"
    }

    /// True when a hook command is one AgentPet installed: the invoked binary
    /// is named `agentpet` (any path, any case) and its first argument is the
    /// `hook` subcommand. A plain substring check would also claim a user's own
    /// hook whose path merely mentions agentpet (e.g.
    /// `/Users/me/agentpet-experiments/my-hook.sh`) and delete it on uninstall.
    static func isOurs(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let binary: String
        let rest: String
        if trimmed.hasPrefix("\"") {
            let afterQuote = trimmed.dropFirst()
            guard let close = afterQuote.firstIndex(of: "\"") else { return false }
            binary = String(afterQuote[..<close])
            rest = String(afterQuote[afterQuote.index(after: close)...])
        } else {
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            binary = parts.first.map(String.init) ?? ""
            rest = parts.count > 1 ? String(parts[1]) : ""
        }
        guard (binary as NSString).lastPathComponent.lowercased() == "agentpet" else { return false }
        return rest.split(separator: " ").first == "hook"
    }

    // MARK: - Claude-nested shape (Claude / Codex / Gemini)

    public static func isInstalled(in settings: [String: Any], events: [String] = events) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        for event in events {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            if groups.contains(where: groupIsOurs) { return true }
        }
        return false
    }

    public static func install(into settings: [String: Any], command: String, events: [String] = events) -> [String: Any] {
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !groupIsOurs($0) }
            groups.append(["hooks": [["type": "command", "command": command]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    public static func uninstall(from settings: [String: Any], events: [String] = events) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for event in events {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let kept = groups.filter { !groupIsOurs($0) }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        return settings
    }

    private static func groupIsOurs(_ group: [String: Any]) -> Bool {
        guard let inner = group["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String).map(isOurs) ?? false }
    }

    // MARK: - Flat shape (Cursor / Windsurf): {"hooks": {event: [{"command": ...}]}}

    private static func flatItemIsOurs(_ item: [String: Any]) -> Bool {
        (item["command"] as? String).map(isOurs) ?? false
    }

    static func installFlat(into settings: [String: Any], command: String, events: [String], style: HookStyle) -> [String: Any] {
        var settings = settings
        if style == .cursorFlat { settings["version"] = settings["version"] ?? 1 }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var items = (hooks[event] as? [[String: Any]] ?? []).filter { !flatItemIsOurs($0) }
            var entry: [String: Any] = ["command": command]
            if style == .cursorFlat { entry["type"] = "command" }
            if style == .windsurfFlat { entry["show_output"] = false }
            items.append(entry)
            hooks[event] = items
        }
        settings["hooks"] = hooks
        return settings
    }

    static func uninstallFlat(from settings: [String: Any], events: [String]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for event in events {
            guard let items = hooks[event] as? [[String: Any]] else { continue }
            let kept = items.filter { !flatItemIsOurs($0) }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        return settings
    }

    static func isInstalledFlat(in settings: [String: Any], events: [String]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        for event in events {
            guard let items = hooks[event] as? [[String: Any]] else { continue }
            if items.contains(where: flatItemIsOurs) { return true }
        }
        return false
    }

    // MARK: - opencode JS plugin

    /// Extracts the agentpet binary path from a hook command like
    /// `"/path/to/agentpet" hook --agent opencode` (the first quoted token).
    static func binaryPath(fromCommand command: String) -> String {
        if let first = command.firstIndex(of: "\"") {
            let rest = command[command.index(after: first)...]
            if let second = rest.firstIndex(of: "\"") {
                return String(rest[..<second])
            }
        }
        return command.components(separatedBy: " ").first ?? command
    }

    static func opencodePlugin(binary: String) -> String {
        """
        // AgentPet integration (auto-generated, safe to delete to uninstall).
        // Reports opencode session lifecycle to AgentPet's menu bar app.
        const AGENTPET_BIN = \(jsString(binary))
        export const AgentPet = async ({ directory }) => {
          const sid = "opencode:" + (directory || "default")
          const send = (state) => {
            try {
              Bun.spawn([AGENTPET_BIN, "hook", "--agent", "opencode",
                         "--event", state, "--session", sid, "--project", directory || ""])
            } catch (e) {}
          }
          return {
            "session.created": async () => { send("working") },
            "session.idle": async () => { send("done") },
          }
        }
        """
    }

    /// JSON-encodes a string for safe embedding in JS source.
    private static func jsString(_ s: String) -> String {
        if let data = try? JSONEncoder().encode(s), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "\"\(s)\""
    }

    // MARK: - Disk IO

    public static func readSettings(path: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    public static func writeSettings(_ settings: [String: Any], path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    public static func installToDisk(command: String, path: String = defaultSettingsPath(),
                                     events: [String] = events, style: HookStyle = .claudeNested) throws {
        switch style {
        case .claudeNested:
            try writeSettings(install(into: readSettings(path: path), command: command, events: events), path: path)
        case .cursorFlat, .windsurfFlat:
            try writeSettings(installFlat(into: readSettings(path: path), command: command, events: events, style: style), path: path)
        case .opencodePlugin:
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let js = opencodePlugin(binary: binaryPath(fromCommand: command))
            try Data(js.utf8).write(to: URL(fileURLWithPath: path))
        }
    }

    public static func uninstallFromDisk(path: String = defaultSettingsPath(),
                                         events: [String] = events, style: HookStyle = .claudeNested) throws {
        switch style {
        case .claudeNested:
            try writeSettings(uninstall(from: readSettings(path: path), events: events), path: path)
        case .cursorFlat, .windsurfFlat:
            try writeSettings(uninstallFlat(from: readSettings(path: path), events: events), path: path)
        case .opencodePlugin:
            if isInstalledOnDisk(path: path, events: events, style: style) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    public static func isInstalledOnDisk(path: String = defaultSettingsPath(),
                                         events: [String] = events, style: HookStyle = .claudeNested) -> Bool {
        switch style {
        case .claudeNested:
            return isInstalled(in: readSettings(path: path), events: events)
        case .cursorFlat, .windsurfFlat:
            return isInstalledFlat(in: readSettings(path: path), events: events)
        case .opencodePlugin:
            // The generated plugin always declares AGENTPET_BIN; a user's own
            // plugin file won't, so it is never mistaken for ours (and deleted).
            guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
            return s.contains("AGENTPET_BIN")
        }
    }
}
