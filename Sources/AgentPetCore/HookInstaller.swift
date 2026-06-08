import Foundation

/// Thrown when an agent's settings file exists but cannot be parsed as a JSON
/// object. Rewriting it anyway would replace whatever the user had with just
/// AgentPet's hooks, so install/uninstall refuse instead.
public enum HookInstallerError: LocalizedError, Equatable {
    case unreadableSettings(path: String)

    public var errorDescription: String? {
        switch self {
        case .unreadableSettings(let path):
            return "\(path) is not valid JSON; fix or remove it and try again."
        }
    }
}

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

    static func isOurs(_ command: String) -> Bool {
        command.contains("agentpet") && command.contains("hook")
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

    // MARK: - Antigravity named-group shape (~/.gemini/config/hooks.json)
    // Same per-event structure as Claude-nested, but the event map sits under a
    // named hook group key instead of "hooks", alongside any other user groups:
    // {"agentpet": {Event: [{"hooks": [{"type": "command", "command": ...}]}]}}

    /// The hook-group key AgentPet owns in an Antigravity hooks.json.
    public static let antigravityGroup = "agentpet"

    public static func installAntigravity(into settings: [String: Any], command: String, events: [String]) -> [String: Any] {
        var settings = settings
        var group = settings[antigravityGroup] as? [String: Any] ?? [:]
        for event in events {
            var groups = (group[event] as? [[String: Any]] ?? []).filter { !groupIsOurs($0) }
            groups.append(["hooks": [["type": "command", "command": command]]])
            group[event] = groups
        }
        settings[antigravityGroup] = group
        return settings
    }

    public static func uninstallAntigravity(from settings: [String: Any], events: [String]) -> [String: Any] {
        var settings = settings
        guard var group = settings[antigravityGroup] as? [String: Any] else { return settings }
        for event in events {
            guard let groups = group[event] as? [[String: Any]] else { continue }
            let kept = groups.filter { !groupIsOurs($0) }
            if kept.isEmpty { group.removeValue(forKey: event) } else { group[event] = kept }
        }
        if group.isEmpty { settings.removeValue(forKey: antigravityGroup) } else { settings[antigravityGroup] = group }
        return settings
    }

    public static func isInstalledAntigravity(in settings: [String: Any], events: [String]) -> Bool {
        guard let group = settings[antigravityGroup] as? [String: Any] else { return false }
        for event in events {
            guard let groups = group[event] as? [[String: Any]] else { continue }
            if groups.contains(where: groupIsOurs) { return true }
        }
        return false
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

    // MARK: - Hermes YAML shape (~/.hermes/config.yaml)

    private struct ParsedHermesHooks {
        var parsedEvents: [String: [String]]
        var eventOrder: [String]
        var startLineIndex: Int
        var endLineIndex: Int
    }

    private static func parseHermesHooks(lines: [String]) -> ParsedHermesHooks? {
        guard let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "hooks:" }) else {
            return nil
        }
        var endIdx = lines.count
        for j in (idx + 1)..<lines.count {
            let trimmed = lines[j].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") && trimmed.utf8.first.map({ $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") }) ?? false {
                endIdx = j
                break
            }
        }

        var parsedEvents: [String: [String]] = [:]
        var eventOrder: [String] = []
        var currentEvent: String? = nil

        for line in lines[(idx + 1)..<endIdx] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if line.hasSuffix(":") && !trimmed.hasPrefix("-") {
                let name = String(trimmed.dropLast())
                currentEvent = name
                if !eventOrder.contains(name) {
                    eventOrder.append(name)
                }
                if parsedEvents[name] == nil {
                    parsedEvents[name] = []
                }
            } else if trimmed.hasPrefix("-") {
                if let event = currentEvent {
                    parsedEvents[event]?.append(line)
                }
            }
        }
        return ParsedHermesHooks(
            parsedEvents: parsedEvents,
            eventOrder: eventOrder,
            startLineIndex: idx,
            endLineIndex: endIdx
        )
    }

    /// Generates a `hooks:` YAML block with the given events and command, merging
    /// with any existing hooks to preserve foreign/custom entries.
    public static func installHermesYaml(into fileContent: String, command: String, events: [String]) -> String {
        let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
        let cmdLine = "    - command: '\(escaped)'"
        var lines = fileContent.components(separatedBy: "\n")

        if let parsed = parseHermesHooks(lines: lines) {
            var parsedEvents = parsed.parsedEvents
            var eventOrder = parsed.eventOrder

            // Clean up our old commands from all events
            for event in parsedEvents.keys {
                parsedEvents[event] = parsedEvents[event]?.filter { !isOurs($0) }
            }

            // Add our command to the target events
            for event in events {
                if parsedEvents[event] == nil {
                    parsedEvents[event] = []
                    eventOrder.append(event)
                }
                parsedEvents[event]?.append(cmdLine)
            }

            // Build the new hooks block
            var blockLines: [String] = ["hooks:"]
            for event in eventOrder {
                if let cmds = parsedEvents[event], !cmds.isEmpty {
                    blockLines.append("  \(event):")
                    for cmd in cmds {
                        if cmd.hasPrefix(" ") || cmd.hasPrefix("\t") {
                            blockLines.append(cmd)
                        } else {
                            blockLines.append("    \(cmd)")
                        }
                    }
                }
            }

            let hooksBlock = blockLines.joined(separator: "\n")
            lines.replaceSubrange(parsed.startLineIndex..<parsed.endLineIndex, with: [hooksBlock])
        } else {
            // Append at the end
            let hooksBlock = hermesYamlBlock(command: command, events: events)
            if !fileContent.isEmpty && !fileContent.hasSuffix("\n") {
                lines.append("")
            }
            lines.append(hooksBlock)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Removes only our hook commands from a Hermes YAML config, leaving any other
    /// custom events/commands intact.
    public static func uninstallHermesYaml(from fileContent: String) -> String {
        var lines = fileContent.components(separatedBy: "\n")
        guard let parsed = parseHermesHooks(lines: lines) else {
            return fileContent
        }

        var parsedEvents = parsed.parsedEvents
        let eventOrder = parsed.eventOrder

        // Remove our commands
        for event in parsedEvents.keys {
            parsedEvents[event] = parsedEvents[event]?.filter { !isOurs($0) }
        }

        // Build the block lines
        var blockLines: [String] = []
        for event in eventOrder {
            if let cmds = parsedEvents[event], !cmds.isEmpty {
                blockLines.append("  \(event):")
                for cmd in cmds {
                    if cmd.hasPrefix(" ") || cmd.hasPrefix("\t") {
                        blockLines.append(cmd)
                    } else {
                        blockLines.append("    \(cmd)")
                    }
                }
            }
        }

        let replacement: String
        if blockLines.isEmpty {
            replacement = "hooks: {}"
        } else {
            replacement = (["hooks:"] + blockLines).joined(separator: "\n")
        }

        lines.replaceSubrange(parsed.startLineIndex..<parsed.endLineIndex, with: [replacement])
        return lines.joined(separator: "\n") + "\n"
    }

    /// True if `fileContent` is a Hermes YAML config with our hook block installed.
    public static func isInstalledHermesYaml(in fileContent: String) -> Bool {
        isOurs(fileContent)
    }

    /// Builds the YAML hooks block string.
    private static func hermesYamlBlock(command: String, events: [String]) -> String {
        let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
        var block = "hooks:\n"
        for event in events {
            block += "  \(event):\n"
            block += "    - command: '\(escaped)'\n"
        }
        return block.hasSuffix("\n") ? String(block.dropLast()) : block
    }

    // MARK: - Disk IO

    /// Reads an agent's settings file. A missing or empty file is an empty
    /// config; a file with content that does not parse as a JSON object throws,
    /// so callers never rewrite (and thereby wipe) settings they could not read.
    public static func readSettings(path: String) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstallerError.unreadableSettings(path: path)
        }
        return obj
    }

    public static func writeSettings(_ settings: [String: Any], path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        // Atomic so a crash mid-write can never leave a truncated settings file.
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    public static func installToDisk(command: String, path: String = defaultSettingsPath(),
                                     events: [String] = events, style: HookStyle = .claudeNested) throws {
        switch style {
        case .claudeNested:
            try writeSettings(install(into: readSettings(path: path), command: command, events: events), path: path)
        case .cursorFlat, .windsurfFlat:
            try writeSettings(installFlat(into: readSettings(path: path), command: command, events: events, style: style), path: path)
        case .antigravityNested:
            try writeSettings(installAntigravity(into: readSettings(path: path), command: command, events: events), path: path)
        case .opencodePlugin:
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let js = opencodePlugin(binary: binaryPath(fromCommand: command))
            try Data(js.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        case .hermesYaml:
            let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let updated = installHermesYaml(into: existing, command: command, events: events)
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try Data(updated.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    public static func uninstallFromDisk(path: String = defaultSettingsPath(),
                                         events: [String] = events, style: HookStyle = .claudeNested) throws {
        switch style {
        case .claudeNested:
            try writeSettings(uninstall(from: readSettings(path: path), events: events), path: path)
        case .cursorFlat, .windsurfFlat:
            try writeSettings(uninstallFlat(from: readSettings(path: path), events: events), path: path)
        case .antigravityNested:
            try writeSettings(uninstallAntigravity(from: readSettings(path: path), events: events), path: path)
        case .opencodePlugin:
            if isInstalledOnDisk(path: path, events: events, style: style) {
                try? FileManager.default.removeItem(atPath: path)
            }
        case .hermesYaml:
            let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let updated = uninstallHermesYaml(from: existing)
            try Data(updated.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    public static func isInstalledOnDisk(path: String = defaultSettingsPath(),
                                         events: [String] = events, style: HookStyle = .claudeNested) -> Bool {
        switch style {
        case .claudeNested:
            return isInstalled(in: (try? readSettings(path: path)) ?? [:], events: events)
        case .cursorFlat, .windsurfFlat:
            return isInstalledFlat(in: (try? readSettings(path: path)) ?? [:], events: events)
        case .antigravityNested:
            return isInstalledAntigravity(in: (try? readSettings(path: path)) ?? [:], events: events)
        case .opencodePlugin:
            guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
            return isOurs(s)
        case .hermesYaml:
            guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
            return isInstalledHermesYaml(in: s)
        }
    }
}
