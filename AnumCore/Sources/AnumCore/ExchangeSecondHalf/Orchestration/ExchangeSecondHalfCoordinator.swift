import Foundation

#if DEBUG
@inline(__always)
private func exchSecondHalfCoordinatorLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeSecondHalfCoordinator] \(message())")
}
#else
@inline(__always)
private func exchSecondHalfCoordinatorLog(_ message: @autoclosure () -> String) {}
#endif

/// Main entry point for the second-half subsystem.
///
/// Orchestrates engines in the right order:
/// - inspect current state
/// - assemble priors and style inputs
/// - assemble operating memory
/// - run qualification
/// - run stance update
/// - run delta update
/// - choose next move
/// - classify boundary
/// - compose draft or decision frame
/// - produce next state and a projection seed
public struct ExchangeSecondHalfCoordinator: Sendable {
    private let stateMachine: ExchangeSecondHalfStateMachine
    private let priorsBuilder: ExchangeThreadPriorsBuilder
    private let qualifier: ExchangeOpportunityQualifier
    private let structuredAnswerEngine: ExchangeStructuredAnswerEngine
    private let decisionFramer: ExchangeDecisionFramer
    private let deltaEngine: ExchangeThreadDeltaEngine
    private let stanceEngine: ExchangeThreadStanceEngine
    private let boundaryEngine: ExchangeCommitmentBoundaryEngine
    private let nextMoveEngine: ExchangeNextMoveEngine
    private let providerIntakeEngine: ExchangeProviderIntakeEngine
    private let requesterReviewEngine: ExchangeRequesterReviewEngine
    private let draftComposer: ExchangeDraftComposer
    private let requesterFlow: ExchangeSecondHalfRequesterFlow
    private let providerFlow: ExchangeSecondHalfProviderFlow

    public init(
        stateMachine: ExchangeSecondHalfStateMachine = .init(),
        priorsBuilder: ExchangeThreadPriorsBuilder = .init(),
        qualifier: ExchangeOpportunityQualifier = .init(),
        structuredAnswerEngine: ExchangeStructuredAnswerEngine = .init(),
        decisionFramer: ExchangeDecisionFramer = .init(),
        deltaEngine: ExchangeThreadDeltaEngine = .init(),
        stanceEngine: ExchangeThreadStanceEngine = .init(),
        boundaryEngine: ExchangeCommitmentBoundaryEngine = .init(),
        nextMoveEngine: ExchangeNextMoveEngine = .init(),
        providerIntakeEngine: ExchangeProviderIntakeEngine = .init(),
        requesterReviewEngine: ExchangeRequesterReviewEngine = .init(),
        draftComposer: ExchangeDraftComposer = .init(),
        requesterFlow: ExchangeSecondHalfRequesterFlow = .init(),
        providerFlow: ExchangeSecondHalfProviderFlow = .init()
    ) {
        self.stateMachine = stateMachine
        self.priorsBuilder = priorsBuilder
        self.qualifier = qualifier
        self.structuredAnswerEngine = structuredAnswerEngine
        self.decisionFramer = decisionFramer
        self.deltaEngine = deltaEngine
        self.stanceEngine = stanceEngine
        self.boundaryEngine = boundaryEngine
        self.nextMoveEngine = nextMoveEngine
        self.providerIntakeEngine = providerIntakeEngine
        self.requesterReviewEngine = requesterReviewEngine
        self.draftComposer = draftComposer
        self.requesterFlow = requesterFlow
        self.providerFlow = providerFlow
    }

    public struct ProjectionSeed: Sendable {
        public var stateTitle: String
        public var roleTitle: String
        public var postureSummary: String
        public var recommendation: String
        public var visibleAction: ExchangeSecondHalfAction?
        public var escalationReason: String?
        public var canSurfaceNow: Bool

