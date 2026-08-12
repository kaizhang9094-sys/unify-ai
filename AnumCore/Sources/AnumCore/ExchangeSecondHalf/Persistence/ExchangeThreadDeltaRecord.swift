import Foundation

/// Durable change-tracking record.
///
/// Stores the compact delta object used for change-aware thread guidance.
public struct ExchangeThreadDeltaRecord: Codable, Hashable, Sendable {
    public var threadID: UUID
    public var role: ExchangeSecondHalfRole
    public var savedAt: Date

    public var newFactsLearned: [String]
    public var riskChange: ExchangeDirectionOfChange
    public var readinessShift: ExchangeDirectionOfChange
    public var recommendationChanged: Bool
    public var nextStepChanged: Bool
    public var significanceExplanation: String

    public init(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        savedAt: Date = Date(),
        newFactsLearned: [String] = [],
        riskChange: ExchangeDirectionOfChange = .unchanged,
        readinessShift: ExchangeDirectionOfChange = .unchanged,
        recommendationChanged: Bool = false,
        nextStepChanged: Bool = false,
        significanceExplanation: String = ""
    ) {
        self.threadID = threadID
        self.role = role
        self.savedAt = savedAt
        self.newFactsLearned = newFactsLearned
        self.riskChange = riskChange
        self.readinessShift = readinessShift
        self.recommendationChanged = recommendationChanged
        self.nextStepChanged = nextStepChanged
        self.significanceExplanation = significanceExplanation
    }
}

public extension ExchangeThreadDeltaRecord {
    init(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        delta: ExchangeThreadDelta,
        savedAt: Date = Date()
    ) {
        self.init(
            threadID: threadID,
            role: role,
            savedAt: savedAt,
            newFactsLearned: delta.newFactsLearned,
            riskChange: delta.riskChange,
            readinessShift: delta.readinessShift,
            recommendationChanged: delta.recommendationChanged,
            nextStepChanged: delta.nextStepChanged,
            significanceExplanation: delta.significanceExplanation
        )
    }

    func asDomainModel() -> ExchangeThreadDelta {
        ExchangeThreadDelta(
            newFactsLearned: newFactsLearned,
            riskChange: riskChange,
            readinessShift: readinessShift,
            recommendationChanged: recommendationChanged,
            nextStepChanged: nextStepChanged,
            significanceExplanation: significanceExplanation
        )
    }
}
