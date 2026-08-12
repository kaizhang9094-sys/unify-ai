import Foundation

// MARK: - Claim ontology

/// Closed claim types for provider inquiry grounding (deterministic ledger; no LLM).
public enum ProviderClaimType: String, Codable, Sendable, Hashable, CaseIterable {
    case licensed
    case insured
    case certified
    case discountOffered
    case responseTime
    case serviceArea
    case availability
    case exactAvailabilitySlot
    case leadTime
    case pricing
    case packageAvailability
    case warrantyOrGuarantee
    case bookingConfirmation
    case policyException
    case customQuote
    case customDiscount
}

/// Whether a claimable attribute is explicitly published on the seller surface.
public enum ProviderClaimStatus: String, Codable, Sendable, Hashable {
    case present
    case absent
    /// Schema does not yet expose a controlled field for this claim (distinct from seller-intentional absent).
    case unknown
}

public enum ProviderClaimRiskTier: String, Codable, Sendable, Hashable, Comparable {
    case low
    case medium
    case high
    case commitment

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .commitment: return 3
        }
    }

    public static func < (lhs: ProviderClaimRiskTier, rhs: ProviderClaimRiskTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct ProviderClaimLedgerEntry: Codable, Sendable, Hashable {
    public var claimType: ProviderClaimType
    public var status: ProviderClaimStatus
    /// Dot-path style identifier for the schema field that grounded this entry (empty when absent/unknown).
    public var sourceField: String
    /// Trimmed preview of the published value; nil when absent/unknown.
    public var sourceValuePreview: String?
    public var mayAutoAnswer: Bool
    public var requiresProviderConfirmation: Bool
    public var riskTier: ProviderClaimRiskTier

    public init(
        claimType: ProviderClaimType,
        status: ProviderClaimStatus,
        sourceField: String,
        sourceValuePreview: String? = nil,
        mayAutoAnswer: Bool,
        requiresProviderConfirmation: Bool,
        riskTier: ProviderClaimRiskTier
    ) {
        self.claimType = claimType
        self.status = status
        self.sourceField = sourceField
        self.sourceValuePreview = sourceValuePreview
        self.mayAutoAnswer = mayAutoAnswer
        self.requiresProviderConfirmation = requiresProviderConfirmation
        self.riskTier = riskTier
    }
}

/// Deterministic present/absent snapshot for a provider public profile + offer (built at read/hydrate time).
public struct ProviderClaimLedger: Codable, Sendable, Hashable {
    public var entries: [ProviderClaimLedgerEntry]
    public var offerID: ExchangeOffer.ID?
    public var profileID: ExchangePublicNodeProfile.ID?
    public var builtAt: Date

    public init(
        entries: [ProviderClaimLedgerEntry],
        offerID: ExchangeOffer.ID? = nil,
        profileID: ExchangePublicNodeProfile.ID? = nil,
        builtAt: Date = Date()
    ) {
        self.entries = entries
        self.offerID = offerID
        self.profileID = profileID
        self.builtAt = builtAt
    }

    public func entry(for claimType: ProviderClaimType) -> ProviderClaimLedgerEntry? {
        entries.first { $0.claimType == claimType }
    }

    public var presentClaimTypes: [ProviderClaimType] {
        entries.filter { $0.status == .present }.map(\.claimType)
    }

    public var absentClaimTypes: [ProviderClaimType] {
        entries.filter { $0.status == .absent }.map(\.claimType)
    }

    public var unknownClaimTypes: [ProviderClaimType] {
        entries.filter { $0.status == .unknown }.map(\.claimType)
    }

    #if DEBUG
    /// Compact one-line-per-claim trace for smoke audits and console inspection.
    public var debugSummary: String {
        let header = [
            "ProviderClaimLedger",
            "offerID=\(offerID ?? "nil")",
            "profileID=\(profileID ?? "nil")",
            "builtAt=\(ISO8601DateFormatter().string(from: builtAt))"
        ].joined(separator: " ")
        let lines = entries.map { e in
            let preview = e.sourceValuePreview.map { " preview=\"\($0)\"" } ?? ""
            return "  \(e.claimType.rawValue): \(e.status.rawValue) field=\(e.sourceField.isEmpty ? "—" : e.sourceField)\(preview) auto=\(e.mayAutoAnswer) confirm=\(e.requiresProviderConfirmation) risk=\(e.riskTier.rawValue)"
        }
        return ([header] + lines).joined(separator: "\n")
    }
    #endif
}
