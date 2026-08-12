import Foundation

#if DEBUG
@inline(__always)
private func exchAgencyPlannerLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeAgencyPlanner] \(message())")
}
#else
@inline(__always)
private func exchAgencyPlannerLog(_ message: @autoclosure () -> String) {}
#endif

/// Deterministic planner for Pass 3 — emits suggestions only (no side effects).
public enum ExchangeAgencyPlanner {

    /// Public API: uses only context, optional situation, and partial/complete assessment.
    public static func suggest(
        context: ExchangeAgencyContext,
        situation: ExchangeThreadSituation?,
        assessment: ExchangeAgencyAssessment?
    ) -> [ExchangeAgencySuggestion] {
        synthesize(
            context: context,
            situation: situation,
            assessment: assessment,
            threadSignals: nil
        )
    }

    /// Internal: used when `ExchangeThread` is available (second-half evaluation path).
    internal static func suggest(
        context: ExchangeAgencyContext,
        situation: ExchangeThreadSituation?,
        assessment: ExchangeAgencyAssessment?,
        thread: ExchangeThread,
        turns: [ExchangeTurn]
    ) -> [ExchangeAgencySuggestion] {
        let signals = AgencyThreadSignals(thread: thread, turns: turns)
        return synthesize(
            context: context,
            situation: situation,
            assessment: assessment,
            threadSignals: signals
        )
    }

    // MARK: - Core

    private static func synthesize(
        context: ExchangeAgencyContext,
        situation: ExchangeThreadSituation?,
        assessment: ExchangeAgencyAssessment?,
        threadSignals: AgencyThreadSignals?
    ) -> [ExchangeAgencySuggestion] {
        let inputs = deriveDecisionInputs(
            context: context,
            situation: situation,
            assessment: assessment,
            threadSignals: threadSignals
        )
        exchAgencyPlannerLog(
            "synthesize role=\(context.side.rawValue) pendingApproval=\(inputs.pendingApproval) awaitingOther=\(inputs.awaitingOther) hasFailure=\(inputs.hasFailure)"
        )
        let decision = buildAgencyDecisionFromInputs(
            context: context,
            assessment: assessment,
            inputs: inputs
        )
        let out = suggestionsFromDecision(
            context: context,
            assessment: assessment,
            inputs: inputs,
            decision: decision
        )
        return capAndDedupe(out, max: 5)
    }

    private static func isLikelyNonBindingRequesterContext(_ context: ExchangeAgencyContext) -> Bool {
        let summary = [
            context.userIntent,
            context.situation?.deliveryLine ?? "",
            context.situation?.boundaryLine ?? "",
            context.situation?.autonomyHoldLine ?? "",
            context.situation?.autonomyHoldReason ?? "",
            context.boundaryHints.joined(separator: " ")
        ]
            .joined(separator: " ")
            .lowercased()

        let hasHardApprovalSignal =
            summary.contains("approval required")
            || summary.contains("pending approval")
            || summary.contains("sensitive disclosure")
            || summary.contains("schedule commitment")
            || summary.contains("custom pricing")
            || summary.contains("legal")
            || summary.contains("commercial commitment")
            || summary.contains("policy exception")
        if hasHardApprovalSignal {
            return false
        }

        let nonBindingSignals = [
            "price",
            "pricing",
            "availability",
            "available",
            "details",
            "detail",
            "clarify",
            "question",
            "quote"
        ]
        return nonBindingSignals.contains(where: { summary.contains($0) })
    }

    // MARK: - Decision + explanation synthesis

    private struct AgencyDecisionInputs: Sendable {
        var hasFailure: Bool
        var pendingApproval: Bool
        var awaitingOther: Bool
        var requesterMissingDecisionFacts: [String]
        var requesterRecommendedQuestions: [String]
        var providerAnswerability: ExchangeProviderAnswerability?
    }

