import Foundation

// MARK: - Output

/// Deterministic projection of buyer-side information sufficiency Pass 1.
public struct ExchangeRequesterDecisionNeeds: Codable, Sendable, Hashable {

    public enum Readiness: String, Codable, Sendable, Hashable {
        case weak
        case needsFacts
        case reviewReady
        case decisionReady
    }

    public var knownDecisionFacts: [String]
    public var missingDecisionFacts: [String]
    public var recommendedQuestions: [String]

    /// Coarse heuristic for surfaced agency UI — not transactional truth.
    public var decisionReadiness: Readiness

    /// Short explanation auditors can read verbatim.
    public var rationale: String

    public init(
        knownDecisionFacts: [String],
        missingDecisionFacts: [String],
        recommendedQuestions: [String],
        decisionReadiness: Readiness,
        rationale: String
    ) {
        self.knownDecisionFacts = knownDecisionFacts
        self.missingDecisionFacts = missingDecisionFacts
        self.recommendedQuestions = recommendedQuestions
        self.decisionReadiness = decisionReadiness
        self.rationale = rationale
    }
}

// MARK: - Engine

public struct ExchangeRequesterDecisionNeedsEngine: Sendable {

    public init() {}

    public func evaluate(context: ExchangeAgencyContext) -> ExchangeRequesterDecisionNeeds {
        guard context.side == .requester else {
            return ExchangeRequesterDecisionNeeds(
                knownDecisionFacts: [],
                missingDecisionFacts: [],
                recommendedQuestions: [],
                decisionReadiness: .weak,
                rationale:
                    "Context is marked for provider-side reasoning; rerun with a requester-bound `ExchangeAgencyContext`."
            )
        }

        let anchoredSurface = anchoredSurfaceSignals(context)

        let knownFacts = extractKnownFacts(context: context, anchored: anchoredSurface)

        let missingFacts = filterLocationMissingFacts(
            synthesizedMissingFacts(
                contextMissing: dedupePreserve(context.missingFacts, cap: 32),
                context: context
            ),
            context: context
        )

        let questions = buildRecommendedQuestions(
            from: missingFacts,
            context: context
        )

        let readiness = classifyReadiness(
            anchoredSurface: anchoredSurface,
            missingCount: missingFacts.count,
            intentGaps: context.intentGaps,
            context: context
        )

        let rationale = userFacingRationale(
            readiness: readiness,
            anchoredSurface: anchoredSurface,
            context: context
        )

        #if DEBUG
        let facetAnchored = context.intentGaps.filter {
            $0.source == "canonicalIntent" || $0.source == "constraint"
        }.count
        let llmAnchored = context.intentGaps.filter { $0.source == "llmCompare" }.count
        let cautionAnchored = context.intentGaps.filter { $0.source == "matchCaution" }.count
        let intentLineCount = missingFacts.filter { $0.hasPrefix("Intent gap") }.count
        let nonIntentLines = max(0, missingFacts.count - intentLineCount)
        Swift.print(
            "[RequesterDecisionNeeds] thread=\(context.threadID?.uuidString ?? "nil") " +
                "facetGaps=\(facetAnchored) llmCompareGaps=\(llmAnchored) matchCautionGaps=\(cautionAnchored) " +
                "intentGapLines=\(intentLineCount) otherMissingLines=\(nonIntentLines) " +
                "readiness=\(readiness.rawValue)"
        )
        #endif

        return ExchangeRequesterDecisionNeeds(
            knownDecisionFacts: knownFacts.prefix(48).map { $0 },
            missingDecisionFacts: missingFacts,
            recommendedQuestions: questions,
            decisionReadiness: readiness,
            rationale: rationale
        )
    }

