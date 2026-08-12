import Foundation
import CryptoKit

public enum ExchangeMessageOpenerError: Error, Sendable, Hashable {
    case unsupportedScheme
    case invalidCiphertext
    case invalidEphemeralKey
    case invalidSignature
    case signatureVerificationFailed
    case missingSenderSigningKey
    case recipientKeyMismatch
    case openingFailed
}

/// Opens/decrypts DM `ExchangeRelayPayloadEncryption` blobs (Phase 2).
public struct ExchangeMessageOpener: Sendable {
    public init() {}

    public func openDMText(
        encryption: ExchangeRelayPayloadEncryption,
        senderSigningPublicKeyBase64: String?,
        localEncryptionMaterial: NodeEncryptionMaterial
    ) throws -> ExchangePrivateMessagePlaintext {
        guard encryption.scheme == ExchangeRelayPayloadEncryption.schemeV1 else {
            throw ExchangeMessageOpenerError.unsupportedScheme
        }
        guard encryption.recipientEncryptionKeyID == localEncryptionMaterial.encryptionKeyID else {
            throw ExchangeMessageOpenerError.recipientKeyMismatch
        }

        guard let ephemeralKeyData = Data(base64Encoded: encryption.ephemeralPublicKey),
              ephemeralKeyData.count == 32,
              let combinedData = Data(base64Encoded: encryption.ciphertext),
              !combinedData.isEmpty else {
            throw ExchangeMessageOpenerError.invalidCiphertext
        }

        let ephemeralPublicKey: Curve25519.KeyAgreement.PublicKey
        do {
            ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralKeyData)
        } catch {
            throw ExchangeMessageOpenerError.invalidEphemeralKey
        }

        let localPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: localEncryptionMaterial.seed)
        let sharedSecret = try localPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(ExchangeRelayPayloadEncryption.schemeV1.utf8),
            outputByteCount: 32
        )

        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)

        let innerBytes: Data
        do {
            innerBytes = try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw ExchangeMessageOpenerError.openingFailed
        }

        let inner = try JSONDecoder().decode(ExchangePrivateMessagePlaintext.self, from: innerBytes)

        guard encryption.signature.algorithm.lowercased() == "ed25519" else {
            throw ExchangeMessageOpenerError.invalidSignature
        }
        guard let signingKeyRaw = senderSigningPublicKeyBase64?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
              let signingKeyData = Data(base64Encoded: signingKeyRaw),
              signingKeyData.count == 32,
              let signatureData = Data(base64Encoded: encryption.signature.value) else {
            throw ExchangeMessageOpenerError.missingSenderSigningKey
        }

        let signingPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: signingKeyData)
        guard signingPublicKey.isValidSignature(signatureData, for: innerBytes) else {
            throw ExchangeMessageOpenerError.signatureVerificationFailed
        }

        return inner
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