    private static func deriveDecisionInputs(
        context: ExchangeAgencyContext,
        situation: ExchangeThreadSituation?,
        assessment: ExchangeAgencyAssessment?,
        threadSignals: AgencyThreadSignals?
    ) -> AgencyDecisionInputs {
        let hasFailure = threadSignals?.hasLegibleFailure == true
            || (situation?.deliveryLine.lowercased().contains("fail") ?? false)

        let explicitApprovalGate =
            situation?.hasPendingApproval == true
                || threadSignals?.hasPendingApprovalGate == true
        let inferredHumanDecision = threadSignals?.requiresHumanDecision == true
        let boundaryLooksSafe = {
            let boundaryLineHasSafe = situation?.boundaryLine.lowercased().contains("safe") == true
            let hintHasSafe = context.boundaryHints.contains {
                $0.lowercased().contains("safe")
            }
            return boundaryLineHasSafe || hintHasSafe
        }()
        let requesterSafeNoExplicitApproval =
            context.side == .requester
                && boundaryLooksSafe
                && !explicitApprovalGate
        let requesterLikelyNonBinding = context.side == .requester && isLikelyNonBindingRequesterContext(context)
        let pendingApproval: Bool = {
            if requesterSafeNoExplicitApproval {
                return false
            }
            if context.side == .requester, requesterLikelyNonBinding, !explicitApprovalGate {
                return false
            }
            return explicitApprovalGate || inferredHumanDecision
        }()

        let awaitingOther =
            threadSignals?.awaitingCounterparty == true
                || (situation.map { isAwaitingResponseLine($0.deliveryLine) } ?? false)

        let needs = assessment?.requesterDecisionNeeds
        return AgencyDecisionInputs(
            hasFailure: hasFailure,
            pendingApproval: pendingApproval,
            awaitingOther: awaitingOther,
            requesterMissingDecisionFacts: needs?.missingDecisionFacts ?? [],
            requesterRecommendedQuestions: needs?.recommendedQuestions ?? [],
            providerAnswerability: assessment?.providerAnswerability
        )
    }