    private func userFacingRationale(
        readiness: ExchangeRequesterDecisionNeeds.Readiness,
        anchoredSurface: AnchoredSurfaceSignals,
        context: ExchangeAgencyContext
    ) -> String {
        var sentences: [String] = []

        switch readiness {
        case .weak:
            sentences.append("This path still looks thin; add detail or keep looking.")
        case .needsFacts:
            sentences.append("Worth clarifying before you decide.")
        case .reviewReady:
            sentences.append("Enough is on the page to review this match.")
        case .decisionReady:
            sentences.append("Enough public and thread detail to decide from.")
        }

        if anchoredSurface.offer != nil {
            sentences.append("Has a published offer tied to this thread.")
        } else {
            sentences.append("No offer is attached on this snapshot.")
        }

        if anchoredSurface.profile != nil {
            sentences.append("Has a public profile to compare.")
        } else {
            sentences.append("No public profile is attached on this snapshot.")
        }

        if context.operatingMemory.hasProviderFacts {
            sentences.append("Has enough public commercial detail to ground simple questions.")
        } else {
            sentences.append("Published commercial detail is still light.")
        }

        return sentences.joined(separator: " ")
    }

    private func extractKnownFacts(context: ExchangeAgencyContext, anchored: AnchoredSurfaceSignals) -> [String] {
        var bucket: [String] = []

        bucket.append(contentsOf: context.knownFacts)

        if let offer = anchored.offer ?? context.offer {
            let f = offer.fulfillment
            bucket.append("Pricing posture (published): \(f.pricingMode.displayLabel)")
            bucket.append("Commitment posture (published): \(f.commitmentMode.displayLabel)")
            bucket.append("Remote readiness (published): \(f.remoteFriendly ? "remote-friendly signal" : "non-remote leaning")")

            bucket.append(contentsOf: ExchangeSellerSurfaceOperatingMemoryHydrator.offerFulfillmentFactLines(for: offer))
            bucket.append(contentsOf: Array(offer.commercialSurfaceSkimLines.prefix(8)))
        }

        if let profile = anchored.profile ?? context.publicProfile {
            bucket.append("Profile availability (coarse): \(profile.availability.rawValue)")
            bucket.append("Profile shows how they can be reached using public fields.")
        }

        return dedupePreserve(bucket, cap: 48)
    }

    private func synthesizedMissingFacts(
        contextMissing: [String],
        context: ExchangeAgencyContext
    ) -> [String] {
        var misses: [String] = []

        misses.append(contentsOf: contextMissing)

        let anchor = resolvedOpportunityAnchor(for: context)
        let bundle = PublicationBundle(
            context: context,
            anchor: anchor,
            requesterLocationFact: context.requesterLocationFact
        )

        var templateFacts = bundle.templateMissingFacts()
        if !context.intentGaps.isEmpty {
            templateFacts = Array(templateFacts.prefix(4))
        }
        misses.append(contentsOf: templateFacts)

        let hydratedOffer = context.offer != nil
        let hydratedProfile = context.publicProfile != nil

        let filtered = anchor.filterOpportunityMissingFactLines(
            misses,
            hasHydratedOffer: hydratedOffer,
            hasHydratedProfile: hydratedProfile
        )

        let serviceOfferAdjusted = suppressProductLogisticsMissingFactsIfServiceLikeOffer(
            filtered,
            offer: context.offer
        )

        let locationAdjusted = filterMisleadingRequesterLocationMissingFacts(
            serviceOfferAdjusted,
            context: context
        )

        #if DEBUG
        Swift.print(
            "[OpportunityQualificationMissing] resolvedSurface=\(Self.debugSurfaceLabel(anchor)) " +
                "before=\(misses.count) after=\(locationAdjusted.count) " +
                "emitted=\(locationAdjusted.joined(separator: " | "))"
        )
        #endif

        return dedupePreserve(locationAdjusted, cap: 32)
    }

    private func filterMisleadingRequesterLocationMissingFacts(
        _ lines: [String],
        context: ExchangeAgencyContext
    ) -> [String] {
        let fact = context.requesterLocationFact
        return lines.filter { line in
            !ExchangeSecondHalfLocationResolver.isMisleadingRequesterLocationUnresolvedLine(
                line,
                locationFact: fact
            )
        }
    }

