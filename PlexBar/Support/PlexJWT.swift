import CryptoKit
import Foundation

struct PlexJSONWebKey: Codable, Equatable, Sendable {
    let kty: String
    let crv: String
    // The JWK field name is defined by RFC 8037.
    // swiftlint:disable:next identifier_name
    let x: String
    let kid: String
    let use: String?
    let alg: String

    init(publicKey: Curve25519.Signing.PublicKey, keyID: String, includeUse: Bool) {
        kty = "OKP"
        crv = "Ed25519"
        x = publicKey.rawRepresentation.base64URLEncodedString()
        kid = keyID
        use = includeUse ? "sig" : nil
        alg = "EdDSA"
    }
}

struct PlexDeviceSigningIdentity: Equatable, Sendable {
    private static let tokenLifetime: TimeInterval = 5 * 60

    let keyID: String
    let privateKeyRepresentation: Data

    init(keyID: String, privateKeyRepresentation: Data) throws {
        _ = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRepresentation)
        self.keyID = keyID
        self.privateKeyRepresentation = privateKeyRepresentation
    }

    static func generate(keyID: String = UUID().uuidString.lowercased()) throws -> PlexDeviceSigningIdentity {
        let privateKey = Curve25519.Signing.PrivateKey()
        return try PlexDeviceSigningIdentity(
            keyID: keyID,
            privateKeyRepresentation: privateKey.rawRepresentation
        )
    }

    func publicJWK(includeUse: Bool) throws -> PlexJSONWebKey {
        PlexJSONWebKey(
            publicKey: try privateKey.publicKey,
            keyID: keyID,
            includeUse: includeUse
        )
    }

    func signedDeviceJWT(
        clientIdentifier: String,
        nonce: String? = nil,
        scope: String? = nil,
        issuedAt: Date = Date()
    ) throws -> String {
        let header = PlexDeviceJWTHeader(kid: keyID)
        let claims = PlexDeviceJWTClaims(
            nonce: nonce,
            scope: scope,
            aud: "plex.tv",
            iss: clientIdentifier,
            iat: Int(issuedAt.timeIntervalSince1970),
            exp: Int(issuedAt.addingTimeInterval(Self.tokenLifetime).timeIntervalSince1970)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encodedHeader = try encoder.encode(header).base64URLEncodedString()
        let encodedClaims = try encoder.encode(claims).base64URLEncodedString()
        let signingInput = Data("\(encodedHeader).\(encodedClaims)".utf8)
        let signature = try privateKey.signature(for: signingInput).base64URLEncodedString()
        return "\(encodedHeader).\(encodedClaims).\(signature)"
    }

    private var privateKey: Curve25519.Signing.PrivateKey {
        get throws {
            try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRepresentation)
        }
    }
}

enum PlexAccountToken: Equatable, Sendable {
    case legacy
    case jwt(expiresAt: Date)

    init(token: String) throws {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            self = .legacy
            return
        }
        guard let payload = Data(base64URLEncoded: String(segments[1])),
              let claims = try? JSONDecoder().decode(PlexAccountJWTClaims.self, from: payload) else {
            throw PlexJWTError.malformedAccountToken
        }
        self = .jwt(expiresAt: Date(timeIntervalSince1970: TimeInterval(claims.exp)))
    }
}

enum PlexJWTError: LocalizedError {
    case malformedAccountToken
    case incompleteDeviceIdentity
    case missingAccountToken
    case expectedAccountJWT
    case accountTokenExpiresTooSoon
    case deviceIdentityPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .malformedAccountToken:
            "The stored Plex account token is not a valid JWT. Sign in to Plex again."
        case .incompleteDeviceIdentity:
            "PlexBar found an incomplete device signing identity in Keychain. Sign in to Plex again."
        case .missingAccountToken:
            "No Plex account token is available. Sign in to Plex."
        case .expectedAccountJWT:
            "Plex returned an account token that is not a JWT. Sign in to Plex again."
        case .accountTokenExpiresTooSoon:
            "Plex returned an account token with an invalid expiration time. Sign in to Plex again."
        case .deviceIdentityPersistenceFailed:
            "PlexBar could not store its device signing identity in Keychain."
        }
    }
}

private struct PlexDeviceJWTHeader: Encodable {
    let alg = "EdDSA"
    let kid: String
    let typ = "JWT"
}

private struct PlexDeviceJWTClaims: Encodable {
    let nonce: String?
    let scope: String?
    let aud: String
    let iss: String
    let iat: Int
    let exp: Int
}

private struct PlexAccountJWTClaims: Decodable {
    let exp: Int
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
