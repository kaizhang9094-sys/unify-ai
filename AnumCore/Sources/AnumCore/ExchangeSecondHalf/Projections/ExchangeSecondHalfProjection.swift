import Foundation

/// Top-level UI projection for a second-half thread.
///
/// This is the main shape the app should render for a second-half thread.
/// It intentionally carries both generic top-level state and specialized
/// sub-projections for requester/provider surfaces.
public struct ExchangeSecondHalfProjection: Codable, Hashable, Sendable {
    public var currentState: ExchangeSecondHalfState
    public var role: ExchangeSecondHalfRole
    public var stance: ExchangeThreadStance
    public var qualification: ExchangeOpportunityQualification
    public var latestDecisionFrame: ExchangeDecisionFrame?
    public var latestDelta: ExchangeThreadDelta?
    public var pendingDraft: ExchangeDraftComposer.Draft?
    public var escalationReason: String?
    public var visibleActions: [ExchangeSecondHalfAction]

    public var nextMove: ExchangeNextMoveViewModel?
    public var decisionPacket: ExchangeDecisionPacketViewModel?
    public var providerInboxCard: ExchangeProviderInboxCardViewModel?
    public var requesterReviewCard: ExchangeRequesterReviewCardViewModel?

    /// Deterministic Pass 2 agency overlay (merged into cards/drafts downstream).
    public var agencyAssessment: ExchangeAgencyAssessment?

    /// Requester logical pause after provider activity (projection artifact).
    public var requesterPauseFrame: ExchangeRequesterPauseFrame?

    /// Optional validated secretary closure copy (display-only; deterministic pause remains authoritative).
    public var requesterClosureComposedCopy: ExchangeRequesterClosureComposedCopy?

    public init(
        currentState: ExchangeSecondHalfState,
        role: ExchangeSecondHalfRole,
        stance: ExchangeThreadStance,
        qualification: ExchangeOpportunityQualification,
        latestDecisionFrame: ExchangeDecisionFrame? = nil,
        latestDelta: ExchangeThreadDelta? = nil,
        pendingDraft: ExchangeDraftComposer.Draft? = nil,
        escalationReason: String? = nil,
        visibleActions: [ExchangeSecondHalfAction] = [],
        nextMove: ExchangeNextMoveViewModel? = nil,
        decisionPacket: ExchangeDecisionPacketViewModel? = nil,
        providerInboxCard: ExchangeProviderInboxCardViewModel? = nil,
        requesterReviewCard: ExchangeRequesterReviewCardViewModel? = nil,
        agencyAssessment: ExchangeAgencyAssessment? = nil,
        requesterPauseFrame: ExchangeRequesterPauseFrame? = nil,
        requesterClosureComposedCopy: ExchangeRequesterClosureComposedCopy? = nil
    ) {
        self.currentState = currentState
        self.role = role
        self.stance = stance
        self.qualification = qualification
        self.latestDecisionFrame = latestDecisionFrame
        self.latestDelta = latestDelta
        self.pendingDraft = pendingDraft
        self.escalationReason = escalationReason
        self.visibleActions = visibleActions
        self.nextMove = nextMove
        self.decisionPacket = decisionPacket
        self.providerInboxCard = providerInboxCard
        self.requesterReviewCard = requesterReviewCard
        self.agencyAssessment = agencyAssessment
        self.requesterPauseFrame = requesterPauseFrame
        self.requesterClosureComposedCopy = requesterClosureComposedCopy
    }
}