    private static func buildAgencyDecisionFromInputs(
        context: ExchangeAgencyContext,
        assessment: ExchangeAgencyAssessment?,
        inputs: AgencyDecisionInputs
    ) -> ExchangeAgencyDecision {
        let providerApprovalBlocked = inputs.providerAnswerability?.requiresHumanApproval == true
        let providerNeedsUserInput: Bool = {
            guard context.side == .provider else { return false }
            guard let pa = inputs.providerAnswerability else { return !inputs.hasFailure }
            switch pa.answerability {
            case .notAnswerable, .requiresProviderApproval:
                return true
            case .partiallyAnswerableNeedsClarification, .answerableFromPublicFacts:
                return false
            }
        }()
        let requesterCounterpartyClarificationNeeded =
            !inputs.requesterMissingDecisionFacts.isEmpty || !inputs.requesterRecommendedQuestions.isEmpty
        let providerCounterpartyClarificationNeeded =
            inputs.providerAnswerability?.answerability == .partiallyAnswerableNeedsClarification
        let needsCounterparty =
            context.side == .requester
                ? requesterCounterpartyClarificationNeeded
                : providerCounterpartyClarificationNeeded

        let canLowRiskPermit: Bool = {
            if inputs.hasFailure || inputs.pendingApproval || inputs.awaitingOther {
                return false
            }
            switch context.side {
            case .requester:
                return context.canContactDirectly
            case .provider:
                guard let pa = inputs.providerAnswerability else { return false }
                return pa.answerability == .answerableFromPublicFacts && !pa.requiresHumanApproval
            }
        }()

        let blockReasons: [String] = {
            if inputs.hasFailure { return ["recover_failure"] }
            if providerApprovalBlocked || inputs.pendingApproval { return ["approval_required"] }
            if providerNeedsUserInput { return ["user_input_required"] }
            if inputs.awaitingOther { return ["wait_for_counterparty"] }
            if needsCounterparty && !canLowRiskPermit { return ["counterparty_clarification_required"] }
            if !canLowRiskPermit { return ["no_safe_autonomous_permit"] }
            return []
        }()

        let disposition: ExchangeAgencyAutonomyDisposition = {
            if inputs.hasFailure { return .blocked }
            if providerApprovalBlocked || inputs.pendingApproval { return .holdForApproval }
            if providerNeedsUserInput { return .holdForUserInput }
            if inputs.awaitingOther { return .wait }
            if needsCounterparty && !canLowRiskPermit { return .holdForCounterparty }
            if canLowRiskPermit { return .allowAutonomousOutbound }
            return .holdForUserInput
        }()

        let recommendedAction: ExchangeSecondHalfAction? = {
            switch context.side {
            case .requester:
                if inputs.hasFailure { return .markBlocked }
                if inputs.pendingApproval { return .escalateForApproval }
                if inputs.awaitingOther { return .pause }
                if requesterCounterpartyClarificationNeeded { return .askClarification }
                if canLowRiskPermit { return .recommendNextMove }
                return .requestUserInput
            case .provider:
                if inputs.hasFailure { return .markBlocked }
                if providerApprovalBlocked || inputs.pendingApproval { return .escalateForApproval }
                if inputs.awaitingOther { return .pause }
                if providerNeedsUserInput { return .requestUserInput }
                if providerCounterpartyClarificationNeeded { return .askClarification }
                if canLowRiskPermit { return .autoRespond }
                return nil
            }
        }()

        let permitReasons: [String] = {
            guard canLowRiskPermit else { return [] }
            switch context.side {
            case .requester:
                if requesterCounterpartyClarificationNeeded {
                    return ["askCounterpartyClarification", "draftRequesterOutreach"]
                }
                return ["sendIfSafe"]
            case .provider:
                return ["draftProviderReply"]
            }
        }()

        return ExchangeAgencyDecision(
            recommendedAction: recommendedAction,
            autonomyDisposition: disposition,
            requiresUserApproval: providerApprovalBlocked || inputs.pendingApproval,
            requiresUserInput: providerNeedsUserInput || disposition == .holdForUserInput,
            blockReasons: blockReasons,
            permitReasons: permitReasons
        )
    }

