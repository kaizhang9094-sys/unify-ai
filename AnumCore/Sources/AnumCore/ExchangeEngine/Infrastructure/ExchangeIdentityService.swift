import Foundation

public enum ExchangeProtocolVersion {
    public static let current = "exchange.v1"
    public static let legacyNumericV1 = "1"
    public static let legacyPrefixedV1 = "v1"

    public static func normalizedVariants(for raw: String) -> Set<String> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        switch trimmed {
        case current, legacyNumericV1, legacyPrefixedV1:
            return [current, legacyNumericV1, legacyPrefixedV1]
        default:
            return [trimmed]
        }
    }

    public static func isSupported(incoming: String, supported: [String]) -> Bool {
        let incomingVariants = normalizedVariants(for: incoming)
        guard !incomingVariants.isEmpty else { return false }

        let supportedVariants = Set(
            supported.flatMap { normalizedVariants(for: $0) }
        )
        return !incomingVariants.isDisjoint(with: supportedVariants)
    }

    public static func normalizedSupportedVersions(from values: [String]) -> [String] {
        var out = Set(
            values.flatMap { normalizedVariants(for: $0) }
        )
        if out.isEmpty {
            out = [current, legacyNumericV1, legacyPrefixedV1]
        }
        return out.sorted()
    }
}

/// Boundary for local Exchange identity.
///
/// This service is responsible for:
/// - exposing the local secretary/node identity
/// - signing outbound envelopes
/// - verifying remote envelope signatures when needed
///
/// It should not own:
/// - thread logic
/// - trust graph logic
/// - transport execution
/// - queue orchestration
public protocol ExchangeIdentityService: Sendable {
    func localIdentity() async throws -> ExchangeLocalIdentity
    func signEnvelope(_ envelope: ExchangeRelayEnvelope) async throws -> ExchangeRelayEnvelope.Signature
    func verifyEnvelopeSignature(
        _ envelope: ExchangeRelayEnvelope,
        expectedKeyID: String?
    ) async throws -> ExchangeEnvelopeVerificationResult
}

public struct ExchangeLocalIdentity: Codable, Sendable, Hashable {
    public var nodeID: String
    public var displayName: String?
    public var publicKeyID: String?
    /// Base64-encoded X25519 public key for private text E2EE (optional until published).
    public var encryptionPublicKey: String?
    /// Stable encryption key identifier, e.g. `ekey-{hash prefix}`.
    public var encryptionKeyID: String?
    public var verification: Verification

    /// Protocol versions this node can read/process for federation envelopes.
    public var supportedProtocolVersions: [String]

    /// Optional default route hint for outbound federation.
    /// This is a hint only, not transport truth.
    public var defaultRouteHint: ExchangeRelayRoute?

    /// Optional profile metadata safe for exchange use.
    public var metadata: [String: String]

    public init(
        nodeID: String,
        displayName: String? = nil,
        publicKeyID: String? = nil,
        encryptionPublicKey: String? = nil,
        encryptionKeyID: String? = nil,
        verification: Verification = .selfAsserted,
        supportedProtocolVersions: [String] = [ExchangeProtocolVersion.current],
        defaultRouteHint: ExchangeRelayRoute? = nil,
        metadata: [String: String] = [:]
    ) {
        let cleanedNodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)

        self.nodeID = cleanedNodeID
        self.displayName = displayName?.nilIfBlank
        self.publicKeyID = publicKeyID?.nilIfBlank
        self.encryptionPublicKey = encryptionPublicKey?.nilIfBlank
        self.encryptionKeyID = encryptionKeyID?.nilIfBlank
        self.verification = verification

        self.supportedProtocolVersions = ExchangeProtocolVersion.normalizedSupportedVersions(
            from: supportedProtocolVersions
        )
        self.defaultRouteHint = defaultRouteHint
        self.metadata = metadata
    }

    public enum Verification: String, Codable, Sendable, CaseIterable, Hashable {
        case unverified
        case selfAsserted
        case cryptographicallyVerified
    }

    public var preferredProtocolVersion: String {
        if supportedProtocolVersions.contains(ExchangeProtocolVersion.current) {
            return ExchangeProtocolVersion.current
        }
        return supportedProtocolVersions.first ?? ExchangeProtocolVersion.current
    }
}

public enum ExchangeEnvelopeVerificationResult: Sendable, Hashable {
    case valid
    case missingSignature
    case missingSenderKey
    case keyMismatch(expected: String?, actual: String?)
    case invalidSignature
    case unsupportedSignatureVersion(String?)
    case malformed(reason: String)

    public var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }

    public var failureReason: String? {
        switch self {
        case .valid:
            return nil
        case .missingSignature:
            return "The envelope has no signature."
        case .missingSenderKey:
            return "The envelope has no sender key information."
        case .keyMismatch(let expected, let actual):
            if let expected, let actual {
                return "The sender key did not match. Expected \(expected), got \(actual)."
            }
            return "The sender key did not match the expected key."
        case .invalidSignature:
            return "The envelope signature could not be validated."
        case .unsupportedSignatureVersion(let version):
            if let version {
                return "Unsupported signature version \(version)."
            }
            return "Unsupported signature version."
        case .malformed(let reason):
            return reason
        }
    }
}

public enum ExchangeIdentityServiceError: Error, Sendable, Hashable {
    case identityUnavailable(reason: String)
    case signingFailed(reason: String)
    case verificationFailed(reason: String)
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
