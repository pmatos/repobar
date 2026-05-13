import Foundation
@testable import RepoBarCore
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Suite
struct OAuthLoginFlowErrorTests {
    @Test
    @MainActor
    func `state mismatch throws OAuthLoginError stateMismatch`() async throws {
        let tokenStore = makeIsolatedTokenStore()
        defer { tokenStore.clear() }

        let server = FakeLoopbackServer(
            redirectURL: URL(string: "http://127.0.0.1:54321/callback")!,
            result: (code: "code-123", state: "wrong-state")
        )
        let flow = OAuthLoginFlow(
            tokenStore: tokenStore,
            openURL: { _ in },
            dataProvider: { _ in
                Issue.record("dataProvider should not be called when state mismatches")
                throw URLError(.unknown)
            },
            makeLoopbackServer: { _ in server },
            stateProvider: { "expected-state" }
        )

        await #expect(throws: OAuthLoginError.stateMismatch) {
            _ = try await flow.login(
                clientID: "cid",
                clientSecret: "csecret",
                host: URL(string: "https://github.com")!,
                loopbackPort: 54321,
                timeout: 2
            )
        }
    }

    @Test
    @MainActor
    func `empty code throws OAuthLoginError missingCode`() async throws {
        let tokenStore = makeIsolatedTokenStore()
        defer { tokenStore.clear() }

        let server = FakeLoopbackServer(
            redirectURL: URL(string: "http://127.0.0.1:54321/callback")!,
            result: (code: "", state: "expected-state")
        )
        let flow = OAuthLoginFlow(
            tokenStore: tokenStore,
            openURL: { _ in },
            dataProvider: { _ in
                Issue.record("dataProvider should not be called when code is missing")
                throw URLError(.unknown)
            },
            makeLoopbackServer: { _ in server },
            stateProvider: { "expected-state" }
        )

        await #expect(throws: OAuthLoginError.missingCode) {
            _ = try await flow.login(
                clientID: "cid",
                clientSecret: "csecret",
                host: URL(string: "https://github.com")!,
                loopbackPort: 54321,
                timeout: 2
            )
        }
    }

    @Test
    @MainActor
    func `non-200 token response throws OAuthLoginError tokenExchangeFailed with status and body`() async throws {
        let tokenStore = makeIsolatedTokenStore()
        defer { tokenStore.clear() }

        let server = FakeLoopbackServer(
            redirectURL: URL(string: "http://127.0.0.1:54321/callback")!,
            result: (code: "code-123", state: "expected-state")
        )
        let flow = OAuthLoginFlow(
            tokenStore: tokenStore,
            openURL: { _ in },
            dataProvider: { request in
                let url = try #require(request.url)
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (Data("bad_verification_code".utf8), response)
            },
            makeLoopbackServer: { _ in server },
            stateProvider: { "expected-state" }
        )

        do {
            _ = try await flow.login(
                clientID: "cid",
                clientSecret: "csecret",
                host: URL(string: "https://github.com")!,
                loopbackPort: 54321,
                timeout: 2
            )
            Issue.record("Expected OAuthLoginError.tokenExchangeFailed")
        } catch let OAuthLoginError.tokenExchangeFailed(status, body) {
            #expect(status == 401)
            #expect(body == "bad_verification_code")
        } catch {
            Issue.record("Expected tokenExchangeFailed, got \(error)")
        }
    }
}

private func makeIsolatedTokenStore() -> TokenStore {
    TokenStore(service: "com.steipete.repobar.auth.tests.\(UUID().uuidString)")
}

@MainActor
private final class FakeLoopbackServer: LoopbackServing {
    private let redirectURL: URL
    private let result: (code: String, state: String)

    init(redirectURL: URL, result: (code: String, state: String)) {
        self.redirectURL = redirectURL
        self.result = result
    }

    func start() throws -> URL { self.redirectURL }

    func waitForCallback(timeout _: TimeInterval) async throws -> (code: String, state: String) {
        self.result
    }

    func stop() {}
}
