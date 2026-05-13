import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

/// Error thrown when the loopback server cannot start.
public enum LoopbackServerError: LocalizedError {
    case portInUse(port: Int)
    case bindFailed(port: Int, underlying: Error)
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case let .portInUse(port):
            "Port \(port) is already in use. This may be caused by a previous login attempt that didn't complete. Try again in a few seconds or choose a different port."
        case let .bindFailed(port, underlying):
            "Failed to bind to port \(port): \(underlying.localizedDescription)"
        case .notImplemented:
            "LoopbackServer is not yet implemented on this platform."
        }
    }
}

/// Minimal one-shot HTTP loopback listener to capture OAuth redirects.
///
/// Single SwiftNIO-backed implementation across macOS and Linux. Binds to
/// `127.0.0.1:<port>`, accepts the first GET request, parses the code/state
/// query params, sends a small success page back, then resolves
/// `waitForCallback` with the parsed values.
@MainActor
public final class LoopbackServer {
    private let port: Int
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    private var continuation: CheckedContinuation<(code: String, state: String), Error>?
    private var pendingResult: (code: String, state: String)?

    public init(port: Int) {
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    deinit {
        try? group.syncShutdownGracefully()
    }

    public func start() throws -> URL {
        let handler = LoopbackHandler { [weak self] code, state in
            // Hop onto the MainActor before touching our state.
            Task { @MainActor [weak self] in
                self?.deliver(code: code, state: state)
            }
        }

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(handler)
                }
            }

        do {
            let channel = try bootstrap.bind(host: "127.0.0.1", port: self.port).wait()
            self.channel = channel
        } catch let error as IOError where error.errnoCode == EADDRINUSE {
            throw LoopbackServerError.portInUse(port: self.port)
        } catch {
            // SwiftNIO surfaces NIOCore.IOError; some platforms wrap the
            // address-in-use case differently. Treat any bind failure whose
            // message mentions the well-known errno as portInUse for friendlier
            // CLI output.
            let message = String(describing: error).lowercased()
            if message.contains("address already in use") || message.contains("eaddrinuse") {
                throw LoopbackServerError.portInUse(port: self.port)
            }
            throw LoopbackServerError.bindFailed(port: self.port, underlying: error)
        }

        return URL(string: "http://127.0.0.1:\(self.port)/callback")!
    }

    public func waitForCallback(timeout: TimeInterval = 180) async throws -> (code: String, state: String) {
        if let pendingResult {
            self.pendingResult = nil
            self.stop()
            return pendingResult
        }

        let timeoutTask = Task { @MainActor in
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if let continuation {
                continuation.resume(throwing: URLError(.timedOut))
                self.continuation = nil
            }
        }
        let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<
            (code: String, state: String),
            Error
        >) in
            self.continuation = cont
        }
        timeoutTask.cancel()
        self.stop()
        return result
    }

    public func stop() {
        if let channel {
            // Best-effort close; ignore errors because stop is also called from
            // the deinit / cancellation paths where the channel may already be
            // gone.
            try? channel.close().wait()
            self.channel = nil
        }
        self.continuation = nil
        self.pendingResult = nil
    }

    private func deliver(code: String, state: String) {
        if let continuation {
            continuation.resume(returning: (code, state))
            self.continuation = nil
        } else {
            self.pendingResult = (code, state)
        }
    }

    /// Pure parser kept on the type for backwards compatibility. Backed by the
    /// shared parser so the macOS impl and the Linux impl share one source of
    /// truth.
    public nonisolated static func parse(request: String) -> (code: String, state: String)? {
        LoopbackServerParser.parse(request: request)
    }
}

/// Cross-platform parser for the OAuth redirect line shape.
enum LoopbackServerParser {
    static func parse(request: String) -> (code: String, state: String)? {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let range = firstLine.range(of: "GET ") else { return nil }

        let pathPart = firstLine[range.upperBound...].split(separator: " ").first ?? "" as Substring
        return parse(uri: String(pathPart))
    }

    static func parse(uri: String) -> (code: String, state: String)? {
        let components = URLComponents(string: "http://localhost\(uri)")
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value ?? ""
        let state = components?.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
        return (code, state)
    }
}

private final class LoopbackHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let onCapture: @Sendable (_ code: String, _ state: String) -> Void
    private var capturedURI: String?
    private var didRespond = false

    init(onCapture: @escaping @Sendable (_ code: String, _ state: String) -> Void) {
        self.onCapture = onCapture
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        switch part {
        case let .head(head):
            self.capturedURI = head.uri
        case .body:
            // OAuth redirects don't have meaningful bodies.
            break
        case .end:
            guard self.didRespond == false else { return }
            self.didRespond = true
            let uri = self.capturedURI ?? "/"
            let parsed = LoopbackServerParser.parse(uri: uri) ?? ("", "")
            self.respondWithSuccess(context: context)
            self.onCapture(parsed.code, parsed.state)
        }
    }

    private func respondWithSuccess(context: ChannelHandlerContext) {
        let body = "Success — you can close this tab."
        let buffer = context.channel.allocator.buffer(string: body)

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: "Content-Length", value: String(buffer.readableBytes))
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        let endPromise = context.eventLoop.makePromise(of: Void.self)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: endPromise)
        endPromise.futureResult.whenComplete { _ in
            context.close(promise: nil)
        }
    }
}
