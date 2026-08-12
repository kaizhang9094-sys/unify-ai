import Foundation

/// Durable goal contract for an exchange thread.
///
/// Intent says what the user is asking for.
/// Posture says how the secretary should carry the user.
/// Expectation says what counts as progress, success, and when autonomous
/// continuation must stop.
public struct ExchangeExpectation: Codable, Sendable, Hashable {
    public var primaryGoal: PrimaryGoal
    public var preferredOutcome: OutcomeTarget
    public var acceptableOutcome: OutcomeTarget

    /// High-level market shape for the thread.
    /// This helps the system distinguish local services, shipped goods,
    /// digital work, and relationship-driven exchanges.
    public var marketType: MarketType

    /// Fulfillment expectation for the thread.
    /// Example:
    /// - nearby food or a contractor visit => localOnly / localPreferred
    /// - physical goods => shippable
    /// - software or design help => remoteFriendly / digitalDelivery
    public var fulfillmentMode: FulfillmentMode

    /// Coarse risk/materiality level.
    /// Used to keep autonomy small for costly or consequential exchanges.
    public var riskLevel: RiskLevel

    /// Whether nearby/local options should be preferred first.
    public var prefersLocalFirst: Bool

    /// Whether remote, shipped, or non-local fulfillment is acceptable.
    public var allowsRemoteOrShipped: Bool

    /// Whether the system may handle a small amount of routine clarification
    /// without immediately stopping for the user.
    public var allowsAutonomousClarification: Bool

    public var completionSignals: [CompletionSignal]
    public var stopConditions: [StopCondition]
    public var maxAutoReplies: Int
    public var autoReplyCount: Int

    /// Separate budget for clarification-only continuation.
    ///
    /// This should usually be 0 or 1.
    public var maxAutonomousClarifications: Int
    public var autonomousClarificationCount: Int

    public var requiresUserDecisionOn: [UserDecisionTrigger]
    public var notes: String?

