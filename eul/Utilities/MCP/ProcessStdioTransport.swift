import Foundation
import Logging
import MCP

actor ProcessStdioTransport: Transport {
    nonisolated let logger: Logger

    private let process: Process
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private var isConnected = false
    private var buffer = Data()
    private var continuation: AsyncThrowingStream<Data, any Swift.Error>.Continuation?
    private var stream: AsyncThrowingStream<Data, any Swift.Error>?
    private var stopping = false
    private let onExit: (@Sendable () -> Void)?
    private static let newline = Data([0x0A])

    init(
        process: Process,
        stdinHandle: FileHandle,
        stdoutHandle: FileHandle,
        logger: Logger? = nil,
        onExit: (@Sendable () -> Void)? = nil
    ) {
        self.process = process
        self.stdinHandle = stdinHandle
        self.stdoutHandle = stdoutHandle
        self.logger = logger ?? Logger(label: "eul2.mcp.process", factory: { _ in SwiftLogNoOpLogHandler() })
        self.onExit = onExit
    }

    func connect() async throws {
        guard !isConnected else {
            return
        }
        if !process.isRunning {
            try process.run()
        }
        isConnected = true
        let (stream, continuation) = AsyncThrowingStream<Data, any Swift.Error>.makeStream()
        self.stream = stream
        self.continuation = continuation
        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { [weak self] in
                await self?.ingest(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { [weak self] in
                await self?.didExit()
            }
        }
    }

    func disconnect() async {
        stopping = true
        process.terminationHandler = nil
        stdoutHandle.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        await finish(nil)
    }

    func send(_ data: Data) async throws {
        var payload = data
        if payload.last != 0x0A {
            payload.append(0x0A)
        }
        try stdinHandle.write(contentsOf: payload)
    }

    func receive() -> AsyncThrowingStream<Data, any Swift.Error> {
        stream ?? AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    private func ingest(_ data: Data) {
        if data.isEmpty {
            Task { await finish("stdout closed") }
            return
        }
        buffer.append(data)
        while let range = buffer.firstRange(of: Self.newline) {
            let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            if !line.isEmpty {
                continuation?.yield(line)
            }
        }
    }

    private func didExit() {
        guard !stopping else {
            return
        }
        stopping = true
        finish("process exited")
        onExit?()
    }

    private func finish(_ reason: String?) {
        stdoutHandle.readabilityHandler = nil
        if let reason {
            continuation?.finish(throwing: MCPError.internalError(reason))
        } else {
            continuation?.finish()
        }
        continuation = nil
        isConnected = false
    }
}
