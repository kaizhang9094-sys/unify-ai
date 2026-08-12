import Foundation

#if DEBUG
@inline(__always)
private func exchProviderAnswerabilityLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeProviderAnswerability] \(message())")
}
#else
@inline(__always)
private func exchProviderAnswerabilityLog(_ message: @autoclosure () -> String) {}
#endif

// MARK: - Output

public struct ExchangeProviderAnswerability: Codable, Sendable, Hashable {

    public enum Answerability: String, Codable, Sendable, Hashable {
        case answerableFromPublicFacts
        case partiallyAnswerableNeedsClarification
        case requiresProviderApproval
        case notAnswerable
    }

    public var answerability: Answerability
    public var knownFactsUsed: [String]
    public var groundedFacts: [ExchangeProviderGroundedFact]
    public var missingFacts: [String]
    public var proposedAnswer: String?

    public var requiresHumanApproval: Bool
    public var allowsAutonomousDrafting: Bool
    public var allowsAutonomousSending: Bool

    public var boundaryReason: String

    /// True when `providerInquiryCompare.draftReply` (post-governor) is the authoritative grounded outbound wording for compare-first `sendWithinConsent`.
    public var usesCompareFirstGroundedFinalBody: Bool

    public init(
        answerability: Answerability,
        knownFactsUsed: [String],
        groundedFacts: [ExchangeProviderGroundedFact] = [],
        missingFacts: [String],
        proposedAnswer: String?,
        requiresHumanApproval: Bool,
        allowsAutonomousDrafting: Bool,
        allowsAutonomousSending: Bool,
        boundaryReason: String,
        usesCompareFirstGroundedFinalBody: Bool = false
    ) {
        self.answerability = answerability
        self.knownFactsUsed = knownFactsUsed
        self.groundedFacts = groundedFacts
        self.missingFacts = missingFacts
        self.proposedAnswer = proposedAnswer
        self.requiresHumanApproval = requiresHumanApproval
        self.allowsAutonomousDrafting = allowsAutonomousDrafting
        self.allowsAutonomousSending = allowsAutonomousSending
        self.boundaryReason = boundaryReason
        self.usesCompareFirstGroundedFinalBody = usesCompareFirstGroundedFinalBody
    }

    enum CodingKeys: String, CodingKey {
        case answerability
        case knownFactsUsed
        case groundedFacts
        case missingFacts
        case proposedAnswer
        case requiresHumanApproval
        case allowsAutonomousDrafting
        case allowsAutonomousSending
        case boundaryReason
        case usesCompareFirstGroundedFinalBody
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        answerability =
            try container.decodeIfPresent(Answerability.self, forKey: .answerability) ?? .notAnswerable
        knownFactsUsed = try container.decodeIfPresent([String].self, forKey: .knownFactsUsed) ?? []
        groundedFacts =
            try container.decodeIfPresent([ExchangeProviderGroundedFact].self, forKey: .groundedFacts) ?? []
        missingFacts = try container.decodeIfPresent([String].self, forKey: .missingFacts) ?? []
        proposedAnswer = try container.decodeIfPresent(String.self, forKey: .proposedAnswer)
        requiresHumanApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresHumanApproval) ?? false
        allowsAutonomousDrafting =
            try container.decodeIfPresent(Bool.self, forKey: .allowsAutonomousDrafting) ?? false
        allowsAutonomousSending =
            try container.decodeIfPresent(Bool.self, forKey: .allowsAutonomousSending) ?? false
        boundaryReason = try container.decodeIfPresent(String.self, forKey: .boundaryReason) ?? ""
        usesCompareFirstGroundedFinalBody =
            try container.decodeIfPresent(Bool.self, forKey: .usesCompareFirstGroundedFinalBody) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(answerability, forKey: .answerability)
        try container.encode(knownFactsUsed, forKey: .knownFactsUsed)
        try container.encode(groundedFacts, forKey: .groundedFacts)
        try container.encode(missingFacts, forKey: .missingFacts)
        try container.encodeIfPresent(proposedAnswer, forKey: .proposedAnswer)
        try container.encode(requiresHumanApproval, forKey: .requiresHumanApproval)
        try container.encode(allowsAutonomousDrafting, forKey: .allowsAutonomousDrafting)
        try container.encode(allowsAutonomousSending, forKey: .allowsAutonomousSending)
        try container.encode(boundaryReason, forKey: .boundaryReason)
        try container.encode(usesCompareFirstGroundedFinalBody, forKey: .usesCompareFirstGroundedFinalBody)
    }
}