    public init(
        primaryGoal: PrimaryGoal,
        preferredOutcome: OutcomeTarget,
        acceptableOutcome: OutcomeTarget,
        marketType: MarketType = .unknown,
        fulfillmentMode: FulfillmentMode = .unknown,
        riskLevel: RiskLevel = .moderate,
        prefersLocalFirst: Bool = false,
        allowsRemoteOrShipped: Bool = false,
        allowsAutonomousClarification: Bool = false,
        completionSignals: [CompletionSignal] = [],
        stopConditions: [StopCondition] = [],
        maxAutoReplies: Int = 0,
        autoReplyCount: Int = 0,
        maxAutonomousClarifications: Int = 0,
        autonomousClarificationCount: Int = 0,
        requiresUserDecisionOn: [UserDecisionTrigger] = [],
        notes: String? = nil
    ) {
        self.primaryGoal = primaryGoal
        self.preferredOutcome = preferredOutcome
        self.acceptableOutcome = acceptableOutcome
        self.marketType = marketType
        self.fulfillmentMode = fulfillmentMode
        self.riskLevel = riskLevel
        self.prefersLocalFirst = prefersLocalFirst
        self.allowsRemoteOrShipped = allowsRemoteOrShipped
        self.allowsAutonomousClarification = allowsAutonomousClarification
        self.completionSignals = Self.normalizedUnique(completionSignals)
        self.stopConditions = Self.normalizedUnique(stopConditions)
        self.maxAutoReplies = max(0, maxAutoReplies)
        self.autoReplyCount = max(0, autoReplyCount)
        self.maxAutonomousClarifications = max(0, maxAutonomousClarifications)
        self.autonomousClarificationCount = max(0, autonomousClarificationCount)
        self.requiresUserDecisionOn = Self.normalizedUnique(requiresUserDecisionOn)
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

public extension ExchangeExpectation {
    enum PrimaryGoal: String, Codable, Sendable, CaseIterable, Hashable {
        case obtainQuote
        case establishContact
        case secureIntroduction
        case arrangeCall
        case arrangeMeeting
        case gatherInformation
        case confirmAvailability
        case confirmFit
        case advanceNegotiation
        case resolveThread
        case other
    }

    enum OutcomeTarget: String, Codable, Sendable, CaseIterable, Hashable {
        case completed
        case meaningfulProgress
        case basicResponse
    }

    enum MarketType: String, Codable, Sendable, CaseIterable, Hashable {
        case localService
        case physicalGoods
        case digitalService
        case informationRequest
        case relationshipLed
        case unknown
    }

    enum FulfillmentMode: String, Codable, Sendable, CaseIterable, Hashable {
        case localOnly
        case localPreferred
        case shippable
        case remoteFriendly
        case digitalDelivery
        case unknown
    }

    enum RiskLevel: String, Codable, Sendable, CaseIterable, Hashable {
        case low
        case moderate
        case high
    }

    enum CompletionSignal: String, Codable, Sendable, CaseIterable, Hashable {
        case quoteReceived
        case introAccepted
        case introDeclined
        case availabilityConfirmed
        case meetingProposed
        case meetingConfirmed
        case answerReceived
        case capabilityConfirmed
        case capabilityDeclined
        case scopeClarified
        case termsAccepted
        case explicitDecline
        case resolvedByUser
    }

    enum StopCondition: String, Codable, Sendable, CaseIterable, Hashable {
        case autoReplyBudgetExhausted
        case counterpartyRequestsSensitiveInfo
        case counterpartyRequestsCommitment
        case counterpartyChangesScopeMaterially
        case counterpartyIntroducesPricingNegotiation
        case counterpartyIntroducesContractualTerms
        case ambiguityTooHigh
        case repeatedLoopDetected
        case userInputRequired
        case approvalRequired
        case disclosureBoundaryReached
    }

    enum UserDecisionTrigger: String, Codable, Sendable, CaseIterable, Hashable {
        case approveOutbound
        case answerMissingInfo
        case chooseBetweenOptions
        case reviewQuote
        case reviewCounteroffer
        case approveCommitment
        case approveDisclosureExpansion
        case confirmSchedulingChoice
        case resolveAmbiguity
    }
}

public extension ExchangeExpectation {
    var autoReplyBudgetRemaining: Int {
        max(0, maxAutoReplies - autoReplyCount)
    }

    var autonomousClarificationsRemaining: Int {
        max(0, maxAutonomousClarifications - autonomousClarificationCount)
    }

    var canAutoReply: Bool {
        autoReplyBudgetRemaining > 0
    }

    var canSendAutonomousClarification: Bool {
        allowsAutonomousClarification &&
        autonomousClarificationsRemaining > 0 &&
        !stopConditions.contains(.userInputRequired) &&
        !stopConditions.contains(.approvalRequired)
    }

    var isExhausted: Bool {
        autoReplyBudgetRemaining == 0
    }

    var isLocalitySensitive: Bool {
        prefersLocalFirst || fulfillmentMode == .localOnly || fulfillmentMode == .localPreferred
    }

    var isHighJudgment: Bool {
        riskLevel == .high ||
        requiresUserDecisionOn.contains(.reviewCounteroffer) ||
        requiresUserDecisionOn.contains(.approveCommitment) ||
        stopConditions.contains(.counterpartyIntroducesContractualTerms) ||
        stopConditions.contains(.counterpartyIntroducesPricingNegotiation)
    }

    func incrementingAutoReplyCount() -> ExchangeExpectation {
        var copy = self
        copy.autoReplyCount += 1
        return copy
    }

    func resettingAutoReplyCount() -> ExchangeExpectation {
        var copy = self
        copy.autoReplyCount = 0
        return copy
    }

    func incrementingAutonomousClarificationCount() -> ExchangeExpectation {
        var copy = self
        copy.autonomousClarificationCount += 1
        return copy
    }

    func resettingAutonomousClarificationCount() -> ExchangeExpectation {
        var copy = self
        copy.autonomousClarificationCount = 0
        return copy
    }

    func withNotes(_ notes: String?) -> ExchangeExpectation {
        var copy = self
        copy.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        return copy
    }

    func withAutoReplyBudget(_ value: Int) -> ExchangeExpectation {
        var copy = self
        copy.maxAutoReplies = max(0, value)
        copy.autoReplyCount = min(copy.autoReplyCount, copy.maxAutoReplies)
        return copy
    }

    func withAutonomousClarificationBudget(_ value: Int) -> ExchangeExpectation {
        var copy = self
        copy.maxAutonomousClarifications = max(0, value)
        copy.autonomousClarificationCount = min(
            copy.autonomousClarificationCount,
            copy.maxAutonomousClarifications
        )
        return copy
    }

    func withLocalityPreference(
        prefersLocalFirst: Bool,
        allowsRemoteOrShipped: Bool
    ) -> ExchangeExpectation {
        var copy = self
        copy.prefersLocalFirst = prefersLocalFirst
        copy.allowsRemoteOrShipped = allowsRemoteOrShipped
        return copy
    }

    func withFulfillmentMode(_ mode: FulfillmentMode) -> ExchangeExpectation {
        var copy = self
        copy.fulfillmentMode = mode
        return copy
    }

    func withMarketType(_ type: MarketType) -> ExchangeExpectation {
        var copy = self
        copy.marketType = type
        return copy
    }

    func withRiskLevel(_ value: RiskLevel) -> ExchangeExpectation {
        var copy = self
        copy.riskLevel = value
        return copy
    }

    func withAutonomousClarificationAllowed(_ allowed: Bool) -> ExchangeExpectation {
        var copy = self
        copy.allowsAutonomousClarification = allowed
        return copy
    }
}

public extension ExchangeExpectation {
    static let cautiousDefault = ExchangeExpectation(
        primaryGoal: .other,
        preferredOutcome: .completed,
        acceptableOutcome: .meaningfulProgress,
        marketType: .unknown,
        fulfillmentMode: .unknown,
        riskLevel: .moderate,
        prefersLocalFirst: false,
        allowsRemoteOrShipped: false,
        allowsAutonomousClarification: false,
        completionSignals: [],
        stopConditions: [
            .autoReplyBudgetExhausted,
            .ambiguityTooHigh,
            .userInputRequired,
            .approvalRequired,
            .disclosureBoundaryReached
        ],
        maxAutoReplies: 0,
        autoReplyCount: 0,
        maxAutonomousClarifications: 0,
        autonomousClarificationCount: 0,
        requiresUserDecisionOn: [
            .approveOutbound,
            .resolveAmbiguity
        ],
        notes: "Conservative default expectation."
    )
}

private extension ExchangeExpectation {
    static func normalizedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        var output: [T] = []

        for value in values where !seen.contains(value) {
            seen.insert(value)
            output.append(value)
        }

        return output
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
