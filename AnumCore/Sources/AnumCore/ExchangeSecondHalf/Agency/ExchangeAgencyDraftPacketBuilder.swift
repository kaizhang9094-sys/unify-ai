import Foundation

public enum ExchangeAgencyDraftPacketBuilder {
    /// Unresolved issues that read like outbound buyer asks to the provider (Pass-2 / agency compose).
    public static func providerDirectedQuestionLines(from execution: ExchangeSecondHalfExecutionContext) -> [String]? {
        let rows = execution.unresolvedIssues.compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let lower = line.lowercased()
            if lower.contains("please confirm") || lower.contains("could you confirm") { return line }
            let keys = [
                "price", "rate", "pricing", "availability", "schedule", "location", "lesson",
                "in-person", "in person", "remote", "service area", "provider's", "provider"
            ]
            if keys.contains(where: { lower.contains($0) }) { return line }
            return nil
        }
        return rows.isEmpty ? nil : dedupeLimit(rows, cap: 6)
    }

    /// Prefer Pass-2 resolved provider-bound questions (LLM or named fallback); else intent-gap / decision-needs seeds; else execution context.
    public static func resolvedProviderDirectedQuestionLines(
        executionContext: ExchangeSecondHalfExecutionContext,
        pass2DirectedOverride: [String]?,
        pass2LLMCompareSucceeded: Bool = false,
        agencyContext: ExchangeAgencyContext? = nil,
        decisionNeeds: ExchangeRequesterDecisionNeeds? = nil
    ) -> [String]? {
        if pass2LLMCompareSucceeded {
            return dedupeLimit(pass2DirectedOverride ?? [], cap: ExchangeRequesterMatchCompareOutputGuard.maxProviderQuestions)
        }
        if let pass2DirectedOverride, !pass2DirectedOverride.isEmpty {
            return dedupeLimit(pass2DirectedOverride, cap: 6)
        }
        if let agencyContext, let decisionNeeds {
            let seeded = providerDirectedSeedFromIntentGaps(
                context: agencyContext,
                decisionNeeds: decisionNeeds
            )
            if !seeded.isEmpty {
                return dedupeLimit(seeded, cap: 6)
            }
        }
        return providerDirectedQuestionLines(from: executionContext)
    }

    public static func buildRequesterClarificationPacket(
        context: ExchangeAgencyContext,
        decisionNeeds: ExchangeRequesterDecisionNeeds,
        executionContext: ExchangeSecondHalfExecutionContext,
        styleProfile: ExchangeSecretaryStyleProfile,
        maxLength: Int,
        topRankedCandidateSummaries: [String] = [],
        providerDirectedQuestionLinesResolved: [String]? = nil,
        pass2LLMCompareSucceeded: Bool = false
    ) -> RequesterClarificationDraftPacket {
        // Packet builders consume pass-2 canonical context only and must not resolve store records.
        let known = dedupeLimit(decisionNeeds.knownDecisionFacts + context.knownFacts, cap: 64)

        return RequesterClarificationDraftPacket(
            threadID: context.threadID,
            selectedOfferID: context.selectedOfferID,
            selectedPublicProfileID: context.selectedPublicProfileID,
            selectedCounterpartyID: context.selectedCounterpartyID,
            originalUserRequest: nonEmpty(context.userIntent) ?? "Clarify requester needs.",
            selectedProfileSummary: profileSummary(from: context.publicProfile),
            selectedOfferSummary: offerSummary(from: context.offer),
            knownFacts: known,
            missingFacts: dedupeLimit(decisionNeeds.missingDecisionFacts, cap: 32),
            recommendedQuestions: dedupeLimit(decisionNeeds.recommendedQuestions, cap: 8),
            alreadyAsked: dedupeLimit(executionContext.priorQuestionsAsked, cap: 16),
            alreadyAnswered: dedupeLimit(executionContext.priorAnswersReceived, cap: 16),
            styleProfile: styleProfile,
            forbiddenClaims: [
                "no booking confirmation",
                "no final quote",
                "no guarantee",
                "no payment/deposit",
                "no agreement",
                "no private details"
            ],
            forbiddenActions: [
                "commit",
                "book",
                "pay",
                "approve",
                "final quote",
                "guarantee",
                "discount",
                "contract",
                "private disclosure"
            ],
            maxLength: max(120, maxLength),
            requiredIntent: .requesterClarificationOnly,
            autonomousComposeMode: nil,
            topRankedCandidateSummaries: Array(topRankedCandidateSummaries.prefix(3)),
            providerDirectedQuestionLines: resolvedProviderDirectedQuestionLines(
                executionContext: executionContext,
                pass2DirectedOverride: providerDirectedQuestionLinesResolved,
                pass2LLMCompareSucceeded: pass2LLMCompareSucceeded,
                agencyContext: context,
                decisionNeeds: decisionNeeds
            )
        )
    }

    /// Pass-2 packet for requester autonomous outbound (LLM-authored body path).
    public static func buildRequesterAutonomousOutboundPacket(
        context: ExchangeAgencyContext,
        decisionNeeds: ExchangeRequesterDecisionNeeds,
        executionContext: ExchangeSecondHalfExecutionContext,
        styleProfile: ExchangeSecretaryStyleProfile,
        composeMode: RequesterAutonomousOutboundComposeMode,
        maxLength: Int,
        topRankedCandidateSummaries: [String] = [],
        providerDirectedQuestionLinesResolved: [String]? = nil,
        pass2LLMCompareSucceeded: Bool = false,
        counterpartyDisplayNameHint: String? = nil,
        facets: ExchangeIntentFacets? = nil,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent? = nil,
        enrichmentPolicyInput: RequesterOutboundEnrichmentPolicy.Input? = nil
    ) -> RequesterClarificationDraftPacket {
        let known = dedupeLimit(decisionNeeds.knownDecisionFacts + context.knownFacts, cap: 64)
        let grounded = RequesterInquiryOpportunityLabel.resolve(
            offer: context.offer,
            publicProfile: context.publicProfile,
            counterpartyDisplayName: counterpartyDisplayNameHint
        )

        let supplemental = RequesterInquiryQuestionNormalizer.autonomousComposeSupplementalRows(
            pass2LLMCompareSucceeded: pass2LLMCompareSucceeded,
            missingFactsLines: dedupeLimit(decisionNeeds.missingDecisionFacts, cap: 48),
            recommendedQuestionLines: dedupeLimit(decisionNeeds.recommendedQuestions, cap: 8)
        )
        let missingClean = supplemental.missingFacts
        let recClean = supplemental.recommendedQuestions

        let directedRaw = resolvedProviderDirectedQuestionLines(
            executionContext: executionContext,
            pass2DirectedOverride: providerDirectedQuestionLinesResolved,
            pass2LLMCompareSucceeded: pass2LLMCompareSucceeded,
            agencyContext: pass2LLMCompareSucceeded ? nil : context,
            decisionNeeds: pass2LLMCompareSucceeded ? nil : decisionNeeds
        ) ?? []

        let directedNormalized = RequesterInquiryQuestionNormalizer.normalizedProviderDirectedQuestions(
            originalRequesterText: nonEmpty(context.userIntent) ?? "",
            missingFactsLines: missingClean,
            offerCategory: context.offer?.category,
            providerDirectedQuestions: directedRaw
        )

        let userIntentLine = nonEmpty(context.userIntent) ?? ""
        let locationFact = ExchangeSecondHalfLocationResolver.resolve(facets: facets)
        let requirementsSummary = ExchangeRequesterCompareGroundingSummary.render(
            originalRequesterMessage: userIntentLine,
            searchIntent: searchIntent ?? facets?.searchIntent,
            thread: nil,
            facets: facets
        )
        #if DEBUG
        Swift.print(
            "[AgencyDraft] locationRedaction source=\(locationFact.source.rawValue) " +
                "phrasePresent=\(locationFact.modelSafeLocationPhrase != nil) rawSpatialIncluded=false"
        )
        #endif
        let resolvedEnrichmentInput = enrichmentPolicyInput
            ?? RequesterOutboundEnrichmentPolicy.Input(
                pass2LLMCompareSucceeded: pass2LLMCompareSucceeded,
                providerDirectedQuestionLines: directedNormalized,
                routingSurface: parseRoutingSurface(from: requirementsSummary),
                queryIntentClass: facets?.queryIntentClass,
                surfacePreference: facets?.surfacePreference,
                domainCategory: searchIntent?.domainCategory
                    ?? facets?.searchIntent?.domainCategory
                    ?? inferDomainCategory(from: context.offer),
                requesterRequirementsSummary: requirementsSummary,
                originalUserRequest: userIntentLine
            )
        let enrichmentOutcome = RequesterOutboundEnrichmentPolicy.resolve(resolvedEnrichmentInput)
        let outboundComposeContract = RequesterOutboundComposeContract(
            routingSurface: resolvedEnrichmentInput.routingSurface,
            requiredProviderQuestionLines: directedNormalized,
            allowedEnrichmentDimensions: enrichmentOutcome.allowedEnrichmentDimensions,
            allowedEnrichmentHints: enrichmentOutcome.allowedEnrichmentHints,
            maxOptionalEnrichmentCount: enrichmentOutcome.allowedEnrichmentDimensions.isEmpty ? 0 : 1
        )

        let requiredIntent: ExchangeAgencyDraftRequiredIntent = {
            switch composeMode {
            case .askClarification:
                return .requesterClarificationOnly
            case .recommendNextMove:
                return .requesterRecommendNextMoveHuman
            case .frameDecision:
                return .requesterFrameDecisionHuman
            }
        }()

        return RequesterClarificationDraftPacket(
            threadID: context.threadID,
            selectedOfferID: context.selectedOfferID,
            selectedPublicProfileID: context.selectedPublicProfileID,
            selectedCounterpartyID: context.selectedCounterpartyID,
            originalUserRequest: nonEmpty(context.userIntent) ?? "Clarify requester needs.",
            selectedProfileSummary: profileSummary(from: context.publicProfile),
            selectedOfferSummary: offerSummary(from: context.offer),
            knownFacts: known,
            missingFacts: dedupeLimit(missingClean, cap: 32),
            recommendedQuestions: recClean,
            alreadyAsked: dedupeLimit(executionContext.priorQuestionsAsked, cap: 16),
            alreadyAnswered: dedupeLimit(executionContext.priorAnswersReceived, cap: 16),
            styleProfile: styleProfile,
            forbiddenClaims: [
                "no booking confirmation",
                "no final quote",
                "no guarantee",
                "no payment/deposit",
                "no agreement",
                "no private details"
            ],
            forbiddenActions: [
                "commit",
                "book",
                "pay",
                "approve",
                "final quote",
                "guarantee",
                "discount",
                "contract",
                "private disclosure"
            ],
            maxLength: max(120, maxLength),
            requiredIntent: requiredIntent,
            autonomousComposeMode: composeMode,
            topRankedCandidateSummaries: Array(topRankedCandidateSummaries.prefix(3)),
            providerDirectedQuestionLines: directedNormalized.isEmpty ? nil : dedupeLimit(directedNormalized, cap: 6),
            groundedOpportunityLabelForPrompt: grounded.label,
            pass2LLMCompareSucceeded: pass2LLMCompareSucceeded,
            outboundComposeContract: outboundComposeContract
        )
    }

    public static func buildProviderResponsePacket(
        context: ExchangeAgencyContext,
        providerAnswerability: ExchangeProviderAnswerability,
        executionContext: ExchangeSecondHalfExecutionContext,
        styleProfile: ExchangeSecretaryStyleProfile,
        maxLength: Int
    ) -> ProviderResponseDraftPacket {
        let inboundInquiry = firstNonEmpty(
            executionContext.inquiry?.requesterAsk,
            executionContext.inquiry?.inquirySummary,
            executionContext.structuredQuery?.rawText,
            context.userIntent,
            "Inbound coordination request."
        )

        let mode = providerResponseMode(from: providerAnswerability)
        let requiredIntent: ExchangeAgencyDraftRequiredIntent = {
            switch mode {
            case .groundedAnswer:
                return .providerGroundedAnswerOnly
            case .partialAnswer, .askProviderInput, .decline:
                return .providerPartialAnswerOrEscalation
            }
        }()

        return ProviderResponseDraftPacket(
            threadID: context.threadID,
            selectedOfferID: context.selectedOfferID,
            selectedPublicProfileID: context.selectedPublicProfileID,
            selectedCounterpartyID: context.selectedCounterpartyID,
            inboundInquiry: inboundInquiry,
            requesterDisplayContext: nonEmpty(executionContext.counterpartyName),
            providerPublicProfileSummary: profileSummary(from: context.publicProfile),
            selectedOfferSummary: offerSummary(from: context.offer),
            approvedGroundedFacts: providerAnswerability.groundedFacts,
            contextOnlyFacts: dedupeLimit(context.knownFacts + executionContext.priorAnswersReceived, cap: 24),
            missingFacts: dedupeLimit(providerAnswerability.missingFacts, cap: 16),
            answerabilityStatus: providerAnswerability.answerability,
            escalationReason: nonEmpty(providerAnswerability.boundaryReason),
            styleProfile: styleProfile,
            responseMode: mode,
            forbiddenClaims: [
                "no custom price unless present in approvedGroundedFacts",
                "no availability unless present in approvedGroundedFacts",
                "no guarantee unless present in approvedGroundedFacts",
                "no discount unless present in approvedGroundedFacts",
                "no booking confirmation unless explicitly approved",
                "no policy exception unless explicitly approved"
            ],
            forbiddenActions: [
                "custom price",
                "final quote",
                "guarantee",
                "discount approval",
                "booking confirmation",
                "appointment confirmation",
                "payment/deposit",
                "contract",
                "refund exception",
                "policy exception",
                "private disclosure"
            ],
            maxLength: max(120, maxLength),
            requiredIntent: requiredIntent
        )
    }
}

