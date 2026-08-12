import Foundation
import CryptoKit

public enum ExchangeMessageSealerError: Error, Sendable, Hashable {
    case invalidRecipientKey
    case invalidSenderIdentity
    case signingFailed
    case sealingFailed
}

/// Seals DM plaintext into `ExchangeRelayPayloadEncryption` (Phase 2).
public struct ExchangeMessageSealer: Sendable {
    public init() {}

    public func sealDMText(
        body: String,
        subject: String?,
        envelopeID: String,
        sentAt: Date,
        senderEncryptionKeyID: String,
        senderSigningKeyID: String,
        recipientEncryptionKeyID: String,
        recipientEncryptionPublicKeyBase64: String,
        attachments: [ExchangePrivateAttachmentPlaintext] = []
    ) throws -> ExchangeRelayPayloadEncryption {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty || !attachments.isEmpty else {
            throw ExchangeMessageSealerError.sealingFailed
        }

        guard let recipientKeyData = Data(base64Encoded: recipientEncryptionPublicKeyBase64),
              recipientKeyData.count == 32 else {
            throw ExchangeMessageSealerError.invalidRecipientKey
        }

        let recipientPublicKey: Curve25519.KeyAgreement.PublicKey
        do {
            recipientPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientKeyData)
        } catch {
            throw ExchangeMessageSealerError.invalidRecipientKey
        }

        let signingMaterial = try NodeIdentityVault.shared.loadOrCreateSigningMaterial()
        guard senderSigningKeyID == signingMaterial.publicKeyID else {
            throw ExchangeMessageSealerError.invalidSenderIdentity
        }

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let inner = ExchangePrivateMessagePlaintext(
            body: trimmedBody,
            sentAt: formatter.string(from: sentAt),
            envelopeID: envelopeID,
            subject: subject,
            attachments: attachments
        )
        let innerBytes = try inner.encodedSigningBytes()

        let signingPrivateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: signingMaterial.seed)
        let signatureData: Data
        do {
            signatureData = try signingPrivateKey.signature(for: innerBytes)
        } catch {
            throw ExchangeMessageSealerError.signingFailed
        }

        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublicKeyData = ephemeralPrivateKey.publicKey.rawRepresentation
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(ExchangeRelayPayloadEncryption.schemeV1.utf8),
            outputByteCount: 32
        )

        let sealedBox = try AES.GCM.seal(innerBytes, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw ExchangeMessageSealerError.sealingFailed
        }

        // Wire format keeps nonce separate; ciphertext holds combined bytes for open().
        return ExchangeRelayPayloadEncryption(
            senderEncryptionKeyID: senderEncryptionKeyID,
            recipientEncryptionKeyID: recipientEncryptionKeyID,
            ephemeralPublicKey: ephemeralPublicKeyData.base64EncodedString(),
            nonce: Data(sealedBox.nonce).base64EncodedString(),
            ciphertext: combined.base64EncodedString(),
            signature: .init(
                algorithm: "ed25519",
                keyID: senderSigningKeyID,
                value: signatureData.base64EncodedString()
            )
        )
    }
}
