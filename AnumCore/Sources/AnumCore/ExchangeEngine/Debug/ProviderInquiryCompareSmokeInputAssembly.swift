#if DEBUG
import Foundation

/// Assembles `providerInquiryCompare` inputs for on-device smoke audits.
/// Mirrors production shape from `ExchangeFacade.providerInquiryCompareSellerControlledFactsBlock`
/// and compact summaries — intentionally simplified to avoid coupling to private facade helpers.
enum ProviderInquiryCompareSmokeInputAssembly {

    static func operatingMemorySummary(_ memory: ExchangeStructuredOperatingMemory) -> String {
        var parts: [String] = []
        for r in memory.pricingRules.prefix(6) {
            parts.append("\(r.label): \(r.amountDescription)")
        }
        for s in memory.serviceItems.prefix(6) where s.isActive {
            let detail = s.details.map { " (\($0))" } ?? ""
            parts.append(s.name + detail)
        }
        for a in memory.coverageAreas.prefix(4) {
            let detail = a.details.map { " — \($0)" } ?? ""
            parts.append("area: \(a.name)\(detail)")
        }
        for w in memory.availabilityWindows.prefix(4) {
            let detail = w.details.map { " — \($0)" } ?? ""
            parts.append("availability: \(w.label)\(detail)")
        }
        for lt in memory.leadTimes.prefix(4) {
            parts.append("lead time: \(lt.label) — \(lt.turnaroundDescription)")
        }
        for constraint in memory.requesterConstraints.prefix(8) {
            parts.append("buyer input: \(constraint.key) — \(constraint.value)")
        }
        let joined = parts.joined(separator: " | ")
        return String(joined.prefix(2800))
    }

    /// Smoke compare offer summary — extends gap compact summary with fulfillment lead time when present.
    static func compactProfileSummaryForCompare(
        profile: ExchangePublicNodeProfile?,
        allowedSurfaces: ProviderAllowedFactSurfaces
    ) -> String? {
        ProviderInquiryCompareProfileSummaryGate.compactProfileSummary(
            profile: profile,
            allowedSurfaces: allowedSurfaces,
            applyFactSurfaceGating: true
        )
    }