private extension ExchangeAgencyDraftPacketBuilder {
    /// Deterministic provider-bound questions when LLM compare did not supply lines.
    static func providerDirectedSeedFromIntentGaps(
        context: ExchangeAgencyContext,
        decisionNeeds: ExchangeRequesterDecisionNeeds
    ) -> [String] {
        var rows: [String] = []

        if let combined = context.intentGapCombinedClarificationQuestion?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !combined.isEmpty {
            rows.append(combined)
        }

        let sortedGaps = context.intentGaps.sorted { $0.priority < $1.priority }
        for gap in sortedGaps {
            guard let q = gap.questionForProvider?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !q.isEmpty else { continue }
            if rows.contains(where: { $0.caseInsensitiveCompare(q) == .orderedSame }) { continue }
            rows.append(q)
            if rows.count >= 6 { break }
        }

        if rows.isEmpty {
            rows = decisionNeeds.recommendedQuestions
        }

        return RequesterInquiryQuestionNormalizer.filteredUserFacingFactsAndGaps(rows)
    }

    static func profileSummary(from profile: ExchangePublicNodeProfile?) -> String? {
        guard let profile else { return nil }
        var parts: [String] = []
        if let name = nonEmpty(profile.displayName) { parts.append(name) }
        if let headline = nonEmpty(profile.headline) { parts.append(headline) }
        parts.append("availability: \(profile.availability.rawValue)")
        return nonEmpty(parts.joined(separator: " · "))
    }

