import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeSQLiteStore remote discovery cache maintenance")
struct ExchangeRemoteDiscoveryCacheMaintenanceStoreTests {
    private func makeStore() throws -> ExchangeSQLiteStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exchange-remote-cache-\(UUID().uuidString).sqlite")
        return try ExchangeSQLiteStore(databaseURL: url)
    }

    private func sampleIntent() -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            title: "Test",
            objective: "Objective",
            readiness: .ready
        )
    }

    private func staleDate() -> Date {
        Date().addingTimeInterval(-45 * 86_400)
    }

    private func discoveryProfile(id: String, nodeID: String) -> ExchangePublicNodeProfile {
        var profile = ExchangePublicNodeProfile(
            id: id,
            nodeID: nodeID,
            displayName: "Remote \(id)",
            visibility: .discoverable,
            availability: .open,
            createdAt: staleDate(),
            updatedAt: staleDate()
        )
        ExchangeRemoteDiscoveryCacheMetadata.tagDiscoveryProfile(&profile, now: staleDate())
        return profile
    }

    private func discoveryCounterparty(id: String) -> ExchangeCounterparty {
        ExchangeRemoteDiscoveryCacheMetadata.tagDiscoveryCounterparty(
            ExchangeCounterparty(
                id: id,
                createdAt: staleDate(),
                updatedAt: staleDate(),
                kind: .provider,
                displayName: "Remote \(id)",
                source: .localDirectory,
                identity: .init(nodeID: id, publicKeyID: nil, verification: .unverified)
            ),
            now: staleDate()
        )
    }

    @Test func staleRemoteProfileWithNoReferencesIsPruned() async throws {
        let store = try makeStore()
        let profile = discoveryProfile(id: "profile-stale", nodeID: "node-stale")
        try await store.savePublicProfiles([profile])

        let result = try await store.runLocalMaintenance(
            policy: ExchangeLocalMaintenancePolicy(remoteDiscoveryCacheRetentionDays: 30),
            reason: "test"
        )

        #expect(result.deletedCount(for: .staleRemotePublicProfiles) == 1)
        #expect(try await store.fetchPublicProfile(id: profile.id) == nil)
    }

    @Test func profileLinkedToActiveThreadIsPreserved() async throws {
        let store = try makeStore()
        let thread = ExchangeThread(
            mode: .transactional,
            intent: sampleIntent(),
            posture: .default,
            state: .drafting
        )
        let profile = discoveryProfile(id: "profile-linked", nodeID: "node-linked")
        try await store.createThread(thread)
        try await store.savePublicProfiles([profile])

        var linked = thread
        linked.selectedPublicProfileID = profile.id
        try await store.updateThread(linked)

        let result = try await store.runLocalMaintenance(
            policy: ExchangeLocalMaintenancePolicy(remoteDiscoveryCacheRetentionDays: 30),
            reason: "test"
        )

        #expect(result.deletedCount(for: .staleRemotePublicProfiles) == 0)
        #expect(try await store.fetchPublicProfile(id: profile.id) != nil)
    }

    @Test func userOwnedProfileWithPublicationStateIsPreserved() async throws {
        let store = try makeStore()
        var profile = discoveryProfile(id: "profile-owned", nodeID: "node-local-owned")
        ExchangeRemoteDiscoveryCacheMetadata.tagLocalOwnedProfile(&profile, now: staleDate())
        try await store.savePublicProfiles([profile])

        let publication = ExchangePublicationState(
            status: .published,
            publishedAt: staleDate(),
            lastSuccessAt: staleDate()
        )
        try await store.savePublicationState(publication, forPublicProfileID: profile.id)

        let result = try await store.runLocalMaintenance(
            policy: ExchangeLocalMaintenancePolicy(
                remoteDiscoveryCacheRetentionDays: 30,
                localNodeID: "node-local-owned"
            ),
            reason: "test"
        )

        #expect(result.deletedCount(for: .staleRemotePublicProfiles) == 0)
        #expect(try await store.fetchPublicProfile(id: profile.id) != nil)
    }

    @Test func counterpartyLinkedToActiveThreadIsPreserved() async throws {
        let store = try makeStore()
        let thread = ExchangeThread(
            mode: .transactional,
            intent: sampleIntent(),
            posture: .default,
            state: .drafting
        )
        let counterparty = discoveryCounterparty(id: "cp-linked")
        try await store.createThread(thread)
        try await store.upsertCounterparties([counterparty])

        var linked = thread
        linked.selectedCounterpartyID = counterparty.id
        try await store.updateThread(linked)

        let result = try await store.runLocalMaintenance(
            policy: ExchangeLocalMaintenancePolicy(remoteDiscoveryCacheRetentionDays: 30),
            reason: "test"
        )

        #expect(result.deletedCount(for: .staleRemoteCounterparties) == 0)
        #expect(try await store.fetchCounterparty(id: counterparty.id) != nil)
    }

    @Test func staleRemoteCounterpartyWithNoReferencesIsPruned() async throws {
        let store = try makeStore()
        let counterparty = discoveryCounterparty(id: "cp-stale")
        try await store.upsertCounterparties([counterparty])

        let result = try await store.runLocalMaintenance(
            policy: ExchangeLocalMaintenancePolicy(remoteDiscoveryCacheRetentionDays: 30),
            reason: "test"
        )

        #expect(result.deletedCount(for: .staleRemoteCounterparties) == 1)
        #expect(try await store.fetchCounterparty(id: counterparty.id) == nil)
    }

    @Test func recentDiscoveryCacheIsPreserved() async throws {
        let store = try makeStore()
        var profile = ExchangePublicNodeProfile(
            id: "profile-fresh",
            nodeID: "node-fresh",
            displayName: "Fresh",
            visibility: .discoverable,
            availability: .open
        )
        ExchangeRemoteDiscoveryCacheMetadata.tagDiscoveryProfile(&profile, now: Date())
        try await store.savePublicProfiles([profile])

        let result = try await store.runLocalMaintenance(
            policy: ExchangeLocalMaintenancePolicy(remoteDiscoveryCacheRetentionDays: 30),
            reason: "test"
        )

        #expect(result.deletedCount(for: .staleRemotePublicProfiles) == 0)
        #expect(try await store.fetchPublicProfile(id: profile.id) != nil)
    }

    @Test func forYouTaggedStaleCounterpartyIsPruned() async throws {
        let store = try makeStore()
        let counterparty = ExchangeRemoteDiscoveryCacheMetadata.tagForYouCounterparty(
            ExchangeCounterparty(
                id: "cp-foryou-stale",
                createdAt: staleDate(),
                updatedAt: staleDate(),
                kind: .provider,
                displayName: "For You",
                source: .localDirectory,
                identity: .init(nodeID: "cp-foryou-stale", publicKeyID: nil, verification: .unverified)
            ),
            now: staleDate()
        )
        try await store.upsertCounterparties([counterparty])

        let result = try await store.runLocalMaintenance(
            policy: ExchangeLocalMaintenancePolicy(
                remoteDiscoveryCacheRetentionDays: 30,
                staleForYouCacheRetentionDays: 30
            ),
            reason: "test"
        )

        #expect(result.deletedCount(for: .staleRemoteCounterparties) == 1)
    }

    @Test func recentOpenInboxRowPreservedOldOpenInboxPruned() async throws {
        let store = try makeStore()
        let old = Date().addingTimeInterval(-200 * 86_400)
        let recent = Date().addingTimeInterval(-2 * 86_400)

        var oldOpen = ExchangeInboxItem(
            envelopeID: "env-open-old",
            processingState: .received,
            visibleSummary: "old open"
        )
        oldOpen.updatedAt = old
        try await store.saveInboxItem(oldOpen)

        var recentOpen = ExchangeInboxItem(
            envelopeID: "env-open-recent",
            processingState: .awaitingOrderingGapResolution,
            visibleSummary: "recent open"
        )
        recentOpen.updatedAt = recent
        try await store.saveInboxItem(recentOpen)

        let result = try await store.runLocalMaintenance(
            policy: ExchangeLocalMaintenancePolicy(staleInboxOpenRetentionDays: 180),
            reason: "test"
        )

        #expect(result.deletedCount(for: .staleInboxOpenRows) == 1)
        let remaining = try await store.listInboxItems(filter: .init())
        let envelopes = Set(remaining.map(\.envelopeID))
        #expect(envelopes.contains("env-open-recent"))
        #expect(!envelopes.contains("env-open-old"))
    }

    @Test func localNodeIDGuardPreservesOwnerNodeProfileWithoutPublicationState() async throws {
        let store = try makeStore()
        let localNodeID = "node-local-guard"
        let localProfile = discoveryProfile(id: "profile-local-guard", nodeID: localNodeID)
        let remoteProfile = discoveryProfile(id: "profile-remote-guard", nodeID: "node-remote-guard")
        try await store.savePublicProfiles([localProfile, remoteProfile])

        let result = try await store.runLocalMaintenance(
            policy: ExchangeLocalMaintenancePolicy(
                remoteDiscoveryCacheRetentionDays: 30,
                localNodeID: localNodeID
            ),
            reason: "test"
        )

        #expect(result.deletedCount(for: .staleRemotePublicProfiles) == 1)
        #expect(try await store.fetchPublicProfile(id: localProfile.id) != nil)
        #expect(try await store.fetchPublicProfile(id: remoteProfile.id) == nil)
    }

}
