import Foundation

#if DEBUG
@inline(__always)
private func exchSecondHalfRequesterLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeSecondHalfRequesterFlow] \(message())")
}
#else
@inline(__always)
private func exchSecondHalfRequesterLog(_ message: @autoclosure () -> String) {}
#endif

/// Explicit requester-side orchestration.
///
/// Keeps requester logic readable and separate from provider-side intake logic.
public struct ExchangeSecondHalfRequesterFlow: Sendable {
    private let assessmentEngine: (any ExchangeProviderResponseAssessmentEngine)?
    private let asyncAssessmentEngine: (any AsyncExchangeProviderResponseAssessmentEngine)?

    public init(
        assessmentEngine: (any ExchangeProviderResponseAssessmentEngine)? = nil,
        asyncAssessmentEngine: (any AsyncExchangeProviderResponseAssessmentEngine)? = nil
    ) {
        self.assessmentEngine = assessmentEngine
        self.asyncAssessmentEngine = asyncAssessmentEngine
    }

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
        public var pauseFrame: ExchangeRequesterPauseFrame?

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
            pauseFrame: ExchangeRequesterPauseFrame? = nil
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
            self.pauseFrame = pauseFrame
        }
    }

    public func run(
        context: ExchangeSecondHalfExecutionContext,
        policy: ExchangeSecondHalfPolicy,
        priorsBuilder: ExchangeThreadPriorsBuilder,
        qualifier: ExchangeOpportunityQualifier,
        stanceEngine: ExchangeThreadStanceEngine,
        deltaEngine: ExchangeThreadDeltaEngine,
        boundaryEngine: ExchangeCommitmentBoundaryEngine,
        nextMoveEngine: ExchangeNextMoveEngine,
        requesterReviewEngine: ExchangeRequesterReviewEngine,
        decisionFramer: ExchangeDecisionFramer,
        draftComposer: ExchangeDraftComposer,
        assessmentOverride: ExchangeProviderResponseAssessment? = nil
    ) -> Result {
        exchSecondHalfRequesterLog(
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

        let preliminaryBoundary = boundaryEngine.classify(
            input: .init(
                action: .recommendNextMove,
                isCustomPricing: context.isCustomPricing,
                includesSensitiveDisclosure: context.includesSensitiveDisclosure,
                includesScheduleCommitment: context.includesScheduleCommitment,
                includesLegalCommercialCommitment: context.includesLegalCommercialCommitment,
                isPolicyException: context.isPolicyException,
                rationale: "Requester-side review boundary check."
            )
        )

        let reviewer = requesterReviewEngine.evaluate(
            input: .init(
                qualification: qualificationResult.qualification,
                stance: context.lastKnownStance ?? .neutral,
                priors: priors,
                clarificationRounds: context.clarificationRounds,
                hasComparableAlternatives: context.hasComparableAlternatives,
                hasFreshProviderAnswer: context.hasFreshProviderAnswer,
                boundary: preliminaryBoundary
            ),
            policy: policy
        )

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
                recommendedNextMove: reviewer.suggestedAction
            )
        )

        let boundary = boundaryEngine.classify(
            input: .init(
                action: reviewer.suggestedAction,
                isCustomPricing: context.isCustomPricing,
                includesSensitiveDisclosure: context.includesSensitiveDisclosure,
                includesScheduleCommitment: context.includesScheduleCommitment,
                includesLegalCommercialCommitment: context.includesLegalCommercialCommitment,
                isPolicyException: context.isPolicyException,
                rationale: reviewer.rationale
            )
        )

        let assessment = assessmentOverride ?? assessmentEngine?.assessProviderResponse(
            context: context,
            priorAssessment: nil
        )
        let assessmentSignals = Self.assessmentSignals(from: assessment)
        let outboundMaterialGapCount: Int = assessmentSignals?.materialUnresolvedCount
            ?? Self.outboundProviderDirectedFollowUpIssueCount(in: context.unresolvedIssues)
        let userProbeIntentLikely: Bool = assessmentSignals?.followUpUseful
            ?? Self.isUserProbeIntentLikely(context: context)
        let hasDirectedUnresolved: Bool = assessmentSignals?.hasDirectedUnresolved
            ?? context.unresolvedIssues.contains { line in
                Self.outboundProviderDirectedFollowUpIssueCount(in: [line]) > 0
            }
        let hasOutboundFollowUpSignal = outboundMaterialGapCount > 0 || userProbeIntentLikely

        var plan = nextMoveEngine.select(
            input: .init(
                role: context.role,
                state: context.currentState,
                qualification: qualificationResult.qualification,
                stance: stance,
                priors: priors,
                clarificationRounds: context.clarificationRounds,
                followUpAttempts: context.followUpAttempts,
                canAnswerStructurally: false,
                boundary: boundary,
                hasOutboundProviderMaterialFollowUpIssues: hasOutboundFollowUpSignal
            ),
            policy: policy
        )

        let hasOnlyRoutineMissingFacts =
            !context.unresolvedIssues.isEmpty &&
            !context.isCustomPricing &&
            !context.includesSensitiveDisclosure &&
            !context.includesScheduleCommitment &&
            !context.includesLegalCommercialCommitment &&
            !context.isPolicyException

        if hasOnlyRoutineMissingFacts &&
            !policy.hasExceededClarificationLimit(context.clarificationRounds) &&
            plan.selectedAction != .askClarification {
            plan = ExchangeSecondHalfPlan(
                selectedAction: .askClarification,
                role: context.role,
                rationale: "Missing routine request details should be clarified before escalation or comparison.",
                requiredInputs: [],
                needsGeneration: true,
                needsUserInput: false,
                needsApproval: false
            )
        }

        if plan.selectedAction == .frameDecision,
           !boundary.requiresHumanApproval,
           !policy.hasExceededClarificationLimit(context.clarificationRounds) {
            if (assessmentSignals?.shouldAskClarification ?? false)
                || outboundMaterialGapCount > 0
                || hasDirectedUnresolved
                || userProbeIntentLikely {
                plan = ExchangeSecondHalfPlan(
                    selectedAction: .askClarification,
                    role: context.role,
                    rationale:
                        "You asked to confirm details with the provider; we'll send a focused clarification first.",
                    requiredInputs: [],
                    needsGeneration: true,
                    needsUserInput: false,
                    needsApproval: false
                )
                #if DEBUG
                exchSecondHalfRequesterLog(
                    "[SecondHalfPlan] requesterOverride askClarification | reason=probeOrDirectedGaps | gapLines=\(outboundMaterialGapCount) probeLikely=\(userProbeIntentLikely) directedUnresolved=\(hasDirectedUnresolved)"
                )
                #endif
            }
        }

        if plan.selectedAction == .recommendNextMove,
           !boundary.requiresHumanApproval,
           !policy.hasExceededClarificationLimit(context.clarificationRounds) {
            if (assessmentSignals?.shouldAskClarification ?? false)
                || outboundMaterialGapCount > 0
                || hasDirectedUnresolved
                || userProbeIntentLikely {
                plan = ExchangeSecondHalfPlan(
                    selectedAction: .askClarification,
                    role: context.role,
                    rationale:
                        "You asked to confirm details with the provider; we'll send a focused clarification before recommending a next move.",
                    requiredInputs: [],
                    needsGeneration: true,
                    needsUserInput: false,
                    needsApproval: false
                )
                #if DEBUG
                exchSecondHalfRequesterLog(
                    "[SecondHalfPlan] requesterOverride askClarification | reason=outboundMaterialGaps_recommendNextMove | gapLines=\(outboundMaterialGapCount) probeLikely=\(userProbeIntentLikely) directedUnresolved=\(hasDirectedUnresolved)"
                )
                #endif
            }
        }

        if let nextMoveRecommendation = assessment?.nextMoveRecommendation {
            switch nextMoveRecommendation {
            case .requestUserInput:
                if !boundary.requiresHumanApproval {
                    plan = .requestInput(
                        role: context.role,
                        rationale: assessment?.summary ?? "Assessment indicates requester input is needed.",
                        requiredInputs: ["Confirm preferences or constraints"]
                    )
                }
            case .escalateForApproval:
                if !boundary.requiresHumanApproval {
                    plan = ExchangeSecondHalfPlan(
                        selectedAction: .frameDecision,
                        role: context.role,
                        rationale: assessment?.summary ?? "Assessment indicates judgment tradeoffs should be surfaced.",
                        requiredInputs: [],
                        needsGeneration: true,
                        needsUserInput: false,
                        needsApproval: false
                    )
                }
            default:
                break
            }
        }

        plan = Self.requesterPlanByGuardingAnchoredRecipientForProviderOutboundDrafts(
            plan: plan,
            context: context
        )

        #if DEBUG
        let userProbeIntentRaw = userProbeIntentLikely || outboundMaterialGapCount > 0
        let qualificationMissingFactsCount = qualificationResult.qualification.missingFacts.count
        let topCandidateCount = min(3, max(0, context.surfacedCandidateCount))
        let reasonSnippet = plan.rationale
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let reasonCapped: String = {
            if reasonSnippet.count > 140 {
                return String(reasonSnippet.prefix(140)) + "…"
            }
            return reasonSnippet
        }()
        exchSecondHalfRequesterLog(
            "[SecondHalfPlan] role=requester selectedActionRaw=\(plan.selectedAction.rawValue) selectedActionTitle=\(plan.selectedAction.displayTitle) unresolvedIssuesCount=\(context.unresolvedIssues.count) qualificationMissingFactsCount=\(qualificationMissingFactsCount) outboundMaterialGapCount=\(outboundMaterialGapCount) userProbeIntentRaw=\(userProbeIntentRaw) topCandidateCount=\(topCandidateCount) reason=\(reasonCapped)"
        )
        #endif

        let pauseEngine = ExchangeRequesterReplyResolutionEngine()
        var requestTextParts: [String] = []
        if let sm = context.subjectMatter?.trimmingCharacters(in: .whitespacesAndNewlines), !sm.isEmpty {
            requestTextParts.append(sm)
        }
        let itemsJoined = context.requestedItems.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !itemsJoined.isEmpty {
            requestTextParts.append(itemsJoined)
        }
        if let ci = context.customInstructions?.trimmingCharacters(in: .whitespacesAndNewlines), !ci.isEmpty {
            requestTextParts.append(ci)
        }
        let requestTextBlob = requestTextParts.joined(separator: " ")

        let rawPauseFrame = pauseEngine.resolve(
            input: .init(
                requestTextBlob: requestTextBlob,
                knownFactsLines: context.knownFacts,
                clarifiedFactsLines: context.clarifiedFacts,
                unresolvedIssuesLines: context.unresolvedIssues,
                qualificationMissingFacts: qualificationResult.qualification.missingFacts,
                latestCounterpartyReplyText: context.latestCounterpartyReplyText,
                hasFreshProviderAnswer: context.hasFreshProviderAnswer,
                qualificationTier: qualificationResult.qualification.qualityTier,
                secondHalfState: context.currentState,
                isThreadExplicitlyCompleted: context.isThreadExplicitlyCompleted
            )
        )
        let pauseFrame = pauseEngine.mergePauseReason(
            base: rawPauseFrame,
            boundaryRequiresHumanApproval: boundary.requiresHumanApproval,
            secondHalfState: context.currentState
        )

        let frame = decisionFramer.buildFrame(
            input: .init(
                role: context.role,
                state: context.currentState,
                qualification: qualificationResult.qualification,
                delta: context.latestDelta,
                stance: stance,
                clarifiedFacts: context.clarifiedFacts,
                unresolvedIssues: context.unresolvedIssues,
                recommendation: reviewer.rationale,
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
                    clarifiedFacts: context.clarifiedFacts,
                    unresolvedIssues: context.unresolvedIssues,
                    customInstructions: context.customInstructions,
                    isFirstExternalContact: context.isFirstExternalContact,
                    requestCapturedText: context.requestCapturedText,
                    offerTitle: nil,
                    profileDisplayName: context.counterpartyName
                )
            )
            #if DEBUG
            if context.isFirstExternalContact {
                RequesterOutboundBodySourceDebugLog.log(
                    threadID: context.threadID,
                    actionRaw: plan.selectedAction.rawValue,
                    firstContact: true,
                    bodySource: "firstContactInquiry",
                    titleSource: context.subjectMatter ?? "this opportunity",
                    containsGenericTitle: false
                )
            }
            #endif
        } else {
            draft = nil
        }

        exchSecondHalfRequesterLog(
            "run exit qualification=\(qualificationResult.qualification.qualityTier.rawValue) " +
            "surface=\(qualificationResult.shouldSurfaceNow) " +
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
            pauseFrame: pauseFrame
        )
    }

    public func runAsync(
        context: ExchangeSecondHalfExecutionContext,
        policy: ExchangeSecondHalfPolicy,
        priorsBuilder: ExchangeThreadPriorsBuilder,
        qualifier: ExchangeOpportunityQualifier,
        stanceEngine: ExchangeThreadStanceEngine,
        deltaEngine: ExchangeThreadDeltaEngine,
        boundaryEngine: ExchangeCommitmentBoundaryEngine,
        nextMoveEngine: ExchangeNextMoveEngine,
        requesterReviewEngine: ExchangeRequesterReviewEngine,
        decisionFramer: ExchangeDecisionFramer,
        draftComposer: ExchangeDraftComposer
    ) async -> Result {
        let asyncAssessment = await asyncAssessmentEngine?.assessProviderResponse(
            context: context,
            priorAssessment: nil
        )
        return run(
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
            draftComposer: draftComposer,
            assessmentOverride: asyncAssessment
        )
    }
}

