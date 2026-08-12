import Foundation
import SQLite3
import Testing
@testable import AnumCore

@Suite("ExchangeSQLiteStore local maintenance")
struct ExchangeLocalMaintenanceStoreTests {
    private func makeStore() throws -> (ExchangeSQLiteStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exchange-maint-\(UUID().uuidString).sqlite")
        let store = try ExchangeSQLiteStore(databaseURL: url)
        return (store, url)
    }

    private func iso(_ date: Date) -> String {
        ExchangeSQLiteStore.isoString(from: date)
    }

    private func execRaw(at url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw ExchangeStoreError.storageFailure(reason: "Could not open test database.")
        }
        defer { sqlite3_close(handle) }
        try? execOn(handle, "PRAGMA foreign_keys = OFF;")
        try execOn(handle, sql)
    }

    private func execOn(_ handle: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard rc == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite exec failed"
            sqlite3_free(errorMessage)
            throw ExchangeStoreError.storageFailure(reason: message)
        }
    }

    private func insertOutbox(
        at url: URL,
        id: String,
        isActive: Bool,
        phase: String,
        updatedAt: Date
    ) throws {
        let active = isActive ? 1 : 0
        let updated = iso(updatedAt)
        try execRaw(at: url, """
        INSERT INTO exchange_outbox_items (
            id, thread_id, draft_id, target_node_id, envelope_id,
            created_at, updated_at, is_active,
            delivery_phase, delivery_priority, delivery_external_effect_json,
            attempt_count, policy_json, payload_summary, metadata_json, json_snapshot
        ) VALUES (
            '\(id)', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'node.test', 'env-\(id)',
            '\(updated)', '\(updated)', \(active),
            '\(phase)', 'normal', x'7B7D',
            0, x'7B7D', 'summary', x'7B7D', x'7B7D'
        );
        """)
    }

    @Test func activeOutboxPreservedTerminalOldDeleted() async throws {
        let (store, url) = try makeStore()
        let old = Date().addingTimeInterval(-100 * 86_400)
        let recent = Date().addingTimeInterval(-2 * 86_400)

        try insertOutbox(at: url, id: "active-queued", isActive: true, phase: "queued", updatedAt: old)
        try insertOutbox(at: url, id: "old-terminal", isActive: false, phase: "acknowledged", updatedAt: old)
        try insertOutbox(at: url, id: "recent-terminal", isActive: false, phase: "acknowledged", updatedAt: recent)

        let result = try await store.runLocalMaintenance(
            policy: ExchangeLocalMaintenancePolicy(retentionDays: 90),
            reason: "test"
        )

        #expect(result.deletedCount(for: .outbox) == 1)
        let remaining = try await store.listOutboxItems(filter: .init())
        let ids = Set(remaining.map { $0.id.uuidString })
        #expect(ids.contains("active-queued"))
        #expect(ids.contains("recent-terminal"))
        #expect(!ids.contains("old-terminal"))
    }

    @Test func inboxActivePreservedArchivedOldDeleted() async throws {
        let (store, _) = try makeStore()
        let old = Date().addingTimeInterval(-100 * 86_400)
        let recent = Date().addingTimeInterval(-2 * 86_400)

        var active = ExchangeInboxItem(
            envelopeID: "env-active",
            processingState: .received,
            visibleSummary: "active"
        )
        active.updatedAt = old
        try await store.saveInboxItem(active)

        var archivedOld = ExchangeInboxItem(
            envelopeID: "env-archived-old",
            processingState: .archived,
            visibleSummary: "archived"
        )
        archivedOld.updatedAt = old
        try await store.saveInboxItem(archivedOld)

        var archivedRecent = ExchangeInboxItem(
            envelopeID: "env-archived-recent",
            processingState: .archived,
            visibleSummary: "archived recent"
        )
        archivedRecent.updatedAt = recent
        try await store.saveInboxItem(archivedRecent)

        let result = try await store.runLocalMaintenance(reason: "test")
        #expect(result.deletedCount(for: .inbox) == 1)

        let remaining = try await store.listInboxItems(filter: .init())
        let envelopes = Set(remaining.map(\.envelopeID))
        #expect(envelopes.contains("env-active"))
        #expect(envelopes.contains("env-archived-recent"))
        #expect(!envelopes.contains("env-archived-old"))
    }

    @Test func auditAgeAndCapPruning() async throws {
        let (store, _) = try makeStore()
        let old = Date().addingTimeInterval(-120 * 86_400)
        let recent = Date()

        for index in 0..<12 {
            let record = ExchangeAuditRecord(
                createdAt: index < 2 ? old : recent,
                direction: .localOnly,
                category: .received,
                actor: .system,
                summary: "audit-\(index)"
            )
            try await store.appendAuditRecord(record)
        }

        let policy = ExchangeLocalMaintenancePolicy(retentionDays: 90, maxAuditRecords: 5)
        let result = try await store.runLocalMaintenance(policy: policy, reason: "test")
        #expect(result.deletedCount(for: .audit) >= 7)

        let remaining = try await store.listAuditRecords(filter: .init())
        #expect(remaining.count <= 5)
    }

    @Test func unreadNotificationPreservedReadOldDeleted() async throws {
        let (store, _) = try makeStore()
        let old = Date().addingTimeInterval(-100 * 86_400)

        let unread = SecretaryNotification(
            createdAt: old,
            updatedAt: old,
            kind: .needsAnswer,
            dedupeKey: "unread:1",
            isRead: false,
            title: "Unread",
            body: "Still needed"
        )
        try await store.upsertSecretaryNotification(unread)

        let readOld = SecretaryNotification(
            createdAt: old,
            updatedAt: old,
            kind: .messageSent,
            dedupeKey: "read:1",
            isRead: true,
            title: "Read",
            body: "Dismissed"
        )
        try await store.upsertSecretaryNotification(readOld)

        let result = try await store.runLocalMaintenance(reason: "test")
        #expect(result.deletedCount(for: .secretaryNotifications) == 1)

        let remaining = try await store.listSecretaryNotifications(filter: .init())
        #expect(remaining.count == 1)
        #expect(remaining.first?.dedupeKey == "unread:1")
    }
}