        public init(
            stateTitle: String,
            roleTitle: String,
            postureSummary: String,
            recommendation: String,
            visibleAction: ExchangeSecondHalfAction?,
            escalationReason: String?,
            canSurfaceNow: Bool
        ) {
            self.stateTitle = stateTitle
            self.roleTitle = roleTitle
            self.postureSummary = postureSummary
            self.recommendation = recommendation
            self.visibleAction = visibleAction
            self.escalationReason = escalationReason
            self.canSurfaceNow = canSurfaceNow
        }
    }

    public struct Result: Sendable {
        public var nextState: ExchangeSecondHalfState
        public var qualification: ExchangeOpportunityQualification
        public var stance: ExchangeThreadStance
        public var delta: ExchangeThreadDelta
        public var boundary: ExchangeCommitmentBoundary
        public var plan: ExchangeSecondHalfPlan
        public var decisionFrame: ExchangeDecisionFrame?
        public var draft: ExchangeDraftComposer.Draft?
        public var projection: ProjectionSeed
        public var providerIntakeDecision: ExchangeProviderIntakeEngine.Decision?
        public var requesterPauseFrame: ExchangeRequesterPauseFrame?
        /// Optional validated secretary-style closure copy (set by `ExchangeSecondHalfFacade` after coordinator evaluate).
        public var requesterClosureComposedCopy: ExchangeRequesterClosureComposedCopy?

        public init(
            nextState: ExchangeSecondHalfState,
            qualification: ExchangeOpportunityQualification,
            stance: ExchangeThreadStance,
            delta: ExchangeThreadDelta,
            boundary: ExchangeCommitmentBoundary,
            plan: ExchangeSecondHalfPlan,
            decisionFrame: ExchangeDecisionFrame?,
            draft: ExchangeDraftComposer.Draft?,
            projection: ProjectionSeed,
            providerIntakeDecision: ExchangeProviderIntakeEngine.Decision? = nil,
            requesterPauseFrame: ExchangeRequesterPauseFrame? = nil,
            requesterClosureComposedCopy: ExchangeRequesterClosureComposedCopy? = nil
        ) {
            self.nextState = nextState
            self.qualification = qualification
            self.stance = stance
            self.delta = delta
            self.boundary = boundary
            self.plan = plan
            self.decisionFrame = decisionFrame
            self.draft = draft
            self.projection = projection
            self.providerIntakeDecision = providerIntakeDecision
            self.requesterPauseFrame = requesterPauseFrame
            self.requesterClosureComposedCopy = requesterClosureComposedCopy
        }
    }

    public func evaluate(
        context: ExchangeSecondHalfExecutionContext,
        policy: ExchangeSecondHalfPolicy = .default
    ) -> Result {
        exchSecondHalfCoordinatorLog(
            "evaluate enter thread=\(context.threadID.uuidString) " +
            "role=\(context.role.rawValue) state=\(context.currentState.rawValue)"
        )

        let flowResult: FlowEnvelope
        switch context.role {
        case .requester:
            flowResult = .requester(
                requesterFlow.run(
                    context: context,
                    policy: policy,
                    priorsBuilder: priorsBuilder,
                    qualifier: qualifier,
                    stanceEngine: stanceEngine,
                    deltaEngine: deltaEngine,
                    boundaryEngine: boundaryEngine,
                    nextMoveEngine: nextMoveEngine,
                    requesterReviewEngine: requesterReviewEngine,
                    decisionFramer: decisionFramer,
                    draftComposer: draftComposer
                )
            )

        case .provider:
            flowResult = .provider(
                providerFlow.run(
                    context: context,
                    policy: policy,
                    priorsBuilder: priorsBuilder,
                    qualifier: qualifier,
                    structuredAnswerEngine: structuredAnswerEngine,
                    stanceEngine: stanceEngine,
                    deltaEngine: deltaEngine,
                    boundaryEngine: boundaryEngine,
                    nextMoveEngine: nextMoveEngine,
                    providerIntakeEngine: providerIntakeEngine,
                    decisionFramer: decisionFramer,
                    draftComposer: draftComposer
                )
            )
        }

        let plan = flowResult.plan
        let computedNextState = stateMachine.nextState(from: context.currentState, action: plan.selectedAction)
        let nextState = resolvedNextStateAfterFlow(
            context: context,
            flowResult: flowResult,
            computedNextState: computedNextState,
            plan: plan
        )

        let decisionFrame = flowResult.decisionFrame
        let projection = ProjectionSeed(
            stateTitle: nextState.displayTitle,
            roleTitle: context.role.displayTitle,
            postureSummary: flowResult.stance.postureSummary,
            recommendation: decisionFrame?.recommendation ?? plan.rationale,
            visibleAction: plan.selectedAction,
            escalationReason: flowResult.boundary.requiresHumanApproval ? flowResult.boundary.reason : nil,
            canSurfaceNow: flowResult.shouldSurfaceNow
        )

        exchSecondHalfCoordinatorLog(
            "evaluate exit nextState=\(nextState.rawValue) " +
            "quality=\(flowResult.qualification.qualityTier.rawValue) " +
            "action=\(plan.selectedAction.rawValue) " +
            "boundary=\(flowResult.boundary.kind.rawValue)"
        )

        return Result(
            nextState: nextState,
            qualification: flowResult.qualification,
            stance: flowResult.stance,
            delta: flowResult.delta,
            boundary: flowResult.boundary,
            plan: plan,
            decisionFrame: decisionFrame,
            draft: flowResult.draft,
            projection: projection,
            providerIntakeDecision: flowResult.providerIntakeDecision,
            requesterPauseFrame: flowResult.requesterPauseFrame,
            requesterClosureComposedCopy: nil
        )
    }

