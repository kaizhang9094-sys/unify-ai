import Foundation

enum ExchangeFederationAttachmentE2EE {
    static let decryptFailurePlaceholder = "Encrypted attachment could not be opened."

    static func logSend(
        encrypted: Bool,
        byteSize: Int? = nil,
        blocked: Bool = false,
        fallback: Bool = false,
        reason: String? = nil
    ) {
        let sizeSuffix = byteSize.map { " byteSize=\($0)" } ?? ""
        let reasonSuffix = reason.map { " reason=\($0)" } ?? ""
        var flags = "encrypted=\(encrypted)"
        if blocked {
            flags += " blocked=true"
        }
        if fallback {
            flags += " fallback=true"
        }
        Swift.print(
            "[E2EE][attachment][send] \(flags)\(sizeSuffix)\(reasonSuffix)"
        )
    }

    static func logReceive(metadataPresent: Bool) {
        Swift.print(
            "[E2EE][attachment][receive] metadataPresent=\(metadataPresent)"
        )
    }

    static func logDownload(encrypted: Bool, decrypted: Bool, reason: String?) {
        let reasonSuffix = reason.map { " reason=\($0)" } ?? ""
        Swift.print(
            "[E2EE][attachment][download] encrypted=\(encrypted) decrypted=\(decrypted)\(reasonSuffix)"
        )
    }

    static func userFacingDecryptFailure(for error: Error) -> String? {
        if case ExchangeDMAttachmentClientError.encryptedDecryptFailed = error {
            return decryptFailurePlaceholder
        }
        if error is ExchangeAttachmentOpenerError {
            return decryptFailurePlaceholder
        }
        return nil
    }

    static func downloadFailureReason(_ error: Error) -> String {
        if let openerError = error as? ExchangeAttachmentOpenerError {
            switch openerError {
            case .unsupportedScheme: return "unsupportedScheme"
            case .invalidCiphertext: return "invalidCiphertext"
            case .invalidWrappedKey: return "invalidWrappedKey"
            case .invalidEphemeralKey: return "invalidEphemeralKey"
            case .keyUnwrapFailed: return "keyUnwrapFailed"
            case .openingFailed: return "openingFailed"
            case .integrityMismatch: return "integrityMismatch"
            }
        }
        if case ExchangeDMAttachmentClientError.encryptedDecryptFailed(let reason) = error {
            return reason
        }
        return "decryptError"
    }
}
