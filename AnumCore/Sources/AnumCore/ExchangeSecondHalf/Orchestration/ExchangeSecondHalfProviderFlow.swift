import Foundation

#if DEBUG
@inline(__always)
private func exchSecondHalfProviderLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeSecondHalfProviderFlow] \(message())")
}
#else
@inline(__always)
private func exchSecondHalfProviderLog(_ message: @autoclosure () -> String) {}
#endif

/// Explicit provider-side orchestration.
///
/// Provider-side reception is intentionally more operational than requester-side
/// review. The provider secretary acts like a front desk:
/// - answer routine grounded inquiries from structured/known facts
/// - escalate custom/unclear/commitment-bearing requests
/// - surface strong leads
/// - quietly downgrade weak leads
///
/// This flow still does not send anything. It only chooses the second-half
/// action and produces a draft/decision frame for the caller to persist.
public struct ExchangeSecondHalfProviderFlow: Sendable {
    public init() {}

    public struct Result: Sendable {
        public var priors: ExchangeThreadPriors
        public var qualification: ExchangeOpportunityQualification
        public var shouldSurfaceNow: Bool
        public var stance: ExchangeThreadStance
        public var delta: ExchangeThreadDelta
        public var boundary: ExchangeCommitmentBoundary
        public var plan: ExchangeSecondHalfPlan
        public var decisionFrame: ExchangeDecisionFrame?
        public var draft: ExchangeDraftComposer.Draft?
        public var structuredAnswer: ExchangeStructuredAnswerEngine.Answer?
        /// Intake engine decision before mapping to `plan` (DEBUG / drift diagnostics).
        public var providerIntakeDecision: ExchangeProviderIntakeEngine.Decision?

        public init(
            priors: ExchangeThreadPriors,
            qualification: ExchangeOpportunityQualification,
            shouldSurfaceNow: Bool,
            stance: ExchangeThreadStance,
            delta: ExchangeThreadDelta,
            boundary: ExchangeCommitmentBoundary,
            plan: ExchangeSecondHalfPlan,
            decisionFrame: ExchangeDecisionFrame?,
            draft: ExchangeDraftComposer.Draft?,
            structuredAnswer: ExchangeStructuredAnswerEngine.Answer?,
            providerIntakeDecision: ExchangeProviderIntakeEngine.Decision? = nil
        ) {
            self.priors = priors
            self.qualification = qualification
            self.shouldSurfaceNow = shouldSurfaceNow
            self.stance = stance
            self.delta = delta
            self.boundary = boundary
            self.plan = plan
            self.decisionFrame = decisionFrame
            self.draft = draft
            self.structuredAnswer = structuredAnswer
            self.providerIntakeDecision = providerIntakeDecision
        }
    }

