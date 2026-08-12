import Foundation

public enum ExchangeAgencyAutonomyDisposition: String, Codable, Hashable, Sendable {
    case allowAutonomousOutbound
    case holdForUserInput
    case holdForApproval
    case holdForCounterparty
    case wait
    case blocked
}

public struct ExchangeAgencyDecision: Codable, Hashable, Sendable {
    public var recommendedAction: ExchangeSecondHalfAction?
    public var autonomyDisposition: ExchangeAgencyAutonomyDisposition
    public var requiresUserApproval: Bool
    public var requiresUserInput: Bool
    public var blockReasons: [String]
    public var permitReasons: [String]

    public init(
        recommendedAction: ExchangeSecondHalfAction? = nil,
        autonomyDisposition: ExchangeAgencyAutonomyDisposition = .holdForUserInput,
        requiresUserApproval: Bool = false,
        requiresUserInput: Bool = true,
        blockReasons: [String] = [],
        permitReasons: [String] = []
    ) {
        self.recommendedAction = recommendedAction
        self.autonomyDisposition = autonomyDisposition
        self.requiresUserApproval = requiresUserApproval
        self.requiresUserInput = requiresUserInput
        self.blockReasons = blockReasons
        self.permitReasons = permitReasons
    }

    public static let conservativeDefault = ExchangeAgencyDecision(
        recommendedAction: nil,
        autonomyDisposition: .holdForUserInput,
        requiresUserApproval: false,
        requiresUserInput: true,
        blockReasons: ["missing_agency_decision"],
        permitReasons: []
    )
}
