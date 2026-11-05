import Foundation
import Network

/// Lightweight loopback HTTP server that receives agent events from remote servers/VPS
/// via SSH remote port forwarding (`ssh -R <port>:127.0.0.1:<port>`).
public final class RemoteEventServer: @unchecked Sendable {
    public let port: UInt16
    public var authTokenProvider: @Sendable () -> String
    public var setupScriptProvider: (@Sendable () -> String)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "agentpet.remote.server", qos: .utility)
    private var isRunning = false

    public init(
        port: UInt16 = 3838,
        authTokenProvider: @escaping @Sendable () -> String,
        setupScriptProvider: (@Sendable () -> String)? = nil
    ) {
        self.port = port
        self.authTokenProvider = authTokenProvider
        self.setupScriptProvider = setupScriptProvider
    }

    deinit {
        stop()
    }

    public func start(onEvent: @escaping @Sendable (AgentEvent) -> Void) throws {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        // Security: Bind strictly to loopback interface only (127.0.0.1).
        // This ensures external LAN/WAN connections are rejected and events can ONLY arrive
        // via local processes or SSH Remote Port Forwarding.
        params.requiredInterfaceType = .loopback

        let newListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection, onEvent: onEvent)
        }

        newListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case .failed(let err):
                NSLog("RemoteEventServer listener failed: \(err)")
            case .cancelled:
                break
            default:
                break
            }
        }

        newListener.start(queue: queue)
        self.listener = newListener
        self.isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        listener?.cancel()
        listener = nil
    }

    // MARK: - HTTP Connection Handling

    private func handleConnection(_ connection: NWConnection, onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        connection.start(queue: queue)
        readHTTPRequest(connection: connection) { [weak self] requestData in
            guard let self, let requestData else {
                connection.cancel()
                return
            }
            self.processRequest(requestData, connection: connection, onEvent: onEvent)
        }
    }

    private func readHTTPRequest(
        connection: NWConnection,
        accumulated: Data = Data(),
        completion: @escaping @Sendable (Data?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let error {
                NSLog("RemoteEventServer receive error: \(error)")
                completion(nil)
                return
            }
            var current = accumulated
            if let data {
                current.append(data)
            }

            // Check if we have read header end (\r\n\r\n or \n\n)
            if let headerEnd = self.findHeaderEnd(in: current) {
                let headerData = current.subdata(in: 0..<headerEnd)
                let headerString = String(decoding: headerData, as: UTF8.self)
                let contentLength = self.extractContentLength(from: headerString)
                let totalExpected = headerEnd + contentLength
                if current.count >= totalExpected {
                    completion(current)
                    return
                }
            }

            if isComplete {
                completion(current.isEmpty ? nil : current)
            } else {
                self.readHTTPRequest(connection: connection, accumulated: current, completion: completion)
            }
        }
    }

    private func findHeaderEnd(in data: Data) -> Int? {
        let patternRN: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
        let patternNN: [UInt8] = [0x0A, 0x0A]             // \n\n

        if let range = data.range(of: Data(patternRN)) {
            return range.upperBound
        }
        if let range = data.range(of: Data(patternNN)) {
            return range.upperBound
        }
        return nil
    }

    private func extractContentLength(from headers: String) -> Int {
        for line in headers.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame {
                return Int(parts[1]) ?? 0
            }
        }
        return 0
    }

    private func processRequest(_ data: Data, connection: NWConnection, onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        guard let headerEnd = findHeaderEnd(in: data) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"bad request"}"#)
            return
        }

        let headerString = String(decoding: data.subdata(in: 0..<headerEnd), as: UTF8.self)
        let bodyData = data.count > headerEnd ? data.subdata(in: headerEnd..<data.count) : Data()

        var lines = headerString.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !lines.isEmpty else {
            sendResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"empty request"}"#)
            return
        }

        let requestLine = lines.removeFirst()
        let reqParts = requestLine.split(separator: " ")
        guard reqParts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid request line"}"#)
            return
        }

        let method = String(reqParts[0]).uppercased()
        let rawURL = String(reqParts[1])
        let pathAndQuery = rawURL.split(separator: "?", maxSplits: 1)
        var path = String(pathAndQuery[0])
        if let parsed = URL(string: rawURL), let p = parsed.path.nilIfEmpty {
            path = p
        }
        if path.hasSuffix("/") && path.count > 1 {
            path = String(path.dropLast())
        }
        let queryString = pathAndQuery.count > 1 ? String(pathAndQuery[1]) : (URL(string: rawURL)?.query ?? "")

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1]
            }
        }

        // Route: GET /health or /api/ping
        if method == "GET" && (path == "/health" || path == "/api/ping") {
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: #"{"status":"ok"}"#)
            return
        }

        // Route: GET /setup.sh
        if method == "GET" && path == "/setup.sh" {
            let script = setupScriptProvider?() ?? "#!/usr/bin/env bash\necho 'AgentPet Remote Setup Script'\n"
            sendResponse(connection: connection, status: "200 OK", contentType: "text/x-shellscript", body: script)
            return
        }

        // Route: POST /api/events
        if method == "POST" && path == "/api/events" {
            // Verify Bearer Token
            let expectedToken = authTokenProvider().trimmingCharacters(in: .whitespacesAndNewlines)
            if !expectedToken.isEmpty {
                let authHeader = headers["authorization"] ?? ""
                let prefix = "Bearer "
                let providedToken = authHeader.hasPrefix(prefix) ? String(authHeader.dropFirst(prefix.count)) : authHeader
                if providedToken.trimmingCharacters(in: .whitespacesAndNewlines) != expectedToken {
                    sendResponse(
                        connection: connection,
                        status: "401 Unauthorized",
                        contentType: "application/json",
                        body: #"{"error":"unauthorized","message":"Invalid or missing Bearer token"}"#
                    )
                    return
                }
            }

            let queryParams = parseQuery(queryString)
            let host = queryParams["host"] ?? headers["x-agentpet-host"]
            let agentParam = queryParams["agent"] ?? headers["x-agentpet-agent"]

            let now = Date()
            if let event = decodeEvent(from: bodyData, agentHint: agentParam, host: host, now: now) {
                onEvent(event)
                sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: #"{"ok":true}"#)
            } else {
                sendResponse(connection: connection, status: "422 Unprocessable Entity", contentType: "application/json", body: #"{"error":"could not decode event"}"#)
            }
            return
        }

        sendResponse(connection: connection, status: "404 Not Found", contentType: "application/json", body: #"{"error":"not found"}"#)
    }

    private func decodeEvent(from data: Data, agentHint: String?, host: String?, now: Date) -> AgentEvent? {
        let hostClean = host?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        // 1. Try decoding as direct AgentEvent JSON
        if let direct = try? EventCoding.decoder.decode(AgentEvent.self, from: data) {
            var e = direct
            if e.host == nil { e.host = hostClean }
            return e
        }

        // 2. Try generic JSON dictionary
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            // Check if it specifies agent and event directly (Generic Webhook)
            let agentString = (json["agent"] as? String) ?? agentHint ?? "generic"
            let kind = AgentKind(rawValue: agentString) ?? .unknown
            let eventName = (json["event"] as? String) ?? (json["eventName"] as? String) ?? "working"
            let sessionId = (json["sessionId"] as? String) ?? (json["session"] as? String) ?? "remote-\(UUID().uuidString.prefix(8))"
            let project = json["project"] as? String
            let message = json["message"] as? String
            let model = json["model"] as? String
            let eventHost = (json["host"] as? String)?.nilIfEmpty ?? hostClean

            // If it's an agent-native hook payload (e.g. Claude Code hook payload JSON),
            // try decoding through HookPayload first
            if let parsedKind = AgentKind(rawValue: agentString), parsedKind != .unknown {
                if var hookEvent = HookPayload.event(forAgent: parsedKind, stdin: data, now: now) {
                    if hookEvent.host == nil { hookEvent.host = eventHost }
                    return hookEvent
                }
            }

            return AgentEvent(
                sessionId: sessionId,
                agentKind: kind,
                eventName: eventName,
                project: project,
                message: message,
                model: model,
                agentName: kind == .unknown ? agentString : nil,
                host: eventHost,
                timestamp: now
            )
        }

        // 3. Fallback: If agentHint is present and body is stdin payload
        if let agentHint, let kind = AgentKind(rawValue: agentHint) {
            if var hookEvent = HookPayload.event(forAgent: kind, stdin: data, now: now) {
                if hookEvent.host == nil { hookEvent.host = hostClean }
                return hookEvent
            }
        }

        return nil
    }

    private func parseQuery(_ query: String) -> [String: String] {
        var dict: [String: String] = [:]
        for item in query.components(separatedBy: "&") where !item.isEmpty {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 {
                let key = pair[0].removingPercentEncoding ?? pair[0]
                let val = pair[1].removingPercentEncoding ?? pair[1]
                dict[key] = val
            } else if pair.count == 1 {
                let key = pair[0].removingPercentEncoding ?? pair[0]
                dict[key] = ""
            }
        }
        return dict
    }

    private func sendResponse(
        connection: NWConnection,
        status: String,
        contentType: String = "text/plain",
        body: String
    ) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType); charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var fullData = Data(header.utf8)
        fullData.append(bodyData)

        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