    public func evaluateAsync(
        context: ExchangeSecondHalfExecutionContext,
        policy: ExchangeSecondHalfPolicy = .default
    ) async -> Result {
        exchSecondHalfCoordinatorLog(
            "evaluateAsync enter thread=\(context.threadID.uuidString) " +
            "role=\(context.role.rawValue) state=\(context.currentState.rawValue)"
        )

        let flowResult: FlowEnvelope
        switch context.role {
        case .requester:
            flowResult = .requester(
                await requesterFlow.runAsync(
                    context: context,
                    policy: policy,
                    priorsBuilder: priorsBuilder,
                    qualifier: qualifier,
                    stanceEngine: stanceEngine,
                    deltaEngine: deltaEngine,
                    boundaryEngine: boundaryEngine,
                    nextMoveEngine: nextMoveEngine,
                    requesterReviewEngine: requesterReviewEngine,
                    decisionFramer: decisionFramer,
                    draftComposer: draftComposer
                )
            )

        case .provider:
            flowResult = .provider(
                providerFlow.run(
                    context: context,
                    policy: policy,
                    priorsBuilder: priorsBuilder,
                    qualifier: qualifier,
                    structuredAnswerEngine: structuredAnswerEngine,
                    stanceEngine: stanceEngine,
                    deltaEngine: deltaEngine,
                    boundaryEngine: boundaryEngine,
                    nextMoveEngine: nextMoveEngine,
                    providerIntakeEngine: providerIntakeEngine,
                    decisionFramer: decisionFramer,
                    draftComposer: draftComposer
                )
            )
        }

        let plan = flowResult.plan
        let computedNextState = stateMachine.nextState(from: context.currentState, action: plan.selectedAction)
        let nextState = resolvedNextStateAfterFlow(
            context: context,
            flowResult: flowResult,
            computedNextState: computedNextState,
            plan: plan
        )

        let decisionFrame = flowResult.decisionFrame
        let projection = ProjectionSeed(
            stateTitle: nextState.displayTitle,
            roleTitle: context.role.displayTitle,
            postureSummary: flowResult.stance.postureSummary,
            recommendation: decisionFrame?.recommendation ?? plan.rationale,
            visibleAction: plan.selectedAction,
            escalationReason: flowResult.boundary.requiresHumanApproval ? flowResult.boundary.reason : nil,
            canSurfaceNow: flowResult.shouldSurfaceNow
        )

        exchSecondHalfCoordinatorLog(
            "evaluateAsync exit nextState=\(nextState.rawValue) " +
            "quality=\(flowResult.qualification.qualityTier.rawValue) " +
            "action=\(plan.selectedAction.rawValue) " +
            "boundary=\(flowResult.boundary.kind.rawValue)"
        )

        return Result(
            nextState: nextState,
            qualification: flowResult.qualification,
            stance: flowResult.stance,
            delta: flowResult.delta,
            boundary: flowResult.boundary,
            plan: plan,
            decisionFrame: decisionFrame,
            draft: flowResult.draft,
            projection: projection,
            providerIntakeDecision: flowResult.providerIntakeDecision,
            requesterPauseFrame: flowResult.requesterPauseFrame,
            requesterClosureComposedCopy: nil
        )
    }

