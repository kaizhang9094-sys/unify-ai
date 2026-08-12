import Foundation

public struct ExchangeAutonomousSendDecision: Sendable, Hashable {
    public enum Outcome: Hashable, Sendable {
        case allowed
        case disabledByUserSetting
        case needsUserApproval
        case needsProviderSetup
        case insufficientGrounding
        case deliveryUnavailable
        case duplicate
        case blocked(String)
    }

    public let outcome: Outcome
    public let allowed: Bool
    public let reason: String
    public let userAuthoritySummary: String
    public let groundingSummary: String
    public let deliverySummary: String

    public init(
        outcome: Outcome,
        allowed: Bool,
        reason: String,
        userAuthoritySummary: String,
        groundingSummary: String,
        deliverySummary: String
    ) {
        self.outcome = outcome
        self.allowed = allowed
        self.reason = reason
        self.userAuthoritySummary = userAuthoritySummary
        self.groundingSummary = groundingSummary
        self.deliverySummary = deliverySummary
    }

    public var outcomeSlug: String {
        switch outcome {
        case .allowed:
            return "allowed"
        case .disabledByUserSetting:
            return "disabledByUserSetting"
        case .needsUserApproval:
            return "needsUserApproval"
        case .needsProviderSetup:
            return "needsProviderSetup"
        case .insufficientGrounding:
            return "insufficientGrounding"
        case .deliveryUnavailable:
            return "deliveryUnavailable"
        case .duplicate:
            return "duplicate"
        case .blocked:
            return "blocked"
        }
    }
}

public enum ExchangeAutonomousUserAuthority: String, Sendable, Hashable {
    case manualOnly
    case draftOnly
    case routineAutoRespond
    case fullWithinBoundaries
    case missing
    case invalid

    public var allowsAutonomousSend: Bool {
        switch self {
        case .routineAutoRespond, .fullWithinBoundaries:
            return true
        case .manualOnly, .draftOnly, .missing, .invalid:
            return false
        }
    }

    /// Whether second-half may prepare outbound draft artifacts (template or LLM) for user review.
    public var allowsDraftPreparation: Bool {
        switch self {
        case .draftOnly, .routineAutoRespond, .fullWithinBoundaries:
            return true
        case .manualOnly, .missing, .invalid:
            return false
        }
    }

    /// When auto-send is blocked, prepared requester drafts should remain visible for review.
    public var shouldSurfacePreparedDraftWhenSendBlocked: Bool {
        self == .draftOnly
    }
}

public enum ExchangeAutonomousSendPolicy {
    private static let threadAutonomyModeKey = "secretary.threadAutonomy.mode"

    public struct ProviderInput: Sendable {
        public var userAuthority: ExchangeAutonomousUserAuthority
        public var actionRaw: String?
        public var canRunAutonomously: Bool
        public var needsHumanAttention: Bool
        public var boundaryRequiresApproval: Bool
        public var pass3GateAllowed: Bool
        public var hasVerifiedContextHold: Bool
        public var hasCounterparty: Bool
        public var hasDraft: Bool
        public var isDuplicate: Bool
        public var hasSelectedOfferAnchor: Bool
        public var hasSelectedPublicProfileAnchor: Bool
        public var providerAnswerability: ExchangeProviderAnswerability?
        /// Narrow path: compare-first direct grounded body already proved safe (bypass packet + governed compare); skip stale planner/display gates.
        public var canonicalCompareFirstDirectGroundedSend: Bool
        /// Compare-first direct was eligible but claim-boundary validator blocked auto-send (prevents fallback to other auto-send paths).
        public var compareFirstDirectClaimBoundaryBlocked: Bool

        public init(
            userAuthority: ExchangeAutonomousUserAuthority,
            actionRaw: String?,
            canRunAutonomously: Bool,
            needsHumanAttention: Bool,
            boundaryRequiresApproval: Bool,
            pass3GateAllowed: Bool,
            hasVerifiedContextHold: Bool,
            hasCounterparty: Bool,
            hasDraft: Bool,
            isDuplicate: Bool,
            hasSelectedOfferAnchor: Bool,
            hasSelectedPublicProfileAnchor: Bool,
            providerAnswerability: ExchangeProviderAnswerability?,
            canonicalCompareFirstDirectGroundedSend: Bool = false,
            compareFirstDirectClaimBoundaryBlocked: Bool = false
        ) {
            self.userAuthority = userAuthority
            self.actionRaw = actionRaw
            self.canRunAutonomously = canRunAutonomously
            self.needsHumanAttention = needsHumanAttention
            self.boundaryRequiresApproval = boundaryRequiresApproval
            self.pass3GateAllowed = pass3GateAllowed
            self.hasVerifiedContextHold = hasVerifiedContextHold
            self.hasCounterparty = hasCounterparty
            self.hasDraft = hasDraft
            self.isDuplicate = isDuplicate
            self.hasSelectedOfferAnchor = hasSelectedOfferAnchor
            self.hasSelectedPublicProfileAnchor = hasSelectedPublicProfileAnchor
            self.providerAnswerability = providerAnswerability
            self.canonicalCompareFirstDirectGroundedSend = canonicalCompareFirstDirectGroundedSend
            self.compareFirstDirectClaimBoundaryBlocked = compareFirstDirectClaimBoundaryBlocked
        }
    }