// MARK: - Engine

public struct ExchangeProviderAnswerabilityEngine: Sendable {

    private let structured: ExchangeStructuredAnswerEngine

    public init(structuredEngine: ExchangeStructuredAnswerEngine = .init()) {
        self.structured = structuredEngine
    }

    public func evaluate(
        context: ExchangeAgencyContext,
        inquiryText: String,
        prefersDeterministicComposer: Bool = true
    ) -> ExchangeProviderAnswerability {
        _ = prefersDeterministicComposer

        guard context.side == .provider else {
            return makeAnswerability(
                answerability: .notAnswerable,
                knownFactsUsed: [],
                groundedFacts: [],
                missingFacts: [],
                proposedAnswer: nil,
                requiresHumanApproval: false,
                allowsAutonomousDrafting: false,
                boundaryReason: "This evaluation needs a provider-side thread to interpret the inquiry."
            )
        }

        let inquiry = sanitizedInquiry(core: inquiryText, context: context)
        let permissionPolicy = context.offer?.commercialFacts.permissionOnlyAutoAnswerPolicy()
        let policyResolved = context.offer?.commercialFacts.resolvedAutoAnswerPolicy()
        let query = inferredQuery(for: inquiry)
        let diagnostics = Diagnostics(
            context: context,
            inquiry: inquiry,
            query: query,
            permissionPolicy: permissionPolicy,
            legacyResolvedPolicy: policyResolved
        )

        if context.offer == nil {
            diagnostics.log(
                reason: .anchorMissing,
                structuredAnswerExists: false,
                result: .notAnswerable
            )
        }

        if context.offer != nil,
           let permissionPolicy,
           permissionPolicy.requiresApprovalForCustomQuote,
           customQuoteLikelyRequested(inquiry) {
            let summary = sanitizedPublicFactsSummary(context)
            let grounded = providerGroundedFacts(context: context)
            let result = makeAnswerability(
                answerability: .requiresProviderApproval,
                knownFactsUsed: summary.isEmpty ? grounded.map(\.text) : summary,
                groundedFacts: grounded,
                missingFacts: missingCommitmentFacts(),
                proposedAnswer: """
                Thanks for your interest. Custom quotes need a quick seller review before we can share firm numbers from here.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                requiresHumanApproval: true,
                allowsAutonomousDrafting: false,
                boundaryReason:
                    "Custom quotes need seller review under this offer’s automation settings."
            )
            diagnostics.log(
                reason: .customQuoteGate,
                structuredAnswerExists: false,
                result: result.answerability
            )
            return result
        }

        if let offer = context.offer,
           let matched = matchedFAQ(
               offer: offer,
               inquiry: inquiry,
               policy: permissionPolicy
           ) {
            let known: [String] = [
                "Matched a published FAQ on the offer."
            ]

            let grounded = [
                ExchangeProviderGroundedFact(
                    text: "Matched a published FAQ on the offer.",
                    source: .offer,
                    field: "offer.faqs"
                )
            ]
            let result = makeAnswerability(
                answerability: .answerableFromPublicFacts,
                knownFactsUsed: known,
                groundedFacts: grounded,
                missingFacts: [],
                proposedAnswer: matched.answer,
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                boundaryReason: "Answer taken from a published FAQ on the offer."
            )
            diagnostics.log(
                reason: .none,
                structuredAnswerExists: true,
                result: result.answerability
            )
            return result
        }

        if requiresSellerEscalation(inquiryLowercased: inquiry.lowercased()) {
            let summary = sanitizedPublicFactsSummary(context)

            let grounded = providerGroundedFacts(context: context)
            let result = makeAnswerability(
                answerability: .requiresProviderApproval,
                knownFactsUsed: summary.isEmpty ? grounded.map(\.text) : summary,
                groundedFacts: grounded,
                missingFacts: missingCommitmentFacts(),
                proposedAnswer: summary.isEmpty
                    ? """
                    Thanks for reaching out. This touches commitments or terms we can’t finalize from published details alone—please loop in seller review before we send a binding reply.
                    """
                    : assembleSafePublicSummary(summary),
                requiresHumanApproval: true,
                allowsAutonomousDrafting: false,
                boundaryReason: "Commitments, privacy, pricing, guarantees, or legal terms need seller review before sending."
            )
            diagnostics.log(
                reason: .riskBoundary,
                structuredAnswerExists: false,
                result: result.answerability
            )
            return result
        }

        if let denial = denialForStructuredAutoPolicy(
            context: context,
            inquiry: inquiry,
            query: query,
            policy: permissionPolicy
        ) {
            diagnostics.log(
                reason: .permissionOff,
                structuredAnswerExists: false,
                result: denial.answerability
            )
            return denial
        }

        if let structuredAnswer = structured.answer(
            query: query,
            memory: context.operatingMemory
        ) {
            let grounded = structuredAnswer.sourcedFacts.map {
                ExchangeProviderGroundedFact(
                    text: $0,
                    source: .operatingMemory,
                    field: "operatingMemory"
                )
            }
            let result = makeAnswerability(
                answerability: .answerableFromPublicFacts,
                knownFactsUsed: structuredAnswer.sourcedFacts,
                groundedFacts: grounded,
                missingFacts: [],
                proposedAnswer: structuredAnswer.text,
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                boundaryReason: "Answer assembled from published offer and profile details."
            )
            diagnostics.log(
                reason: .none,
                structuredAnswerExists: true,
                result: result.answerability
            )
            return result
        }

        if let evidenceGap = insufficientEvidenceAnswerability(
            context: context,
            inquiry: inquiry,
            query: query,
            policy: permissionPolicy
        ) {
            diagnostics.log(
                reason: .structuredNoMatch,
                structuredAnswerExists: false,
                result: evidenceGap.answerability
            )
            return evidenceGap
        }

        if let partial = contextualPartialAnswer(context: context, inquiry: inquiry) {
            let result = makeAnswerability(
                answerability: .partiallyAnswerableNeedsClarification,
                knownFactsUsed: partial.known,
                groundedFacts: partial.grounded,
                missingFacts: partial.holes,
                proposedAnswer: partial.text,
                requiresHumanApproval: false,
                allowsAutonomousDrafting: partial.text != nil,
                boundaryReason: "Only part of this could be answered from published details; a short clarification may help."
            )
            diagnostics.log(
                reason: .evidenceInsufficient,
                structuredAnswerExists: false,
                result: result.answerability
            )
            return result
        }

        let result = makeAnswerability(
            answerability: .notAnswerable,
            knownFactsUsed: [],
            groundedFacts: [],
            missingFacts: [
                """
                Not enough published detail to answer this confidently—seller input or a clarifying question may be needed.
                """
            ],
            proposedAnswer: nil,
            requiresHumanApproval: false,
            allowsAutonomousDrafting: false,
            boundaryReason: "Not enough overlap with published offer and profile information."
        )
        diagnostics.log(
            reason: .evidenceInsufficient,
            structuredAnswerExists: false,
            result: result.answerability
        )
        return result
    }

    private func matchedFAQ(
        offer: ExchangeOffer,
        inquiry: String,
        policy: ExchangeOffer.AutoAnswerPolicy?
    ) -> ExchangeOffer.FAQ? {
        guard policy?.canAnswerFAQs == true else {
            return nil
        }

        let lower = inquiry.lowercased()
        for faq in offer.commercialFacts.faqs {
            let condensed = faq.question
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard condensed.count >= 3 else {
                continue
            }

            if lower.contains(condensed) {
                return faq
            }

            let qWords = condensed.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter {
                $0.count > 2
            }
            guard !qWords.isEmpty else { continue }

            let hits = qWords.filter { lower.contains($0) }
            if hits.count >= max(1, (qWords.count + 1) / 2) {
                return faq
            }
        }

        return nil
    }

    private func customQuoteLikelyRequested(_ text: String) -> Bool {
        let lowered = text.lowercased()

        let needles = [
            "custom quote",
            "custom pricing",
            "bespoke quote",
            "quote for my",
            "tailored quote",
            "one-off quote"
        ]

        return needles.contains { lowered.contains($0) }
    }

    private func policyAllowsStructuredAnswer(
        query: ExchangeStructuredAnswerEngine.Query,
        policy: ExchangeOffer.AutoAnswerPolicy?
    ) -> Bool {
        guard let policy else { return true }

        switch query.kind {
        case .pricing:
            return policy.canAnswerPricing
        case .availability:
            return policy.canAnswerAvailability
        case .serviceArea,
             .locations:
            return policy.canAnswerServiceArea
        case .standardPolicy:
            return policy.canAnswerPolicies
        case .itemsServices,
             .requesterConstraint,
             .general:
            return true
        }
    }

    private func providerLedgerLines(context: ExchangeAgencyContext) -> [String] {
        var lines: [String] = []

        if let offer = context.offer {
            lines.append(contentsOf: ExchangeSellerSurfaceOperatingMemoryHydrator.offerFulfillmentFactLines(for: offer))
            lines.append(contentsOf: Array(offer.commercialSurfaceSkimLines.prefix(6)))
        }

        lines.append(contentsOf: ExchangeSellerSurfaceOperatingMemoryHydrator
            .hydrate(publicProfile: context.publicProfile, offer: context.offer)
            .compactCanonStrings(limit: 4))

        return Array(lines.prefix(12))
    }

    private func denialForStructuredAutoPolicy(
        context: ExchangeAgencyContext,
        inquiry _: String,
        query: ExchangeStructuredAnswerEngine.Query,
        policy: ExchangeOffer.AutoAnswerPolicy?
    ) -> ExchangeProviderAnswerability? {
        guard let policy else {
            return nil
        }

        guard !policyAllowsStructuredAnswer(query: query, policy: policy) else {
            return nil
        }

        let known = providerLedgerLines(context: context)

        switch query.kind {
        case .pricing:
            return makeAnswerability(
                answerability: .requiresProviderApproval,
                knownFactsUsed: known,
                groundedFacts: providerGroundedFacts(context: context),
                missingFacts: [
                    "Published offer details do not allow automated pricing answers beyond what is already shown."
                ],
                proposedAnswer: """
                Thanks for asking about pricing. I’m not able to extend or invent pricing beyond what’s published on this offer—happy to follow up after seller review if you need a binding quote.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                requiresHumanApproval: true,
                allowsAutonomousDrafting: false,
                boundaryReason: "This seller’s settings do not allow automated pricing replies."
            )

        case .availability:
            return makeAnswerability(
                answerability: .requiresProviderApproval,
                knownFactsUsed: known,
                groundedFacts: providerGroundedFacts(context: context),
                missingFacts: [
                    "Published details do not support an automated availability answer beyond what is already shown."
                ],
                proposedAnswer: """
                Thanks for asking about timing. I can only reflect what’s published here—please confirm scheduling after seller review so we don’t imply unlisted slots or guarantees.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                requiresHumanApproval: true,
                allowsAutonomousDrafting: false,
                boundaryReason: "This seller’s settings do not allow automated availability replies."
            )

        case .serviceArea,
             .locations:
            return makeAnswerability(
                answerability: .requiresProviderApproval,
                knownFactsUsed: known,
                groundedFacts: providerGroundedFacts(context: context),
                missingFacts: [
                    "Published details do not support an automated answer about service area or coverage beyond what is shown."
                ],
                proposedAnswer: """
                Thanks for asking about coverage. I can only repeat what’s published for this offer—please confirm service area after seller review if you need a precise boundary.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                requiresHumanApproval: true,
                allowsAutonomousDrafting: false,
                boundaryReason: "This seller’s settings do not allow automated service-area replies."
            )

        case .standardPolicy:
            return makeAnswerability(
                answerability: .requiresProviderApproval,
                knownFactsUsed: known,
                groundedFacts: providerGroundedFacts(context: context),
                missingFacts: [
                    "Published details do not support an automated answer about cancellations, refunds, or warranties beyond what is shown."
                ],
                proposedAnswer: """
                Thanks for asking about policies. I can only summarize what’s published here—please confirm specifics after seller review so we don’t promise protections beyond the public text.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                requiresHumanApproval: true,
                allowsAutonomousDrafting: false,
                boundaryReason: "This seller’s settings do not allow automated policy replies."
            )

        case .itemsServices,
             .requesterConstraint,
             .general:
            return nil
        }
    }

    private func insufficientEvidenceAnswerability(
        context: ExchangeAgencyContext,
        inquiry: String,
        query: ExchangeStructuredAnswerEngine.Query,
        policy: ExchangeOffer.AutoAnswerPolicy?
    ) -> ExchangeProviderAnswerability? {
        guard policyAllowsStructuredAnswer(query: query, policy: policy) else {
            return nil
        }

        let known = providerLedgerLines(context: context)
        let grounded = providerGroundedFacts(context: context)

        switch query.kind {
        case .pricing:
            return makeAnswerability(
                answerability: .partiallyAnswerableNeedsClarification,
                knownFactsUsed: known,
                groundedFacts: grounded,
                missingFacts: ["No confirmed public price fact matched this inquiry yet."],
                proposedAnswer: """
                I don’t have a confirmed listed price I can quote from published details yet. \
                I can ask the seller to confirm the current price for you.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                boundaryReason: "Pricing is permitted, but available public evidence is insufficient for a direct price answer."
            )

        case .availability:
            return makeAnswerability(
                answerability: .partiallyAnswerableNeedsClarification,
                knownFactsUsed: known,
                groundedFacts: grounded,
                missingFacts: ["No confirmed availability window matched this inquiry yet."],
                proposedAnswer: """
                I can’t confirm exact availability from published details yet. \
                I can check with the seller and follow up right away.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                boundaryReason: "Availability is permitted, but available public evidence is insufficient for a direct schedule commitment."
            )

        case .serviceArea,
             .locations:
            return makeAnswerability(
                answerability: .partiallyAnswerableNeedsClarification,
                knownFactsUsed: known,
                groundedFacts: grounded,
                missingFacts: ["No precise published service-area fact matched this inquiry."],
                proposedAnswer: """
                I don’t have a precise coverage confirmation for that location from published details. \
                I can check with the seller and confirm.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                boundaryReason: "Service-area replies are permitted, but evidence is not specific enough for a direct commitment."
            )

        case .standardPolicy:
            return makeAnswerability(
                answerability: .partiallyAnswerableNeedsClarification,
                knownFactsUsed: known,
                groundedFacts: grounded,
                missingFacts: ["No published policy line matched this inquiry."],
                proposedAnswer: """
                I don’t see a confirmed policy line for that exact question in published details yet. \
                I can ask the seller to confirm.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                boundaryReason: "Policy replies are permitted, but evidence is insufficient for a direct factual answer."
            )

        case .itemsServices,
             .requesterConstraint,
             .general:
            guard inquiry.lowercased().contains("price")
                    || inquiry.lowercased().contains("cost")
                    || inquiry.lowercased().contains("avail")
                    || inquiry.lowercased().contains("policy")
                    || inquiry.lowercased().contains("where")
            else {
                return nil
            }

            return makeAnswerability(
                answerability: .partiallyAnswerableNeedsClarification,
                knownFactsUsed: known,
                groundedFacts: grounded,
                missingFacts: ["Published evidence did not map cleanly to this question."],
                proposedAnswer: """
                I can’t confirm that from published details alone yet. \
                I can ask the seller and get back to you.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                boundaryReason: "Question is allowed in principle, but evidence was insufficient for a deterministic direct answer."
            )
        }
    }

