import Foundation

/// UI-facing projection of the recommended next move.
///
/// This is intentionally simple and stable so the UI can always show:
/// - what the secretary wants to do next
/// - why
/// - whether user input or approval is needed
public struct ExchangeNextMoveViewModel: Codable, Hashable, Sendable {
    public var action: ExchangeSecondHalfAction
    public var title: String
    public var rationale: String
    public var requiredInputs: [String]
    public var needsGeneration: Bool
    public var needsUserInput: Bool
    public var needsApproval: Bool

    public init(
        action: ExchangeSecondHalfAction,
        title: String,
        rationale: String,
        requiredInputs: [String] = [],
        needsGeneration: Bool,
        needsUserInput: Bool,
        needsApproval: Bool
    ) {
        self.action = action
        self.title = title
        self.rationale = rationale
        self.requiredInputs = requiredInputs
        self.needsGeneration = needsGeneration
        self.needsUserInput = needsUserInput
        self.needsApproval = needsApproval
    }
}

public extension ExchangeNextMoveViewModel {
    init(plan: ExchangeSecondHalfPlan) {
        self.init(
            action: plan.selectedAction,
            title: plan.selectedAction.displayTitle,
            rationale: plan.rationale,
            requiredInputs: plan.requiredInputs,
            needsGeneration: plan.needsGeneration,
            needsUserInput: plan.needsUserInput,
            needsApproval: plan.needsApproval
        )
    }

    var isAutonomous: Bool {
        !needsUserInput && !needsApproval
    }

    var isBlockingOnHuman: Bool {
        needsUserInput || needsApproval
    }
}
