import Foundation

/// Canonical legal moves in the second half.
///
/// Natural language stays on the surface, but the engine should always reduce
/// the thread to one of these structured actions underneath.
public enum ExchangeSecondHalfAction: String, Codable, CaseIterable, Hashable, Sendable {
    case qualifyMatch
    case askClarification
    case answerClarification
    case requestUserInput
    case autoRespond
    case frameDecision
    case recommendNextMove
    case compareOptions
    case proposeTerms
    case reviseTerms
    case escalateForApproval
    case accept
    case decline
    case pause
    case markBlocked
    case markStalled
    case complete
}

public extension ExchangeSecondHalfAction {
    /// Human-readable labels for UI — raw enum strings stay in `rawValue` for persistence.
    var displayTitle: String {
        switch self {
        case .qualifyMatch: return "Review match"
        case .askClarification: return "Ask a question"
        case .answerClarification: return "Answer"
        case .requestUserInput: return "Needs your input"
        case .autoRespond: return "Continue"
        case .frameDecision: return "Prepare decision"
        case .recommendNextMove: return "Suggest next step"
        case .compareOptions: return "Compare options"
        case .proposeTerms: return "Propose terms"
        case .reviseTerms: return "Revise terms"
        case .escalateForApproval: return "Needs approval"
        case .accept: return "Accept"
        case .decline: return "Decline"
        case .pause: return "Pause"
        case .markBlocked: return "Blocked"
        case .markStalled: return "Paused"
        case .complete: return "Complete"
        }
    }

    var isTerminalAction: Bool {
        switch self {
        case .accept, .decline, .complete:
            return true
        case .qualifyMatch,
             .askClarification,
             .answerClarification,
             .requestUserInput,
             .autoRespond,
             .frameDecision,
             .recommendNextMove,
             .compareOptions,
             .proposeTerms,
             .reviseTerms,
             .escalateForApproval,
             .pause,
             .markBlocked,
             .markStalled:
            return false
        }
    }

    var usuallyNeedsGeneration: Bool {
        switch self {
        case .askClarification,
             .answerClarification,
             .autoRespond,
             .frameDecision,
             .recommendNextMove,
             .proposeTerms,
             .reviseTerms:
            return true
        case .qualifyMatch,
             .requestUserInput,
             .compareOptions,
             .escalateForApproval,
             .accept,
             .decline,
             .pause,
             .markBlocked,
             .markStalled,
             .complete:
            return false
        }
    }

    var usuallyNeedsUserInput: Bool {
        switch self {
        case .requestUserInput, .accept, .decline:
            return true
        case .qualifyMatch,
             .askClarification,
             .answerClarification,
             .autoRespond,
             .frameDecision,
             .recommendNextMove,
             .compareOptions,
             .proposeTerms,
             .reviseTerms,
             .escalateForApproval,
             .pause,
             .markBlocked,
             .markStalled,
             .complete:
            return false
        }
    }

    var isClarificationAction: Bool {
        switch self {
        case .askClarification, .answerClarification:
            return true
        default:
            return false
        }
    }

    var isDecisionShapingAction: Bool {
        switch self {
        case .frameDecision, .recommendNextMove, .compareOptions, .proposeTerms, .reviseTerms:
            return true
        default:
            return false
        }
    }

    var isEscalationAction: Bool {
        switch self {
        case .requestUserInput, .escalateForApproval, .markBlocked:
            return true
        default:
            return false
        }
    }
}