    private static func suggestionsFromDecision(
        context: ExchangeAgencyContext,
        assessment: ExchangeAgencyAssessment?,
        inputs: AgencyDecisionInputs,
        decision: ExchangeAgencyDecision
    ) -> [ExchangeAgencySuggestion] {
        var out: [ExchangeAgencySuggestion] = []

        if inputs.hasFailure {
            out.append(
                ExchangeAgencySuggestion(
                    kind: .recoverFailure,
                    title: "Recover from delivery or sync failure",
                    summary: "Review the latest failure context and choose a safe retry or alternate path.",
                    requiresUserApproval: true,
                    canRunAutonomously: false,
                    riskLevel: "high",
                    reasons: ["Thread or transport shows a legible failure signal."]
                )
            )
        }

        if decision.requiresUserApproval {
            out.append(
                ExchangeAgencySuggestion(
                    kind: .reviewApproval,
                    title: "Review pending approval",
                    summary: "A prepared move needs human judgment before anything external is sent.",
                    requiresUserApproval: true,
                    canRunAutonomously: false,
                    riskLevel: "medium",
                    reasons: ["Approval gate is active on this snapshot."]
                )
            )
        }

        if inputs.awaitingOther, !inputs.hasFailure {
            out.append(
                ExchangeAgencySuggestion(
                    kind: .wait,
                    title: "Wait for the other side",
                    summary: "Last activity suggests a reply or external step is still outstanding.",
                    requiresUserApproval: false,
                    canRunAutonomously: false,
                    riskLevel: "low",
                    reasons: ["Avoid duplicate outbound while awaiting response."]
                )
            )
        }

        switch context.side {
        case .requester:
            if !inputs.requesterMissingDecisionFacts.isEmpty {
                out.append(
                    ExchangeAgencySuggestion(
                        kind: .askCounterpartyClarification,
                        title: "Ask the counterparty for missing details",
                        summary: "Surface-specific gaps remain before you can decide confidently.",
                        requiresUserApproval: false,
                        canRunAutonomously: decision.autonomyDisposition == .allowAutonomousOutbound && context.canContactDirectly,
                        riskLevel: "low",
                        reasons: Array(inputs.requesterMissingDecisionFacts.prefix(4))
                    )
                )
            }

            if !inputs.requesterRecommendedQuestions.isEmpty {
                out.append(
                    ExchangeAgencySuggestion(
                        kind: .draftRequesterOutreach,
                        title: "Draft outreach with suggested questions",
                        summary: "Use the suggested questions as a short checklist before you send.",
                        requiresUserApproval: decision.requiresUserApproval,
                        canRunAutonomously: decision.autonomyDisposition == .allowAutonomousOutbound && context.canContactDirectly,
                        riskLevel: "low",
                        reasons: Array(inputs.requesterRecommendedQuestions.prefix(4))
                    )
                )
            }

            if decision.autonomyDisposition == .allowAutonomousOutbound && context.canContactDirectly {
                out.append(
                    ExchangeAgencySuggestion(
                        kind: .sendIfSafe,
                        title: "First message may qualify for automatic send",
                        summary:
                            "Only when every safety check already passed; this is not permission to send on its own.",
                        requiresUserApproval: false,
                        canRunAutonomously: true,
                        riskLevel: "low",
                        reasons: [
                            "Direct contact may be allowed on this thread.",
                            "Sending still goes through the usual approval and eligibility checks."
                        ]
                    )
                )
            }

        case .provider:
            guard let pa = assessment?.providerAnswerability else {
                if !inputs.hasFailure {
                    out.append(
                        ExchangeAgencySuggestion(
                            kind: .askUserClarification,
                            title: "Gather context for this inquiry",
                            summary: "Published profile and offer details did not fully cover the inbound question.",
                            requiresUserApproval: false,
                            canRunAutonomously: false,
                            riskLevel: "medium",
                            reasons: ["Provider answerability overlay missing or incomplete."]
                        )
                    )
                }
                return out
            }

            switch pa.answerability {
            case .answerableFromPublicFacts:
                if !pa.requiresHumanApproval {
                    out.append(
                        ExchangeAgencySuggestion(
                            kind: .draftProviderReply,
                            title: "Draft reply from published facts",
                            summary: "Structured retrieval covered the inquiry without seller-only commitments.",
                            requiresUserApproval: false,
                            canRunAutonomously: decision.autonomyDisposition == .allowAutonomousOutbound,
                            riskLevel: "low",
                            reasons: Array(pa.knownFactsUsed.prefix(4))
                        )
                    )
                } else {
                    out.append(
                        ExchangeAgencySuggestion(
                            kind: .reviewApproval,
                            title: "Seller review before sending",
                            summary: pa.boundaryReason,
                            requiresUserApproval: true,
                            canRunAutonomously: false,
                            riskLevel: "high",
                            reasons: [pa.boundaryReason]
                        )
                    )
                }

            case .partiallyAnswerableNeedsClarification:
                out.append(
                    ExchangeAgencySuggestion(
                        kind: .askCounterpartyClarification,
                        title: "Ask a targeted clarifying question",
                        summary: "Share what you can from published details, then ask for the smallest missing piece.",
                        requiresUserApproval: false,
                        canRunAutonomously: false,
                        riskLevel: "medium",
                        reasons: Array(pa.missingFacts.prefix(4))
                    )
                )

            case .requiresProviderApproval:
                out.append(
                    ExchangeAgencySuggestion(
                        kind: .reviewApproval,
                        title: "Route to seller review",
                        summary: pa.boundaryReason,
                        requiresUserApproval: true,
                        canRunAutonomously: false,
                        riskLevel: "high",
                        reasons: [pa.boundaryReason]
                    )
                )

            case .notAnswerable:
                out.append(
                    ExchangeAgencySuggestion(
                        kind: .askUserClarification,
                        title: "Escalate or collect facts internally",
                        summary: "There is not enough published detail to answer this inquiry safely.",
                        requiresUserApproval: true,
                        canRunAutonomously: false,
                        riskLevel: "high",
                        reasons: Array(pa.missingFacts.prefix(3))
                    )
                )
            }
        }

        return out
    }

