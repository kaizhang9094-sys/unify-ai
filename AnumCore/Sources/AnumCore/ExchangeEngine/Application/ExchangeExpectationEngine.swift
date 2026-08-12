import Foundation

/// Builds a bounded expectation contract from thread intent + posture + facets.
///
/// This should stay mostly deterministic.
/// Later you may let an intelligence provider suggest refinements, but the
/// contract should remain clampable and legible.
public struct ExchangeExpectationEngine: Sendable {
    public init() {}

    public func buildExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets? = nil
    ) -> ExchangeExpectation {
        switch intent.kind {
        case .requestQuote:
            return buildQuoteExpectation(intent: intent, posture: posture, facets: facets)

        case .introduce:
            return buildIntroductionExpectation(intent: intent, posture: posture, facets: facets)

        case .arrangeCall:
            return buildArrangeCallExpectation(intent: intent, posture: posture, facets: facets)

        case .arrangeMeeting:
            return buildArrangeMeetingExpectation(intent: intent, posture: posture, facets: facets)

        case .followUp, .checkStatus:
            return buildFollowUpExpectation(intent: intent, posture: posture, facets: facets)

        case .message:
            return buildMessageExpectation(intent: intent, posture: posture, facets: facets)

        case .find, .source:
            return buildSearchExpectation(intent: intent, posture: posture, facets: facets)

        case .negotiate:
            return buildNegotiationExpectation(intent: intent, posture: posture, facets: facets)

        case .invite, .coordinate, .plan:
            return buildCoordinationExpectation(intent: intent, posture: posture, facets: facets)

        case .other:
            return buildOtherExpectation(intent: intent, posture: posture, facets: facets)
        }
    }

    public func recordAutoReplyUsed(
        _ expectation: ExchangeExpectation
    ) -> ExchangeExpectation {
        expectation.incrementingAutoReplyCount()
    }

    public func resetAutoReplyBudget(
        _ expectation: ExchangeExpectation
    ) -> ExchangeExpectation {
        expectation.resettingAutoReplyCount()
    }
}