private extension ExchangeSecondHalfRequesterFlow {
    struct AssessmentSignals: Sendable {
        var materialUnresolvedCount: Int
        var followUpUseful: Bool
        var hasDirectedUnresolved: Bool
        var shouldAskClarification: Bool
    }

    static func assessmentSignals(
        from assessment: ExchangeProviderResponseAssessment?
    ) -> AssessmentSignals? {
        guard let assessment else { return nil }
        let material = assessment.conditionAssessments.filter {
            $0.status == .notAnswered || $0.status == .needsFollowUp
        }
        let hasDirected = material.contains {
            $0.source == .gapFill || $0.source == .commercialConstraint || $0.source == .timingConstraint
        }
        let hasContradiction = assessment.conditionAssessments.contains {
            $0.status == .contradicted
        }
        let shouldAskClarification = material.count > 0 && !hasContradiction
        return AssessmentSignals(
            materialUnresolvedCount: material.count,
            followUpUseful: assessment.safeForAutonomousFollowup || shouldAskClarification,
            hasDirectedUnresolved: hasDirected,
            shouldAskClarification: shouldAskClarification
        )
    }

    /// Any **requester** plan that would generate persisted **provider-bound** outbound copy needs a durable
    /// recipient surface (selected counterparty / offer / profile, or federation inbound context). Without one,
    /// downgrade so the draft composer and executor cannot emit external counterparty drafts for a phantom recipient.
    static func requesterPlanByGuardingAnchoredRecipientForProviderOutboundDrafts(
        plan: ExchangeSecondHalfPlan,
        context: ExchangeSecondHalfExecutionContext
    ) -> ExchangeSecondHalfPlan {
        guard context.role == .requester else { return plan }
        guard !context.hasAnchoredRecipientSurfaceForRequesterProviderOutbound else { return plan }
        guard plan.needsGeneration else { return plan }

        let outboundish: Set<ExchangeSecondHalfAction> = [
            .askClarification,
            .recommendNextMove,
            .frameDecision,
            .proposeTerms,
            .reviseTerms,
            .compareOptions,
            .decline
        ]
        guard outboundish.contains(plan.selectedAction) else { return plan }

        let topCandidateCount = min(3, max(0, context.surfacedCandidateCount))
        #if DEBUG
        let cid = logTokenNonBlankElseNilWord(context.selectedCounterpartyID)
        let pid = logTokenNonBlankElseNilWord(context.selectedPublicProfileID)
        let oid = logTokenNonBlankElseNilWord(context.selectedOfferID)
        exchSecondHalfRequesterLog(
            "[SecondHalfPlan] requester outbound draft blocked reason=no_recipient_surface action=\(plan.selectedAction.rawValue) topCandidateCount=\(topCandidateCount) selectedCounterpartyID=\(cid) selectedProfileID=\(pid) selectedOfferID=\(oid)"
        )
        #endif

        return .requestInput(
            role: .requester,
            rationale:
                "No confirmed provider, listing, or profile is anchored on this thread yet. Refine your search, broaden coverage, or wait for clearer matches before sending outward questions.",
            requiredInputs: ["Refine search criteria or broaden the request"]
        )
    }

