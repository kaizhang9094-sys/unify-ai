import Foundation

public struct ExchangeAgencyDraftValidationResult: Sendable, Hashable {
    public var accepted: Bool
    public var rejectionReasons: [String]

    public init(accepted: Bool, rejectionReasons: [String]) {
        self.accepted = accepted
        self.rejectionReasons = rejectionReasons
    }
}

public enum ExchangeAgencyDraftValidator {
    public static func validateRequesterClarification(
        body: String,
        packet: RequesterClarificationDraftPacket
    ) -> [String] {
        var reasons: [String] = []
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            reasons.append("empty_body")
            return reasons
        }

        if trimmed.count > packet.maxLength {
            reasons.append("body_exceeds_max_length")
        }

        let lower = trimmed.lowercased()
        let compareSucceededNoDirected =
            packet.pass2LLMCompareSucceeded
            && (packet.providerDirectedQuestionLines ?? []).isEmpty
        if !compareSucceededNoDirected,
           !containsQuestionLanguage(lower, original: trimmed) {
            reasons.append("missing_question_language")
        }

        let forbiddenCommitments = [
            "confirmed booking",
            "appointment confirmed",
            "final quote",
            "guaranteed",
            "discount approved",
            "deposit",
            "payment",
            "contract accepted",
            "i agree",
            "we agree"
        ]

        if forbiddenCommitments.contains(where: { lower.contains($0) }) {
            reasons.append("contains_forbidden_commitment_phrase")
        }

        if !packet.pass2LLMCompareSucceeded,
           !packet.recommendedQuestions.isEmpty,
           (packet.providerDirectedQuestionLines ?? []).isEmpty {
            let themes = packet.recommendedQuestions
                .compactMap(themeToken(from:))
            if !themes.isEmpty && !themes.contains(where: { lower.contains($0) }) {
                reasons.append("missing_recommended_question_theme")
            }
        }