    // MARK: - Helpers

    private static func isAwaitingResponseLine(_ line: String) -> Bool {
        let l = line.lowercased()
        return l.contains("await") || l.contains("waiting") || l.contains("response expected")
    }

    private static func capAndDedupe(_ rows: [ExchangeAgencySuggestion], max: Int) -> [ExchangeAgencySuggestion] {
        var seen = Set<String>()
        var out: [ExchangeAgencySuggestion] = []

        for s in rows {
            let key = "\(s.kind.rawValue)|\(s.title)"
            guard seen.insert(key).inserted else { continue }

            out.append(s)
            if out.count >= max {
                break
            }
        }

        return out
    }
}

// MARK: - Thread signals

private struct AgencyThreadSignals: Sendable {
    var hasLegibleFailure: Bool
    var requiresHumanDecision: Bool
    var hasPendingApprovalGate: Bool
    var awaitingCounterparty: Bool

    init(thread: ExchangeThread, turns: [ExchangeTurn]) {
        self.requiresHumanDecision = thread.requiresHumanDecision
        if case .awaitingApproval = thread.state {
            self.hasPendingApprovalGate = true
        } else {
            self.hasPendingApprovalGate = thread.approval?.status == .pending
        }
        self.hasLegibleFailure = thread.latestFailure != nil

        switch thread.state {
        case .awaitingResponse:
            self.awaitingCounterparty = true

        case .blockedByDeliveryFailure, .blockedBySystemFailure:
            self.awaitingCounterparty = false

        default:
            let lastSend = turns.reversed().first { $0.kind == .sendConfirmed }
            let gotReplyAfter = lastSend.map { send in
                turns.contains { $0.createdAt > send.createdAt && $0.kind == .replyReceived }
            } ?? false
            self.awaitingCounterparty = lastSend != nil && !gotReplyAfter
        }
    }
}

// MARK: - Autonomous outbound gate (Pass 3)

/// Result for `ExchangeAgencyPlanner.evaluateAutonomousOutboundGate(display:)`.
///
/// Planner output never widens send paths; this gate may only block automatic queue paths.
public struct ExchangeAgencyAutonomousOutboundGateResult: Sendable {
    /// When Pass 3 assessment is absent, callers keep existing autonomy checks only.
    public var allowed: Bool
    /// Human-readable veto line for logs / debugging — not for user-facing banners by default.
    public var vetoReason: String?
    /// Mirrors `agency_suggestion_kind` metadata (permit kind when allowed; first blocker when rejected).
    public var agencySuggestionKind: String?
    /// Stable opaque reason slug for instrumentation (`agency_block_reason`).
    public var agencyBlockReason: String?
    /// Count of surfaced public-fact strings on the snapshot (`used_public_facts_count`).
    public var usedPublicFactsCount: Int

    public init(
        allowed: Bool,
        vetoReason: String?,
        agencySuggestionKind: String?,
        agencyBlockReason: String?,
        usedPublicFactsCount: Int
    ) {
        self.allowed = allowed
        self.vetoReason = vetoReason
        self.agencySuggestionKind = agencySuggestionKind
        self.agencyBlockReason = agencyBlockReason
        self.usedPublicFactsCount = usedPublicFactsCount
    }
}

public extension ExchangeAgencyPlanner {
    private enum Pass3AutonomousOutboundGateVariant {
        case provider
        case requester
    }

