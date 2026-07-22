import AgentPetCore
import Foundation

/// CLI helper invoked by agent hooks: `agentpet hook --event ... --session ...`.
enum HookCLI {
    static func run(arguments: [String]) -> Never {
        // Explicit flags win (used by opencode's plugin and the run wrapper);
        // otherwise fall back to the agent's hook payload on stdin, decoded with
        // that agent's field convention. `--agent` selects the agent.
        let now = Date()
        let parsed = HookArguments.parse(arguments)
        let kind = parsed.agent.flatMap(AgentKind.init(rawValue:)) ?? .claude
        var event = parsed.makeEvent(now: now)
            ?? HookPayload.event(forAgent: kind, stdin: FileHandle.standardInput.readDataToEndOfFile(), now: now)

        // Tag the event with the terminal we're running in, so a click on the
        // session's bubble row can focus that exact window/tab later.
        let terminal = TerminalInfo.capture()
        event?.terminalProgram = terminal.program
        event?.terminalTTY = terminal.tty

        guard let event else {
            FileHandle.standardError.write(Data(
                "usage: agentpet hook --event <name> --session <id> [--project <path>] [--agent <kind>] [--message <text>]\n         or pipe a Claude Code hook JSON payload on stdin\n".utf8
            ))
            exit(2)
        }
        // Approval-gated events must reply with the hook's permission decision on
        // stdout so Claude Code can allow/deny the tool call synchronously.
        if event.approvalRequestId != nil {
            let decision = EventSender.sendAndAwaitReply(event, socketPath: AgentPetPaths.socketPath)
            print(ApprovalHookResponse.json(for: decision))
            exit(0)
        }
        EventSender.send(event, socketPath: AgentPetPaths.socketPath, queueDir: AgentPetPaths.queueDir)
        exit(0)
    }
}