        return reasons
    }

    public static func validateProviderResponse(
        body: String,
        packet: ProviderResponseDraftPacket
    ) -> ExchangeAgencyDraftValidationResult {
        var reasons: [String] = []
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if trimmed.isEmpty {
            reasons.append("empty_body")
        }

        if trimmed.count > packet.maxLength {
            reasons.append("body_exceeds_max_length")
        }

        if packet.responseMode == .groundedAnswer && packet.approvedGroundedFacts.isEmpty {
            reasons.append("grounded_answer_requires_approved_facts")
        }

        if containsPricingLanguage(lower),
           !hasGroundedFactForPricing(packet.approvedGroundedFacts) {
            reasons.append("pricing_claim_without_grounded_fact")
        }

        if containsAvailabilityLanguage(lower),
           !hasGroundedFactForAvailability(packet.approvedGroundedFacts) {
            reasons.append("availability_claim_without_grounded_fact")
        }

        let forbiddenCommitments = [
            "booking confirmed",
            "appointment confirmed",
            "guaranteed",
            "final quote",
            "discount approved",
            "deposit",
            "payment",
            "contract accepted",
            "refund exception approved",
            "policy exception approved"
        ]
        if forbiddenCommitments.contains(where: { lower.contains($0) }) {
            reasons.append("contains_forbidden_commitment_phrase")
        }

        return ExchangeAgencyDraftValidationResult(
            accepted: reasons.isEmpty,
            rejectionReasons: reasons
        )
    }

    /// Human-facing checks for autonomous outbound (no internal scaffolding labels).
    public static func validateHumanFacingAutonomousBody(body: String, maxLength: Int) -> [String] {
        var reasons: [String] = []
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            reasons.append("empty_body")
            return reasons
        }
        if trimmed.count > maxLength {
            reasons.append("body_exceeds_max_length")
        }
        let lower = trimmed.lowercased()
        let forbiddenInternals = [
            "role:",
            "action:",
            "subject:",
            "boundary:",
            "thread context",
            "decision packet",
            "answerability",
            "provider-facing",
            "current request details",
            "based on available facts",
            "as an ai",
            "warm, relationship-aware tone",
            "balanced tone",
            "direct tone",
            "keep the wording",
            "structured facts",
            "known structured facts",
            "safe autonomous",
            "routine non-binding",
            "envelope id",
            "second_half",
            "metadata"
        ]
        if forbiddenInternals.contains(where: { lower.contains($0) }) {
            reasons.append("contains_internal_scaffolding")
        }
        if trimmed.contains("00000000-0000-") || (trimmed.contains("-") && trimmed.range(of: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#, options: .regularExpression) != nil) {
            reasons.append("contains_uuid_like_token")
        }
        return reasons
    }

    /// Validates requester autonomous LLM body using mode-specific rules on top of human-facing checks.
    public static func validateRequesterAutonomousOutbound(
        body: String,
        packet: RequesterClarificationDraftPacket
    ) -> [String] {
        var reasons = validateHumanFacingAutonomousBody(body: body, maxLength: packet.maxLength)
        guard reasons.isEmpty else { return reasons }

        let mode = packet.autonomousComposeMode ?? .askClarification
        switch mode {
        case .askClarification:
            reasons.append(contentsOf: validateRequesterClarification(body: body, packet: packet))
            if reasons.isEmpty {
                reasons.append(contentsOf: requesterAskClarificationProviderVoiceRejections(body: body))
            }
        case .recommendNextMove, .frameDecision:
            let lower = body.lowercased()
            let forbiddenCommitments = [
                "confirmed booking",
                "appointment confirmed",
                "final quote",
                "guaranteed",
                "discount approved",
                "deposit",
                "payment",
                "contract accepted",
                "i agree",
                "we agree"
            ]
            if forbiddenCommitments.contains(where: { lower.contains($0) }) {
                reasons.append("contains_forbidden_commitment_phrase")
            }
        }
        if packet.pass2LLMCompareSucceeded {
            reasons.append(contentsOf: compareSucceededOutboundQuestionGuardReasons(body: body, packet: packet))
        }
        return reasons
    }

    /// When grounded compare succeeded, outbound copy may only use compare-directed provider questions
    /// plus contract-allowed optional enrichment.
    static func compareSucceededOutboundQuestionGuardReasons(
        body: String,
        packet: RequesterClarificationDraftPacket
    ) -> [String] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let directed = (packet.providerDirectedQuestionLines ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let directedHaystack = directed.joined(separator: " ").lowercased()
        let contract = packet.outboundComposeContract
        let allowedEnrichment = contract?.allowedEnrichmentDimensions ?? []
        let maxOptionalEnrichment = allowedEnrichment.isEmpty
            ? 0
            : max(0, contract?.maxOptionalEnrichmentCount ?? 1)

        let scaffoldNeedles = [
            "for this request?",
            "for this job?",
            "hardened timeline",
            "high-level cues",
            "underspecified publicly",
            "services matching"
        ]

        if directed.isEmpty {
            if trimmed.contains("?") {
                return ["invented_provider_question_when_compare_empty"]
            }
            if bodyContainsForbiddenProviderQuestion(lower, directedHaystack: directedHaystack) {
                return ["invented_provider_diligence_when_compare_empty"]
            }
            let detected = detectedEnrichmentDimensions(in: trimmed)
            if !detected.isEmpty {
                return ["invented_provider_diligence_when_compare_empty"]
            }
            if scaffoldNeedles.contains(where: { lower.contains($0) }) {
                return ["invented_provider_diligence_when_compare_empty"]
            }
            return []
        }

        if bodyContainsForbiddenProviderQuestion(lower, directedHaystack: directedHaystack) {
            return ["extra_provider_diligence_beyond_compare_directed"]
        }

        let detected = detectedEnrichmentDimensions(in: trimmed)
        if hasUnapprovedEnrichmentDimensions(
            detected: detected,
            allowedEnrichment: allowedEnrichment,
            directedHaystack: directedHaystack
        ) {
            return ["extra_provider_diligence_beyond_compare_directed"]
        }

        if scaffoldNeedles.contains(where: { lower.contains($0) && !directedHaystack.contains($0) }) {
            return ["extra_provider_diligence_beyond_compare_directed"]
        }

        let questionMarkCount = trimmed.filter { $0 == "?" }.count
        let directedQuestionMarks = directed.reduce(0) { $0 + $1.filter { $0 == "?" }.count }
        let allowedQuestionMarks = directedQuestionMarks + maxOptionalEnrichment
        if questionMarkCount > allowedQuestionMarks {
            return ["extra_provider_questions_beyond_compare_directed"]
        }

        return []
    }

    /// Maps outbound body copy to optional enrichment dimensions (for tests and guard diagnostics).
    static func detectedEnrichmentDimensions(in body: String) -> Set<RequesterOutboundEnrichmentDimension> {
        let lower = body.lowercased()
        var detected = Set<RequesterOutboundEnrichmentDimension>()

        if matchesAnyPattern(lower, patterns: pricingProcessPatterns) {
            detected.insert(.pricingProcess)
        }
        if matchesAnyPattern(lower, patterns: estimateRangePatterns) {
            detected.insert(.estimateRange)
        }
        if matchesAnyPattern(lower, patterns: budgetAlignmentPatterns) {
            detected.insert(.budgetAlignment)
        }
        if matchesAnyPattern(lower, patterns: shippingOrDeliveryPatterns) {
            detected.insert(.shippingOrDelivery)
        }
        if matchesAnyPattern(lower, patterns: productConditionPatterns) {
            detected.insert(.productCondition)
        }
        if matchesAnyPattern(lower, patterns: collaborationModePatterns) {
            detected.insert(.collaborationMode)
        }
        if matchesAnyPattern(lower, patterns: commercialTermsPatterns) {
            detected.insert(.commercialTerms)
        }
        if matchesAnyPattern(lower, patterns: basicLogisticsPatterns) {
            detected.insert(.basicLogistics)
        }

        return detected
    }
}

