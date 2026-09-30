import AgentPetCore
import Foundation

/// Opt-in resize trace for `scripts/bubble_selftest.py`. Launch the app with
/// `AGENTPET_METRICS=1` and every measured content size and applied window
/// size is appended to `~/.agentpet/metrics.log` as
/// `<uptime> content|window w=<W> h=<H>`. Off by default: nothing is opened
/// or written unless the env var is set.
@MainActor
enum ResizeMetrics {
    private static let handle: FileHandle? = {
        guard ProcessInfo.processInfo.environment["AGENTPET_METRICS"] == "1" else { return nil }
        let path = AgentPetPaths.baseDir + "/metrics.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static func log(_ kind: String, _ size: CGSize) {
        guard let handle else { return }
        let line = String(format: "%.4f %@ w=%d h=%d\n", ProcessInfo.processInfo.systemUptime,
                          kind, Int(size.width.rounded()), Int(size.height.rounded()))
        handle.write(Data(line.utf8))
    }
}
