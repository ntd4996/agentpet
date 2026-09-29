import Foundation

/// jcode lifecycle hook integration (github.com/1jehuang/jcode, docs/HOOKS.md).
///
/// jcode runs each configured observer hook detached with stdin = /dev/null and
/// describes the event in `JCODE_HOOK_*` env vars, so the event is built from
/// the environment instead of a stdin payload.
public enum JcodeHookPayload {
    public static func event(env: [String: String], now: Date) -> AgentEvent? {
        guard let name = nonEmpty(env["JCODE_HOOK_EVENT"]),
              let sessionId = nonEmpty(env["JCODE_HOOK_SESSION_ID"]) else { return nil }
        let toolName = nonEmpty(env["JCODE_HOOK_TOOL_NAME"])
        var eventName = name
        // jcode has no "needs input" hook. A turn that ends by asking the user
        // something is reported as waiting, like Claude's Stop refinement.
        if name == "turn_end", env["JCODE_HOOK_STATUS"] != "error",
           let text = nonEmpty(env["JCODE_HOOK_LAST_ASSISTANT_TEXT"]),
           QuestionDetector.looksLikeQuestion(text) {
            eventName = AgentState.waiting.rawValue
        }
        let message = toolName.flatMap {
            ActivityFormatter.activityMessage(
                eventName: "PostToolUse", sessionId: sessionId,
                toolName: $0, toolInput: nil, explicitMessage: nil)
        }
        return AgentEvent(
            sessionId: sessionId, agentKind: .jcode, eventName: eventName,
            project: nonEmpty(env["JCODE_HOOK_CWD"]), message: message,
            model: nonEmpty(env["JCODE_HOOK_MODEL"]), timestamp: now)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}

/// Thrown when a jcode hook key AgentPet needs is already set to someone
/// else's command.
public enum JcodeHookConfigError: LocalizedError, Equatable {
    case conflictingHook(event: String, path: String)

    public var errorDescription: String? {
        switch self {
        case .conflictingHook(let event, let path):
            return "\(path) already sets hooks.\(event); remove it or add AgentPet's command to it manually."
        }
    }
}

/// Adds/removes AgentPet's entries in the `[hooks]` table of
/// `~/.jcode/config.toml` with line edits, so comments and every other key are
/// left byte-for-byte intact. Pure string transforms (tested) plus disk IO.
///
/// simplify: a key already set to a foreign command is refused, not merged.
/// jcode accepts an array value (`key = ["a", "b"]`), so merging is the upgrade
/// path if anyone needs to share a hook with AgentPet.
public enum JcodeHookConfig {
    /// Line indices of the `[hooks]` table body: after its header, up to the
    /// next table header. `nil` when the table is absent.
    static func hooksBody(_ lines: [String]) -> (header: Int, end: Int)? {
        guard let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[hooks]" })
        else { return nil }
        var end = header + 1
        while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            end += 1
        }
        return (header, end)
    }

    /// Index of the uncommented `key = ...` line in the hooks body, if any.
    static func keyLine(_ key: String, in lines: [String], body: (header: Int, end: Int)) -> Int? {
        (body.header + 1 ..< body.end).first { i in
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(key) else { return false }
            return line.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix("=")
        }
    }

    /// TOML string for `command`: a literal string when possible (no escaping
    /// of the embedded double quotes), otherwise an escaped basic string.
    static func tomlString(_ command: String) -> String {
        if !command.contains("'") && !command.contains("\n") { return "'\(command)'" }
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    public static func isInstalled(in toml: String, events: [String]) -> Bool {
        let lines = toml.components(separatedBy: "\n")
        guard let body = hooksBody(lines) else { return false }
        return events.contains { event in
            keyLine(event, in: lines, body: body).map { HookInstaller.isOurs(lines[$0]) } ?? false
        }
    }

    public static func install(in toml: String, command: String, events: [String], path: String = "config.toml") throws -> String {
        var lines = toml.components(separatedBy: "\n")
        if hooksBody(lines) == nil {
            if let last = lines.last, last.isEmpty { lines.removeLast() }
            if !lines.isEmpty { lines.append("") }
            lines.append("[hooks]")
            lines.append("")
        }
        let body = hooksBody(lines)!
        // Validate every key before editing so a conflict never half-installs.
        for event in events {
            if let i = keyLine(event, in: lines, body: body), !HookInstaller.isOurs(lines[i]) {
                throw JcodeHookConfigError.conflictingHook(event: event, path: path)
            }
        }
        let value = tomlString(command)
        var insertAt = body.header + 1
        for event in events {
            let entry = "\(event) = \(value)"
            if let i = keyLine(event, in: lines, body: hooksBody(lines)!) {
                lines[i] = entry
            } else {
                lines.insert(entry, at: insertAt)
                insertAt += 1
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Removes only AgentPet's keys; foreign hooks and the table header stay.
    public static func uninstall(in toml: String, events: [String]) -> String {
        var lines = toml.components(separatedBy: "\n")
        for event in events {
            guard let body = hooksBody(lines),
                  let i = keyLine(event, in: lines, body: body),
                  HookInstaller.isOurs(lines[i]) else { continue }
            lines.remove(at: i)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Disk IO

    static func read(path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    static func write(_ toml: String, path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // Atomic: jcode re-reads this file on mtime change, never a partial one.
        try Data(toml.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    public static func installToDisk(command: String, path: String, events: [String]) throws {
        let existing = read(path: path)
        let updated = try install(in: existing, command: command, events: events, path: path)
        if updated != existing { try write(updated, path: path) }
    }

    public static func uninstallFromDisk(path: String, events: [String]) throws {
        let existing = read(path: path)
        let updated = uninstall(in: existing, events: events)
        if updated != existing { try write(updated, path: path) }
    }
}
