import Foundation

/// Canonical user-facing decision packet.
///
/// This is what the secretary should ultimately surface instead of raw
/// thread messages when the thread is mature enough to present meaningfully.
public struct ExchangeDecisionFrame: Codable, Hashable, Sendable {
    public var summary: String
    public var clarifiedFacts: [String]
    public var whatChanged: [String]
    public var unresolvedIssues: [String]
    public var recommendation: String
    public var tradeoffs: [String]
    public var nextMove: ExchangeSecondHalfAction?
    public var needsUserJudgment: Bool
    public var needsCommitmentApproval: Bool

    public init(
        summary: String = "",
        clarifiedFacts: [String] = [],
        whatChanged: [String] = [],
        unresolvedIssues: [String] = [],
        recommendation: String = "",
        tradeoffs: [String] = [],
        nextMove: ExchangeSecondHalfAction? = nil,
        needsUserJudgment: Bool = false,
        needsCommitmentApproval: Bool = false
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
    }
}

public extension ExchangeDecisionFrame {
    static let empty = ExchangeDecisionFrame()

    var isActionable: Bool {
        nextMove != nil || needsUserJudgment || needsCommitmentApproval
    }

    var hasOpenIssues: Bool {
        !unresolvedIssues.isEmpty
    }

    var hasMeaningfulContent: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !clarifiedFacts.isEmpty ||
        !whatChanged.isEmpty ||
        !recommendation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
