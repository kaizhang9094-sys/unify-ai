import Foundation
import AnumCore

/// Fixed identifiers and builders for deterministic second-half engine tests.
enum SecondHalfEngineTestFixtures {
    static let fixtureDate = Date(timeIntervalSince1970: 1_700_000_000)

    static let pricingRuleID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let availabilityID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let coverageID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    static let policyID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!

    static let offerID = "fixture-offer-second-half"
    static let nodeID = "fixture-node-second-half"

    static func memoryWithRoutineFacts() -> ExchangeStructuredOperatingMemory {
        ExchangeStructuredOperatingMemory(
            pricingRules: [
                ExchangeStructuredOperatingMemory.PricingRule(
                    id: pricingRuleID,
                    label: "Home visit",
                    amountDescription: "$120",
                    notes: "Flat rate within metro"
                )
            ],
            coverageAreas: [
                ExchangeStructuredOperatingMemory.CoverageArea(
                    id: coverageID,
                    name: "Metro East",
                    details: "Within 25 miles of downtown"
                )
            ],
            availabilityWindows: [
                ExchangeStructuredOperatingMemory.AvailabilityWindow(
                    id: availabilityID,
                    label: "Weekdays",
                    details: "9am–5pm by appointment"
                )
            ],
            standardPolicies: [
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: policyID,
                    title: "Cancellation",
                    details: "Free cancel up to 24 hours before the visit."
                )
            ]
        )
    }

    /// Commercial facts + auto-answer flags that allow structured pricing, availability, service area, and policies.
    static func permissiveAutoAnswerFacts() -> ExchangeOffer.CommercialFacts {
        ExchangeOffer.CommercialFacts(
            priceDisplay: "$120 visit",
            serviceAreaNote: "Metro East coverage",
            availabilityNote: "Weekdays 9–5",
            cancellationPolicy: "Cancel free up to 24h before.",
            autoAnswerPolicy: ExchangeOffer.AutoAnswerPolicy(
                canAnswerPricing: true,
                canAnswerAvailability: true,
                canAnswerPolicies: true,
                canAnswerServiceArea: true,
                canAnswerFAQs: false,
                requiresApprovalForCustomQuote: true
            )
        )
    }

    static func restrictiveAutoAnswerFacts() -> ExchangeOffer.CommercialFacts {
        ExchangeOffer.CommercialFacts(
            priceDisplay: "$120 visit",
            serviceAreaNote: "Metro East coverage",
            availabilityNote: "Weekdays 9–5",
            cancellationPolicy: "Cancel free up to 24h before.",
            autoAnswerPolicy: ExchangeOffer.AutoAnswerPolicy(
                canAnswerPricing: false,
                canAnswerAvailability: false,
                canAnswerPolicies: false,
                canAnswerServiceArea: false,
                canAnswerFAQs: false,
                requiresApprovalForCustomQuote: true
            )
        )
    }

    static func fixtureOffer(
        commercialFacts: ExchangeOffer.CommercialFacts,
        fulfillment: ExchangeOffer.Fulfillment = ExchangeOffer.Fulfillment(pricingMode: .fixed)
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: offerID,
            nodeID: nodeID,
            title: "Fixture plumbing visit",
            fulfillment: fulfillment,
            status: .active,
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            commercialFacts: commercialFacts
        )
    }

    static func providerContext(
        operatingMemory: ExchangeStructuredOperatingMemory,
        offer: ExchangeOffer?,
        userIntent: String = "Fixture thread intent"
    ) -> ExchangeAgencyContext {
        ExchangeAgencyContext(
            side: .provider,
            userIntent: userIntent,
            offer: offer,
            operatingMemory: operatingMemory,
            createdAt: fixtureDate
        )
    }

    static func explicitSecondHalfPolicy(
        clarificationRoundLimit: Int = 1,
        allowSurfaceWhenPromising: Bool = true
    ) -> ExchangeSecondHalfPolicy {
        ExchangeSecondHalfPolicy(
            clarificationRoundLimit: clarificationRoundLimit,
            allowSurfaceWhenPromising: allowSurfaceWhenPromising,
            minimumSurfaceQualityTier: .promising,
            decisionReadinessThreshold: .decisionReady,
            requireApprovalForCommitmentBearingActions: true,
            requireApprovalForSensitiveActions: true
        )
    }
}
