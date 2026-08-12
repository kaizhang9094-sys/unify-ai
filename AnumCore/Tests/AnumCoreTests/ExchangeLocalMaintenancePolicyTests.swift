import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeLocalMaintenancePolicy classification")
struct ExchangeLocalMaintenancePolicyTests {
    private let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
    private let old = Date(timeIntervalSince1970: 1_600_000_000)
    private let recent = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func activeOutboxIsNeverPrunable() {
        for phase in ExchangeDeliveryState.Phase.allCases {
            #expect(
                ExchangeLocalMaintenancePolicy.isOutboxRowPrunable(
                    isActive: true,
                    phase: phase,
                    updatedAt: old,
                    cutoff: cutoff
                ) == false
            )
        }
    }

    @Test func terminalOldInactiveOutboxIsPrunable() {
        #expect(
            ExchangeLocalMaintenancePolicy.isOutboxRowPrunable(
                isActive: false,
                phase: .acknowledged,
                updatedAt: old,
                cutoff: cutoff
            )
        )
        #expect(
            ExchangeLocalMaintenancePolicy.isOutboxRowPrunable(
                isActive: false,
                phase: .failed,
                updatedAt: old,
                cutoff: cutoff
            )
        )
    }

    @Test func recentTerminalInactiveOutboxIsNotPrunable() {
        #expect(
            ExchangeLocalMaintenancePolicy.isOutboxRowPrunable(
                isActive: false,
                phase: .acknowledged,
                updatedAt: recent,
                cutoff: cutoff
            ) == false
        )
    }

    @Test func pendingOutboxPhasesAreNotPrunable() {
        for phase: ExchangeDeliveryState.Phase in [.queued, .blockedByPrerequisite, .deferred, .sending, .sent] {
            #expect(
                ExchangeLocalMaintenancePolicy.isOutboxRowPrunable(
                    isActive: false,
                    phase: phase,
                    updatedAt: old,
                    cutoff: cutoff
                ) == false
            )
        }
    }

    @Test func activeUnreadInboxIsNotPrunable() {
        #expect(
            ExchangeLocalMaintenancePolicy.isInboxRowPrunable(
                processingState: .received,
                updatedAt: old,
                cutoff: cutoff
            ) == false
        )
        #expect(
            ExchangeLocalMaintenancePolicy.isInboxRowPrunable(
                processingState: .awaitingOrderingGapResolution,
                updatedAt: old,
                cutoff: cutoff
            ) == false
        )
    }

    @Test func oldArchivedInboxIsPrunable() {
        #expect(
            ExchangeLocalMaintenancePolicy.isInboxRowPrunable(
                processingState: .archived,
                updatedAt: old,
                cutoff: cutoff
            )
        )
        #expect(
            ExchangeLocalMaintenancePolicy.isInboxRowPrunable(
                processingState: .reconciledIntoThread,
                updatedAt: old,
                cutoff: cutoff
            )
        )
    }

    @Test func unreadNotificationIsNotPrunable() {
        #expect(
            ExchangeLocalMaintenancePolicy.isNotificationRowPrunable(
                isRead: false,
                updatedAt: old,
                cutoff: cutoff
            ) == false
        )
    }

    @Test func readOldNotificationIsPrunable() {
        #expect(
            ExchangeLocalMaintenancePolicy.isNotificationRowPrunable(
                isRead: true,
                updatedAt: old,
                cutoff: cutoff
            )
        )
    }

    @Test func activeThreadMatchIsNotPrunable() {
        #expect(
            ExchangeLocalMaintenancePolicy.isMatchRowPrunable(
                matchStatus: .archived,
                matchCreatedAt: old,
                threadStateKey: ExchangeTransition.ExchangeStateKey.searching.rawValue,
                threadMetadataArchived: false,
                cutoff: cutoff
            ) == false
        )
    }

    @Test func staleMatchOnResolvedThreadIsPrunable() {
        #expect(
            ExchangeLocalMaintenancePolicy.isMatchRowPrunable(
                matchStatus: .rejected,
                matchCreatedAt: old,
                threadStateKey: ExchangeTransition.ExchangeStateKey.resolved.rawValue,
                threadMetadataArchived: false,
                cutoff: cutoff
            )
        )
    }
}

    @Test func remoteDiscoveryCacheCutoffUsesDedicatedRetentionDays() {
        let policy = ExchangeLocalMaintenancePolicy(
            retentionDays: 90,
            remoteDiscoveryCacheRetentionDays: 30
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoff = policy.remoteDiscoveryCacheCutoffDate(now: now)
        let expected = now.addingTimeInterval(-30 * 86_400)
        #expect(abs(cutoff.timeIntervalSince(expected)) < 1)
    }

    @Test func staleInboxOpenCutoffUsesDedicatedRetentionDays() {
        let policy = ExchangeLocalMaintenancePolicy(staleInboxOpenRetentionDays: 180)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoff = policy.staleInboxOpenCutoffDate(now: now)
        let expected = now.addingTimeInterval(-180 * 86_400)
        #expect(abs(cutoff.timeIntervalSince(expected)) < 1)
    }

}