    private enum FlowEnvelope {
        case requester(ExchangeSecondHalfRequesterFlow.Result)
        case provider(ExchangeSecondHalfProviderFlow.Result)

        var qualification: ExchangeOpportunityQualification {
            switch self {
            case .requester(let result): return result.qualification
            case .provider(let result): return result.qualification
            }
        }

        var shouldSurfaceNow: Bool {
            switch self {
            case .requester(let result): return result.shouldSurfaceNow
            case .provider(let result): return result.shouldSurfaceNow
            }
        }

        var stance: ExchangeThreadStance {
            switch self {
            case .requester(let result): return result.stance
            case .provider(let result): return result.stance
            }
        }

        var delta: ExchangeThreadDelta {
            switch self {
            case .requester(let result): return result.delta
            case .provider(let result): return result.delta
            }
        }

        var boundary: ExchangeCommitmentBoundary {
            switch self {
            case .requester(let result): return result.boundary
            case .provider(let result): return result.boundary
            }
        }

        var plan: ExchangeSecondHalfPlan {
            switch self {
            case .requester(let result): return result.plan
            case .provider(let result): return result.plan
            }
        }

        var decisionFrame: ExchangeDecisionFrame? {
            switch self {
            case .requester(let result): return result.decisionFrame
            case .provider(let result): return result.decisionFrame
            }
        }

        var draft: ExchangeDraftComposer.Draft? {
            switch self {
            case .requester(let result): return result.draft
            case .provider(let result): return result.draft
            }
        }

        var providerIntakeDecision: ExchangeProviderIntakeEngine.Decision? {
            switch self {
            case .requester:
                return nil
            case .provider(let result):
                return result.providerIntakeDecision
            }
        }

        var requesterPauseFrame: ExchangeRequesterPauseFrame? {
            switch self {
            case .requester(let result):
                return result.pauseFrame
            case .provider:
                return nil
            }
        }
    }

    private func resolvedNextStateAfterFlow(
        context: ExchangeSecondHalfExecutionContext,
        flowResult: FlowEnvelope,
        computedNextState: ExchangeSecondHalfState?,
        plan: ExchangeSecondHalfPlan
    ) -> ExchangeSecondHalfState {
        if let computedNextState {
            return computedNextState
        }
        #if DEBUG
        exchSecondHalfCoordinatorLog(
            "fallbackToCurrentState currentState=\(context.currentState.rawValue) " +
                "action=\(plan.selectedAction.rawValue) role=\(context.role.rawValue) " +
                "boundary=\(flowResult.boundary.kind.rawValue) " +
                "boundaryRequiresApproval=\(flowResult.boundary.requiresHumanApproval) " +
                "fallbackState=\(context.currentState.rawValue)"
        )
        #endif
        if let cleared = clearedStaleAwaitingCommitmentApprovalForSafeProviderCompareFirstAutoRespond(
            context: context,
            flowResult: flowResult,
            plan: plan
        ) {
            return cleared
        }
        return context.currentState
    }

