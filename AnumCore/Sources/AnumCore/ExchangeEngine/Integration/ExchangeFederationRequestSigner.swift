import Foundation
import CryptoKit

#if DEBUG
@inline(__always)
private func exchFederationSignerLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeFederationRequestSigner] \(message())")
}
#else
@inline(__always)
private func exchFederationSignerLog(_ message: @autoclosure () -> String) {}
#endif

public struct ExchangeFederationRequestSigner: Sendable {
    public enum SignerError: Error, Sendable, Hashable {
        case invalidMethod
        case invalidPath
        case signingFailed
    }

    public struct SignedHeaders: Sendable, Hashable {
        public let nodeID: String
        public let publicKeyID: String
        public let timestamp: String
        public let nonce: String
        public let signature: String
    }

    public init() {}

    private static func iso8601WithFractionalUTCString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public func currentIdentity() throws -> NodeSigningMaterial {
        try NodeIdentityVault.shared.loadOrCreateSigningMaterial()
    }

    public func makeSignedFederationHeaders(
        method: String,
        path: String,
        bodyData: Data?,
        endpointLabel: String? = nil
    ) throws -> SignedHeaders {
        let trimmedMethod = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedMethod.isEmpty else { throw SignerError.invalidMethod }

        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.hasPrefix("/") else { throw SignerError.invalidPath }

        let material = try currentIdentity()
        let now = Date()
        // Generate once per signed request and reuse this exact string for both
        // header and signature payload.
        let timestamp = Self.iso8601WithFractionalUTCString(from: now)
        let nonce = UUID().uuidString.lowercased()
        let hashHex = Self.bodyHashHex(for: bodyData ?? Data("{}".utf8))

        let payload = Self.makeSigningPayload(
            method: trimmedMethod,
            pathWithQuery: trimmedPath,
            timestamp: timestamp,
            nonce: nonce,
            bodyHashHex: hashHex
        )
        let payloadData = Data(payload.utf8)

        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: material.seed)
        let signature: Data
        do {
            signature = try privateKey.signature(for: payloadData)
        } catch {
            throw SignerError.signingFailed
        }

        let signed = SignedHeaders(
            nodeID: material.nodeID,
            publicKeyID: material.publicKeyID,
            timestamp: timestamp,
            nonce: nonce,
            signature: signature.base64EncodedString()
        )

        let localNowISO = Self.iso8601WithFractionalUTCString(from: now)
        let noncePrefix = String(nonce.prefix(8))
        let bodyHashPrefix = String(hashHex.prefix(12))
        let signaturePrefix = String(signed.signature.prefix(12))
        exchFederationSignerLog(
            "signed endpoint=\(endpointLabel ?? trimmedPath) " +
            "method=\(trimmedMethod) pathWithQuery=\(trimmedPath) " +
            "timestamp=\(timestamp) localNow=\(localNowISO) " +
            "nodeID=\(signed.nodeID) publicKeyID=\(signed.publicKeyID) " +
            "skewCheckLocalSeconds=0 noncePrefix=\(noncePrefix) " +
            "bodyHashPrefix=\(bodyHashPrefix) signaturePrefix=\(signaturePrefix)"
        )

        return signed
    }

    public func apply(
        _ headers: SignedHeaders,
        to request: inout URLRequest
    ) {
        request.setValue(headers.nodeID, forHTTPHeaderField: "x-unify-node-id")
        request.setValue(headers.publicKeyID, forHTTPHeaderField: "x-unify-public-key-id")
        request.setValue(headers.timestamp, forHTTPHeaderField: "x-unify-timestamp")
        request.setValue(headers.nonce, forHTTPHeaderField: "x-unify-nonce")
        request.setValue(headers.signature, forHTTPHeaderField: "x-unify-signature")
    }

    public func canonicalPath(for url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SignerError.invalidPath
        }
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }

    public static func makeSigningPayload(
        method: String,
        pathWithQuery: String,
        timestamp: String,
        nonce: String,
        bodyHashHex: String
    ) -> String {
        "\(method)\n\(pathWithQuery)\n\(timestamp)\n\(nonce)\n\(bodyHashHex)"
    }

    public static func bodyHashHex(for bodyData: Data) -> String {
        SHA256.hash(data: bodyData).map { String(format: "%02x", $0) }.joined()
    }

    public static func makeDeterministicJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

}
