import Foundation

/// Parsed `agentpet run [flags] -- <command...>` arguments.
public struct RunArguments: Equatable {
    public var session: String?
    public var project: String?
    public var agent: String?
    public var command: [String]

    public init(session: String? = nil, project: String? = nil, agent: String? = nil, command: [String] = []) {
        self.session = session
        self.project = project
        self.agent = agent
        self.command = command
    }

    /// Flags appear before `--`; everything after `--` is the command to run.
    public static func parse(_ args: [String]) -> RunArguments {
        var result = RunArguments()
        var i = 0
        while i < args.count {
            let flag = args[i]
            if flag == "--" {
                result.command = Array(args[(i + 1)...])
                break
            }
            let value = i + 1 < args.count ? args[i + 1] : nil
            switch flag {
            case "--session": result.session = value; i += 2
            case "--project": result.project = value; i += 2
            case "--agent": result.agent = value; i += 2
            default: i += 1
            }
        }
        return result
    }
}
