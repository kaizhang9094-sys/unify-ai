import Foundation

// MARK: - Policy answerability (log / future enforcement)

public enum ProviderPolicyAnswerability: String, Codable, Sendable, Hashable {
    case answerDirectly
    case answerWithCaveat
    case needsProviderConfirmation
    case notInOffer
    case refuseCommitment
}

// MARK: - Claims

public struct ProviderAllowedClaim: Codable, Sendable, Hashable {
    public var factID: String
    public var text: String
    public var source: ExchangeProviderFactSource

    public init(factID: String, text: String, source: ExchangeProviderFactSource) {
        self.factID = factID
        self.text = text
        self.source = source
    }
}

public struct ProviderMissingClaim: Codable, Sendable, Hashable {
    public var dimension: ProviderInboundDimension
    public var reason: String

    public init(dimension: ProviderInboundDimension, reason: String) {
        self.dimension = dimension
        self.reason = reason
    }
}

// MARK: - Packet

public struct ProviderClaimBoundaryPacket: Codable, Sendable, Hashable {
    public var responseMode: ProviderResponseMode
    public var riskTier: ProviderInboundRiskTier
    public var askedDimensions: [ProviderInboundDimension]
    public var allowedClaims: [ProviderAllowedClaim]
    public var missingClaims: [ProviderMissingClaim]
    public var requiredCaveats: [String]
    public var forbiddenClaims: [String]
    public var requesterClaimsUntrusted: [String]
    public var answerabilityStatus: ProviderPolicyAnswerability
    public var commitmentBoundary: ExchangeCommitmentBoundary?

    public init(
        responseMode: ProviderResponseMode,
        riskTier: ProviderInboundRiskTier,
        askedDimensions: [ProviderInboundDimension],
        allowedClaims: [ProviderAllowedClaim],
        missingClaims: [ProviderMissingClaim],
        requiredCaveats: [String],
        forbiddenClaims: [String],
        requesterClaimsUntrusted: [String],
        answerabilityStatus: ProviderPolicyAnswerability,
        commitmentBoundary: ExchangeCommitmentBoundary? = nil
    ) {
        self.responseMode = responseMode
        self.riskTier = riskTier
        self.askedDimensions = askedDimensions
        self.allowedClaims = allowedClaims
        self.missingClaims = missingClaims
        self.requiredCaveats = requiredCaveats
        self.forbiddenClaims = forbiddenClaims
        self.requesterClaimsUntrusted = requesterClaimsUntrusted
        self.answerabilityStatus = answerabilityStatus
        self.commitmentBoundary = commitmentBoundary
    }

    /// Compact trace for smoke JSONL / facade logs (log-only phase).
    public var traceSummary: ProviderClaimBoundaryTraceSummary {
        ProviderClaimBoundaryTraceSummary(
            dimensions: askedDimensions.map(\.rawValue),
            riskTier: riskTier.rawValue,
            answerabilityStatus: answerabilityStatus.rawValue,
            responseMode: responseMode.rawValue,
            allowedClaimsCount: allowedClaims.count,
            missingClaimsCount: missingClaims.count,
            requiredCaveats: requiredCaveats,
            forbiddenClaimsCount: forbiddenClaims.count,
            requesterClaimsUntrustedCount: requesterClaimsUntrusted.count
        )
    }
}

// MARK: - Validation result (report-only until enforcement phase)

public struct ProviderClaimBoundaryValidationResult: Codable, Sendable, Hashable {
    public var isValid: Bool
    public var severity: Severity
    public var reasons: [Reason]
    public var suggestedAction: SuggestedAction

    public enum Severity: String, Codable, Sendable, Hashable {
        case pass
        case warning
        case blockAutoSend
        case requireProviderApproval
    }

    public enum SuggestedAction: String, Codable, Sendable, Hashable {
        case allow
        case holdForProviderApproval
        case useFallback
    }

    public struct Reason: Codable, Sendable, Hashable {
        public var code: String
        public var message: String
        public var matchedText: String?

        public init(code: String, message: String, matchedText: String? = nil) {
            self.code = code
            self.message = message
            self.matchedText = matchedText
        }
    }

    public init(
        isValid: Bool,
        severity: Severity,
        reasons: [Reason],
        suggestedAction: SuggestedAction
    ) {
        self.isValid = isValid
        self.severity = severity
        self.reasons = reasons
        self.suggestedAction = suggestedAction
    }

    public static let pass = ProviderClaimBoundaryValidationResult(
        isValid: true,
        severity: .pass,
        reasons: [],
        suggestedAction: .allow
    )
}

public struct ProviderClaimBoundaryTraceSummary: Codable, Sendable, Hashable {
    public var dimensions: [String]
    public var riskTier: String
    public var answerabilityStatus: String
    public var responseMode: String
    public var allowedClaimsCount: Int
    public var missingClaimsCount: Int
    public var requiredCaveats: [String]
    public var forbiddenClaimsCount: Int
    public var requesterClaimsUntrustedCount: Int

    public init(
        dimensions: [String],
        riskTier: String,
        answerabilityStatus: String,
        responseMode: String,
        allowedClaimsCount: Int,
        missingClaimsCount: Int,
        requiredCaveats: [String],
        forbiddenClaimsCount: Int,
        requesterClaimsUntrustedCount: Int
    ) {
        self.dimensions = dimensions
        self.riskTier = riskTier
        self.answerabilityStatus = answerabilityStatus
        self.responseMode = responseMode
        self.allowedClaimsCount = allowedClaimsCount
        self.missingClaimsCount = missingClaimsCount
        self.requiredCaveats = requiredCaveats
        self.forbiddenClaimsCount = forbiddenClaimsCount
        self.requesterClaimsUntrustedCount = requesterClaimsUntrustedCount
    }
}
