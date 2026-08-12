import Foundation
import AnumCore

/// Cheap desk invalidation token (Phase 1: derived from loaded payloads, not store SQL).
struct SecretaryDeskFingerprint: Equatable, Sendable {
    let threadCount: Int
    let inboxCount: Int
    let pendingCount: Int
    let maxThreadUpdatedAt: TimeInterval
    let maxInboxUpdatedAt: TimeInterval

    static func make(
        threadItems: [ExchangeModels.InboxItem],
        visibleInboxItems: [ExchangeInboxItem],
        pendingApprovals: [ExchangeModels.PendingApproval]
    ) -> SecretaryDeskFingerprint {
        SecretaryDeskFingerprint(
            threadCount: threadItems.count,
            inboxCount: visibleInboxItems.count,
            pendingCount: pendingApprovals.count,
            maxThreadUpdatedAt: threadItems.map(\.updatedAt.timeIntervalSince1970).max() ?? 0,
            maxInboxUpdatedAt: visibleInboxItems.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        )
    }
}

/// Tab-badge counts shared by workspace chrome (active includes visible federation inbox rows).
struct SecretaryDeskChromeCounts: Equatable, Sendable {
    let activeCount: Int
    let pendingCount: Int
    let trustedCount: Int
    let recoveryCount: Int

    static let empty = SecretaryDeskChromeCounts(
        activeCount: 0,
        pendingCount: 0,
        trustedCount: 0,
        recoveryCount: 0
    )
}

/// Immutable secretary desk state produced once per refresh for UI consumers.
/// Intentionally not `Equatable` — UI observers should key off `generation` only.
struct SecretaryDeskSnapshot: Sendable {
    let threadItems: [ExchangeModels.InboxItem]
    let pendingApprovals: [ExchangeModels.PendingApproval]
    let visibleInboxItems: [ExchangeInboxItem]
    let currentFocusItem: ExchangeModels.InboxItem?
    let visibleRootThreadIDs: [ExchangeThread.ID]
    let chrome: SecretaryDeskChromeCounts
    let fingerprint: SecretaryDeskFingerprint
    let generatedAt: Date
    let generation: UInt64
}

#if DEBUG
enum SecretaryDeskStartupAudit {
    static var listThreadsCalls: Int = 0
    static var listDeskThreadsCalls: Int = 0
    static var snapshotRefreshes: Int = 0
    static var dashboardDirectLoads: Int = 0
    static var workspaceDirectLoads: Int = 0
    static var threadListDirectLoads: Int = 0
    static var blockedDirectLoads: Int = 0

    static func logSummary() {
        print(
            "[ThreadStartupAudit] listThreadsCalls=\(listThreadsCalls) listDeskThreadsCalls=\(listDeskThreadsCalls) " +
            "snapshotRefreshes=\(snapshotRefreshes) " +
            "dashboardDirectLoads=\(dashboardDirectLoads) " +
            "workspaceDirectLoads=\(workspaceDirectLoads) " +
            "threadListDirectLoads=\(threadListDirectLoads) " +
            "blockedDirectLoads=\(blockedDirectLoads)"
        )
    }
}
#endif

