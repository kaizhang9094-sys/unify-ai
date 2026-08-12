import Foundation

/// First-class qualification logic for the second half.
///
/// Decides whether the opportunity is weak, promising, strong, or decision-ready,
/// what is missing, whether one more clarification is worthwhile, and whether
/// the thread is good enough to surface now.
public struct ExchangeOpportunityQualifier: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var role: ExchangeSecondHalfRole
        public var priors: ExchangeThreadPriors
        public var operatingMemory: ExchangeStructuredOperatingMemory
        public var threadState: ExchangeSecondHalfState
        public var knownFacts: [String]
        public var unresolvedIssues: [String]
        public var surfacedCandidateCount: Int
        public var hasDecisionFrame: Bool

        public init(
            role: ExchangeSecondHalfRole,
            priors: ExchangeThreadPriors,
            operatingMemory: ExchangeStructuredOperatingMemory,
            threadState: ExchangeSecondHalfState,
            knownFacts: [String] = [],
            unresolvedIssues: [String] = [],
            surfacedCandidateCount: Int = 1,
            hasDecisionFrame: Bool = false
        ) {
            self.role = role
            self.priors = priors
            self.operatingMemory = operatingMemory
            self.threadState = threadState
            self.knownFacts = knownFacts
            self.unresolvedIssues = unresolvedIssues
            self.surfacedCandidateCount = surfacedCandidateCount
            self.hasDecisionFrame = hasDecisionFrame
        }
    }

    public struct Result: Sendable {
        public var qualification: ExchangeOpportunityQualification
        public var shouldSurfaceNow: Bool

        public init(
            qualification: ExchangeOpportunityQualification,
            shouldSurfaceNow: Bool
        ) {
            self.qualification = qualification
            self.shouldSurfaceNow = shouldSurfaceNow
        }
    }

    public func evaluate(
        input: Input,
        policy: ExchangeSecondHalfPolicy
    ) -> Result {
        let knownFacts = cleaned(input.knownFacts)
        let unresolved = cleaned(input.unresolvedIssues)

        let missingFacts = unresolved
        var strengthReasons: [String] = []
        var weaknessReasons: [String] = []

        if !knownFacts.isEmpty {
            strengthReasons.append("Has enough thread detail to work with.")
        }

        if input.surfacedCandidateCount > 0 {
            strengthReasons.append("A published listing or profile is in play.")
        } else {
            weaknessReasons.append("No provider path is locked in yet.")
        }

        if let stance = input.priors.threadStanceSnapshot {
            switch stance.readinessLevel {
            case .promising, .decisionReady, .commitmentReady:
                strengthReasons.append("Conversation is moving forward.")
            case .weak, .incomplete:
                weaknessReasons.append("Thread needs a bit more back-and-forth.")
            }
        }

        if input.role == .provider && input.operatingMemory.hasProviderFacts {
            strengthReasons.append("Published details support routine answers.")
        }

        if input.role == .requester && input.operatingMemory.hasRequesterConstraints {
            strengthReasons.append("Your request includes clear preferences.")
        }

        let qualityTier: ExchangeOpportunityQualityTier
        let status: ExchangeQualificationStatus
        let oneMoreClarificationWorthwhile: Bool

        if missingFacts.isEmpty && (input.hasDecisionFrame || isDecisionReadyByThreadState(input.threadState)) {
            qualityTier = .decisionReady
            status = .decisionReady
            oneMoreClarificationWorthwhile = false
        } else if missingFacts.isEmpty && knownFacts.count >= 2 {
            qualityTier = .strong
            status = .qualified
            oneMoreClarificationWorthwhile = false
        } else if !missingFacts.isEmpty && missingFacts.count <= policy.clarificationRoundLimit {
            qualityTier = .promising
            status = .needsClarification
            oneMoreClarificationWorthwhile = true
        } else if !missingFacts.isEmpty {
            qualityTier = .weak
            status = .incomplete
            oneMoreClarificationWorthwhile = false
            weaknessReasons.append("Several details still need clearing up.")
        } else {
            qualityTier = .promising
            status = .qualified
            oneMoreClarificationWorthwhile = false
        }

        if qualityTier == .decisionReady {
            strengthReasons.append("Enough detail to shape a recommendation.")
        }

        if qualityTier == .weak && missingFacts.isEmpty && knownFacts.isEmpty {
            weaknessReasons.append("Not enough evidence yet to recommend.")
        }

        let qualification = ExchangeOpportunityQualification(
            qualityTier: qualityTier,
            missingFacts: missingFacts,
            strengthReasons: strengthReasons,
            weaknessReasons: weaknessReasons,
            qualificationStatus: status,
            isOneMoreClarificationWorthwhile: oneMoreClarificationWorthwhile
        )

        return Result(
            qualification: qualification,
            shouldSurfaceNow: policy.maySurface(qualification: qualification)
        )
    }

    private func isDecisionReadyByThreadState(_ state: ExchangeSecondHalfState) -> Bool {
        switch state {
        case .decisionReady, .awaitingCommitmentApproval, .accepted, .completed:
            return true
        case .matchFound,
             .qualifying,
             .awaitingProviderClarification,
             .awaitingRequesterClarification,
             .providerReview,
             .requesterReview,
             .declined,
             .stalled,
             .blocked,
             .expired:
            return false
        }
    }

    private func cleaned(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }

        return result
    }
}
