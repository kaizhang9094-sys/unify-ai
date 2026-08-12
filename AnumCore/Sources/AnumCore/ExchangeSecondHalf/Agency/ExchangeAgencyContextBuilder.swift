import Foundation

/// Assembles `ExchangeAgencyContext` from existing read models without IO or mutation.
public enum ExchangeAgencyContextBuilder {

    // MARK: - Requester

    public static func buildRequesterContext(
        threadID: ExchangeThread.ID? = nil,
        selectedOfferID: ExchangeOffer.ID? = nil,
        selectedPublicProfileID: ExchangePublicNodeProfile.ID? = nil,
        selectedCounterpartyID: ExchangeCounterparty.ID? = nil,
        userIntent: String,
        secretaryStyleText: String? = nil,
        situation: ExchangeThreadSituation? = nil,
        publicProfile: ExchangePublicNodeProfile? = nil,
        offer: ExchangeOffer? = nil,
        operatingMemory: ExchangeStructuredOperatingMemory,
        threadHistoryLines: [String] = [],
        additionalKnownFacts: [String] = [],
        additionalBoundaryHints: [String] = [],
        opportunitySurfaceAnchor: ExchangeOpportunitySurfaceAnchor? = nil,
        intentGaps: [ExchangeRequesterIntentGap] = [],
        intentGapCombinedClarificationQuestion: String? = nil,
        facets: ExchangeIntentFacets? = nil
    ) -> ExchangeAgencyContext {
        let tid = threadID ?? situation?.threadID
        let locationFact = ExchangeSecondHalfLocationResolver.resolve(facets: facets)

        let reachability = situation?.reachabilityLine.agencyNonBlank ?? postureReachabilitySnippet(publicProfile?.reachability)

        var mergedKnown = mergedKnownFacts(
            situation: situation,
            offer: offer,
            profile: publicProfile,
            operatingMemory: operatingMemory,
            additionalKnownFacts: additionalKnownFacts,
            secretaryStyleLine: secretaryStyleText
        )
        if let anchored = ExchangeSecondHalfLocationResolver.knownFactLine(for: locationFact) {
            mergedKnown.insert(anchored, at: 0)
        }

        let intentGapLines = ExchangeRequesterIntentGapReducer.userFacingMissingLines(
            from: intentGaps,
            locationFact: locationFact
        )
        let templateMissing = ExchangeSecondHalfLocationResolver.filterPoisonedMissingFacts(
            mergedMissingFacts(
                situationMissing: situation?.missingFacts ?? [],
                offer: offer,
                profile: publicProfile,
                operatingMemory: operatingMemory
            )
        )
        let missing = dedupePreservingOrder(intentGapLines + templateMissing)
            .prefix(32)
            .map { String($0) }

        let hints = dedupePreservingOrder(
            boundaryHintLines(situation: situation, operatingMemory: operatingMemory)
                + additionalBoundaryHints
        )
            .prefix(16)
            .map { $0 }

        let intentLine = trimmedNonEmpty(userIntent)
            ?? situation?.latestUserIntent
            ?? situation?.title
            ?? ""

        return ExchangeAgencyContext(
            threadID: tid,
            side: .requester,
            selectedOfferID: selectedOfferID ?? situation?.selectedOfferID,
            selectedPublicProfileID: selectedPublicProfileID ?? situation?.selectedPublicProfileID,
            selectedCounterpartyID: selectedCounterpartyID,
            userIntent: intentLine.isEmpty ? "Review surfaced opportunity." : intentLine,
            secretaryStyleText: secretaryStyleText,
            situation: situation,
            publicProfile: publicProfile,
            offer: offer,
            operatingMemory: operatingMemory,
            threadHistoryLines: clippedLines(threadHistoryLines, limit: 12),
            knownFacts: mergedKnown,
            missingFacts: missing,
            intentGaps: intentGaps,
            intentGapCombinedClarificationQuestion: intentGapCombinedClarificationQuestion,
            boundaryHints: hints,
            reachabilityLine: reachability,
            canContactDirectly: canContactDirectly(publicProfile: publicProfile),
            opportunitySurfaceAnchor: opportunitySurfaceAnchor,
            requesterLocationFact: locationFact,
            createdAt: Date()
        )
    }

