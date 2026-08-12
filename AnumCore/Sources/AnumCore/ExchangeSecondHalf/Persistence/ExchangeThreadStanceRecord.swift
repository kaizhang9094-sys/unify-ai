import Foundation

/// Durable stance record.
///
/// Stores the compact thread stance in a persistence-friendly shape.
public struct ExchangeThreadStanceRecord: Codable, Hashable, Sendable {
    public var threadID: UUID
    public var role: ExchangeSecondHalfRole
    public var savedAt: Date

    public var interestLevel: ExchangeInterestLevel
    public var urgencyLevel: ExchangeUrgencyLevel
    public var trustLevel: ExchangeTrustLevel
    public var priceSensitivity: ExchangePriceSensitivity
    public var flexibilityLevel: ExchangeFlexibilityLevel
    public var readinessLevel: ExchangeReadinessLevel
    public var postureSummary: String
    public var recommendedNextMove: ExchangeSecondHalfAction?
    public var followUpHints: [String]

    public init(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        savedAt: Date = Date(),
        interestLevel: ExchangeInterestLevel,
        urgencyLevel: ExchangeUrgencyLevel,
        trustLevel: ExchangeTrustLevel,
        priceSensitivity: ExchangePriceSensitivity,
        flexibilityLevel: ExchangeFlexibilityLevel,
        readinessLevel: ExchangeReadinessLevel,
        postureSummary: String,
        recommendedNextMove: ExchangeSecondHalfAction? = nil,
        followUpHints: [String] = []
    ) {
        self.threadID = threadID
        self.role = role
        self.savedAt = savedAt
        self.interestLevel = interestLevel
        self.urgencyLevel = urgencyLevel
        self.trustLevel = trustLevel
        self.priceSensitivity = priceSensitivity
        self.flexibilityLevel = flexibilityLevel
        self.readinessLevel = readinessLevel
        self.postureSummary = postureSummary
        self.recommendedNextMove = recommendedNextMove
        self.followUpHints = followUpHints
    }
}

public extension ExchangeThreadStanceRecord {
    init(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        stance: ExchangeThreadStance,
        savedAt: Date = Date()
    ) {
        self.init(
            threadID: threadID,
            role: role,
            savedAt: savedAt,
            interestLevel: stance.interestLevel,
            urgencyLevel: stance.urgencyLevel,
            trustLevel: stance.trustLevel,
            priceSensitivity: stance.priceSensitivity,
            flexibilityLevel: stance.flexibilityLevel,
            readinessLevel: stance.readinessLevel,
            postureSummary: stance.postureSummary,
            recommendedNextMove: stance.recommendedNextMove,
            followUpHints: stance.followUpHints
        )
    }

    func asDomainModel() -> ExchangeThreadStance {
        ExchangeThreadStance(
            interestLevel: interestLevel,
            urgencyLevel: urgencyLevel,
            trustLevel: trustLevel,
            priceSensitivity: priceSensitivity,
            flexibilityLevel: flexibilityLevel,
            readinessLevel: readinessLevel,
            postureSummary: postureSummary,
            recommendedNextMove: recommendedNextMove,
            followUpHints: followUpHints
        )
    }
}
