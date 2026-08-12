import Foundation

/// Centralized retention and classification rules for local `exchange.sqlite` maintenance.
public struct ExchangeLocalMaintenancePolicy: Sendable, Hashable {
    /// Rows older than this many days may be pruned when otherwise eligible.
    public var retentionDays: Int

    /// After age pruning, keep at most this many audit rows (newest retained).
    public var maxAuditRecords: Int

    /// Retention for remote directory / For You cache rows with no durable references.
    public var remoteDiscoveryCacheRetentionDays: Int

    /// Retention specifically for For You-tagged transient cache (defaults same as discovery cache).
    public var staleForYouCacheRetentionDays: Int

    /// Max age for open inbox rows (`received`, `awaitingOrderingGapResolution`) before eligible for pruning.
    public var staleInboxOpenRetentionDays: Int

    /// Optional local node id used to treat matching `exchange_public_profiles` / offers as user-owned.
    public var localNodeID: String?

    public init(
        retentionDays: Int = 90,
        maxAuditRecords: Int = 5_000,
        remoteDiscoveryCacheRetentionDays: Int = 30,
        staleForYouCacheRetentionDays: Int = 30,
        staleInboxOpenRetentionDays: Int = 180,
        localNodeID: String? = nil
    ) {
        self.retentionDays = max(1, retentionDays)
        self.maxAuditRecords = max(100, maxAuditRecords)
        self.remoteDiscoveryCacheRetentionDays = max(1, remoteDiscoveryCacheRetentionDays)
        self.staleForYouCacheRetentionDays = max(1, staleForYouCacheRetentionDays)
        self.staleInboxOpenRetentionDays = max(1, staleInboxOpenRetentionDays)
        let trimmedLocalNodeID = localNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.localNodeID = trimmedLocalNodeID.isEmpty ? nil : trimmedLocalNodeID
    }

    public static let `default` = ExchangeLocalMaintenancePolicy()

    public func cutoffDate(now: Date = Date()) -> Date {
        cutoffDate(retentionDays: retentionDays, now: now)
    }

    public func remoteDiscoveryCacheCutoffDate(now: Date = Date()) -> Date {
        cutoffDate(retentionDays: remoteDiscoveryCacheRetentionDays, now: now)
    }

    public func staleForYouCacheCutoffDate(now: Date = Date()) -> Date {
        cutoffDate(retentionDays: staleForYouCacheRetentionDays, now: now)
    }

    public func staleInboxOpenCutoffDate(now: Date = Date()) -> Date {
        cutoffDate(retentionDays: staleInboxOpenRetentionDays, now: now)
    }

    private func cutoffDate(retentionDays: Int, now: Date) -> Date {
        let interval = TimeInterval(retentionDays) * 86_400
        return now.addingTimeInterval(-interval)
    }

    /// Delivery phases eligible for pruning when the row is inactive and older than the cutoff.
    public static let prunableInactiveOutboxPhases: Set<ExchangeDeliveryState.Phase> = [
        .acknowledged,
        .failed,
        .cancelledBeforeSend,
        .tooLateToCancel,
        .incompatible
    ]

    /// Inbox processing states eligible for pruning when older than the cutoff.
    public static let prunableInboxProcessingStates: Set<ExchangeInboxItem.ProcessingState> = [
        .archived,
        .deferred,
        .reconciledIntoThread,
        .rejected,
        .duplicateIgnored
    ]

    /// Match statuses eligible for pruning on inactive threads.
    public static let prunableMatchStatuses: Set<ExchangeMatch.Status> = [
        .rejected,
        .archived
    ]

    /// Thread `state_key` values treated as completed/inactive for match pruning.
    public static let inactiveThreadStateKeys: Set<String> = [
        ExchangeTransition.ExchangeStateKey.declined.rawValue,
        ExchangeTransition.ExchangeStateKey.stalled.rawValue,
        ExchangeTransition.ExchangeStateKey.resolved.rawValue
    ]

    public static func isOutboxRowPrunable(
        isActive: Bool,
        phase: ExchangeDeliveryState.Phase,
        updatedAt: Date,
        cutoff: Date
    ) -> Bool {
        guard !isActive else { return false }
        guard updatedAt < cutoff else { return false }
        return prunableInactiveOutboxPhases.contains(phase)
    }

    public static func isInboxRowPrunable(
        processingState: ExchangeInboxItem.ProcessingState,
        updatedAt: Date,
        cutoff: Date
    ) -> Bool {
        guard updatedAt < cutoff else { return false }
        return prunableInboxProcessingStates.contains(processingState)
    }

    public static func isNotificationRowPrunable(
        isRead: Bool,
        updatedAt: Date,
        cutoff: Date
    ) -> Bool {
        isRead && updatedAt < cutoff
    }

    public static func isMatchRowPrunable(
        matchStatus: ExchangeMatch.Status,
        matchCreatedAt: Date,
        threadStateKey: String,
        threadMetadataArchived: Bool,
        cutoff: Date
    ) -> Bool {
        guard matchCreatedAt < cutoff else { return false }
        guard prunableMatchStatuses.contains(matchStatus) else { return false }
        return inactiveThreadStateKeys.contains(threadStateKey) || threadMetadataArchived
    }
}
