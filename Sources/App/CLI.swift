import AgentPetCore
import Foundation

/// CLI helper invoked by agent hooks: `agentpet hook --event ... --session ...`.
enum HookCLI {
    static func run(arguments: [String]) -> Never {
        let parsed = HookArguments.parse(arguments)
        guard let event = parsed.makeEvent(now: Date()) else {
            FileHandle.standardError.write(Data(
                "usage: agentpet hook --event <name> --session <id> [--project <path>] [--agent <kind>] [--message <text>]\n".utf8
            ))
            exit(2)
        }
        EventSender.send(event, socketPath: AgentPetPaths.socketPath, queueDir: AgentPetPaths.queueDir)
        exit(0)
    }
}