    public func run(
        context: ExchangeSecondHalfExecutionContext,
        policy: ExchangeSecondHalfPolicy,
        priorsBuilder: ExchangeThreadPriorsBuilder,
        qualifier: ExchangeOpportunityQualifier,
        structuredAnswerEngine: ExchangeStructuredAnswerEngine,
        stanceEngine: ExchangeThreadStanceEngine,
        deltaEngine: ExchangeThreadDeltaEngine,
        boundaryEngine: ExchangeCommitmentBoundaryEngine,
        nextMoveEngine: ExchangeNextMoveEngine,
        providerIntakeEngine: ExchangeProviderIntakeEngine,
        decisionFramer: ExchangeDecisionFramer,
        draftComposer: ExchangeDraftComposer
    ) -> Result {
        exchSecondHalfProviderLog(
            "run enter thread=\(context.threadID.uuidString) state=\(context.currentState.rawValue)"
        )

        let priors = priorsBuilder.build(
            from: .init(
                role: context.role,
                priorQuestionsAsked: context.priorQuestionsAsked,
                priorAnswersReceived: context.priorAnswersReceived,
                currentConstraints: context.currentConstraints,
                priorNonCommitments: context.priorNonCommitments,
                lastDecisionFrame: context.lastDecisionFrame,
                lastApprovedPosition: context.lastApprovedPosition,
                latestDelta: context.latestDelta,
                lastKnownStance: context.lastKnownStance
            )
        )

        let qualificationResult = qualifier.evaluate(
            input: .init(
                role: context.role,
                priors: priors,
                operatingMemory: context.operatingMemory,
                threadState: context.currentState,
                knownFacts: context.knownFacts,
                unresolvedIssues: context.unresolvedIssues,
                surfacedCandidateCount: context.surfacedCandidateCount,
                hasDecisionFrame: context.lastDecisionFrame?.hasMeaningfulContent ?? false
            ),
            policy: policy
        )

        let structuredAnswer = context.structuredQuery.flatMap {
            structuredAnswerEngine.answer(query: $0, memory: context.operatingMemory)
        }

        let canAnswerFromContext =
            structuredAnswer != nil ||
            context.inquiry?.canBeAnsweredFromKnownFacts == true ||
            !context.knownFacts.isEmpty

        let provisionalAction: ExchangeSecondHalfAction =
            canAnswerFromContext ? .autoRespond : .requestUserInput

        let boundary = boundaryEngine.classify(
            input: .init(
                action: provisionalAction,
                isCustomPricing: context.isCustomPricing,
                includesSensitiveDisclosure: context.includesSensitiveDisclosure,
                includesScheduleCommitment: context.includesScheduleCommitment,
                includesLegalCommercialCommitment: context.includesLegalCommercialCommitment,
                isPolicyException: context.isPolicyException,
                rationale: nil
            )
        )

        exchSecondHalfProviderLog(
            "conversion pre_intake thread=\(context.threadID.uuidString) " +
                "inquiryAnswerability=\(context.inquiry?.answerabilityStatus.rawValue ?? "nil") " +
                "provisionalAction=\(provisionalAction.rawValue) " +
                "structuredAnswer=\(structuredAnswer != nil) " +
                "boundaryKind=\(boundary.kind.rawValue) " +
                "boundaryRequiresApproval=\(boundary.requiresHumanApproval)"
        )

        var intakeResult: ExchangeProviderIntakeEngine.Result
        if let inquiry = context.inquiry {
            intakeResult = providerIntakeEngine.evaluate(
                inquiry: inquiry,
                qualification: qualificationResult.qualification,
                boundary: boundary,
                autonomousRoundsSoFar: context.autonomousRoundsSoFar,
                policy: policy
            )
        } else {
            intakeResult = .init(
                decision: .surfaceStrongLead,
                rationale: "No explicit inquiry object was supplied; defaulting to general provider-side review.",
                suggestedAction: .recommendNextMove
            )
        }

        if intakeResult.decision == .answerAutomatically && structuredAnswer == nil {
            let bypassPacket = context.providerCompareFirstStructuredPillarBypassPacket
            let bypass = bypassPacket?.isEligible == true

            var gateDecision = "keep"
            var gateReason = "answerAutomatically_without_structured_pillar"

            if bypass {
                gateDecision = "keep"
                gateReason = "compare_first_grounded_public_facts_bypass"
            } else if context.inquiry?.canBeAnsweredFromKnownFacts != true {
                gateDecision = "downgrade"
                gateReason = "inquiry_not_marked_answerable_from_known_facts"
                intakeResult = .init(
                    decision: .askProviderUser,
                    rationale: "The inquiry is not grounded in structured operating facts yet; provider input is required.",
                    suggestedAction: .requestUserInput
                )
            } else if let inquiry = context.inquiry, let structuredQuery = context.structuredQuery,
                      !structuredQueryRoughlyAlignedWithInboundInquiry(structuredQuery, inquiry) {
                // Classifier/onboarding can label the inbound thread answerable while a specific structured
                // pillar failed to hydrate; do not autopilot when the operative query diverges materially.
                gateDecision = "downgrade"
                gateReason = "structured_pillar_empty_and_query_not_aligned_with_inquiry"
                intakeResult = .init(
                    decision: .askProviderUser,
                    rationale: "The structured pillar did not hydrate and does not clearly match this inbound inquiry; provider input is required.",
                    suggestedAction: .requestUserInput
                )
            }

            #if DEBUG
            providerFlowStructuredPillarDecisionGateDebugLog(
                threadID: context.threadID,
                bypassPacket: bypassPacket,
                answerability: context.inquiry?.answerabilityStatus.rawValue ?? "nil",
                structuredAnswer: false,
                boundaryKind: boundary.kind.rawValue,
                boundaryRequiresApproval: boundary.requiresHumanApproval,
                bypassApplied: bypass,
                gateDecision: gateDecision,
                gateReason: gateReason
            )
            #endif
        }

        let stance = stanceEngine.update(
            input: .init(
                previousStance: context.lastKnownStance,
                qualification: qualificationResult.qualification,
                priors: priors,
                role: context.role,
                threadState: context.currentState,
                isTimeSensitive: context.isTimeSensitive,
                isPriceSensitive: context.isPriceSensitive,
                hasLowTrustSignals: context.hasLowTrustSignals,
                recommendedNextMove: intakeResult.suggestedAction
            )
        )

        let plan = providerPlan(
            intakeResult: intakeResult,
            context: context,
            qualification: qualificationResult.qualification,
            stance: stance,
            priors: priors,
            boundary: boundary,
            policy: policy,
            nextMoveEngine: nextMoveEngine
        )

        exchSecondHalfProviderLog(
            "conversion post_plan thread=\(context.threadID.uuidString) " +
                "intakeDecision=\(intakeResult.decision.rawValue) " +
                "suggestedAction=\(intakeResult.suggestedAction.rawValue) " +
                "finalAction=\(plan.selectedAction.rawValue) " +
                "boundaryKind=\(boundary.kind.rawValue) " +
                "boundaryRequiresApproval=\(boundary.requiresHumanApproval)"
        )

        let frame = decisionFramer.buildFrame(
            input: .init(
                role: context.role,
                state: context.currentState,
                qualification: qualificationResult.qualification,
                delta: context.latestDelta,
                stance: stance,
                clarifiedFacts: context.clarifiedFacts + (structuredAnswer?.sourcedFacts ?? []),
                unresolvedIssues: context.unresolvedIssues,
                recommendation: intakeResult.rationale,
                tradeoffs: qualificationResult.qualification.weaknessReasons,
                nextMove: plan.selectedAction,
                escalationReason: boundary.requiresHumanApproval ? boundary.reason : nil
            ),
            boundary: boundary,
            policy: policy
        )

        let delta = deltaEngine.calculate(
            input: .init(
                previousQualification: nil,
                currentQualification: qualificationResult.qualification,
                previousStance: context.lastKnownStance,
                currentStance: stance,
                previousRecommendation: context.previousRecommendation,
                currentRecommendation: frame.recommendation
            )
        )

        let draft: ExchangeDraftComposer.Draft?
        if plan.needsGeneration {
            draft = draftComposer.compose(
                input: .init(
                    role: context.role,
                    action: plan.selectedAction,
                    priors: priors,
                    style: context.styleProfile,
                    operatingMemory: context.operatingMemory,
                    boundary: boundary,
                    counterpartyName: context.counterpartyName,
                    subjectMatter: context.subjectMatter,
                    requestedItems: context.requestedItems,
                    clarifiedFacts: context.clarifiedFacts + (structuredAnswer?.sourcedFacts ?? []),
                    unresolvedIssues: context.unresolvedIssues,
                    customInstructions: context.customInstructions
                )
            )
        } else {
            draft = nil
        }

        exchSecondHalfProviderLog(
            "run exit qualification=\(qualificationResult.qualification.qualityTier.rawValue) " +
            "surface=\(qualificationResult.shouldSurfaceNow) " +
            "decision=\(intakeResult.decision.rawValue) " +
            "action=\(plan.selectedAction.rawValue) " +
            "boundary=\(boundary.kind.rawValue)"
        )

        return Result(
            priors: priors,
            qualification: qualificationResult.qualification,
            shouldSurfaceNow: qualificationResult.shouldSurfaceNow,
            stance: stance,
            delta: delta,
            boundary: boundary,
            plan: plan,
            decisionFrame: frame.hasMeaningfulContent ? frame : nil,
            draft: draft,
            structuredAnswer: structuredAnswer,
            providerIntakeDecision: intakeResult.decision
        )
    }
}

