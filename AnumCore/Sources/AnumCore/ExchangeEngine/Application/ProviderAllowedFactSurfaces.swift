import Foundation

/// Local fact-boundary gate for `providerInquiryCompare` only (not a global intent model).
public struct ProviderAllowedFactSurfaces: Sendable, Hashable, Equatable {
    public let includePublicProfile: Bool
    public let includeOffer: Bool
    public let includeCommercialOffer: Bool
    /// When `includeCommercialOffer` is true, whether pricing-scoped commercial facts (display price, ranges, priced packages) may flow.
    public let includeCommercialPricingFacts: Bool
    /// When `includeCommercialOffer` is true, whether non-pricing commercial facts (service area, availability posture, policy skim lines) may flow.
    public let includeCommercialNonPricingFacts: Bool
    public let includeContactReachability: Bool
    public let includeOperatingMemoryDelta: Bool
    public let reason: String

    public init(
        includePublicProfile: Bool,
        includeOffer: Bool,
        includeCommercialOffer: Bool,
        includeContactReachability: Bool,
        includeOperatingMemoryDelta: Bool,
        reason: String,
        includeCommercialPricingFacts: Bool? = nil,
        includeCommercialNonPricingFacts: Bool? = nil
    ) {
        self.includePublicProfile = includePublicProfile
        self.includeOffer = includeOffer
        self.includeCommercialOffer = includeCommercialOffer
        self.includeContactReachability = includeContactReachability
        self.includeOperatingMemoryDelta = includeOperatingMemoryDelta
        self.reason = reason
        self.includeCommercialPricingFacts = includeCommercialPricingFacts ?? includeCommercialOffer
        self.includeCommercialNonPricingFacts = includeCommercialNonPricingFacts ?? includeCommercialOffer
    }

    /// Conservative packet when inbound classification is missing or too weak.
    public static let conservativeUnknown = ProviderAllowedFactSurfaces(
        includePublicProfile: false,
        includeOffer: false,
        includeCommercialOffer: false,
        includeContactReachability: false,
        includeOperatingMemoryDelta: true,
        reason: "unknown_or_unclassified_inbound",
        includeCommercialPricingFacts: false,
        includeCommercialNonPricingFacts: false
    )

    /// Decode failed or absent model output for inbound classification: do not pretend profile/contact/offer are known.
    public static let classificationDecodeFailed = ProviderAllowedFactSurfaces(
        includePublicProfile: false,
        includeOffer: false,
        includeCommercialOffer: false,
        includeContactReachability: false,
        includeOperatingMemoryDelta: false,
        reason: "classification_decode_failed_conservative_unknown",
        includeCommercialPricingFacts: false,
        includeCommercialNonPricingFacts: false
    )

