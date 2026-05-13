import Foundation

// swift-crypto on Linux exposes the same Crypto module; on Apple platforms,
// CryptoKit is preferred since it ships with the OS.
#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public static func generate() -> PKCE {
        // RFC 7636: code_verifier 43-128 chars of unreserved; use 32 bytes base64url.
        // SymmetricKey is the portable way to obtain CSPRNG bytes across
        // CryptoKit (Apple) and swift-crypto (Linux).
        let randomBytes = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let verifier = randomBytes.base64URLEncodedString()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}
