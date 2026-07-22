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
        guard let fd = connectedSocket(path: path) else { return false }
        defer { close(fd) }
        return writeAll(data, fd: fd)
    }

    static func writeToQueue(_ data: Data, dir: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let name = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).json"
        let full = (dir as NSString).appendingPathComponent(name)
        try? data.write(to: URL(fileURLWithPath: full))
    }

    /// Sends an approval-gated event and blocks for the daemon's decision,
    /// falling back to `.ask` on connect/write/timeout/decode failure.
    public static func sendAndAwaitReply(
        _ event: AgentEvent, socketPath: String, timeout: TimeInterval = ApprovalTimeouts.client
    ) -> ApprovalDecision {
        guard let line = try? encodeLine(event), let fd = connectedSocket(path: socketPath) else {
            return .ask
        }
        defer { close(fd) }
        guard writeAll(line, fd: fd) else { return .ask }

        var tv = timeval(
            tv_sec: Int(timeout), tv_usec: Int32(timeout.truncatingRemainder(dividingBy: 1) * 1_000_000)
        )
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
            return .ask
        }

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 256)
        while !buffer.contains(0x0A) {
            guard Date() < deadline else { return .ask }
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return .ask }
            buffer.append(contentsOf: chunk[0..<n])
        }
        guard let newlineIndex = buffer.firstIndex(of: 0x0A),
              let reply = try? EventCoding.decoder.decode(ApprovalReply.self, from: Data(buffer[..<newlineIndex]))
        else { return .ask }
        return reply.decision
    }

    private static func connectedSocket(path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { close(fd); return nil }
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
        guard connected == 0 else { close(fd); return nil }
        // SO_NOSIGPIPE: a write after the daemon died must not SIGPIPE the CLI.
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    static func writeAll(_ data: Data, fd: Int32) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }
}

private struct ApprovalReply: Decodable {
    let decision: ApprovalDecision
}