    static func compactOfferSummaryForCompare(offer: ExchangeOffer?) -> String? {
        guard let offer else { return nil }
        var parts: [String] = []
        if let base = RequesterGapOnDeviceSmokeAuditSupport.pass2CompactOfferSummary(offer: offer) {
            parts.append(base)
        }
        if let lead = trim(offer.fulfillment.leadTimeNote) {
            parts.append("lead time: \(lead)")
        }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    static func consentAutomationSummary(offer: ExchangeOffer?) -> String? {
        guard let facts = offer?.commercialFacts else { return nil }
        let p = facts.permissionOnlyAutoAnswerPolicy()
        return """
        automation_permissions: pricing=\(p.canAnswerPricing), availability=\(p.canAnswerAvailability), policies=\(p.canAnswerPolicies), service_area=\(p.canAnswerServiceArea), faqs=\(p.canAnswerFAQs), custom_quote_requires_approval=\(p.requiresApprovalForCustomQuote)
        """
    }

    static func governorPermissionPolicy(from offer: ExchangeOffer?) -> ProviderInquiryCompareGovernor.PermissionPolicy? {
        guard let policy = offer?.commercialFacts.permissionOnlyAutoAnswerPolicy() else { return nil }
        return ProviderInquiryCompareGovernor.PermissionPolicy(
            canAnswerPricing: policy.canAnswerPricing,
            canAnswerAvailability: policy.canAnswerAvailability,
            canAnswerPolicies: policy.canAnswerPolicies,
            canAnswerServiceArea: policy.canAnswerServiceArea,
            canAnswerFAQs: policy.canAnswerFAQs
        )
    }

    static func primaryOpportunitySurfaceLabel(
        boundaryExpectation: ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.BoundaryExpectation,
        hasOffer: Bool,
        hasProfile: Bool
    ) -> String {
        if !hasOffer && !hasProfile { return "unknown" }
        switch boundaryExpectation {
        case .publicOnly:
            return hasProfile ? "profileSurface" : "unknown"
        case .commercialOnly:
            return hasOffer ? "offerSurface" : "unknown"
        case .mixedSeparated:
            if hasOffer && hasProfile { return "mixed" }
            return hasOffer ? "offerSurface" : "profileSurface"
        case .noAnswer:
            return hasOffer ? "offerSurface" : (hasProfile ? "profileSurface" : "unknown")
        }
    }

    static func sellerControlledFactsBlock(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        operatingMemory: ExchangeStructuredOperatingMemory,
        allowedSurfaces: ProviderAllowedFactSurfaces
    ) -> String {
        var blocks: [String] = []

        if allowedSurfaces.includePublicProfile {
            var profileLines: [String] = ["=== PROFILE_FACTS ==="]
            if let profile {
                if let n = trim(profile.displayName) { profileLines.append("profile_display_name: \(n)") }
                if let h = trim(profile.headline) { profileLines.append("profile_headline: \(h)") }
                if let s = trim(profile.summary) { profileLines.append("profile_summary: \(s)") }
                profileLines.append("profile_availability: \(profile.availability.rawValue)")
                if !profile.regionTags.isEmpty {
                    profileLines.append("profile_region_tags: \(profile.regionTags.joined(separator: ", "))")
                }
                if !profile.openTo.isEmpty {
                    profileLines.append("profile_open_to: \(profile.openTo.joined(separator: ", "))")
                }
                if !profile.activityTags.isEmpty {
                    profileLines.append("profile_activity_tags: \(profile.activityTags.joined(separator: ", "))")
                }
                if !profile.interests.isEmpty {
                    profileLines.append("profile_interests: \(profile.interests.joined(separator: ", "))")
                }
                if !profile.offers.isEmpty {
                    profileLines.append("profile_public_offer_terms: \(profile.offers.joined(separator: ", "))")
                }
            } else {
                profileLines.append("public_profile: (nil)")
            }
            profileLines.append("=== END PROFILE_FACTS ===")
            blocks.append(profileLines.joined(separator: "\n"))
        }

        if allowedSurfaces.includeOffer {
            var offerLines: [String] = ["=== OFFER_FACTS ==="]
            if let offer {
                offerLines.append("offer_id: \(offer.id)")
                offerLines.append("offer_title: \(offer.title)")
                if let s = trim(offer.summary) { offerLines.append("offer_details: \(s)") }
                if let cat = trim(offer.category) { offerLines.append("category: \(cat)") }
                if !offer.tags.isEmpty {
                    offerLines.append("offer_tags: \(offer.tags.joined(separator: ", "))")
                }

                let cf = offer.commercialFacts
                if allowedSurfaces.includeCommercialOffer {
                    if allowedSurfaces.includeCommercialPricingFacts {
                        for skim in offer.commercialSurfaceSkimLines {
                            let t = skim.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !t.isEmpty { offerLines.append("useful_commercial: \(t)") }
                        }
                        if let pd = trim(cf.priceDisplay) { offerLines.append("price_display: \(pd)") }
                        for pkg in cf.packages.prefix(8) {
                            var p = pkg.title
                            if let sum = trim(pkg.summary) { p += " — \(sum)" }
                            offerLines.append("package: \(p)")
                        }
                    }
                    if allowedSurfaces.includeCommercialNonPricingFacts {
                        if let area = trim(cf.serviceAreaNote) { offerLines.append("service_area_note: \(area)") }
                        if let avail = trim(cf.availabilityNote) {
                            offerLines.append("availability_note: \(avail)")
                        }
                        if let cancel = trim(cf.cancellationPolicy) {
                            offerLines.append("cancellation_policy: \(cancel)")
                        }
                        for input in cf.requiredBuyerInputs.prefix(8) {
                            offerLines.append("required_buyer_input: \(input)")
                        }
                        for faq in cf.faqs.prefix(6) {
                            offerLines.append("faq: \(faq.question) — \(faq.answer)")
                        }
                    }
                }
                if let note = trim(offer.fulfillment.leadTimeNote) {
                    offerLines.append("lead_time_note: \(note)")
                }
            } else {
                offerLines.append("offer: (nil)")
            }
            offerLines.append("=== END OFFER_FACTS ===")
            blocks.append(offerLines.joined(separator: "\n"))
        }

        if allowedSurfaces.includeOperatingMemoryDelta {
            let osm = operatingMemorySummary(operatingMemory)
            if !osm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(
                    """
                    === OPERATING_MEMORY_EXCERPT ===
                    \(osm)
                    === END OPERATING_MEMORY_EXCERPT ===
                    """
                )
            }
        }

        return blocks.joined(separator: "\n")
    }

