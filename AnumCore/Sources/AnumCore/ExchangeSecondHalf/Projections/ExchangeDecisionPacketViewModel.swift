import Foundation

/// User-facing decision packet projection.
///
/// This is the cleaner packet the user should see instead of raw thread logs
/// when the thread becomes meaningful enough to review.
public struct ExchangeDecisionPacketViewModel: Codable, Hashable, Sendable {
    public var summary: String
    public var clarifiedFacts: [String]
    public var whatChanged: [String]
    public var unresolvedIssues: [String]
    public var recommendation: String
    public var tradeoffs: [String]
    public var nextMove: ExchangeNextMoveViewModel?
    public var needsUserJudgment: Bool
    public var needsCommitmentApproval: Bool
    public var requesterPause: ExchangeRequesterPauseFrame?

    public init(
        summary: String,
        clarifiedFacts: [String] = [],
        whatChanged: [String] = [],
        unresolvedIssues: [String] = [],
        recommendation: String,
        tradeoffs: [String] = [],
        nextMove: ExchangeNextMoveViewModel? = nil,
        needsUserJudgment: Bool,
        needsCommitmentApproval: Bool,
        requesterPause: ExchangeRequesterPauseFrame? = nil
    ) {
        self.summary = summary
        self.clarifiedFacts = clarifiedFacts
        self.whatChanged = whatChanged
        self.unresolvedIssues = unresolvedIssues
        self.recommendation = recommendation
        self.tradeoffs = tradeoffs
        self.nextMove = nextMove
        self.needsUserJudgment = needsUserJudgment
        self.needsCommitmentApproval = needsCommitmentApproval
        self.requesterPause = requesterPause
    }
}

public extension ExchangeDecisionPacketViewModel {
    init(
        frame: ExchangeDecisionFrame,
        plan: ExchangeSecondHalfPlan? = nil
    ) {
        let cleanedFacts = ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(frame.clarifiedFacts)
        let cleanedChanged = ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(frame.whatChanged)
        let cleanedIssues = ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(frame.unresolvedIssues)
        let cleanedTradeoffs = ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(frame.tradeoffs)

        let rawReco = frame.recommendation.trimmingCharacters(in: .whitespacesAndNewlines)
        let recommendationOut: String = {
            if let sanitized = ExchangeRequesterReviewPresentation.sanitizedRecommendationBlock(rawReco), !sanitized.isEmpty {
                return sanitized
            }
            if !rawReco.isEmpty, !ExchangeRequesterReviewPresentation.containsInternalRequesterLeak(rawReco) {
                return rawReco
            }
            if let first = cleanedFacts.first {
                return first
            }
            return "Review fit, open questions, and the suggested next step."
        }()

        self.init(
            summary: ExchangeRequesterReviewPresentation.decisionPacketSummary(frame: frame),
            clarifiedFacts: cleanedFacts,
            whatChanged: cleanedChanged,
            unresolvedIssues: cleanedIssues,
            recommendation: recommendationOut,
            tradeoffs: cleanedTradeoffs,
            nextMove: plan.map(ExchangeNextMoveViewModel.init(plan:)),
            needsUserJudgment: frame.needsUserJudgment,
            needsCommitmentApproval: frame.needsCommitmentApproval,
            requesterPause: nil
        )
    }

    /// Decision packet shaped primarily from the logical pause (no meaningful decision frame).
    init(pauseOnly pause: ExchangeRequesterPauseFrame, plan: ExchangeSecondHalfPlan) {
        self.init(
            summary: pause.summaryLine,
            clarifiedFacts: pause.answeredFacts,
            whatChanged: [],
            unresolvedIssues: pause.stillMissingFacts,
            recommendation: pause.recommendationLine,
            tradeoffs: [],
            nextMove: ExchangeNextMoveViewModel(plan: plan),
            needsUserJudgment: pause.pauseReason != .completed && pause.pauseReason != .waitingForProviderReply,
            needsCommitmentApproval: pause.pauseReason == .commitmentReview,
            requesterPause: pause
        )
    }

    var isActionable: Bool {
        nextMove != nil || needsUserJudgment || needsCommitmentApproval
    }

    var hasOpenIssues: Bool {
        !unresolvedIssues.isEmpty
    }

    /// Overlays validated closure copy onto packet fields; keeps deterministic `requesterPause` for authority.
    func mergingClosureComposedCopy(
        _ composed: ExchangeRequesterClosureComposedCopy,
        sanitizedPause: ExchangeRequesterPauseFrame?
    ) -> ExchangeDecisionPacketViewModel {
        ExchangeDecisionPacketViewModel(
            summary: composed.summary,
            clarifiedFacts: ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(composed.answeredBullets),
            whatChanged: whatChanged,
            unresolvedIssues: ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(composed.stillOpenBullets),
            recommendation: composed.recommendation,
            tradeoffs: tradeoffs,
            nextMove: nextMove,
            needsUserJudgment: needsUserJudgment,
            needsCommitmentApproval: needsCommitmentApproval,
            requesterPause: sanitizedPause ?? requesterPause
        )
    }
}