    /// Drops B2B / product-logistics scaffolding when the surfaced offer reads like a lesson or local service.
    private func suppressProductLogisticsMissingFactsIfServiceLikeOffer(
        _ lines: [String],
        offer: ExchangeOffer?
    ) -> [String] {
        guard isLikelyServiceLessonOrLocalOffer(offer) else { return lines }
        return lines.filter { !Self.lineLooksLikeProductLogisticsMissingFact($0) }
    }

    private func isLikelyServiceLessonOrLocalOffer(_ offer: ExchangeOffer?) -> Bool {
        guard let offer else { return false }
        let modes = offer.semantic.fulfillmentModes
        if modes.contains(.inPerson) || modes.contains(.localOnly) || modes.contains(.localPreferred) {
            return true
        }
        if modes.contains(.remoteFriendly), !modes.contains(.shippable) {
            return true
        }
        let summary = offer.summary ?? ""
        let category = offer.category ?? ""
        let tagRun = offer.tags.joined(separator: " ")
        let domainRun = offer.semantic.domains.joined(separator: " ")
        let kindRun = offer.semantic.serviceKinds.joined(separator: " ")
        let notes = offer.semantic.notes ?? ""
        let hay = "\(offer.title) \(summary) \(category) \(tagRun) \(domainRun) \(kindRun) \(notes)"
            .lowercased()
        return Self.serviceLessonHayNeedles.contains { hay.contains($0) }
    }

    private static let serviceLessonHayNeedles: [String] = [
        "lesson", "tutor", "music", "piano", "class", "coaching", "session", "appointment",
        "therapy", "consult", "training", "instruction", "teach", "teacher", "yoga", "fitness"
    ]

    private static func lineLooksLikeProductLogisticsMissingFact(_ line: String) -> Bool {
        let lower = line.lowercased()
        let badSubstrings = [
            "freight", "shipping channel", "shipping/delivery", "carrier", "insurance", "threshold",
            "throughput", "batch limit", "hardened production", "production / delivery",
            "minimum order", " moq", "negotiation/discount knobs", "invoiced amount for your scope",
            "quoting workbook", "numeric tariff", "capacity / throughput"
        ]
        return badSubstrings.contains { lower.contains($0) }
    }

    private func resolvedOpportunityAnchor(for context: ExchangeAgencyContext) -> ExchangeOpportunitySurfaceAnchor {
        if let explicit = context.opportunitySurfaceAnchor {
            return explicit
        }
        if context.offer != nil {
            return .offerSurface
        }
        if context.publicProfile != nil {
            return .profileSurface
        }
        return .counterpartyNode
    }

    private static func debugSurfaceLabel(_ anchor: ExchangeOpportunitySurfaceAnchor) -> String {
        switch anchor {
        case .offerSurface: return "offer"
        case .profileSurface: return "profile"
        case .counterpartyNode: return "counterpartyNode"
        }
    }

    private func filterLocationMissingFacts(
        _ lines: [String],
        context: ExchangeAgencyContext
    ) -> [String] {
        var filtered = ExchangeSecondHalfLocationResolver.filterRequesterLocationMissingFactLines(
            lines,
            locationFact: context.requesterLocationFact
        )
        if hasSearchAreaClarificationGap(context) {
            filtered = filtered.filter { line in
                let lower = line.lowercased()
                return !lower.contains("locationtext: me") && !lower.contains("location: me")
            }
            if !filtered.contains(where: { $0.contains("What city or area should I search in?") }) {
                filtered.insert("What city or area should I search in?", at: 0)
            }
        }
        return dedupePreserve(filtered, cap: 32)
    }

    private func hasSearchAreaClarificationGap(_ context: ExchangeAgencyContext) -> Bool {
        context.intentGaps.contains { gap in
            gap.label == "Search area" && gap.source == "secondHalfLocation"
        }
    }