    public struct RequesterInput: Sendable {
        public var userAuthority: ExchangeAutonomousUserAuthority
        public var isRequesterRole: Bool
        public var hasEscalationReason: Bool
        public var providerAnswerabilityRequiresApproval: Bool
        public var actionRaw: String?
        public var actionSupported: Bool
        public var boundaryRequiresApproval: Bool
        public var boundaryAllowsAutonomousSending: Bool
        public var moveNeedsUserInput: Bool
        public var moveNeedsApproval: Bool
        public var moveIsAutonomous: Bool
        public var pass3GateAllowed: Bool
        public var hasVerifiedContextHold: Bool
        public var hasCounterparty: Bool
        public var hasDraft: Bool
        public var isDuplicate: Bool

        public init(
            userAuthority: ExchangeAutonomousUserAuthority,
            isRequesterRole: Bool,
            hasEscalationReason: Bool,
            providerAnswerabilityRequiresApproval: Bool,
            actionRaw: String?,
            actionSupported: Bool,
            boundaryRequiresApproval: Bool,
            boundaryAllowsAutonomousSending: Bool,
            moveNeedsUserInput: Bool,
            moveNeedsApproval: Bool,
            moveIsAutonomous: Bool,
            pass3GateAllowed: Bool,
            hasVerifiedContextHold: Bool,
            hasCounterparty: Bool,
            hasDraft: Bool,
            isDuplicate: Bool
        ) {
            self.userAuthority = userAuthority
            self.isRequesterRole = isRequesterRole
            self.hasEscalationReason = hasEscalationReason
            self.providerAnswerabilityRequiresApproval = providerAnswerabilityRequiresApproval
            self.actionRaw = actionRaw
            self.actionSupported = actionSupported
            self.boundaryRequiresApproval = boundaryRequiresApproval
            self.boundaryAllowsAutonomousSending = boundaryAllowsAutonomousSending
            self.moveNeedsUserInput = moveNeedsUserInput
            self.moveNeedsApproval = moveNeedsApproval
            self.moveIsAutonomous = moveIsAutonomous
            self.pass3GateAllowed = pass3GateAllowed
            self.hasVerifiedContextHold = hasVerifiedContextHold
            self.hasCounterparty = hasCounterparty
            self.hasDraft = hasDraft
            self.isDuplicate = isDuplicate
        }
    }

    public static func currentThreadAutonomyAuthority(
        defaults: UserDefaults = .standard
    ) -> ExchangeAutonomousUserAuthority {
        guard let raw = defaults.string(forKey: threadAutonomyModeKey) else {
            return .missing
        }
        switch raw {
        case ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue:
            return .manualOnly
        case ExchangeModels.ExchangeThreadAutonomyMode.draftOnly.rawValue:
            return .draftOnly
        case ExchangeModels.ExchangeThreadAutonomyMode.routineAutoRespond.rawValue:
            return .routineAutoRespond
        case ExchangeModels.ExchangeThreadAutonomyMode.fullWithinBoundaries.rawValue:
            return .fullWithinBoundaries
        default:
            return .invalid
        }
    }

