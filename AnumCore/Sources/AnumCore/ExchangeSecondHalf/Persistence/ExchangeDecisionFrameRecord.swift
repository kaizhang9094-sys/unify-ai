import Foundation

/// Durable decision frame record.
///
/// Stores the latest user-facing decision frame in a persistence-friendly form.
public struct ExchangeDecisionFrameRecord: Codable, Hashable, Sendable {
    public var threadID: UUID
    public var role: ExchangeSecondHalfRole
    public var savedAt: Date

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
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        savedAt: Date = Date(),
        summary: String,
        clarifiedFacts: [String] = [],
        whatChanged: [String] = [],
        unresolvedIssues: [String] = [],
        recommendation: String,
        tradeoffs: [String] = [],
        nextMove: ExchangeSecondHalfAction? = nil,
        needsUserJudgment: Bool,
        needsCommitmentApproval: Bool
    ) {
        self.threadID = threadID
        self.role = role
        self.savedAt = savedAt
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

public extension ExchangeDecisionFrameRecord {
    init(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        frame: ExchangeDecisionFrame,
        savedAt: Date = Date()
    ) {
        self.init(
            threadID: threadID,
            role: role,
            savedAt: savedAt,
            summary: frame.summary,
            clarifiedFacts: frame.clarifiedFacts,
            whatChanged: frame.whatChanged,
            unresolvedIssues: frame.unresolvedIssues,
            recommendation: frame.recommendation,
            tradeoffs: frame.tradeoffs,
            nextMove: frame.nextMove,
            needsUserJudgment: frame.needsUserJudgment,
            needsCommitmentApproval: frame.needsCommitmentApproval
        )
    }

    func asDomainModel() -> ExchangeDecisionFrame {
        ExchangeDecisionFrame(
            summary: summary,
            clarifiedFacts: clarifiedFacts,
            whatChanged: whatChanged,
            unresolvedIssues: unresolvedIssues,
            recommendation: recommendation,
            tradeoffs: tradeoffs,
            nextMove: nextMove,
            needsUserJudgment: needsUserJudgment,
            needsCommitmentApproval: needsCommitmentApproval
        )
    }
}