#if DEBUG
@inline(__always)
private func providerFlowStructuredPillarDecisionGateDebugLog(
    threadID: UUID,
    bypassPacket: ProviderCompareFirstStructuredPillarBypassPacket?,
    answerability: String,
    structuredAnswer: Bool,
    boundaryKind: String,
    boundaryRequiresApproval: Bool,
    bypassApplied: Bool,
    gateDecision: String,
    gateReason: String
) {
    let p = bypassPacket
    let compareAction = p?.compareNormalizedAction ?? "nil"
    let recommendedDisposition = p?.recommendedDisposition ?? "nil"
    let hasCompareGroundedDraft = p.map { String($0.hasCompareGroundedDraft) } ?? "nil"
    let missingFactsCount = p.map { String($0.missingFactsCount) } ?? "nil"
    let needsProviderInput = p.map { String($0.needsProviderInput) } ?? "nil"
    let canSendWithinConsent = p.flatMap { $0.canSendWithinConsent }.map { String($0) } ?? "nil"
    let requiresBoundaryApproval = p.flatMap { $0.requiresBoundaryApproval }.map { String($0) } ?? "nil"
    Swift.print(
        "[ProviderFlow][decisionGate] thread=\(threadID.uuidString) " +
            "compareAction=\(compareAction) " +
            "recommendedDisposition=\(recommendedDisposition) " +
            "answerability=\(answerability) " +
            "structuredAnswer=\(structuredAnswer) " +
            "hasCompareGroundedDraft=\(hasCompareGroundedDraft) " +
            "missingFactsCount=\(missingFactsCount) " +
            "needsProviderInput=\(needsProviderInput) " +
            "canSendWithinConsent=\(canSendWithinConsent) " +
            "requiresBoundaryApproval=\(requiresBoundaryApproval) " +
            "boundaryKind=\(boundaryKind) " +
            "boundaryRequiresApproval=\(boundaryRequiresApproval) " +
            "bypassEligible=\(p.map { String($0.isEligible) } ?? "nil") " +
            "bypassApplied=\(bypassApplied) " +
            "decision=\(gateDecision) " +
            "reason=\(gateReason)"
    )
}
#endif

