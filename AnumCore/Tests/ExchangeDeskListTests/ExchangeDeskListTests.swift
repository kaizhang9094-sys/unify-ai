import Foundation
import Testing
@testable import AnumCore

@Suite("Exchange desk list policy and maintenance")
struct ExchangeDeskListTests {
    private func sampleIntent() -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            title: "Desk test",
            objective: "Objective",
            readiness: .ready
        )
    }

    private func sampleThread(
        id: UUID = UUID(),
        state: ExchangeState = .drafting,
        updatedAt: Date = Date(),
        archived: Bool = false
    ) -> ExchangeThread {
        var thread = ExchangeThread(
            id: id,
            mode: .transactional,
            intent: sampleIntent(),
            posture: .default,
            state: state
        )
        thread.updatedAt = updatedAt
        if archived {
            thread.metadata[ExchangeThreadArchiveMetadata.archivedKey] = "true"
        }
        return thread
    }

    @Test func mergedDeskThreadsRespectsLimitAndExcludesArchived() {
        let now = Date()
        let recent = (0..<3).map { index in
            sampleThread(updatedAt: now.addingTimeInterval(-Double(index)))
        }
        var archived = sampleThread(updatedAt: now.addingTimeInterval(-10))
        archived.metadata[ExchangeThreadArchiveMetadata.archivedKey] = "true"

        let merged = ExchangeDeskListPolicy.mergedDeskThreads(
            recent: recent + [archived],
            pending: [],
            policy: .default
        )

        #expect(merged.count == 3)
        #expect(merged.allSatisfy { !$0.isArchived })
        #expect(merged[0].updatedAt >= merged[1].updatedAt)
    }

    @Test func mergedDeskThreadsIncludesPendingOutsideRecentWindow() {
        let now = Date()
        let recent = [
            sampleThread(updatedAt: now)
        ]
        let stalePendingID = UUID()
        let pending = sampleThread(
            id: stalePendingID,
            state: .awaitingApproval(.init(summary: "Needs approval")),
            updatedAt: now.addingTimeInterval(-200 * 86_400)
        )

        let merged = ExchangeDeskListPolicy.mergedDeskThreads(
            recent: recent,
            pending: [pending],
            policy: .default
        )

        #expect(merged.contains(where: { $0.id == stalePendingID }))
    }

    @Test func stalePruneSkipsPendingAndPrunesOldResolved() {
        let cutoff = Date().addingTimeInterval(-90 * 86_400)
        let old = cutoff.addingTimeInterval(-1 * 86_400)

        let pendingOld = sampleThread(state: .awaitingApproval(.init(summary: "Needs approval")), updatedAt: old)
        #expect(
            !ExchangeSQLiteStore.isThreadEligibleForStalePrune(
                pendingOld,
                cutoff: cutoff,
                allThreads: [pendingOld]
            )
        )

        let resolvedOld = sampleThread(state: .resolved(.init(summary: "Done")), updatedAt: old)
        #expect(
            ExchangeSQLiteStore.isThreadEligibleForStalePrune(
                resolvedOld,
                cutoff: cutoff,
                allThreads: [resolvedOld]
            )
        )

        var archivedOld = resolvedOld
        archivedOld.metadata[ExchangeThreadArchiveMetadata.archivedKey] = "true"
        #expect(
            ExchangeSQLiteStore.isThreadEligibleForStalePrune(
                archivedOld,
                cutoff: cutoff,
                allThreads: [archivedOld]
            )
        )
    }

    @Test func listThreadsStoreLimitReturnsBoundedRecentRows() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exchange-desk-limit-\(UUID().uuidString).sqlite")
        let store = try ExchangeSQLiteStore(databaseURL: url)
        let now = Date()

        for index in 0..<55 {
            let thread = sampleThread(
                updatedAt: now.addingTimeInterval(-Double(index))
            )
            try await store.createThread(thread)
        }

        let limited = try await store.listThreads(filter: .init(limit: 40))
        #expect(limited.count == 40)
        #expect(limited.first?.updatedAt ?? .distantPast >= limited.last?.updatedAt ?? .distantFuture)
    }

    @Test func maintenancePrunesOldArchivedThreadNotRecentActive() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exchange-desk-prune-\(UUID().uuidString).sqlite")
        let store = try ExchangeSQLiteStore(databaseURL: url)
        let old = Date().addingTimeInterval(-120 * 86_400)
        let recent = Date().addingTimeInterval(-2 * 86_400)

        var archivedOld = sampleThread(state: .resolved(.init(summary: "Done")), updatedAt: old)
        archivedOld.metadata[ExchangeThreadArchiveMetadata.archivedKey] = "true"
        try await store.createThread(archivedOld)

        let activeRecent = sampleThread(state: .drafting, updatedAt: recent)
        try await store.createThread(activeRecent)

        let policy = ExchangeLocalMaintenancePolicy(terminalThreadRetentionDays: 90)
        let result = try await store.runLocalMaintenance(policy: policy, reason: "desk_test")

        #expect(result.deletedCount(for: .threads) == 1)
        #expect(try await store.fetchThread(id: archivedOld.id) == nil)
        #expect(try await store.fetchThread(id: activeRecent.id) != nil)
    }

    @Test func countPendingApprovalRowsIsZeroOnEmptyStore() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exchange-pending-count-\(UUID().uuidString).sqlite")
        let store = try ExchangeSQLiteStore(databaseURL: url)
        #expect(try await store.countPendingApprovalRows() == 0)
        #expect(try await store.listPendingApprovalRows(limit: nil).isEmpty)
    }
    @Test func deskVisibleFilterExcludesCoordinationChildrenInSQL() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exchange-desk-visible-\(UUID().uuidString).sqlite")
        let store = try ExchangeSQLiteStore(databaseURL: url)
        let now = Date()

        var root = sampleThread(updatedAt: now)
        ExchangeThreadRoleResolver.applyRole(.umbrellaSearch, to: &root.metadata)
        try await store.createThread(root)

        var child = sampleThread(updatedAt: now.addingTimeInterval(-1))
        ExchangeThreadRoleResolver.applyRole(.candidateCoordination, to: &child.metadata)
        ExchangeThreadRoleResolver.applyParentThreadID(root.id, to: &child.metadata)
        ExchangeThreadRoleResolver.applyRootThreadID(root.id, to: &child.metadata)
        try await store.createThread(child)

        let deskVisible = try await store.listThreads(filter: .deskVisible(limit: 10))
        #expect(deskVisible.count == 1)
        #expect(deskVisible.first?.id == root.id)

        let children = try await store.listCandidateChildren(rootThreadIDs: [root.id], limitPerRoot: nil)
        #expect(children.count == 1)
        #expect(children.first?.id == child.id)
    }

    @Test func isDeskTopLevelVisibleExcludesCoordinationChild() {
        var child = sampleThread()
        ExchangeThreadRoleResolver.applyRole(.candidateCoordination, to: &child.metadata)
        #expect(!ExchangeDeskListPolicy.isDeskTopLevelVisible(child))
    }

}