    private func sanitizedInquiry(core: String, context: ExchangeAgencyContext) -> String {
        let cleaned = core.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return contextualFallbackPrompt(context).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    private func contextualFallbackPrompt(_ context: ExchangeAgencyContext) -> String {
        if let inbound = context.situation?.latestInboundLine, !inbound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inbound
        }

        if let pending = context.situation?.pendingDraftPreview, !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pending
        }

        return context.userIntent
    }

    private func requiresSellerEscalation(inquiryLowercased lowered: String) -> Bool {
        let triggers = [
            "contract",
            "agreement signature",
            "purchase order issued",
            "deposit",
            "legal counsel",
            "court",
            "ssn ",
            "social security",
            "passport",
            "credit card",
            "stripe",
            "guarantee me",
            "final quote",
            "final price after discount",
            "private dossier",
            "confidential",
            "bind now",
            "penalty clause",
            "nda"
        ]

        return triggers.contains { raw in
            let trigger = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty else { return false }
            if trigger.contains(where: { $0.isWhitespace }) {
                return lowered.contains(trigger)
            }
            return inquiryContainsWholeWordToken(haystack: lowered, token: trigger)
        }
    }

    /// Single-token triggers must match as standalone words (e.g. `nda` ≠ substring of `standard`).
    /// Multi-word phrases keep substring semantics via `contains`.
    private func inquiryContainsWholeWordToken(haystack: String, token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: token)
        let pattern = "(?<![a-z0-9])\(escaped)(?![a-z0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        let range = NSRange(haystack.startIndex..., in: haystack)
        return regex.firstMatch(in: haystack, options: [], range: range) != nil
    }

    private func inferredQuery(for text: String) -> ExchangeStructuredAnswerEngine.Query {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        func kindForHeuristic() -> ExchangeStructuredAnswerEngine.QueryKind {
            if mentionsAny(lower, needles: ["price", "cost", "quote", "$", "usd", "rate card"]) {
                return .pricing
            }

            if mentionsAny(lower, needles: ["avail", "slot", "when can", "timing", "schedule"]) {
                return .availability
            }

            if mentionsAny(lower, needles: ["where", "location", "ship", "deliver", "region", "area"]) {
                return .serviceArea
            }

            if mentionsAny(lower, needles: ["policy", "cancel", "refund", "return", "fine print"]) {
                return .standardPolicy
            }

            if mentionsAny(lower, needles: ["minimum", "commitment months", "retainer"]) {
                return .standardPolicy
            }

            return .general
        }

        return ExchangeStructuredAnswerEngine.Query(
            rawText: trimmed.isEmpty ? "assist" : trimmed,
            kind: kindForHeuristic()
        )
    }

    private func mentionsAny(_ lower: String, needles: [String]) -> Bool {
        needles.contains { lower.contains($0) }
    }

    private func contextualPartialAnswer(
        context: ExchangeAgencyContext,
        inquiry: String
    ) -> (
        text: String?,
        known: [String],
        grounded: [ExchangeProviderGroundedFact],
        holes: [String]
    )? {
        guard let offer = context.offer else {
            return nil
        }

        let lower = inquiry.lowercased()
        guard lower.contains("price") || lower.contains("quote") || lower.contains("cost") else {
            return nil
        }

        switch offer.fulfillment.pricingMode {
        case .quoteRequired, .custom, .undisclosed:
            let mode = publishablePricingCue(offer)
            let text = """
            The published offer shows pricing as \(offer.fulfillment.pricingMode.displayCanonical). \
            I can’t invent negotiated numbers from here—please confirm a binding quote after seller review. (\(mode))
            """

            let missing = ["Exact invoiced tariff", "Quoted scope deltas", "Escalations for contingent fees"]

            return (
                text: text,
                known: ExchangeSellerSurfaceOperatingMemoryHydrator.offerFulfillmentFactLines(for: offer),
                grounded: offerGroundedFacts(from: offer),
                holes: missing
            )

        default:
            return nil
        }
    }

    private func publishablePricingCue(_ offer: ExchangeOffer) -> String {
        "Published lead note: \(offer.fulfillment.leadTimeNote ?? "unspecified")."
    }

    private func sanitizedPublicFactsSummary(_ context: ExchangeAgencyContext) -> [String] {
        ExchangeSellerSurfaceOperatingMemoryHydrator
            .hydrate(publicProfile: context.publicProfile, offer: context.offer)
            .compactCanonStrings(limit: 6)
    }

    private func assembleSafePublicSummary(_ lines: [String]) -> String {
        lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func missingCommitmentFacts() -> [String] {
        [
            """
            Agreed commercial terms are not present in published offer or profile details—seller confirmation is needed before relaying.
            """
        ]
    }

    private enum DiagnosticReason: String {
        case none
        case permissionOff
        case evidenceInsufficient
        case structuredNoMatch
        case customQuoteGate
        case riskBoundary
        case anchorMissing
    }

    private struct Diagnostics {
        var threadID: String
        var selectedOfferID: String
        var selectedPublicProfileID: String
        var queryKind: String
        var inquiry: String
        var permissionPolicy: ExchangeOffer.AutoAnswerPolicy?
        var legacyResolvedPolicy: ExchangeOffer.AutoAnswerPolicy?
        var offerEvidence: (
            hasAnyPublicPriceSignal: Bool,
            hasAvailabilityEvidence: Bool,
            hasPolicyEvidence: Bool,
            faqCount: Int
        )
        var memoryCounts: (pricing: Int, availability: Int, coverage: Int, policies: Int)

        init(
            context: ExchangeAgencyContext,
            inquiry: String,
            query: ExchangeStructuredAnswerEngine.Query,
            permissionPolicy: ExchangeOffer.AutoAnswerPolicy?,
            legacyResolvedPolicy: ExchangeOffer.AutoAnswerPolicy?
        ) {
            self.threadID = context.threadID?.uuidString ?? "nil"
            self.selectedOfferID = context.selectedOfferID ?? "nil"
            self.selectedPublicProfileID = context.selectedPublicProfileID ?? "nil"
            self.queryKind = query.kind.rawValue
            self.inquiry = inquiry
            self.permissionPolicy = permissionPolicy
            self.legacyResolvedPolicy = legacyResolvedPolicy
            let facts = context.offer?.commercialFacts
            self.offerEvidence = (
                facts?.hasAnyPublicPriceSignal == true,
                facts?.hasAvailabilityEvidence == true,
                facts?.hasPolicyEvidence == true,
                facts?.faqs.count ?? 0
            )
            self.memoryCounts = (
                context.operatingMemory.pricingRules.count,
                context.operatingMemory.availabilityWindows.count,
                context.operatingMemory.coverageAreas.count,
                context.operatingMemory.standardPolicies.count
            )
        }

        func log(
            reason: DiagnosticReason,
            structuredAnswerExists: Bool,
            result: ExchangeProviderAnswerability.Answerability
        ) {
            exchProviderAnswerabilityLog(
                "thread=\(threadID) offer=\(selectedOfferID) profile=\(selectedPublicProfileID) " +
                    "query=\(queryKind) inquiry=\"\(inquiry)\" " +
                    "perm[p=\(bool(permissionPolicy?.canAnswerPricing)) a=\(bool(permissionPolicy?.canAnswerAvailability)) pol=\(bool(permissionPolicy?.canAnswerPolicies)) sa=\(bool(permissionPolicy?.canAnswerServiceArea)) faq=\(bool(permissionPolicy?.canAnswerFAQs)) cq=\(bool(permissionPolicy?.requiresApprovalForCustomQuote))] " +
                    "legacy[p=\(bool(legacyResolvedPolicy?.canAnswerPricing)) a=\(bool(legacyResolvedPolicy?.canAnswerAvailability)) pol=\(bool(legacyResolvedPolicy?.canAnswerPolicies)) sa=\(bool(legacyResolvedPolicy?.canAnswerServiceArea)) faq=\(bool(legacyResolvedPolicy?.canAnswerFAQs)) cq=\(bool(legacyResolvedPolicy?.requiresApprovalForCustomQuote))] " +
                    "evidence[price=\(offerEvidence.hasAnyPublicPriceSignal) avail=\(offerEvidence.hasAvailabilityEvidence) policy=\(offerEvidence.hasPolicyEvidence) faqs=\(offerEvidence.faqCount)] " +
                    "memory[p=\(memoryCounts.pricing) a=\(memoryCounts.availability) c=\(memoryCounts.coverage) pol=\(memoryCounts.policies)] " +
                    "structured=\(structuredAnswerExists) reason=\(reason.rawValue) result=\(result.rawValue)"
            )
        }

        private func bool(_ value: Bool?) -> String {
            guard let value else { return "nil" }
            return value ? "1" : "0"
        }
    }

    private func makeAnswerability(
        answerability: ExchangeProviderAnswerability.Answerability,
        knownFactsUsed: [String],
        groundedFacts: [ExchangeProviderGroundedFact],
        missingFacts: [String],
        proposedAnswer: String?,
        requiresHumanApproval: Bool,
        allowsAutonomousDrafting: Bool,
        boundaryReason: String
    ) -> ExchangeProviderAnswerability {
        let normalizedGrounded = normalizedGroundedFacts(groundedFacts)
        let resolvedKnown = knownFactsUsed.isEmpty ? normalizedGrounded.map(\.text) : knownFactsUsed
        let canSendAutonomously =
            answerability == .answerableFromPublicFacts &&
            !requiresHumanApproval &&
            !normalizedGrounded.isEmpty

        return ExchangeProviderAnswerability(
            answerability: answerability,
            knownFactsUsed: resolvedKnown,
            groundedFacts: normalizedGrounded,
            missingFacts: missingFacts,
            proposedAnswer: proposedAnswer,
            requiresHumanApproval: requiresHumanApproval,
            allowsAutonomousDrafting: allowsAutonomousDrafting,
            allowsAutonomousSending: canSendAutonomously,
            boundaryReason: boundaryReason
        )
    }

    private func normalizedGroundedFacts(
        _ facts: [ExchangeProviderGroundedFact]
    ) -> [ExchangeProviderGroundedFact] {
        var seen = Set<String>()
        var output: [ExchangeProviderGroundedFact] = []
        for fact in facts {
            let text = fact.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let key = "\(fact.source.rawValue)|\(fact.field ?? "")|\(text.lowercased())"
            guard seen.insert(key).inserted else { continue }
            output.append(
                ExchangeProviderGroundedFact(
                    text: text,
                    source: fact.source,
                    field: fact.field
                )
            )
        }
        return output
    }

    private func providerGroundedFacts(
        context: ExchangeAgencyContext
    ) -> [ExchangeProviderGroundedFact] {
        offerGroundedFacts(from: context.offer) +
            publicProfileGroundedFacts(from: context.publicProfile) +
            operatingMemoryGroundedFacts(from: context.operatingMemory) +
            threadGroundedFacts(from: context.knownFacts)
    }

    private func offerGroundedFacts(from offer: ExchangeOffer?) -> [ExchangeProviderGroundedFact] {
        guard let offer else { return [] }
        let lines =
            ExchangeSellerSurfaceOperatingMemoryHydrator.offerFulfillmentFactLines(for: offer) +
            Array(offer.commercialSurfaceSkimLines.prefix(8))
        return lines.map {
            ExchangeProviderGroundedFact(
                text: $0,
                source: .offer,
                field: "offer"
            )
        }
    }

    private func publicProfileGroundedFacts(
        from profile: ExchangePublicNodeProfile?
    ) -> [ExchangeProviderGroundedFact] {
        guard let profile else { return [] }
        var lines: [String] = []
        if let dn = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !dn.isEmpty {
            lines.append("Public profile display name: \(dn)")
        }
        if let hl = profile.headline?.trimmingCharacters(in: .whitespacesAndNewlines), !hl.isEmpty {
            lines.append("Public profile headline: \(hl)")
        }
        lines.append("Public profile availability: \(profile.availability.rawValue)")
        lines.append(contentsOf: Array(profile.regionTags.prefix(5)).map { "Public profile region: \($0)" })
        return lines.map {
            ExchangeProviderGroundedFact(
                text: $0,
                source: .publicProfile,
                field: "publicProfile"
            )
        }
    }

    private func operatingMemoryGroundedFacts(
        from memory: ExchangeStructuredOperatingMemory
    ) -> [ExchangeProviderGroundedFact] {
        var lines: [ExchangeProviderGroundedFact] = []
        lines.append(contentsOf: memory.pricingRules.prefix(3).map {
            ExchangeProviderGroundedFact(
                text: "\($0.label): \($0.amountDescription)",
                source: .operatingMemory,
                field: "operatingMemory.pricingRules"
            )
        })
        lines.append(contentsOf: memory.availabilityWindows.prefix(3).map {
            ExchangeProviderGroundedFact(
                text: "Availability: \($0.label)\($0.details.map { " — \($0)" } ?? "")",
                source: .operatingMemory,
                field: "operatingMemory.availabilityWindows"
            )
        })
        lines.append(contentsOf: memory.coverageAreas.prefix(3).map {
            ExchangeProviderGroundedFact(
                text: "Coverage: \($0.name)\($0.details.map { " — \($0)" } ?? "")",
                source: .operatingMemory,
                field: "operatingMemory.coverageAreas"
            )
        })
        lines.append(contentsOf: memory.standardPolicies.prefix(3).map {
            ExchangeProviderGroundedFact(
                text: "\($0.title): \($0.details)",
                source: .operatingMemory,
                field: "operatingMemory.standardPolicies"
            )
        })
        return lines
    }

    private func threadGroundedFacts(
        from knownFacts: [String]
    ) -> [ExchangeProviderGroundedFact] {
        Array(knownFacts.prefix(6)).map {
            ExchangeProviderGroundedFact(
                text: $0,
                source: .thread,
                field: "thread.knownFacts"
            )
        }
    }
}