    /// Shared Pass-3 autonomous outbound evaluation; wrappers preserve legacy strings and logging.
    private static func evaluatePass3AutonomousOutboundGate(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        variant: Pass3AutonomousOutboundGateVariant
    ) -> ExchangeAgencyAutonomousOutboundGateResult {
        guard let assessment = display.agencyAssessment else {
            return ExchangeAgencyAutonomousOutboundGateResult(
                allowed: false,
                vetoReason: "Pass 3: missing verified agency assessment context.",
                agencySuggestionKind: nil,
                agencyBlockReason: "agency_missing_verified_context",
                usedPublicFactsCount: 0
            )
        }

        let factsCount = assessment.groundedFactLines.count
        let decision = assessment.agencyDecision

        switch variant {
        case .requester:
            exchAgencyPlannerLog(
                "requesterGate inspect role=\(display.status.role) boundary=\(display.boundary.kind) disposition=\(decision.autonomyDisposition.rawValue) requiresApproval=\(decision.requiresUserApproval) requiresInput=\(decision.requiresUserInput)"
            )
        case .provider:
            break
        }

        if decision.autonomyDisposition == .allowAutonomousOutbound,
           !decision.requiresUserApproval,
           !decision.requiresUserInput {
            switch variant {
            case .requester:
                exchAgencyPlannerLog("requesterGate allowed reason=decision_permit")
            case .provider:
                break
            }
            return ExchangeAgencyAutonomousOutboundGateResult(
                allowed: true,
                vetoReason: nil,
                agencySuggestionKind: decision.permitReasons.first,
                agencyBlockReason: nil,
                usedPublicFactsCount: factsCount
            )
        }

        let primaryReason: String
        let vetoPrefix: String
        let agencyBlockPrefix: String
        switch variant {
        case .provider:
            primaryReason = decision.blockReasons.first ?? "agency_no_safe_permit_decision"
            vetoPrefix = "Pass 3: autonomy decision withholds automatic outbound"
            agencyBlockPrefix = "agency_decision_"
        case .requester:
            primaryReason = decision.blockReasons.first ?? "agency_requester_no_safe_permit"
            vetoPrefix = "Pass 3 requester gate: autonomy decision withholds automatic outbound"
            agencyBlockPrefix = "agency_requester_decision_"
            exchAgencyPlannerLog("requesterGate blocked reason=\(primaryReason)")
        }

        return ExchangeAgencyAutonomousOutboundGateResult(
            allowed: false,
            vetoReason: "\(vetoPrefix) (\(primaryReason)).",
            agencySuggestionKind: decision.recommendedAction?.rawValue,
            agencyBlockReason: "\(agencyBlockPrefix)\(primaryReason)",
            usedPublicFactsCount: factsCount
        )
    }

    static func buildAgencyDecision(
        context: ExchangeAgencyContext,
        assessment: ExchangeAgencyAssessment
    ) -> ExchangeAgencyDecision {
        let inputs = deriveDecisionInputs(
            context: context,
            situation: context.situation,
            assessment: assessment,
            threadSignals: nil
        )
        return buildAgencyDecisionFromInputs(
            context: context,
            assessment: assessment,
            inputs: inputs
        )
    }


