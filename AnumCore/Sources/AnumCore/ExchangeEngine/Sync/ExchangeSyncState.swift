import Foundation

public struct ExchangeSyncState: Codable, Sendable, Hashable {
    public var id: String

    /// Durable inbound position persisted by the client.
    /// This is intentionally named checkpoint at the sync layer,
    /// even if the relay currently implements it as a cursor string.
    public var inboundCheckpoint: String?

    public var lastInboundSyncAt: Date?
    public var lastOutboundFlushAt: Date?
    public var lastReconcileAt: Date?
    public var lastSuccessfulSyncAt: Date?
    public var lastAttemptAt: Date?
    public var backoffUntil: Date?
    public var consecutiveFailureCount: Int
    public var lastErrorSummary: String?
    public var lastErrorDomain: String?
    public var activeRunID: UUID?
    public var updatedAt: Date

    public init(
        id: String = Self.primaryID,
        inboundCheckpoint: String? = nil,
        lastInboundSyncAt: Date? = nil,
        lastOutboundFlushAt: Date? = nil,
        lastReconcileAt: Date? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        backoffUntil: Date? = nil,
        consecutiveFailureCount: Int = 0,
        lastErrorSummary: String? = nil,
        lastErrorDomain: String? = nil,
        activeRunID: UUID? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.inboundCheckpoint = inboundCheckpoint?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.lastInboundSyncAt = lastInboundSyncAt
        self.lastOutboundFlushAt = lastOutboundFlushAt
        self.lastReconcileAt = lastReconcileAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastAttemptAt = lastAttemptAt
        self.backoffUntil = backoffUntil
        self.consecutiveFailureCount = max(0, consecutiveFailureCount)
        self.lastErrorSummary = lastErrorSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.lastErrorDomain = lastErrorDomain?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.activeRunID = activeRunID
        self.updatedAt = updatedAt
    }

    public static let primaryID = "primary"

    public static func initial(now: Date) -> ExchangeSyncState {
        ExchangeSyncState(
            id: Self.primaryID,
            updatedAt: now
        )
    }

    public func withUpdatedTimestamp(_ now: Date) -> ExchangeSyncState {
        var copy = self
        copy.updatedAt = now
        return copy
    }

    public func beginningRun(runID: UUID, now: Date) -> ExchangeSyncState {
        var copy = self
        copy.activeRunID = runID
        copy.lastAttemptAt = now
        copy.updatedAt = now
        return copy
    }

    public func endingRun(now: Date) -> ExchangeSyncState {
        var copy = self
        copy.activeRunID = nil
        copy.updatedAt = now
        return copy
    }

    public func recordingSuccess(
        inboundCheckpoint: String?,
        inboundSyncedAt: Date?,
        outboundFlushedAt: Date?,
        reconciledAt: Date?,
        now: Date
    ) -> ExchangeSyncState {
        var copy = self

        if let inboundCheckpoint {
            copy.inboundCheckpoint = inboundCheckpoint.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }

        if let inboundSyncedAt {
            copy.lastInboundSyncAt = inboundSyncedAt
        }

        if let outboundFlushedAt {
            copy.lastOutboundFlushAt = outboundFlushedAt
        }

        if let reconciledAt {
            copy.lastReconcileAt = reconciledAt
        }

        copy.lastSuccessfulSyncAt = now
        copy.consecutiveFailureCount = 0
        copy.backoffUntil = nil
        copy.lastErrorSummary = nil
        copy.lastErrorDomain = nil
        copy.updatedAt = now
        return copy
    }

    public func recordingFailure(
        summary: String,
        domain: String,
        backoffUntil: Date?,
        now: Date
    ) -> ExchangeSyncState {
        var copy = self
        copy.consecutiveFailureCount += 1
        copy.lastErrorSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        copy.lastErrorDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        copy.backoffUntil = backoffUntil
        copy.updatedAt = now
        return copy
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
