import Foundation

/// Optional composer enrichment dimensions (not compare gaps).
public enum RequesterOutboundEnrichmentDimension: String, Codable, Sendable, Hashable, CaseIterable {
    case pricingProcess
    case estimateRange
    case budgetAlignment
    case commercialTerms
    case shippingOrDelivery
    case productCondition
    case collaborationMode
    case basicLogistics
}