    /// Derives allowed seller-fact surfaces from the latest inbound fast classification only.
    public static func derive(
        latestInbound: ExchangeIntelligenceFastClassificationResponse?
    ) -> ProviderAllowedFactSurfaces {
        guard let latest = latestInbound else {
            return .conservativeUnknown
        }

        if latest.confidence < 0.35 {
            return ProviderAllowedFactSurfaces(
                includePublicProfile: false,
                includeOffer: false,
                includeCommercialOffer: false,
                includeContactReachability: false,
                includeOperatingMemoryDelta: true,
                reason: "low_confidence_inbound_classification",
                includeCommercialPricingFacts: false,
                includeCommercialNonPricingFacts: false
            )
        }

        let q = latest.queryIntentClass
        let s = latest.surfacePreference
        let needsFull = latest.needsFullLLMInterpretation

        if needsFull {
            switch (q, s) {
            case (.directOutreach, .mixed), (.generalDiscovery, .mixed):
                // Ambiguous inbound wording: prefer listing geography + commercial posture, not identity/contact flood.
                return ProviderAllowedFactSurfaces(
                    includePublicProfile: false,
                    includeOffer: true,
                    includeCommercialOffer: true,
                    includeContactReachability: false,
                    includeOperatingMemoryDelta: true,
                    reason: "needs_full_mixed_offer_geography_without_pricing",
                    includeCommercialPricingFacts: false,
                    includeCommercialNonPricingFacts: true
                )
            default:
                break
            }
        }

        switch (q, s) {
        case (.offerSearch, .offer), (.providerSearch, .offer):
            return ProviderAllowedFactSurfaces(
                includePublicProfile: false,
                includeOffer: true,
                includeCommercialOffer: true,
                includeContactReachability: false,
                includeOperatingMemoryDelta: true,
                reason: "transactional_offer_surface"
            )
        case (.socialAffinitySearch, .affinity), (.relationshipSearch, .affinity):
            return ProviderAllowedFactSurfaces(
                includePublicProfile: true,
                includeOffer: false,
                includeCommercialOffer: false,
                includeContactReachability: true,
                includeOperatingMemoryDelta: true,
                reason: "identity_affinity_surface"
            )
        case (.capabilitySearch, .capability), (.collaborationSearch, .capability):
            return ProviderAllowedFactSurfaces(
                includePublicProfile: true,
                includeOffer: false,
                includeCommercialOffer: false,
                includeContactReachability: true,
                includeOperatingMemoryDelta: true,
                reason: "capability_collaboration_surface"
            )
        case (.directOutreach, .offer):
            return ProviderAllowedFactSurfaces(
                includePublicProfile: false,
                includeOffer: true,
                includeCommercialOffer: true,
                includeContactReachability: false,
                includeOperatingMemoryDelta: true,
                reason: "direct_offer_detail_surface"
            )
        case (.directOutreach, .affinity):
            return ProviderAllowedFactSurfaces(
                includePublicProfile: true,
                includeOffer: false,
                includeCommercialOffer: false,
                includeContactReachability: true,
                includeOperatingMemoryDelta: true,
                reason: "direct_reachability_surface"
            )
        case (.followUp, _), (.statusCheck, _):
            return ProviderAllowedFactSurfaces(
                includePublicProfile: true,
                includeOffer: false,
                includeCommercialOffer: false,
                includeContactReachability: true,
                includeOperatingMemoryDelta: true,
                reason: "thread_progress_surface"
            )
        case (.generalDiscovery, .mixed) where !needsFull:
            return ProviderAllowedFactSurfaces(
                includePublicProfile: true,
                includeOffer: true,
                includeCommercialOffer: true,
                includeContactReachability: true,
                includeOperatingMemoryDelta: true,
                reason: "mixed_discovery_both_surfaces"
            )
        default:
            return ProviderAllowedFactSurfaces(
                includePublicProfile: false,
                includeOffer: false,
                includeCommercialOffer: false,
                includeContactReachability: false,
                includeOperatingMemoryDelta: true,
                reason: "unmapped_inbound_classification",
                includeCommercialPricingFacts: false,
                includeCommercialNonPricingFacts: false
            )
        }
    }