private extension ExchangeAgencyDraftValidator {
    static let pricingProcessPatterns = [
        "how your pricing works",
        "how pricing works",
        "pricing policy",
        "pricing process",
        "your pricing",
        "pricing",
        " price ",
        " rate",
        " fee"
    ]

    static let estimateRangePatterns = [
        "how estimates usually work",
        "how estimates work",
        "estimate process",
        "rough estimate",
        "ballpark",
        " quote",
        "estimate"
    ]

    static let budgetAlignmentPatterns = [
        "within budget",
        "maximum spend",
        "max spend",
        "budget range",
        "under $",
        "under ",
        "budget"
    ]

    static let shippingOrDeliveryPatterns = [
        "how shipping",
        "how delivery",
        "shipping",
        "delivery",
        " shipped",
        " ship "
    ]

    static let productConditionPatterns = [
        "item condition",
        "used condition",
        "condition details",
        " condition"
    ]

    static let collaborationModePatterns = [
        "how collaboration",
        "working together",
        "work together",
        "how we would work",
        "collaborat"
    ]

    static let commercialTermsPatterns = [
        "commercial terms",
        "payment terms",
        "terms would apply"
    ]

    static let basicLogisticsPatterns = [
        "next steps to proceed",
        "basic logistics"
    ]

    static let forbiddenProviderQuestionPatterns = [
        "are you licensed",
        "are you insured",
        "licensed and insured",
        "whether you are licensed",
        "whether you are insured",
        "if you are licensed",
        "if you are insured",
        "your license",
        "your certification",
        "credential",
        "certification",
        "are you available",
        "your availability",
        "availability for",
        "service area",
        "serve the area",
        "serve my area",
        "cover this area",
        "turnaround",
        "lead time",
        "timeline for completion",
        "how long would it take"
    ]

    static func matchesAnyPattern(_ haystack: String, patterns: [String]) -> Bool {
        patterns.contains { haystack.contains($0) }
    }

    static func bodyContainsForbiddenProviderQuestion(_ lower: String, directedHaystack: String) -> Bool {
        forbiddenProviderQuestionPatterns.contains { pattern in
            lower.contains(pattern) && !directedHaystack.contains(pattern)
        }
    }

    static func hasUnapprovedEnrichmentDimensions(
        detected: Set<RequesterOutboundEnrichmentDimension>,
        allowedEnrichment: [RequesterOutboundEnrichmentDimension],
        directedHaystack: String
    ) -> Bool {
        let allowed = Set(allowedEnrichment)
        for dimension in detected {
            if directedHaystackCovers(dimension, haystack: directedHaystack) {
                continue
            }
            if isEnrichmentDimensionAllowed(dimension, allowed: allowed) {
                continue
            }
            return true
        }
        return false
    }

    static func isEnrichmentDimensionAllowed(
        _ dimension: RequesterOutboundEnrichmentDimension,
        allowed: Set<RequesterOutboundEnrichmentDimension>
    ) -> Bool {
        if allowed.contains(dimension) {
            return true
        }
        switch dimension {
        case .pricingProcess, .estimateRange:
            return allowed.contains(.pricingProcess) || allowed.contains(.estimateRange)
        case .budgetAlignment:
            return allowed.contains(.budgetAlignment)
                || allowed.contains(.pricingProcess)
                || allowed.contains(.estimateRange)
        default:
            return false
        }
    }