    // MARK: - Provider

    public static func buildProviderContext(
        threadID: ExchangeThread.ID? = nil,
        selectedOfferID: ExchangeOffer.ID? = nil,
        selectedPublicProfileID: ExchangePublicNodeProfile.ID? = nil,
        selectedCounterpartyID: ExchangeCounterparty.ID? = nil,
        userIntent: String,
        secretaryStyleText: String? = nil,
        situation: ExchangeThreadSituation? = nil,
        publicProfile: ExchangePublicNodeProfile? = nil,
        offer: ExchangeOffer? = nil,
        operatingMemory: ExchangeStructuredOperatingMemory,
        threadHistoryLines: [String] = [],
        additionalKnownFacts: [String] = [],
        opportunitySurfaceAnchor: ExchangeOpportunitySurfaceAnchor? = nil
    ) -> ExchangeAgencyContext {
        let tid = threadID ?? situation?.threadID

        let reachability = situation?.reachabilityLine.agencyNonBlank ?? postureReachabilitySnippet(publicProfile?.reachability)

        let mergedKnown = mergedKnownFacts(
            situation: situation,
            offer: offer,
            profile: publicProfile,
            operatingMemory: operatingMemory,
            additionalKnownFacts: additionalKnownFacts,
            secretaryStyleLine: secretaryStyleText
        )

        let missing = mergedMissingFacts(
            situationMissing: situation?.missingFacts ?? [],
            offer: offer,
            profile: publicProfile,
            operatingMemory: operatingMemory
        )

        let hints = boundaryHintLines(situation: situation, operatingMemory: operatingMemory)

        let intentLine = trimmedNonEmpty(userIntent)
            ?? situation?.latestInboundLine
            ?? situation?.latestOutboundLine
            ?? situation?.title
            ?? ""

        return ExchangeAgencyContext(
            threadID: tid,
            side: .provider,
            selectedOfferID: selectedOfferID ?? situation?.selectedOfferID,
            selectedPublicProfileID: selectedPublicProfileID ?? situation?.selectedPublicProfileID,
            selectedCounterpartyID: selectedCounterpartyID,
            userIntent: intentLine.isEmpty ? "Handle inbound coordination." : intentLine,
            secretaryStyleText: secretaryStyleText,
            situation: situation,
            publicProfile: publicProfile,
            offer: offer,
            operatingMemory: operatingMemory,
            threadHistoryLines: clippedLines(threadHistoryLines, limit: 12),
            knownFacts: mergedKnown,
            missingFacts: missing,
            intentGaps: [],
            intentGapCombinedClarificationQuestion: nil,
            boundaryHints: hints,
            reachabilityLine: reachability,
            canContactDirectly: canContactDirectly(publicProfile: publicProfile),
            opportunitySurfaceAnchor: opportunitySurfaceAnchor,
            createdAt: Date()
        )
    }

    // MARK: - Internals

