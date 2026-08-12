import Foundation
import CryptoKit

/// Private DM file attachment metadata (descriptor only — never file bytes).
public struct DirectMessageAttachmentDescriptor: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID { attachmentID }

    public var attachmentID: UUID
    public var filename: String
    public var mimeType: String
    public var byteSize: Int
    public var storageKey: String
    /// Federation-relative download path, e.g. `/v1/dm-attachments/<storageKey>`.
    public var downloadPath: String
    public var sha256: String?
    public var uploadedAt: Date?
    public var accessScope: AccessScope
    /// Present only for locally reconstructed encrypted inbound descriptors (never relay metadata).
    public var encryption: EncryptionMetadata?

    public enum AccessScope: String, Codable, Sendable, Hashable {
        case dmPrivate = "dm_private"
    }

    /// Local decrypt metadata for encrypted DM attachments (Phase C).
    public struct EncryptionMetadata: Codable, Sendable, Hashable {
        public var version: Int
        public var scheme: String
        public var fileNonce: String
        public var encryptedByteSize: Int
        public var wrappedFileKey: String
        public var keyWrapEphemeralPublicKey: String
        public var plaintextSHA256: String?

        public init(
            version: Int = ExchangePrivateAttachmentPlaintext.currentVersion,
            scheme: String = ExchangePrivateAttachmentPlaintext.schemeV1,
            fileNonce: String,
            encryptedByteSize: Int,
            wrappedFileKey: String,
            keyWrapEphemeralPublicKey: String,
            plaintextSHA256: String? = nil
        ) {
            self.version = version
            self.scheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
            self.fileNonce = fileNonce.trimmingCharacters(in: .whitespacesAndNewlines)
            self.encryptedByteSize = max(0, encryptedByteSize)
            self.wrappedFileKey = wrappedFileKey.trimmingCharacters(in: .whitespacesAndNewlines)
            self.keyWrapEphemeralPublicKey = keyWrapEphemeralPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            self.plaintextSHA256 = plaintextSHA256?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
    }

    public var isEncrypted: Bool {
        encryption != nil
    }

    public init(
        attachmentID: UUID = UUID(),
        filename: String,
        mimeType: String,
        byteSize: Int,
        storageKey: String,
        downloadPath: String,
        sha256: String? = nil,
        uploadedAt: Date? = nil,
        accessScope: AccessScope = .dmPrivate,
        encryption: EncryptionMetadata? = nil
    ) {
        self.attachmentID = attachmentID
        self.filename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.byteSize = max(0, byteSize)
        self.storageKey = storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.downloadPath = downloadPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sha256 = sha256?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.uploadedAt = uploadedAt
        self.accessScope = accessScope
        self.encryption = encryption
    }
}

// MARK: - Metadata keys (draft / turn / inbox / relay envelope)

public enum DirectMessageAttachmentMetadata {
    public static let attachmentCountKey = "dm_attachment_count"
    public static let hasAttachmentsKey = "dm_has_attachments"
    public static let attachmentsJSONKey = "dm_attachments_json"
    public static let attachmentsEncryptedKey = "dm_attachments_encrypted"
    public static let innerPlaintextAttachmentsJSONKey = "dm_inner_attachment_plaintext_json"

    public static let encryptedRelayMetadataKeys: [String] = [
        attachmentCountKey,
        hasAttachmentsKey,
        attachmentsEncryptedKey
    ]

    public static let federationMetadataKeys: [String] = [
        attachmentCountKey,
        hasAttachmentsKey,
        attachmentsJSONKey
    ]

    public static func applyEncryptedRelayFlags(to metadata: inout [String: String]) {
        metadata[attachmentCountKey] = "1"
        metadata[hasAttachmentsKey] = "true"
        metadata[attachmentsEncryptedKey] = "true"
        metadata.removeValue(forKey: attachmentsJSONKey)
    }

