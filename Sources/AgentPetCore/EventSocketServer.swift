import Foundation

public enum SocketError: Error, Equatable {
    case create(Int32)
    case bind(Int32)
    case listen(Int32)
    case pathTooLong
    case unsupportedPlatform
}

/// Listens on a Unix domain socket for newline-delimited `AgentEvent` JSON.
///
/// Clients connect, write one or more `\n`-terminated JSON events, then close.
/// `onEvent` is invoked on a background queue, once per decoded event;
/// undecodable lines are skipped.
public final class EventSocketServer: @unchecked Sendable {
    private let path: String

    #if !os(Windows)
    private var listenFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "agentpet.socket.accept")
    private var running = false
    #endif

    public init(path: String) {
        self.path = path
    }

    deinit { stop() }

    #if os(Windows)
    public func start(onEvent: @escaping @Sendable (AgentEvent) -> Void) throws {
        _ = onEvent
        throw SocketError.unsupportedPlatform
    }

    public func stop() {}
    #else
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

    private func acceptLoop(onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        while running {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                if running { continue } else { break }
            }
            handleClient(client, onEvent: onEvent)
        }
    }

    private func handleClient(_ fd: Int32, onEvent: (AgentEvent) -> Void) {
        defer { close(fd) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
        }
        Self.decodeLines(buffer, onEvent: onEvent)
    }
    #endif

    /// Drains a directory of queued event files written while the daemon was
    /// down, emitting each event and removing the file. Files are processed in
    /// name order.
    public static func drainQueue(directory: String, onEvent: (AgentEvent) -> Void) {
        let fm = FileManager.default
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else { return }
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let data = try? Data(contentsOf: url) {
                decodeLines(data, onEvent: onEvent)
            }
            try? fm.removeItem(at: url)
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
