import Foundation

/// Structured internal plan for the next move.
///
/// This keeps orchestration explicit and inspectable, instead of letting the
/// coordinator become an opaque pile of if-statements.
public struct ExchangeSecondHalfPlan: Codable, Hashable, Sendable {
    public var selectedAction: ExchangeSecondHalfAction
    public var role: ExchangeSecondHalfRole
    public var rationale: String
    public var requiredInputs: [String]
    public var needsGeneration: Bool
    public var needsUserInput: Bool
    public var needsApproval: Bool

    public init(
        selectedAction: ExchangeSecondHalfAction,
        role: ExchangeSecondHalfRole,
        rationale: String,
        requiredInputs: [String] = [],
        needsGeneration: Bool? = nil,
        needsUserInput: Bool? = nil,
        needsApproval: Bool = false
    ) {
        self.selectedAction = selectedAction
        self.role = role
        self.rationale = rationale
        self.requiredInputs = requiredInputs
        self.needsGeneration = needsGeneration ?? selectedAction.usuallyNeedsGeneration
        self.needsUserInput = needsUserInput ?? selectedAction.usuallyNeedsUserInput
        self.needsApproval = needsApproval
    }
}

public extension ExchangeSecondHalfPlan {
    var isAutonomous: Bool {
        !needsUserInput && !needsApproval
    }

    var isReadyToExecute: Bool {
        requiredInputs.isEmpty
    }

    static func qualify(
        role: ExchangeSecondHalfRole,
        rationale: String
    ) -> ExchangeSecondHalfPlan {
        ExchangeSecondHalfPlan(
            selectedAction: .qualifyMatch,
            role: role,
            rationale: rationale,
            requiredInputs: [],
            needsGeneration: false,
            needsUserInput: false,
            needsApproval: false
        )
    }

    static func requestInput(
        role: ExchangeSecondHalfRole,
        rationale: String,
        requiredInputs: [String]
    ) -> ExchangeSecondHalfPlan {
        ExchangeSecondHalfPlan(
            selectedAction: .requestUserInput,
            role: role,
            rationale: rationale,
            requiredInputs: requiredInputs,
            needsGeneration: false,
            needsUserInput: true,
            needsApproval: false
        )
    }

    static func escalate(
        role: ExchangeSecondHalfRole,
        rationale: String
    ) -> ExchangeSecondHalfPlan {
        ExchangeSecondHalfPlan(
            selectedAction: .escalateForApproval,
            role: role,
            rationale: rationale,
            requiredInputs: [],
            needsGeneration: false,
            needsUserInput: true,
            needsApproval: true
        )
    }
}
