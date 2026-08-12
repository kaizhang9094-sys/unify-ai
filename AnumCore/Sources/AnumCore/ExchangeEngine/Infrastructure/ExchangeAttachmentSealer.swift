import Foundation
import CryptoKit
import Security

public enum ExchangeAttachmentSealerError: Error, Sendable, Hashable {
    case invalidRecipientKey
    case emptyFile
    case sealingFailed
    case keyWrapFailed
}

public struct ExchangeAttachmentSealerResult: Sendable {
    public let encryptedData: Data
    public let fileNonce: String
    public let encryptedByteSize: Int
    public let originalFilename: String
    public let originalMimeType: String
    public let originalByteSize: Int
    public let plaintextSHA256: String
    public let wrappedFileKey: String
    public let keyWrapEphemeralPublicKey: String

    func completed(
        storageKey: String,
        downloadPath: String
    ) -> ExchangePrivateAttachmentPlaintext {
        ExchangePrivateAttachmentPlaintext(
            storageKey: storageKey,
            downloadPath: downloadPath,
            fileNonce: fileNonce,
            encryptedByteSize: encryptedByteSize,
            originalFilename: originalFilename,
            originalMimeType: originalMimeType,
            originalByteSize: originalByteSize,
            plaintextSHA256: plaintextSHA256,
            wrappedFileKey: wrappedFileKey,
            keyWrapEphemeralPublicKey: keyWrapEphemeralPublicKey
        )
    }
}

/// Encrypts DM attachment bytes locally before opaque federation upload (Phase B).
public struct ExchangeAttachmentSealer: Sendable {
    public static let fileKeyWrapInfo = "unify.v1.x25519-file-key-wrap"

    public init() {}

    public func seal(
        fileData: Data,
        originalFilename: String,
        originalMimeType: String,
        recipientEncryptionPublicKeyBase64: String
    ) throws -> ExchangeAttachmentSealerResult {
        guard !fileData.isEmpty else {
            throw ExchangeAttachmentSealerError.emptyFile
        }

        guard let recipientKeyData = Data(base64Encoded: recipientEncryptionPublicKeyBase64),
              recipientKeyData.count == 32 else {
            throw ExchangeAttachmentSealerError.invalidRecipientKey
        }

        let recipientPublicKey: Curve25519.KeyAgreement.PublicKey
        do {
            recipientPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientKeyData)
        } catch {
            throw ExchangeAttachmentSealerError.invalidRecipientKey
        }

        var keyMaterial = Data(count: 32)
        let keyStatus = keyMaterial.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard keyStatus == errSecSuccess else {
            throw ExchangeAttachmentSealerError.sealingFailed
        }

        let fileKey = SymmetricKey(data: keyMaterial)
        let sealedFile: AES.GCM.SealedBox
        do {
            sealedFile = try AES.GCM.seal(fileData, using: fileKey)
        } catch {
            throw ExchangeAttachmentSealerError.sealingFailed
        }
        guard let combined = sealedFile.combined else {
            throw ExchangeAttachmentSealerError.sealingFailed
        }

        let wrapEphemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let wrapEphemeralPublicKeyData = wrapEphemeralPrivateKey.publicKey.rawRepresentation
        let wrapSharedSecret = try wrapEphemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let wrapSymmetricKey = wrapSharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(Self.fileKeyWrapInfo.utf8),
            outputByteCount: 32
        )

        let wrappedKeyBox: AES.GCM.SealedBox
        do {
            wrappedKeyBox = try AES.GCM.seal(keyMaterial, using: wrapSymmetricKey)
        } catch {
            throw ExchangeAttachmentSealerError.keyWrapFailed
        }
        guard let wrappedCombined = wrappedKeyBox.combined else {
            throw ExchangeAttachmentSealerError.keyWrapFailed
        }

        return ExchangeAttachmentSealerResult(
            encryptedData: combined,
            fileNonce: Data(sealedFile.nonce).base64EncodedString(),
            encryptedByteSize: combined.count,
            originalFilename: originalFilename,
            originalMimeType: originalMimeType,
            originalByteSize: fileData.count,
            plaintextSHA256: DirectMessageAttachmentMetadata.sha256Hex(of: fileData),
            wrappedFileKey: wrappedCombined.base64EncodedString(),
            keyWrapEphemeralPublicKey: wrapEphemeralPublicKeyData.base64EncodedString()
        )
    }
}
