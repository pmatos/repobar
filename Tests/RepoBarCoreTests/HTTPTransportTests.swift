import Foundation
@testable import RepoBarCore
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Suite("HTTPTransport")
struct HTTPTransportTests {
    @Test("default transport GETs https://api.github.com/zen")
    func defaultTransportFetchesZen() async throws {
        let transport = makeDefaultHTTPTransport()
        let response = try await transport.perform(
            HTTPRequest(
                url: URL(string: "https://api.github.com/zen")!,
                method: "GET",
                headers: ["User-Agent": "repobar-tests"],
                body: nil
            )
        )

        #expect(response.statusCode == 200)
        let body = String(data: response.body, encoding: .utf8) ?? ""
        // /zen returns a single short pithy line. We assert non-empty and ASCII.
        #expect(body.isEmpty == false)
        #expect(body.allSatisfy { $0.isASCII })
    }

    @Test("default transport surfaces non-200 responses without throwing")
    func defaultTransportSurfacesErrors() async throws {
        let transport = makeDefaultHTTPTransport()
        let response = try await transport.perform(
            HTTPRequest(
                url: URL(string: "https://api.github.com/this-path-does-not-exist-zzz")!,
                method: "GET",
                headers: ["User-Agent": "repobar-tests"],
                body: nil
            )
        )
        #expect(response.statusCode == 404)
    }
}