public extension ExchangeSecondHalfProjection {
    init(
        coordinatorResult: ExchangeSecondHalfCoordinator.Result,
        inquiry: ExchangeInboundInquiry? = nil,
        agencyAssessment: ExchangeAgencyAssessment? = nil,
        requesterSurfaceContext: ExchangeRequesterReviewSurfaceContext? = nil
    ) {
        let baseRole: ExchangeSecondHalfRole =
            coordinatorResult.projection.roleTitle == ExchangeSecondHalfRole.provider.displayTitle
                ? .provider
                : .requester

        let mergedDraft = ExchangeSecondHalfPass2DraftAugment.merge(
            base: coordinatorResult.draft,
            assessment: agencyAssessment,
            role: baseRole
        )

        let mergedEscalationBundle = Self.mergedEscalation(
            boundary: coordinatorResult.boundary,
            agency: agencyAssessment?.providerAnswerability
        )

        var nextMoveMerged = Self.mergedNextMove(
            plan: coordinatorResult.plan,
            role: baseRole,
            agency: agencyAssessment
        )

        let sanitizedPause = ExchangeRequesterReviewPresentation.sanitizedPauseFrame(
            coordinatorResult.requesterPauseFrame
        )

        if let composed = coordinatorResult.requesterClosureComposedCopy {
            var nm = nextMoveMerged
            nm.title = composed.nextActionLabel
            nextMoveMerged = nm
        }

        let decisionPacketBase: ExchangeDecisionPacketViewModel? = {
            guard let frame = coordinatorResult.decisionFrame else {
                return sanitizedPause.map { ExchangeDecisionPacketViewModel(pauseOnly: $0, plan: coordinatorResult.plan) }
            }
            var packet = ExchangeDecisionPacketViewModel(frame: frame, plan: coordinatorResult.plan)
            packet.requesterPause = sanitizedPause
            return packet
        }()

        let decisionPacket: ExchangeDecisionPacketViewModel? = {
            guard var packet = decisionPacketBase else { return nil }
            if let composed = coordinatorResult.requesterClosureComposedCopy {
                packet = packet.mergingClosureComposedCopy(composed, sanitizedPause: sanitizedPause)
            }
            return packet
        }()

        let providerInboxCard: ExchangeProviderInboxCardViewModel?
        if coordinatorResult.projection.roleTitle == ExchangeSecondHalfRole.provider.displayTitle {
            providerInboxCard = Self.mergedProviderInboxCard(
                inquiry: inquiry,
                qualification: coordinatorResult.qualification,
                plan: coordinatorResult.plan,
                boundary: coordinatorResult.boundary,
                agencyAnswerability: agencyAssessment?.providerAnswerability,
                nextMoveMerged: nextMoveMerged
            )
        } else {
            providerInboxCard = nil
        }

        let requesterReviewCard: ExchangeRequesterReviewCardViewModel?
        if coordinatorResult.projection.roleTitle == ExchangeSecondHalfRole.requester.displayTitle {
            var card = Self.mergedRequesterReviewCard(
                qualification: coordinatorResult.qualification,
                frame: coordinatorResult.decisionFrame,
                plan: coordinatorResult.plan,
                decisionNeeds: agencyAssessment?.requesterDecisionNeeds,
                nextMoveMerged: nextMoveMerged,
                surfaceContext: requesterSurfaceContext,
                pauseFrame: sanitizedPause
            )
            if let composed = coordinatorResult.requesterClosureComposedCopy {
                card.title = composed.title
            }
            requesterReviewCard = card
        } else {
            requesterReviewCard = nil
        }

        let escalationLine = mergedEscalationBundle.flatMap(\.composedLine)
            ?? (
                coordinatorResult.boundary.requiresHumanApproval
                    ? coordinatorResult.boundary.reason
                    : nil
            )

        self.init(
            currentState: coordinatorResult.nextState,
            role: baseRole,
            stance: coordinatorResult.stance,
            qualification: coordinatorResult.qualification,
            latestDecisionFrame: coordinatorResult.decisionFrame,
            latestDelta: coordinatorResult.delta.hasMeaningfulChange ? coordinatorResult.delta : nil,
            pendingDraft: mergedDraft ?? coordinatorResult.draft,
            escalationReason: escalationLine,
            visibleActions: [coordinatorResult.plan.selectedAction],
            nextMove: nextMoveMerged,
            decisionPacket: decisionPacket,
            providerInboxCard: providerInboxCard,
            requesterReviewCard: requesterReviewCard,
            agencyAssessment: agencyAssessment,
            requesterPauseFrame: sanitizedPause,
            requesterClosureComposedCopy: coordinatorResult.requesterClosureComposedCopy
        )
    }

    var isBlockingOnHuman: Bool {
        nextMove?.isBlockingOnHuman == true ||
            escalationReason != nil ||
            agencyAssessment?.providerAnswerability?.requiresHumanApproval == true
    }

    var hasRenderableContent: Bool {
        latestDecisionFrame?.hasMeaningfulContent == true ||
            latestDelta?.hasMeaningfulChange == true ||
            pendingDraft != nil ||
            providerInboxCard != nil ||
            requesterReviewCard != nil
    }
}

// MARK: - Pass 2 merge helpers (projection-local)

private extension ExchangeSecondHalfProjection {

    struct MergedEscalation {
        var boundaryReason: String?
        var agencyReason: String?

        var composedLine: String? {
            let parts = [boundaryReason, agencyReason]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !parts.isEmpty else { return nil }

            return Array(Set(parts)).sorted().joined(separator: " · ")
        }
    }

