import Foundation
import CryptoKit

public enum ExchangeAttachmentOpenerError: Error, Sendable, Hashable {
    case unsupportedScheme
    case invalidCiphertext
    case invalidWrappedKey
    case invalidEphemeralKey
    case keyUnwrapFailed
    case openingFailed
    case integrityMismatch
}

/// Decrypts locally downloaded DM attachment ciphertext (Phase C).
public struct ExchangeAttachmentOpener: Sendable {
    public init() {}

    public func open(
        encryptedFileData: Data,
        encryption: DirectMessageAttachmentDescriptor.EncryptionMetadata,
        localEncryptionMaterial: NodeEncryptionMaterial
    ) throws -> Data {
        guard encryption.scheme == ExchangePrivateAttachmentPlaintext.schemeV1 else {
            throw ExchangeAttachmentOpenerError.unsupportedScheme
        }

        let fileKeyMaterial = try unwrapFileKey(
            encryption: encryption,
            localEncryptionMaterial: localEncryptionMaterial
        )
        let fileKey = SymmetricKey(data: fileKeyMaterial)

        guard let combined = encryptedFileData.nilIfEmpty else {
            throw ExchangeAttachmentOpenerError.invalidCiphertext
        }

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw ExchangeAttachmentOpenerError.invalidCiphertext
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: fileKey)
        } catch {
            throw ExchangeAttachmentOpenerError.openingFailed
        }

        if let expected = encryption.plaintextSHA256?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
           !expected.isEmpty {
            let actual = DirectMessageAttachmentMetadata.sha256Hex(of: plaintext)
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                throw ExchangeAttachmentOpenerError.integrityMismatch
            }
        }

        return plaintext
    }

    private func unwrapFileKey(
        encryption: DirectMessageAttachmentDescriptor.EncryptionMetadata,
        localEncryptionMaterial: NodeEncryptionMaterial
    ) throws -> Data {
        guard let ephemeralKeyData = Data(base64Encoded: encryption.keyWrapEphemeralPublicKey),
              ephemeralKeyData.count == 32,
              let wrappedCombined = Data(base64Encoded: encryption.wrappedFileKey),
              !wrappedCombined.isEmpty else {
            throw ExchangeAttachmentOpenerError.invalidWrappedKey
        }

        let ephemeralPublicKey: Curve25519.KeyAgreement.PublicKey
        do {
            ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralKeyData)
        } catch {
            throw ExchangeAttachmentOpenerError.invalidEphemeralKey
        }

        let localPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: localEncryptionMaterial.seed)
        let sharedSecret = try localPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        let wrapSymmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(ExchangeAttachmentSealer.fileKeyWrapInfo.utf8),
            outputByteCount: 32
        )

        let wrappedBox: AES.GCM.SealedBox
        do {
            wrappedBox = try AES.GCM.SealedBox(combined: wrappedCombined)
        } catch {
            throw ExchangeAttachmentOpenerError.invalidWrappedKey
        }

        do {
            return try AES.GCM.open(wrappedBox, using: wrapSymmetricKey)
        } catch {
            throw ExchangeAttachmentOpenerError.keyUnwrapFailed
        }
    }
}

private extension Data {
    var nilIfEmpty: Data? {
        isEmpty ? nil : self
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
