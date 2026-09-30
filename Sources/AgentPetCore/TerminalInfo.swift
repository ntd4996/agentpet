import Foundation

/// Captures which terminal the CLI helper runs inside, so the daemon can later
/// bring that exact window/tab to the front when the user clicks a bubble row.
public enum TerminalInfo {
    public struct Captured: Sendable, Equatable {
        public let program: String?
        public let tty: String?
        /// A deep link that focuses the exact tab/pane, when the terminal offers
        /// one (Warp sets `WARP_FOCUS_URL`, e.g. `warp://session/<uuid>`).
        public let focusURL: String?
    }

    /// Terminal identifiers read from the current process. All `nil` when there's
    /// no terminal (e.g. an agent launched from CI), which leaves the
    /// click-to-focus affordance disabled for that session.
    public static func capture(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Captured {
        func nonEmpty(_ key: String) -> String? { env[key].flatMap { $0.isEmpty ? nil : $0 } }
        return Captured(
            program: nonEmpty("TERM_PROGRAM"),
            tty: controllingTTY(),
            focusURL: nonEmpty("WARP_FOCUS_URL")
        )
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

    /// Walks up the process tree reading each ancestor's controlling terminal,
    /// returning the first real one as a `/dev/ttysNNN` path.
    private static func ttyViaAncestors() -> String? {
        var pid = getppid()
        for _ in 0..<10 {
            guard pid > 1, let info = procInfo(pid: pid) else { break }
            if let tty = info.tty { return tty }
            pid = info.ppid
        }
        return nil
    }

    /// Reads `pid`'s parent and controlling terminal via `sysctl`, the same
    /// source `ps` uses. Spawning `/bin/ps` instead cost ~70 ms per call, which
    /// made every hook without a tty (e.g. under jcode) take ~0.3 s longer.
    static func procInfo(pid: Int32) -> (ppid: Int32, tty: String?)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let dev = info.kp_eproc.e_tdev
        // NODEV (-1) means no controlling terminal (`ps` shows "??").
        guard dev != -1, let name = devname(dev, S_IFCHR) else {
            return (info.kp_eproc.e_ppid, nil)
        }
        return (info.kp_eproc.e_ppid, "/dev/" + String(cString: name))
    }
}
