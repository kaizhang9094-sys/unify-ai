import Foundation

/// Canonical legal second-half state transitions.
///
/// This centralizes legal moves so transition logic does not get scattered
/// across UI, facade, and coordinator code.
public struct ExchangeSecondHalfStateMachine: Sendable {
    public init() {}

    public func allowedActions(
        for state: ExchangeSecondHalfState
    ) -> Set<ExchangeSecondHalfAction> {
        switch state {
        case .matchFound:
            return [
                .qualifyMatch,
                .requestUserInput,
                .markBlocked,
                .markStalled
            ]

        case .qualifying:
            return [
                .askClarification,
                .requestUserInput,
                .frameDecision,
                .recommendNextMove,
                .markBlocked,
                .markStalled
            ]

        case .awaitingProviderClarification:
            return [
                .answerClarification,
                .requestUserInput,
                .markBlocked,
                .markStalled
            ]

        case .awaitingRequesterClarification:
            return [
                .answerClarification,
                .requestUserInput,
                .markBlocked,
                .markStalled
            ]

        case .providerReview:
            return [
                .autoRespond,
                .answerClarification,
                .requestUserInput,
                .decline,
                .pause,
                .markBlocked,
                .markStalled
            ]

        case .requesterReview:
            return [
                .askClarification,
                .frameDecision,
                .recommendNextMove,
                .compareOptions,
                .requestUserInput,
                .decline,
                .pause,
                .markBlocked,
                .markStalled
            ]

        case .decisionReady:
            return [
                .frameDecision,
                .recommendNextMove,
                .compareOptions,
                .proposeTerms,
                .reviseTerms,
                .escalateForApproval,
                .accept,
                .decline,
                .pause
            ]

        case .awaitingCommitmentApproval:
            return [
                .requestUserInput,
                .accept,
                .decline,
                .pause,
                .markBlocked
            ]

        case .accepted:
            return [
                .complete
            ]

        case .declined:
            return []

        case .stalled:
            return [
                .recommendNextMove,
                .askClarification,
                .requestUserInput,
                .decline,
                .markBlocked
            ]

        case .blocked:
            return [
                .requestUserInput,
                .decline,
                .pause
            ]

        case .expired:
            return []

        case .completed:
            return []
        }
    }

    public func validate(
        action: ExchangeSecondHalfAction,
        state: ExchangeSecondHalfState
    ) -> Bool {
        allowedActions(for: state).contains(action)
    }

    public func nextState(
        from state: ExchangeSecondHalfState,
        action: ExchangeSecondHalfAction
    ) -> ExchangeSecondHalfState? {
        guard validate(action: action, state: state) else {
            return nil
        }

        switch (state, action) {
        case (.matchFound, .qualifyMatch):
            return .qualifying

        case (.matchFound, .requestUserInput):
            return .requesterReview

        case (.matchFound, .markBlocked):
            return .blocked

        case (.matchFound, .markStalled):
            return .stalled

        case (.qualifying, .askClarification):
            return .awaitingProviderClarification

        case (.qualifying, .requestUserInput):
            return .requesterReview

        case (.qualifying, .frameDecision),
             (.qualifying, .recommendNextMove):
            return .decisionReady

        case (.qualifying, .markBlocked):
            return .blocked

        case (.qualifying, .markStalled):
            return .stalled

        case (.awaitingProviderClarification, .answerClarification):
            return .requesterReview

        case (.awaitingProviderClarification, .requestUserInput):
            return .providerReview

        case (.awaitingProviderClarification, .markBlocked):
            return .blocked

        case (.awaitingProviderClarification, .markStalled):
            return .stalled

        case (.awaitingRequesterClarification, .answerClarification):
            return .providerReview

        case (.awaitingRequesterClarification, .requestUserInput):
            return .requesterReview

        case (.awaitingRequesterClarification, .markBlocked):
            return .blocked

        case (.awaitingRequesterClarification, .markStalled):
            return .stalled

        case (.providerReview, .autoRespond),
             (.providerReview, .answerClarification):
            return .requesterReview

        case (.providerReview, .requestUserInput):
            return .providerReview

        case (.providerReview, .decline):
            return .declined

        case (.providerReview, .pause),
             (.providerReview, .markStalled):
            return .stalled

        case (.providerReview, .markBlocked):
            return .blocked

        case (.requesterReview, .askClarification):
            return .awaitingProviderClarification

        case (.requesterReview, .frameDecision),
             (.requesterReview, .recommendNextMove),
             (.requesterReview, .compareOptions):
            return .decisionReady

        case (.requesterReview, .requestUserInput):
            return .requesterReview

        case (.requesterReview, .decline):
            return .declined

        case (.requesterReview, .pause),
             (.requesterReview, .markStalled):
            return .stalled

        case (.requesterReview, .markBlocked):
            return .blocked

        case (.decisionReady, .frameDecision),
             (.decisionReady, .recommendNextMove),
             (.decisionReady, .compareOptions):
            return .decisionReady

        case (.decisionReady, .proposeTerms),
             (.decisionReady, .reviseTerms),
             (.decisionReady, .escalateForApproval):
            return .awaitingCommitmentApproval

        case (.decisionReady, .accept):
            return .accepted

        case (.decisionReady, .decline):
            return .declined

        case (.decisionReady, .pause):
            return .stalled

        case (.awaitingCommitmentApproval, .requestUserInput):
            return .providerReview

        case (.awaitingCommitmentApproval, .accept):
            return .accepted

        case (.awaitingCommitmentApproval, .decline):
            return .declined

        case (.awaitingCommitmentApproval, .pause):
            return .stalled

        case (.awaitingCommitmentApproval, .markBlocked):
            return .blocked

        case (.accepted, .complete):
            return .completed

        case (.stalled, .recommendNextMove):
            return .requesterReview

        case (.stalled, .askClarification):
            return .awaitingProviderClarification

        case (.stalled, .requestUserInput):
            return .requesterReview

        case (.stalled, .decline):
            return .declined

        case (.stalled, .markBlocked):
            return .blocked

        case (.blocked, .requestUserInput):
            return .requesterReview

        case (.blocked, .decline):
            return .declined

        case (.blocked, .pause):
            return .stalled

        default:
            return nil
        }
    }
}
