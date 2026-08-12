import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeSQLiteStore hard delete thread locally")
struct ExchangeThreadHardDeleteStoreTests {
    private func makeStore() throws -> ExchangeSQLiteStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exchange-hard-delete-\(UUID().uuidString).sqlite")
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

    private func sampleThread(id: UUID = UUID()) -> ExchangeThread {
        ExchangeThread(
            id: id,
            mode: .transactional,
            intent: sampleIntent(),
            posture: .default,
            state: .drafting
        )
    }

    private func sampleCounterparty(id: String = "cp_hard_delete_test") -> ExchangeCounterparty {
        ExchangeCounterparty(
            id: id,
            kind: .provider,
            displayName: "Provider",
            source: .localDirectory,
            identity: .init(nodeID: "node.hard.delete.test", publicKeyID: nil, verification: .selfAsserted)
        )
    }

    @Test func archivePreservesThreadAndTurns() async throws {
        let store = try makeStore()
        let thread = sampleThread()
        try await store.createThread(thread)
        try await store.appendTurn(
            ExchangeTurn(
                threadID: thread.id,
                actor: .user,
                kind: .requestCaptured,
                summary: "hello"
            )
        )

        var archived = try await store.requireThread(id: thread.id)
        archived.metadata["archived"] = "true"
        try await store.updateThread(archived)

        #expect(try await store.fetchThread(id: thread.id) != nil)
        #expect(try await store.listTurns(threadID: thread.id, limit: nil, ascending: true).count == 1)
    }

    @Test func hardDeleteRemovesThreadTurnsDraftsAndMatches() async throws {
        let store = try makeStore()
        let thread = sampleThread()
        let other = sampleThread()
        try await store.createThread(thread)
        try await store.createThread(other)

        try await store.appendTurn(
            ExchangeTurn(threadID: thread.id, actor: .user, kind: .requestCaptured, summary: "one")
        )

        let draft = ExchangeMessageDraft(
            threadID: thread.id,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Draft body",
            posture: .default
        )
        try await store.saveDraft(draft)

        try await store.upsertCounterparties([sampleCounterparty()])
        let match = ExchangeMatch(
            threadID: thread.id,
            counterpartyID: "cp_hard_delete_test",
            strength: .moderate,
            score: 0.8
        )
        try await store.saveMatches([match])

        let report = try await store.hardDeleteThreadLocally(id: thread.id)
        #expect(report != nil)
        #expect(report?.deletedCount(for: .threads) == 1)
        #expect(report?.deletedCount(for: .turns) == 1)
        #expect(report?.deletedCount(for: .drafts) == 1)
        #expect(report?.deletedCount(for: .matches) == 1)

        #expect(try await store.fetchThread(id: thread.id) == nil)
        #expect(try await store.listTurns(threadID: thread.id, limit: nil, ascending: true).isEmpty)
        #expect(try await store.listDrafts(threadID: thread.id).isEmpty)
        #expect(try await store.listMatches(threadID: thread.id, status: nil).isEmpty)
        #expect(try await store.fetchThread(id: other.id) != nil)
    }

    @Test func hardDeleteDoesNotRemoveCounterparty() async throws {
        let store = try makeStore()
        let thread = sampleThread()
        try await store.createThread(thread)
        try await store.upsertCounterparties([sampleCounterparty()])
        try await store.saveMatches([
            ExchangeMatch(
                threadID: thread.id,
                counterpartyID: "cp_hard_delete_test",
                strength: .weak,
                score: 0.5
            )
        ])

        _ = try await store.hardDeleteThreadLocally(id: thread.id)

        #expect(try await store.fetchCounterparty(id: "cp_hard_delete_test") != nil)
    }

    @Test func hardDeleteIsIdempotentWhenThreadMissing() async throws {
        let store = try makeStore()
        let missing = UUID()
        #expect(try await store.hardDeleteThreadLocally(id: missing) == nil)
        #expect(try await store.hardDeleteThreadLocally(id: missing) == nil)
    }

    @Test func hardDeleteRemovesThreadScopedInboxAndAudit() async throws {
        let store = try makeStore()
        let thread = sampleThread()
        try await store.createThread(thread)

        var inbox = ExchangeInboxItem(
            envelopeID: "env-hard-delete",
            threadID: thread.id,
            processingState: .archived,
            visibleSummary: "Inbound"
        )
        try await store.saveInboxItem(inbox)

        try await store.appendAuditRecord(
            ExchangeAuditRecord(
                threadID: thread.id,
                direction: .inbound,
                category: .received,
                actor: .remoteNode,
                summary: "Received"
            )
        )

        _ = try await store.hardDeleteThreadLocally(id: thread.id)

        #expect(try await store.listInboxItems(filter: .init(threadID: thread.id)).isEmpty)
        #expect(try await store.listAuditRecords(filter: .init(threadID: thread.id)).isEmpty)
    }
}