enum SecretaryDeskSnapshotBuilder {
    static func filterVisibleInboxItems(_ inbox: [ExchangeInboxItem]) -> [ExchangeInboxItem] {
        inbox
            .filter {
                switch $0.processingState {
                case .received, .deferred, .awaitingOrderingGapResolution:
                    return true
                case .duplicateIgnored, .reconciledIntoThread, .rejected, .archived:
                    return false
                }
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    static func orderThreads(
        _ threads: [ExchangeModels.InboxItem],
        preferredThreadID: ExchangeThread.ID?
    ) -> [ExchangeModels.InboxItem] {
        guard let preferredThreadID,
              let preferred = threads.first(where: { $0.threadID == preferredThreadID }) else {
            return threads
        }
        return [preferred] + threads.filter { $0.threadID != preferredThreadID }
    }

    static func resolveCurrentFocusItem(
        threads: [ExchangeModels.InboxItem],
        pendingApprovals: [ExchangeModels.PendingApproval],
        preferredThreadID: ExchangeThread.ID?
    ) -> ExchangeModels.InboxItem? {
        let pendingApprovalThreadIDs = Set(pendingApprovals.map(\.threadID))

        let projected: [(ExchangeModels.InboxItem, SecretaryProjectionEngine.Bucket)] = threads.compactMap { item in
            let bucket = SecretaryProjectionEngine.bucket(
                for: item,
                pendingApprovalThreadIDs: pendingApprovalThreadIDs,
                preferredThreadID: preferredThreadID
            )
            guard bucket != .none else { return nil }
            return (item, bucket)
        }

        if let pending = projected.first(where: { $0.1 == .pending })?.0 { return pending }
        if let recovery = projected.first(where: { $0.1 == .recovery })?.0 { return recovery }

        if let preferredThreadID,
           let preferredPair = projected.first(where: { $0.0.threadID == preferredThreadID }),
           SecretaryProjectionEngine.isOperationalThreadOpenAllowed(preferredPair.0) {
            return preferredPair.0
        }

        if let search = projected.first(where: {
            $0.1 == .searchResult && SecretaryProjectionEngine.isOperationalThreadOpenAllowed($0.0)
        })?.0 { return search }

        if let preferredThreadID,
           let preferred = projected.first(where: { $0.0.threadID == preferredThreadID })?.0 {
            return preferred
        }

        if let search = projected.first(where: { $0.1 == .searchResult })?.0 { return search }
        if let active = projected.first(where: { $0.1 == .active })?.0 { return active }
        if let trusted = projected.first(where: { $0.1 == .trusted })?.0 { return trusted }
        return projected.first?.0
    }

    static func chromeCounts(
        threads: [ExchangeModels.InboxItem],
        visibleInboxItems: [ExchangeInboxItem],
        pendingApprovals: [ExchangeModels.PendingApproval],
        preferredThreadID: ExchangeThread.ID?
    ) -> SecretaryDeskChromeCounts {
        let pendingApprovalThreadIDs = Set(pendingApprovals.map(\.threadID))
        let buckets = threads.map {
            SecretaryProjectionEngine.bucket(
                for: $0,
                pendingApprovalThreadIDs: pendingApprovalThreadIDs,
                preferredThreadID: preferredThreadID
            )
        }

        return SecretaryDeskChromeCounts(
            activeCount: buckets.filter { $0 == .active }.count + visibleInboxItems.count,
            pendingCount: buckets.filter { $0 == .pending }.count,
            trustedCount: buckets.filter { $0 == .trusted }.count,
            recoveryCount: buckets.filter { $0 == .recovery }.count
        )
    }

    static func build(
        rawThreadItems: [ExchangeModels.InboxItem],
        rawInboxItems: [ExchangeInboxItem],
        pendingApprovals: [ExchangeModels.PendingApproval],
        preferredThreadID: ExchangeThread.ID?,
        generation: UInt64,
        generatedAt: Date = Date()
    ) -> SecretaryDeskSnapshot {
        let visibleInboxItems = filterVisibleInboxItems(rawInboxItems)
        let threadItems = orderThreads(rawThreadItems, preferredThreadID: preferredThreadID)
        let currentFocusItem = resolveCurrentFocusItem(
            threads: threadItems,
            pendingApprovals: pendingApprovals,
            preferredThreadID: preferredThreadID
        )
        let visibleRootThreadIDs = threadItems.map(\.threadID)
        let chrome = chromeCounts(
            threads: threadItems,
            visibleInboxItems: visibleInboxItems,
            pendingApprovals: pendingApprovals,
            preferredThreadID: preferredThreadID
        )
        let fingerprint = SecretaryDeskFingerprint.make(
            threadItems: threadItems,
            visibleInboxItems: visibleInboxItems,
            pendingApprovals: pendingApprovals
        )

        return SecretaryDeskSnapshot(
            threadItems: threadItems,
            pendingApprovals: pendingApprovals,
            visibleInboxItems: visibleInboxItems,
            currentFocusItem: currentFocusItem,
            visibleRootThreadIDs: visibleRootThreadIDs,
            chrome: chrome,
            fingerprint: fingerprint,
            generatedAt: generatedAt,
            generation: generation
        )
    }
}
