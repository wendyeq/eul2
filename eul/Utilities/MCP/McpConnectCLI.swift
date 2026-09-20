import Foundation
import MCP
import Network

enum McpConnectCLI {
    static func run() {
        var code: Int32 = 1
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            code = await runAsync()
            semaphore.signal()
        }
        semaphore.wait()
        exit(code)
    }

    private static func runAsync() async -> Int32 {
        let catalog = McpCatalogStore.load()
        let port = catalog.listenPort
        let urlString = "http://127.0.0.1:\(port)/mcp"
        guard let url = URL(string: urlString) else {
            fputs("eul mcp-connect: bad hub url\n", stderr)
            return 1
        }
        guard await probe(host: "127.0.0.1", port: UInt16(port), timeout: 2) else {
            fputs("eul mcp-connect: hub not listening on \(urlString)\n", stderr)
            return 1
        }
        do {
            let client = Client(name: "eul-mcp-connect", version: "2.2.0")
            let transport = HTTPClientTransport(endpoint: url, streaming: true)
            _ = try await client.connect(transport: transport)

            let server = Server(
                name: "eul2",
                version: "2.2.0",
                capabilities: .init(
                    prompts: .init(listChanged: true),
                    resources: .init(listChanged: true),
                    tools: .init(listChanged: true)
                )
            )
            await client.onNotification(ToolListChangedNotification.self) { _ in
                try? await server.notify(ToolListChangedNotification.message())
            }
            await server.withMethodHandler(ListTools.self) { _ in
                let (tools, next) = try await client.listTools()
                return .init(tools: tools, nextCursor: next)
            }
            await server.withMethodHandler(CallTool.self) { params in
                let (content, isError) = try await client.callTool(name: params.name, arguments: params.arguments)
                return .init(content: content, isError: isError)
            }
            await server.withMethodHandler(ListResources.self) { _ in
                let (resources, next) = try await client.listResources()
                return .init(resources: resources, nextCursor: next)
            }
            await server.withMethodHandler(ReadResource.self) { params in
                let contents = try await client.readResource(uri: params.uri)
                return .init(contents: contents)
            }
            await server.withMethodHandler(ListPrompts.self) { _ in
                let (prompts, next) = try await client.listPrompts()
                return .init(prompts: prompts, nextCursor: next)
            }
            await server.withMethodHandler(GetPrompt.self) { params in
                let (description, messages) = try await client.getPrompt(name: params.name, arguments: params.arguments)
                return .init(description: description, messages: messages)
            }
            try await server.start(transport: StdioTransport())
            while true {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }
        } catch {
            fputs("eul mcp-connect: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func probe(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let lock = NSLock()
            var resumed = false
            func finish(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
        }
    }
}
