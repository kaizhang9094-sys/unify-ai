import Foundation

/// Decrypted inner federation message body (DM text v1).
public struct ExchangePrivateMessagePlaintext: Codable, Sendable, Hashable {
    public static let currentVersion = 1

    public var version: Int
    public var body: String
    public var sentAt: String
    public var envelopeID: String?
    public var subject: String?
    public var attachments: [ExchangePrivateAttachmentPlaintext]

    public init(
        version: Int = ExchangePrivateMessagePlaintext.currentVersion,
        body: String,
        sentAt: String,
        envelopeID: String? = nil,
        subject: String? = nil,
        attachments: [ExchangePrivateAttachmentPlaintext] = []
    ) {
        self.version = version
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sentAt = sentAt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.envelopeID = envelopeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.subject = subject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.attachments = attachments
    }
}

extension ExchangePrivateMessagePlaintext {
    static func deterministicJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    func encodedSigningBytes() throws -> Data {
        try Self.deterministicJSONEncoder().encode(self)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