    /// When persisted snapshot says `awaitingCommitmentApproval` but the state machine disallows `autoRespond`
    /// from that state, evaluation used to fall back and strand the thread. Clears to `requesterReview`
    /// only when compare-first bypass + safe outbound gates align with provider intake (narrow path).
    private func clearedStaleAwaitingCommitmentApprovalForSafeProviderCompareFirstAutoRespond(
        context: ExchangeSecondHalfExecutionContext,
        flowResult: FlowEnvelope,
        plan: ExchangeSecondHalfPlan
    ) -> ExchangeSecondHalfState? {
        guard context.role == .provider else {
            logSecondHalfStateTransitionBlocked(context: context, plan: plan, reason: "role_not_provider")
            return nil
        }
        guard context.currentState == .awaitingCommitmentApproval else {
            return nil
        }
        guard plan.selectedAction == .autoRespond else {
            logSecondHalfStateTransitionBlocked(context: context, plan: plan, reason: "action_not_autoRespond")
            return nil
        }
        let boundary = flowResult.boundary
        guard boundary.kind == .safe, !boundary.requiresHumanApproval else {
            logSecondHalfStateTransitionBlocked(
                context: context,
                plan: plan,
                reason: "boundary_not_safe_or_requires_approval",
                boundaryKind: boundary.kind.rawValue,
                boundaryRequiresApproval: boundary.requiresHumanApproval
            )
            return nil
        }
        guard !context.isCustomPricing,
              !context.includesScheduleCommitment,
              !context.includesLegalCommercialCommitment,
              !context.includesSensitiveDisclosure,
              !context.isPolicyException else {
            logSecondHalfStateTransitionBlocked(
                context: context,
                plan: plan,
                reason: "snapshot_commitment_or_policy_exception_hint"
            )
            return nil
        }
        guard let pkt = context.providerCompareFirstStructuredPillarBypassPacket, pkt.isEligible else {
            logSecondHalfStateTransitionBlocked(
                context: context,
                plan: plan,
                reason: "compare_first_bypass_missing_or_ineligible"
            )
            return nil
        }
        if flowResult.providerIntakeDecision != .answerAutomatically {
            logSecondHalfStateTransitionBlocked(
                context: context,
                plan: plan,
                reason: "intake_not_answer_automatically"
            )
            return nil
        }
        let body = flowResult.draft.map {
            $0.body.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        guard !body.isEmpty else {
            logSecondHalfStateTransitionBlocked(context: context, plan: plan, reason: "no_sendable_draft_body")
            return nil
        }
        let hasDirectGrounded = pkt.hasCompareGroundedDraft
        #if DEBUG
        Swift.print(
            "[SecondHalfStateTransition] thread=\(context.threadID.uuidString) " +
                "role=provider " +
                "from=awaitingCommitmentApproval " +
                "action=autoRespond " +
                "boundaryKind=\(boundary.kind.rawValue) " +
                "boundaryRequiresApproval=\(boundary.requiresHumanApproval) " +
                "compareFirstBypassEligible=\(pkt.isEligible) " +
                "hasDirectGroundedBody=\(hasDirectGrounded) " +
                "nextState=\(ExchangeSecondHalfState.requesterReview.rawValue) " +
                "reason=cleared_stale_commitment_approval_for_safe_autorespond"
        )
        #endif
        return .requesterReview
    }

    private func logSecondHalfStateTransitionBlocked(
        context: ExchangeSecondHalfExecutionContext,
        plan: ExchangeSecondHalfPlan,
        reason: String,
        boundaryKind: String? = nil,
        boundaryRequiresApproval: Bool? = nil
    ) {
        #if DEBUG
        guard context.currentState == .awaitingCommitmentApproval,
              context.role == .provider,
              plan.selectedAction == .autoRespond else {
            return
        }
        let bk = boundaryKind ?? "n/a"
        let bra = boundaryRequiresApproval.map { String($0) } ?? "n/a"
        Swift.print(
            "[SecondHalfStateTransitionBlocked] thread=\(context.threadID.uuidString) " +
                "from=awaitingCommitmentApproval action=autoRespond reason=\(reason) " +
                "boundaryKind=\(bk) boundaryRequiresApproval=\(bra) " +
                "requiresHumanAttention=n/a pendingApproval=n/a"
        )
        #endif
    }
}