    static func mergedEscalation(
        boundary: ExchangeCommitmentBoundary,
        agency: ExchangeProviderAnswerability?
    ) -> MergedEscalation? {
        let boundaryLine = boundary.requiresHumanApproval ? boundary.reason : nil
        let agencyLine = agency?.requiresHumanApproval == true ? agency?.boundaryReason : nil

        if boundaryLine == nil, agencyLine == nil {
            return nil
        }

        return MergedEscalation(
            boundaryReason: boundaryLine,
            agencyReason: agencyLine
        )
    }

    static func mergedNextMove(
        plan: ExchangeSecondHalfPlan,
        role: ExchangeSecondHalfRole,
        agency: ExchangeAgencyAssessment?
    ) -> ExchangeNextMoveViewModel {
        let base = ExchangeNextMoveViewModel(plan: plan)

        switch role {
        case .requester:
            guard let dec = agency?.requesterDecisionNeeds,
                  !dec.recommendedQuestions.isEmpty
            else {
                return base
            }

            let qs = dec.recommendedQuestions.prefix(3).joined(separator: " — ")
            let extra = "Useful asks: \(qs)"
            let mergedRationale =
                base.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? extra
                    : "\(base.rationale)\n\n\(extra)"

            return ExchangeNextMoveViewModel(
                action: base.action,
                title: base.title,
                rationale: mergedRationale,
                requiredInputs: base.requiredInputs,
                needsGeneration: base.needsGeneration,
                needsUserInput: base.needsUserInput,
                needsApproval: base.needsApproval
            )

        case .provider:
            guard let pa = agency?.providerAnswerability else {
                return base
            }

            let title = pa.pass2NextMoveTitle ?? base.title

            var rationale = base.rationale
            if let snippet = pa.proposedAnswer?.trimmingCharacters(in: .whitespacesAndNewlines),
               !snippet.isEmpty {
                let prefix = "Grounding (published facts): \(snippet)"
                rationale = rationale.isEmpty ? prefix : "\(rationale)\n\n\(prefix)"
            }

            let needsApproval = base.needsApproval || pa.requiresHumanApproval

            return ExchangeNextMoveViewModel(
                action: base.action,
                title: title,
                rationale: rationale,
                requiredInputs: base.requiredInputs,
                needsGeneration: base.needsGeneration,
                needsUserInput: base.needsUserInput,
                needsApproval: needsApproval
            )
        }
    }

    static func mergedProviderInboxCard(
        inquiry: ExchangeInboundInquiry?,
        qualification: ExchangeOpportunityQualification,
        plan: ExchangeSecondHalfPlan,
        boundary: ExchangeCommitmentBoundary,
        agencyAnswerability: ExchangeProviderAnswerability?,
        nextMoveMerged: ExchangeNextMoveViewModel
    ) -> ExchangeProviderInboxCardViewModel {
        let baseInquiryStatus = inquiry?.answerabilityStatus.rawValue
        let answerabilityLine = agencyAnswerability?.answerability.pass2DisplayLabel ?? baseInquiryStatus

        let escalationMerged = firstNonBlank(
            boundary.requiresHumanApproval ? boundary.reason : nil,
            agencyAnswerability?.requiresHumanApproval == true ? agencyAnswerability?.boundaryReason : nil
        )

        return ExchangeProviderInboxCardViewModel(
            inquiry: inquiry,
            qualification: qualification,
            plan: plan,
            answerabilityStatusOverride: answerabilityLine,
            escalationReason: escalationMerged,
            nextMove: nextMoveMerged
        )
    }

    static func mergedRequesterReviewCard(
        qualification: ExchangeOpportunityQualification,
        frame: ExchangeDecisionFrame?,
        plan: ExchangeSecondHalfPlan,
        decisionNeeds: ExchangeRequesterDecisionNeeds?,
        nextMoveMerged: ExchangeNextMoveViewModel,
        surfaceContext: ExchangeRequesterReviewSurfaceContext?,
        pauseFrame: ExchangeRequesterPauseFrame? = nil
    ) -> ExchangeRequesterReviewCardViewModel {
        ExchangeRequesterReviewCardViewModel(
            qualification: qualification,
            frame: frame,
            plan: plan,
            decisionNeeds: decisionNeeds,
            nextMove: nextMoveMerged,
            surfaceContext: surfaceContext,
            pauseFrame: pauseFrame
        )
    }

    static func firstNonBlank(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }
}

private extension ExchangeProviderAnswerability {
    var pass2NextMoveTitle: String? {
        switch answerability {
        case .answerableFromPublicFacts:
            return "Grounded reply (public facts)"

        case .partiallyAnswerableNeedsClarification:
            return "Clarify before sending"

        case .requiresProviderApproval:
            return "Seller review required"

        case .notAnswerable:
            return "Needs more context"
        }
    }
}

