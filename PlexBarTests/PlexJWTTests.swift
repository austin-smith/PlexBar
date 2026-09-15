import CryptoKit
import Foundation
import Testing
@testable import PlexBar

struct PlexJWTTests {
    @Test func publicJWKUsesPlexEd25519Contract() throws {
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")

        let pinJWK = try identity.publicJWK(includeUse: false)
        let migrationJWK = try identity.publicJWK(includeUse: true)

        #expect(pinJWK.kty == "OKP")
        #expect(pinJWK.crv == "Ed25519")
        #expect(pinJWK.alg == "EdDSA")
        #expect(pinJWK.kid == "device-key")
        #expect(pinJWK.use == nil)
        #expect(try decodeBase64URL(pinJWK.x).count == 32)
        #expect(migrationJWK.use == "sig")
    }

    @Test func signedDeviceJWTContainsExactClaimsAndValidSignature() throws {
        let identity = try PlexDeviceSigningIdentity.generate(keyID: "device-key")
        let issuedAt = Date(timeIntervalSince1970: 2_000_000_000)

        let token = try identity.signedDeviceJWT(
            clientIdentifier: "stable-client-id",
            nonce: "plex-nonce",
            scope: PlexAccountJWTManager.requestedScope,
            issuedAt: issuedAt
        )

        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        #expect(segments.count == 3)
        let header = try jsonObject(from: String(segments[0]))
        let claims = try jsonObject(from: String(segments[1]))
        #expect(header["alg"] as? String == "EdDSA")
        #expect(header["kid"] as? String == "device-key")
        #expect(header["typ"] as? String == "JWT")
        #expect(claims["nonce"] as? String == "plex-nonce")
        #expect(claims["scope"] as? String == "username,email,friendly_name")
        #expect(claims["aud"] as? String == "plex.tv")
        #expect(claims["iss"] as? String == "stable-client-id")
        #expect(claims["iat"] as? Int == 2_000_000_000)
        #expect(claims["exp"] as? Int == 2_000_000_300)

        let jwk = try identity.publicJWK(includeUse: false)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: decodeBase64URL(jwk.x))
        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        let signature = try decodeBase64URL(String(segments[2]))
        #expect(publicKey.isValidSignature(signature, for: signingInput))
    }

    @Test func accountJWTDecodesExpiration() throws {
        let expiration = 4_102_444_800
        let token = try makeAccountJWT(expiration: expiration)

        let accountToken = try PlexAccountToken(token: token)

        #expect(accountToken == .jwt(expiresAt: Date(timeIntervalSince1970: TimeInterval(expiration))))
    }

    @Test func malformedThreePartAccountTokenIsRejected() {
        #expect(throws: PlexJWTError.self) {
            _ = try PlexAccountToken(token: "header.not-json.signature")
        }
    }

    @Test func opaqueAccountTokenIsClassifiedAsLegacy() throws {
        #expect(try PlexAccountToken(token: "legacy-token") == .legacy)
    }
}

private func makeAccountJWT(expiration: Int) throws -> String {
    let header = try JSONSerialization.data(withJSONObject: ["alg": "EdDSA", "typ": "JWT"])
    let payload = try JSONSerialization.data(withJSONObject: ["exp": expiration])
    return "\(encodeBase64URL(header)).\(encodeBase64URL(payload)).test-signature"
}

private func jsonObject(from encodedSegment: String) throws -> [String: Any] {
    let data = try decodeBase64URL(encodedSegment)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func decodeBase64URL(_ value: String) throws -> Data {
    var base64 = value
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder != 0 {
        base64.append(String(repeating: "=", count: 4 - remainder))
    }
    return try #require(Data(base64Encoded: base64))
}

private func encodeBase64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
