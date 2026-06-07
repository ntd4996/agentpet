import Foundation

/// The JSON Hermes writes to a shell hook's stdin.
///
/// Decoded via `JSONSerialization` (not `Decodable`) to handle the arbitrary
/// `tool_input` dict cleanly.  Only the fields AgentPet needs are extracted.
public struct HermesHookPayload {
    public let sessionId: String?
    public let cwd: String?
    public let hookEventName: String?
    public let toolName: String?
    /// The tool's arguments dict — e.g. `["command": "npm install"]` for terminal.
    public let toolInput: [String: Any]?

    public init(
        sessionId: String? = nil, cwd: String? = nil,
        hookEventName: String? = nil, toolName: String? = nil,
        toolInput: [String: Any]? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.hookEventName = hookEventName
        self.toolName = toolName
        self.toolInput = toolInput
    }

    /// Decodes the Hermes hook JSON payload via `JSONSerialization`.
    public static func decode(from data: Data) -> HermesHookPayload? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return HermesHookPayload(
            sessionId: json["session_id"] as? String,
            cwd: json["cwd"] as? String,
            hookEventName: json["hook_event_name"] as? String,
            toolName: json["tool_name"] as? String,
            toolInput: json["tool_input"] as? [String: Any]
        )
    }

    /// Builds an `AgentEvent` carrying a short human-readable message about what
    /// Hermes is doing right now.
    public func makeAgentEvent(now: Date) -> AgentEvent? {
        guard let sessionId, let hookEventName else { return nil }
        return AgentEvent(
            sessionId: sessionId, agentKind: .hermes, eventName: hookEventName,
            project: cwd, message: makeMessage(), timestamp: now
        )
    }

    /// Produces a one-line activity description suitable for the pet bubble.
    public func makeMessage() -> String? {
        guard let hookEventName else { return nil }

        switch hookEventName {
        case "pre_llm_call", "post_llm_call":
            return "Thinking…"
        case "pre_tool_call":
            return describeToolActivity()
        case "post_tool_call":
            return nil  // keep the "pre" message
        case "pre_api_request":
            return "Calling API…"
        case "post_api_request":
            return nil
        case "on_session_start":
            return nil
        case "on_session_end", "on_session_finalize", "on_session_reset":
            return "Done"
        case "subagent_stop":
            return "Subtask finished"
        default:
            return "Working…"
        }
    }

    // MARK: - Tool activity summary

    private func describeToolActivity() -> String? {
        let name = toolName ?? "tool"

        // If there's nothing in tool_input, show the tool name.
        guard let input = toolInput, !input.isEmpty else {
            return "Using \(name)"
        }

        // Priority: known tool shapes with interesting payload.
        if let cmd = input["command"] as? String, !cmd.isEmpty {
            return truncate(cmd, maxLen: 60)
        }
        if let path = input["file_path"] as? String, !path.isEmpty {
            return "📄 \(shortPath(path))"
        }
        if let paths = input["file_paths"] as? [String], let first = paths.first, !first.isEmpty {
            return "📄 \(shortPath(first))"
        }
        if let url = input["url"] as? String, !url.isEmpty {
            return "🌐 \(shortURL(url))"
        }
        if let query = input["query"] as? String, !query.isEmpty {
            return "Search: \(truncate(query, maxLen: 50))"
        }
        // Tool-specific keys that are common.
        if input.keys.contains("messages") || input.keys.contains("model") {
            return "Thinking…"
        }
        // Fallback: show tool name + first input value if it's short.
        if let firstVal = input.values.compactMap({ $0 as? String }).first, firstVal.count < 60 {
            return "\(name): \(truncate(firstVal, maxLen: 50))"
        }

        return "Using \(name)"
    }

    // MARK: - Utils

    private func truncate(_ s: String, maxLen: Int = 55) -> String {
        let cleaned = s.replacingOccurrences(of: "\n", with: " ↵ ")
        if cleaned.count <= maxLen { return cleaned }
        return String(cleaned.prefix(maxLen - 3)) + "..."
    }

    private func shortPath(_ p: String) -> String {
        let parts = p.split(separator: "/")
        if parts.count <= 2 { return String(p) }
        return "…/\(parts.suffix(2).joined(separator: "/"))"
    }

    private func shortURL(_ url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if cleaned.count <= 40 { return cleaned }
        return String(cleaned.prefix(37)) + "..."
    }
}