    private func buildRecommendedQuestions(
        from missing: [String],
        context: ExchangeAgencyContext
    ) -> [String] {
        var rows: [String] = []

        if hasSearchAreaClarificationGap(context) {
            rows.append("What city or area should I search in?")
        }

        if let combined = context.intentGapCombinedClarificationQuestion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !combined.isEmpty,
           !ExchangeSecondHalfLocationResolver.isPoisonedMissingFactLine(combined) {
            rows.append(combined)
        }

        let hasAnchoredProviderSurface = context.offer != nil || context.publicProfile != nil
        let sortedGaps = context.intentGaps.sorted { $0.priority < $1.priority }
        for gap in sortedGaps {
            if gap.source == "secondHalfLocation" { continue }
            if let fact = context.requesterLocationFact,
               ExchangeSecondHalfLocationResolver.isRequesterLocationIntentGap(gap, locationFact: fact) {
                continue
            }
            if let q = gap.questionForProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
                if ExchangeSecondHalfLocationResolver.isPoisonedMissingFactLine(q) { continue }
                if !hasAnchoredProviderSurface,
                   ExchangeSecondHalfLocationResolver.isProviderServeLocationQuestion(q) {
                    continue
                }
                let exists = rows.contains { $0.caseInsensitiveCompare(q) == .orderedSame }
                if !exists {
                    rows.append(q)
                }
            }
            if rows.count >= 6 { break }
        }

        if let intake = context.offer?.commercialFacts.requiredBuyerInputs,
           !intake.isEmpty {
            rows.append(contentsOf: intake.prefix(5).compactMap { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return "Seller expects: \(trimmed)"
            })
        }

        let stubSource = ExchangeSecondHalfLocationResolver.filterPoisonedMissingFacts(
            missing.filter { !$0.hasPrefix("Intent gap") }
        )
        if !stubSource.isEmpty, !hasSearchAreaClarificationGap(context) {
            rows.append(
                contentsOf: Array(stubSource.prefix(5).compactMap(questionStub(for:)).prefix(2))
            )
        }

        rows = ExchangeSecondHalfLocationResolver.filterPoisonedRecommendedQuestions(rows)
        rows = ExchangeSecondHalfLocationResolver.filterProviderQuestionsWithoutSurface(
            rows,
            hasAnchoredProviderSurface: hasAnchoredProviderSurface
        )