private extension ExchangeOffer.Fulfillment.PricingMode {
    var displayCanonical: String {
        switch self {
        case .fixed: return "fixed"
        case .quoteRequired: return "quote required"
        case .custom: return "custom"
        case .undisclosed: return "undisclosed"
        }
    }
}

private extension ExchangeStructuredOperatingMemory {

    func compactCanonStrings(limit: Int) -> [String] {
        guard limit > 0 else { return [] }

        var lines: [String] = []

        for rule in pricingRules.prefix(limit) {
            lines.append("\(rule.label): \(rule.amountDescription)")
        }

        for policy in standardPolicies.prefix(max(0, limit - lines.count)) {
            lines.append("\(policy.title): \(policy.details)")
        }

        return Array(lines.prefix(limit))
    }
}

// MARK: - Answerability UI labels

public extension ExchangeProviderAnswerability.Answerability {
    /// Human-readable label for projection and situation overlays.
    var pass2DisplayLabel: String {
        switch self {
        case .answerableFromPublicFacts:
            return "Answerable from published details"

        case .partiallyAnswerableNeedsClarification:
            return "Partially answerable; needs a short clarification"

        case .requiresProviderApproval:
            return "Needs seller review"

        case .notAnswerable:
            return "Not enough published detail to answer safely"
        }
    }
}
