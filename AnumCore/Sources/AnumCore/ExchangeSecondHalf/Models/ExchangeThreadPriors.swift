import Foundation

/// Compact thread-local priors bundle.
///
/// This exists to avoid replaying full thread history while still preserving
/// the thread’s evolving memory for second-half reasoning.
public struct ExchangeThreadPriors: Codable, Hashable, Sendable {
    public var priorQuestionsAsked: [String]
    public var priorAnswersReceived: [String]
    public var currentConstraints: [String]
    public var priorNonCommitments: [String]
    public var lastKnownRecommendation: String?
    public var latestDelta: ExchangeThreadDelta?
    public var threadStanceSnapshot: ExchangeThreadStance?

    public init(
        priorQuestionsAsked: [String] = [],
        priorAnswersReceived: [String] = [],
        currentConstraints: [String] = [],
        priorNonCommitments: [String] = [],
        lastKnownRecommendation: String? = nil,
        latestDelta: ExchangeThreadDelta? = nil,
        threadStanceSnapshot: ExchangeThreadStance? = nil
    ) {
        self.priorQuestionsAsked = priorQuestionsAsked
        self.priorAnswersReceived = priorAnswersReceived
        self.currentConstraints = currentConstraints
        self.priorNonCommitments = priorNonCommitments
        self.lastKnownRecommendation = lastKnownRecommendation
        self.latestDelta = latestDelta
        self.threadStanceSnapshot = threadStanceSnapshot
    }
}

public extension ExchangeThreadPriors {
    static let empty = ExchangeThreadPriors()

    var hasQuestionHistory: Bool {
        !priorQuestionsAsked.isEmpty
    }

    var hasAnswerHistory: Bool {
        !priorAnswersReceived.isEmpty
    }

    var hasConstraints: Bool {
        !currentConstraints.isEmpty
    }

    var hasNonCommitments: Bool {
        !priorNonCommitments.isEmpty
    }

    var hasRecommendationContext: Bool {
        if let lastKnownRecommendation {
            return !lastKnownRecommendation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    var hasMeaningfulContext: Bool {
        hasQuestionHistory ||
        hasAnswerHistory ||
        hasConstraints ||
        hasNonCommitments ||
        hasRecommendationContext ||
        latestDelta != nil ||
        threadStanceSnapshot != nil
    }
}
