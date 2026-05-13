import Foundation
@testable import repobarcli
import Testing

@Suite("resolveCLIAuthSource")
struct CLIAuthSourceTests {
    @Test("GITHUB_TOKEN wins even when OAuth tokens are stored")
    func envTokenWinsOverStoredOAuth() {
        let source = resolveCLIAuthSource(
            env: ["GITHUB_TOKEN": "ghp_envvar"],
            hasOAuth: true,
            pat: "stored-pat"
        )
        #expect(source == .envToken("ghp_envvar"))
    }

    @Test("empty GITHUB_TOKEN falls through to stored OAuth")
    func emptyEnvFallsThroughToOAuth() {
        let source = resolveCLIAuthSource(
            env: ["GITHUB_TOKEN": "   "],
            hasOAuth: true,
            pat: nil
        )
        #expect(source == .storedOAuth)
    }

    @Test("no env, OAuth present → storedOAuth")
    func storedOAuth() {
        let source = resolveCLIAuthSource(env: [:], hasOAuth: true, pat: nil)
        #expect(source == .storedOAuth)
    }

    @Test("no env, no OAuth, PAT present → storedPAT")
    func storedPAT() {
        let source = resolveCLIAuthSource(env: [:], hasOAuth: false, pat: "ghp_stored")
        #expect(source == .storedPAT("ghp_stored"))
    }

    @Test("no env, no OAuth, no PAT → unauthenticated")
    func unauthenticated() {
        let source = resolveCLIAuthSource(env: [:], hasOAuth: false, pat: nil)
        #expect(source == .unauthenticated)
    }

    @Test("whitespace around GITHUB_TOKEN is trimmed")
    func envTokenIsTrimmed() {
        let source = resolveCLIAuthSource(
            env: ["GITHUB_TOKEN": "  ghp_padded  "],
            hasOAuth: false,
            pat: nil
        )
        #expect(source == .envToken("ghp_padded"))
    }
}
