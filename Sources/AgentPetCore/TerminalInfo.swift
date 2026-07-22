import Foundation

/// Captures which terminal the CLI helper runs inside, so the daemon can later
/// bring that exact window/tab to the front when the user clicks a bubble row.
public enum TerminalInfo {
    /// `TERM_PROGRAM` + controlling TTY, read from the current process. Both are
    /// `nil` when there's no terminal (e.g. an agent launched from CI), which
    /// leaves the click-to-focus affordance disabled for that session.
    public static func capture(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> (program: String?, tty: String?) {
        let program = env["TERM_PROGRAM"].flatMap { $0.isEmpty ? nil : $0 }
        return (program, controllingTTY())
    }

    /// The device path of the controlling terminal (e.g. `/dev/ttys003`). Hooks
    /// run with stdio piped, so `isatty` on 0/1/2 usually fails. `/dev/tty` works
    /// when the hook keeps the terminal's session; if the agent detaches it
    /// (new session), we walk up the parent chain — the agent process (e.g.
    /// `claude`) still owns the tty — and read its controlling terminal.
    static func controllingTTY() -> String? {
        for fd in Int32(0)...2 where isatty(fd) != 0 {
            if let name = ttyname(fd) { return String(cString: name) }
        }
        if let fdTTY = ttyViaDevTTY() { return fdTTY }
        return ttyViaAncestors()
    }

    private static func ttyViaDevTTY() -> String? {
        let fd = open("/dev/tty", O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard let name = ttyname(fd) else { return nil }
        return String(cString: name)
    }

    /// Walks up the process tree asking `ps` for each ancestor's controlling
    /// terminal, returning the first real one as a `/dev/ttysNNN` path.
    private static func ttyViaAncestors() -> String? {
        var pid = getppid()
        for _ in 0..<10 {
            guard pid > 1 else { break }
            if let tty = psField("tty", pid: pid),
               tty != "??", tty != "-", !tty.isEmpty {
                return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
            }
            guard let ppidStr = psField("ppid", pid: pid), let ppid = Int32(ppidStr) else { break }
            pid = ppid
        }
        return nil
    }

    private static func psField(_ field: String, pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "\(field)=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
