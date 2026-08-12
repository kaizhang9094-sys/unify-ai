import Foundation

/// Low-level cryptographic boundary for Exchange.
///
/// This service should stay narrow:
/// - sign raw payload bytes
/// - verify raw payload bytes against a signature and key id
///
/// It should not own:
/// - envelope construction
/// - identity policy
/// - trust policy
/// - federation routing
public protocol ExchangeCryptoService: Sendable {
    func sign(
        payload: Data,
        keyID: String,
        algorithm: ExchangeCryptoSignature.Algorithm
    ) async throws -> ExchangeCryptoSignature

    func verify(
        payload: Data,
        signature: ExchangeCryptoSignature,
        keyID: String
    ) async throws -> ExchangeCryptoVerificationResult
}

public struct ExchangeCryptoSignature: Codable, Sendable, Hashable {
    public var algorithm: Algorithm
    public var value: String
    public var keyID: String

    public init(
        algorithm: Algorithm,
        value: String,
        keyID: String
    ) {
        self.algorithm = algorithm
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public extension ExchangeCryptoSignature {
    enum Algorithm: String, Codable, Sendable, CaseIterable, Hashable {
        case ed25519
        case other
    }
}

public enum ExchangeCryptoVerificationResult: Sendable, Hashable {
    case valid
    case invalidSignature
    case keyMismatch(expected: String, actual: String)
    case unsupportedAlgorithm
    case malformedSignature
}

public extension ExchangeCryptoVerificationResult {
    var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }
}

public enum ExchangeCryptoServiceError: Error, Sendable, Hashable {
    case signingFailed(reason: String)
    case verificationFailed(reason: String)
    case invalidKey(reason: String)
    case unsupportedAlgorithm(reason: String)
}