    /// When an assessment is present, require an explicit low-risk, autonomous-allowed planner row.
    ///
    /// - Note: Boundary / eligibility guards in `ExchangeFacade` still apply; `sendIfSafe` suggestions are necessary but never sufficient alone.
    static func evaluateAutonomousOutboundGate(
        display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> ExchangeAgencyAutonomousOutboundGateResult {
        evaluatePass3AutonomousOutboundGate(display: display, variant: .provider)
    }

    /// Requester-side autonomous outbound gate: allows low‑risk counterparty clarification / outreach
    /// permits that the provider-oriented `evaluateAutonomousOutboundGate` intentionally vetoes.
    ///
    /// Hard stops still block: wait, recovery, explicit review approval, or missing local user judgment.
    static func evaluateRequesterAutonomousOutboundGate(
        display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> ExchangeAgencyAutonomousOutboundGateResult {
        evaluatePass3AutonomousOutboundGate(display: display, variant: .requester)
    }

    /// User-safe copy when `evaluateAutonomousOutboundGate` returns `allowed == false`. Does not surface raw slugs, enums, or JSON.
    static func userFacingAutonomyHold(
        from gate: ExchangeAgencyAutonomousOutboundGateResult
    ) -> (line: String, reason: String?) {
        guard gate.allowed == false else {
            return ("", nil)
        }

        if gate.agencyBlockReason == "agency_missing_verified_context" {
            return (
                "The secretary paused until it has enough verified context to move safely.",
                "Reason: missing verified context."
            )
        }

        if gate.agencyBlockReason == "agency_no_safe_permit_suggestion" {
            return (
                "The secretary paused because there is not enough published detail to move safely.",
                "Reason: not enough published detail."
            )
        }

        if gate.agencyBlockReason == "agency_provider_requires_human_approval" {
            return (
                "The secretary paused because the next move may need seller review.",
                "Reason: seller review."
            )
        }

        if let core = autonomyHoldDecisionCore(gate.agencyBlockReason) {
            switch core {
            case "approval_required":
                return (
                    "The secretary paused because the next move may need your approval.",
                    "Reason: approval required."
                )
            case "user_input_required":
                return (
                    "The secretary paused because something still needs your input.",
                    "Reason: your input needed."
                )
            case "wait_for_counterparty":
                return (
                    "The secretary is waiting for the other side before moving automatically.",
                    "Reason: waiting on the other party."
                )
            case "recover_failure":
                return (
                    "The secretary paused because this thread needs attention after a delivery or sync issue.",
                    "Reason: recovery needed."
                )
            case "counterparty_clarification_required":
                return (
                    "The secretary paused because the other side may need to clarify before sending.",
                    "Reason: waiting on clarification."
                )
            case "no_safe_autonomous_permit",
                 "agency_no_safe_permit_decision",
                 "agency_requester_no_safe_permit":
                return (
                    "The secretary paused because automatic sending is not available for this step.",
                    "Reason: needs a reviewed path."
                )
            default:
                break
            }
        }

        let plannerPrefix = "agency_planner_kind_"
        if let slug = gate.agencyBlockReason, slug.hasPrefix(plannerPrefix) {
            let raw = String(slug.dropFirst(plannerPrefix.count))
            switch raw {
            case "wait":
                return (
                    "The secretary is waiting for the right moment before sending automatically.",
                    "Reason: waiting."
                )
            case "recoverFailure":
                return (
                    "The secretary paused because this thread needs recovery before sending.",
                    "Reason: recovery needed."
                )
            case "reviewApproval":
                return (
                    "The secretary paused because the next move may need your approval.",
                    "Reason: approval required."
                )
            case "askUserClarification":
                return (
                    "The secretary paused because something still needs your input.",
                    "Reason: your input needed."
                )
            case "askCounterpartyClarification":
                return (
                    "The secretary paused because the other side may need to clarify before sending.",
                    "Reason: waiting on clarification."
                )
            case "draftRequesterOutreach":
                return (
                    "The secretary paused because the next outreach needs your review first.",
                    "Reason: tailored offer or scheduling question."
                )
            default:
                break
            }
        }

        return (
            "The secretary paused because this step still needs your judgment.",
            nil
        )
    }

    /// Strips `agency_decision_` / `agency_requester_decision_` prefixes from gate slugs for stable branching.
    private static func autonomyHoldDecisionCore(_ reason: String?) -> String? {
        guard let reason else { return nil }
        let decisionPrefix = "agency_decision_"
        let requesterPrefix = "agency_requester_decision_"
        if reason.hasPrefix(decisionPrefix) {
            return String(reason.dropFirst(decisionPrefix.count))
        }
        if reason.hasPrefix(requesterPrefix) {
            return String(reason.dropFirst(requesterPrefix.count))
        }
        return nil
    }
}
