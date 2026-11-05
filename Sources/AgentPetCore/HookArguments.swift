import Foundation

/// Parsed `agentpet hook` flags. Unknown flags are ignored.
public struct HookArguments: Equatable {
    public var event: String?
    public var session: String?
    public var project: String?
    public var agent: String?
    public var message: String?
    public var transcript: String?
    public var model: String?

    public init(event: String? = nil, session: String? = nil, project: String? = nil,
                agent: String? = nil, message: String? = nil, transcript: String? = nil,
                model: String? = nil) {
        self.event = event
        self.session = session
        self.project = project
        self.agent = agent
        self.message = message
        self.transcript = transcript
        self.model = model
    }

    /// Parses `--key value` pairs from the argument list.
    public static func parse(_ args: [String]) -> HookArguments {
        var result = HookArguments()
        var i = 0
        while i < args.count {
            let flag = args[i]
            let value = i + 1 < args.count ? args[i + 1] : nil
            switch flag {
            case "--event": result.event = value
            case "--session": result.session = value
            case "--project": result.project = value
            case "--agent": result.agent = value
            case "--message": result.message = value
            case "--transcript": result.transcript = value
            case "--model": result.model = value
            default:
                i += 1
                continue
            }
            i += 2
        }
        return result
    }

    /// Builds an `AgentEvent`, or `nil` if required flags are missing.
    /// A missing `--agent` still defaults to `.claude` (Claude's hooks omit the
    /// flag). A recognized name maps to its kind. An unrecognized name maps to
    /// `.unknown` but keeps its raw name, so custom agents neither masquerade as
    /// Claude nor collapse into one shared row (issue #56).
    public func makeEvent(now: Date) -> AgentEvent? {
        guard let event, let session else { return nil }
        let kind: AgentKind
        let name: String?
        if let agent {
            if let known = AgentKind(rawValue: agent) { kind = known; name = nil }
            else { kind = .unknown; name = agent }
        } else {
            kind = .claude; name = nil
        }
        return AgentEvent(
            sessionId: session, agentKind: kind, eventName: event,
            project: project, message: message, model: model,
            transcriptPath: transcript, agentName: name, timestamp: now
        )
    }
}