    static func directedHaystackCovers(
        _ dimension: RequesterOutboundEnrichmentDimension,
        haystack: String
    ) -> Bool {
        switch dimension {
        case .pricingProcess:
            return matchesAnyPattern(haystack, patterns: pricingProcessPatterns)
        case .estimateRange:
            return matchesAnyPattern(haystack, patterns: estimateRangePatterns)
        case .budgetAlignment:
            return matchesAnyPattern(haystack, patterns: budgetAlignmentPatterns)
        case .shippingOrDelivery:
            return matchesAnyPattern(haystack, patterns: shippingOrDeliveryPatterns)
        case .productCondition:
            return matchesAnyPattern(haystack, patterns: productConditionPatterns)
        case .collaborationMode:
            return matchesAnyPattern(haystack, patterns: collaborationModePatterns)
        case .commercialTerms:
            return matchesAnyPattern(haystack, patterns: commercialTermsPatterns)
        case .basicLogistics:
            return matchesAnyPattern(haystack, patterns: basicLogisticsPatterns)
        }
    }
}

private extension ExchangeAgencyDraftValidator {
    /// Narrow provider-voice detector for requester autonomous askClarification only.
    static func requesterAskClarificationProviderVoiceRejections(body: String) -> [String] {
        let lower = body.lowercased()
        var reasons: [String] = []
        let pairs: [(String, String)] = [
            ("thanks for reaching out", "provider_voice_thanks_reaching_out"),
            ("thank you for reaching out", "provider_voice_thanks_reaching_out"),
            ("thanks for contacting", "provider_voice_thanks_contacting"),
            ("i'm available to discuss", "provider_voice_im_available_discuss"),
            ("i am available to discuss", "provider_voice_im_available_discuss"),
            ("i'm available to teach", "provider_voice_im_available_teach"),
            ("i am available to teach", "provider_voice_im_available_teach"),
            ("i'm available", "provider_voice_im_available"),
            ("i am available", "provider_voice_im_available"),
            ("available to discuss a", "provider_voice_available_to_discuss"),
            ("available to provide", "provider_voice_available_to_provide"),
            ("i can offer", "provider_voice_i_can_offer"),
            ("i offer", "provider_voice_i_offer"),
            ("i provide", "provider_voice_i_provide"),
            ("my availability", "provider_voice_my_availability"),
            ("my lessons", "provider_voice_my_lessons"),
            ("book a session with me", "provider_voice_book_with_me"),
            ("schedule a lesson with me", "provider_voice_schedule_with_me")
        ]
        for pair in pairs where lower.contains(pair.0) {
            reasons.append(pair.1)
        }
        return reasons
    }

    static func containsQuestionLanguage(_ lower: String, original: String) -> Bool {
        if original.contains("?") { return true }
        let needles = ["could you", "can you", "please share", "please confirm", "what ", "which ", "when ", "where ", "how "]
        return needles.contains(where: { lower.contains($0) })
    }

    static func themeToken(from question: String) -> String? {
        let words = question
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 4 }
        return words.first
    }

    static func containsPricingLanguage(_ lower: String) -> Bool {
        ["price", "pricing", "quote", "rate", "cost", "usd", "$", "eur", "gbp"]
            .contains(where: { lower.contains($0) })
    }

    static func containsAvailabilityLanguage(_ lower: String) -> Bool {
        ["availability", "available", "slot", "schedule", "timeline", "lead time", "capacity"]
            .contains(where: { lower.contains($0) })
    }

    static func hasGroundedFactForPricing(_ facts: [ExchangeProviderGroundedFact]) -> Bool {
        facts.contains(where: {
            let field = $0.field?.lowercased() ?? ""
            let text = $0.text.lowercased()
            return field.contains("pricing")
                || field.contains("price")
                || text.contains("price")
                || text.contains("pricing")
                || text.contains("quote")
                || text.contains("$")
                || text.contains("usd")
                || text.contains("eur")
                || text.contains("gbp")
        })
    }

    static func hasGroundedFactForAvailability(_ facts: [ExchangeProviderGroundedFact]) -> Bool {
        facts.contains(where: {
            let field = $0.field?.lowercased() ?? ""
            let text = $0.text.lowercased()
            return field.contains("availability")
                || field.contains("lead")
                || field.contains("capacity")
                || text.contains("availability")
                || text.contains("lead time")
                || text.contains("capacity")
                || text.contains("schedule")
        })
    }
}
