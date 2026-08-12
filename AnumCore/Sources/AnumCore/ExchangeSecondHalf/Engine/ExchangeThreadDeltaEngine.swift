import Foundation

/// Cheap change-tracking engine.
///
/// Compares previous and current qualification, stance, and recommendation
/// so the system can explain what changed without expensive reasoning.
public struct ExchangeThreadDeltaEngine: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var previousQualification: ExchangeOpportunityQualification?
        public var currentQualification: ExchangeOpportunityQualification
        public var previousStance: ExchangeThreadStance?
        public var currentStance: ExchangeThreadStance
        public var previousRecommendation: String?
        public var currentRecommendation: String?

        public init(
            previousQualification: ExchangeOpportunityQualification? = nil,
            currentQualification: ExchangeOpportunityQualification,
            previousStance: ExchangeThreadStance? = nil,
            currentStance: ExchangeThreadStance,
            previousRecommendation: String? = nil,
            currentRecommendation: String? = nil
        ) {
            self.previousQualification = previousQualification
            self.currentQualification = currentQualification
            self.previousStance = previousStance
            self.currentStance = currentStance
            self.previousRecommendation = previousRecommendation
            self.currentRecommendation = currentRecommendation
        }
    }

    public func calculate(
        input: Input
    ) -> ExchangeThreadDelta {
        let newFacts = newFactsLearned(
            previous: input.previousQualification?.missingFacts ?? [],
            current: input.currentQualification.missingFacts,
            currentStrengthReasons: input.currentQualification.strengthReasons
        )

        let riskChange = compareRisk(
            previous: input.previousQualification,
            current: input.currentQualification
        )

        let readinessShift = compareReadiness(
            previous: input.previousStance,
            current: input.currentStance
        )

        let recommendationChanged = normalized(input.previousRecommendation) != normalized(input.currentRecommendation)
        let nextStepChanged = input.previousStance?.recommendedNextMove != input.currentStance.recommendedNextMove

        let explanation = buildSignificanceExplanation(
            newFacts: newFacts,
            riskChange: riskChange,
            readinessShift: readinessShift,
            recommendationChanged: recommendationChanged,
            nextStepChanged: nextStepChanged
        )

        return ExchangeThreadDelta(
            newFactsLearned: newFacts,
            riskChange: riskChange,
            readinessShift: readinessShift,
            recommendationChanged: recommendationChanged,
            nextStepChanged: nextStepChanged,
            significanceExplanation: explanation
        )
    }

    private func newFactsLearned(
        previous: [String],
        current: [String],
        currentStrengthReasons: [String]
    ) -> [String] {
        let previousSet = Set(cleaned(previous))
        let currentStrengths = cleaned(currentStrengthReasons)

        // We treat newly emerged strength reasons as the most useful cheap proxy
        // for "what new useful facts did we learn?"
        return currentStrengths.filter { !previousSet.contains($0) }
    }

    private func compareRisk(
        previous: ExchangeOpportunityQualification?,
        current: ExchangeOpportunityQualification
    ) -> ExchangeDirectionOfChange {
        guard let previous else {
            return current.qualityTier == .weak ? .unchanged : .decreased
        }

        let previousScore = riskScore(for: previous)
        let currentScore = riskScore(for: current)

        if currentScore > previousScore { return .increased }
        if currentScore < previousScore { return .decreased }
        return .unchanged
    }

    private func compareReadiness(
        previous: ExchangeThreadStance?,
        current: ExchangeThreadStance
    ) -> ExchangeDirectionOfChange {
        guard let previous else {
            return current.readinessLevel == .weak || current.readinessLevel == .incomplete ? .unchanged : .increased
        }

        let previousScore = readinessScore(previous.readinessLevel)
        let currentScore = readinessScore(current.readinessLevel)

        if currentScore > previousScore { return .increased }
        if currentScore < previousScore { return .decreased }
        return .unchanged
    }

    private func buildSignificanceExplanation(
        newFacts: [String],
        riskChange: ExchangeDirectionOfChange,
        readinessShift: ExchangeDirectionOfChange,
        recommendationChanged: Bool,
        nextStepChanged: Bool
    ) -> String {
        var parts: [String] = []

        if !newFacts.isEmpty {
            parts.append("New useful facts were surfaced.")
        }

        switch riskChange {
        case .increased:
            parts.append("Thread risk increased.")
        case .decreased:
            parts.append("Thread risk decreased.")
        case .unchanged:
            break
        }

        switch readinessShift {
        case .increased:
            parts.append("The thread moved closer to decision.")
        case .decreased:
            parts.append("The thread became less decision-ready.")
        case .unchanged:
            break
        }

        if recommendationChanged {
            parts.append("The recommendation changed.")
        }

        if nextStepChanged {
            parts.append("The recommended next step changed.")
        }

        return parts.joined(separator: " ")
    }

    private func riskScore(for qualification: ExchangeOpportunityQualification) -> Int {
        switch qualification.qualityTier {
        case .decisionReady: return 0
        case .strong: return 1
        case .promising: return 2
        case .weak: return 3
        }
    }

    private func readinessScore(_ level: ExchangeReadinessLevel) -> Int {
        switch level {
        case .weak: return 0
        case .incomplete: return 1
        case .promising: return 2
        case .decisionReady: return 3
        case .commitmentReady: return 4
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleaned(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
