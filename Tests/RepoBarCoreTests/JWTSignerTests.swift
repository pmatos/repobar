import Foundation
@testable import RepoBarCore
import Testing

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

import _CryptoExtras

@Suite("JWTSigner")
struct JWTSignerTests {
    static let pemPrivateKey: String = {
        let url = Bundle.module.url(
            forResource: "jwt-test-key",
            withExtension: "pem",
            subdirectory: "Fixtures"
        )!
        return try! String(contentsOf: url, encoding: .utf8)
    }()

    static let pemPublicKey: String = {
        let url = Bundle.module.url(
            forResource: "jwt-test-public-key",
            withExtension: "pem",
            subdirectory: "Fixtures"
        )!
        return try! String(contentsOf: url, encoding: .utf8)
    }()

    @Test("sign produces a JWT with three base64url segments")
    func signProducesThreePartJWT() throws {
        let jwt = try JWTSigner.sign(
            appID: "test-app",
            pemString: Self.pemPrivateKey,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let parts = jwt.split(separator: ".")
        #expect(parts.count == 3)
        for part in parts {
            // base64url alphabet only — no `+`, `/`, or `=`.
            #expect(part.allSatisfy { c in
                c.isLetter || c.isNumber || c == "-" || c == "_"
            })
        }
    }

    @Test("header decodes to RS256/JWT")
    func headerShape() throws {
        let jwt = try JWTSigner.sign(
            appID: "test-app",
            pemString: Self.pemPrivateKey,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let headerData = try decodeBase64URL(String(jwt.split(separator: ".")[0]))
        let header = try JSONSerialization.jsonObject(with: headerData) as? [String: String]
        #expect(header?["alg"] == "RS256")
        #expect(header?["typ"] == "JWT")
    }

    @Test("payload carries iat, exp, iss with a <=10 minute window")
    func payloadShape() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let jwt = try JWTSigner.sign(appID: "app-42", pemString: Self.pemPrivateKey, now: now)
        let payloadData = try decodeBase64URL(String(jwt.split(separator: ".")[1]))
        let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        let iat = payload?["iat"] as? Int
        let exp = payload?["exp"] as? Int
        let iss = payload?["iss"] as? String
        #expect(iat == 1_700_000_000)
        #expect(iss == "app-42")
        try #require(exp != nil)
        let window = exp! - iat!
        #expect(window > 0)
        #expect(window <= 600)
    }

    @Test("signature verifies under the matching public key")
    func signatureRoundtrip() throws {
        let jwt = try JWTSigner.sign(
            appID: "round-trip",
            pemString: Self.pemPrivateKey,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let parts = jwt.split(separator: ".")
        let signingInput = "\(parts[0]).\(parts[1])"
        let signatureBytes = try decodeBase64URL(String(parts[2]))

        let publicKey = try _RSA.Signing.PublicKey(pemRepresentation: Self.pemPublicKey)
        let signature = _RSA.Signing.RSASignature(rawRepresentation: signatureBytes)
        let isValid = publicKey.isValidSignature(
            signature,
            for: Data(signingInput.utf8),
            padding: .insecurePKCS1v1_5
        )
        #expect(isValid)
    }

    @Test("signing the same input twice produces the same JWT (PKCS#1 v1.5 is deterministic)")
    func deterministicSignature() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = try JWTSigner.sign(appID: "det", pemString: Self.pemPrivateKey, now: now)
        let b = try JWTSigner.sign(appID: "det", pemString: Self.pemPrivateKey, now: now)
        #expect(a == b)
    }

    @Test("invalid PEM throws .invalidPEM")
    func invalidPEM() {
        #expect(throws: JWTSigner.Error.invalidPEM) {
            try JWTSigner.sign(appID: "x", pemString: "not a pem")
        }
    }
}

private func decodeBase64URL(_ string: String) throws -> Data {
    var b64 = string
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while b64.count % 4 != 0 {
        b64.append("=")
    }
    guard let data = Data(base64Encoded: b64) else {
        struct DecodeError: Error {}
        throw DecodeError()
    }
    return data
}