private extension ExchangeSecondHalfProviderFlow {
    /// Token overlap heuristic: when structured engine returns nothing, only trust `.answerAutomatically`
    /// for known-fact labeling if the operative query aligns with inbound ask/summary wording.
    /// Skips trivial English question words so “home visit price” matches canonical pricing prompts.
    func structuredQueryRoughlyAlignedWithInboundInquiry(
        _ query: ExchangeStructuredAnswerEngine.Query,
        _ inquiry: ExchangeInboundInquiry
    ) -> Bool {
        let stopwords: Set<String> = [
            "what", "when", "where", "who", "why", "how", "much", "the", "a", "an", "your", "our", "any",
            "tell", "please", "about", "with", "from", "this", "that", "these", "those", "and", "or", "you",
            "can", "does", "would", "could", "for", "are", "is", "do", "be", "need", "like", "some", "get",
            "have", "has", "will", "just", "very", "more", "than", "into", "per", "not", "all", "each"
        ]

        func significantTokens(from raw: String) -> Set<String> {
            let pieces = raw
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 2 && !stopwords.contains($0) }
            return Set(pieces)
        }

        let qTokens = significantTokens(from: query.rawText)
        let inbound = inquiry.requesterAsk + " " + inquiry.inquirySummary
        let inboundTokens = significantTokens(from: inbound)
        if qTokens.isEmpty || inboundTokens.isEmpty {
            return false
        }
        return !qTokens.isDisjoint(with: inboundTokens)
    }

    func providerPlan(
        intakeResult: ExchangeProviderIntakeEngine.Result,
        context: ExchangeSecondHalfExecutionContext,
        qualification: ExchangeOpportunityQualification,
        stance: ExchangeThreadStance,
        priors: ExchangeThreadPriors,
        boundary: ExchangeCommitmentBoundary,
        policy: ExchangeSecondHalfPolicy,
        nextMoveEngine: ExchangeNextMoveEngine
    ) -> ExchangeSecondHalfPlan {
        if policy.requiresApproval(for: boundary) {
            let approvalRationale = boundary.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            exchSecondHalfProviderLog(
                "providerPlan escalation thread=\(context.threadID.uuidString) " +
                    "intakeDecision=\(intakeResult.decision.rawValue) " +
                    "suggestedAction=\(intakeResult.suggestedAction.rawValue) " +
                    "boundaryKind=\(boundary.kind.rawValue) " +
                    "reason=\(approvalRationale.isEmpty ? "empty" : approvalRationale)"
            )

            return .escalate(
                role: context.role,
                rationale: approvalRationale.isEmpty
                    ? "The provider-side response crosses an approval boundary."
                    : approvalRationale
            )
        }

        switch intakeResult.decision {
        case .answerAutomatically:
            return ExchangeSecondHalfPlan(
                selectedAction: .autoRespond,
                role: context.role,
                rationale: intakeResult.rationale,
                requiredInputs: [],
                needsGeneration: true,
                needsUserInput: false,
                needsApproval: false
            )

        case .askProviderUser:
            return .requestInput(
                role: context.role,
                rationale: intakeResult.rationale,
                requiredInputs: ["Provider-side input is needed before replying."]
            )

        case .declinePolitely:
            return ExchangeSecondHalfPlan(
                selectedAction: .decline,
                role: context.role,
                rationale: intakeResult.rationale,
                requiredInputs: [],
                needsGeneration: true,
                needsUserInput: false,
                needsApproval: false
            )

        case .markWeakLead:
            return ExchangeSecondHalfPlan(
                selectedAction: .markStalled,
                role: context.role,
                rationale: intakeResult.rationale,
                requiredInputs: [],
                needsGeneration: false,
                needsUserInput: false,
                needsApproval: false
            )

        case .surfaceStrongLead:
            return ExchangeSecondHalfPlan(
                selectedAction: .recommendNextMove,
                role: context.role,
                rationale: intakeResult.rationale,
                requiredInputs: [],
                needsGeneration: true,
                needsUserInput: false,
                needsApproval: false
            )
        }
    }
    
}
