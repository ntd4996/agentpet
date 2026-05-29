import Foundation

/// Parsed `agentpet hook` flags. Unknown flags are ignored.
public struct HookArguments: Equatable {
    public var event: String?
    public var session: String?
    public var project: String?
    public var agent: String?
    public var message: String?

    public init(event: String? = nil, session: String? = nil, project: String? = nil,
                agent: String? = nil, message: String? = nil) {
        self.event = event
        self.session = session
        self.project = project
        self.agent = agent
        self.message = message
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
            default:
                i += 1
                continue
            }
            i += 2
        }
        return result
    }

    /// Builds an `AgentEvent`, or `nil` if required flags are missing.
    /// Defaults to `.claude` since it is the only hook-supported agent in v1.
    public func makeEvent(now: Date) -> AgentEvent? {
        guard let event, let session else { return nil }
        let kind = agent.flatMap(AgentKind.init(rawValue:)) ?? .claude
        return AgentEvent(
            sessionId: session, agentKind: kind, eventName: event,
            project: project, message: message, timestamp: now
        )
    }
}
