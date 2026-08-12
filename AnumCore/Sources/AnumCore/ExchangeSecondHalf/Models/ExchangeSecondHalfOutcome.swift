import Foundation

public enum ExchangeSecondHalfOutcomeType: String, Codable, CaseIterable, Hashable, Sendable {
    case progressed
    case accepted
    case declined
    case stalled
    case blocked
    case expired
    case completed
}

public enum ExchangeExternalEffect: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case internalOnly
    case outboundDraftPrepared
    case outboundMessageSent
    case commitmentRecorded
}

/// End or intermediate meaningful outcome.
///
/// This keeps second-half state and user-facing outcome legible, especially
/// around "what happened" vs "what did not happen".
public struct ExchangeSecondHalfOutcome: Codable, Hashable, Sendable {
    public var outcomeType: ExchangeSecondHalfOutcomeType
    public var externalEffect: ExchangeExternalEffect
    public var whatHappened: String
    public var whatDidNotHappen: String
    public var userActionStillNeeded: Bool
    public var recommendedRecovery: String?

    public init(
        outcomeType: ExchangeSecondHalfOutcomeType,
        externalEffect: ExchangeExternalEffect,
        whatHappened: String,
        whatDidNotHappen: String,
        userActionStillNeeded: Bool,
        recommendedRecovery: String? = nil
    ) {
        self.outcomeType = outcomeType
        self.externalEffect = externalEffect
        self.whatHappened = whatHappened
        self.whatDidNotHappen = whatDidNotHappen
        self.userActionStillNeeded = userActionStillNeeded
        self.recommendedRecovery = recommendedRecovery
    }
}

public extension ExchangeSecondHalfOutcome {
    static func progressed(
        happened: String,
        didNotHappen: String = "",
        externalEffect: ExchangeExternalEffect = .internalOnly,
        userActionStillNeeded: Bool = false
    ) -> ExchangeSecondHalfOutcome {
        ExchangeSecondHalfOutcome(
            outcomeType: .progressed,
            externalEffect: externalEffect,
            whatHappened: happened,
            whatDidNotHappen: didNotHappen,
            userActionStillNeeded: userActionStillNeeded,
            recommendedRecovery: nil
        )
    }

    static func blocked(
        happened: String,
        didNotHappen: String,
        recovery: String?
    ) -> ExchangeSecondHalfOutcome {
        ExchangeSecondHalfOutcome(
            outcomeType: .blocked,
            externalEffect: .none,
            whatHappened: happened,
            whatDidNotHappen: didNotHappen,
            userActionStillNeeded: true,
            recommendedRecovery: recovery
        )
    }

    var isTerminal: Bool {
        switch outcomeType {
        case .accepted, .declined, .expired, .completed:
            return true
        case .progressed, .stalled, .blocked:
            return false
        }
    }
}
