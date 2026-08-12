import Foundation

/// Controls whether agency outbound materialization runs a full autonomous compose (`task=draft`) or trusts a grounded draft body.
public enum ExchangeDraftAgencyComposePolicy: String, Codable, Hashable, Sendable {
    /// Default: agency materialization may run full autonomous compose when eligible.
    case standard
    /// Compare-first governed `draftReply` is authoritative; skip full compose LLM.
    case skipFullComposeCompareFirstGrounded = "skip_full_compose"
}

/// Centralized second-half draft composition.
///
/// This composes outbound drafts from:
/// - thread priors
/// - secretary style profile
/// - structured operating facts
/// - selected next move
/// - commitment boundary
///
/// It intentionally stays deterministic and template-driven first, so the
/// second-half subsystem has a stable drafting baseline even before any
/// narrower LLM-assisted drafting is introduced later.
public struct ExchangeDraftComposer: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var role: ExchangeSecondHalfRole
        public var action: ExchangeSecondHalfAction
        public var priors: ExchangeThreadPriors
        public var style: ExchangeSecretaryStyleProfile
        public var operatingMemory: ExchangeStructuredOperatingMemory
        public var boundary: ExchangeCommitmentBoundary
        public var counterpartyName: String?
        public var subjectMatter: String?
        public var requestedItems: [String]
        public var clarifiedFacts: [String]
        public var unresolvedIssues: [String]
        public var customInstructions: String?
        public var isFirstExternalContact: Bool
        public var requestCapturedText: String?
        public var offerTitle: String?
        public var profileDisplayName: String?

        public init(
            role: ExchangeSecondHalfRole,
            action: ExchangeSecondHalfAction,
            priors: ExchangeThreadPriors,
            style: ExchangeSecretaryStyleProfile,
            operatingMemory: ExchangeStructuredOperatingMemory,
            boundary: ExchangeCommitmentBoundary = .safe,
            counterpartyName: String? = nil,
            subjectMatter: String? = nil,
            requestedItems: [String] = [],
            clarifiedFacts: [String] = [],
            unresolvedIssues: [String] = [],
            customInstructions: String? = nil,
            isFirstExternalContact: Bool = false,
            requestCapturedText: String? = nil,
            offerTitle: String? = nil,
            profileDisplayName: String? = nil
        ) {
            self.role = role
            self.action = action
            self.priors = priors
            self.style = style
            self.operatingMemory = operatingMemory
            self.boundary = boundary
            self.counterpartyName = counterpartyName
            self.subjectMatter = subjectMatter
            self.requestedItems = requestedItems
            self.clarifiedFacts = clarifiedFacts
            self.unresolvedIssues = unresolvedIssues
            self.customInstructions = customInstructions
            self.isFirstExternalContact = isFirstExternalContact
            self.requestCapturedText = requestCapturedText
            self.offerTitle = offerTitle
            self.profileDisplayName = profileDisplayName
        }
    }

    public struct Draft: Codable, Hashable, Sendable {
        public var subject: String?
        public var body: String
        public var usedStructuredFacts: [String]
        public var notes: [String]
        /// When set, persisted outbound draft receives matching metadata for agency materialization routing.
        public var agencyComposePolicy: ExchangeDraftAgencyComposePolicy?

        public init(
            subject: String? = nil,
            body: String,
            usedStructuredFacts: [String] = [],
            notes: [String] = [],
            agencyComposePolicy: ExchangeDraftAgencyComposePolicy? = nil
        ) {
            self.subject = subject
            self.body = body
            self.usedStructuredFacts = usedStructuredFacts
            self.notes = notes
            self.agencyComposePolicy = agencyComposePolicy
        }

        enum CodingKeys: String, CodingKey {
            case subject
            case body
            case usedStructuredFacts
            case notes
            case agencyComposePolicy
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            subject = try c.decodeIfPresent(String.self, forKey: .subject)
            body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
            usedStructuredFacts = try c.decodeIfPresent([String].self, forKey: .usedStructuredFacts) ?? []
            notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
            agencyComposePolicy = try c.decodeIfPresent(
                ExchangeDraftAgencyComposePolicy.self,
                forKey: .agencyComposePolicy
            )
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(subject, forKey: .subject)
            try c.encode(body, forKey: .body)
            try c.encode(usedStructuredFacts, forKey: .usedStructuredFacts)
            try c.encode(notes, forKey: .notes)
            try c.encodeIfPresent(agencyComposePolicy, forKey: .agencyComposePolicy)
        }
    }

    public func compose(
        input: Input
    ) -> Draft {
        let greeting = makeGreeting(style: input.style, counterpartyName: input.counterpartyName)
        let signoff = makeSignoff(style: input.style)
        let tonePrefix = makeTonePrefix(style: input.style)
        let subject = makeSubject(input: input)

        if shouldEmitMinimalAutonomousRequesterOutboundSeed(input) {
            return Draft(
                subject: subject,
                body: composeMinimalAutonomousRequesterOutboundBody(
                    greeting: greeting,
                    input: input,
                    signoff: signoff
                ),
                usedStructuredFacts: [],
                notes: notes(for: input)
            )
        }

        if shouldEmitMinimalProviderAutoRespondSeed(input) {
            let structured = bestStructuredFacts(for: input)
            return Draft(
                subject: subject,
                body: composeMinimalProviderAutoRespondBody(
                    greeting: greeting,
                    structuredFacts: structured,
                    signoff: signoff
                ),
                usedStructuredFacts: structured,
                notes: notes(for: input)
            )
        }

        switch input.action {
        case .askClarification:
            return Draft(
                subject: subject,
                body: composeClarificationBody(
                    greeting: greeting,
                    tonePrefix: tonePrefix,
                    input: input,
                    signoff: signoff
                ),
                usedStructuredFacts: [],
                notes: notes(for: input)
            )

        case .answerClarification, .autoRespond:
            let structured = bestStructuredFacts(for: input)
            return Draft(
                subject: subject,
                body: composeAnswerBody(
                    greeting: greeting,
                    tonePrefix: tonePrefix,
                    input: input,
                    structuredFacts: structured,
                    signoff: signoff
                ),
                usedStructuredFacts: structured,
                notes: notes(for: input)
            )

        case .proposeTerms, .reviseTerms:
            let structured = bestStructuredFacts(for: input)
            return Draft(
                subject: subject,
                body: composeTermsBody(
                    greeting: greeting,
                    tonePrefix: tonePrefix,
                    input: input,
                    structuredFacts: structured,
                    signoff: signoff
                ),
                usedStructuredFacts: structured,
                notes: notes(for: input)
            )

        case .frameDecision, .recommendNextMove, .compareOptions:
            return Draft(
                subject: subject,
                body: composeInternalDecisionBody(
                    tonePrefix: tonePrefix,
                    input: input
                ),
                usedStructuredFacts: [],
                notes: notes(for: input)
            )

        case .qualifyMatch,
             .requestUserInput,
             .escalateForApproval,
             .accept,
             .decline,
             .pause,
             .markBlocked,
             .markStalled,
             .complete:
            return Draft(
                subject: subject,
                body: composeFallbackBody(
                    greeting: greeting,
                    tonePrefix: tonePrefix,
                    input: input,
                    signoff: signoff
                ),
                usedStructuredFacts: [],
                notes: notes(for: input)
            )
        }
    }

    /// Deterministic seed for provider `autoRespond` when the move is autonomous-safe (no approval boundary) — recipient-facing only.
    private func shouldEmitMinimalProviderAutoRespondSeed(_ input: Input) -> Bool {
        guard input.role == .provider,
              input.action == .autoRespond,
              !input.boundary.requiresHumanApproval else { return false }
        return true
    }

    private func composeMinimalProviderAutoRespondBody(
        greeting: String,
        structuredFacts: [String],
        signoff: String
    ) -> String {
        let factBlock: String
        if structuredFacts.isEmpty {
            factBlock = "Thanks for your message. Here is what we can share from our published information."
        } else {
            factBlock = structuredFacts.joined(separator: "\n")
        }
        return [greeting, factBlock, signoff]
            .compactMap(nonEmpty)
            .joined(separator: "\n\n")
    }

    /// Deterministic seed for requester outbound drafts that may be replaced by LLM materialization — no internal stage directions in body.
    private func shouldEmitMinimalAutonomousRequesterOutboundSeed(_ input: Input) -> Bool {
        guard input.role == .requester, !input.boundary.requiresHumanApproval else { return false }
        switch input.action {
        case .askClarification, .recommendNextMove, .frameDecision:
            return true
        default:
            return false
        }
    }

    private func composeMinimalAutonomousRequesterOutboundBody(
        greeting: String,
        input: Input,
        signoff: String
    ) -> String {
        let subjectMatter =
            RequesterOutboundSubjectResolver.sanitizedOutboundSubject(input.subjectMatter)
            ?? "this opportunity"

        if input.isFirstExternalContact {
            return RequesterOutboundFirstContactComposer.compose(
                .init(
                    greeting: greeting,
                    signoff: signoff,
                    capturedRequestText: input.requestCapturedText,
                    subjectMatter: subjectMatter,
                    counterpartyName: input.counterpartyName,
                    offerTitle: input.offerTitle,
                    profileDisplayName: input.profileDisplayName
                )
            )
        }

        switch input.action {
        case .askClarification:
            return composeRequesterClarificationBuyerBody(
                greeting: greeting,
                tonePrefix: "",
                input: input,
                signoff: signoff
            )

        case .recommendNextMove:
            let line =
                "We're reviewing \(subjectMatter) and would value a concise note on what you recommend as the best next step."
            return [greeting, line, signoff]
                .compactMap(nonEmpty)
                .joined(separator: "\n\n")

        case .frameDecision:
            let line =
                "We're close to a decision on \(subjectMatter); please share any practical details that would help finalize."
            return [greeting, line, signoff]
                .compactMap(nonEmpty)
                .joined(separator: "\n\n")

        default:
            return composeFallbackBody(
                greeting: greeting,
                tonePrefix: "",
                input: input,
                signoff: signoff
            )
        }
    }

    private func composeClarificationBody(
        greeting: String,
        tonePrefix: String,
        input: Input,
        signoff: String
    ) -> String {
        if input.role == .requester {
            return composeRequesterClarificationBuyerBody(
                greeting: greeting,
                tonePrefix: tonePrefix,
                input: input,
                signoff: signoff
            )
        }

        let subjectMatter = nonEmpty(input.subjectMatter) ?? "this opportunity"
        let unresolved = cleaned(sanitizedUnresolvedIssuesForProviderClarification(input.unresolvedIssues))
        let priorQuestionSet = Set(cleaned(input.priors.priorQuestionsAsked).map(normalizedQuestion))
        let candidateQuestion = unresolved.first(where: { !priorQuestionSet.contains(normalizedQuestion($0)) })

        let questionLine: String
        if let first = candidateQuestion {
            questionLine = "To move forward on \(subjectMatter), could you clarify: \(first)"
        } else {
            questionLine = "To move forward on \(subjectMatter), could you clarify one remaining detail?"
        }

        let requestDetails = cleaned(input.clarifiedFacts + input.requestedItems)
        let detailsLine: String? = requestDetails.isEmpty
            ? nil
            : "Current request details: " + Array(requestDetails.prefix(4)).joined(separator: "; ")

        return [
            greeting,
            tonePrefix,
            detailsLine,
            questionLine,
            signoff
        ]
        .compactMap(nonEmpty)
        .joined(separator: "\n\n")
    }

    /// Buyer → provider clarification: prefer explicit provider-directed lines, then theme fallbacks from the user ask.
    private func composeRequesterClarificationBuyerBody(
        greeting: String,
        tonePrefix: String,
        input: Input,
        signoff: String
    ) -> String {
        let subjectMatter = nonEmpty(input.subjectMatter) ?? "this opportunity"
        let priorQuestionSet = Set(cleaned(input.priors.priorQuestionsAsked).map(normalizedQuestion))
        let directed = providerDirectedClarificationLines(input: input).filter {
            !priorQuestionSet.contains(normalizedQuestion($0))
        }
        if !directed.isEmpty {
            let intro = "I'm reaching out about \(subjectMatter). I'd appreciate your help with:"
            let bodyCore = ([intro] + directed).joined(separator: "\n")
            return [greeting, tonePrefix, bodyCore, signoff]
                .compactMap(nonEmpty)
                .joined(separator: "\n\n")
        }
        let fallback = requesterThemeFallbackQuestions(input: input).filter {
            !priorQuestionSet.contains(normalizedQuestion($0))
        }
        if !fallback.isEmpty {
            let intro = "I'm reaching out about \(subjectMatter). Could you help with:"
            let bodyCore = ([intro] + fallback).joined(separator: "\n")
            return [greeting, tonePrefix, bodyCore, signoff]
                .compactMap(nonEmpty)
                .joined(separator: "\n\n")
        }
        let unresolved = cleaned(sanitizedUnresolvedIssuesForProviderClarification(input.unresolvedIssues))
        let candidateQuestion = unresolved.first(where: { !priorQuestionSet.contains(normalizedQuestion($0)) })
        let questionLine: String
        if let first = candidateQuestion {
            questionLine = "To move forward on \(subjectMatter), could you clarify: \(first)"
        } else {
            questionLine = "To move forward on \(subjectMatter), could you clarify one remaining detail?"
        }
        let requestDetails = cleaned(input.clarifiedFacts + input.requestedItems)
        let detailsLine: String? = requestDetails.isEmpty
            ? nil
            : "Context: " + Array(requestDetails.prefix(4)).joined(separator: "; ")
        return [greeting, tonePrefix, detailsLine, questionLine, signoff]
            .compactMap(nonEmpty)
            .joined(separator: "\n\n")
    }

    private func sanitizedUnresolvedIssuesForProviderClarification(_ issues: [String]) -> [String] {
        cleaned(issues).filter { !Self.isStructuredMemoryNoiseClarificationLine($0) }
    }

    /// Filters operating-memory / scaffold lines that must never become provider-directed questions.
    private static func isStructuredMemoryNoiseClarificationLine(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        let bannedPhrases = [
            "published seller surface",
            "seller surfaces anchored",
            "anchored snapshot",
            "anchored on this snapshot",
            "exchange is strong enough",
            "coordination path",
            "fit movement",
            "hardened timeline",
            "system message",
            "throughput",
            "capacity/throughput",
            "return policy",
            "cancellation policy",
            "cancellation/refund",
            "refund policy"
        ]
        if bannedPhrases.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower.contains("shipping") || lower.contains("delivery window") {
            return true
        }
        return false
    }

    private func providerDirectedClarificationLines(input: Input) -> [String] {
        sanitizedUnresolvedIssuesForProviderClarification(input.unresolvedIssues).filter { line in
            let lower = line.lowercased()
            if lower.contains("please confirm") { return true }
            let keys = [
                "price", "rate", "pricing", "availability", "schedule", "location", "lesson",
                "in-person", "in person", "remote", "service area", "provider's", "provider",
                "financing", "mortgage", "down payment", "closing", "seller", "vtb", "take-back", "listing"
            ]
            return keys.contains { lower.contains($0) }
        }
    }

    private func requesterThemeFallbackQuestions(input: Input) -> [String] {
        var blob = (nonEmpty(input.subjectMatter) ?? "").lowercased()
        blob += " " + input.requestedItems.joined(separator: " ").lowercased()
        var lines: [String] = []
        let propertyHints = [
            "bedroom", "home", "house", "condo", "townhome", "townhouse",
            "mortgage", "listing", "for sale", "real estate", "property", "seller financing",
            "vtb", "vendor take", "closing", "gta"
        ]
        if propertyHints.contains(where: { blob.contains($0) }) {
            lines.append(
                "Could you confirm whether seller financing or a vendor take-back arrangement might be possible on suitable listings?"
            )
            lines.append(
                "What down payment, interest rate range, amortization term, and target closing timeframe would sellers typically consider?"
            )
            lines.append("Could we schedule a viewing window and clarify appraisal or inspection timing?")
        }
        if ["price", "rate", "cost", "how much", "tuition", "pricing"].contains(where: { blob.contains($0) }) {
            lines.append("Could you share your current rate or pricing for lessons?")
        }
        if blob.contains("availability") || blob.contains("schedule") || blob.contains(" available") {
            lines.append("Could you share your availability or typical lesson schedule?")
        }
        if ["location", "remote", "in-person", "in person", "online", "lesson location"].contains(where: { blob.contains($0) }) {
            lines.append(
                "Could you confirm whether lessons are in-person, remote/online, or both, and your service area or studio location?"
            )
        }
        return lines
    }

    private func composeAnswerBody(
        greeting: String,
        tonePrefix: String,
        input: Input,
        structuredFacts: [String],
        signoff: String
    ) -> String {
        let factBlock: String
        if structuredFacts.isEmpty {
            factBlock = "Here is the current answer based on the available thread context."
        } else {
            factBlock = structuredFacts.joined(separator: "\n")
        }

        let clarificationLine: String
        if !input.clarifiedFacts.isEmpty {
            clarificationLine = "This reflects the latest clarified facts from the thread."
        } else {
            clarificationLine = "This reflects the current known facts."
        }

        return [
            greeting,
            tonePrefix,
            factBlock,
            clarificationLine,
            signoff
        ]
        .compactMap(nonEmpty)
        .joined(separator: "\n\n")
    }

    private func composeTermsBody(
        greeting: String,
        tonePrefix: String,
        input: Input,
        structuredFacts: [String],
        signoff: String
    ) -> String {
        let subjectMatter = nonEmpty(input.subjectMatter) ?? "the current opportunity"
        let factBlock = structuredFacts.isEmpty
            ? "Here is a proposed next position for \(subjectMatter)."
            : "Relevant structured facts:\n" + structuredFacts.joined(separator: "\n")

        let boundaryLine: String
        if input.boundary.requiresHumanApproval {
            boundaryLine = "This position should be treated as draft-only pending explicit approval."
        } else {
            boundaryLine = "This position reflects the current intended next step."
        }

        return [
            greeting,
            tonePrefix,
            factBlock,
            boundaryLine,
            signoff
        ]
        .compactMap(nonEmpty)
        .joined(separator: "\n\n")
    }

    private func composeInternalDecisionBody(
        tonePrefix: String,
        input: Input
    ) -> String {
        var sections: [String] = []

        if let subjectMatter = nonEmpty(input.subjectMatter) {
            sections.append("Subject: \(subjectMatter)")
        }

        if let recommendation = nonEmpty(input.priors.lastKnownRecommendation) {
            sections.append("Prior recommendation: \(recommendation)")
        }

        if !input.clarifiedFacts.isEmpty {
            sections.append("Clarified facts: " + cleaned(input.clarifiedFacts).joined(separator: "; "))
        }

        if !input.unresolvedIssues.isEmpty {
            sections.append("Unresolved issues: " + cleaned(input.unresolvedIssues).joined(separator: "; "))
        }

        if let customInstructions = nonEmpty(input.customInstructions) {
            sections.append("Additional instruction: \(customInstructions)")
        }

        if let tone = nonEmpty(tonePrefix) {
            sections.insert(tone, at: 0)
        }

        return sections.joined(separator: "\n\n")
    }

    private func composeFallbackBody(
        greeting: String,
        tonePrefix: String,
        input: Input,
        signoff: String
    ) -> String {
        let actionText = "Action: \(input.action.displayTitle)."
        let subjectText = nonEmpty(input.subjectMatter).map { "Subject: \($0)." }
        let requestDetails = cleaned(input.clarifiedFacts + input.requestedItems)
        let detailsText = requestDetails.isEmpty
            ? nil
            : "Request details: " + Array(requestDetails.prefix(4)).joined(separator: "; ") + "."

        return [
            greeting,
            tonePrefix,
            actionText,
            subjectText,
            detailsText,
            signoff
        ]
        .compactMap(nonEmpty)
        .joined(separator: "\n\n")
    }

    private func makeSubject(input: Input) -> String? {
        let base = nonEmpty(input.subjectMatter) ?? "Thread update"

        switch input.action {
        case .askClarification:
            return "Clarification needed — \(base)"
        case .answerClarification, .autoRespond:
            return "Response — \(base)"
        case .proposeTerms:
            return "Proposed terms — \(base)"
        case .reviseTerms:
            return "Revised terms — \(base)"
        case .frameDecision:
            return "Decision frame — \(base)"
        case .recommendNextMove:
            return "Recommended next move — \(base)"
        case .compareOptions:
            return "Comparison — \(base)"
        default:
            return nil
        }
    }

    private func makeGreeting(
        style: ExchangeSecretaryStyleProfile,
        counterpartyName: String?
    ) -> String {
        let namePart = counterpartyName.map { " \($0)" } ?? ""

        switch style.tone {
        case .formal:
            return "Hello\(namePart),"
        case .warm:
            return "Hi\(namePart),"
        case .neutral, .concise, .direct:
            return "Hi\(namePart),"
        }
    }

    private func makeSignoff(
        style: ExchangeSecretaryStyleProfile
    ) -> String {
        switch style.tone {
        case .formal:
            return "Regards,"
        case .warm:
            return "Thanks,"
        case .neutral, .concise, .direct:
            return "Thank you,"
        }
    }

    private func makeTonePrefix(
        style: ExchangeSecretaryStyleProfile
    ) -> String {
        var parts: [String] = []

        switch style.warmthDirectness {
        case .warm:
            parts.append("Warm, relationship-aware tone.")
        case .balanced:
            parts.append("Balanced tone.")
        case .direct:
            parts.append("Direct tone.")
        }

        switch style.firmness {
        case .soft:
            parts.append("Keep the wording gentle.")
        case .balanced:
            parts.append("Keep the wording clear and steady.")
        case .firm:
            parts.append("Keep the wording clear and firm.")
        }

        if let extra = nonEmpty(style.freeformInstructions) {
            parts.append(extra)
        }

        return parts.joined(separator: " ")
    }

    private func bestStructuredFacts(
        for input: Input
    ) -> [String] {
        var facts: [String] = []

        facts.append(contentsOf: input.operatingMemory.pricingRules.prefix(2).map {
            "\($0.label): \($0.amountDescription)"
        })

        facts.append(contentsOf: input.operatingMemory.serviceItems.prefix(3).map {
            if let details = nonEmpty($0.details) {
                return "\($0.name): \(details)"
            } else {
                return $0.name
            }
        })

        facts.append(contentsOf: input.operatingMemory.coverageAreas.prefix(2).map {
            if let details = nonEmpty($0.details) {
                return "Coverage — \($0.name): \(details)"
            } else {
                return "Coverage — \($0.name)"
            }
        })

        facts.append(contentsOf: input.operatingMemory.availabilityWindows.prefix(2).map {
            if let details = nonEmpty($0.details) {
                return "Availability — \($0.label): \(details)"
            } else {
                return "Availability — \($0.label)"
            }
        })

        facts.append(contentsOf: input.operatingMemory.leadTimes.prefix(2).map {
            "\($0.label): \($0.turnaroundDescription)"
        })

        return cleaned(facts)
    }

    private func notes(
        for input: Input
    ) -> [String] {
        var notes: [String] = []

        notes.append("Role: \(input.role.displayTitle)")
        notes.append("Action: \(input.action.displayTitle)")
        notes.append("Boundary: \(input.boundary.kind.rawValue)")

        if input.boundary.requiresHumanApproval {
            notes.append("Approval required before external commitment.")
        }

        return notes
    }

    private func cleaned(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                output.append(trimmed)
            }
        }

        return output
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedQuestion(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
