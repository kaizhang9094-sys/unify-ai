import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeUmbrellaDiscoveryGradePersistence")
struct ExchangeUmbrellaDiscoveryGradePersistenceTests {
    private func makeStore() throws -> ExchangeSQLiteStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exchange-umbrella-grade-\(UUID().uuidString).sqlite")
        return try ExchangeSQLiteStore(databaseURL: url)
    }

    private func sampleIntent() -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            title: "Find computer",
            objective: "Find computer",
            readiness: .ready
        )
    }

    private func makeUmbrellaThread() -> ExchangeThread {
        var thread = ExchangeThread(
            mode: .transactional,
            intent: sampleIntent(),
            posture: .default,
            state: .matchCandidatesWeak(
                .init(
                    candidateCount: 2,
                    explanation: "Found paths",
                    suggestedRefinement: "Review"
                )
            )
        )
        ExchangeThreadRoleResolver.applyUmbrellaSearchRole(
            rootThreadID: thread.id,
            to: &thread.metadata
        )
        return thread
    }

    @Test("SQLite roundtrip preserves discovery grade metadata keys")
    func sqliteRoundtripPreservesDiscoveryGradeMetadataKeys() async throws {
        let store = try makeStore()
        var thread = makeUmbrellaThread()
        ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
            classifyGrade: .strong,
            activatedChildCount: 2,
            to: &thread.metadata
        )

        try await store.createThread(thread)
        let fetched = try await store.requireThread(id: thread.id)
        let snapshot = ExchangeThreadDiscoveryGradeMetadata.snapshot(from: fetched.metadata)

        #expect(snapshot.discoveryResult == .found)
        #expect(snapshot.classifyGrade == .strong)
        #expect(snapshot.projectedGrade == .strong)
        #expect(snapshot.gradeReason == "strong_classify_preserved")
    }

    @Test("listThreads returns umbrella threads with discovery grade metadata intact")
    func listThreadsReturnsUmbrellaThreadsWithDiscoveryGradeMetadataIntact() async throws {
        let store = try makeStore()
        var thread = makeUmbrellaThread()
        ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
            classifyGrade: .moderateReviewNeeded,
            activatedChildCount: 1,
            to: &thread.metadata
        )

        try await store.createThread(thread)
        let listed = try await store.listThreads(filter: .init(limit: 10))
        let listedThread = try #require(listed.first(where: { $0.id == thread.id }))
        let snapshot = ExchangeThreadDiscoveryGradeMetadata.snapshot(from: listedThread.metadata)

        #expect(snapshot.classifyGrade == .moderateReviewNeeded)
        #expect(snapshot.projectedGrade == .moderate)
        #expect(snapshot.gradeReason == "moderate_review_needed_preserved")
    }

    @Test("metadata column merge restores grade keys when snapshot metadata is stale")
    func metadataColumnMergeRestoresGradeKeysWhenSnapshotMetadataIsStale() async throws {
        let store = try makeStore()
        var thread = makeUmbrellaThread()
        ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
            classifyGrade: .strong,
            activatedChildCount: 2,
            to: &thread.metadata
        )

        try await store.createThread(thread)

        var staleSnapshotThread = try await store.requireThread(id: thread.id)
        staleSnapshotThread.metadata.removeValue(forKey: ExchangeThreadDiscoveryGradeMetadata.projectedGradeKey)
        staleSnapshotThread.metadata.removeValue(forKey: ExchangeThreadDiscoveryGradeMetadata.classifyGradeKey)
        try await store.updateThread(staleSnapshotThread)

        var regradeThread = try await store.requireThread(id: thread.id)
        ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
            classifyGrade: .strong,
            activatedChildCount: 2,
            to: &regradeThread.metadata
        )
        try await store.updateThread(regradeThread)

        let fetched = try await store.requireThread(id: thread.id)
        let resolution = ExchangeUmbrellaDiscoveryGradeProjection.resolve(
            thread: fetched,
            context: .init(activatedChildCount: 2, strongestChildSourceRank: 1, strongestChildProofValid: true)
        )

        #expect(resolution.usesMetadata == true)
        #expect(resolution.projectedGrade == .strong)
    }

    @Test("ExchangeCoordinationProjection applyListFields preserves discovery grade metadata on thread")
    func coordinationProjectionPreservesDiscoveryGradeMetadataOnThread() {
        var thread = makeUmbrellaThread()
        ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
            classifyGrade: .strong,
            activatedChildCount: 2,
            to: &thread.metadata
        )

        var inboxItem = ExchangeModels.InboxItem(
            threadID: thread.id,
            title: "Find computer",
            subtitle: "",
            state: thread.state,
            stateTitle: "No match yet",
            updatedAt: thread.updatedAt,
            requiresHumanDecision: true,
            hasFailure: false
        )

        let child = makeChildThread(parent: thread)
        let index = ExchangeCoordinationThreadIndex(threads: [thread, child])
        ExchangeCoordinationProjection.applyListFields(
            to: &inboxItem,
            thread: thread,
            index: index
        )

        let snapshot = ExchangeThreadDiscoveryGradeMetadata.snapshot(from: thread.metadata)
        #expect(snapshot.projectedGrade == .strong)
        #expect(inboxItem.coordinationChildThreadIDs.count == 1)
    }

    @Test("live-like umbrella with weak internal state and grade metadata projects strong")
    func liveLikeUmbrellaProjectsStrongNotWeak() {
        var thread = makeUmbrellaThread()
        ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
            classifyGrade: .strong,
            activatedChildCount: 2,
            to: &thread.metadata
        )

        let resolution = ExchangeUmbrellaDiscoveryGradeProjection.resolve(
            thread: thread,
            context: .init(activatedChildCount: 2, strongestChildSourceRank: 1, strongestChildProofValid: true)
        )

        #expect(resolution.internalStateKey == "matchCandidatesWeak")
        #expect(resolution.usesMetadata == true)
        #expect(resolution.projectedGrade == .strong)
        #expect(ExchangeUmbrellaDiscoveryGradeProjection.inboxStateTitle(for: resolution) == "Found strong matches")
        let title = ExchangeUmbrellaDiscoveryGradeProjection.inboxStateTitle(for: resolution) ?? ""
        #expect(!title.localizedCaseInsensitiveContains("Weak"))
    }

    private func makeChildThread(parent: ExchangeThread) -> ExchangeThread {
        var child = ExchangeThread(
            mode: parent.mode,
            intent: parent.intent,
            posture: parent.posture,
            state: .matchFound(
                .init(
                    candidateCount: 1,
                    summary: "Match found",
                    selectedCounterpartyID: "seller-1",
                    selectedPublicProfileID: "profile-1",
                    selectedOfferID: "offer-1"
                )
            )
        )
        ExchangeThreadRoleResolver.applyCandidateCoordinationHierarchy(
            parentThreadID: parent.id,
            rootThreadID: parent.id,
            sourceMatchID: UUID(),
            sourceRank: 1,
            to: &child.metadata
        )
        return child
    }
}
