import _CryptoExtras
import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// Minimal RS256 JWT signer for GitHub App authentication.
///
/// Backed by swift-crypto's `_RSA.Signing` so the implementation is identical
/// on macOS and Linux. PKCS#1 v1.5 with SHA-256 is the RS256 signing primitive.
public enum JWTSigner {
    public enum Error: Swift.Error, Equatable {
        case invalidPEM
        case keyCreationFailed
        case signFailed
    }

    public static func sign(appID: String, pemString: String, now: Date = Date()) throws -> String {
        let privateKey: _RSA.Signing.PrivateKey
        do {
            privateKey = try _RSA.Signing.PrivateKey(pemRepresentation: pemString)
        } catch {
            throw Error.invalidPEM
        }

        let header: [String: String] = ["alg": "RS256", "typ": "JWT"]
        let iat = Int(now.timeIntervalSince1970)
        let exp = iat + 8 * 60 + 30 // <=10 minutes; use 8.5 to be safe.
        let payload: [String: Any] = ["iat": iat, "exp": exp, "iss": appID]

        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let signingInput = [
            headerData.base64URLEncodedString(),
            payloadData.base64URLEncodedString(),
        ].joined(separator: ".")

        let signature: _RSA.Signing.RSASignature
        do {
            signature = try privateKey.signature(
                for: Data(signingInput.utf8),
                padding: .insecurePKCS1v1_5
            )
        } catch {
            throw Error.signFailed
        }

        return signingInput + "." + signature.rawRepresentation.base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