private extension ExchangeExpectationEngine {
    func buildQuoteExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?
    ) -> ExchangeExpectation {
        let market = resolveMarketType(intent: intent, facets: facets)
        let fulfillment = resolveFulfillmentMode(intent: intent, facets: facets, marketType: market)
        let risk = resolveRiskLevel(intent: intent, facets: facets, marketType: market)

        return ExchangeExpectation(
            primaryGoal: .obtainQuote,
            preferredOutcome: .completed,
            acceptableOutcome: .meaningfulProgress,
            marketType: market,
            fulfillmentMode: fulfillment,
            riskLevel: risk,
            prefersLocalFirst: resolvePrefersLocalFirst(intent: intent, facets: facets, marketType: market),
            allowsRemoteOrShipped: resolveAllowsRemoteOrShipped(intent: intent, facets: facets, marketType: market),
            allowsAutonomousClarification: resolveAllowsAutonomousClarification(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk
            ),
            completionSignals: [
                .quoteReceived,
                .scopeClarified,
                .capabilityConfirmed,
                .capabilityDeclined,
                .explicitDecline
            ],
            stopConditions: baseStopConditions() + [
                .counterpartyRequestsSensitiveInfo,
                .counterpartyIntroducesPricingNegotiation,
                .counterpartyRequestsCommitment
            ],
            maxAutoReplies: autoReplyBudget(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk,
                fulfillmentMode: fulfillment,
                base: 1
            ),
            autoReplyCount: 0,
            requiresUserDecisionOn: [
                .answerMissingInfo,
                .reviewQuote,
                .approveDisclosureExpansion,
                .approveCommitment
            ],
            notes: "Goal is to reach a quote or a clean quote-enabling next step."
        )
    }

    func buildIntroductionExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?
    ) -> ExchangeExpectation {
        let market = resolveMarketType(intent: intent, facets: facets, fallback: .relationshipLed)
        let fulfillment = resolveFulfillmentMode(intent: intent, facets: facets, marketType: market, fallback: .remoteFriendly)
        let risk = resolveRiskLevel(intent: intent, facets: facets, marketType: market, fallback: .moderate)

        return ExchangeExpectation(
            primaryGoal: .secureIntroduction,
            preferredOutcome: .completed,
            acceptableOutcome: .meaningfulProgress,
            marketType: market,
            fulfillmentMode: fulfillment,
            riskLevel: risk,
            prefersLocalFirst: resolvePrefersLocalFirst(intent: intent, facets: facets, marketType: market),
            allowsRemoteOrShipped: true,
            allowsAutonomousClarification: false,
            completionSignals: [
                .introAccepted,
                .introDeclined,
                .answerReceived,
                .explicitDecline
            ],
            stopConditions: baseStopConditions() + [
                .counterpartyRequestsSensitiveInfo,
                .counterpartyRequestsCommitment
            ],
            maxAutoReplies: autoReplyBudget(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk,
                fulfillmentMode: fulfillment,
                base: 1
            ),
            autoReplyCount: 0,
            requiresUserDecisionOn: [
                .approveOutbound,
                .approveDisclosureExpansion,
                .resolveAmbiguity
            ],
            notes: "Goal is a clean intro outcome, not open-ended social negotiation."
        )
    }

    func buildArrangeCallExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?
    ) -> ExchangeExpectation {
        let market = resolveMarketType(intent: intent, facets: facets)
        let fulfillment = resolveFulfillmentMode(intent: intent, facets: facets, marketType: market, fallback: .remoteFriendly)
        let risk = resolveRiskLevel(intent: intent, facets: facets, marketType: market)

        return ExchangeExpectation(
            primaryGoal: .arrangeCall,
            preferredOutcome: .completed,
            acceptableOutcome: .meaningfulProgress,
            marketType: market,
            fulfillmentMode: fulfillment,
            riskLevel: risk,
            prefersLocalFirst: false,
            allowsRemoteOrShipped: true,
            allowsAutonomousClarification: resolveAllowsAutonomousClarification(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk
            ),
            completionSignals: [
                .availabilityConfirmed,
                .meetingProposed,
                .meetingConfirmed,
                .explicitDecline
            ],
            stopConditions: baseStopConditions() + [
                .counterpartyRequestsCommitment
            ],
            maxAutoReplies: autoReplyBudget(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk,
                fulfillmentMode: fulfillment,
                base: 2
            ),
            autoReplyCount: 0,
            requiresUserDecisionOn: [
                .confirmSchedulingChoice,
                .approveCommitment,
                .resolveAmbiguity
            ],
            notes: "Low-risk scheduling may continue briefly, but should stop before commitment-bearing details."
        )
    }

    func buildArrangeMeetingExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?
    ) -> ExchangeExpectation {
        let market = resolveMarketType(intent: intent, facets: facets)
        let fulfillment = resolveFulfillmentMode(intent: intent, facets: facets, marketType: market)
        let risk = resolveRiskLevel(intent: intent, facets: facets, marketType: market)

        return ExchangeExpectation(
            primaryGoal: .arrangeMeeting,
            preferredOutcome: .completed,
            acceptableOutcome: .meaningfulProgress,
            marketType: market,
            fulfillmentMode: fulfillment,
            riskLevel: risk,
            prefersLocalFirst: resolvePrefersLocalFirst(intent: intent, facets: facets, marketType: market),
            allowsRemoteOrShipped: resolveAllowsRemoteOrShipped(intent: intent, facets: facets, marketType: market),
            allowsAutonomousClarification: resolveAllowsAutonomousClarification(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk
            ),
            completionSignals: [
                .availabilityConfirmed,
                .meetingProposed,
                .meetingConfirmed,
                .explicitDecline
            ],
            stopConditions: baseStopConditions() + [
                .counterpartyRequestsCommitment
            ],
            maxAutoReplies: autoReplyBudget(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk,
                fulfillmentMode: fulfillment,
                base: 2
            ),
            autoReplyCount: 0,
            requiresUserDecisionOn: [
                .confirmSchedulingChoice,
                .approveCommitment,
                .resolveAmbiguity
            ],
            notes: "Meeting coordination can continue briefly if choices stay routine."
        )
    }

    func buildFollowUpExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?
    ) -> ExchangeExpectation {
        let market = resolveMarketType(intent: intent, facets: facets)
        let fulfillment = resolveFulfillmentMode(intent: intent, facets: facets, marketType: market)
        let risk = resolveRiskLevel(intent: intent, facets: facets, marketType: market)

        return ExchangeExpectation(
            primaryGoal: .confirmAvailability,
            preferredOutcome: .meaningfulProgress,
            acceptableOutcome: .basicResponse,
            marketType: market,
            fulfillmentMode: fulfillment,
            riskLevel: risk,
            prefersLocalFirst: resolvePrefersLocalFirst(intent: intent, facets: facets, marketType: market),
            allowsRemoteOrShipped: resolveAllowsRemoteOrShipped(intent: intent, facets: facets, marketType: market),
            allowsAutonomousClarification: resolveAllowsAutonomousClarification(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk
            ),
            completionSignals: [
                .answerReceived,
                .availabilityConfirmed,
                .explicitDecline
            ],
            stopConditions: baseStopConditions(),
            maxAutoReplies: autoReplyBudget(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk,
                fulfillmentMode: fulfillment,
                base: 1
            ),
            autoReplyCount: 0,
            requiresUserDecisionOn: [
                .chooseBetweenOptions,
                .resolveAmbiguity
            ],
            notes: "Goal is to re-open the thread or get a clear yes/no/status signal."
        )
    }

    func buildMessageExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?
    ) -> ExchangeExpectation {
        let market = resolveMarketType(intent: intent, facets: facets)
        let fulfillment = resolveFulfillmentMode(intent: intent, facets: facets, marketType: market)
        let risk = resolveRiskLevel(intent: intent, facets: facets, marketType: market)

        return ExchangeExpectation(
            primaryGoal: .establishContact,
            preferredOutcome: .meaningfulProgress,
            acceptableOutcome: .basicResponse,
            marketType: market,
            fulfillmentMode: fulfillment,
            riskLevel: risk,
            prefersLocalFirst: resolvePrefersLocalFirst(intent: intent, facets: facets, marketType: market),
            allowsRemoteOrShipped: resolveAllowsRemoteOrShipped(intent: intent, facets: facets, marketType: market),
            allowsAutonomousClarification: resolveAllowsAutonomousClarification(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk
            ),
            completionSignals: [
                .answerReceived,
                .capabilityConfirmed,
                .capabilityDeclined,
                .explicitDecline
            ],
            stopConditions: baseStopConditions() + [
                .counterpartyRequestsSensitiveInfo,
                .counterpartyRequestsCommitment
            ],
            maxAutoReplies: autoReplyBudget(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk,
                fulfillmentMode: fulfillment,
                base: 1
            ),
            autoReplyCount: 0,
            requiresUserDecisionOn: [
                .approveDisclosureExpansion,
                .approveCommitment,
                .resolveAmbiguity
            ],
            notes: "Goal is meaningful thread progress, not endless exchange."
        )
    }

    func buildSearchExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?
    ) -> ExchangeExpectation {
        let market = resolveMarketType(intent: intent, facets: facets)
        let fulfillment = resolveFulfillmentMode(intent: intent, facets: facets, marketType: market)
        let risk = resolveRiskLevel(intent: intent, facets: facets, marketType: market)

        return ExchangeExpectation(
            primaryGoal: .confirmFit,
            preferredOutcome: .meaningfulProgress,
            acceptableOutcome: .basicResponse,
            marketType: market,
            fulfillmentMode: fulfillment,
            riskLevel: risk,
            prefersLocalFirst: resolvePrefersLocalFirst(intent: intent, facets: facets, marketType: market),
            allowsRemoteOrShipped: resolveAllowsRemoteOrShipped(intent: intent, facets: facets, marketType: market),
            allowsAutonomousClarification: resolveAllowsAutonomousClarification(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk
            ),
            completionSignals: [
                .capabilityConfirmed,
                .capabilityDeclined,
                .answerReceived,
                .explicitDecline
            ],
            stopConditions: baseStopConditions() + [
                .counterpartyRequestsSensitiveInfo,
                .counterpartyRequestsCommitment
            ],
            maxAutoReplies: autoReplyBudget(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk,
                fulfillmentMode: fulfillment,
                base: 1
            ),
            autoReplyCount: 0,
            requiresUserDecisionOn: [
                .chooseBetweenOptions,
                .approveDisclosureExpansion,
                .resolveAmbiguity
            ],
            notes: "Goal is fit confirmation or clean disqualification."
        )
    }

    func buildNegotiationExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?
    ) -> ExchangeExpectation {
        let market = resolveMarketType(intent: intent, facets: facets)
        let fulfillment = resolveFulfillmentMode(intent: intent, facets: facets, marketType: market)
        let risk: ExchangeExpectation.RiskLevel = .high

        return ExchangeExpectation(
            primaryGoal: .advanceNegotiation,
            preferredOutcome: .meaningfulProgress,
            acceptableOutcome: .basicResponse,
            marketType: market,
            fulfillmentMode: fulfillment,
            riskLevel: risk,
            prefersLocalFirst: resolvePrefersLocalFirst(intent: intent, facets: facets, marketType: market),
            allowsRemoteOrShipped: resolveAllowsRemoteOrShipped(intent: intent, facets: facets, marketType: market),
            allowsAutonomousClarification: false,
            completionSignals: [
                .termsAccepted,
                .explicitDecline,
                .answerReceived
            ],
            stopConditions: baseStopConditions() + [
                .counterpartyIntroducesPricingNegotiation,
                .counterpartyIntroducesContractualTerms,
                .counterpartyRequestsCommitment,
                .disclosureBoundaryReached
            ],
            maxAutoReplies: 0,
            autoReplyCount: 0,
            requiresUserDecisionOn: [
                .reviewCounteroffer,
                .approveCommitment,
                .approveDisclosureExpansion
            ],
            notes: "Negotiation is high-judgment. Default to stopping before autonomous continuation."
        )
    }

    func buildCoordinationExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?
    ) -> ExchangeExpectation {
        let market = resolveMarketType(intent: intent, facets: facets)
        let fulfillment = resolveFulfillmentMode(intent: intent, facets: facets, marketType: market)
        let risk = resolveRiskLevel(intent: intent, facets: facets, marketType: market)

        return ExchangeExpectation(
            primaryGoal: .gatherInformation,
            preferredOutcome: .meaningfulProgress,
            acceptableOutcome: .basicResponse,
            marketType: market,
            fulfillmentMode: fulfillment,
            riskLevel: risk,
            prefersLocalFirst: resolvePrefersLocalFirst(intent: intent, facets: facets, marketType: market),
            allowsRemoteOrShipped: resolveAllowsRemoteOrShipped(intent: intent, facets: facets, marketType: market),
            allowsAutonomousClarification: resolveAllowsAutonomousClarification(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk
            ),
            completionSignals: [
                .answerReceived,
                .availabilityConfirmed,
                .meetingProposed,
                .explicitDecline
            ],
            stopConditions: baseStopConditions() + [
                .counterpartyRequestsCommitment,
                .counterpartyChangesScopeMaterially
            ],
            maxAutoReplies: autoReplyBudget(
                intent: intent,
                posture: posture,
                facets: facets,
                riskLevel: risk,
                fulfillmentMode: fulfillment,
                base: 1
            ),
            autoReplyCount: 0,
            requiresUserDecisionOn: [
                .chooseBetweenOptions,
                .confirmSchedulingChoice,
                .resolveAmbiguity
            ],
            notes: "General coordination may continue briefly if the thread remains routine."
        )
    }

    func buildOtherExpectation(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?
    ) -> ExchangeExpectation {
        let market = resolveMarketType(intent: intent, facets: facets)
        let fulfillment = resolveFulfillmentMode(intent: intent, facets: facets, marketType: market)
        let risk = resolveRiskLevel(intent: intent, facets: facets, marketType: market)

        return ExchangeExpectation.cautiousDefault
            .withMarketType(market)
            .withFulfillmentMode(fulfillment)
            .withRiskLevel(risk)
            .withLocalityPreference(
                prefersLocalFirst: resolvePrefersLocalFirst(intent: intent, facets: facets, marketType: market),
                allowsRemoteOrShipped: resolveAllowsRemoteOrShipped(intent: intent, facets: facets, marketType: market)
            )
            .withAutonomousClarificationAllowed(
                resolveAllowsAutonomousClarification(
                    intent: intent,
                    posture: posture,
                    facets: facets,
                    riskLevel: risk
                )
            )
            .withAutoReplyBudget(
                autoReplyBudget(
                    intent: intent,
                    posture: posture,
                    facets: facets,
                    riskLevel: risk,
                    fulfillmentMode: fulfillment,
                    base: 0
                )
            )
            .withNotes("Fallback expectation for loosely structured thread.")
    }

    func baseStopConditions() -> [ExchangeExpectation.StopCondition] {
        [
            .autoReplyBudgetExhausted,
            .ambiguityTooHigh,
            .repeatedLoopDetected,
            .userInputRequired,
            .approvalRequired,
            .disclosureBoundaryReached
        ]
    }

    func autoReplyBudget(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?,
        riskLevel: ExchangeExpectation.RiskLevel,
        fulfillmentMode: ExchangeExpectation.FulfillmentMode,
        base: Int
    ) -> Int {
        var value = base

        if posture.privacy == .guarded {
            value = min(value, 1)
        }

        if riskLevel == .high {
            value = 0
        }

        if intent.kind == .negotiate || intent.kind == .introduce {
            value = 0
        }

        if facets?.allowsAutonomousClarification == false {
            value = 0
        }

        if fulfillmentMode == .localOnly {
            value = min(value, 1)
        }

        if posture.directness == .firm &&
            (intent.kind == .arrangeCall || intent.kind == .arrangeMeeting) {
            value = min(2, max(value, 1))
        }

        return max(0, min(value, 1))
    }

    func resolveMarketType(
        intent: ExchangeIntent,
        facets: ExchangeIntentFacets?,
        fallback: ExchangeExpectation.MarketType? = nil
    ) -> ExchangeExpectation.MarketType {
        if let facets {
            switch facets.marketType {
            case .localService: return .localService
            case .physicalGoods: return .physicalGoods
            case .digitalService: return .digitalService
            case .informationRequest: return .informationRequest
            case .relationshipLed: return .relationshipLed
            case .unknown: break
            }
        }

        if let fallback {
            return fallback
        }

        return inferMarketType(intent: intent)
    }

    func resolveFulfillmentMode(
        intent: ExchangeIntent,
        facets: ExchangeIntentFacets?,
        marketType: ExchangeExpectation.MarketType,
        fallback: ExchangeExpectation.FulfillmentMode? = nil
    ) -> ExchangeExpectation.FulfillmentMode {
        if let facets {
            switch facets.fulfillmentMode {
            case .localOnly: return .localOnly
            case .localPreferred: return .localPreferred
            case .remoteFriendly: return .remoteFriendly
            case .shippable: return .shippable
            case .digitalDelivery: return .digitalDelivery
            case .unknown: break
            }
        }

        if let fallback {
            return fallback
        }

        return inferFulfillmentMode(intent: intent, marketType: marketType)
    }

    func resolveRiskLevel(
        intent: ExchangeIntent,
        facets: ExchangeIntentFacets?,
        marketType: ExchangeExpectation.MarketType,
        fallback: ExchangeExpectation.RiskLevel? = nil
    ) -> ExchangeExpectation.RiskLevel {
        if let facets {
            switch facets.riskLevel {
            case .low: return .low
            case .moderate: return .moderate
            case .high: return .high
            }
        }

        if let fallback {
            return fallback
        }

        return inferRiskLevel(intent: intent, marketType: marketType)
    }

    func resolvePrefersLocalFirst(
        intent: ExchangeIntent,
        facets: ExchangeIntentFacets?,
        marketType: ExchangeExpectation.MarketType
    ) -> Bool {
        if let facets, facets.prefersLocalFirst {
            return true
        }

        return prefersLocalFirst(intent: intent, marketType: marketType)
    }

    func resolveAllowsRemoteOrShipped(
        intent: ExchangeIntent,
        facets: ExchangeIntentFacets?,
        marketType: ExchangeExpectation.MarketType
    ) -> Bool {
        if let facets {
            return facets.allowsRemoteOrShipped
        }

        return allowsRemoteOrShipped(intent: intent, marketType: marketType)
    }

    func resolveAllowsAutonomousClarification(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        facets: ExchangeIntentFacets?,
        riskLevel: ExchangeExpectation.RiskLevel
    ) -> Bool {
        if let facets {
            return facets.allowsAutonomousClarification &&
                allowsAutonomousClarification(
                    intent: intent,
                    posture: posture,
                    riskLevel: riskLevel
                )
        }

        return allowsAutonomousClarification(
            intent: intent,
            posture: posture,
            riskLevel: riskLevel
        )
    }

    func inferMarketType(
        intent: ExchangeIntent
    ) -> ExchangeExpectation.MarketType {
        let haystack = [
            intent.title,
            intent.objective,
            intent.targetDescription ?? "",
            intent.interpretationNotes ?? "",
            intent.constraints.map { "\($0.key) \($0.value)" }.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        if containsAny(haystack, [
            "restaurant", "food", "meal", "catering", "coffee", "bakery",
            "plumber", "electrician", "roofer", "contractor", "cleaner",
            "barber", "salon", "dentist", "mechanic", "near me", "local"
        ]) {
            return .localService
        }

        if containsAny(haystack, [
            "ship", "shipping", "deliver", "delivery", "inventory", "product",
            "goods", "item", "manufacturer", "supplier", "wholesale", "retail",
            "car", "vehicle", "parts", "equipment", "furniture"
        ]) {
            return .physicalGoods
        }

        if containsAny(haystack, [
            "software", "design", "marketing", "consulting", "developer",
            "programmer", "editor", "writer", "digital", "online", "remote"
        ]) {
            return .digitalService
        }

        if containsAny(haystack, [
            "intro", "introduce", "relationship", "dating", "friend", "social"
        ]) {
            return .relationshipLed
        }

        if containsAny(haystack, [
            "ask", "question", "info", "information", "availability", "status", "follow up"
        ]) {
            return .informationRequest
        }

        switch intent.kind {
        case .introduce:
            return .relationshipLed
        case .requestQuote:
            return .physicalGoods
        case .find, .source:
            return .informationRequest
        case .arrangeCall, .arrangeMeeting, .followUp, .checkStatus, .message, .coordinate, .plan:
            return .informationRequest
        case .negotiate, .invite, .other:
            return .unknown
        }
    }

    func inferFulfillmentMode(
        intent: ExchangeIntent,
        marketType: ExchangeExpectation.MarketType
    ) -> ExchangeExpectation.FulfillmentMode {
        let haystack = [
            intent.title,
            intent.objective,
            intent.targetDescription ?? "",
            intent.interpretationNotes ?? "",
            intent.constraints.map { "\($0.key) \($0.value)" }.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        if containsAny(haystack, ["pickup only", "must be local", "on site", "onsite", "near me"]) {
            return .localOnly
        }

        if containsAny(haystack, ["remote", "virtual", "zoom", "phone", "call"]) {
            return .remoteFriendly
        }

        if containsAny(haystack, ["download", "digital", "online only"]) {
            return .digitalDelivery
        }

        if containsAny(haystack, ["ship", "shipping", "deliver", "delivery"]) {
            return .shippable
        }

        switch marketType {
        case .localService:
            return .localPreferred
        case .physicalGoods:
            return .shippable
        case .digitalService:
            return .digitalDelivery
        case .informationRequest, .relationshipLed:
            return .remoteFriendly
        case .unknown:
            return .unknown
        }
    }

    func inferRiskLevel(
        intent: ExchangeIntent,
        marketType: ExchangeExpectation.MarketType
    ) -> ExchangeExpectation.RiskLevel {
        let haystack = [
            intent.title,
            intent.objective,
            intent.targetDescription ?? "",
            intent.interpretationNotes ?? "",
            intent.constraints.map { "\($0.key) \($0.value)" }.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        if intent.kind == .negotiate {
            return .high
        }

        if containsAny(haystack, [
            "contract", "agreement", "legal", "lawyer", "financing",
            "loan", "mortgage", "counteroffer", "terms", "large order",
            "high value", "expensive"
        ]) {
            return .high
        }

        if containsAny(haystack, [
            "car", "vehicle", "contractor", "renovation", "manufacturer",
            "equipment", "wholesale", "quote"
        ]) {
            return .moderate
        }

        switch marketType {
        case .localService, .physicalGoods, .digitalService, .informationRequest, .relationshipLed, .unknown:
            return .moderate
        }
    }

    func prefersLocalFirst(
        intent: ExchangeIntent,
        marketType: ExchangeExpectation.MarketType
    ) -> Bool {
        let haystack = [
            intent.title,
            intent.objective,
            intent.targetDescription ?? "",
            intent.interpretationNotes ?? "",
            intent.constraints.map { "\($0.key) \($0.value)" }.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        if containsAny(haystack, ["near me", "local", "nearby", "hamilton", "toronto", "in person"]) {
            return true
        }

        switch marketType {
        case .localService:
            return true
        case .relationshipLed:
            return containsAny(haystack, ["meet", "date", "in person"])
        case .physicalGoods, .digitalService, .informationRequest, .unknown:
            return false
        }
    }

    func allowsRemoteOrShipped(
        intent: ExchangeIntent,
        marketType: ExchangeExpectation.MarketType
    ) -> Bool {
        let haystack = [
            intent.title,
            intent.objective,
            intent.targetDescription ?? "",
            intent.interpretationNotes ?? "",
            intent.constraints.map { "\($0.key) \($0.value)" }.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        if containsAny(haystack, ["must be local", "local only", "on site", "onsite", "pickup only"]) {
            return false
        }

        if containsAny(haystack, ["remote", "virtual", "ship", "shipping", "delivery", "online"]) {
            return true
        }

        switch marketType {
        case .physicalGoods, .digitalService, .informationRequest, .relationshipLed:
            return true
        case .localService, .unknown:
            return false
        }
    }

    func allowsAutonomousClarification(
        intent: ExchangeIntent,
        posture: ExchangePosture,
        riskLevel: ExchangeExpectation.RiskLevel
    ) -> Bool {
        if riskLevel == .high {
            return false
        }

        if posture.privacy == .guarded {
            return false
        }

        if intent.kind == .negotiate || intent.kind == .introduce {
            return false
        }

        return true
    }

    func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
}
