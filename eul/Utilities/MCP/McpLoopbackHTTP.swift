import Foundation
import MCP
import Network

actor McpLoopbackHTTP {
    private struct Session {
        let server: Server
        let transport: StatefulHTTPServerTransport
    }

    private let aggregator: McpAggregator
    private var listenPort = McpPaths.defaultPort
    private var listener: NWListener?
    private var sessions: [String: Session] = [:]
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(aggregator: McpAggregator) {
        self.aggregator = aggregator
    }

    func start(port: Int) async throws {
        try await stop()
        listenPort = port
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: UInt16(port))!)
        listener.newConnectionHandler = { connection in
            Task { await self.accept(connection) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var resumed = false
            func resumeOnce(_ body: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                body()
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce { continuation.resume() }
                case let .failed(error):
                    resumeOnce { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue(label: "eul2.mcp.http"))
        }
        self.listener = listener
    }

    func stop() async {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        sessions.removeAll()
    }

    func notifyToolsListChanged() async {
        let live = Array(sessions.values)
        for session in live {
            do {
                try await session.server.notify(ToolListChangedNotification.message())
            } catch {}
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { state in
            if case .failed = state {
                Task { await self.drop(id) }
            }
        }
        connection.start(queue: DispatchQueue(label: "eul2.mcp.conn.\(id.hashValue)"))
        Task {
            await self.serve(connection)
            await self.drop(id)
        }
    }

    private func drop(_ id: ObjectIdentifier) {
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
    }

    private func serve(_ connection: NWConnection) async {
        do {
            while true {
                let request = try await readHTTPRequest(from: connection)
                let path = request.path ?? "/"
                if path != "/mcp", !path.hasPrefix("/mcp?") {
                    try await writeHTTP(connection, status: 404, headers: ["Content-Type": "text/plain"], body: Data("not found".utf8))
                    return
                }
                let response = await route(request)
                try await write(response, to: connection)
                if case .stream = response {
                    return
                }
                if request.header("Connection")?.lowercased() == "close" {
                    return
                }
            }
        } catch {
            connection.cancel()
        }
    }

    private func route(_ request: HTTPRequest) async -> HTTPResponse {
        let sessionHeader = request.header(HTTPHeaderName.sessionID)
        if let sessionHeader, let session = sessions[sessionHeader] {
            return await session.transport.handleRequest(request)
        }
        if request.method.uppercased() == "POST", isInitialize(request.body) {
            let session = await makeSession()
            let response = await session.transport.handleRequest(request)
            if let sid = response.headers[HTTPHeaderName.sessionID] ?? response.headers.first(where: { $0.key.lowercased() == HTTPHeaderName.sessionID.lowercased() })?.value {
                sessions[sid] = session
            }
            return response
        }
        return .error(statusCode: 400, .internalError("missing session"))
    }

    private func makeSession() async -> Session {
        let transport = StatefulHTTPServerTransport()
        let server = Server(
            name: "eul2",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2.0",
            capabilities: .init(
                prompts: .init(listChanged: true),
                resources: .init(listChanged: true),
                tools: .init(listChanged: true)
            )
        )
        let aggregator = self.aggregator
        await server.withMethodHandler(ListTools.self) { _ in
            let tools = try await aggregator.listTools()
            return .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { params in
            try await aggregator.callTool(name: params.name, arguments: params.arguments)
        }
        await server.withMethodHandler(ListResources.self) { _ in
            let resources = try await aggregator.listResources()
            return .init(resources: resources, nextCursor: nil)
        }
        await server.withMethodHandler(ReadResource.self) { params in
            try await aggregator.readResource(uri: params.uri)
        }
        await server.withMethodHandler(ListPrompts.self) { _ in
            let prompts = try await aggregator.listPrompts()
            return .init(prompts: prompts, nextCursor: nil)
        }
        await server.withMethodHandler(GetPrompt.self) { params in
            try await aggregator.getPrompt(name: params.name, arguments: params.arguments)
        }
        try? await server.start(transport: transport)
        return Session(server: server, transport: transport)
    }

    private func isInitialize(_ body: Data?) -> Bool {
        guard
            let body,
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let method = json["method"] as? String
        else {
            return false
        }
        return method == "initialize"
    }

    private func readHTTPRequest(from connection: NWConnection) async throws -> HTTPRequest {
        let separator = Data("\r\n\r\n".utf8)
        var buffer = Data()
        while buffer.range(of: separator) == nil {
            buffer.append(try await receive(connection))
            if buffer.count > 1_000_000 {
                throw MCPError.internalError("headers too large")
            }
        }
        guard let headerEnd = buffer.range(of: separator) else {
            throw MCPError.internalError("bad request")
        }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
        var leftover = buffer.subdata(in: headerEnd.upperBound..<buffer.endIndex)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw MCPError.internalError("bad headers")
        }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            throw MCPError.internalError("empty request")
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            throw MCPError.internalError("bad request line")
        }
        let method = String(parts[0])
        let path = String(parts[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        headers["Origin"] = "http://127.0.0.1:\(listenPort)"
        if headers["Accept"] == nil {
            headers["Accept"] = "application/json, text/event-stream"
        }
        let length = Int(headers["Content-Length"] ?? headers["content-length"] ?? "0") ?? 0
        while leftover.count < length {
            leftover.append(try await receive(connection))
        }
        let body = length > 0 ? leftover.prefix(length) : Data()
        return HTTPRequest(method: method, headers: headers, body: Data(body), path: path)
    }

    private func receive(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: MCPError.internalError("connection closed"))
                }
            }
        }
    }

    private func write(_ response: HTTPResponse, to connection: NWConnection) async throws {
        var headers = response.headers
        switch response {
        case let .stream(stream, _):
            if headers[HTTPHeaderName.contentType] == nil {
                headers[HTTPHeaderName.contentType] = "text/event-stream"
            }
            headers["Cache-Control"] = headers["Cache-Control"] ?? "no-cache"
            headers["Connection"] = "keep-alive"
            try await writeHTTP(connection, status: 200, headers: headers, body: nil)
            for try await chunk in stream {
                try await send(connection, chunk)
            }
        default:
            let body = response.bodyData ?? Data()
            headers["Content-Length"] = "\(body.count)"
            if headers[HTTPHeaderName.contentType] == nil, !body.isEmpty {
                headers[HTTPHeaderName.contentType] = "application/json"
            }
            try await writeHTTP(connection, status: response.statusCode, headers: headers, body: body)
        }
    }

    private func writeHTTP(_ connection: NWConnection, status: Int, headers: [String: String], body: Data?) async throws {
        var text = "HTTP/1.1 \(status) \(reason(status))\r\n"
        for (key, value) in headers {
            text += "\(key): \(value)\r\n"
        }
        text += "\r\n"
        var data = Data(text.utf8)
        if let body {
            data.append(body)
        }
        try await send(connection, data)
    }

    private func send(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        default: return "Error"
        }
    }
}
