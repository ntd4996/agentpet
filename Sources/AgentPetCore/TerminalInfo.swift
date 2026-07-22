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
    /// run with stdio piped, so `isatty` on 0/1/2 usually fails; the reliable
    /// source is `/dev/tty`, which resolves to the inherited controlling tty.
    static func controllingTTY() -> String? {
        for fd in Int32(0)...2 where isatty(fd) != 0 {
            if let name = ttyname(fd) { return String(cString: name) }
        }
        let fd = open("/dev/tty", O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard let name = ttyname(fd) else { return nil }
        return String(cString: name)
    }
}