    static func syntheticInboundClassification(
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference
    ) -> ExchangeIntelligenceFastClassificationResponse {
        ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference,
            mode: .transactional,
            kind: .find,
            readiness: .ready,
            confidence: 0.9,
            needsFullLLMInterpretation: false
        )
    }

    /// DEBUG smoke bridge: legacy fixture lanes → provider-native extraction (not production routing).
    static func syntheticInboundIntentExtraction(
        requesterQuestion: String,
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference
    ) -> ProviderInboundIntentExtraction {
        let raw = requesterQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let (kind, surfaces, claims, commercial, commitment, sensitive): (
            ProviderInboundInquiryKind,
            Set<ProviderInboundRequestedFactSurface>,
            Set<ProviderInboundRequestedClaim>,
            Bool,
            Bool,
            Bool
        ) = {
            switch (queryIntentClass, surfacePreference) {
            case (.socialAffinitySearch, .affinity):
                return (
                    .socialOrAffinityOnly,
                    [.publicProfile, .reachability],
                    [],
                    false,
                    false,
                    false
                )
            case (.directOutreach, _), (.followUp, _), (.statusCheck, _):
                return (
                    .socialOrAffinityOnly,
                    [.publicProfile],
                    [],
                    false,
                    false,
                    false
                )
            case (.generalDiscovery, .mixed):
                return (
                    .unclear,
                    [.offer, .commercialNonPricing, .publicProfile],
                    [],
                    true,
                    false,
                    false
                )
            case (.offerSearch, .offer), (.providerSearch, .offer):
                let pricing = raw.localizedCaseInsensitiveContains("pric")
                    || raw.localizedCaseInsensitiveContains("cost")
                    || raw.localizedCaseInsensitiveContains("$")
                if pricing {
                    return (
                        .pricingOrQuote,
                        [.offer, .commercialPricing],
                        [.pricePosture, .quoteRequired],
                        true,
                        false,
                        false
                    )
                }
                return (
                    .capabilityOrServiceFit,
                    [.offer, .publicProfile, .commercialNonPricing],
                    [.serviceCapability],
                    true,
                    false,
                    false
                )
            default:
                return (
                    .unclear,
                    [],
                    [],
                    false,
                    false,
                    false
                )
            }
        }()

        return ProviderInboundIntentExtraction(
            rawRequesterAsk: raw.isEmpty ? requesterQuestion : raw,
            normalizedRequesterQuestion: raw.isEmpty ? requesterQuestion : raw,
            askSummary: "Smoke fixture inbound ask.",
            inquiryKind: kind,
            requestedFactSurfaces: surfaces,
            requestedClaims: claims,
            commercialIntent: commercial,
            asksForCommitment: commitment,
            asksForSensitiveInfo: sensitive,
            needsProviderInputLikely: kind == .unclear,
            needsCompareLLM: true,
            confidence: 0.9,
            rationaleShort: "smoke_fixture_bridge"
        )
    }

    private static func trim(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#endif