    static func offerSummary(from offer: ExchangeOffer?) -> String? {
        guard let offer else { return nil }
        var parts: [String] = []
        if let title = nonEmpty(offer.title) { parts.append(title) }
        if let summary = nonEmpty(offer.summary) { parts.append(summary) }
        parts.append("pricing: \(offer.fulfillment.pricingMode.rawValue)")
        if let area = nonEmpty(offer.commercialFacts.serviceAreaNote) {
            parts.append("service area: \(area)")
        }
        return nonEmpty(parts.joined(separator: " · "))
    }

    static func dedupeLimit(_ values: [String], cap: Int) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            guard let line = nonEmpty(value) else { continue }
            let key = line.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(line)
            if output.count >= cap { break }
        }
        return output
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func inferDomainCategory(from offer: ExchangeOffer?) -> ExchangeIntentFacets.DomainCategory? {
        let hay = [
            offer?.category,
            offer?.title,
            offer?.summary
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        guard !hay.isEmpty else { return nil }
        if hay.contains("plumb") || hay.contains("contractor") || hay.contains("electric")
            || hay.contains("hvac") || hay.contains("roof") {
            return .homeService
        }
        if hay.contains("tutor") || hay.contains("photo") || hay.contains("consult") {
            return .professionalService
        }
        if hay.contains("product") || hay.contains("shipping") || hay.contains("inventory") {
            return .product
        }
        return nil
    }

    static func parseRoutingSurface(from requirementsSummary: String?) -> String? {
        guard let requirementsSummary else { return nil }
        for line in requirementsSummary.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            guard lower.hasPrefix("routingsurface:") else { continue }
            let value = trimmed.split(separator: ":", maxSplits: 1).dropFirst().joined(separator: ":")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            if let value = nonEmpty(value) {
                return value
            }
        }
        return ""
    }

    static func providerResponseMode(
        from answerability: ExchangeProviderAnswerability
    ) -> ProviderResponseMode {
        if answerability.answerability == .answerableFromPublicFacts,
           !answerability.requiresHumanApproval,
           !answerability.groundedFacts.isEmpty {
            return .groundedAnswer
        }

        switch answerability.answerability {
        case .partiallyAnswerableNeedsClarification:
            return .partialAnswer
        case .requiresProviderApproval:
            return .askProviderInput
        case .notAnswerable:
            return .decline
        case .answerableFromPublicFacts:
            return answerability.requiresHumanApproval ? .askProviderInput : .partialAnswer
        }
    }
}
