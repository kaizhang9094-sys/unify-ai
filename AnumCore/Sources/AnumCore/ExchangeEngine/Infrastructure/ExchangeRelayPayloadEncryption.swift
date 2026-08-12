import Foundation

/// Wire-format encryption envelope for private federation message bodies.
///
/// Populated by private text E2EE send paths. Legacy plaintext envelopes omit this field.
public struct ExchangeRelayPayloadEncryption: Codable, Sendable, Hashable {
    public static let schemeV1 = "unify.v1.x25519-aesgcm"
    public static let currentVersion = 1

    public var version: Int
    public var scheme: String
    public var senderEncryptionKeyID: String
    public var recipientEncryptionKeyID: String
    public var ephemeralPublicKey: String
    public var nonce: String
    public var ciphertext: String
    public var signature: Signature

    public init(
        version: Int = ExchangeRelayPayloadEncryption.currentVersion,
        scheme: String = ExchangeRelayPayloadEncryption.schemeV1,
        senderEncryptionKeyID: String,
        recipientEncryptionKeyID: String,
        ephemeralPublicKey: String,
        nonce: String,
        ciphertext: String,
        signature: Signature
    ) {
        self.version = version
        self.scheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        self.senderEncryptionKeyID = senderEncryptionKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.recipientEncryptionKeyID = recipientEncryptionKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ephemeralPublicKey = ephemeralPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nonce = nonce.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ciphertext = ciphertext.trimmingCharacters(in: .whitespacesAndNewlines)
        self.signature = signature
    }

    public struct Signature: Codable, Sendable, Hashable {
        public var algorithm: String
        public var keyID: String
        public var value: String

        public init(
            algorithm: String = "ed25519",
            keyID: String,
            value: String
        ) {
            self.algorithm = algorithm.trimmingCharacters(in: .whitespacesAndNewlines)
            self.keyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
            self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