    public static func applyInnerPlaintextAttachments(
        _ attachments: [ExchangePrivateAttachmentPlaintext],
        to metadata: inout [String: String]
    ) {
        guard let data = try? JSONEncoder().encode(attachments),
              let json = String(data: data, encoding: .utf8),
              !json.isEmpty else {
            metadata.removeValue(forKey: innerPlaintextAttachmentsJSONKey)
            return
        }
        metadata[innerPlaintextAttachmentsJSONKey] = json
    }

    public static func innerPlaintextAttachments(
        from metadata: [String: String]
    ) -> [ExchangePrivateAttachmentPlaintext] {
        guard let raw = metadata[innerPlaintextAttachmentsJSONKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let data = raw.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([ExchangePrivateAttachmentPlaintext].self, from: data)) ?? []
    }

    public static func isEncryptedRelayAttachment(in metadata: [String: String]) -> Bool {
        metadata[attachmentsEncryptedKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    public static func apply(
        descriptors: [DirectMessageAttachmentDescriptor],
        to metadata: inout [String: String]
    ) {
        guard let first = descriptors.first else {
            metadata.removeValue(forKey: attachmentCountKey)
            metadata.removeValue(forKey: hasAttachmentsKey)
            metadata.removeValue(forKey: attachmentsJSONKey)
            return
        }

        let encoded = encodeDescriptors([first])
        metadata[attachmentCountKey] = "1"
        metadata[hasAttachmentsKey] = "true"
        metadata[attachmentsJSONKey] = encoded
    }

    public static func hasAttachment(in metadata: [String: String]) -> Bool {
        metadata[hasAttachmentsKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            || (metadata[attachmentCountKey].flatMap(Int.init) ?? 0) > 0
    }

    public static func descriptors(from metadata: [String: String]) -> [DirectMessageAttachmentDescriptor] {
        guard metadata[hasAttachmentsKey] == "true"
            || (metadata[attachmentCountKey].flatMap(Int.init) ?? 0) > 0 else {
            return []
        }
        guard let raw = metadata[attachmentsJSONKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return []
        }
        return decodeDescriptors(raw)
    }

    public static func encodeDescriptors(_ descriptors: [DirectMessageAttachmentDescriptor]) -> String {
        let payload = Array(descriptors.prefix(1))
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    public static func decodeDescriptors(_ json: String) -> [DirectMessageAttachmentDescriptor] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([DirectMessageAttachmentDescriptor].self, from: data)) ?? []
    }

    /// SHA-256 hex of file bytes for upload integrity (optional descriptor field).
    public static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Reconstructs a local UI/download descriptor from decrypted inner attachment metadata.
    public static func localDescriptor(
        from inner: ExchangePrivateAttachmentPlaintext
    ) -> DirectMessageAttachmentDescriptor {
        DirectMessageAttachmentDescriptor(
            filename: inner.originalFilename,
            mimeType: inner.originalMimeType,
            byteSize: inner.originalByteSize,
            storageKey: inner.storageKey,
            downloadPath: inner.downloadPath,
            sha256: inner.plaintextSHA256,
            encryption: DirectMessageAttachmentDescriptor.EncryptionMetadata(
                version: inner.version,
                scheme: inner.scheme,
                fileNonce: inner.fileNonce,
                encryptedByteSize: inner.encryptedByteSize,
                wrappedFileKey: inner.wrappedFileKey,
                keyWrapEphemeralPublicKey: inner.keyWrapEphemeralPublicKey,
                plaintextSHA256: inner.plaintextSHA256
            )
        )
    }

    public static func localDescriptors(
        from innerAttachments: [ExchangePrivateAttachmentPlaintext]
    ) -> [DirectMessageAttachmentDescriptor] {
        Array(innerAttachments.prefix(1).map(localDescriptor(from:)))
    }
}

public struct DirectMessageOutboundAttachmentInput: Sendable, Hashable {
    public var fileURL: URL
    public var filename: String
    public var mimeType: String

    public init(fileURL: URL, filename: String, mimeType: String) {
        self.fileURL = fileURL
        self.filename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
