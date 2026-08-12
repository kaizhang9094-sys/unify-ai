import Foundation

/// Attachment decrypt metadata carried inside sealed `ExchangePrivateMessagePlaintext` (not relay metadata).
public struct ExchangePrivateAttachmentPlaintext: Codable, Sendable, Hashable {
    public static let schemeV1 = "unify.v1.aesgcm-file"
    public static let currentVersion = 1

    public var version: Int
    public var scheme: String
    public var storageKey: String
    public var downloadPath: String
    public var fileNonce: String
    public var encryptedByteSize: Int
    public var originalFilename: String
    public var originalMimeType: String
    public var originalByteSize: Int
    public var plaintextSHA256: String?
    public var wrappedFileKey: String
    public var keyWrapEphemeralPublicKey: String

    public init(
        version: Int = ExchangePrivateAttachmentPlaintext.currentVersion,
        scheme: String = ExchangePrivateAttachmentPlaintext.schemeV1,
        storageKey: String,
        downloadPath: String,
        fileNonce: String,
        encryptedByteSize: Int,
        originalFilename: String,
        originalMimeType: String,
        originalByteSize: Int,
        plaintextSHA256: String? = nil,
        wrappedFileKey: String,
        keyWrapEphemeralPublicKey: String
    ) {
        self.version = version
        self.scheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        self.storageKey = storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.downloadPath = downloadPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fileNonce = fileNonce.trimmingCharacters(in: .whitespacesAndNewlines)
        self.encryptedByteSize = max(0, encryptedByteSize)
        self.originalFilename = originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        self.originalMimeType = originalMimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.originalByteSize = max(0, originalByteSize)
        self.plaintextSHA256 = plaintextSHA256?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.wrappedFileKey = wrappedFileKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keyWrapEphemeralPublicKey = keyWrapEphemeralPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
