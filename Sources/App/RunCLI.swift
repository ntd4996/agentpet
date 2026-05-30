import AgentPetCore
import Foundation

/// `agentpet run [--session id] [--project path] [--agent kind] -- <command...>`
///
/// Launches any CLI agent, marks the session `working` while it runs (with a
/// heartbeat so it isn't pruned as stale) and `done` when it exits. Works with
/// any command, no per-agent hooks required.
enum RunCLI {
    static func run(arguments: [String]) -> Never {
        let parsed = RunArguments.parse(arguments)
        guard !parsed.command.isEmpty else {
            FileHandle.standardError.write(Data(
                "usage: agentpet run [--session id] [--project path] [--agent kind] -- <command...>\n".utf8))
            exit(2)
        }

        let session = parsed.session ?? "run-\(UUID().uuidString.prefix(8))"
        let project = parsed.project ?? FileManager.default.currentDirectoryPath
        let kind = parsed.agent.flatMap(AgentKind.init(rawValue:)) ?? .cli

        func emit(_ state: String) {
            let event = AgentEvent(sessionId: session, agentKind: kind, eventName: state,
                                   project: project, message: nil, timestamp: Date())
            EventSender.send(event, socketPath: AgentPetPaths.socketPath, queueDir: AgentPetPaths.queueDir)
        }

        emit("working")

        // Heartbeat so a long-running agent's session stays fresh.
        let heartbeat = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        heartbeat.schedule(deadline: .now() + 60, repeating: 60)
        heartbeat.setEventHandler { emit("working") }
        heartbeat.resume()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = parsed.command   // env resolves the program from PATH

        do {
            try process.run()
        } catch {
            heartbeat.cancel()
            emit("done")
            FileHandle.standardError.write(Data("agentpet run: failed to launch \(parsed.command.first ?? "")\n".utf8))
            exit(126)
        }

        // Survive Ctrl-C so the child (which already has default handlers) gets
        // the signal, then we still report `done`. Set after spawn so the child
        // doesn't inherit SIG_IGN.
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        process.waitUntilExit()
        heartbeat.cancel()
        emit("done")
        exit(process.terminationStatus)
    }
}
