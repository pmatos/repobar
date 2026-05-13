import Commander
import Foundation
import RepoBarCore

struct AuthContext {
    let client: GitHubClient
    let settings: UserSettings
    let host: URL
}

/// The three ways the CLI can authenticate, in priority order.
enum CLIAuthSource: Equatable, Sendable {
    case envToken(String)
    case storedOAuth
    case storedPAT(String)
    case unauthenticated
}

/// Pick the auth source based on the env var first, then stored credentials.
///
/// `env`, `hasOAuth`, and `pat` are injectable so unit tests can exercise the
/// decision matrix without hitting the real keychain / file store.
func resolveCLIAuthSource(
    env: [String: String] = ProcessInfo.processInfo.environment,
    hasOAuth: Bool = (try? TokenStore.shared.load()) != nil,
    pat: String? = try? TokenStore.shared.loadPAT()
) -> CLIAuthSource {
    let envToken = env["GITHUB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if envToken.isEmpty == false {
        return .envToken(envToken)
    }
    if hasOAuth {
        return .storedOAuth
    }
    if let pat, pat.isEmpty == false {
        return .storedPAT(pat)
    }
    return .unauthenticated
}

func makeAuthenticatedClient() async throws -> AuthContext {
    let settings = SettingsStore().load()
    let host = settings.enterpriseHost ?? settings.githubHost
    let apiHost: URL = if let enterprise = settings.enterpriseHost {
        enterprise.appending(path: "/api/v3")
    } else {
        RepoBarAuthDefaults.apiHost
    }

    let client = GitHubClient()
    await client.setAPIHost(apiHost)

    switch resolveCLIAuthSource() {
    case let .envToken(token):
        await client.setTokenProvider { @Sendable () async throws -> OAuthTokens? in
            OAuthTokens(accessToken: token, refreshToken: "", expiresAt: nil)
        }
    case .storedOAuth:
        await client.setTokenProvider { @Sendable () async throws -> OAuthTokens? in
            try await OAuthTokenRefresher().refreshIfNeeded(host: host)
        }
    case let .storedPAT(token):
        await client.setTokenProvider { @Sendable () async throws -> OAuthTokens? in
            OAuthTokens(accessToken: token, refreshToken: "", expiresAt: nil)
        }
    case .unauthenticated:
        throw CLIError.notAuthenticated
    }

    return AuthContext(client: client, settings: settings, host: host)
}

func makeRepoURL(baseHost: URL, owner: String, name: String) -> URL {
    baseHost.appending(path: "/\(owner)/\(name)")
}

func requireRepoName(_ name: String?) throws -> String {
    guard let name, name.isEmpty == false else {
        throw ValidationError("Missing repository name (owner/name)")
    }

    return name
}

func parseRepoName(_ value: String) throws -> (owner: String, name: String) {
    let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
    guard parts.count == 2, parts[0].isEmpty == false, parts[1].isEmpty == false else {
        throw ValidationError("Repository must be in owner/name format")
    }

    return (parts[0], parts[1])
}
