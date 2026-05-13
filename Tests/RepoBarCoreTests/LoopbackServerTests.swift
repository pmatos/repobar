import Foundation
@testable import RepoBarCore
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Suite("LoopbackServer")
@MainActor
struct LoopbackServerTests {
    static let testPort = 53_691 // Picked to not collide with the default 53682.

    @Test("captures code+state from an OAuth-redirect-shaped request")
    func capturesCallback() async throws {
        let server = LoopbackServer(port: Self.testPort)
        let url = try server.start()
        defer { server.stop() }

        async let callback = server.waitForCallback(timeout: 10)

        let request = URL(string: "\(url.absoluteString)?code=abc123&state=xyz789")!
        let task = Task.detached {
            _ = try? await URLSession.shared.data(from: request)
        }

        let result = try await callback
        _ = await task.value
        #expect(result.code == "abc123")
        #expect(result.state == "xyz789")
    }

    @Test("starting on an in-use port throws portInUse")
    func portInUseSurfaces() async throws {
        let port = Self.testPort + 1
        let first = LoopbackServer(port: port)
        _ = try first.start()
        defer { first.stop() }

        let second = LoopbackServer(port: port)
        #expect(throws: LoopbackServerError.self) {
            _ = try second.start()
        }
    }

    @Test("parse extracts code+state from a raw request line")
    func parseRequestLine() {
        let request = "GET /callback?code=cccc&state=ssss HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let parsed = LoopbackServer.parse(request: request)
        #expect(parsed?.code == "cccc")
        #expect(parsed?.state == "ssss")
    }
}