    public static func evaluateProviderAutoResponse(
        _ input: ProviderInput
    ) -> ExchangeAutonomousSendDecision {
        let authoritySummary = "Thread autonomy authority: \(input.userAuthority.rawValue)"
        let deliverySummary = "Counterparty=\(input.hasCounterparty) draft=\(input.hasDraft) duplicate=\(input.isDuplicate)"
        let answerability = input.providerAnswerability
        let hasProviderMemoryAnchor = answerability?.groundedFacts.contains(where: { $0.source == .operatingMemory }) == true
        let hasProviderAnchor = input.hasSelectedOfferAnchor || input.hasSelectedPublicProfileAnchor || hasProviderMemoryAnchor

        guard input.userAuthority.allowsAutonomousSend else {
            return .init(
                outcome: .disabledByUserSetting,
                allowed: false,
                reason: "Autonomous provider sending is disabled by user mode.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "Skipped due to authority setting.",
                deliverySummary: deliverySummary
            )
        }

        if input.compareFirstDirectClaimBoundaryBlocked {
            return .init(
                outcome: .needsUserApproval,
                allowed: false,
                reason: """
                Needs provider confirmation because the draft may contain unsupported commercial, credential, or commitment claims.
                """
                .trimmingCharacters(in: .whitespacesAndNewlines),
                userAuthoritySummary: authoritySummary,
                groundingSummary: "compareFirstDirectClaimBoundaryBlocked=true",
                deliverySummary: deliverySummary
            )
        }

        if input.canonicalCompareFirstDirectGroundedSend {
            guard input.actionRaw == ExchangeSecondHalfAction.autoRespond.rawValue else {
                return .init(
                    outcome: .blocked("unsupported_action"),
                    allowed: false,
                    reason: "Second-half action is not autoRespond.",
                    userAuthoritySummary: authoritySummary,
                    groundingSummary: "canonicalCompareFirstDirect mismatch action=\(input.actionRaw ?? "nil")",
                    deliverySummary: deliverySummary
                )
            }
            guard input.hasCounterparty, input.hasDraft else {
                return .init(
                    outcome: .deliveryUnavailable,
                    allowed: false,
                    reason: "Missing routing counterparty or sendable draft.",
                    userAuthoritySummary: authoritySummary,
                    groundingSummary: "canonicalCompareFirstDirect delivery preconditions.",
                    deliverySummary: deliverySummary
                )
            }
            if input.isDuplicate {
                return .init(
                    outcome: .duplicate,
                    allowed: false,
                    reason: "An equivalent autonomous outbound is already queued.",
                    userAuthoritySummary: authoritySummary,
                    groundingSummary: "canonicalCompareFirstDirect duplicate queue.",
                    deliverySummary: deliverySummary
                )
            }
            return .init(
                outcome: .allowed,
                allowed: true,
                reason: "Canonical compare-first direct grounded body; stale structured-pillar/planner gates skipped.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "canonicalCompareFirstDirectGroundedSend=true",
                deliverySummary: deliverySummary
            )
        }

        guard hasProviderAnchor else {
            return .init(
                outcome: .needsProviderSetup,
                allowed: false,
                reason: "No anchored provider surface is available for autonomous provider send.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "offerAnchor=\(input.hasSelectedOfferAnchor) profileAnchor=\(input.hasSelectedPublicProfileAnchor) memoryAnchor=\(hasProviderMemoryAnchor)",
                deliverySummary: deliverySummary
            )
        }

        guard input.canRunAutonomously else {
            return .init(
                outcome: .needsUserApproval,
                allowed: false,
                reason: "Thread is not marked as able to run autonomous second-half actions.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "canRunAutonomously=false",
                deliverySummary: deliverySummary
            )
        }

        guard !input.needsHumanAttention else {
            return .init(
                outcome: .needsUserApproval,
                allowed: false,
                reason: "Thread requires human attention before autonomous provider send.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "needsHumanAttention=true",
                deliverySummary: deliverySummary
            )
        }

        guard input.pass3GateAllowed else {
            return .init(
                outcome: .needsUserApproval,
                allowed: false,
                reason: "Autonomous outbound agency gate (pass 3) did not allow this send.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "pass3GateAllowed=false",
                deliverySummary: deliverySummary
            )
        }

        guard !input.boundaryRequiresApproval, !input.hasVerifiedContextHold else {
            return .init(
                outcome: .needsUserApproval,
                allowed: false,
                reason: "Commitment boundary or verified-context hold requires user approval before autonomous provider send.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "boundaryRequiresApproval=\(input.boundaryRequiresApproval) verifiedContextHold=\(input.hasVerifiedContextHold)",
                deliverySummary: deliverySummary
            )
        }

        guard input.actionRaw == ExchangeSecondHalfAction.autoRespond.rawValue else {
            return .init(
                outcome: .blocked("unsupported_action"),
                allowed: false,
                reason: "Second-half action is not autoRespond.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "Action mismatch: \(input.actionRaw ?? "nil")",
                deliverySummary: deliverySummary
            )
        }

        let hasGroundedFacts = answerability?.groundedFacts.isEmpty == false
        let hasNonBlankAnswer = !(answerability?.proposedAnswer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let answerableFromPublicFacts = answerability?.answerability == .answerableFromPublicFacts
        let requiresHumanApproval = answerability?.requiresHumanApproval == true
        let groundedByAnswerability = answerability != nil &&
            answerableFromPublicFacts &&
            !requiresHumanApproval &&
            hasGroundedFacts &&
            hasNonBlankAnswer
        guard groundedByAnswerability else {
            return .init(
                outcome: .insufficientGrounding,
                allowed: false,
                reason: "Provider auto-response is not grounded enough for autonomous send.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "answerableFromPublicFacts=\(answerableFromPublicFacts) requiresHumanApproval=\(requiresHumanApproval) groundedFacts=\(hasGroundedFacts) nonBlankAnswer=\(hasNonBlankAnswer)",
                deliverySummary: deliverySummary
            )
        }

        guard input.hasCounterparty, input.hasDraft else {
            return .init(
                outcome: .deliveryUnavailable,
                allowed: false,
                reason: "Missing routing counterparty or sendable draft.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "Grounded and authorized.",
                deliverySummary: deliverySummary
            )
        }

        if input.isDuplicate {
            return .init(
                outcome: .duplicate,
                allowed: false,
                reason: "An equivalent autonomous outbound is already queued.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: "Grounded and authorized.",
                deliverySummary: deliverySummary
            )
        }

        return .init(
            outcome: .allowed,
            allowed: true,
            reason: "Authorized, grounded, and ready for delivery checks.",
            userAuthoritySummary: authoritySummary,
            groundingSummary: "Provider response grounded in known facts.",
            deliverySummary: deliverySummary
        )
    }

    public static func evaluateRequesterOutbound(
        _ input: RequesterInput
    ) -> ExchangeAutonomousSendDecision {
        let authoritySummary = "Thread autonomy authority: \(input.userAuthority.rawValue)"
        let groundingSummary = "action=\(input.actionRaw ?? "nil") supported=\(input.actionSupported) autonomous=\(input.moveIsAutonomous)"
        let deliverySummary = "counterparty=\(input.hasCounterparty) draft=\(input.hasDraft) duplicate=\(input.isDuplicate)"

        guard input.userAuthority.allowsAutonomousSend else {
            let reason: String
            if input.userAuthority.shouldSurfacePreparedDraftWhenSendBlocked {
                reason = "Draft-only mode: outbound prepared for your review; autonomous send disabled."
            } else {
                reason = "Autonomous requester outbound is disabled by user mode."
            }
            return .init(
                outcome: .disabledByUserSetting,
                allowed: false,
                reason: reason,
                userAuthoritySummary: authoritySummary,
                groundingSummary: groundingSummary,
                deliverySummary: deliverySummary
            )
        }

        guard input.isRequesterRole else {
            return .init(
                outcome: .blocked("not_requester_role"),
                allowed: false,
                reason: "Requester outbound path requires requester role.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: groundingSummary,
                deliverySummary: deliverySummary
            )
        }

        guard !input.hasEscalationReason, !input.providerAnswerabilityRequiresApproval else {
            return .init(
                outcome: .needsUserApproval,
                allowed: false,
                reason: "Escalation or provider approval boundary is active.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: groundingSummary,
                deliverySummary: deliverySummary
            )
        }

        guard input.actionSupported, input.moveIsAutonomous else {
            return .init(
                outcome: .blocked("unsupported_action"),
                allowed: false,
                reason: "Requester outbound action is unsupported or not autonomous.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: groundingSummary,
                deliverySummary: deliverySummary
            )
        }

        guard !input.boundaryRequiresApproval,
              input.boundaryAllowsAutonomousSending,
              !input.moveNeedsApproval,
              !input.moveNeedsUserInput,
              !input.hasVerifiedContextHold,
              input.pass3GateAllowed
        else {
            return .init(
                outcome: .needsUserApproval,
                allowed: false,
                reason: "Requester move still requires approval or additional user input.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: groundingSummary,
                deliverySummary: deliverySummary
            )
        }

        guard input.hasCounterparty, input.hasDraft else {
            return .init(
                outcome: .deliveryUnavailable,
                allowed: false,
                reason: "Missing routing counterparty or sendable draft.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: groundingSummary,
                deliverySummary: deliverySummary
            )
        }

        if input.isDuplicate {
            return .init(
                outcome: .duplicate,
                allowed: false,
                reason: "An equivalent requester outbound is already queued.",
                userAuthoritySummary: authoritySummary,
                groundingSummary: groundingSummary,
                deliverySummary: deliverySummary
            )
        }

        return .init(
            outcome: .allowed,
            allowed: true,
            reason: "Authorized requester autonomous outbound is ready for delivery checks.",
            userAuthoritySummary: authoritySummary,
            groundingSummary: groundingSummary,
            deliverySummary: deliverySummary
        )
    }
}
