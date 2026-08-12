import Foundation

/// Requester-side logical pause after a provider message — projection artifact only (does not own thread state).
public enum ExchangeRequesterFitMovement: String, Codable, CaseIterable, Hashable, Sendable {
    case improved
    case weakened
    case unchanged
    case unclear
}

public enum ExchangeRequesterPauseReason: String, Codable, CaseIterable, Hashable, Sendable {
    case waitingForRequesterDecision
    case waitingForRequesterInput
    case waitingForProviderReply
    case needsOneMoreClarification
    case weakFitKeepSearching
    case commitmentReview
    case blockedNeedsCare
    case completed
}

public struct ExchangeRequesterPauseFrame: Codable, Hashable, Sendable {
    public var answeredFacts: [String]
    public var resolvedMissingLabels: [String]
    public var stillMissingFacts: [String]
    public var providerQuestions: [String]
    public var commitmentSignals: [String]
    public var weakeningSignals: [String]
    public var fitMovement: ExchangeRequesterFitMovement
    public var pauseReason: ExchangeRequesterPauseReason
    public var summaryLine: String
    public var recommendationLine: String
    public var nextActionLabel: String
    public var canContinueOnReply: Bool

    public init(
        answeredFacts: [String] = [],
        resolvedMissingLabels: [String] = [],
        stillMissingFacts: [String] = [],
        providerQuestions: [String] = [],
        commitmentSignals: [String] = [],
        weakeningSignals: [String] = [],
        fitMovement: ExchangeRequesterFitMovement = .unclear,
        pauseReason: ExchangeRequesterPauseReason = .needsOneMoreClarification,
        summaryLine: String = "",
        recommendationLine: String = "",
        nextActionLabel: String = "",
        canContinueOnReply: Bool = true
    ) {
        self.answeredFacts = answeredFacts
        self.resolvedMissingLabels = resolvedMissingLabels
        self.stillMissingFacts = stillMissingFacts
        self.providerQuestions = providerQuestions
        self.commitmentSignals = commitmentSignals
        self.weakeningSignals = weakeningSignals
        self.fitMovement = fitMovement
        self.pauseReason = pauseReason
        self.summaryLine = summaryLine
        self.recommendationLine = recommendationLine
        self.nextActionLabel = nextActionLabel
        self.canContinueOnReply = canContinueOnReply
    }
}
