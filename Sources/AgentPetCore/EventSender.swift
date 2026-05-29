import Foundation

/// Sends an `AgentEvent` to the daemon over the Unix socket, falling back to a
/// queue file when the daemon is not running so no event is lost.
public enum EventSender {
    /// Returns `true` if delivered over the socket, `false` if queued to disk.
    @discardableResult
    public static func send(_ event: AgentEvent, socketPath: String, queueDir: String) -> Bool {
        guard let line = try? encodeLine(event) else { return false }
        if writeToSocket(line, path: socketPath) {
            return true
        }
        writeToQueue(line, dir: queueDir)
        return false
    }

    static func encodeLine(_ event: AgentEvent) throws -> Data {
        var data = try EventCoding.encoder.encode(event)
        data.append(0x0A)
        return data
    }

    static func writeToSocket(_ data: Data, path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (i, b) in bytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[bytes.count] = 0
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard connected == 0 else { return false }

        return data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }

    static func writeToQueue(_ data: Data, dir: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let name = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).json"
        let full = (dir as NSString).appendingPathComponent(name)
        try? data.write(to: URL(fileURLWithPath: full))
    }
}
