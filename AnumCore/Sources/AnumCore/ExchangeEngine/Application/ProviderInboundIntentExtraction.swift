import Foundation

// MARK: - Provider inbound intent (not requester search routing)

public enum ProviderInboundInquiryKind: String, Codable, Sendable, Hashable, CaseIterable {
    case availabilityOrOpenness
    case capabilityOrServiceFit
    case pricingOrQuote
    case schedulingOrTiming
    case logisticsOrFulfillment
    case policyOrTerms
    case introductionOrContact
    case sensitiveDisclosure
    case commitmentRequest
    case socialOrAffinityOnly
    case unclear
}

public enum ProviderInboundRequestedFactSurface: String, Codable, Sendable, Hashable, CaseIterable {
    case publicProfile
    case offer
    case commercialPricing
    case commercialNonPricing
    case reachability
    case operatingMemory
    case policy
    case availability
}

public enum ProviderInboundRequestedClaim: String, Codable, Sendable, Hashable, CaseIterable {
    case openTo
    case availability
    case serviceCapability
    case pricePosture
    case quoteRequired
    case serviceArea
    case leadTime
    case contactPreference
    case policy
    case commitment
}

/// Canonical provider-side interpretation of an inbound requester message (seller fact ownership, not search).
public struct ProviderInboundIntentExtraction: Codable, Sendable, Hashable {
    public var rawRequesterAsk: String
    public var normalizedRequesterQuestion: String
    public var askSummary: String
    public var inquiryKind: ProviderInboundInquiryKind
    public var requestedFactSurfaces: Set<ProviderInboundRequestedFactSurface>
    public var requestedClaims: Set<ProviderInboundRequestedClaim>
    public var commercialIntent: Bool
    public var asksForCommitment: Bool
    public var asksForSensitiveInfo: Bool
    public var needsProviderInputLikely: Bool
    public var needsCompareLLM: Bool
    public var confidence: Double
    public var rationaleShort: String

    public init(
        rawRequesterAsk: String,
        normalizedRequesterQuestion: String,
        askSummary: String,
        inquiryKind: ProviderInboundInquiryKind,
        requestedFactSurfaces: Set<ProviderInboundRequestedFactSurface>,
        requestedClaims: Set<ProviderInboundRequestedClaim>,
        commercialIntent: Bool,
        asksForCommitment: Bool,
        asksForSensitiveInfo: Bool,
        needsProviderInputLikely: Bool,
        needsCompareLLM: Bool,
        confidence: Double,
        rationaleShort: String
    ) {
        self.rawRequesterAsk = rawRequesterAsk
        self.normalizedRequesterQuestion = normalizedRequesterQuestion
        self.askSummary = askSummary
        self.inquiryKind = inquiryKind
        self.requestedFactSurfaces = requestedFactSurfaces
        self.requestedClaims = requestedClaims
        self.commercialIntent = commercialIntent
        self.asksForCommitment = asksForCommitment
        self.asksForSensitiveInfo = asksForSensitiveInfo
        self.needsProviderInputLikely = needsProviderInputLikely
        self.needsCompareLLM = needsCompareLLM
        self.confidence = confidence
        self.rationaleShort = rationaleShort
    }

    /// Labels passed into compare routing metadata (not requester search lanes).
    public var compareRoutingInquiryKindLabel: String { inquiryKind.rawValue }

    public var compareRoutingRequestedSurfacesLabel: String {
        requestedFactSurfaces.map(\.rawValue).sorted().joined(separator: ",")
    }

    public func providerInquiryCompareIntentContextBlock() -> String {
        let surfaces = compareRoutingRequestedSurfacesLabel
        let claims = requestedClaims.map(\.rawValue).sorted().joined(separator: ",")
        return """
        PROVIDER_INBOUND_INTENT (advisory only; compare/governor remain final authority):
        inquiryKind=\(inquiryKind.rawValue)
        requestedFactSurfaces=\(surfaces.isEmpty ? "none" : surfaces)
        requestedClaims=\(claims.isEmpty ? "none" : claims)
        commercialIntent=\(commercialIntent)
        asksForCommitment=\(asksForCommitment)
        asksForSensitiveInfo=\(asksForSensitiveInfo)
        needsProviderInputLikely=\(needsProviderInputLikely)
        needsCompareLLM=\(needsCompareLLM)
        confidence=\(String(format: "%.2f", confidence))
        rationaleShort=\(rationaleShort)

        Do not auto-send because this block says the ask is likely answerable. Disposition is yours.
        """
    }
}

public struct ProviderInboundIntentExtractionRequest: Sendable, Hashable {
    public var rawRequesterAsk: String
    public var threadID: UUID?
    public var selectedCounterpartyID: String?
    public var selectedOfferID: String?
    public var selectedPublicProfileID: String?

    public init(
        rawRequesterAsk: String,
        threadID: UUID? = nil,
        selectedCounterpartyID: String? = nil,
        selectedOfferID: String? = nil,
        selectedPublicProfileID: String? = nil
    ) {
        self.rawRequesterAsk = rawRequesterAsk
        self.threadID = threadID
        self.selectedCounterpartyID = selectedCounterpartyID
        self.selectedOfferID = selectedOfferID
        self.selectedPublicProfileID = selectedPublicProfileID
    }
}

public struct ProviderInboundIntentExtractionDecodeDetails: Sendable, Equatable {
    public let underlyingDescription: String
    public let rawCharacterCount: Int
    public let cleanedCharacterCount: Int

    public init(
        underlyingDescription: String,
        rawCharacterCount: Int,
        cleanedCharacterCount: Int
    ) {
        self.underlyingDescription = underlyingDescription
        self.rawCharacterCount = rawCharacterCount
        self.cleanedCharacterCount = cleanedCharacterCount
    }
}

public enum ProviderInboundIntentExtractionFailure: Error, Sendable, Equatable {
    case decodeFailed(ProviderInboundIntentExtractionDecodeDetails)
}
