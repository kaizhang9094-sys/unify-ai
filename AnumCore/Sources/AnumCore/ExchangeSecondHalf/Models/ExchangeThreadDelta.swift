import Foundation

public enum ExchangeDirectionOfChange: String, Codable, CaseIterable, Hashable, Sendable {
    case increased
    case decreased
    case unchanged
}

/// Tracks what changed since the last meaningful thread point.
///
/// This powers cheap but high-value change-aware guidance.
public struct ExchangeThreadDelta: Codable, Hashable, Sendable {
    public var newFactsLearned: [String]
    public var riskChange: ExchangeDirectionOfChange
    public var readinessShift: ExchangeDirectionOfChange
    public var recommendationChanged: Bool
    public var nextStepChanged: Bool
    public var significanceExplanation: String

    public init(
        newFactsLearned: [String] = [],
        riskChange: ExchangeDirectionOfChange = .unchanged,
        readinessShift: ExchangeDirectionOfChange = .unchanged,
        recommendationChanged: Bool = false,
        nextStepChanged: Bool = false,
        significanceExplanation: String = ""
    ) {
        self.newFactsLearned = newFactsLearned
        self.riskChange = riskChange
        self.readinessShift = readinessShift
        self.recommendationChanged = recommendationChanged
        self.nextStepChanged = nextStepChanged
        self.significanceExplanation = significanceExplanation
    }
}

public extension ExchangeThreadDelta {
    static let none = ExchangeThreadDelta()

    var hasMeaningfulChange: Bool {
        !newFactsLearned.isEmpty ||
        riskChange != .unchanged ||
        readinessShift != .unchanged ||
        recommendationChanged ||
        nextStepChanged ||
        !significanceExplanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
