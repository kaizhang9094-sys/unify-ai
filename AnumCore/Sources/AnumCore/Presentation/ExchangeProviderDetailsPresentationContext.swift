import Foundation

/// Read-only Details presentation mode derived from thread lane, intent, and surface anchors.
///
/// Phase 2A/2B: logged and carried on build input; section gating in Phase 2B.
public enum ExchangeProviderDetailsPresentationContext: String, Codable, Sendable, Hashable {
    case socialProfile
    case commercialOpportunity
    case opportunityProfile
    case mixedHydrated
    case unknown
}

public enum ExchangeProviderDetailsPresentationContextResolver {

    /// Thread-bound derivation (Secretary thread Details).
    public static func derive(from thread: ExchangeThread) -> ExchangeProviderDetailsPresentationContext {
        let lane = ExchangeThreadLaneResolver.lane(for: thread)
        let queryIntentClass = thread.facets?.queryIntentClass ?? thread.intent.queryIntentClass
        let surfacePreference = thread.facets?.surfacePreference ?? thread.intent.surfacePreference
        let surfaceLead = ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: thread.selectedOfferID,
            selectedPublicProfileID: thread.selectedPublicProfileID
        )
        let hasOfferAnchor = nonBlank(thread.selectedOfferID) != nil
        let hasProfileAnchor = nonBlank(thread.selectedPublicProfileID) != nil

        return derive(
            lane: lane,
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference,
            surfaceLead: surfaceLead,
            hasOfferAnchor: hasOfferAnchor,
            hasProfileAnchor: hasProfileAnchor
        )
    }

    /// Candidate-centric derivation (For You / directory card — no user query thread).
    public static func deriveForCandidate(
        surfaceLead: ExchangePresentationSurfaceLead,
        hasProfile: Bool,
        hasOffer: Bool
    ) -> ExchangeProviderDetailsPresentationContext {
        if surfaceLead == .offerLed, hasOffer {
            return .commercialOpportunity
        }

        if surfaceLead == .profileLed, hasProfile {
            return .opportunityProfile
        }

        if hasOffer, hasProfile {
            return .mixedHydrated
        }

        if hasOffer {
            return .commercialOpportunity
        }

        if hasProfile {
            return .opportunityProfile
        }

        return .unknown
    }

    // MARK: - Core

    static func derive(
        lane: ExchangeThreadLane,
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference,
        surfaceLead: ExchangePresentationSurfaceLead,
        hasOfferAnchor: Bool,
        hasProfileAnchor: Bool
    ) -> ExchangeProviderDetailsPresentationContext {
        // 1. Social lane or social affinity / relationship intent.
        if lane == .socialConnection {
            return .socialProfile
        }

        if isSocialAffinityIntent(queryIntentClass, surfacePreference: surfacePreference) {
            return .socialProfile
        }

        // 2. Direct message / contact lane.
        switch lane {
        case .directMessage, .contactSignal:
            return .unknown
        case .commercialInquiry, .unknown, .socialConnection:
            break
        }

        // 3. Clear commercial offer-led path on commercial inquiry threads.
        if lane == .commercialInquiry,
           (surfaceLead == .offerLed || hasOfferAnchor),
           isCommercialOfferLedCapable(
               queryIntentClass: queryIntentClass,
               surfacePreference: surfacePreference
           ) {
            return .commercialOpportunity
        }

        // 4. Clear profile-led opportunity path on commercial inquiry threads.
        if lane == .commercialInquiry,
           surfaceLead == .profileLed,
           isProfileLedOpportunityCapable(
               queryIntentClass: queryIntentClass,
               surfacePreference: surfacePreference
           ) {
            return .opportunityProfile
        }

        // 5. Non-social offer-led fallback.
        if surfaceLead == .offerLed, hasOfferAnchor {
            return .commercialOpportunity
        }

        // 6. Non-social profile-led fallback.
        if surfaceLead == .profileLed, hasProfileAnchor {
            return .opportunityProfile
        }

        // 7. Both anchors but still unclear after lead/intent classification.
        if hasOfferAnchor, hasProfileAnchor {
            return .mixedHydrated
        }

        // 8. Intent-only fallbacks.
        if isCommercialQueryIntent(queryIntentClass) || surfacePreference == .offer {
            return .commercialOpportunity
        }

        if isOpportunityQueryIntent(queryIntentClass, surfacePreference: surfacePreference) {
            return .opportunityProfile
        }

        // 9.
        return .unknown
    }

    // MARK: - Intent buckets

    private static func isSocialAffinityIntent(
        _ queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference
    ) -> Bool {
        switch queryIntentClass {
        case .socialAffinitySearch, .relationshipSearch:
            return surfacePreference == .affinity || surfacePreference == .mixed
        default:
            return false
        }
    }

    private static func isCommercialOfferLedCapable(
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference
    ) -> Bool {
        switch queryIntentClass {
        case .providerSearch, .offerSearch, .capabilitySearch:
            return true
        default:
            return surfacePreference == .offer
        }
    }

    private static func isProfileLedOpportunityCapable(
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference
    ) -> Bool {
        switch queryIntentClass {
        case .collaborationSearch, .capabilitySearch, .providerSearch:
            return true
        case .generalDiscovery:
            return surfacePreference == .mixed || surfacePreference == .capability
        default:
            return false
        }
    }

    private static func isCommercialQueryIntent(_ queryIntentClass: ExchangeIntent.QueryIntentClass) -> Bool {
        switch queryIntentClass {
        case .providerSearch, .offerSearch:
            return true
        default:
            return false
        }
    }

    private static func isOpportunityQueryIntent(
        _ queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference
    ) -> Bool {
        switch queryIntentClass {
        case .capabilitySearch, .collaborationSearch:
            return true
        case .generalDiscovery:
            return surfacePreference == .capability || surfacePreference == .mixed
        default:
            return false
        }
    }

    private static func nonBlank(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
