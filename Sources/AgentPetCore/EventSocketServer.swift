import Foundation

public enum SocketError: Error, Equatable {
    case create(Int32)
    case bind(Int32)
    case listen(Int32)
    case pathTooLong
}

/// Listens on a Unix domain socket for newline-delimited `AgentEvent` JSON.
///
/// Clients connect, write one or more `\n`-terminated JSON events, then close.
/// `onEvent` is invoked on a background queue, once per decoded event;
/// undecodable lines are skipped.
public final class EventSocketServer: @unchecked Sendable {
    private let path: String
    private var listenFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "agentpet.socket.accept")
    private var running = false

    public init(path: String) {
        self.path = path
    }

    deinit { stop() }

    public func start(onEvent: @escaping @Sendable (AgentEvent) -> Void) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.create(errno) }

        unlink(path)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else {
            close(fd)
            throw SocketError.pathTooLong
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (i, byte) in pathBytes.enumerated() {
                    dst[i] = CChar(bitPattern: byte)
                }
                dst[pathBytes.count] = 0
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else { close(fd); throw SocketError.bind(errno) }
        guard listen(fd, 16) == 0 else { close(fd); throw SocketError.listen(errno) }

        listenFD = fd
        running = true
        acceptQueue.async { [weak self] in self?.acceptLoop(onEvent: onEvent) }
    }

    public func stop() {
        running = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(path)
    }

    /// What the accept loop should do after `accept()` returns an error.
    enum AcceptErrorAction: Equatable {
        /// Transient, expected error (interrupted syscall, client aborted) —
        /// loop again right away.
        case retryImmediately
        /// Recoverable resource pressure (fd exhaustion) or an unknown error —
        /// sleep briefly before retrying so a *persistent* error can't spin a
        /// CPU core at 100%.
        case backoff
        /// The listen socket itself is gone (closed/invalid) — retrying can
        /// only ever fail again, so stop the loop instead of spinning.
        case stop
    }

    /// Classifies an `accept()` errno. The default is `.backoff`, never
    /// `.retryImmediately`: an unrecognised error must not fall through to a
    /// tight, CPU-pegging retry loop.
    static func acceptErrorAction(errno code: Int32) -> AcceptErrorAction {
        switch code {
        case EINTR, ECONNABORTED:
            return .retryImmediately
        case EBADF, EINVAL, ENOTSOCK:
            return .stop
        default:
            return .backoff
        }
    }

    private func acceptLoop(onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        while running {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                let err = errno
                guard running else { break }
                switch Self.acceptErrorAction(errno: err) {
                case .retryImmediately:
                    continue
                case .backoff:
                    usleep(50_000)   // 50ms — cap a persistent error at ~20 retries/sec
                    continue
                case .stop:
                    return
                }
            }
            handleClient(client, onEvent: onEvent)
        }
    }

    // Assumes one event per connection: if the first line decodes to an
    // approval request, its fd is handed off to the registry (not closed here).
    private func handleClient(_ fd: Int32, onEvent: (AgentEvent) -> Void) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.firstIndex(of: 0x0A) == nil {
            guard Self.readMore(fd: fd, into: &buffer, chunk: &chunk) else { break }
        }
        if let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newlineIndex]
            if let event = try? EventCoding.decoder.decode(AgentEvent.self, from: Data(line)),
               let requestId = event.approvalRequestId {
                PendingApprovalRegistry.shared.register(requestId: requestId, fd: fd)
                onEvent(event)
                return
            }
        }
        while Self.readMore(fd: fd, into: &buffer, chunk: &chunk) {}
        close(fd)
        Self.decodeLines(buffer, onEvent: onEvent)
    }

    /// Reads one chunk from `fd` into `buffer`. Returns `false` at EOF/error.
    private static func readMore(fd: Int32, into buffer: inout Data, chunk: inout [UInt8]) -> Bool {
        let n = read(fd, &chunk, chunk.count)
        guard n > 0 else { return false }
        buffer.append(contentsOf: chunk[0..<n])
        return true
    }

    /// Drains a directory of queued event files written while the daemon was
    /// down, emitting each event and removing the file. Files are processed in
    /// name order.
    public static func drainQueue(directory: String, onEvent: (AgentEvent) -> Void) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return }
        for name in names.sorted() {
            let full = (directory as NSString).appendingPathComponent(name)
            if let data = fm.contents(atPath: full) {
                decodeLines(data, onEvent: onEvent)
            }
            try? fm.removeItem(atPath: full)
        }
    }

    static func decodeLines(_ data: Data, onEvent: (AgentEvent) -> Void) {
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            if let event = try? EventCoding.decoder.decode(AgentEvent.self, from: Data(line)) {
                onEvent(event)
            }
        }
    }
}
