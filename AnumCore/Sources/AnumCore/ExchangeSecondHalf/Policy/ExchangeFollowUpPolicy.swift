import Foundation

/// Controls stale / repeated follow-up behavior.
///
/// The goal is to make the secretary disciplined, not naggy.
public struct ExchangeFollowUpPolicy: Codable, Hashable, Sendable {
    /// Maximum total follow-up attempts before the thread should stop nudging
    /// and be surfaced as stale, stalled, or blocked.
    public var maxFollowUpAttempts: Int

    /// Maximum repeated clarification rounds before escalation or pause.
    public var maxRepeatedClarificationRounds: Int

    /// Minimum waiting interval between outbound follow-up attempts.
    public var minimumFollowUpInterval: TimeInterval

    /// After this amount of inactivity, a thread may be considered stale.
    public var staleThreadInterval: TimeInterval

    /// Whether the system should avoid sending essentially the same follow-up again.
    public var avoidDuplicateFollowUps: Bool

    /// Whether the system should prefer surfacing a stale thread to the user
    /// instead of sending another autonomous nudge.
    public var preferSurfacingOverNagging: Bool

    public init(
        maxFollowUpAttempts: Int = 2,
        maxRepeatedClarificationRounds: Int = 2,
        minimumFollowUpInterval: TimeInterval = 60 * 60 * 12, // 12 hours
        staleThreadInterval: TimeInterval = 60 * 60 * 24 * 3, // 3 days
        avoidDuplicateFollowUps: Bool = true,
        preferSurfacingOverNagging: Bool = true
    ) {
        self.maxFollowUpAttempts = max(0, maxFollowUpAttempts)
        self.maxRepeatedClarificationRounds = max(0, maxRepeatedClarificationRounds)
        self.minimumFollowUpInterval = max(0, minimumFollowUpInterval)
        self.staleThreadInterval = max(0, staleThreadInterval)
        self.avoidDuplicateFollowUps = avoidDuplicateFollowUps
        self.preferSurfacingOverNagging = preferSurfacingOverNagging
    }
}

public extension ExchangeFollowUpPolicy {
    static let `default` = ExchangeFollowUpPolicy()

    func canSendAnotherFollowUp(
        attemptsSoFar: Int,
        repeatedClarificationRounds: Int
    ) -> Bool {
        attemptsSoFar < maxFollowUpAttempts &&
        repeatedClarificationRounds < maxRepeatedClarificationRounds
    }

    func isStale(
        lastMeaningfulUpdateAt: Date,
        now: Date = Date()
    ) -> Bool {
        now.timeIntervalSince(lastMeaningfulUpdateAt) >= staleThreadInterval
    }

    func canFollowUp(
        lastOutboundAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let lastOutboundAt else { return true }
        return now.timeIntervalSince(lastOutboundAt) >= minimumFollowUpInterval
    }
}
