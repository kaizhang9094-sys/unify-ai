import Foundation

/// Canonical second-half lifecycle state.
///
/// Owns the post-match thread progression language so the system does not
/// drift into ad hoc string states across engines, UI, or orchestration.
public enum ExchangeSecondHalfState: String, Codable, CaseIterable, Hashable, Sendable {
    case matchFound
    case qualifying
    case awaitingProviderClarification
    case awaitingRequesterClarification
    case providerReview
    case requesterReview
    case decisionReady
    case awaitingCommitmentApproval
    case accepted
    case declined
    case stalled
    case blocked
    case expired
    case completed
}

public extension ExchangeSecondHalfState {
    /// Short, product-language labels for status chips — not internal enum spellings.
    var displayTitle: String {
        switch self {
        case .matchFound: return "Ready to review"
        case .qualifying: return "Review in progress"
        case .awaitingProviderClarification: return "Waiting on them"
        case .awaitingRequesterClarification: return "Needs your reply"
        case .providerReview: return "Their review"
        case .requesterReview: return "Review opportunity"
        case .decisionReady: return "Ready to decide"
        case .awaitingCommitmentApproval: return "Needs approval"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .stalled: return "Paused"
        case .blocked: return "Blocked"
        case .expired: return "Expired"
        case .completed: return "Done"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .accepted, .declined, .expired, .completed:
            return true
        case .matchFound,
             .qualifying,
             .awaitingProviderClarification,
             .awaitingRequesterClarification,
             .providerReview,
             .requesterReview,
             .decisionReady,
             .awaitingCommitmentApproval,
             .stalled,
             .blocked:
            return false
        }
    }

    var isAwaitingClarification: Bool {
        switch self {
        case .awaitingProviderClarification, .awaitingRequesterClarification:
            return true
        default:
            return false
        }
    }

    var isHumanReviewState: Bool {
        switch self {
        case .providerReview,
             .requesterReview,
             .decisionReady,
             .awaitingCommitmentApproval,
             .blocked:
            return true
        case .matchFound,
             .qualifying,
             .awaitingProviderClarification,
             .awaitingRequesterClarification,
             .accepted,
             .declined,
             .stalled,
             .expired,
             .completed:
            return false
        }
    }

    var canProgressAutonomously: Bool {
        switch self {
        case .matchFound,
             .qualifying,
             .awaitingProviderClarification,
             .awaitingRequesterClarification,
             .stalled:
            return true
        case .providerReview,
             .requesterReview,
             .decisionReady,
             .awaitingCommitmentApproval,
             .blocked,
             .accepted,
             .declined,
             .expired,
             .completed:
            return false
        }
    }
}