    private static func mergedKnownFacts(
        situation: ExchangeThreadSituation?,
        offer: ExchangeOffer?,
        profile: ExchangePublicNodeProfile?,
        operatingMemory: ExchangeStructuredOperatingMemory,
        additionalKnownFacts: [String],
        secretaryStyleLine: String?
    ) -> [String] {
        var lines: [String] = []

        if let trimmed = secretaryStyleLine.agencyNonBlank {
            lines.append("Secretary posture: \(trimmed)")
        }

        if let situation {
            lines.append(contentsOf: situation.explanationLines.prefix(16))
            lines.append(contentsOf: situation.strengthReasons.prefix(8))
            lines.append(contentsOf: situation.whatChanged.prefix(6))
            if let t = situation.selectedOfferTitle.agencyNonBlank {
                lines.append("Offer title (surface): \(t)")
            }
            if let s = situation.selectedOfferSummary.agencyNonBlank {
                lines.append("Offer summary (surface): \(s)")
            }
        }

        if let offer {
            lines.append(contentsOf: ExchangeSellerSurfaceOperatingMemoryHydrator.offerFulfillmentFactLines(for: offer))
        }

        if let profile {
            if let dn = profile.displayName.agencyNonBlank {
                lines.append("Seller display name (public): \(dn)")
            }
            if let h = profile.headline.agencyNonBlank {
                lines.append("Seller headline (public): \(h)")
            }
            lines.append("Profile availability posture (public): \(profile.availability.rawValue)")
        }

        lines.append(contentsOf: canonicalLines(from: operatingMemory, limitPerSection: 4))

        lines.append(contentsOf: additionalKnownFacts)

        return dedupePreservingOrder(lines).prefix(48).map { $0 }
    }

    private static func mergedMissingFacts(
        situationMissing: [String],
        offer: ExchangeOffer?,
        profile: ExchangePublicNodeProfile?,
        operatingMemory: ExchangeStructuredOperatingMemory
    ) -> [String] {
        var merged: [String] = []

        merged.append(contentsOf: situationMissing)

        if operatingMemory.standardPolicies.isEmpty
            && operatingMemory.pricingRules.isEmpty
            && offer == nil
            && profile == nil {
            merged.append("Published seller surfaces are not anchored on this snapshot.")
        }

        if offer.flatMap(\.fulfillment.leadTimeNote).agencyNonBlank == nil
            && operatingMemory.leadTimes.isEmpty {
            merged.append("Published lead-time or schedule detail is not anchored.")
        }

        if operatingMemory.capacityRules.isEmpty
            && offer.flatMap(\.fulfillment.capacityNote).agencyNonBlank == nil {
            merged.append("Capacity / throughput specifics are not published.")
        }

        if operatingMemory.coverageAreas.isEmpty
            && offer?.regionTags.isEmpty ?? true
            && profile?.regionTags.isEmpty ?? true {
            merged.append("Geographic/service area fit is underspecified publicly.")
        }

        merged.append(contentsOf: policyGapHints(offer: offer, profile: profile, memory: operatingMemory))

        return dedupePreservingOrder(merged).prefix(32).map { $0 }
    }

    private static func policyGapHints(
        offer: ExchangeOffer?,
        profile: ExchangePublicNodeProfile?,
        memory: ExchangeStructuredOperatingMemory
    ) -> [String] {
        var hints: [String] = []

        let policyTexts = memory.standardPolicies.map { "\($0.title) \($0.details)".lowercased() }.joined()

        func policyMentions(_ term: String) -> Bool {
            policyTexts.contains(term)
        }

        if !policyMentions("refund")
            && !policyMentions("return")
            && !policyMentions("cancellation") {
            hints.append("Cancellation/refund/return posture is not clearly published.")
        }

        if !policyMentions("ship")
            && !policyMentions("delivery")
            && !(offer?.semantic.fulfillmentModes.contains(.shippable) ?? false) {
            if let offer, offer.semantic.notes.agencyNonBlank == nil {
                hints.append("Shipping/delivery modality not clearly described for buyers.")
            }
        }

        if offer?.fulfillment.pricingMode == .undisclosed
            || offer?.fulfillment.pricingMode == .quoteRequired {
            hints.append("Exact commercial price is typically decided after quoting — not disclosed as a single number.")
        }

        _ = profile
        return hints
    }