    #if DEBUG
    static func logTokenNonBlankElseNilWord(_ raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return "nil"
        }
        return trimmed
    }
    #endif

    /// Counts user-facing outbound material-gap lines from `ExchangeFacade.makeSecondHalfUnresolvedIssues`
    /// (including newer provider-directed confirmation lines).
    static func outboundProviderDirectedFollowUpIssueCount(in issues: [String]) -> Int {
        issues.filter { issue in
            let lower = issue.lowercased()
            if lower.contains("please confirm") || lower.contains("could you confirm") {
                return true
            }
            let keys = [
                "price", "rate", "pricing", "availability", "schedule", "location", "lesson",
                "in-person", "in person", "remote", "service area", "provider's", "provider"
            ]
            return keys.contains { lower.contains($0) }
        }.count
    }

    /// Heuristic: user text (subject + requested items + constraints + early known facts) asks to learn/confirm details.
    static func isUserProbeIntentLikely(context: ExchangeSecondHalfExecutionContext) -> Bool {
        var parts: [String] = []
        if let s = context.subjectMatter?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            parts.append(s)
        }
        parts.append(contentsOf: context.requestedItems)
        parts.append(contentsOf: context.currentConstraints)
        for line in context.knownFacts.prefix(3) {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { parts.append(t) }
        }
        let blob = parts.joined(separator: " ").lowercased()
        return Self.probePhraseMatched(inLowercasedBlob: blob)
    }

    static func probePhraseMatched(inLowercasedBlob blob: String) -> Bool {
        let phrases: [String] = [
            "tell me about", "learn about", "see if", "find out", "ask about", "ask them about",
            "check with", "confirm with", "reach out", "contact them", "inquire about",
            "what's the", "what is the", "how much", "availability"
        ]
        if phrases.contains(where: { blob.contains($0) }) {
            return true
        }
        if blob.contains(" confirm") || blob.contains("confirm ") || blob.contains("confirmation") {
            return true
        }
        if blob.contains(" check ") || blob.hasPrefix("check ") || blob.contains("check if")
            || blob.contains("check on") || blob.contains("checking") {
            return true
        }
        if blob.contains(" available ") || blob.contains("availability") {
            return true
        }
        return false
    }
}
