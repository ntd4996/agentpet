import Foundation

public struct AntigravityToolArgs: Decodable, Equatable {
    public let toolSummary: String?
    public let commandLine: String?
    public let path: String?
    public let query: String?
    public let pattern: String?
    public let role: String?
    public let prompt: String?
    public let url: String?

    public init(
        toolSummary: String? = nil,
        commandLine: String? = nil,
        path: String? = nil,
        query: String? = nil,
        pattern: String? = nil,
        role: String? = nil,
        prompt: String? = nil,
        url: String? = nil
    ) {
        self.toolSummary = toolSummary
        self.commandLine = commandLine
        self.path = path
        self.query = query
        self.pattern = pattern
        self.role = role
        self.prompt = prompt
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        struct DynamicCodingKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
            init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
        }

        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        func findString(_ candidates: [String]) -> String? {
            for c in candidates {
                if let key = DynamicCodingKey(stringValue: c),
                   let val = try? container.decodeIfPresent(String.self, forKey: key) {
                    let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }

        self.toolSummary = findString(["toolSummary", "tool_summary", "summary", "description"])
        self.commandLine = findString(["CommandLine", "command_line", "command", "cmd"])
        self.path = findString(["Path", "path", "filePath", "file_path"])
        self.query = findString(["query", "q"])
        self.pattern = findString(["pattern"])
        self.role = findString(["Role", "role", "TypeName", "typeName", "subagentType", "subagent_type"])
        self.prompt = findString(["Prompt", "prompt"])
        self.url = findString(["url", "uri", "URL", "URI"])
    }

    public func toToolActivityInput() -> ToolActivityInput {
        ToolActivityInput(
            filePath: path,
            command: commandLine,
            description: toolSummary,
            pattern: pattern,
            query: query,
            url: url,
            prompt: prompt,
            subagentType: role
        )
    }
}

/// Decodes an Antigravity hook payload (camelCase JSON on stdin). Antigravity
/// does NOT send an event name, so the normalised state is inferred from which
/// discriminator fields are present, per the official hook schema:
///   • Stop          → `terminationReason` / `fullyIdle`
///   • PreToolUse    → `toolCall`
///   • Pre/PostInvocation → `invocationNum`
///   • PostToolUse   → `stepIdx`
/// The resulting `eventName` is the state's raw value, which `StateMapper`'s
/// generic decoder maps straight back to the state.
public struct AntigravityHookPayload: Decodable, Equatable {
    public let conversationId: String?
    public let workspacePaths: [String]?
    public let transcriptPath: String?
    public let toolCall: ToolCall?
    public let terminationReason: String?
    public let fullyIdle: Bool?
    public let invocationNum: Int?
    public let stepIdx: Int?
    public let model: HookModelInfo?

    public struct ToolCall: Decodable, Equatable {
        public let name: String?
        public let args: AntigravityToolArgs?

        private enum CodingKeys: String, CodingKey {
            case name, args, arguments, parameters
        }

        public init(name: String?, args: AntigravityToolArgs? = nil) {
            self.name = name
            self.args = args
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            args = (try? container.decodeIfPresent(AntigravityToolArgs.self, forKey: .args))
                ?? (try? container.decodeIfPresent(AntigravityToolArgs.self, forKey: .arguments))
                ?? (try? container.decodeIfPresent(AntigravityToolArgs.self, forKey: .parameters))
        }
    }

    public static func decode(from data: Data) -> AntigravityHookPayload? {
        try? JSONDecoder().decode(AntigravityHookPayload.self, from: data)
    }

    public func makeEvent(now: Date) -> AgentEvent? {
        guard let conversationId, !conversationId.isEmpty else { return nil }
        let state: AgentState
        if terminationReason != nil || fullyIdle != nil {
            state = .done
        } else if toolCall != nil || invocationNum != nil || stepIdx != nil {
            state = .working
        } else {
            return nil
        }
        let toolInput = toolCall?.args?.toToolActivityInput()
        let context = ActivityFormatter.activityMessage(
            eventName: state.rawValue, sessionId: conversationId,
            toolName: toolCall?.name, toolInput: toolInput, explicitMessage: nil
        ) ?? toolCall?.args?.toolSummary ?? toolCall?.name.map { "Using \($0)" }
        return AgentEvent(
            sessionId: conversationId,
            agentKind: .antigravity,
            eventName: state.rawValue,
            project: workspacePaths?.first(where: { !$0.isEmpty }),
            message: context,
            model: model?.displayName,
            transcriptPath: transcriptPath,
            timestamp: now
        )
    }
}