    private static func boundaryHintLines(
        situation: ExchangeThreadSituation?,
        operatingMemory: ExchangeStructuredOperatingMemory
    ) -> [String] {
        var hints: [String] = []

        if let situation {
            if let boundary = Optional(situation.boundaryLine).agencyNonBlank {
                hints.append(boundary)
            }
            hints.append(contentsOf: situation.weaknessReasons.prefix(6))

            let nextTrim = situation.nextMoveLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !nextTrim.isEmpty {
                hints.append("Next move: \(nextTrim)")
            }

            if let trust = situation.trustLine.agencyNonBlank {
                hints.append("Trust posture snapshot: \(trust)")
            }

            hints.append(contentsOf: situation.agencyBaselineBoundaryHints(prefixLimit: 2))
        }

        if !operatingMemory.exclusions.isEmpty {
            hints.append("Published exclusions/topics: \(operatingMemory.exclusions.prefix(4).joined(separator: "; "))")
        }

        return dedupePreservingOrder(hints).prefix(16).map { $0 }
    }

    private static func clippedLines(_ lines: [String], limit: Int) -> [String] {
        lines
            .compactMap { Optional($0).agencyNonBlank }
            .prefix(limit)
            .map { String($0) }
    }

    private static func canonicalLines(
        from memory: ExchangeStructuredOperatingMemory,
        limitPerSection: Int
    ) -> [String] {
        var out: [String] = []

        for rule in memory.pricingRules.prefix(limitPerSection) {
            out.append("Pricing (\(rule.label)): \(rule.amountDescription)")
        }
        for item in memory.serviceItems.prefix(limitPerSection) {
            let line = nonEmptyConcat(item.name, item.details.map { "; \($0)" } ?? "")
            out.append("Service/item: \(line)")
        }
        for cov in memory.coverageAreas.prefix(limitPerSection) {
            out.append("Coverage: \(cov.name)\(cov.details.map { " — \($0)" } ?? "")")
        }
        for w in memory.availabilityWindows.prefix(limitPerSection) {
            out.append("Availability window: \(w.label)\(w.details.map { " — \($0)" } ?? "")")
        }
        for c in memory.capacityRules.prefix(limitPerSection) {
            out.append("Capacity: \(c.label)\(c.details.map { " — \($0)" } ?? "")")
        }
        for l in memory.leadTimes.prefix(limitPerSection) {
            out.append("Lead time rule: \(l.label) → \(l.turnaroundDescription)")
        }
        for p in memory.standardPolicies.prefix(limitPerSection * 2) {
            out.append("Policy \"\(p.title)\": \(p.details)")
        }
        for rq in memory.requesterConstraints.prefix(limitPerSection) {
            out.append("\(rq.key): \(rq.value)")
        }

        return out
    }

    private static func canContactDirectly(publicProfile: ExchangePublicNodeProfile?) -> Bool {
        guard let pub = publicProfile else {
            return true
        }
        let r = pub.reachability
        if r.accessMode == .closed {
            return false
        }
        if !r.acceptingInbound {
            return false
        }
        if r.accessMode == .introRequired {
            return false
        }
        return true
    }

    private static func postureReachabilitySnippet(_ r: ExchangePublicNodeProfile.ReachabilityPolicy?) -> String? {
        guard let r else { return nil }
        return """
        access=\(r.accessMode.rawValue), acceptingInbound=\(r.acceptingInbound ? "yes" : "no"), \
        disclosureCeiling=\(r.disclosureCeiling.rawValue), routeableOnly=\(r.routeableOnly ? "yes" : "no")
        """
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmedNonEmpty(_ raw: String) -> String? {
        Optional(raw).agencyNonBlank
    }

    private static func dedupePreservingOrder(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            out.append(trimmed)
        }

        return out
    }

    private static func nonEmptyConcat(_ a: String, _ b: String) -> String {
        if b.isEmpty { return a }
        return a + b
    }
}

private extension Optional where Wrapped == String {
    /// Trims whitespace; returns nil when absent or blank.
    var agencyNonBlank: String? {
        switch self {
        case nil:
            return nil

        case let value?:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            return trimmed
        }
    }
}

