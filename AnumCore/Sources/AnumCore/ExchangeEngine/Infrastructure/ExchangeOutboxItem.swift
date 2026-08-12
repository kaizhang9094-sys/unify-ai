import Foundation

/// Durable outbound federation work item.
///
/// Important distinction:
/// - A draft is authored content.
/// - An outbox item is transport/execution work derived from approved content.
///
/// This allows cancellation, retry, auditability, and delivery truth
/// without mutating the original draft into a transport object.
public struct ExchangeOutboxItem: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var createdAt: Date
    public var updatedAt: Date

    public var threadID: ExchangeThread.ID
    public var draftID: ExchangeMessageDraft.ID
    public var approvalID: ExchangeApproval.ID?

    /// Federation target for this outbound work item.
    public var targetNodeID: String

    /// Stable envelope identifier used for dedupe/replay-safe delivery.
    public var envelopeID: String

    public var deliveryState: ExchangeDeliveryState
    public var policy: PolicySnapshot
    public var payloadSummary: String

    /// Whether the item should still be attempted by the scheduler.
    public var isActive: Bool

    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        threadID: ExchangeThread.ID,
        draftID: ExchangeMessageDraft.ID,
        approvalID: ExchangeApproval.ID? = nil,
        targetNodeID: String,
        envelopeID: String,
        deliveryState: ExchangeDeliveryState = .init(),
        policy: PolicySnapshot = .init(),
        payloadSummary: String,
        isActive: Bool = true,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.threadID = threadID
        self.draftID = draftID
        self.approvalID = approvalID
        self.targetNodeID = targetNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.envelopeID = envelopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deliveryState = deliveryState
        self.policy = policy
        self.payloadSummary = payloadSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isActive = isActive
        self.metadata = metadata
    }
}

public extension ExchangeOutboxItem {
    struct PolicySnapshot: Codable, Sendable, Hashable {
        public var maxAttempts: Int
        public var allowsBackgroundRetry: Bool
        public var cancelOnApprovalRevocation: Bool
        public var requiresVisibleAudit: Bool
        public var expiresAt: Date?

        public init(
            maxAttempts: Int = 5,
            allowsBackgroundRetry: Bool = true,
            cancelOnApprovalRevocation: Bool = true,
            requiresVisibleAudit: Bool = true,
            expiresAt: Date? = nil
        ) {
            self.maxAttempts = max(1, maxAttempts)
            self.allowsBackgroundRetry = allowsBackgroundRetry
            self.cancelOnApprovalRevocation = cancelOnApprovalRevocation
            self.requiresVisibleAudit = requiresVisibleAudit
            self.expiresAt = expiresAt
        }
    }
}

public extension ExchangeOutboxItem {
    var isTerminal: Bool {
        !isActive || deliveryState.phase.isTerminal
    }

    var isExpiredByPolicy: Bool {
        guard let expiresAt = policy.expiresAt else { return false }
        return expiresAt < Date()
    }

    var isDeferredRightNow: Bool {
        guard deliveryState.phase == .deferred else { return false }
        guard let deferredUntil = deliveryState.deferredUntil else { return true }
        return deferredUntil > Date()
    }

    var mayAttemptNow: Bool {
        guard isActive else { return false }
        guard !deliveryState.phase.isTerminal else { return false }
        guard deliveryState.attemptCount < policy.maxAttempts else { return false }
        guard !isExpiredByPolicy else { return false }
        guard !isDeferredRightNow else { return false }
        return true
    }

    var canBeCancelledLocally: Bool {
        isActive && deliveryState.canCancelSafely
    }

    func updatingDeliveryState(
        _ deliveryState: ExchangeDeliveryState,
        at date: Date = Date()
    ) -> ExchangeOutboxItem {
        var copy = self
        copy.deliveryState = deliveryState
        copy.updatedAt = date
        return copy
    }

    func deactivating(
        at date: Date = Date()
    ) -> ExchangeOutboxItem {
        var copy = self
        copy.isActive = false
        copy.updatedAt = date
        return copy
    }

    func cancellingBeforeSend(
        note: String? = nil,
        at date: Date = Date()
    ) -> ExchangeOutboxItem {
        var copy = self
        copy.deliveryState = copy.deliveryState.cancellingBeforeSend(note: note, at: date)
        copy.isActive = false
        copy.updatedAt = date
        return copy
    }

    func markingTooLateToCancel(
        note: String? = nil,
        at date: Date = Date()
    ) -> ExchangeOutboxItem {
        var copy = self
        copy.deliveryState = copy.deliveryState.markingTooLateToCancel(note: note, at: date)
        copy.isActive = false
        copy.updatedAt = date
        return copy
    }

    /// Use only when the outbox work should stop permanently.
    func failingTerminally(
        errorCode: String? = nil,
        note: String? = nil,
        externalEffect: ExchangeFailure.ExternalEffect = .none,
        at date: Date = Date()
    ) -> ExchangeOutboxItem {
        var copy = self
        copy.deliveryState = copy.deliveryState.failing(
            errorCode: errorCode,
            note: note,
            externalEffect: externalEffect,
            at: date
        )
        copy.isActive = false
        copy.updatedAt = date
        return copy
    }

    func markingAcknowledged(
        externalReference: String? = nil,
        note: String? = nil,
        at date: Date = Date()
    ) -> ExchangeOutboxItem {
        var copy = self
        copy.deliveryState = copy.deliveryState.acknowledging(
            externalReference: externalReference,
            note: note,
            at: date
        )
        copy.isActive = false
        copy.updatedAt = date
        return copy
    }
}