    /// Derives allowed seller-fact surfaces from provider-native inbound intent extraction.
    public static func derive(
        from extraction: ProviderInboundIntentExtraction,
        hasHydratedOffer: Bool,
        hasHydratedProfile: Bool
    ) -> ProviderAllowedFactSurfaces {
        if extraction.confidence < 0.35 {
            return ProviderAllowedFactSurfaces(
                includePublicProfile: false,
                includeOffer: false,
                includeCommercialOffer: false,
                includeContactReachability: false,
                includeOperatingMemoryDelta: true,
                reason: "low_confidence_provider_inbound_extraction",
                includeCommercialPricingFacts: false,
                includeCommercialNonPricingFacts: false
            )
        }

        if extraction.inquiryKind == .unclear {
            return conservativeUnknown
        }

        let wantsPricing = explicitlyRequestsPricing(extraction)
        let surfaces = extraction.requestedFactSurfaces

        func union(
            base: ProviderAllowedFactSurfaces,
            surfaces: Set<ProviderInboundRequestedFactSurface>,
            hasOffer: Bool,
            hasProfile: Bool,
            wantsPricing: Bool
        ) -> ProviderAllowedFactSurfaces {
            var profile = base.includePublicProfile
            var offer = base.includeOffer
            var commercial = base.includeCommercialOffer
            var pricing = base.includeCommercialPricingFacts
            var nonPricing = base.includeCommercialNonPricingFacts
            var reach = base.includeContactReachability
            var osm = base.includeOperatingMemoryDelta

            if surfaces.contains(.publicProfile), hasProfile { profile = true }
            if surfaces.contains(.reachability) { reach = true }
            if surfaces.contains(.operatingMemory) { osm = true }
            if surfaces.contains(.offer), hasOffer {
                offer = true
                commercial = true
                nonPricing = true
            }
            if surfaces.contains(.commercialNonPricing), hasOffer {
                offer = true
                commercial = true
                nonPricing = true
            }
            if surfaces.contains(.availability), hasOffer {
                offer = true
                commercial = true
                nonPricing = true
            }
            if surfaces.contains(.policy) {
                osm = true
                if hasOffer {
                    offer = true
                    commercial = true
                    nonPricing = true
                }
            }
            if surfaces.contains(.commercialPricing), hasOffer, wantsPricing {
                offer = true
                commercial = true
                pricing = true
                nonPricing = true
            }

            return ProviderAllowedFactSurfaces(
                includePublicProfile: profile,
                includeOffer: offer,
                includeCommercialOffer: commercial,
                includeContactReachability: reach,
                includeOperatingMemoryDelta: osm,
                reason: base.reason,
                includeCommercialPricingFacts: pricing,
                includeCommercialNonPricingFacts: nonPricing
            )
        }

        switch extraction.inquiryKind {
        case .availabilityOrOpenness:
            return union(
                base: ProviderAllowedFactSurfaces(
                    includePublicProfile: hasHydratedProfile,
                    includeOffer: hasHydratedOffer,
                    includeCommercialOffer: hasHydratedOffer,
                    includeContactReachability: true,
                    includeOperatingMemoryDelta: true,
                    reason: "provider_inbound_availabilityOrOpenness",
                    includeCommercialPricingFacts: false,
                    includeCommercialNonPricingFacts: hasHydratedOffer
                ),
                surfaces: surfaces,
                hasOffer: hasHydratedOffer,
                hasProfile: hasHydratedProfile,
                wantsPricing: wantsPricing
            )

        case .capabilityOrServiceFit:
            return union(
                base: ProviderAllowedFactSurfaces(
                    includePublicProfile: hasHydratedProfile,
                    includeOffer: hasHydratedOffer,
                    includeCommercialOffer: hasHydratedOffer,
                    includeContactReachability: false,
                    includeOperatingMemoryDelta: true,
                    reason: "provider_inbound_capabilityOrServiceFit",
                    includeCommercialPricingFacts: wantsPricing && hasHydratedOffer,
                    includeCommercialNonPricingFacts: hasHydratedOffer
                ),
                surfaces: surfaces,
                hasOffer: hasHydratedOffer,
                hasProfile: hasHydratedProfile,
                wantsPricing: wantsPricing
            )

        case .pricingOrQuote:
            return union(
                base: ProviderAllowedFactSurfaces(
                    includePublicProfile: false,
                    includeOffer: hasHydratedOffer,
                    includeCommercialOffer: hasHydratedOffer,
                    includeContactReachability: false,
                    includeOperatingMemoryDelta: true,
                    reason: "provider_inbound_pricingOrQuote",
                    includeCommercialPricingFacts: hasHydratedOffer,
                    includeCommercialNonPricingFacts: hasHydratedOffer
                ),
                surfaces: surfaces,
                hasOffer: hasHydratedOffer,
                hasProfile: hasHydratedProfile,
                wantsPricing: true
            )

        case .schedulingOrTiming:
            return union(
                base: ProviderAllowedFactSurfaces(
                    includePublicProfile: false,
                    includeOffer: hasHydratedOffer,
                    includeCommercialOffer: hasHydratedOffer,
                    includeContactReachability: false,
                    includeOperatingMemoryDelta: true,
                    reason: "provider_inbound_schedulingOrTiming",
                    includeCommercialPricingFacts: false,
                    includeCommercialNonPricingFacts: hasHydratedOffer
                ),
                surfaces: surfaces,
                hasOffer: hasHydratedOffer,
                hasProfile: hasHydratedProfile,
                wantsPricing: wantsPricing
            )

        case .logisticsOrFulfillment:
            return union(
                base: ProviderAllowedFactSurfaces(
                    includePublicProfile: false,
                    includeOffer: hasHydratedOffer,
                    includeCommercialOffer: hasHydratedOffer,
                    includeContactReachability: false,
                    includeOperatingMemoryDelta: true,
                    reason: "provider_inbound_logisticsOrFulfillment",
                    includeCommercialPricingFacts: false,
                    includeCommercialNonPricingFacts: hasHydratedOffer
                ),
                surfaces: surfaces,
                hasOffer: hasHydratedOffer,
                hasProfile: hasHydratedProfile,
                wantsPricing: wantsPricing
            )

        case .policyOrTerms:
            return union(
                base: ProviderAllowedFactSurfaces(
                    includePublicProfile: false,
                    includeOffer: hasHydratedOffer,
                    includeCommercialOffer: hasHydratedOffer,
                    includeContactReachability: false,
                    includeOperatingMemoryDelta: true,
                    reason: "provider_inbound_policyOrTerms",
                    includeCommercialPricingFacts: false,
                    includeCommercialNonPricingFacts: hasHydratedOffer
                ),
                surfaces: surfaces,
                hasOffer: hasHydratedOffer,
                hasProfile: hasHydratedProfile,
                wantsPricing: wantsPricing
            )

        case .introductionOrContact:
            let includeOffer = extraction.commercialIntent && hasHydratedOffer
            return union(
                base: ProviderAllowedFactSurfaces(
                    includePublicProfile: hasHydratedProfile,
                    includeOffer: includeOffer,
                    includeCommercialOffer: includeOffer,
                    includeContactReachability: true,
                    includeOperatingMemoryDelta: true,
                    reason: "provider_inbound_introductionOrContact",
                    includeCommercialPricingFacts: false,
                    includeCommercialNonPricingFacts: includeOffer
                ),
                surfaces: surfaces,
                hasOffer: hasHydratedOffer,
                hasProfile: hasHydratedProfile,
                wantsPricing: wantsPricing
            )

        case .sensitiveDisclosure:
            return union(
                base: ProviderAllowedFactSurfaces(
                    includePublicProfile: hasHydratedProfile,
                    includeOffer: false,
                    includeCommercialOffer: false,
                    includeContactReachability: false,
                    includeOperatingMemoryDelta: true,
                    reason: "provider_inbound_sensitiveDisclosure",
                    includeCommercialPricingFacts: false,
                    includeCommercialNonPricingFacts: false
                ),
                surfaces: surfaces,
                hasOffer: hasHydratedOffer,
                hasProfile: hasHydratedProfile,
                wantsPricing: false
            )

        case .commitmentRequest:
            return union(
                base: ProviderAllowedFactSurfaces(
                    includePublicProfile: hasHydratedProfile,
                    includeOffer: hasHydratedOffer,
                    includeCommercialOffer: hasHydratedOffer,
                    includeContactReachability: false,
                    includeOperatingMemoryDelta: true,
                    reason: "provider_inbound_commitmentRequest",
                    includeCommercialPricingFacts: wantsPricing && hasHydratedOffer,
                    includeCommercialNonPricingFacts: hasHydratedOffer
                ),
                surfaces: surfaces,
                hasOffer: hasHydratedOffer,
                hasProfile: hasHydratedProfile,
                wantsPricing: wantsPricing
            )

        case .socialOrAffinityOnly:
            return ProviderAllowedFactSurfaces(
                includePublicProfile: hasHydratedProfile,
                includeOffer: false,
                includeCommercialOffer: false,
                includeContactReachability: false,
                includeOperatingMemoryDelta: true,
                reason: "provider_inbound_socialOrAffinityOnly",
                includeCommercialPricingFacts: false,
                includeCommercialNonPricingFacts: false
            )

        case .unclear:
            return conservativeUnknown
        }
    }

    private static func explicitlyRequestsPricing(_ extraction: ProviderInboundIntentExtraction) -> Bool {
        extraction.inquiryKind == .pricingOrQuote
            || extraction.requestedFactSurfaces.contains(.commercialPricing)
            || extraction.requestedClaims.contains(.pricePosture)
            || extraction.requestedClaims.contains(.quoteRequired)
    }

    public func allowedFactBlocksMetadataLine() -> String {
        """
        publicProfile=\(includePublicProfile)
        offer=\(includeOffer)
        commercialOffer=\(includeCommercialOffer)
        commercialPricing=\(includeCommercialPricingFacts)
        commercialNonPricing=\(includeCommercialNonPricingFacts)
        contactReachability=\(includeContactReachability)
        operatingMemoryDelta=\(includeOperatingMemoryDelta)
        """
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
    }
}