        return dedupeQuestionRows(rows, max: 8)
    }

    private func dedupeQuestionRows(_ rows: [String], max: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for row in rows {
            let t = row.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let key = t.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(t)
            if out.count >= max { break }
        }
        return out
    }

    private func classifyReadiness(
        anchoredSurface: AnchoredSurfaceSignals,
        missingCount: Int,
        intentGaps: [ExchangeRequesterIntentGap],
        context _: ExchangeAgencyContext
    ) -> ExchangeRequesterDecisionNeeds.Readiness {
        guard anchoredSurface.intensity != .none else {
            return .weak
        }

        if hasBlockingIntentGaps(intentGaps) {
            if missingCount >= 10 { return .needsFacts }
            return .reviewReady
        }

        if missingCount <= 2
            && anchoredSurface.offer != nil
            && anchoredSurface.hasCoverageSignal {
            return .decisionReady
        }

        if missingCount >= 10 {
            return .needsFacts
        }

        if missingCount >= 6 {
            return .needsFacts
        }

        if anchoredSurface.offer != nil {
            return missingCount <= 4 ? .reviewReady : .needsFacts
        }

        return .reviewReady
    }

    /// True when unknown/mismatch gaps still need resolution before treating the thread as decision-ready.
    private func hasBlockingIntentGaps(_ gaps: [ExchangeRequesterIntentGap]) -> Bool {
        gaps.contains { gap in
            switch gap.status {
            case .mismatch:
                return true
            case .unknown:
                switch gap.kind {
                case .preference:
                    return gap.label.lowercased().contains("required")
                default:
                    return true
                }
            case .optionalUnknown, .satisfied:
                return false
            }
        }
    }

    private func questionStub(for missing: String) -> String? {
        if ExchangeSecondHalfLocationResolver.isPoisonedMissingFactLine(missing) {
            return nil
        }
        let lower = missing.lowercased()

        func q(_ literal: String) -> String {
            literal
        }

        if lower.contains("price") || lower.contains("quote") {
            return q("What explicit price range or quoting process applies to my exact requirement?")
        }

        if lower.contains("cancellation") || lower.contains("refund") || lower.contains("return") {
            return q("Can you summarize cancellation/refund/return protections for my scenario?")
        }

        if lower.contains("ship") || lower.contains("deliver") {
            return q("What delivery modality, transit time, or pickup expectations apply geographically?")
        }

        if lower.contains("timeline") || lower.contains("lead") {
            return q("What hardened timeline should I rely on beyond high-level cues?")
        }

        return q(
            missing.hasSuffix("?") ? missing : "Could you clarify: \(missing)"
        )
    }

    private func anchoredSurfaceSignals(_ context: ExchangeAgencyContext) -> AnchoredSurfaceSignals {
        let offer = context.offer
        let profile = context.publicProfile

        let coverageTokens =
            !(offer?.regionTags.isEmpty ?? true) ||
            !(context.publicProfile?.regionTags.isEmpty ?? true) ||
            !context.operatingMemory.coverageAreas.isEmpty ||
            !(offer?.commercialFacts.serviceAreaNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let hasOffer = offer != nil
        let hasProfile = profile != nil
        let hasMemory = context.operatingMemory.hasProviderFacts

        let intensity: AnchorIntensity

        switch (hasOffer, hasProfile, hasMemory) {
        case (false, false, false):
            intensity = .none
        case (true, true, true):
            intensity = .strong
        case (true, false, true),
             (false, true, true),
             (true, true, false):
            intensity = .mediumStrong
        default:
            intensity = (hasOffer || hasProfile || hasMemory) ? .medium : .none
        }

        return AnchoredSurfaceSignals(
            offer: offer,
            profile: profile,
            hasCoverageSignal: coverageTokens,
            intensity: intensity
        )
    }

    private enum AnchorIntensity: String, Sendable, Hashable {
        case none
        case light
        case medium
        case mediumStrong
        case strong
    }

    private struct AnchoredSurfaceSignals: Sendable, Hashable {
        var offer: ExchangeOffer?
        var profile: ExchangePublicNodeProfile?
        var hasCoverageSignal: Bool
        var intensity: AnchorIntensity
    }

    private struct PublicationBundle {
        let offer: ExchangeOffer?
        let profile: ExchangePublicNodeProfile?
        let memory: ExchangeStructuredOperatingMemory
        let anchor: ExchangeOpportunitySurfaceAnchor
        let requesterLocationFact: ExchangeSecondHalfLocationFact?

        init(
            context: ExchangeAgencyContext,
            anchor: ExchangeOpportunitySurfaceAnchor,
            requesterLocationFact: ExchangeSecondHalfLocationFact?
        ) {
            self.offer = context.offer
            self.profile = context.publicProfile
            self.memory = context.operatingMemory
            self.anchor = anchor
            self.requesterLocationFact = requesterLocationFact
        }

        func templateMissingFacts() -> [String] {
            switch anchor {
            case .offerSurface:
                return templateMissingFactsOfferSurface()
            case .profileSurface:
                return templateMissingFactsProfileSurface()
            case .counterpartyNode:
                return templateMissingFactsCounterpartyNode()
            }
        }

        /// Full commercial / fulfillment template used when the thread is offer-led.
        private func templateMissingFactsOfferSurface() -> [String] {
            if isLikelyServiceLessonOrLocalOffer(offer) {
                return templateMissingFactsServiceLessonOfferSurface()
            }

            var misses: [String] = []

            misses.append(contentsOf: priceGap())
            misses.append(contentsOf: shippingGap())
            misses.append(contentsOf: policyGap())

            let noteEmpty =
                offer?.fulfillment.leadTimeNote.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                } ?? true

            let leadMissing = memory.leadTimes.isEmpty && noteEmpty && offer != nil

            if leadMissing {
                misses.append("Hardened production / delivery timeline commitments are not surfaced.")
            }

            let hasCapacityNote = offer?.fulfillment.capacityNote.map {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? false

            let capacityVacant = memory.capacityRules.isEmpty && !hasCapacityNote && offer != nil

            if capacityVacant {
                misses.append(
                    """
                    Throughput / concurrency / batch limits are unspecified beyond capacity notes.
                    """
                )
            }

            misses.append(contentsOf: minimumGap())
            misses.append(contentsOf: locationFitMisses())
            return misses
        }

        /// Offer-led path for local / lesson-style services: avoid freight, MOQ, and manufacturing scaffolding.
        private func templateMissingFactsServiceLessonOfferSurface() -> [String] {
            var misses: [String] = []
            misses.append(contentsOf: priceGap())
            misses.append(contentsOf: locationFitMisses())
            return misses
        }

        private func isLikelyServiceLessonOrLocalOffer(_ offer: ExchangeOffer?) -> Bool {
            guard let offer else { return false }
            let modes = offer.semantic.fulfillmentModes
            if modes.contains(.inPerson) || modes.contains(.localOnly) || modes.contains(.localPreferred) {
                return true
            }
            if modes.contains(.remoteFriendly), !modes.contains(.shippable) {
                return true
            }
            let summary = offer.summary ?? ""
            let category = offer.category ?? ""
            let tagRun = offer.tags.joined(separator: " ")
            let domainRun = offer.semantic.domains.joined(separator: " ")
            let kindRun = offer.semantic.serviceKinds.joined(separator: " ")
            let notes = offer.semantic.notes ?? ""
            let hay = "\(offer.title) \(summary) \(category) \(tagRun) \(domainRun) \(kindRun) \(notes)"
                .lowercased()
            return ExchangeRequesterDecisionNeedsEngine.serviceLessonHayNeedles.contains { hay.contains($0) }
        }

        /// Profile-led threads: avoid offer-commercial scaffolding; keep policy + geography (+ optional MOQ when an offer row exists).
        private func templateMissingFactsProfileSurface() -> [String] {
            var misses: [String] = []
            misses.append(contentsOf: policyGap())
            if offer != nil {
                misses.append(contentsOf: minimumGap())
            }
            misses.append(contentsOf: locationFitMisses())
            return misses
        }

        /// Coarse identity path: only surface geography/coverage gaps, not offer economics.
        private func templateMissingFactsCounterpartyNode() -> [String] {
            locationFitMisses()
        }

        private func locationFitMisses() -> [String] {
            guard providerCoverageSignalsEmpty else { return [] }

            guard let fact = requesterLocationFact else {
                return [Self.legacyRequesterLocationUnresolvedLine]
            }

            if fact.shouldAskClarification {
                return []
            }

            if !fact.isSatisfiedForCurrentStep {
                return []
            }

            if let providerMiss = ExchangeSecondHalfLocationResolver.opportunityQualificationCoverageMiss(
                locationFact: fact,
                hasOffer: offer != nil,
                hasProfile: profile != nil
            ) {
                return [providerMiss]
            }

            return []
        }

        private var providerCoverageSignalsEmpty: Bool {
            memory.coverageAreas.isEmpty
                && offer?.regionTags.isEmpty ?? true
                && profile?.regionTags.isEmpty ?? true
                && !(offer?.commercialFacts.serviceAreaNote?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        }

        private static let legacyRequesterLocationUnresolvedLine = """
            Location fit boundaries (metro/service radius) vs your requirement are unresolved.
            """

        private func priceGap() -> [String] {
            guard let offer else {
                if anchor == .offerSurface {
                    return ["Exact commercial economics are not anchored to a surfaced offer."]
                }
                return []
            }

            let cf = offer.commercialFacts

            switch offer.fulfillment.pricingMode {
            case .fixed:
                let hasStructuredAmount = memory.pricingRules.contains {
                    $0.amountDescription.rangeOfCharacter(from: .decimalDigits) != nil
                }

                guard !hasStructuredAmount && !cf.hasAnyPublicPriceSignal else {
                    return []
                }

                return [
                    """
                    Listed as fixed-price posture but no deterministic numeric tariff is surfaced in structured memory — \
                        confirm invoiced amount for your scope.
                    """
                ]

            case .quoteRequired, .custom, .undisclosed:
                if cf.hasAnyPublicPriceSignal {
                    return []
                }

                return [
                    "Formal quote/pricing workbook is still required — published surface only conveys pricing posture.",
                    """
                    Negotiation/discount knobs are intentionally blocked at this deterministic layer — escalate for binding numbers.
                    """
                ]
            }
        }

        private func shippingGap() -> [String] {
            guard let offer else { return [] }

            let textualBundle = memory.standardPolicies
                .map { "\($0.title) \($0.details)".lowercased() }
                .joined()

            guard !textualBundle.contains("ship")
                && !textualBundle.contains("deliver") else {
                return []
            }

            if offer.semantic.fulfillmentModes.contains(.shippable) {
                return [] // hinted via semantic mode
            }

            return [
                """
                Freight / shipping channel details (carrier, insurance, thresholds) aren’t enumerated on the public surface —
                    confirm logistic constraints.
                """
            ]
        }

        private func policyGap() -> [String] {
            var textual = memory.standardPolicies
                .map { "\($0.title) \($0.details)".lowercased() }
                .joined()

            if let cf = offer?.commercialFacts {
                let bundles = [
                    cf.cancellationPolicy,
                    cf.refundPolicy,
                    cf.warrantyPolicy
                ]
                .compactMap {
                    $0?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .joined(separator: " ")
                .lowercased()

                textual += bundles
            }

            guard !textual.contains("refund")
                && !textual.contains("cancel")
                && !textual.contains("return")
                && !textual.contains("warranty") else {
                return []
            }

            return [
                """
                Warranty / SLA / escrow / remediation pathways are not enumerated on deterministic layers — confirm contractual riders.
                """
            ]
        }

        private func minimumGap() -> [String] {
            if let raw = offer?.commercialFacts.minimumEngagement?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                return []
            }

            let bundle = memory.standardPolicies
                .map { "\($0.title) \($0.details)".lowercased() }
                .joined()

            guard !bundle.contains("minimum")
                && !bundle.contains("moq") else {
                return []
            }

            return [
                "Minimum order / minimum engagement length is not clearly published for this surface."
            ]
        }
    }

    private func trimOrDash(_ raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return "—"
        }

        return trimmed
    }

    private func dedupePreserve(_ rows: [String], cap: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for row in rows {
            let trimmed = row.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            out.append(trimmed)
            if out.count >= cap {
                break
            }
        }

        return out
    }
}

// MARK: - Offer fulfillment display labels (reuse seller hydrator enums)

private extension ExchangeOffer.Fulfillment.PricingMode {
    var displayLabel: String {
        switch self {
        case .fixed: return "Fixed"
        case .quoteRequired: return "Quote required"
        case .custom: return "Custom"
        case .undisclosed: return "Undisclosed"
        }
    }
}

private extension ExchangeOffer.Fulfillment.CommitmentMode {
    var displayLabel: String {
        switch self {
        case .exploratory: return "Exploratory"
        case .active: return "Active"
        case .approvalRequired: return "Approval required"
        }
    }
}
