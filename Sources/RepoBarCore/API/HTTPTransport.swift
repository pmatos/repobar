import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if !canImport(Darwin)
    import AsyncHTTPClient
    import NIOCore
    import NIOFoundationCompat
    import NIOHTTP1
    import NIOPosix
#endif

/// Minimal request/response shape `RepoBarCore`'s GitHub clients need.
///
/// Kept deliberately small. Streaming bodies, websockets, multipart uploads, and
/// HTTP/2 push are not part of the contract because the GitHub clients never
/// need them.
public struct HTTPRequest: Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data?

    public init(url: URL, method: String, headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    /// Perform `request`. Returns the response on any HTTP status (including
    /// 4xx/5xx). Throws only on transport-level failure: DNS, TLS, connection
    /// closed, decoder errors, etc.
    func perform(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Picks the right transport for the current platform.
///
/// - macOS / iOS: backed by `URLSession.shared` (preserves the prior behaviour).
/// - Linux: backed by `AsyncHTTPClient`, sharing a single process-wide client.
public func makeDefaultHTTPTransport() -> HTTPTransport {
    #if canImport(Darwin)
        return URLSessionHTTPTransport()
    #else
        return AsyncHTTPClientTransport.shared
    #endif
}

// MARK: - macOS / iOS implementation

#if canImport(Darwin)
    public struct URLSessionHTTPTransport: HTTPTransport {
        private let session: URLSession

        public init(session: URLSession = .shared) {
            self.session = session
        }

        public func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
            var urlRequest = URLRequest(url: request.url)
            urlRequest.httpMethod = request.method
            for (k, v) in request.headers {
                urlRequest.addValue(v, forHTTPHeaderField: k)
            }
            urlRequest.httpBody = request.body

            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let k = key as? String, let v = value as? String {
                    headers[k] = v
                }
            }
            return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
        }
    }
#endif

// MARK: - Linux implementation

#if !canImport(Darwin)
    /// AsyncHTTPClient-backed transport. Holds a process-wide `HTTPClient` so we
    /// keep one event loop group rather than tearing one down per request.
    public final class AsyncHTTPClientTransport: HTTPTransport, @unchecked Sendable {
        public static let shared = AsyncHTTPClientTransport()

        private let client: HTTPClient

        public init() {
            // Using `.singleton` matches AsyncHTTPClient's recommended usage and
            // means we don't have to ever shut the client down for the lifetime
            // of the process.
            self.client = HTTPClient(eventLoopGroupProvider: .singleton)
        }

        public func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
            var httpRequest = HTTPClientRequest(url: request.url.absoluteString)
            httpRequest.method = .init(rawValue: request.method)
            for (k, v) in request.headers {
                httpRequest.headers.add(name: k, value: v)
            }
            if let body = request.body {
                httpRequest.body = .bytes(body)
            }

            let response = try await self.client.execute(httpRequest, timeout: .seconds(30))
            let bodyBuffer = try await response.body.collect(upTo: 64 * 1024 * 1024)
            var headers: [String: String] = [:]
            for header in response.headers {
                headers[header.name] = header.value
            }
            return HTTPResponse(
                statusCode: Int(response.status.code),
                headers: headers,
                body: Data(buffer: bodyBuffer)
            )
        }
    }
#endif
