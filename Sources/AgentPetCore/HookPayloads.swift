import Foundation

/// Decodes a hook payload's `model` field into a display name. Tolerates
/// every shape we might see — `{"display_name": "...", "id": "..."}`,
/// `{"id": "..."}` only, a bare string, or the key being absent entirely —
/// and never throws, so an unexpected `model` shape can't fail the decode
/// of the surrounding hook payload.
public struct HookModelInfo: Decodable, Equatable {
    public let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case id
    }

    public init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            let name = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? nil
            let id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
            displayName = name ?? id
        } else if let single = try? decoder.singleValueContainer(),
                  let str = try? single.decode(String.self) {
            displayName = str
        } else {
            displayName = nil
        }
    }
}

/// The JSON Cursor writes to a hook's stdin (only the fields AgentPet needs).
public struct CursorHookPayload: Decodable, Equatable {
    public let conversationId: String?
    public let hookEventName: String?
    public let workspaceRoots: [String]?
    public let toolName: String?
    public let toolInput: ToolActivityInput?
    public let model: HookModelInfo?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case hookEventName = "hook_event_name"
        case workspaceRoots = "workspace_roots"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case model
    }

    public static func decode(from data: Data) -> CursorHookPayload? {
        try? JSONDecoder().decode(CursorHookPayload.self, from: data)
    }

    public func makeEvent(now: Date) -> AgentEvent? {
        guard let conversationId, let hookEventName else { return nil }
        let context = ActivityFormatter.activityMessage(
            eventName: hookEventName, sessionId: conversationId,
            toolName: toolName, toolInput: toolInput, explicitMessage: nil
        )
        return AgentEvent(
            sessionId: conversationId, agentKind: .cursor, eventName: hookEventName,
            project: workspaceRoots?.first, message: context, model: model?.displayName,
            timestamp: now
        )
    }
}

/// The JSON Windsurf (Cascade) writes to a hook's stdin.
public struct WindsurfHookPayload: Decodable, Equatable {
    public let trajectoryId: String?
    public let agentActionName: String?
    public let model: HookModelInfo?

    enum CodingKeys: String, CodingKey {
        case trajectoryId = "trajectory_id"
        case agentActionName = "agent_action_name"
        case model
    }

    public static func decode(from data: Data) -> WindsurfHookPayload? {
        try? JSONDecoder().decode(WindsurfHookPayload.self, from: data)
    }

    public func makeEvent(now: Date) -> AgentEvent? {
        guard let trajectoryId, let agentActionName else { return nil }
        return AgentEvent(
            sessionId: trajectoryId, agentKind: .windsurf, eventName: agentActionName,
            project: nil, message: nil, model: model?.displayName, timestamp: now
        )
    }
}

/// The JSON xAI's Grok Build writes to a hook's stdin. Keys are camelCase
/// (matching the property names, so no CodingKeys mapping is needed) and the
/// `hookEventName` VALUE is snake_case (e.g. `pre_tool_use`, `stop`) , the
/// StateMapper `.grok` cases match those.
public struct GrokHookPayload: Decodable, Equatable {
    public let sessionId: String?
    public let hookEventName: String?
    public let cwd: String?
    public let workspaceRoot: String?
    public let toolName: String?
    public let toolInput: ToolActivityInput?

    public static func decode(from data: Data) -> GrokHookPayload? {
        try? JSONDecoder().decode(GrokHookPayload.self, from: data)
    }

    public func makeEvent(now: Date) -> AgentEvent? {
        guard let sessionId, let hookEventName else { return nil }
        let context = ActivityFormatter.activityMessage(
            eventName: hookEventName, sessionId: sessionId,
            toolName: toolName, toolInput: toolInput, explicitMessage: nil
        )
        return AgentEvent(
            sessionId: sessionId, agentKind: .grok, eventName: hookEventName,
            project: cwd ?? workspaceRoot, message: context, timestamp: now
        )
    }
}

/// Decodes a hook's stdin payload into an `AgentEvent`, choosing the field
/// convention by agent kind. opencode sends explicit flags instead of stdin.
public enum HookPayload {
    public static func event(forAgent kind: AgentKind, stdin data: Data, now: Date) -> AgentEvent? {
        switch kind {
        case .cursor:
            return CursorHookPayload.decode(from: data)?.makeEvent(now: now)
        case .windsurf:
            return WindsurfHookPayload.decode(from: data)?.makeEvent(now: now)
        case .antigravity:
            return AntigravityHookPayload.decode(from: data)?.makeEvent(now: now)
        case .grok:
            return GrokHookPayload.decode(from: data)?.makeEvent(now: now)
        default:
            return ClaudeHookPayload.decode(from: data)?.makeEvent(now: now, kind: kind)
        }
    }
}
