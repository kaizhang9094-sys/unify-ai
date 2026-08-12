import Foundation

/// Durable snapshot record for the second-half thread state.
///
/// This is the canonical persistence envelope for second-half state, so the
/// system does not end up stuffing random fields into unrelated stores.
public struct ExchangeSecondHalfRecord: Codable, Hashable, Sendable {
    public var threadID: UUID
    public var role: ExchangeSecondHalfRole
    public var savedAt: Date

    public var state: ExchangeSecondHalfState
    public var qualification: ExchangeOpportunityQualification
    public var latestDecisionFrame: ExchangeDecisionFrame?
    public var latestDelta: ExchangeThreadDelta?
    public var latestStance: ExchangeThreadStance?
    public var latestBoundary: ExchangeCommitmentBoundary?
    public var latestPlan: ExchangeSecondHalfPlan?
    public var pendingDraft: ExchangeDraftComposer.Draft?
    public var lastOutcome: ExchangeSecondHalfOutcome?
    public var agency: ExchangeSecondHalfAgencySnapshot?

    public init(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        savedAt: Date = Date(),
        state: ExchangeSecondHalfState,
        qualification: ExchangeOpportunityQualification = .empty,
        latestDecisionFrame: ExchangeDecisionFrame? = nil,
        latestDelta: ExchangeThreadDelta? = nil,
        latestStance: ExchangeThreadStance? = nil,
        latestBoundary: ExchangeCommitmentBoundary? = nil,
        latestPlan: ExchangeSecondHalfPlan? = nil,
        pendingDraft: ExchangeDraftComposer.Draft? = nil,
        lastOutcome: ExchangeSecondHalfOutcome? = nil,
        agency: ExchangeSecondHalfAgencySnapshot? = nil
    ) {
        self.threadID = threadID
        self.role = role
        self.savedAt = savedAt
        self.state = state
        self.qualification = qualification
        self.latestDecisionFrame = latestDecisionFrame
        self.latestDelta = latestDelta
        self.latestStance = latestStance
        self.latestBoundary = latestBoundary
        self.latestPlan = latestPlan
        self.pendingDraft = pendingDraft
        self.lastOutcome = lastOutcome
        self.agency = agency
    }
}

public extension ExchangeSecondHalfRecord {
    var hasPendingDraft: Bool {
        pendingDraft != nil
    }

    var isTerminal: Bool {
        state.isTerminal
    }

    func withUpdatedTimestamp(
        _ date: Date = Date()
    ) -> ExchangeSecondHalfRecord {
        var copy = self
        copy.savedAt = date
        return copy
    }
}
