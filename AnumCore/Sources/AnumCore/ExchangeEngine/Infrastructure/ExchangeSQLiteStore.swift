import Foundation
import SQLite3

// MARK: - DEBUG logging

@inline(__always)
private func exStoreLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    Swift.print(message())
    #endif
}

@inline(__always)
private func exStoreNowMs() -> Double {
    #if DEBUG
    return CFAbsoluteTimeGetCurrent() * 1000.0
    #else
    return 0
    #endif
}

/// Appends a SQL fragment with a guaranteed separator when the base does not end in whitespace.
/// Use for clauses appended after multiline literals (Swift strips the newline before closing `"""`).
private func appendSQLFragment(_ sql: inout String, _ fragment: String) {
    let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    if sql.isEmpty {
        sql = trimmed
        return
    }
    if let last = sql.last, last.isWhitespace || last.isNewline {
        sql += trimmed
    } else {
        sql += "\n" + trimmed
    }
}

private enum ExchangeStoreTaskContext {
    @TaskLocal static var transactionToken: UUID?
}

public actor ExchangeSQLiteStore: ExchangeStore, ExchangeSyncStateStore {
    private final class SQLiteConnection: @unchecked Sendable {
        let raw: OpaquePointer

        init(raw: OpaquePointer) {
            self.raw = raw
        }

        deinit {
            sqlite3_close(raw)
        }
    }

    private let connection: SQLiteConnection
    private var activeTransactionToken: UUID?
    private var transactionWaiters: [CheckedContinuation<Void, Never>] = []
    private var secretarySQLiteHooks = ExchangeSecretarySQLiteHooks.none

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard rc == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database."
            if let handle { sqlite3_close(handle) }
            throw ExchangeStoreError.storageFailure(reason: message)
        }

        do {
            try Self.execOnDB("PRAGMA foreign_keys = ON;", db: handle)
            try Self.execOnDB("PRAGMA journal_mode = WAL;", db: handle)
            try Self.execOnDB("PRAGMA synchronous = NORMAL;", db: handle)
            try Self.execOnDB("PRAGMA temp_store = MEMORY;", db: handle)
            try Self.migrateOnDB(handle)
        } catch {
            sqlite3_close(handle)
            throw error
        }

        self.connection = SQLiteConnection(raw: handle)
    }

    /// Enables Secretary local notification hooks tied to approvals, turns, outbox, and failures.
    public func configureSecretarySQLiteHooks(_ hooks: ExchangeSecretarySQLiteHooks) {
        secretarySQLiteHooks = hooks
    }

    private var db: OpaquePointer { connection.raw }

    // MARK: - Threads

    public func createThread(_ thread: ExchangeThread) async throws {
        await gateForAccess()
        #if DEBUG
        exStoreLog("[ExchangeSQLiteStore] createThread id=\(thread.id.uuidString) state=\(ExchangeTransition.ExchangeStateKey(thread.state).rawValue) title=\(thread.title)")
        #endif

        if try await fetchThread(id: thread.id) != nil {
            throw ExchangeStoreError.conflict(reason: "Thread \(thread.id.uuidString) already exists.")
        }
        try saveThread(thread, bumpRevision: false)
    }

    public func updateThread(_ thread: ExchangeThread) async throws {
        await gateForAccess()
        #if DEBUG
        exStoreLog(
            "[ExchangeSQLiteStore] updateThread " +
            "id=\(thread.id.uuidString) " +
            "state=\(ExchangeTransition.ExchangeStateKey(thread.state).rawValue) " +
            "selected=\(thread.selectedCounterpartyID ?? "nil") " +
            "failure=\(thread.latestFailure?.id.uuidString ?? "nil") " +
            "secondHalf=\(thread.secondHalf == nil ? "nil" : "rev-\(thread.secondHalf!.revision)")"
        )
        #endif

        try saveThread(thread, bumpRevision: true)
        if let failure = thread.latestFailure {
            await secretarySQLiteHooks.onFailurePersisted?(thread.id, failure)
        }
    }

    public func listDirectMessageThreadCandidates(
        counterpartyNodeID: String,
        limit: Int
    ) async throws -> [ExchangeThread] {
        await gateForAccess()

        let trimmed = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let boundedLimit = max(1, min(limit, 32))

        let rows = try queryHydratedThreads(
            sql: """
            SELECT json_snapshot, metadata_json
            FROM exchange_threads
            WHERE selected_counterparty_id = ?1
            ORDER BY updated_at DESC
            LIMIT \(boundedLimit);
            """,
            bind: { stmt in bindText(stmt, 1, trimmed) }
        )

        #if DEBUG
        exStoreLog(
            "[ExchangeSQLiteStore] listDirectMessageThreadCandidates " +
            "counterparty=\(trimmed) count=\(rows.count) limit=\(boundedLimit)"
        )
        #endif

        return rows
    }

    public func fetchThread(id: ExchangeThread.ID) async throws -> ExchangeThread? {
        await gateForAccess()

        let thread = try fetchHydratedThread(
            sql: "SELECT json_snapshot, metadata_json FROM exchange_threads WHERE id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, id.uuidString) }
        )

        #if DEBUG
        exStoreLog(
            "[ExchangeSQLiteStore] fetchThread " +
            "id=\(id.uuidString) " +
            "found=\(thread != nil) " +
            "secondHalf=\(thread?.secondHalf == nil ? "nil" : "rev-\(thread!.secondHalf!.revision)") " +
            "discoveryGrade=\(thread.flatMap { ExchangeThreadDiscoveryGradeMetadata.snapshot(from: $0.metadata).projectedGrade?.rawValue } ?? "nil")"
        )
        #endif

        return thread
    }

    public func listThreads(filter: ExchangeThreadFilter) async throws -> [ExchangeThread] {
        await gateForAccess()

        if let limit = filter.limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT json_snapshot, metadata_json
        FROM exchange_threads
        WHERE 1=1
        """
        var bindValues: [String] = []

        if let states = filter.states, !states.isEmpty {
            let sorted = states.sorted { $0.rawValue < $1.rawValue }
            let placeholders = Array(repeating: "?", count: sorted.count).joined(separator: ", ")
            sql += " AND state_key IN (\(placeholders))"
            bindValues.append(contentsOf: sorted.map(\.rawValue))
        }

        if filter.requiresHumanDecisionOnly {
            sql += " AND requires_human_decision = 1"
        }

        if let updatedAfter = filter.updatedAfter {
            sql += " AND updated_at >= ?"
            bindValues.append(Self.isoString(from: updatedAfter))
        }

        if let updatedBefore = filter.updatedBefore {
            sql += " AND updated_at <= ?"
            bindValues.append(Self.isoString(from: updatedBefore))
        }

        sql += " ORDER BY updated_at DESC"

        if let limit = filter.limit {
            sql += " LIMIT \(limit)"
        }

        let rows = try queryHydratedThreads(
            sql: sql,
            bind: { stmt in
                for (idx, value) in bindValues.enumerated() {
                    bindText(stmt, Int32(idx + 1), value)
                }
            }
        )

        #if DEBUG
        exStoreLog("[ExchangeSQLiteStore] listThreads count=\(rows.count) requiresHumanDecisionOnly=\(filter.requiresHumanDecisionOnly) limit=\(filter.limit.map(String.init) ?? "nil")")
        #endif

        return rows
    }

    /// Hard-deletes one thread and all safely linked local rows. Does not delete counterparties, public profiles, or remote data.
    ///
    /// `archiveThread` remains metadata-only and must not call this method.
    public func hardDeleteThreadLocally(id: ExchangeThread.ID) async throws -> ExchangeThreadLocalDeleteReport? {
        await gateForAccess()
        guard try await fetchThread(id: id) != nil else {
            #if DEBUG
            exStoreLog("[ExchangeSQLiteStore] hardDeleteThreadLocally id=\(id.uuidString) notFound")
            #endif
            return nil
        }

        var deletedCounts: [ExchangeThreadLocalDeleteTable: Int] = [:]

        try await performExclusiveSQLiteTransaction {
            let threadIDText = id.uuidString
            deletedCounts[.audit] = try deleteThreadScopedRows(
                sql: """
                DELETE FROM exchange_audit_records
                WHERE thread_id = ?1
                   OR outbox_item_id IN (
                        SELECT id FROM exchange_outbox_items WHERE thread_id = ?2
                   )
                   OR inbox_item_id IN (
                        SELECT id FROM exchange_inbox_items WHERE thread_id = ?3
                   );
                """,
                bindValues: [threadIDText, threadIDText, threadIDText]
            )
            deletedCounts[.inbox] = try deleteThreadScopedRows(
                sql: "DELETE FROM exchange_inbox_items WHERE thread_id = ?1;",
                bindValues: [threadIDText]
            )
            deletedCounts[.secretaryNotifications] = try deleteThreadScopedRows(
                sql: "DELETE FROM exchange_secretary_notifications WHERE thread_id = ?1;",
                bindValues: [threadIDText]
            )
            deletedCounts[.trustEvidence] = try deleteThreadScopedRows(
                sql: "DELETE FROM exchange_trust_evidence WHERE thread_id = ?1;",
                bindValues: [threadIDText]
            )
            deletedCounts[.failures] = try deleteThreadScopedRows(
                sql: "DELETE FROM exchange_failures WHERE thread_id = ?1;",
                bindValues: [threadIDText]
            )

            let cascadeCounts = try countThreadCascadeRows(threadID: id)
            deletedCounts[.threads] = try deleteThreadScopedRows(
                sql: "DELETE FROM exchange_threads WHERE id = ?1;",
                bindValues: [threadIDText]
            )
            deletedCounts[.turns] = cascadeCounts.turns
            deletedCounts[.drafts] = cascadeCounts.drafts
            deletedCounts[.approvals] = cascadeCounts.approvals
            deletedCounts[.outcomes] = cascadeCounts.outcomes
            deletedCounts[.matches] = cascadeCounts.matches
            deletedCounts[.artifacts] = cascadeCounts.artifacts
            deletedCounts[.outbox] = cascadeCounts.outbox
        }

        let report = ExchangeThreadLocalDeleteReport(threadID: id, deletedCounts: deletedCounts)
        #if DEBUG
        exStoreLog(
            "[ExchangeSQLiteStore] hardDeleteThreadLocally id=\(id.uuidString) " +
            "total=\(report.totalDeleted)"
        )
        #endif
        return report
    }

    // MARK: - Turns

    public func appendTurn(_ turn: ExchangeTurn) async throws {
        await gateForAccess()

        #if DEBUG
        exStoreLog("[ExchangeSQLiteStore] appendTurn id=\(turn.id.uuidString) thread=\(turn.threadID.uuidString) kind=\(turn.kind.rawValue) actor=\(turn.actor.rawValue)")
        #endif

        if let failure = turn.failure {
            try saveFailure(failure, threadID: turn.threadID)
        }

        let metadataJSON = try encodeJSON(turn.metadata)
        let snapshot = try encode(turn)
        let visibilityMask = Int64(turn.visibility.rawValue)

        try withStatement("""
            INSERT INTO exchange_turns (
                id, thread_id, created_at, actor, kind, summary, detail,
                visibility, visibility_mask, external_reference, failure_id, metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13);
            """
        ) { stmt in
            bindText(stmt, 1, turn.id.uuidString)
            bindText(stmt, 2, turn.threadID.uuidString)
            bindText(stmt, 3, Self.isoString(from: turn.createdAt))
            bindText(stmt, 4, turn.actor.rawValue)
            bindText(stmt, 5, turn.kind.rawValue)
            bindText(stmt, 6, turn.summary)
            bindNullableText(stmt, 7, turn.detail)
            bindText(stmt, 8, turn.visibility.isInternalOnly ? "internalOnly" : "userVisible")
            sqlite3_bind_int64(stmt, 9, visibilityMask)
            bindNullableText(stmt, 10, turn.externalReference)
            bindNullableText(stmt, 11, turn.failure?.id.uuidString)
            bindBlob(stmt, 12, metadataJSON)
            bindBlob(stmt, 13, snapshot)
            try stepDone(stmt)
        }

        await secretarySQLiteHooks.onTurnAppended?(turn)

        if let failure = turn.failure {
            await secretarySQLiteHooks.onFailurePersisted?(turn.threadID, failure)
        }
    }

    public func listTurns(
        threadID: ExchangeThread.ID,
        limit: Int?,
        ascending: Bool
    ) async throws -> [ExchangeTurn] {
        await gateForAccess()

        if let limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT json_snapshot
        FROM exchange_turns
        WHERE thread_id = ?1
        ORDER BY created_at \(ascending ? "ASC" : "DESC")
        """

        if let limit {
            sql += " LIMIT \(limit)"
        }

        let rows = try querySnapshots(
            sql: sql,
            bind: { stmt in bindText(stmt, 1, threadID.uuidString) },
            as: ExchangeTurn.self
        )

        #if DEBUG
        exStoreLog("[ExchangeSQLiteStore] listTurns thread=\(threadID.uuidString) count=\(rows.count) ascending=\(ascending) limit=\(limit.map(String.init) ?? "nil")")
        #endif

        return rows
    }

    // MARK: - Approvals

    public func saveApproval(_ approval: ExchangeApproval) async throws {
        await gateForAccess()

        let requestedActionJSON = try encode(approval.requestedAction)
        let metadataJSON = try encodeJSON(approval.metadata)
        let snapshot = try encode(approval)
        let revision = try nextRevision(
            table: "exchange_approvals",
            id: approval.id.uuidString
        )

        try withStatement("""
            INSERT INTO exchange_approvals (
                id, thread_id, created_at, updated_at, revision, status, kind, draft_id,
                summary, rationale, expires_at, decided_at, decision_note,
                requested_action_json, metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
            ON CONFLICT(id) DO UPDATE SET
                thread_id = excluded.thread_id,
                updated_at = excluded.updated_at,
                revision = excluded.revision,
                status = excluded.status,
                kind = excluded.kind,
                draft_id = excluded.draft_id,
                summary = excluded.summary,
                rationale = excluded.rationale,
                expires_at = excluded.expires_at,
                decided_at = excluded.decided_at,
                decision_note = excluded.decision_note,
                requested_action_json = excluded.requested_action_json,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, approval.id.uuidString)
            bindText(stmt, 2, approval.threadID.uuidString)
            bindText(stmt, 3, Self.isoString(from: approval.createdAt))
            bindText(stmt, 4, Self.isoString(from: approval.updatedAt))
            sqlite3_bind_int64(stmt, 5, revision)
            bindText(stmt, 6, approval.status.rawValue)
            bindText(stmt, 7, approval.kind.rawValue)
            bindNullableText(stmt, 8, approval.draftID?.uuidString)
            bindText(stmt, 9, approval.summary)
            bindNullableText(stmt, 10, approval.rationale)
            bindNullableText(stmt, 11, approval.expiresAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 12, approval.decidedAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 13, approval.decisionNote)
            bindBlob(stmt, 14, requestedActionJSON)
            bindBlob(stmt, 15, metadataJSON)
            bindBlob(stmt, 16, snapshot)
            try stepDone(stmt)
        }

        await secretarySQLiteHooks.onApprovalSaved?(approval)
    }

    public func fetchApproval(id: ExchangeApproval.ID) async throws -> ExchangeApproval? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM exchange_approvals WHERE id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, id.uuidString) },
            as: ExchangeApproval.self
        )
    }

    public func fetchLatestApproval(threadID: ExchangeThread.ID) async throws -> ExchangeApproval? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: """
            SELECT json_snapshot
            FROM exchange_approvals
            WHERE thread_id = ?1
            ORDER BY updated_at DESC
            LIMIT 1;
            """,
            bind: { stmt in bindText(stmt, 1, threadID.uuidString) },
            as: ExchangeApproval.self
        )
    }

    public func listLatestPendingApprovals() async throws -> [ExchangeApproval] {
        await gateForAccess()

        return try querySnapshots(
            sql: """
            SELECT a.json_snapshot
            FROM exchange_approvals a
            INNER JOIN (
                SELECT thread_id, MAX(updated_at) AS max_updated_at
                FROM exchange_approvals
                GROUP BY thread_id
            ) latest
                ON latest.thread_id = a.thread_id
               AND latest.max_updated_at = a.updated_at
            WHERE a.status = ?1
            ORDER BY a.updated_at DESC;
            """,
            bind: { stmt in bindText(stmt, 1, ExchangeApproval.Status.pending.rawValue) },
            as: ExchangeApproval.self
        )
    }

    // MARK: - Drafts

    public func saveDraft(_ draft: ExchangeMessageDraft) async throws {
        await gateForAccess()

        let postureJSON = try encode(draft.posture)
        let metadataJSON = try encodeJSON(draft.metadata)
        let snapshot = try encode(draft)
        let revision = try nextRevision(table: "exchange_drafts", id: draft.id.uuidString)

        try withStatement("""
            INSERT INTO exchange_drafts (
                id, thread_id, created_at, updated_at, revision, status, kind, audience,
                subject, body, strategy_note, target_counterparty_id, supersedes_draft_id,
                sent_external_reference, posture_json, metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
            ON CONFLICT(id) DO UPDATE SET
                thread_id = excluded.thread_id,
                updated_at = excluded.updated_at,
                revision = excluded.revision,
                status = excluded.status,
                kind = excluded.kind,
                audience = excluded.audience,
                subject = excluded.subject,
                body = excluded.body,
                strategy_note = excluded.strategy_note,
                target_counterparty_id = excluded.target_counterparty_id,
                supersedes_draft_id = excluded.supersedes_draft_id,
                sent_external_reference = excluded.sent_external_reference,
                posture_json = excluded.posture_json,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, draft.id.uuidString)
            bindText(stmt, 2, draft.threadID.uuidString)
            bindText(stmt, 3, Self.isoString(from: draft.createdAt))
            bindText(stmt, 4, Self.isoString(from: draft.updatedAt))
            sqlite3_bind_int64(stmt, 5, revision)
            bindText(stmt, 6, draft.status.rawValue)
            bindText(stmt, 7, draft.kind.rawValue)
            bindText(stmt, 8, draft.audience.rawValue)
            bindNullableText(stmt, 9, draft.subject)
            bindText(stmt, 10, draft.body)
            bindNullableText(stmt, 11, draft.strategyNote)
            bindNullableText(stmt, 12, draft.targetCounterpartyID)
            bindNullableText(stmt, 13, draft.supersedesDraftID?.uuidString)
            bindNullableText(stmt, 14, draft.sentExternalReference)
            bindBlob(stmt, 15, postureJSON)
            bindBlob(stmt, 16, metadataJSON)
            bindBlob(stmt, 17, snapshot)
            try stepDone(stmt)
        }
    }

    public func fetchDraft(id: ExchangeMessageDraft.ID) async throws -> ExchangeMessageDraft? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM exchange_drafts WHERE id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, id.uuidString) },
            as: ExchangeMessageDraft.self
        )
    }

    public func listDrafts(threadID: ExchangeThread.ID) async throws -> [ExchangeMessageDraft] {
        await gateForAccess()

        return try querySnapshots(
            sql: """
            SELECT json_snapshot
            FROM exchange_drafts
            WHERE thread_id = ?1
            ORDER BY updated_at DESC;
            """,
            bind: { stmt in bindText(stmt, 1, threadID.uuidString) },
            as: ExchangeMessageDraft.self
        )
    }

    // MARK: - Outcomes

    public func saveOutcome(_ outcome: ExchangeOutcome) async throws {
        await gateForAccess()

        let externalEffectJSON = try encode(outcome.externalEffect)
        let metadataJSON = try encodeJSON(outcome.metadata)
        let snapshot = try encode(outcome)

        try withStatement("""
            INSERT INTO exchange_outcomes (
                id, thread_id, created_at, status, category, summary,
                what_happened, what_did_not_happen, recommended_next_step,
                failure_id, external_effect_json, metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
            ON CONFLICT(id) DO UPDATE SET
                thread_id = excluded.thread_id,
                status = excluded.status,
                category = excluded.category,
                summary = excluded.summary,
                what_happened = excluded.what_happened,
                what_did_not_happen = excluded.what_did_not_happen,
                recommended_next_step = excluded.recommended_next_step,
                failure_id = excluded.failure_id,
                external_effect_json = excluded.external_effect_json,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, outcome.id.uuidString)
            bindText(stmt, 2, outcome.threadID.uuidString)
            bindText(stmt, 3, Self.isoString(from: outcome.createdAt))
            bindText(stmt, 4, outcome.status.rawValue)
            bindText(stmt, 5, outcome.category.rawValue)
            bindText(stmt, 6, outcome.summary)
            bindText(stmt, 7, outcome.whatHappened)
            bindText(stmt, 8, outcome.whatDidNotHappen)
            bindNullableText(stmt, 9, outcome.recommendedNextStep)
            bindNullableText(stmt, 10, outcome.failureID?.uuidString)
            bindBlob(stmt, 11, externalEffectJSON)
            bindBlob(stmt, 12, metadataJSON)
            bindBlob(stmt, 13, snapshot)
            try stepDone(stmt)
        }
    }

    public func fetchLatestOutcome(threadID: ExchangeThread.ID) async throws -> ExchangeOutcome? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: """
            SELECT json_snapshot
            FROM exchange_outcomes
            WHERE thread_id = ?1
            ORDER BY created_at DESC
            LIMIT 1;
            """,
            bind: { stmt in bindText(stmt, 1, threadID.uuidString) },
            as: ExchangeOutcome.self
        )
    }

    // MARK: - Discovery
    
    public func saveMatches(_ matches: [ExchangeMatch]) async throws {
        await gateForAccess()

        var seenReasonIDs = Set<UUID>()
        var seenCautionIDs = Set<UUID>()
        seenReasonIDs.reserveCapacity(matches.count * 4)
        seenCautionIDs.reserveCapacity(matches.count * 2)

        for match in matches {
            let normalized = match.ensuringUniqueNestedIDs(
                seenReasonIDs: &seenReasonIDs,
                seenCautionIDs: &seenCautionIDs
            )
            try saveMatch(normalized)
        }
    }
    
    public func upsertCounterparties(_ counterparties: [ExchangeCounterparty]) async throws {
        await gateForAccess()

        for counterparty in counterparties {
            try saveCounterparty(counterparty)
        }
    }

    public func fetchCounterparty(id: ExchangeCounterparty.ID) async throws -> ExchangeCounterparty? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM exchange_counterparties WHERE id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, id) },
            as: ExchangeCounterparty.self
        )
    }

    public func listCounterparties(filter: ExchangeCounterpartyFilter) async throws -> [ExchangeCounterparty] {
        await gateForAccess()

        if let limit = filter.limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        let requestedLimit = max(1, filter.limit ?? 24)
        let workingLimit = max(requestedLimit * 6, 60)

        let normalizedQuery = normalizedCounterpartySearchQuery(from: filter.searchText)
        let normalizedTags = normalizedCounterpartySearchValues(
            Array(filter.tags),
            maxCount: 24,
            maxLength: 80
        )

        let hasSearchSignal = normalizedQuery != nil || !normalizedTags.isEmpty

        var sql = """
        WITH aggregated AS (
            SELECT
                c.id,
                c.json_snapshot,
                c.updated_at,
                c.status,
                c.trust_level,
                LOWER(COALESCE(c.display_name, '')) AS display_name_lc,
                LOWER(COALESCE(c.handle, '')) AS handle_lc,
                LOWER(COALESCE(c.bio, '')) AS bio_lc,
                LOWER(COALESCE((
                    SELECT REPLACE(GROUP_CONCAT(DISTINCT t.tag), ',', ' ')
                    FROM exchange_counterparty_tags t
                    WHERE t.counterparty_id = c.id
                ), '')) AS tags_lc,
                LOWER(COALESCE((
                    SELECT REPLACE(GROUP_CONCAT(DISTINCT cap.label), ',', ' ')
                    FROM exchange_counterparty_capabilities cap
                    WHERE cap.counterparty_id = c.id
                ), '')) AS capability_labels_lc,
                LOWER(COALESCE((
                    SELECT REPLACE(GROUP_CONCAT(DISTINCT cap.category), ',', ' ')
                    FROM exchange_counterparty_capabilities cap
                    WHERE cap.counterparty_id = c.id
                      AND cap.category IS NOT NULL
                ), '')) AS capability_categories_lc,
                LOWER(COALESCE((
                    SELECT REPLACE(GROUP_CONCAT(DISTINCT cap.notes), ',', ' ')
                    FROM exchange_counterparty_capabilities cap
                    WHERE cap.counterparty_id = c.id
                      AND cap.notes IS NOT NULL
                ), '')) AS capability_notes_lc
            FROM exchange_counterparties c
        )
        SELECT
            a.json_snapshot,
            (
                0
        """

        var scoreBindValues: [String] = []

        if let normalizedQuery {
            let pattern = "%\(normalizedQuery.lowercased())%"

            sql += """
             + CASE WHEN a.display_name_lc LIKE ? THEN 120 ELSE 0 END
             + CASE WHEN a.handle_lc LIKE ? THEN 90 ELSE 0 END
             + CASE WHEN a.capability_labels_lc LIKE ? THEN 80 ELSE 0 END
             + CASE WHEN a.capability_categories_lc LIKE ? THEN 65 ELSE 0 END
             + CASE WHEN a.tags_lc LIKE ? THEN 60 ELSE 0 END
             + CASE WHEN a.bio_lc LIKE ? THEN 40 ELSE 0 END
             + CASE WHEN a.capability_notes_lc LIKE ? THEN 30 ELSE 0 END
            """

            scoreBindValues.append(pattern)
            scoreBindValues.append(pattern)
            scoreBindValues.append(pattern)
            scoreBindValues.append(pattern)
            scoreBindValues.append(pattern)
            scoreBindValues.append(pattern)
            scoreBindValues.append(pattern)
        }

        for tag in normalizedTags {
            let pattern = "%\(tag.lowercased())%"

            sql += """
             + CASE WHEN a.tags_lc LIKE ? THEN 70 ELSE 0 END
             + CASE WHEN a.capability_categories_lc LIKE ? THEN 40 ELSE 0 END
             + CASE WHEN a.capability_labels_lc LIKE ? THEN 24 ELSE 0 END
            """

            scoreBindValues.append(pattern)
            scoreBindValues.append(pattern)
            scoreBindValues.append(pattern)
        }

        sql += """
             + CASE a.trust_level
                 WHEN 'high' THEN 18
                 WHEN 'moderate' THEN 10
                 WHEN 'low' THEN 4
                 ELSE 0
               END
             + CASE WHEN a.status = 'active' THEN 8 ELSE 0 END
            ) AS retrieval_score
        FROM aggregated a
        WHERE 1=1
        """

        var whereBindValues: [String] = []

        if let status = filter.status, !status.isEmpty {
            let statuses = status.sorted { $0.rawValue < $1.rawValue }
            sql += " AND a.status IN (\(Array(repeating: "?", count: statuses.count).joined(separator: ", ")))"
            whereBindValues.append(contentsOf: statuses.map(\.rawValue))
        }

        if let trustLevels = filter.trustLevels, !trustLevels.isEmpty {
            let levels = trustLevels.sorted { $0.rawValue < $1.rawValue }
            sql += " AND a.trust_level IN (\(Array(repeating: "?", count: levels.count).joined(separator: ", ")))"
            whereBindValues.append(contentsOf: levels.map(\.rawValue))
        }

        if hasSearchSignal {
            var recallClauses: [String] = []
            var recallBindValues: [String] = []

            if let normalizedQuery {
                let pattern = "%\(normalizedQuery.lowercased())%"
                recallClauses.append("""
                a.display_name_lc LIKE ?
                OR a.handle_lc LIKE ?
                OR a.bio_lc LIKE ?
                OR a.tags_lc LIKE ?
                OR a.capability_labels_lc LIKE ?
                OR a.capability_categories_lc LIKE ?
                OR a.capability_notes_lc LIKE ?
                """)
                recallBindValues.append(pattern)
                recallBindValues.append(pattern)
                recallBindValues.append(pattern)
                recallBindValues.append(pattern)
                recallBindValues.append(pattern)
                recallBindValues.append(pattern)
                recallBindValues.append(pattern)
            }

            for tag in normalizedTags {
                let pattern = "%\(tag.lowercased())%"
                recallClauses.append("""
                a.tags_lc LIKE ?
                OR a.capability_categories_lc LIKE ?
                OR a.capability_labels_lc LIKE ?
                """)
                recallBindValues.append(pattern)
                recallBindValues.append(pattern)
                recallBindValues.append(pattern)
            }

            if !recallClauses.isEmpty {
                sql += " AND ("
                sql += recallClauses.map { "(\($0))" }.joined(separator: " OR ")
                sql += ")"
                whereBindValues.append(contentsOf: recallBindValues)
            }
        }

        appendSQLFragment(&sql, "ORDER BY retrieval_score DESC, a.updated_at DESC")
        appendSQLFragment(&sql, "LIMIT \(workingLimit)")

        let rows = try withStatementAndResult(
            sql,
            bind: { stmt in
                var bindIndex: Int32 = 1

                for value in scoreBindValues {
                    bindText(stmt, bindIndex, value)
                    bindIndex += 1
                }

                for value in whereBindValues {
                    bindText(stmt, bindIndex, value)
                    bindIndex += 1
                }
            }
        ) { stmt in
            var seen = Set<String>()
            var items: [ExchangeCounterparty] = []

            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW {
                    let snapshot = try blobColumn(stmt, index: 0)
                    let counterparty = try decode(ExchangeCounterparty.self, from: snapshot)

                    guard !seen.contains(counterparty.id) else { continue }
                    seen.insert(counterparty.id)
                    items.append(counterparty)

                    if items.count >= requestedLimit {
                        break
                    }
                } else if rc == SQLITE_DONE {
                    break
                } else {
                    throw sqliteError()
                }
            }

            return items
        }

        #if DEBUG
        exStoreLog(
            "[ExchangeSQLiteStore] listCounterparties " +
            "query=\(normalizedQuery ?? "nil") " +
            "tags=\(normalizedTags) " +
            "requestedLimit=\(requestedLimit) " +
            "returned=\(rows.count)"
        )
        #endif

        return rows
    }

    func saveMatch(_ match: ExchangeMatch) throws {
        let fitJSON = try encode(match.fit)
        let metadataJSON = try encodeJSON(match.metadata)
        let matchedOfferIDsJSON = try encode(match.matchedOfferIDs)
        let snapshot = try encode(match)

        #if DEBUG
        let reasonIDStrings = match.reasons.map(\.id.uuidString)
        let uniqueReasonIDCount = Set(reasonIDStrings).count
        exStoreLog(
            "[ExchangeSQLiteStore] saveMatch " +
            "threadID=\(match.threadID.uuidString) " +
            "matchID=\(match.id.uuidString) " +
            "reasonIDsCount=\(reasonIDStrings.count) " +
            "duplicateReasonIDsCount=\(max(0, reasonIDStrings.count - uniqueReasonIDCount))"
        )
        #endif

        try withStatement("""
            INSERT INTO exchange_matches (
                id,
                thread_id,
                counterparty_id,
                scope,
                public_profile_id,
                offer_id,
                matched_offer_ids_json,
                created_at,
                status,
                strength,
                score,
                recommendation,
                fit_json,
                metadata_json,
                json_snapshot
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15
            )
            ON CONFLICT(id) DO UPDATE SET
                thread_id = excluded.thread_id,
                counterparty_id = excluded.counterparty_id,
                scope = excluded.scope,
                public_profile_id = excluded.public_profile_id,
                offer_id = excluded.offer_id,
                matched_offer_ids_json = excluded.matched_offer_ids_json,
                status = excluded.status,
                strength = excluded.strength,
                score = excluded.score,
                recommendation = excluded.recommendation,
                fit_json = excluded.fit_json,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, match.id.uuidString)
            bindText(stmt, 2, match.threadID.uuidString)
            bindText(stmt, 3, match.counterpartyID)
            bindText(stmt, 4, match.scope.rawValue)
            bindNullableText(stmt, 5, match.publicProfileID)
            bindNullableText(stmt, 6, match.offerID)
            bindBlob(stmt, 7, matchedOfferIDsJSON)
            bindText(stmt, 8, Self.isoString(from: match.createdAt))
            bindText(stmt, 9, match.status.rawValue)
            bindText(stmt, 10, match.strength.rawValue)
            sqlite3_bind_double(stmt, 11, match.score)
            bindNullableText(stmt, 12, match.recommendation)
            bindBlob(stmt, 13, fitJSON)
            bindBlob(stmt, 14, metadataJSON)
            bindBlob(stmt, 15, snapshot)
            try stepDone(stmt)
        }

        try withStatement("DELETE FROM exchange_match_reasons WHERE match_id = ?1;") { stmt in
            bindText(stmt, 1, match.id.uuidString)
            try stepDone(stmt)
        }

        try withStatement("DELETE FROM exchange_match_cautions WHERE match_id = ?1;") { stmt in
            bindText(stmt, 1, match.id.uuidString)
            try stepDone(stmt)
        }

        for reason in match.reasons {
            try withStatement("""
                INSERT INTO exchange_match_reasons (id, match_id, kind, summary)
                VALUES (?1, ?2, ?3, ?4);
                """
            ) { stmt in
                bindText(stmt, 1, reason.id.uuidString)
                bindText(stmt, 2, match.id.uuidString)
                bindText(stmt, 3, reason.kind.rawValue)
                bindText(stmt, 4, reason.summary)
                try stepDone(stmt)
            }
        }

        for caution in match.cautions {
            try withStatement("""
                INSERT INTO exchange_match_cautions (id, match_id, kind, summary)
                VALUES (?1, ?2, ?3, ?4);
                """
            ) { stmt in
                bindText(stmt, 1, caution.id.uuidString)
                bindText(stmt, 2, match.id.uuidString)
                bindText(stmt, 3, caution.kind.rawValue)
                bindText(stmt, 4, caution.summary)
                try stepDone(stmt)
            }
        }
    }

    func withStatementAndResult<T>(
        _ sql: String,
        bind: (OpaquePointer?) throws -> Void,
        body: (OpaquePointer?) throws -> T
    ) throws -> T {
        #if DEBUG
        let t0 = exStoreNowMs()
        let oneLineSQL = sql
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        exStoreLog("[ExchangeSQLiteStore] SQL prepare \(oneLineSQL)")
        #endif

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            #if DEBUG
            exStoreLog("[ExchangeSQLiteStore] SQL prepare FAILED err=\(String(cString: sqlite3_errmsg(db)))")
            #endif
            throw sqliteError()
        }

        defer {
            sqlite3_finalize(stmt)
            #if DEBUG
            let dt = exStoreNowMs() - t0
            exStoreLog("[ExchangeSQLiteStore] SQL finalize totalMs=\(Int(dt))")
            #endif
        }

        try bind(stmt)
        return try body(stmt)
    }

    // MARK: - No-mutation search normalization

    func normalizedCounterpartySearchQuery(from query: String?) -> String? {
        guard let query else { return nil }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let collapsed = trimmed.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        let capped = String(collapsed.prefix(160))
        return capped.isEmpty ? nil : capped
    }

    func normalizedCounterpartySearchValues(
        _ values: [String],
        maxCount: Int,
        maxLength: Int
    ) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        output.reserveCapacity(min(values.count, maxCount))

        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let collapsed = trimmed.replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )

            let capped = String(collapsed.prefix(maxLength))
            guard !capped.isEmpty else { continue }

            let dedupeKey = capped.lowercased()
            guard !seen.contains(dedupeKey) else { continue }

            seen.insert(dedupeKey)
            output.append(capped)

            if output.count >= maxCount {
                break
            }
        }

        return output
    }

    public func listMatches(
        threadID: ExchangeThread.ID,
        status: ExchangeMatch.Status?
    ) async throws -> [ExchangeMatch] {
        await gateForAccess()

        var sql = """
        SELECT json_snapshot
        FROM exchange_matches
        WHERE thread_id = ?1
        """
        if status != nil {
            sql += " AND status = ?2"
        }
        sql += " ORDER BY score DESC, created_at DESC;"

        return try querySnapshots(
            sql: sql,
            bind: { stmt in
                bindText(stmt, 1, threadID.uuidString)
                if let status {
                    bindText(stmt, 2, status.rawValue)
                }
            },
            as: ExchangeMatch.self
        )
    }
    
    // MARK: - Public Profiles

    public func savePublicProfile(_ profile: ExchangePublicNodeProfile) async throws {
        await gateForAccess()
        try savePublicProfileRecord(profile)
    }

    public func savePublicProfiles(_ profiles: [ExchangePublicNodeProfile]) async throws {
        await gateForAccess()

        for profile in profiles {
            try savePublicProfileRecord(profile)
        }
    }

    public func fetchPublicProfile(id: ExchangePublicNodeProfile.ID) async throws -> ExchangePublicNodeProfile? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM exchange_public_profiles WHERE id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, id) },
            as: ExchangePublicNodeProfile.self
        )
    }

    public func listPublicProfiles(filter: ExchangePublicProfileFilter) async throws -> [ExchangePublicNodeProfile] {
        await gateForAccess()

        if let limit = filter.limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT json_snapshot
        FROM exchange_public_profiles
        WHERE 1=1
        """
        var bindValues: [String] = []

        if let nodeID = filter.nodeID {
            sql += " AND node_id = ?"
            bindValues.append(nodeID)
        }

        if let counterpartyID = filter.counterpartyID {
            sql += " AND counterparty_id = ?"
            bindValues.append(counterpartyID)
        }

        if let visibility = filter.visibility, !visibility.isEmpty {
            let values = visibility.sorted { $0.rawValue < $1.rawValue }
            sql += " AND visibility IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if let availability = filter.availability, !availability.isEmpty {
            let values = availability.sorted { $0.rawValue < $1.rawValue }
            sql += " AND availability IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if let searchText = filter.searchText {
            let pattern = "%\(searchText.lowercased())%"
            sql += """
             AND (
                LOWER(COALESCE(display_name, '')) LIKE ?
                OR LOWER(COALESCE(headline, '')) LIKE ?
                OR LOWER(COALESCE(summary, '')) LIKE ?
             )
            """
            bindValues.append(pattern)
            bindValues.append(pattern)
            bindValues.append(pattern)
        }

        if !filter.regionTags.isEmpty {
            for tag in filter.regionTags.sorted() {
                sql += " AND LOWER(COALESCE(region_tags_json, '')) LIKE ?"
                bindValues.append("%\(tag.lowercased())%")
            }
        }

        if !filter.activityTags.isEmpty {
            for tag in filter.activityTags.sorted() {
                sql += " AND LOWER(COALESCE(activity_tags_json, '')) LIKE ?"
                bindValues.append("%\(tag.lowercased())%")
            }
        }

        sql += " ORDER BY updated_at DESC"

        if let limit = filter.limit {
            sql += " LIMIT \(limit)"
        }

        return try querySnapshots(
            sql: sql,
            bind: { stmt in
                for (idx, value) in bindValues.enumerated() {
                    bindText(stmt, Int32(idx + 1), value)
                }
            },
            as: ExchangePublicNodeProfile.self
        )
    }
    
    // MARK: - Offers

    public func saveOffers(_ offers: [ExchangeOffer]) async throws {
        await gateForAccess()

        for offer in offers {
            try saveOfferRecord(offer)
        }
    }
    
    public func saveOffer(_ offer: ExchangeOffer) async throws {
        await gateForAccess()
        try saveOfferRecord(offer)
    }

    public func savePublicationState(
        _ state: ExchangePublicationState,
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID
    ) async throws {
        await gateForAccess()
        try savePublicationStateRecord(state, publicProfileID: publicProfileID)
    }

    public func fetchPublicationState(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID
    ) async throws -> ExchangePublicationState? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: """
            SELECT json_snapshot
            FROM exchange_publication_state
            WHERE public_profile_id = ?1
            LIMIT 1;
            """,
            bind: { stmt in
                bindText(stmt, 1, publicProfileID)
            },
            as: ExchangePublicationState.self
        )
    }

    public func fetchOffer(id: ExchangeOffer.ID) async throws -> ExchangeOffer? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM exchange_offers WHERE id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, id) },
            as: ExchangeOffer.self
        )
    }

    public func listOffers(filter: ExchangeOfferFilter) async throws -> [ExchangeOffer] {
        await gateForAccess()

        if let limit = filter.limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT json_snapshot
        FROM exchange_offers
        WHERE 1=1
        """
        var bindValues: [String] = []

        if let nodeID = filter.nodeID {
            sql += " AND node_id = ?"
            bindValues.append(nodeID)
        }

        if let publicProfileID = filter.publicProfileID {
            sql += " AND public_profile_id = ?"
            bindValues.append(publicProfileID)
        }

        if let statuses = filter.statuses, !statuses.isEmpty {
            let values = statuses.sorted { $0.rawValue < $1.rawValue }
            sql += " AND status IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if let visibility = filter.visibility, !visibility.isEmpty {
            let values = visibility.sorted { $0.rawValue < $1.rawValue }
            sql += " AND visibility IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if !filter.categories.isEmpty {
            let values = filter.categories.sorted()
            sql += " AND category IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values)
        }

        if let fulfillmentModes = filter.fulfillmentModes, !fulfillmentModes.isEmpty {
            let values = fulfillmentModes.sorted { $0.rawValue < $1.rawValue }
            let clauses = Array(
                repeating: "LOWER(COALESCE(semantic_json, '')) LIKE ?",
                count: values.count
            ).joined(separator: " OR ")
            sql += " AND (\(clauses))"
            bindValues.append(contentsOf: values.map { "%\($0.rawValue.lowercased())%" })
        }

        if let searchText = filter.searchText {
            let pattern = "%\(searchText.lowercased())%"
            sql += """
             AND (
                LOWER(title) LIKE ?
                OR LOWER(COALESCE(summary, '')) LIKE ?
                OR LOWER(COALESCE(category, '')) LIKE ?
                OR LOWER(COALESCE(tags_json, '')) LIKE ?
                OR LOWER(COALESCE(region_tags_json, '')) LIKE ?
                OR LOWER(COALESCE(semantic_json, '')) LIKE ?
                OR LOWER(COALESCE(fulfillment_json, '')) LIKE ?
             )
            """
            bindValues.append(pattern)
            bindValues.append(pattern)
            bindValues.append(pattern)
            bindValues.append(pattern)
            bindValues.append(pattern)
            bindValues.append(pattern)
            bindValues.append(pattern)
        }

        if let updatedAfter = filter.updatedAfter {
            sql += " AND updated_at >= ?"
            bindValues.append(Self.isoString(from: updatedAfter))
        }

        if let updatedBefore = filter.updatedBefore {
            sql += " AND updated_at <= ?"
            bindValues.append(Self.isoString(from: updatedBefore))
        }

        sql += " ORDER BY updated_at DESC, created_at DESC"

        if let limit = filter.limit {
            sql += " LIMIT \(limit)"
        }

        return try querySnapshots(
            sql: sql,
            bind: { stmt in
                for (idx, value) in bindValues.enumerated() {
                    bindText(stmt, Int32(idx + 1), value)
                }
            },
            as: ExchangeOffer.self
        )
    }
    
    // MARK: - Retrieval Documents

    public func saveRetrievalDocuments(_ documents: [ExchangeRetrievalDocument]) async throws {
        await gateForAccess()

        guard !documents.isEmpty else {
            #if DEBUG
            exStoreLog("[ExchangeSQLiteStore] saveRetrievalDocuments skipped empty")
            #endif
            return
        }

        for document in documents {
            try saveRetrievalDocumentRecord(document)
        }

        #if DEBUG
        let embeddedCount = documents.filter(\.hasEmbedding).count
        let dims = Array(Set(documents.map(\.embeddingDimension).filter { $0 > 0 })).sorted()
        exStoreLog("[ExchangeSQLiteStore] saveRetrievalDocuments count=\(documents.count) embedded=\(embeddedCount) dims=\(dims)")
        #endif
    }

    public func replaceRetrievalDocuments(
        _ documents: [ExchangeRetrievalDocument],
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) async throws {
        await gateForAccess()

        try withStatement("""
            DELETE FROM exchange_retrieval_documents
            WHERE source_kind = ?1;
            """
        ) { stmt in
            bindText(stmt, 1, sourceKind.rawValue)
            try stepDone(stmt)
        }

        for document in documents {
            try saveRetrievalDocumentRecord(document)
        }

        #if DEBUG
        let embeddedCount = documents.filter(\.hasEmbedding).count
        let dims = Array(Set(documents.map(\.embeddingDimension).filter { $0 > 0 })).sorted()
        exStoreLog("[ExchangeSQLiteStore] replaceRetrievalDocuments source=\(sourceKind.rawValue) count=\(documents.count) embedded=\(embeddedCount) dims=\(dims)")
        #endif
    }

    public func fetchRetrievalDocument(id: ExchangeRetrievalDocument.ID) async throws -> ExchangeRetrievalDocument? {
        await gateForAccess()

        return try fetchRetrievalDocumentRecord(id: id)
    }

    public func listRetrievalDocuments(
        sourceKind: ExchangeRetrievalDocument.SourceKind? = nil,
        ownerNodeID: String? = nil,
        publicProfileID: String? = nil,
        offerID: String? = nil,
        limit: Int? = nil
    ) async throws -> [ExchangeRetrievalDocument] {
        await gateForAccess()

        if let limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT d.json_snapshot, e.embedding_json
        FROM exchange_retrieval_documents d
        LEFT JOIN exchange_retrieval_embeddings e
            ON e.document_id = d.id
        WHERE 1=1
        """

        var bindValues: [String] = []

        if let sourceKind {
            sql += " AND d.source_kind = ?"
            bindValues.append(sourceKind.rawValue)
        }

        if let ownerNodeID {
            sql += " AND d.owner_node_id = ?"
            bindValues.append(ownerNodeID)
        }

        if let publicProfileID {
            sql += " AND d.public_profile_id = ?"
            bindValues.append(publicProfileID)
        }

        if let offerID {
            sql += " AND d.offer_id = ?"
            bindValues.append(offerID)
        }

        sql += " ORDER BY d.updated_at DESC, d.id ASC"

        if let limit {
            sql += " LIMIT \(limit)"
        }

        let rows = try withStatementAndResult(
            sql,
            bind: { stmt in
                for (idx, value) in bindValues.enumerated() {
                    bindText(stmt, Int32(idx + 1), value)
                }
            }
        ) { stmt in
            var documents: [ExchangeRetrievalDocument] = []

            while true {
                let rc = sqlite3_step(stmt)

                if rc == SQLITE_ROW {
                    let snapshot = try blobColumn(stmt, index: 0)
                    var document = try decode(ExchangeRetrievalDocument.self, from: snapshot)

                    if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                        let embeddingData = try blobColumn(stmt, index: 1)
                        let embedding = try decode([Float].self, from: embeddingData)
                        document = document.updatingEmbedding(embedding)
                    }

                    documents.append(document)
                } else if rc == SQLITE_DONE {
                    break
                } else {
                    throw sqliteError()
                }
            }

            return documents
        }

        #if DEBUG
        exStoreLog("[ExchangeSQLiteStore] listRetrievalDocuments count=\(rows.count) source=\(sourceKind?.rawValue ?? "nil") owner=\(ownerNodeID ?? "nil") profile=\(publicProfileID ?? "nil") offer=\(offerID ?? "nil")")
        #endif

        return rows
    }

    public func removeRetrievalDocuments(ids: [ExchangeRetrievalDocument.ID]) async throws {
        await gateForAccess()

        guard !ids.isEmpty else { return }

        for id in ids {
            try withStatement("""
                DELETE FROM exchange_retrieval_documents
                WHERE id = ?1;
                """
            ) { stmt in
                bindText(stmt, 1, id)
                try stepDone(stmt)
            }
        }

        #if DEBUG
        exStoreLog("[ExchangeSQLiteStore] removeRetrievalDocuments ids=\(ids.count)")
        #endif
    }

    public func removeRetrievalDocuments(sourceKind: ExchangeRetrievalDocument.SourceKind) async throws {
        await gateForAccess()

        try withStatement("""
            DELETE FROM exchange_retrieval_documents
            WHERE source_kind = ?1;
            """
        ) { stmt in
            bindText(stmt, 1, sourceKind.rawValue)
            try stepDone(stmt)
        }

        #if DEBUG
        exStoreLog("[ExchangeSQLiteStore] removeRetrievalDocuments source=\(sourceKind.rawValue)")
        #endif
    }

    public func clearRetrievalDocuments() async throws {
        await gateForAccess()

        try withStatement("DELETE FROM exchange_retrieval_documents;") { stmt in
            try stepDone(stmt)
        }

        #if DEBUG
        exStoreLog("[ExchangeSQLiteStore] clearRetrievalDocuments")
        #endif
    }

    // MARK: - Artifacts

    public func saveArtifact(_ artifact: ExchangeArtifact) async throws {
        await gateForAccess()

        let payloadJSON = try encode(artifact.payload)
        let metadataJSON = try encodeJSON(artifact.metadata)
        let snapshot = try encode(artifact)
        let revision = try nextRevision(table: "exchange_artifacts", id: artifact.id.uuidString)
        let visibilityMask = Int64(artifact.visibility.rawValue)

        try withStatement("""
            INSERT INTO exchange_artifacts (
                id, thread_id, created_at, updated_at, revision,
                kind, status, title, summary, visibility, visibility_mask,
                payload_json, metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
            ON CONFLICT(id) DO UPDATE SET
                thread_id = excluded.thread_id,
                updated_at = excluded.updated_at,
                revision = excluded.revision,
                kind = excluded.kind,
                status = excluded.status,
                title = excluded.title,
                summary = excluded.summary,
                visibility = excluded.visibility,
                visibility_mask = excluded.visibility_mask,
                payload_json = excluded.payload_json,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, artifact.id.uuidString)
            bindText(stmt, 2, artifact.threadID.uuidString)
            bindText(stmt, 3, Self.isoString(from: artifact.createdAt))
            bindText(stmt, 4, Self.isoString(from: artifact.updatedAt))
            sqlite3_bind_int64(stmt, 5, revision)
            bindText(stmt, 6, artifact.kind.rawValue)
            bindText(stmt, 7, artifact.status.rawValue)
            bindText(stmt, 8, artifact.title)
            bindNullableText(stmt, 9, artifact.summary)
            bindText(stmt, 10, artifact.visibility.isInternalOnly ? "internalOnly" : "userVisible")
            sqlite3_bind_int64(stmt, 11, visibilityMask)
            bindBlob(stmt, 12, payloadJSON)
            bindBlob(stmt, 13, metadataJSON)
            bindBlob(stmt, 14, snapshot)
            try stepDone(stmt)
        }
    }

    public func listArtifacts(threadID: ExchangeThread.ID) async throws -> [ExchangeArtifact] {
        await gateForAccess()

        return try querySnapshots(
            sql: """
            SELECT json_snapshot
            FROM exchange_artifacts
            WHERE thread_id = ?1
            ORDER BY updated_at DESC;
            """,
            bind: { stmt in bindText(stmt, 1, threadID.uuidString) },
            as: ExchangeArtifact.self
        )
    }

    // MARK: - Trust Graph

    public func saveTrustEdge(_ edge: ExchangeTrustEdge) async throws {
        await gateForAccess()

        var edgeToPersist = edge

        let existingForPair = try fetchSnapshot(
            sql: """
            SELECT json_snapshot
            FROM exchange_trust_edges
            WHERE source_node_id = ?1 AND target_node_id = ?2
            LIMIT 1;
            """,
            bind: { stmt in
                bindText(stmt, 1, edge.sourceNodeID)
                bindText(stmt, 2, edge.targetNodeID)
            },
            as: ExchangeTrustEdge.self
        )

        if let existingForPair, existingForPair.id != edge.id {
            edgeToPersist.id = existingForPair.id
            edgeToPersist.createdAt = existingForPair.createdAt
        }

        let metadataJSON = try encodeJSON(edgeToPersist.metadata)
        let snapshot = try encode(edgeToPersist)

        try withStatement("""
            INSERT INTO exchange_trust_edges (
                id, source_node_id, target_node_id, relationship_type, trust_level,
                visibility, propagation, source_kind, note, created_at, updated_at,
                last_confirmed_at, revoked_at, metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)
            ON CONFLICT(source_node_id, target_node_id) DO UPDATE SET
                relationship_type = excluded.relationship_type,
                trust_level = excluded.trust_level,
                visibility = excluded.visibility,
                propagation = excluded.propagation,
                source_kind = excluded.source_kind,
                note = excluded.note,
                updated_at = excluded.updated_at,
                last_confirmed_at = excluded.last_confirmed_at,
                revoked_at = excluded.revoked_at,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, edgeToPersist.id.uuidString)
            bindText(stmt, 2, edgeToPersist.sourceNodeID)
            bindText(stmt, 3, edgeToPersist.targetNodeID)
            bindText(stmt, 4, edgeToPersist.relationshipType.rawValue)
            bindText(stmt, 5, edgeToPersist.trustLevel.rawValue)
            bindText(stmt, 6, edgeToPersist.propagation.rawValue)
            bindText(stmt, 7, edgeToPersist.propagation.rawValue)
            bindText(stmt, 8, edgeToPersist.sourceKind.rawValue)
            bindNullableText(stmt, 9, edgeToPersist.note)
            bindText(stmt, 10, Self.isoString(from: edgeToPersist.createdAt))
            bindText(stmt, 11, Self.isoString(from: edgeToPersist.updatedAt))
            bindNullableText(stmt, 12, edgeToPersist.lastConfirmedAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 13, edgeToPersist.revokedAt.map { Self.isoString(from: $0) })
            bindBlob(stmt, 14, metadataJSON)
            bindBlob(stmt, 15, snapshot)
            try stepDone(stmt)
        }

        try withStatement("DELETE FROM exchange_trust_edge_scopes WHERE trust_edge_id = ?1;") { stmt in
            bindText(stmt, 1, edgeToPersist.id.uuidString)
            try stepDone(stmt)
        }

        for scope in edgeToPersist.scopes.sorted(by: { $0.rawValue < $1.rawValue }) {
            try withStatement("""
                INSERT INTO exchange_trust_edge_scopes (trust_edge_id, scope)
                VALUES (?1, ?2);
                """
            ) { stmt in
                bindText(stmt, 1, edgeToPersist.id.uuidString)
                bindText(stmt, 2, scope.rawValue)
                try stepDone(stmt)
            }
        }
    }

    public func fetchTrustEdge(id: ExchangeTrustEdge.ID) async throws -> ExchangeTrustEdge? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM exchange_trust_edges WHERE id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, id.uuidString) },
            as: ExchangeTrustEdge.self
        )
    }

    public func fetchTrustEdge(
        sourceNodeID: String,
        targetNodeID: String
    ) async throws -> ExchangeTrustEdge? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: """
            SELECT json_snapshot
            FROM exchange_trust_edges
            WHERE source_node_id = ?1 AND target_node_id = ?2
            LIMIT 1;
            """,
            bind: { stmt in
                bindText(stmt, 1, sourceNodeID)
                bindText(stmt, 2, targetNodeID)
            },
            as: ExchangeTrustEdge.self
        )
    }

    public func listTrustEdges(filter: ExchangeTrustEdgeFilter) async throws -> [ExchangeTrustEdge] {
        await gateForAccess()

        if let limit = filter.limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT DISTINCT e.json_snapshot
        FROM exchange_trust_edges e
        """
        var bindValues: [String] = []

        if let scopes = filter.scopes, !scopes.isEmpty {
            sql += """
             INNER JOIN exchange_trust_edge_scopes s
                ON s.trust_edge_id = e.id
            """
        }

        sql += " WHERE 1=1"

        if let sourceNodeID = filter.sourceNodeID {
            sql += " AND e.source_node_id = ?"
            bindValues.append(sourceNodeID)
        }

        if let targetNodeID = filter.targetNodeID {
            sql += " AND e.target_node_id = ?"
            bindValues.append(targetNodeID)
        }

        if let relationshipTypes = filter.relationshipTypes, !relationshipTypes.isEmpty {
            let values = relationshipTypes.sorted { $0.rawValue < $1.rawValue }
            sql += " AND e.relationship_type IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if let trustLevels = filter.trustLevels, !trustLevels.isEmpty {
            let values = trustLevels.sorted { $0.rawValue < $1.rawValue }
            sql += " AND e.trust_level IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if let propagations = filter.propagations, !propagations.isEmpty {
            let values = propagations.sorted { $0.rawValue < $1.rawValue }
            sql += " AND COALESCE(e.propagation, e.visibility) IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if let sourceKinds = filter.sourceKinds, !sourceKinds.isEmpty {
            let values = sourceKinds.sorted { $0.rawValue < $1.rawValue }
            sql += " AND e.source_kind IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if filter.activeOnly {
            sql += " AND e.revoked_at IS NULL"
        }

        if let scopes = filter.scopes, !scopes.isEmpty {
            let values = scopes.sorted { $0.rawValue < $1.rawValue }
            sql += " AND s.scope IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        sql += " ORDER BY e.updated_at DESC"

        if let limit = filter.limit {
            sql += " LIMIT \(limit)"
        }

        return try querySnapshots(
            sql: sql,
            bind: { stmt in
                for (idx, value) in bindValues.enumerated() {
                    bindText(stmt, Int32(idx + 1), value)
                }
            },
            as: ExchangeTrustEdge.self
        )
    }

    public func appendTrustEvidence(_ evidence: ExchangeTrustEvidence) async throws {
        await gateForAccess()

        let metadataJSON = try encodeJSON(evidence.metadata)
        let snapshot = try encode(evidence)

        try withStatement("""
            INSERT INTO exchange_trust_evidence (
                id, trust_edge_id, type, weight, thread_id, related_node_id,
                related_counterparty_id, summary, note, recorded_at, metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12);
            """
        ) { stmt in
            bindText(stmt, 1, evidence.id.uuidString)
            bindText(stmt, 2, evidence.trustEdgeID.uuidString)
            bindText(stmt, 3, evidence.type.rawValue)
            sqlite3_bind_double(stmt, 4, evidence.weight)
            bindNullableText(stmt, 5, evidence.threadID?.uuidString)
            bindNullableText(stmt, 6, nil)
            bindNullableText(stmt, 7, evidence.relatedCounterpartyID)
            bindNullableText(stmt, 8, evidence.summary)
            bindNullableText(stmt, 9, evidence.note)
            bindText(stmt, 10, Self.isoString(from: evidence.recordedAt))
            bindBlob(stmt, 11, metadataJSON)
            bindBlob(stmt, 12, snapshot)
            try stepDone(stmt)
        }
    }

    public func listTrustEvidence(
        trustEdgeID: ExchangeTrustEdge.ID,
        limit: Int?,
        ascending: Bool
    ) async throws -> [ExchangeTrustEvidence] {
        await gateForAccess()

        if let limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT json_snapshot
        FROM exchange_trust_evidence
        WHERE trust_edge_id = ?1
        ORDER BY recorded_at \(ascending ? "ASC" : "DESC")
        """

        if let limit {
            sql += " LIMIT \(limit)"
        }

        return try querySnapshots(
            sql: sql,
            bind: { stmt in bindText(stmt, 1, trustEdgeID.uuidString) },
            as: ExchangeTrustEvidence.self
        )
    }

    public func fetchTrustedNodeProfile(
        nodeID: String,
        forSourceNodeID sourceNodeID: String?
    ) async throws -> ExchangeTrustedNodeProfile? {
        await gateForAccess()

        let localEdge: ExchangeTrustEdge?
        if let sourceNodeID {
            localEdge = try fetchSnapshot(
                sql: """
                SELECT json_snapshot
                FROM exchange_trust_edges
                WHERE source_node_id = ?1 AND target_node_id = ?2
                LIMIT 1;
                """,
                bind: { stmt in
                    bindText(stmt, 1, sourceNodeID)
                    bindText(stmt, 2, nodeID)
                },
                as: ExchangeTrustEdge.self
            )
        } else {
            localEdge = nil
        }

        let networkTrust = try computeNetworkTrust(
            nodeID: nodeID,
            forSourceNodeID: sourceNodeID
        )

        let scopedTrust = try computeScopedTrust(nodeID: nodeID)

        if localEdge == nil &&
            networkTrust.trustedByCount == 0 &&
            networkTrust.trustedByYourTrustedCount == 0 &&
            networkTrust.mutualTrustCount == 0 &&
            scopedTrust.isEmpty {
            return nil
        }

        let localTrust: ExchangeTrustedNodeProfile.LocalTrust?
        if let localEdge {
            let isMutual = try self.isMutualTrust(
                sourceNodeID: localEdge.sourceNodeID,
                targetNodeID: localEdge.targetNodeID
            )

            localTrust = ExchangeTrustedNodeProfile.LocalTrust(
                relationshipType: localEdge.relationshipType,
                trustLevel: localEdge.trustLevel,
                scopes: localEdge.scopes,
                propagation: localEdge.propagation,
                isMutual: isMutual,
                lastConfirmedAt: localEdge.lastConfirmedAt,
                note: localEdge.note
            )
        } else {
            localTrust = nil
        }

        let fallbackDate = Date(timeIntervalSince1970: 0)
        let createdAt = localEdge?.createdAt
            ?? networkTrust.lastObservedAt
            ?? fallbackDate

        let updatedAt = [
            localEdge?.updatedAt,
            localEdge?.lastConfirmedAt,
            networkTrust.lastObservedAt
        ]
        .compactMap { $0 }
        .max() ?? createdAt

        return ExchangeTrustedNodeProfile(
            id: nodeID,
            nodeID: nodeID,
            counterpartyID: nil,
            localTrust: localTrust,
            networkTrust: networkTrust,
            scopedTrust: scopedTrust,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Federation Outbox

    public func saveOutboxItem(_ item: ExchangeOutboxItem) async throws {
        await gateForAccess()

        let deliveryExternalEffectJSON = try encode(item.deliveryState.externalEffect)
        let policyJSON = try encode(item.policy)
        let metadataJSON = try encodeJSON(item.metadata)
        let snapshot = try encode(item)

        try withStatement("""
            INSERT INTO exchange_outbox_items (
                id, thread_id, draft_id, approval_id, target_node_id, envelope_id,
                created_at, updated_at, is_active,
                delivery_phase, delivery_priority, delivery_note, delivery_external_effect_json,
                queued_at, first_attempt_at, last_attempt_at, sent_at, acknowledged_at,
                cancelled_at, failed_at, deferred_until,
                attempt_count, last_error_code, last_external_reference, relay_route_summary,
                policy_json, payload_summary, metadata_json, json_snapshot
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6,
                ?7, ?8, ?9,
                ?10, ?11, ?12, ?13,
                ?14, ?15, ?16, ?17, ?18,
                ?19, ?20, ?21,
                ?22, ?23, ?24, ?25,
                ?26, ?27, ?28, ?29
            )
            ON CONFLICT(id) DO UPDATE SET
                thread_id = excluded.thread_id,
                draft_id = excluded.draft_id,
                approval_id = excluded.approval_id,
                target_node_id = excluded.target_node_id,
                envelope_id = excluded.envelope_id,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                is_active = excluded.is_active,
                delivery_phase = excluded.delivery_phase,
                delivery_priority = excluded.delivery_priority,
                delivery_note = excluded.delivery_note,
                delivery_external_effect_json = excluded.delivery_external_effect_json,
                queued_at = excluded.queued_at,
                first_attempt_at = excluded.first_attempt_at,
                last_attempt_at = excluded.last_attempt_at,
                sent_at = excluded.sent_at,
                acknowledged_at = excluded.acknowledged_at,
                cancelled_at = excluded.cancelled_at,
                failed_at = excluded.failed_at,
                deferred_until = excluded.deferred_until,
                attempt_count = excluded.attempt_count,
                last_error_code = excluded.last_error_code,
                last_external_reference = excluded.last_external_reference,
                relay_route_summary = excluded.relay_route_summary,
                policy_json = excluded.policy_json,
                payload_summary = excluded.payload_summary,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, item.id.uuidString)
            bindText(stmt, 2, item.threadID.uuidString)
            bindText(stmt, 3, item.draftID.uuidString)
            bindNullableText(stmt, 4, item.approvalID?.uuidString)
            bindText(stmt, 5, item.targetNodeID)
            bindText(stmt, 6, item.envelopeID)
            bindText(stmt, 7, Self.isoString(from: item.createdAt))
            bindText(stmt, 8, Self.isoString(from: item.updatedAt))
            sqlite3_bind_int(stmt, 9, item.isActive ? 1 : 0)
            bindText(stmt, 10, item.deliveryState.phase.rawValue)
            bindText(stmt, 11, item.deliveryState.priority.rawValue)
            bindNullableText(stmt, 12, item.deliveryState.note)
            bindBlob(stmt, 13, deliveryExternalEffectJSON)
            bindNullableText(stmt, 14, item.deliveryState.queuedAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 15, item.deliveryState.firstAttemptAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 16, item.deliveryState.lastAttemptAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 17, item.deliveryState.sentAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 18, item.deliveryState.acknowledgedAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 19, item.deliveryState.cancelledAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 20, item.deliveryState.failedAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 21, item.deliveryState.deferredUntil.map { Self.isoString(from: $0) })
            sqlite3_bind_int64(stmt, 22, Int64(item.deliveryState.attemptCount))
            bindNullableText(stmt, 23, item.deliveryState.lastErrorCode)
            bindNullableText(stmt, 24, item.deliveryState.lastExternalReference)
            bindNullableText(stmt, 25, item.deliveryState.relayRouteSummary)
            bindBlob(stmt, 26, policyJSON)
            bindText(stmt, 27, item.payloadSummary)
            bindBlob(stmt, 28, metadataJSON)
            bindBlob(stmt, 29, snapshot)
            try stepDone(stmt)
        }

        await secretarySQLiteHooks.onOutboxItemSaved?(item)
    }

    public func fetchOutboxItem(id: ExchangeOutboxItem.ID) async throws -> ExchangeOutboxItem? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM exchange_outbox_items WHERE id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, id.uuidString) },
            as: ExchangeOutboxItem.self
        )
    }

    public func fetchOutboxItemByEnvelopeID(_ envelopeID: String) async throws -> ExchangeOutboxItem? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM exchange_outbox_items WHERE envelope_id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, envelopeID) },
            as: ExchangeOutboxItem.self
        )
    }

    public func listOutboxItems(filter: ExchangeOutboxFilter) async throws -> [ExchangeOutboxItem] {
        await gateForAccess()

        if let limit = filter.limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT json_snapshot
        FROM exchange_outbox_items
        WHERE 1=1
        """
        var bindValues: [String] = []

        if let threadID = filter.threadID {
            sql += " AND thread_id = ?"
            bindValues.append(threadID.uuidString)
        }

        if let draftID = filter.draftID {
            sql += " AND draft_id = ?"
            bindValues.append(draftID.uuidString)
        }

        if let approvalID = filter.approvalID {
            sql += " AND approval_id = ?"
            bindValues.append(approvalID.uuidString)
        }

        if let targetNodeID = filter.targetNodeID {
            sql += " AND target_node_id = ?"
            bindValues.append(targetNodeID)
        }

        if let phases = filter.phases, !phases.isEmpty {
            let values = phases.sorted { $0.rawValue < $1.rawValue }
            sql += " AND delivery_phase IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if filter.activeOnly {
            sql += " AND is_active = 1"
        }

        if let createdAfter = filter.createdAfter {
            sql += " AND created_at >= ?"
            bindValues.append(Self.isoString(from: createdAfter))
        }

        if let createdBefore = filter.createdBefore {
            sql += " AND created_at <= ?"
            bindValues.append(Self.isoString(from: createdBefore))
        }

        sql += " ORDER BY updated_at DESC"

        if let limit = filter.limit {
            sql += " LIMIT \(limit)"
        }

        return try querySnapshots(
            sql: sql,
            bind: { stmt in
                for (idx, value) in bindValues.enumerated() {
                    bindText(stmt, Int32(idx + 1), value)
                }
            },
            as: ExchangeOutboxItem.self
        )
    }

    // MARK: - Federation Inbox

    public func saveInboxItem(_ item: ExchangeInboxItem) async throws {
        await gateForAccess()

        let metadataJSON = try encodeJSON(item.metadata)
        let snapshot = try encode(item)

        let compatibilityKind: String
        let compatibilityValue: String?

        switch item.compatibility {
        case .supported:
            compatibilityKind = "supported"
            compatibilityValue = nil
        case .unsupportedVersion(let value):
            compatibilityKind = "unsupportedVersion"
            compatibilityValue = value
        case .unsupportedPayload(let value):
            compatibilityKind = "unsupportedPayload"
            compatibilityValue = value
        case .invalidSignature:
            compatibilityKind = "invalidSignature"
            compatibilityValue = nil
        case .malformed(let reason):
            compatibilityKind = "malformed"
            compatibilityValue = reason
        }

        try withStatement("""
            INSERT INTO exchange_inbox_items (
                id, envelope_id, thread_id, sender_node_id, sender_display_name,
                received_at, updated_at, sequence_number, parent_envelope_id, sender_timestamp,
                compatibility_kind, compatibility_value, processing_state,
                visible_summary, metadata_json, json_snapshot
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5,
                ?6, ?7, ?8, ?9, ?10,
                ?11, ?12, ?13,
                ?14, ?15, ?16
            )
            ON CONFLICT(id) DO UPDATE SET
                envelope_id = excluded.envelope_id,
                thread_id = excluded.thread_id,
                sender_node_id = excluded.sender_node_id,
                sender_display_name = excluded.sender_display_name,
                received_at = excluded.received_at,
                updated_at = excluded.updated_at,
                sequence_number = excluded.sequence_number,
                parent_envelope_id = excluded.parent_envelope_id,
                sender_timestamp = excluded.sender_timestamp,
                compatibility_kind = excluded.compatibility_kind,
                compatibility_value = excluded.compatibility_value,
                processing_state = excluded.processing_state,
                visible_summary = excluded.visible_summary,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, item.id.uuidString)
            bindText(stmt, 2, item.envelopeID)
            bindNullableText(stmt, 3, item.threadID?.uuidString)
            bindNullableText(stmt, 4, item.senderNodeID)
            bindNullableText(stmt, 5, item.senderDisplayName)
            bindText(stmt, 6, Self.isoString(from: item.receivedAt))
            bindText(stmt, 7, Self.isoString(from: item.updatedAt))

            if let sequenceNumber = item.ordering.sequenceNumber {
                sqlite3_bind_int64(stmt, 8, Int64(sequenceNumber))
            } else {
                sqlite3_bind_null(stmt, 8)
            }

            bindNullableText(stmt, 9, item.ordering.parentEnvelopeID)
            bindNullableText(stmt, 10, item.ordering.senderTimestamp.map { Self.isoString(from: $0) })
            bindText(stmt, 11, compatibilityKind)
            bindNullableText(stmt, 12, compatibilityValue)
            bindText(stmt, 13, item.processingState.rawValue)
            bindText(stmt, 14, item.visibleSummary)
            bindBlob(stmt, 15, metadataJSON)
            bindBlob(stmt, 16, snapshot)
            try stepDone(stmt)
        }
    }

    public func fetchInboxItem(id: ExchangeInboxItem.ID) async throws -> ExchangeInboxItem? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM exchange_inbox_items WHERE id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, id.uuidString) },
            as: ExchangeInboxItem.self
        )
    }

    public func fetchInboxItemByEnvelopeID(_ envelopeID: String) async throws -> ExchangeInboxItem? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM exchange_inbox_items WHERE envelope_id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, envelopeID) },
            as: ExchangeInboxItem.self
        )
    }

    public func listInboxItems(filter: ExchangeInboxFilter) async throws -> [ExchangeInboxItem] {
        await gateForAccess()

        if let limit = filter.limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT json_snapshot
        FROM exchange_inbox_items
        WHERE 1=1
        """
        var bindValues: [String] = []

        if let threadID = filter.threadID {
            sql += " AND thread_id = ?"
            bindValues.append(threadID.uuidString)
        }

        if let senderNodeID = filter.senderNodeID {
            sql += " AND sender_node_id = ?"
            bindValues.append(senderNodeID)
        }

        if let processingStates = filter.processingStates, !processingStates.isEmpty {
            let values = processingStates.sorted { $0.rawValue < $1.rawValue }
            sql += " AND processing_state IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if filter.processableOnly {
            sql += " AND compatibility_kind = ?"
            bindValues.append("supported")
        }

        if let receivedAfter = filter.receivedAfter {
            sql += " AND received_at >= ?"
            bindValues.append(Self.isoString(from: receivedAfter))
        }

        if let receivedBefore = filter.receivedBefore {
            sql += " AND received_at <= ?"
            bindValues.append(Self.isoString(from: receivedBefore))
        }

        sql += " ORDER BY received_at DESC"

        if let limit = filter.limit {
            sql += " LIMIT \(limit)"
        }

        return try querySnapshots(
            sql: sql,
            bind: { stmt in
                for (idx, value) in bindValues.enumerated() {
                    bindText(stmt, Int32(idx + 1), value)
                }
            },
            as: ExchangeInboxItem.self
        )
    }

    // MARK: - Federation Audit

    public func appendAuditRecord(_ record: ExchangeAuditRecord) async throws {
        await gateForAccess()

        let externalEffectJSON = try encode(record.externalEffect)
        let metadataJSON = try encodeJSON(record.metadata)
        let snapshot = try encode(record)

        try withStatement("""
            INSERT INTO exchange_audit_records (
                id, created_at, thread_id, direction, category, actor,
                envelope_id, outbox_item_id, inbox_item_id,
                summary, detail, external_effect_json,
                related_node_id, related_display_name,
                metadata_json, json_snapshot
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6,
                ?7, ?8, ?9,
                ?10, ?11, ?12,
                ?13, ?14,
                ?15, ?16
            );
            """
        ) { stmt in
            bindText(stmt, 1, record.id.uuidString)
            bindText(stmt, 2, Self.isoString(from: record.createdAt))
            bindNullableText(stmt, 3, record.threadID?.uuidString)
            bindText(stmt, 4, record.direction.rawValue)
            bindText(stmt, 5, record.category.rawValue)
            bindText(stmt, 6, record.actor.rawValue)
            bindNullableText(stmt, 7, record.envelopeID)
            bindNullableText(stmt, 8, record.outboxItemID?.uuidString)
            bindNullableText(stmt, 9, record.inboxItemID?.uuidString)
            bindText(stmt, 10, record.summary)
            bindNullableText(stmt, 11, record.detail)
            bindBlob(stmt, 12, externalEffectJSON)
            bindNullableText(stmt, 13, record.relatedNodeID)
            bindNullableText(stmt, 14, record.relatedDisplayName)
            bindBlob(stmt, 15, metadataJSON)
            bindBlob(stmt, 16, snapshot)
            try stepDone(stmt)
        }
    }

    public func listAuditRecords(filter: ExchangeAuditFilter) async throws -> [ExchangeAuditRecord] {
        await gateForAccess()

        if let limit = filter.limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT json_snapshot
        FROM exchange_audit_records
        WHERE 1=1
        """
        var bindValues: [String] = []

        if let threadID = filter.threadID {
            sql += " AND thread_id = ?"
            bindValues.append(threadID.uuidString)
        }

        if let direction = filter.direction {
            sql += " AND direction = ?"
            bindValues.append(direction.rawValue)
        }

        if let categories = filter.categories, !categories.isEmpty {
            let values = categories.sorted { $0.rawValue < $1.rawValue }
            sql += " AND category IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: values.map(\.rawValue))
        }

        if let envelopeID = filter.envelopeID {
            sql += " AND envelope_id = ?"
            bindValues.append(envelopeID)
        }

        if let relatedNodeID = filter.relatedNodeID {
            sql += " AND related_node_id = ?"
            bindValues.append(relatedNodeID)
        }

        if let createdAfter = filter.createdAfter {
            sql += " AND created_at >= ?"
            bindValues.append(Self.isoString(from: createdAfter))
        }

        if let createdBefore = filter.createdBefore {
            sql += " AND created_at <= ?"
            bindValues.append(Self.isoString(from: createdBefore))
        }

        sql += " ORDER BY created_at DESC"

        if let limit = filter.limit {
            sql += " LIMIT \(limit)"
        }

        return try querySnapshots(
            sql: sql,
            bind: { stmt in
                for (idx, value) in bindValues.enumerated() {
                    bindText(stmt, Int32(idx + 1), value)
                }
            },
            as: ExchangeAuditRecord.self
        )
    }

    // MARK: - Contact signal outbound (friend request lane)

    public func saveOutgoingContactRequest(_ request: OutgoingContactRequest) async throws {
        await gateForAccess()

        let metadataJSON = try encodeJSON(request.metadata)
        let snapshot = try encode(request)

        try withStatement(
            """
            INSERT INTO outgoing_contact_requests (
                id, target_node_id, target_display_name, target_profile_id,
                envelope_id, correlation_id, phase, body,
                created_at, updated_at, sent_at, last_error,
                metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
            ON CONFLICT(id) DO UPDATE SET
                target_node_id = excluded.target_node_id,
                target_display_name = excluded.target_display_name,
                target_profile_id = excluded.target_profile_id,
                envelope_id = excluded.envelope_id,
                correlation_id = excluded.correlation_id,
                phase = excluded.phase,
                body = excluded.body,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                sent_at = excluded.sent_at,
                last_error = excluded.last_error,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, request.id.uuidString)
            bindText(stmt, 2, request.targetNodeID)
            bindNullableText(stmt, 3, request.targetDisplayName)
            bindNullableText(stmt, 4, request.targetProfileID)
            bindText(stmt, 5, request.envelopeID)
            bindText(stmt, 6, request.correlationID.uuidString)
            bindText(stmt, 7, request.phase.rawValue)
            bindText(stmt, 8, request.body)
            bindText(stmt, 9, Self.isoString(from: request.createdAt))
            bindText(stmt, 10, Self.isoString(from: request.updatedAt))
            bindNullableText(stmt, 11, request.sentAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 12, request.lastError)
            bindBlob(stmt, 13, metadataJSON)
            bindBlob(stmt, 14, snapshot)
            try stepDone(stmt)
        }
    }

    public func fetchOutgoingContactRequest(id: OutgoingContactRequest.ID) async throws -> OutgoingContactRequest? {
        await gateForAccess()
        return try fetchSnapshot(
            sql: "SELECT json_snapshot FROM outgoing_contact_requests WHERE id = ?1 LIMIT 1;",
            bind: { stmt in bindText(stmt, 1, id.uuidString) },
            as: OutgoingContactRequest.self
        )
    }

    public func fetchPendingOutgoingContactRequest(targetNodeID: String) async throws -> OutgoingContactRequest? {
        await gateForAccess()
        let trimmed = targetNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pendingPhases = [
            OutgoingContactRequest.Phase.queued.rawValue,
            OutgoingContactRequest.Phase.sending.rawValue,
            OutgoingContactRequest.Phase.sent.rawValue
        ]
        let placeholders = pendingPhases.map { _ in "?" }.joined(separator: ", ")
        let sql = """
        SELECT json_snapshot
        FROM outgoing_contact_requests
        WHERE target_node_id = ?1
          AND phase IN (\(placeholders))
        ORDER BY created_at DESC
        LIMIT 1;
        """

        return try fetchSnapshot(
            sql: sql,
            bind: { stmt in
                bindText(stmt, 1, trimmed)
                for (i, p) in pendingPhases.enumerated() {
                    bindText(stmt, Int32(i + 2), p)
                }
            },
            as: OutgoingContactRequest.self
        )
    }

    public func markOutgoingContactRequestsAcceptedForTarget(
        targetNodeID: String,
        now: Date
    ) async throws -> Int {
        await gateForAccess()
        let trimmed = targetNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let pending = try await listOutgoingContactRequests(
            filter: OutgoingContactRequestFilter(
                targetNodeID: trimmed,
                phases: [.queued, .sending, .sent],
                limit: nil
            )
        )
        guard !pending.isEmpty else { return 0 }

        for var request in pending {
            request.phase = .accepted
            request.updatedAt = now
            try await saveOutgoingContactRequest(request)
        }
        return pending.count
    }

    public func listOutgoingContactRequests(filter: OutgoingContactRequestFilter) async throws -> [OutgoingContactRequest] {
        await gateForAccess()

        if let limit = filter.limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT json_snapshot
        FROM outgoing_contact_requests
        WHERE 1=1
        """
        var bindValues: [String] = []

        if let targetNodeID = filter.targetNodeID {
            sql += " AND target_node_id = ?"
            bindValues.append(targetNodeID)
        }

        if let phases = filter.phases, !phases.isEmpty {
            let sorted = phases.map(\.rawValue).sorted()
            sql += " AND phase IN (\(Array(repeating: "?", count: sorted.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: sorted)
        }

        sql += " ORDER BY created_at DESC"

        if let limit = filter.limit {
            sql += " LIMIT \(limit)"
        }

        return try querySnapshots(
            sql: sql,
            bind: { stmt in
                for (idx, value) in bindValues.enumerated() {
                    bindText(stmt, Int32(idx + 1), value)
                }
            },
            as: OutgoingContactRequest.self
        )
    }

    // MARK: - Secretary notifications

    public func upsertSecretaryNotification(_ notification: SecretaryNotification) async throws {
        await gateForAccess()

        let metadataJSON = try encodeJSON(notification.metadata)
        let snapshot = try encode(notification)

        try withStatement(
            """
            INSERT INTO exchange_secretary_notifications (
                id, created_at, updated_at, kind, dedupe_key, is_read, priority,
                title, body, thread_id, approval_id, failure_id, turn_id, trusted_node_id,
                metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
            ON CONFLICT(dedupe_key) DO UPDATE SET
                updated_at = CASE
                    WHEN exchange_secretary_notifications.kind != excluded.kind
                        OR exchange_secretary_notifications.priority != excluded.priority
                        OR exchange_secretary_notifications.title != excluded.title
                        OR exchange_secretary_notifications.body != excluded.body
                        OR IFNULL(exchange_secretary_notifications.thread_id, '') != IFNULL(excluded.thread_id, '')
                        OR IFNULL(exchange_secretary_notifications.approval_id, '') != IFNULL(excluded.approval_id, '')
                        OR IFNULL(exchange_secretary_notifications.failure_id, '') != IFNULL(excluded.failure_id, '')
                        OR IFNULL(exchange_secretary_notifications.turn_id, '') != IFNULL(excluded.turn_id, '')
                        OR IFNULL(exchange_secretary_notifications.trusted_node_id, '') != IFNULL(excluded.trusted_node_id, '')
                        OR exchange_secretary_notifications.metadata_json != excluded.metadata_json
                    THEN excluded.updated_at
                    ELSE exchange_secretary_notifications.updated_at
                END,
                title = excluded.title,
                body = excluded.body,
                kind = excluded.kind,
                priority = excluded.priority,
                thread_id = excluded.thread_id,
                approval_id = excluded.approval_id,
                failure_id = excluded.failure_id,
                turn_id = excluded.turn_id,
                trusted_node_id = excluded.trusted_node_id,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, notification.id.uuidString)
            bindText(stmt, 2, Self.isoString(from: notification.createdAt))
            bindText(stmt, 3, Self.isoString(from: notification.updatedAt))
            bindText(stmt, 4, notification.kind.rawValue)
            bindText(stmt, 5, notification.dedupeKey)
            sqlite3_bind_int(stmt, 6, notification.isRead ? 1 : 0)
            bindText(stmt, 7, notification.priority.rawValue)
            bindText(stmt, 8, notification.title)
            bindText(stmt, 9, notification.body)
            bindNullableText(stmt, 10, notification.threadID?.uuidString)
            bindNullableText(stmt, 11, notification.approvalID?.uuidString)
            bindNullableText(stmt, 12, notification.failureID?.uuidString)
            bindNullableText(stmt, 13, notification.turnID?.uuidString)
            bindNullableText(stmt, 14, notification.trustedNodeID)
            bindBlob(stmt, 15, metadataJSON)
            bindBlob(stmt, 16, snapshot)
            try stepDone(stmt)
        }
    }

    public func listSecretaryNotifications(
        filter: ExchangeSecretaryNotificationFilter
    ) async throws -> [SecretaryNotification] {
        await gateForAccess()

        if let limit = filter.limit, limit <= 0 {
            throw ExchangeStoreError.invalidLimit
        }

        var sql = """
        SELECT id, is_read, updated_at, json_snapshot
        FROM exchange_secretary_notifications
        WHERE 1=1
        """
        var bindValues: [String] = []

        if filter.unreadOnly {
            sql += " AND is_read = 0"
        }

        if filter.excludingPriorityLow {
            sql += " AND priority != ?"
            bindValues.append(SecretaryNotificationPriority.low.rawValue)
        }

        if let kinds = filter.kinds, !kinds.isEmpty {
            let sorted = kinds.sorted { $0.rawValue < $1.rawValue }
            sql += " AND kind IN (\(Array(repeating: "?", count: sorted.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: sorted.map(\.rawValue))
        }

        if let excluded = filter.excludedKinds, !excluded.isEmpty {
            let sorted = excluded.sorted { $0.rawValue < $1.rawValue }
            sql += " AND kind NOT IN (\(Array(repeating: "?", count: sorted.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: sorted.map(\.rawValue))
        }

        sql += " ORDER BY created_at DESC"

        if let limit = filter.limit {
            sql += " LIMIT \(limit)"
        }

        /// `json_snapshot` may lag `is_read` / `updated_at` after UPDATE-only marks; honor live columns.
        var results: [SecretaryNotification] = []
        try withStatement(sql) { stmt in
            for (idx, value) in bindValues.enumerated() {
                bindText(stmt, Int32(idx + 1), value)
            }

            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW {
                    let idRaw = textColumn(stmt, index: 0) ?? ""
                    let columnIsRead = sqlite3_column_int(stmt, 1) != 0
                    let updatedRaw = textColumn(stmt, index: 2) ?? ""
                    let data = try blobColumn(stmt, index: 3)
                    guard let rowID = UUID(uuidString: idRaw) else {
                        exStoreLog(
                            "[SecretaryNotificationsList] skip row invalid SQL id=\(idRaw)"
                        )
                        continue
                    }
                    var decoded: SecretaryNotification = try decode(SecretaryNotification.self, from: data)
                    decoded.id = rowID
                    decoded.isRead = columnIsRead
                    if let stamped = Self.isoDate(from: updatedRaw) {
                        decoded.updatedAt = stamped
                    }
                    results.append(decoded)
                } else if rc == SQLITE_DONE {
                    break
                } else {
                    throw sqliteError()
                }
            }
        }

        return results
    }

    public func countUnreadSecretaryNotifications(
        excludingPriorityLow: Bool,
        excludedKinds: Set<SecretaryNotificationKind>?
    ) async throws -> Int {
        await gateForAccess()

        var sql = "SELECT COUNT(*) FROM exchange_secretary_notifications WHERE is_read = 0"
        var bindValues: [String] = []

        if excludingPriorityLow {
            sql += " AND priority != ?"
            bindValues.append(SecretaryNotificationPriority.low.rawValue)
        }

        if let excluded = excludedKinds, !excluded.isEmpty {
            let sorted = excluded.sorted { $0.rawValue < $1.rawValue }
            sql += " AND kind NOT IN (\(Array(repeating: "?", count: sorted.count).joined(separator: ", ")))"
            bindValues.append(contentsOf: sorted.map(\.rawValue))
        }

        sql += ";"

        return try scalarInt(
            sql: sql,
            bind: { stmt in
                for (idx, value) in bindValues.enumerated() {
                    bindText(stmt, Int32(idx + 1), value)
                }
            }
        )
    }

    public func markSecretaryNotificationsRead(ids: Set<SecretaryNotification.ID>) async throws {
        await gateForAccess()

        guard !ids.isEmpty else { return }

        let attempted = ids.count
        try withStatement(
            """
            UPDATE exchange_secretary_notifications
            SET is_read = 1
            WHERE id IN (\(Array(repeating: "?", count: ids.count).joined(separator: ", ")));
            """
        ) { stmt in
            let idStrings = ids.map(\.uuidString).sorted()
            for (idx, id) in idStrings.enumerated() {
                bindText(stmt, Int32(idx + 1), id)
            }
            try stepDone(stmt)
        }
        let affected = Int(sqlite3_changes(db))
        exStoreLog("[SecretaryNotificationsMarkRead] attempted=\(attempted) affected=\(affected)")
    }

    public func markSecretaryNotificationsUnread(ids: Set<SecretaryNotification.ID>) async throws {
        await gateForAccess()

        guard !ids.isEmpty else { return }

        try withStatement(
            """
            UPDATE exchange_secretary_notifications
            SET is_read = 0
            WHERE id IN (\(Array(repeating: "?", count: ids.count).joined(separator: ", ")));
            """
        ) { stmt in
            let idStrings = ids.map(\.uuidString).sorted()
            for (idx, id) in idStrings.enumerated() {
                bindText(stmt, Int32(idx + 1), id)
            }
            try stepDone(stmt)
        }
    }

    public func markSecretaryNotificationsReadForThread(
        threadID: ExchangeThread.ID,
        kinds: Set<SecretaryNotificationKind>?
    ) async throws {
        await gateForAccess()

        var sql = """
        UPDATE exchange_secretary_notifications
        SET is_read = 1
        WHERE thread_id = ?1
        """

        let sortedKinds: [String]? = kinds.map {
            Array($0).sorted { $0.rawValue < $1.rawValue }.map(\.rawValue)
        }

        if let sortedKinds, !sortedKinds.isEmpty {
            sql += " AND kind IN (\(Array(repeating: "?", count: sortedKinds.count).joined(separator: ", ")))"
        }

        sql += ";"

        try withStatement(sql) { stmt in
            bindText(stmt, 1, threadID.uuidString)

            if let sortedKinds {
                for (idx, raw) in sortedKinds.enumerated() {
                    bindText(stmt, Int32(idx + 2), raw)
                }
            }

            try stepDone(stmt)
        }
    }

    public func markSecretaryNotificationsReadWhereApproval(
        approvalID: ExchangeApproval.ID
    ) async throws {
        await gateForAccess()
        try withStatement(
            """
            UPDATE exchange_secretary_notifications
            SET is_read = 1
            WHERE approval_id = ?1;
            """
        ) { stmt in
            bindText(stmt, 1, approvalID.uuidString)
            try stepDone(stmt)
        }
    }

    public func markSecretaryNotificationsReadWhereFailure(
        failureID: ExchangeFailure.ID
    ) async throws {
        await gateForAccess()
        try withStatement(
            """
            UPDATE exchange_secretary_notifications
            SET is_read = 1
            WHERE failure_id = ?1;
            """
        ) { stmt in
            bindText(stmt, 1, failureID.uuidString)
            try stepDone(stmt)
        }
    }

    public func markSecretaryNotificationsReadWhereTrustedNode(
        nodeID: String
    ) async throws {
        await gateForAccess()
        let trimmed = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try withStatement(
            """
            UPDATE exchange_secretary_notifications
            SET is_read = 1
            WHERE trusted_node_id = ?1;
            """
        ) { stmt in
            bindText(stmt, 1, trimmed)
            try stepDone(stmt)
        }
    }

    // MARK: - Sync State

    public func fetchSyncState(id: String) async throws -> ExchangeSyncState? {
        await gateForAccess()

        return try fetchSnapshot(
            sql: """
            SELECT json_snapshot
            FROM exchange_sync_state
            WHERE id = ?1
            LIMIT 1;
            """,
            bind: { stmt in
                bindText(stmt, 1, id)
            },
            as: ExchangeSyncState.self
        )
    }

    public func saveSyncState(_ state: ExchangeSyncState) async throws {
        await gateForAccess()

        let snapshot = try encode(state)

        try withStatement("""
            INSERT INTO exchange_sync_state (
                id,
                inbound_checkpoint,
                last_inbound_sync_at,
                last_outbound_flush_at,
                last_reconcile_at,
                last_successful_sync_at,
                last_attempt_at,
                backoff_until,
                consecutive_failure_count,
                last_error_summary,
                last_error_domain,
                active_run_id,
                updated_at,
                json_snapshot
            ) VALUES (
                ?1,
                ?2,
                ?3,
                ?4,
                ?5,
                ?6,
                ?7,
                ?8,
                ?9,
                ?10,
                ?11,
                ?12,
                ?13,
                ?14
            )
            ON CONFLICT(id) DO UPDATE SET
                inbound_checkpoint = excluded.inbound_checkpoint,
                last_inbound_sync_at = excluded.last_inbound_sync_at,
                last_outbound_flush_at = excluded.last_outbound_flush_at,
                last_reconcile_at = excluded.last_reconcile_at,
                last_successful_sync_at = excluded.last_successful_sync_at,
                last_attempt_at = excluded.last_attempt_at,
                backoff_until = excluded.backoff_until,
                consecutive_failure_count = excluded.consecutive_failure_count,
                last_error_summary = excluded.last_error_summary,
                last_error_domain = excluded.last_error_domain,
                active_run_id = excluded.active_run_id,
                updated_at = excluded.updated_at,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, state.id)
            bindNullableText(stmt, 2, state.inboundCheckpoint)
            bindNullableText(stmt, 3, state.lastInboundSyncAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 4, state.lastOutboundFlushAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 5, state.lastReconcileAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 6, state.lastSuccessfulSyncAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 7, state.lastAttemptAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 8, state.backoffUntil.map { Self.isoString(from: $0) })
            sqlite3_bind_int64(stmt, 9, Int64(state.consecutiveFailureCount))
            bindNullableText(stmt, 10, state.lastErrorSummary)
            bindNullableText(stmt, 11, state.lastErrorDomain)
            bindNullableText(stmt, 12, state.activeRunID?.uuidString)
            bindText(stmt, 13, Self.isoString(from: state.updatedAt))
            bindBlob(stmt, 14, snapshot)
            try stepDone(stmt)
        }
    }

    // MARK: - Local maintenance

    /// Runs a single transactional local maintenance pass. Not invoked automatically by the store.
    public func runLocalMaintenance(
        policy: ExchangeLocalMaintenancePolicy = .default,
        now: Date = Date(),
        reason: String = "manual"
    ) async throws -> ExchangeLocalMaintenanceResult {
        let startedAt = now
        let cutoff = policy.cutoffDate(now: now)
        let discoveryCacheCutoff = policy.remoteDiscoveryCacheCutoffDate(now: now)
        let inboxOpenCutoff = policy.staleInboxOpenCutoffDate(now: now)

        let deletedCounts = try await performExclusiveSQLiteTransaction {
            var counts: [ExchangeLocalMaintenanceTable: Int] = [:]
            counts[.outbox] = try pruneOutboxItemsForLocalMaintenance(cutoff: cutoff)
            counts[.inbox] = try pruneInboxItemsForLocalMaintenance(cutoff: cutoff)
            counts[.staleInboxOpenRows] = try pruneStaleOpenInboxItemsForLocalMaintenance(
                cutoff: inboxOpenCutoff
            )
            counts[.audit] = try pruneAuditRecordsForLocalMaintenance(
                cutoff: cutoff,
                maxRecords: policy.maxAuditRecords
            )
            counts[.secretaryNotifications] = try pruneSecretaryNotificationsForLocalMaintenance(
                cutoff: cutoff
            )
            counts[.discoveryMatches] = try pruneDiscoveryMatchesForLocalMaintenance(cutoff: cutoff)
            counts[.discoveryMatches, default: 0] += try pruneDiscoveryCacheMatchesForLocalMaintenance(
                cutoff: discoveryCacheCutoff
            )
            counts[.staleRemoteOffers] = try pruneStaleRemoteOffersForLocalMaintenance(
                policy: policy,
                cutoff: discoveryCacheCutoff
            )
            counts[.staleRemotePublicProfiles] = try pruneStaleRemotePublicProfilesForLocalMaintenance(
                policy: policy,
                cutoff: discoveryCacheCutoff
            )
            counts[.staleRemoteCounterparties] = try pruneStaleRemoteCounterpartiesForLocalMaintenance(
                policy: policy,
                cutoff: discoveryCacheCutoff
            )
            return counts
        }

        let result = ExchangeLocalMaintenanceResult(
            reason: reason,
            startedAt: startedAt,
            completedAt: Date(),
            deletedCounts: deletedCounts
        )

        #if DEBUG
        let summary = ExchangeLocalMaintenanceTable.allCases
            .map { "\($0.rawValue)=\(result.deletedCount(for: $0))" }
            .joined(separator: " ")
        exStoreLog("[ExchangeLocalMaintenance] reason=\(reason) \(summary) total=\(result.totalDeleted)")
        #endif

        return result
    }

    /// Manual compaction helper. Not run automatically on launch.
    public func compactExchangeDatabaseStorage() async throws {
        await gateForAccess()
        try exec("VACUUM;")
    }

    private func pruneOutboxItemsForLocalMaintenance(cutoff: Date) throws -> Int {
        let phases = ExchangeLocalMaintenancePolicy.prunableInactiveOutboxPhases
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
        let placeholders = Array(repeating: "?", count: phases.count).joined(separator: ", ")
        let sql = """
        DELETE FROM exchange_outbox_items
        WHERE is_active = 0
          AND updated_at < ?
          AND delivery_phase IN (\(placeholders));
        """
        var bindValues = [Self.isoString(from: cutoff)]
        bindValues.append(contentsOf: phases)
        return try executeMaintenanceDelete(sql: sql, bindValues: bindValues)
    }

    private func pruneInboxItemsForLocalMaintenance(cutoff: Date) throws -> Int {
        let states = ExchangeLocalMaintenancePolicy.prunableInboxProcessingStates
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
        let placeholders = Array(repeating: "?", count: states.count).joined(separator: ", ")
        let sql = """
        DELETE FROM exchange_inbox_items
        WHERE updated_at < ?
          AND processing_state IN (\(placeholders));
        """
        var bindValues = [Self.isoString(from: cutoff)]
        bindValues.append(contentsOf: states)
        return try executeMaintenanceDelete(sql: sql, bindValues: bindValues)
    }

    private func pruneAuditRecordsForLocalMaintenance(cutoff: Date, maxRecords: Int) throws -> Int {
        let cutoffString = Self.isoString(from: cutoff)
        var deleted = try executeMaintenanceDelete(
            sql: "DELETE FROM exchange_audit_records WHERE created_at < ?1;",
            bindValues: [cutoffString]
        )

        let remaining = try queryMaintenanceRowCount(table: "exchange_audit_records")
        if remaining > maxRecords {
            let excess = remaining - maxRecords
            deleted += try executeMaintenanceDelete(
                sql: """
                DELETE FROM exchange_audit_records
                WHERE id IN (
                    SELECT id
                    FROM exchange_audit_records
                    ORDER BY created_at ASC
                    LIMIT \(excess)
                );
                """
            )
        }

        return deleted
    }

    private func pruneSecretaryNotificationsForLocalMaintenance(cutoff: Date) throws -> Int {
        try executeMaintenanceDelete(
            sql: """
            DELETE FROM exchange_secretary_notifications
            WHERE is_read = 1
              AND updated_at < ?1;
            """,
            bindValues: [Self.isoString(from: cutoff)]
        )
    }

    private func pruneDiscoveryMatchesForLocalMaintenance(cutoff: Date) throws -> Int {
        let statuses = ExchangeLocalMaintenancePolicy.prunableMatchStatuses
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
        let statusPlaceholders = Array(repeating: "?", count: statuses.count).joined(separator: ", ")
        let inactiveStates = ExchangeLocalMaintenancePolicy.inactiveThreadStateKeys.sorted()
        let statePlaceholders = Array(repeating: "?", count: inactiveStates.count).joined(separator: ", ")

        let sql = """
        DELETE FROM exchange_matches
        WHERE created_at < ?
          AND status IN (\(statusPlaceholders))
          AND thread_id IN (
            SELECT id
            FROM exchange_threads
            WHERE state_key IN (\(statePlaceholders))
               OR metadata_json LIKE '%"archived":"true"%'
          );
        """

        var bindValues = [Self.isoString(from: cutoff)]
        bindValues.append(contentsOf: statuses)
        bindValues.append(contentsOf: inactiveStates)
        return try executeMaintenanceDelete(sql: sql, bindValues: bindValues)
    }

    private func pruneDiscoveryCacheMatchesForLocalMaintenance(cutoff: Date) throws -> Int {
        let inactiveStates = ExchangeLocalMaintenancePolicy.inactiveThreadStateKeys.sorted()
        let statePlaceholders = Array(repeating: "?", count: inactiveStates.count).joined(separator: ", ")
        let sql = """
        DELETE FROM exchange_matches
        WHERE created_at < ?1
          AND status = 'candidate'
          AND thread_id IN (
            SELECT id
            FROM exchange_threads
            WHERE state_key IN (\(statePlaceholders))
               OR metadata_json LIKE '%"archived":"true"%'
          );
        """
        var bindValues = [Self.isoString(from: cutoff)]
        bindValues.append(contentsOf: inactiveStates)
        return try executeMaintenanceDelete(sql: sql, bindValues: bindValues)
    }

    private func pruneStaleOpenInboxItemsForLocalMaintenance(cutoff: Date) throws -> Int {
        let openStates = [
            ExchangeInboxItem.ProcessingState.received.rawValue,
            ExchangeInboxItem.ProcessingState.awaitingOrderingGapResolution.rawValue
        ]
        let placeholders = Array(repeating: "?", count: openStates.count).joined(separator: ", ")
        let sql = """
        DELETE FROM exchange_inbox_items
        WHERE updated_at < ?1
          AND processing_state IN (\(placeholders));
        """
        var bindValues = [Self.isoString(from: cutoff)]
        bindValues.append(contentsOf: openStates)
        return try executeMaintenanceDelete(sql: sql, bindValues: bindValues)
    }

    private func pruneStaleRemoteOffersForLocalMaintenance(
        policy: ExchangeLocalMaintenancePolicy,
        cutoff: Date
    ) throws -> Int {
        let activeStatuses = ExchangeRemoteDiscoveryCacheProtection.activeMatchStatuses
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
        let statusPlaceholders = Array(repeating: "?", count: activeStatuses.count).joined(separator: ", ")
        let durablePattern = ExchangeRemoteDiscoveryCacheProtection.durableMetadataPattern
        let forYouSource = ExchangeRemoteDiscoveryCacheMetadata.CacheSource.forYou.rawValue
        let forYouCutoff = Self.isoString(from: policy.staleForYouCacheCutoffDate())

        var sql = """
        DELETE FROM exchange_offers AS o
        WHERE o.updated_at < ?1
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_publication_state ps
            WHERE ps.public_profile_id = o.public_profile_id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_threads t
            WHERE t.selected_offer_id = o.id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_matches m
            WHERE m.offer_id = o.id
              AND m.status IN (\(statusPlaceholders))
          )
          AND (o.metadata_json IS NULL OR o.metadata_json NOT LIKE ?2)
          AND (
            o.metadata_json IS NULL
            OR o.metadata_json NOT LIKE '%"\(ExchangeRemoteDiscoveryCacheMetadata.cacheSourceKey)":"\(forYouSource)"%'
            OR o.updated_at < ?3
          )
        """

        var bindValues = [Self.isoString(from: cutoff), durablePattern, forYouCutoff]
        bindValues.append(contentsOf: activeStatuses)

        if let localNodeID = policy.localNodeID {
            sql += " AND o.node_id != ?\(bindValues.count + 1)"
            bindValues.append(localNodeID)
        }

        return try executeMaintenanceDelete(sql: sql, bindValues: bindValues)
    }

    private func pruneStaleRemotePublicProfilesForLocalMaintenance(
        policy: ExchangeLocalMaintenancePolicy,
        cutoff: Date
    ) throws -> Int {
        let activeStatuses = ExchangeRemoteDiscoveryCacheProtection.activeMatchStatuses
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
        let statusPlaceholders = Array(repeating: "?", count: activeStatuses.count).joined(separator: ", ")
        let durablePattern = ExchangeRemoteDiscoveryCacheProtection.durableMetadataPattern
        let forYouSource = ExchangeRemoteDiscoveryCacheMetadata.CacheSource.forYou.rawValue
        let forYouCutoff = Self.isoString(from: policy.staleForYouCacheCutoffDate())

        var sql = """
        DELETE FROM exchange_public_profiles AS p
        WHERE p.updated_at < ?1
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_publication_state ps
            WHERE ps.public_profile_id = p.id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_threads t
            WHERE t.selected_public_profile_id = p.id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_matches m
            WHERE m.public_profile_id = p.id
              AND m.status IN (\(statusPlaceholders))
          )
          AND (p.metadata_json IS NULL OR p.metadata_json NOT LIKE ?2)
          AND (
            p.metadata_json IS NULL
            OR p.metadata_json NOT LIKE '%"\(ExchangeRemoteDiscoveryCacheMetadata.cacheSourceKey)":"\(forYouSource)"%'
            OR p.updated_at < ?3
          )
        """

        var bindValues = [Self.isoString(from: cutoff), durablePattern, forYouCutoff]
        bindValues.append(contentsOf: activeStatuses)

        if let localNodeID = policy.localNodeID {
            sql += " AND p.node_id != ?\(bindValues.count + 1)"
            bindValues.append(localNodeID)
        }

        return try executeMaintenanceDelete(sql: sql, bindValues: bindValues)
    }

    private func pruneStaleRemoteCounterpartiesForLocalMaintenance(
        policy: ExchangeLocalMaintenancePolicy,
        cutoff: Date
    ) throws -> Int {
        let activeStatuses = ExchangeRemoteDiscoveryCacheProtection.activeMatchStatuses
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
        let statusPlaceholders = Array(repeating: "?", count: activeStatuses.count).joined(separator: ", ")
        let durablePattern = ExchangeRemoteDiscoveryCacheProtection.durableMetadataPattern
        let forYouSource = ExchangeRemoteDiscoveryCacheMetadata.CacheSource.forYou.rawValue
        let forYouCutoff = Self.isoString(from: policy.staleForYouCacheCutoffDate())
        let cutoffString = Self.isoString(from: cutoff)

        var sql = """
        DELETE FROM exchange_counterparties AS c
        WHERE c.updated_at < ?1
          AND c.status != 'blocked'
          AND (c.metadata_json IS NULL OR c.metadata_json NOT LIKE ?2)
          AND (
            c.metadata_json IS NULL
            OR c.metadata_json NOT LIKE '%"\(ExchangeRemoteDiscoveryCacheMetadata.cacheSourceKey)":"\(forYouSource)"%'
            OR c.updated_at < ?3
          )
          AND (c.source_json NOT LIKE '%"manualEntry"%' AND c.source_json NOT LIKE '%"trustedIntroduction"%')
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_threads t
            WHERE t.selected_counterparty_id = c.id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_matches m
            WHERE m.counterparty_id = c.id
              AND (
                m.status IN (\(statusPlaceholders))
                OR m.created_at >= ?4
              )
          )
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_trust_edges te
            WHERE te.revoked_at IS NULL
              AND (te.target_node_id = c.id OR te.source_node_id = c.id)
          )
          AND NOT EXISTS (
            SELECT 1
            FROM outgoing_contact_requests ocr
            WHERE ocr.target_node_id = c.id
              AND ocr.phase IN ('queued', 'sending', 'sent')
          )
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_public_profiles p
            JOIN exchange_publication_state ps ON ps.public_profile_id = p.id
            WHERE p.counterparty_id = c.id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM exchange_public_profiles p
            WHERE p.counterparty_id = c.id
              AND (
                p.metadata_json LIKE ?2
                OR EXISTS (
                  SELECT 1
                  FROM exchange_publication_state ps
                  WHERE ps.public_profile_id = p.id
                )
              )
          )
        """

        var bindValues = [cutoffString, durablePattern, forYouCutoff, cutoffString]
        bindValues.append(contentsOf: activeStatuses)

        if let localNodeID = policy.localNodeID {
            sql += " AND c.id != ?\(bindValues.count + 1)"
            bindValues.append(localNodeID)
            sql += " AND (c.identity_json IS NULL OR c.identity_json NOT LIKE ?\(bindValues.count + 1))"
            bindValues.append("%\"nodeID\":\"\(localNodeID)\"%")
        }

        return try executeMaintenanceDelete(sql: sql, bindValues: bindValues)
    }

    private func executeMaintenanceDelete(
        sql: String,
        bindValues: [String] = []
    ) throws -> Int {
        try withStatement(sql) { stmt in
            for (index, value) in bindValues.enumerated() {
                bindText(stmt, Int32(index + 1), value)
            }
            try stepDone(stmt)
        }
        return Int(sqlite3_changes(db))
    }

    private func queryMaintenanceRowCount(table: String) throws -> Int {
        guard table.allSatisfy({ $0.isLetter || $0 == "_" }) else {
            throw ExchangeStoreError.storageFailure(reason: "Invalid maintenance table name.")
        }
        var count = 0
        try withStatement("SELECT COUNT(*) FROM \(table);") { stmt in
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw sqliteError()
            }
            count = Int(sqlite3_column_int64(stmt, 0))
        }
        return count
    }

    private func deleteThreadScopedRows(sql: String, bindValues: [String]) throws -> Int {
        try withStatement(sql) { stmt in
            for (index, value) in bindValues.enumerated() {
                bindText(stmt, Int32(index + 1), value)
            }
            try stepDone(stmt)
        }
        return Int(sqlite3_changes(db))
    }

    private struct ThreadCascadeRowCounts {
        var turns: Int = 0
        var drafts: Int = 0
        var approvals: Int = 0
        var outcomes: Int = 0
        var matches: Int = 0
        var artifacts: Int = 0
        var outbox: Int = 0
    }

    private func countThreadCascadeRows(threadID: ExchangeThread.ID) throws -> ThreadCascadeRowCounts {
        ThreadCascadeRowCounts(
            turns: try countThreadScopedRows(table: "exchange_turns", threadID: threadID),
            drafts: try countThreadScopedRows(table: "exchange_drafts", threadID: threadID),
            approvals: try countThreadScopedRows(table: "exchange_approvals", threadID: threadID),
            outcomes: try countThreadScopedRows(table: "exchange_outcomes", threadID: threadID),
            matches: try countThreadScopedRows(table: "exchange_matches", threadID: threadID),
            artifacts: try countThreadScopedRows(table: "exchange_artifacts", threadID: threadID),
            outbox: try countThreadScopedRows(table: "exchange_outbox_items", threadID: threadID)
        )
    }

    private func countThreadScopedRows(table: String, threadID: ExchangeThread.ID) throws -> Int {
        guard table.allSatisfy({ $0.isLetter || $0 == "_" }) else {
            throw ExchangeStoreError.storageFailure(reason: "Invalid thread-scoped table name.")
        }
        var count = 0
        try withStatement("SELECT COUNT(*) FROM \(table) WHERE thread_id = ?1;") { stmt in
            bindText(stmt, 1, threadID.uuidString)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw sqliteError()
            }
            count = Int(sqlite3_column_int64(stmt, 0))
        }
        return count
    }

    private func performExclusiveSQLiteTransaction<T>(
        _ operation: () throws -> T
    ) async throws -> T {
        await gateForAccess()
        let token = UUID()
        await gateForTransactionStart(token: token)
        activeTransactionToken = token
        do {
            try exec("BEGIN IMMEDIATE TRANSACTION;")
        } catch {
            activeTransactionToken = nil
            resumeTransactionWaiters()
            throw error
        }

        do {
            let result = try ExchangeStoreTaskContext.$transactionToken.withValue(token) {
                try operation()
            }
            try exec("COMMIT;")
            activeTransactionToken = nil
            resumeTransactionWaiters()
            return result
        } catch {
            try? exec("ROLLBACK;")
            activeTransactionToken = nil
            resumeTransactionWaiters()
            throw error
        }
    }

    // MARK: - Transaction boundary

    public func performTransaction<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        let token = ExchangeStoreTaskContext.transactionToken ?? UUID()

        #if DEBUG
        let t0 = exStoreNowMs()
        exStoreLog("[ExchangeSQLiteStore] TX request token=\(token.uuidString)")
        #endif

        await gateForTransactionStart(token: token)

        let beganTopLevelTransaction = activeTransactionToken == nil
        if beganTopLevelTransaction {
            activeTransactionToken = token
            do {
                #if DEBUG
                exStoreLog("[ExchangeSQLiteStore] TX begin token=\(token.uuidString)")
                #endif
                try exec("BEGIN IMMEDIATE TRANSACTION;")
            } catch {
                activeTransactionToken = nil
                resumeTransactionWaiters()
                #if DEBUG
                exStoreLog("[ExchangeSQLiteStore] TX begin FAILED token=\(token.uuidString) err=\(error)")
                #endif
                throw error
            }
        } else {
            #if DEBUG
            exStoreLog("[ExchangeSQLiteStore] TX join existing token=\(token.uuidString)")
            #endif
        }

        do {
            let result = try await ExchangeStoreTaskContext.$transactionToken.withValue(token) {
                try await operation()
            }

            if beganTopLevelTransaction {
                try exec("COMMIT;")
                activeTransactionToken = nil
                resumeTransactionWaiters()
                #if DEBUG
                let dt = exStoreNowMs() - t0
                exStoreLog("[ExchangeSQLiteStore] TX commit token=\(token.uuidString) totalMs=\(Int(dt))")
                #endif
            }

            return result
        } catch {
            if beganTopLevelTransaction {
                try? exec("ROLLBACK;")
                activeTransactionToken = nil
                resumeTransactionWaiters()
                #if DEBUG
                let dt = exStoreNowMs() - t0
                exStoreLog("[ExchangeSQLiteStore] TX rollback token=\(token.uuidString) totalMs=\(Int(dt)) err=\(error)")
                #endif
            } else {
                #if DEBUG
                exStoreLog("[ExchangeSQLiteStore] TX nested error token=\(token.uuidString) err=\(error)")
                #endif
            }
            throw error
        }
    }
}

private extension ExchangeSQLiteStore {
    static func execOnDB(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard rc == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw ExchangeStoreError.storageFailure(reason: message)
        }
    }

    static func migrateOnDB(_ db: OpaquePointer) throws {
        let applied = try currentSchemaVersionOnDB(db)

        for migration in ExchangeSchema.migrations.sorted(by: { $0.version < $1.version }) where migration.version > applied {
            try execOnDB("BEGIN IMMEDIATE TRANSACTION;", db: db)
            do {
                for statement in migration.statements {
                    try execOnDB(statement, db: db)
                }

                var stmt: OpaquePointer?
                let sql = """
                INSERT INTO exchange_schema_version (version, applied_at)
                VALUES (?1, ?2)
                ON CONFLICT(version) DO NOTHING;
                """
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw ExchangeStoreError.storageFailure(reason: String(cString: sqlite3_errmsg(db)))
                }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_int64(stmt, 1, Int64(migration.version))
                bindText(stmt, 2, isoString(from: Date()))

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw ExchangeStoreError.storageFailure(reason: String(cString: sqlite3_errmsg(db)))
                }

                try execOnDB("COMMIT;", db: db)
            } catch {
                try? execOnDB("ROLLBACK;", db: db)
                throw error
            }
        }

        let finalVersion = try currentSchemaVersionOnDB(db)
        guard finalVersion == ExchangeSchema.currentVersion else {
            throw ExchangeStoreError.storageFailure(
                reason: "Schema migration incomplete. Expected \(ExchangeSchema.currentVersion), got \(finalVersion)."
            )
        }
    }

    static func currentSchemaVersionOnDB(_ db: OpaquePointer) throws -> Int {
        var stmt: OpaquePointer?
        let existsSQL = """
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name = 'exchange_schema_version'
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(db, existsSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw ExchangeStoreError.storageFailure(reason: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let exists = sqlite3_step(stmt) == SQLITE_ROW
        guard exists else { return 0 }

        var versionStmt: OpaquePointer?
        let versionSQL = "SELECT COALESCE(MAX(version), 0) FROM exchange_schema_version;"
        guard sqlite3_prepare_v2(db, versionSQL, -1, &versionStmt, nil) == SQLITE_OK else {
            throw ExchangeStoreError.storageFailure(reason: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(versionStmt) }

        var version = 0
        if sqlite3_step(versionStmt) == SQLITE_ROW {
            version = Int(sqlite3_column_int64(versionStmt, 0))
        }
        return version
    }

    func saveThread(_ thread: ExchangeThread, bumpRevision: Bool) throws {
        #if DEBUG
        exStoreLog(
            "[ExchangeSQLiteStore] saveThread " +
            "threadID=\(thread.id.uuidString) " +
            "thread_role=\(thread.metadata[ExchangeThreadRoleResolver.threadRoleMetadataKey] ?? "nil") " +
            "parent_thread_id=\(thread.metadata[ExchangeThreadRoleResolver.parentThreadIDMetadataKey] ?? "nil") " +
            "root_thread_id=\(thread.metadata[ExchangeThreadRoleResolver.rootThreadIDMetadataKey] ?? "nil") " +
            "source_match_id=\(thread.metadata[ExchangeThreadRoleResolver.sourceMatchIDMetadataKey] ?? "nil")"
        )
        #endif

        if let failure = thread.latestFailure {
            try saveFailure(failure, threadID: thread.id)
        }

        let intentJSON = try encode(thread.intent)
        let postureJSON = try encode(thread.posture)
        let approvalJSON = try encodeOptional(thread.approval)
        let deliveryJSON = try encodeOptional(thread.delivery)
        let outcomeJSON = try encodeOptional(thread.outcome)
        let metadataJSON = try encodeJSON(thread.metadata)
        let snapshot = try encode(thread)
        let revision = bumpRevision ? try nextRevision(table: "exchange_threads", id: thread.id.uuidString) : 1

        #if DEBUG
        if thread.threadRole == .umbrellaSearch,
           case .matchCandidatesWeak = thread.state,
           ExchangeThreadDiscoveryGradeMetadata.hasPersistedGrade(in: thread.metadata) {
            let gradeSnapshot = ExchangeThreadDiscoveryGradeMetadata.snapshot(from: thread.metadata)
            exStoreLog(
                "[ExchangeSQLiteStore] saveThread discoveryGrade " +
                "threadID=\(thread.id.uuidString) " +
                "classifyGrade=\(gradeSnapshot.classifyGrade?.rawValue ?? "nil") " +
                "projectedGrade=\(gradeSnapshot.projectedGrade?.rawValue ?? "nil") " +
                "reason=\(gradeSnapshot.gradeReason ?? "nil")"
            )
        }
        #endif

        try withStatement("""
            INSERT INTO exchange_threads (
                id, created_at, updated_at, revision, mode, state_key, title,
                selected_counterparty_id, selected_public_profile_id, selected_offer_id,
                latest_failure_id, visible_summary,
                requires_human_decision, outcome_status,
                intent_json, posture_json, approval_json, delivery_json,
                outcome_json, metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21)
            ON CONFLICT(id) DO UPDATE SET
                updated_at = excluded.updated_at,
                revision = excluded.revision,
                mode = excluded.mode,
                state_key = excluded.state_key,
                title = excluded.title,
                selected_counterparty_id = excluded.selected_counterparty_id,
                selected_public_profile_id = excluded.selected_public_profile_id,
                selected_offer_id = excluded.selected_offer_id,
                latest_failure_id = excluded.latest_failure_id,
                visible_summary = excluded.visible_summary,
                requires_human_decision = excluded.requires_human_decision,
                outcome_status = excluded.outcome_status,
                intent_json = excluded.intent_json,
                posture_json = excluded.posture_json,
                approval_json = excluded.approval_json,
                delivery_json = excluded.delivery_json,
                outcome_json = excluded.outcome_json,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, thread.id.uuidString)
            bindText(stmt, 2, Self.isoString(from: thread.createdAt))
            bindText(stmt, 3, Self.isoString(from: thread.updatedAt))
            sqlite3_bind_int64(stmt, 4, revision)
            bindText(stmt, 5, thread.mode.rawValue)
            bindText(stmt, 6, ExchangeTransition.ExchangeStateKey(thread.state).rawValue)
            bindText(stmt, 7, thread.title)
            bindNullableText(stmt, 8, thread.selectedCounterpartyID)
            bindNullableText(stmt, 9, thread.selectedPublicProfileID)
            bindNullableText(stmt, 10, thread.selectedOfferID)
            bindNullableText(stmt, 11, thread.latestFailure?.id.uuidString)
            bindNullableText(stmt, 12, thread.visibleSummary)
            sqlite3_bind_int(stmt, 13, thread.requiresHumanDecision ? 1 : 0)
            bindNullableText(stmt, 14, thread.outcome?.status.rawValue)
            bindBlob(stmt, 15, intentJSON)
            bindBlob(stmt, 16, postureJSON)
            bindNullableBlob(stmt, 17, approvalJSON)
            bindNullableBlob(stmt, 18, deliveryJSON)
            bindNullableBlob(stmt, 19, outcomeJSON)
            bindBlob(stmt, 20, metadataJSON)
            bindBlob(stmt, 21, snapshot)
            try stepDone(stmt)
        }
    }
    
    func saveFailure(_ failure: ExchangeFailure, threadID: ExchangeThread.ID?) throws {
        let externalEffectJSON = try encode(failure.externalEffect)
        let nextStepJSON = try encode(failure.recommendedNextStep)
        let snapshot = try encode(failure)

        try withStatement("""
            INSERT INTO exchange_failures (
                id, thread_id, created_at, kind, severity, summary,
                what_happened, what_did_not_happen,
                external_effect_json, recommended_next_step_json,
                reason_code, technical_details, is_retryable, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
            ON CONFLICT(id) DO UPDATE SET
                thread_id = excluded.thread_id,
                created_at = excluded.created_at,
                kind = excluded.kind,
                severity = excluded.severity,
                summary = excluded.summary,
                what_happened = excluded.what_happened,
                what_did_not_happen = excluded.what_did_not_happen,
                external_effect_json = excluded.external_effect_json,
                recommended_next_step_json = excluded.recommended_next_step_json,
                reason_code = excluded.reason_code,
                technical_details = excluded.technical_details,
                is_retryable = excluded.is_retryable,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, failure.id.uuidString)
            bindNullableText(stmt, 2, threadID?.uuidString)
            bindText(stmt, 3, Self.isoString(from: failure.createdAt))
            bindText(stmt, 4, failure.kind.rawValue)
            bindText(stmt, 5, failure.severity.rawValue)
            bindText(stmt, 6, failure.summary)
            bindText(stmt, 7, failure.whatHappened)
            bindText(stmt, 8, failure.whatDidNotHappen)
            bindBlob(stmt, 9, externalEffectJSON)
            bindBlob(stmt, 10, nextStepJSON)
            bindNullableText(stmt, 11, failure.reasonCode)
            bindNullableText(stmt, 12, failure.technicalDetails)
            sqlite3_bind_int(stmt, 13, failure.isRetryable ? 1 : 0)
            bindBlob(stmt, 14, snapshot)
            try stepDone(stmt)
        }
    }
    
    func savePublicProfileRecord(_ profile: ExchangePublicNodeProfile) throws {
        let interestsJSON = try encode(profile.interests)
        let offersJSON = try encode(profile.offers)
        let openToJSON = try encode(profile.openTo)
        let excludedTopicsJSON = try encode(profile.excludedTopics)
        let activityTagsJSON = try encode(profile.activityTags)
        let regionTagsJSON = try encode(profile.regionTags)
        let semanticJSON = try encode(profile.semantic)
        let reachabilityJSON = try encode(profile.reachability)
        let approachJSON = try encode(profile.approach)
        let metadataJSON = try encodeJSON(profile.metadata)
        let snapshot = try encode(profile)
        let revision = try nextRevision(table: "exchange_public_profiles", id: profile.id)

        try withStatement("""
            INSERT INTO exchange_public_profiles (
                id, node_id, counterparty_id,
                created_at, updated_at, revision,
                display_name, headline, summary,
                visibility, availability,
                interests_json, offers_json, open_to_json, excluded_topics_json,
                activity_tags_json, region_tags_json,
                semantic_json, reachability_json, approach_json,
                metadata_json, json_snapshot
            ) VALUES (
                ?1, ?2, ?3,
                ?4, ?5, ?6,
                ?7, ?8, ?9,
                ?10, ?11,
                ?12, ?13, ?14, ?15,
                ?16, ?17,
                ?18, ?19, ?20,
                ?21, ?22
            )
            ON CONFLICT(id) DO UPDATE SET
                node_id = excluded.node_id,
                counterparty_id = excluded.counterparty_id,
                updated_at = excluded.updated_at,
                revision = excluded.revision,
                display_name = excluded.display_name,
                headline = excluded.headline,
                summary = excluded.summary,
                visibility = excluded.visibility,
                availability = excluded.availability,
                interests_json = excluded.interests_json,
                offers_json = excluded.offers_json,
                open_to_json = excluded.open_to_json,
                excluded_topics_json = excluded.excluded_topics_json,
                activity_tags_json = excluded.activity_tags_json,
                region_tags_json = excluded.region_tags_json,
                semantic_json = excluded.semantic_json,
                reachability_json = excluded.reachability_json,
                approach_json = excluded.approach_json,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, profile.id)
            bindText(stmt, 2, profile.nodeID)
            bindNullableText(stmt, 3, profile.counterpartyID)
            bindText(stmt, 4, Self.isoString(from: profile.createdAt))
            bindText(stmt, 5, Self.isoString(from: profile.updatedAt))
            sqlite3_bind_int64(stmt, 6, revision)
            bindNullableText(stmt, 7, profile.displayName)
            bindNullableText(stmt, 8, profile.headline)
            bindNullableText(stmt, 9, profile.summary)
            bindText(stmt, 10, profile.visibility.rawValue)
            bindText(stmt, 11, profile.availability.rawValue)
            bindBlob(stmt, 12, interestsJSON)
            bindBlob(stmt, 13, offersJSON)
            bindBlob(stmt, 14, openToJSON)
            bindBlob(stmt, 15, excludedTopicsJSON)
            bindBlob(stmt, 16, activityTagsJSON)
            bindBlob(stmt, 17, regionTagsJSON)
            bindBlob(stmt, 18, semanticJSON)
            bindBlob(stmt, 19, reachabilityJSON)
            bindBlob(stmt, 20, approachJSON)
            bindBlob(stmt, 21, metadataJSON)
            bindBlob(stmt, 22, snapshot)
            try stepDone(stmt)
        }
    }

    func savePublicationStateRecord(
        _ state: ExchangePublicationState,
        publicProfileID: ExchangePublicNodeProfile.ID
    ) throws {
        let remoteOfferIDsJSON = try encode(state.lastRemoteOfferIDs)
        let metadataJSON = try encodeJSON(state.metadata)
        let snapshot = try encode(state)

        try withStatement("""
            INSERT INTO exchange_publication_state (
                public_profile_id,
                status,
                is_dirty,
                published_at,
                last_attempt_at,
                last_success_at,
                last_local_mutation_at,
                last_failure_summary,
                last_remote_profile_id,
                last_remote_offer_ids_json,
                last_published_fingerprint,
                metadata_json,
                json_snapshot
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13
            )
            ON CONFLICT(public_profile_id) DO UPDATE SET
                status = excluded.status,
                is_dirty = excluded.is_dirty,
                published_at = excluded.published_at,
                last_attempt_at = excluded.last_attempt_at,
                last_success_at = excluded.last_success_at,
                last_local_mutation_at = excluded.last_local_mutation_at,
                last_failure_summary = excluded.last_failure_summary,
                last_remote_profile_id = excluded.last_remote_profile_id,
                last_remote_offer_ids_json = excluded.last_remote_offer_ids_json,
                last_published_fingerprint = excluded.last_published_fingerprint,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, publicProfileID)
            bindText(stmt, 2, state.status.rawValue)
            sqlite3_bind_int(stmt, 3, state.isDirty ? 1 : 0)
            bindNullableText(stmt, 4, state.publishedAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 5, state.lastAttemptAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 6, state.lastSuccessAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 7, state.lastLocalMutationAt.map { Self.isoString(from: $0) })
            bindNullableText(stmt, 8, state.lastFailureSummary)
            bindNullableText(stmt, 9, state.lastRemoteProfileID)
            bindBlob(stmt, 10, remoteOfferIDsJSON)
            bindNullableText(stmt, 11, state.lastPublishedFingerprint)
            bindBlob(stmt, 12, metadataJSON)
            bindBlob(stmt, 13, snapshot)
            try stepDone(stmt)
        }
    }
    
    func saveOfferRecord(_ offer: ExchangeOffer) throws {
        let tagsJSON = try encode(offer.tags)
        let regionTagsJSON = try encode(offer.regionTags)
        let semanticJSON = try encode(offer.semantic)
        let fulfillmentJSON = try encode(offer.fulfillment)
        let metadataJSON = try encodeJSON(offer.metadata)
        let normalizedContactInfo = offer.contactInfo?.normalized()
        let contactInfoJSON = try encodeOptional(normalizedContactInfo)
        let snapshot = try encode(offer)
        let revision = try nextRevision(table: "exchange_offers", id: offer.id)

        try withStatement("""
            INSERT INTO exchange_offers (
                id, node_id, public_profile_id,
                created_at, updated_at, revision,
                title, summary, category,
                status, visibility,
                tags_json, region_tags_json,
                semantic_json, fulfillment_json,
                metadata_json, contact_info_json, json_snapshot
            ) VALUES (
                ?1, ?2, ?3,
                ?4, ?5, ?6,
                ?7, ?8, ?9,
                ?10, ?11,
                ?12, ?13,
                ?14, ?15,
                ?16, ?17, ?18
            )
            ON CONFLICT(id) DO UPDATE SET
                node_id = excluded.node_id,
                public_profile_id = excluded.public_profile_id,
                updated_at = excluded.updated_at,
                revision = excluded.revision,
                title = excluded.title,
                summary = excluded.summary,
                category = excluded.category,
                status = excluded.status,
                visibility = excluded.visibility,
                tags_json = excluded.tags_json,
                region_tags_json = excluded.region_tags_json,
                semantic_json = excluded.semantic_json,
                fulfillment_json = excluded.fulfillment_json,
                metadata_json = excluded.metadata_json,
                contact_info_json = excluded.contact_info_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, offer.id)
            bindText(stmt, 2, offer.nodeID)
            bindNullableText(stmt, 3, offer.publicProfileID)
            bindText(stmt, 4, Self.isoString(from: offer.createdAt))
            bindText(stmt, 5, Self.isoString(from: offer.updatedAt))
            sqlite3_bind_int64(stmt, 6, revision)
            bindText(stmt, 7, offer.title)
            bindNullableText(stmt, 8, offer.summary)
            bindNullableText(stmt, 9, offer.category)
            bindText(stmt, 10, offer.status.rawValue)
            bindText(stmt, 11, offer.visibility.rawValue)
            bindBlob(stmt, 12, tagsJSON)
            bindBlob(stmt, 13, regionTagsJSON)
            bindBlob(stmt, 14, semanticJSON)
            bindBlob(stmt, 15, fulfillmentJSON)
            bindBlob(stmt, 16, metadataJSON)
            bindNullableBlob(stmt, 17, contactInfoJSON)
            bindBlob(stmt, 18, snapshot)
            try stepDone(stmt)
        }
    }
    
    func saveRetrievalDocumentRecord(_ document: ExchangeRetrievalDocument) throws {
        let tagsJSON = try encode(document.tags)
        let regionTagsJSON = try encode(document.regionTags)
        let metadataJSON = try encodeJSON([
            "visibility": document.visibility ?? "",
            "availability": document.availability ?? "",
            "accessMode": document.accessMode ?? "",
            "acceptingInbound": document.acceptingInbound.map(String.init) ?? "",
            "routeableOnly": document.routeableOnly.map(String.init) ?? ""
        ])
        let snapshot = try encode(document)

        try withStatement("""
            INSERT INTO exchange_retrieval_documents (
                id,
                owner_node_id,
                counterparty_id,
                public_profile_id,
                offer_id,
                source_kind,
                surface_type,
                title,
                summary,
                category,
                tags_json,
                region_tags_json,
                semantic_text,
                document_text,
                created_at,
                updated_at,
                published_at,
                metadata_json,
                json_snapshot
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5,
                ?6, ?7, ?8, ?9, ?10,
                ?11, ?12, ?13, ?14,
                ?15, ?16, ?17, ?18, ?19
            )
            ON CONFLICT(id) DO UPDATE SET
                owner_node_id = excluded.owner_node_id,
                counterparty_id = excluded.counterparty_id,
                public_profile_id = excluded.public_profile_id,
                offer_id = excluded.offer_id,
                source_kind = excluded.source_kind,
                surface_type = excluded.surface_type,
                title = excluded.title,
                summary = excluded.summary,
                category = excluded.category,
                tags_json = excluded.tags_json,
                region_tags_json = excluded.region_tags_json,
                semantic_text = excluded.semantic_text,
                document_text = excluded.document_text,
                updated_at = excluded.updated_at,
                published_at = excluded.published_at,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, document.id)
            bindText(stmt, 2, document.ownerNodeID)
            bindText(stmt, 3, document.counterpartyID)
            bindNullableText(stmt, 4, document.publicProfileID)
            bindNullableText(stmt, 5, document.offerID)
            bindText(stmt, 6, document.sourceKind.rawValue)
            bindText(stmt, 7, document.surfaceType.rawValue)
            bindText(stmt, 8, document.title)
            bindNullableText(stmt, 9, document.summary)
            bindNullableText(stmt, 10, document.category)
            bindBlob(stmt, 11, tagsJSON)
            bindBlob(stmt, 12, regionTagsJSON)
            bindNullableText(stmt, 13, document.semanticText.nilIfBlankForSQLite)
            bindNullableText(stmt, 14, document.documentText.nilIfBlankForSQLite)
            bindText(stmt, 15, Self.isoString(from: document.updatedAt))
            bindText(stmt, 16, Self.isoString(from: document.updatedAt))
            bindNullableText(stmt, 17, nil)
            bindBlob(stmt, 18, metadataJSON)
            bindBlob(stmt, 19, snapshot)
            try stepDone(stmt)
        }

        if let embedding = document.embedding, !embedding.isEmpty {
            try saveRetrievalEmbeddingRecord(
                documentID: document.id,
                embedding: embedding,
                updatedAt: document.updatedAt
            )
        } else {
            try withStatement("""
                DELETE FROM exchange_retrieval_embeddings
                WHERE document_id = ?1;
                """
            ) { stmt in
                bindText(stmt, 1, document.id)
                try stepDone(stmt)
            }
        }
    }

    func saveRetrievalEmbeddingRecord(
        documentID: ExchangeRetrievalDocument.ID,
        embedding: [Float],
        updatedAt: Date
    ) throws {
        let embeddingJSON = try encode(embedding)
        let modelID = "default"

        try withStatement("""
            INSERT INTO exchange_retrieval_embeddings (
                document_id,
                model_id,
                dimension,
                embedding_json,
                created_at,
                updated_at
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6
            )
            ON CONFLICT(document_id, model_id) DO UPDATE SET
                dimension = excluded.dimension,
                embedding_json = excluded.embedding_json,
                updated_at = excluded.updated_at;
            """
        ) { stmt in
            bindText(stmt, 1, documentID)
            bindText(stmt, 2, modelID)
            sqlite3_bind_int64(stmt, 3, Int64(embedding.count))
            bindBlob(stmt, 4, embeddingJSON)
            bindText(stmt, 5, Self.isoString(from: updatedAt))
            bindText(stmt, 6, Self.isoString(from: updatedAt))
            try stepDone(stmt)
        }
    }

    func fetchRetrievalDocumentRecord(
        id: ExchangeRetrievalDocument.ID
    ) throws -> ExchangeRetrievalDocument? {
        try withStatementAndResult(
            """
            SELECT d.json_snapshot, e.embedding_json
            FROM exchange_retrieval_documents d
            LEFT JOIN exchange_retrieval_embeddings e
                ON e.document_id = d.id
            WHERE d.id = ?1
            LIMIT 1;
            """,
            bind: { stmt in
                bindText(stmt, 1, id)
            }
        ) { stmt in
            let rc = sqlite3_step(stmt)

            if rc == SQLITE_ROW {
                let snapshot = try blobColumn(stmt, index: 0)
                var document = try decode(ExchangeRetrievalDocument.self, from: snapshot)

                if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                    let embeddingData = try blobColumn(stmt, index: 1)
                    let embedding = try decode([Float].self, from: embeddingData)
                    document = document.updatingEmbedding(embedding)
                }

                return document
            }

            if rc == SQLITE_DONE {
                return nil
            }

            throw sqliteError()
        }
    }

    func saveCounterparty(_ counterparty: ExchangeCounterparty) throws {
        let sourceJSON = try encode(counterparty.source)
        let identityJSON = try encodeOptional(counterparty.identity)
        let locationJSON = try encodeOptional(counterparty.location)
        let metadataJSON = try encodeJSON(counterparty.metadata)
        let snapshot = try encode(counterparty)
        let revision = try nextRevision(table: "exchange_counterparties", id: counterparty.id)

        try withStatement("""
            INSERT INTO exchange_counterparties (
                id, created_at, updated_at, revision, kind, display_name, handle, bio,
                trust_level, trust_summary, completed_threads, successful_threads, status,
                source_json, identity_json, location_json, metadata_json, json_snapshot
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)
            ON CONFLICT(id) DO UPDATE SET
                updated_at = excluded.updated_at,
                revision = excluded.revision,
                kind = excluded.kind,
                display_name = excluded.display_name,
                handle = excluded.handle,
                bio = excluded.bio,
                trust_level = excluded.trust_level,
                trust_summary = excluded.trust_summary,
                completed_threads = excluded.completed_threads,
                successful_threads = excluded.successful_threads,
                status = excluded.status,
                source_json = excluded.source_json,
                identity_json = excluded.identity_json,
                location_json = excluded.location_json,
                metadata_json = excluded.metadata_json,
                json_snapshot = excluded.json_snapshot;
            """
        ) { stmt in
            bindText(stmt, 1, counterparty.id)
            bindText(stmt, 2, Self.isoString(from: counterparty.createdAt))
            bindText(stmt, 3, Self.isoString(from: counterparty.updatedAt))
            sqlite3_bind_int64(stmt, 4, revision)
            bindText(stmt, 5, counterparty.kind.rawValue)
            bindText(stmt, 6, counterparty.displayName)
            bindNullableText(stmt, 7, counterparty.handle)
            bindNullableText(stmt, 8, counterparty.bio)
            bindText(stmt, 9, counterparty.trust.level.rawValue)
            bindNullableText(stmt, 10, counterparty.trust.summary)
            sqlite3_bind_int64(stmt, 11, Int64(counterparty.trust.completedThreads))
            sqlite3_bind_int64(stmt, 12, Int64(counterparty.trust.successfulThreads))
            bindText(stmt, 13, counterparty.status.rawValue)
            bindBlob(stmt, 14, sourceJSON)
            bindNullableBlob(stmt, 15, identityJSON)
            bindNullableBlob(stmt, 16, locationJSON)
            bindBlob(stmt, 17, metadataJSON)
            bindBlob(stmt, 18, snapshot)
            try stepDone(stmt)
        }

        try withStatement("DELETE FROM exchange_counterparty_tags WHERE counterparty_id = ?1;") { stmt in
            bindText(stmt, 1, counterparty.id)
            try stepDone(stmt)
        }
        try withStatement("DELETE FROM exchange_counterparty_capabilities WHERE counterparty_id = ?1;") { stmt in
            bindText(stmt, 1, counterparty.id)
            try stepDone(stmt)
        }
        try withStatement("DELETE FROM exchange_contact_routes WHERE counterparty_id = ?1;") { stmt in
            bindText(stmt, 1, counterparty.id)
            try stepDone(stmt)
        }

        let normalizedTags = Set(
            counterparty.tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        for tag in normalizedTags.sorted() {
            try withStatement("""
                INSERT INTO exchange_counterparty_tags (counterparty_id, tag)
                VALUES (?1, ?2);
                """
            ) { stmt in
                bindText(stmt, 1, counterparty.id)
                bindText(stmt, 2, tag)
                try stepDone(stmt)
            }
        }

        for capability in counterparty.capabilities {
            try withStatement("""
                INSERT INTO exchange_counterparty_capabilities (id, counterparty_id, label, category, notes)
                VALUES (?1, ?2, ?3, ?4, ?5);
                """
            ) { stmt in
                bindText(stmt, 1, capability.id.uuidString)
                bindText(stmt, 2, counterparty.id)
                bindText(stmt, 3, capability.label)
                bindNullableText(stmt, 4, capability.category)
                bindNullableText(stmt, 5, capability.notes)
                try stepDone(stmt)
            }
        }

        for route in counterparty.contactRoutes {
            try withStatement("""
                INSERT INTO exchange_contact_routes (id, counterparty_id, kind, value, is_preferred)
                VALUES (?1, ?2, ?3, ?4, ?5);
                """
            ) { stmt in
                bindText(stmt, 1, route.id.uuidString)
                bindText(stmt, 2, counterparty.id)
                bindText(stmt, 3, route.kind.rawValue)
                bindText(stmt, 4, route.value)
                sqlite3_bind_int(stmt, 5, route.isPreferred ? 1 : 0)
                try stepDone(stmt)
            }
        }
    }

    func computeNetworkTrust(
        nodeID: String,
        forSourceNodeID sourceNodeID: String?
    ) throws -> ExchangeTrustedNodeProfile.NetworkTrust {
        let trustedByCount = try scalarInt(
            sql: """
            SELECT COUNT(*)
            FROM exchange_trust_edges
            WHERE target_node_id = ?1 AND revoked_at IS NULL;
            """,
            bind: { stmt in bindText(stmt, 1, nodeID) }
        )

        let trustedByHighTrustCount = try scalarInt(
            sql: """
            SELECT COUNT(*)
            FROM exchange_trust_edges
            WHERE target_node_id = ?1
              AND revoked_at IS NULL
              AND trust_level = ?2;
            """,
            bind: { stmt in
                bindText(stmt, 1, nodeID)
                bindText(stmt, 2, ExchangeTrustEdge.TrustLevel.high.rawValue)
            }
        )

        let trustedByYourTrustedCount: Int
        if let sourceNodeID {
            trustedByYourTrustedCount = try scalarInt(
                sql: """
                SELECT COUNT(DISTINCT inbound.source_node_id)
                FROM exchange_trust_edges inbound
                INNER JOIN exchange_trust_edges my_trusted
                    ON my_trusted.target_node_id = inbound.source_node_id
                WHERE inbound.target_node_id = ?1
                  AND inbound.revoked_at IS NULL
                  AND my_trusted.source_node_id = ?2
                  AND my_trusted.revoked_at IS NULL;
                """,
                bind: { stmt in
                    bindText(stmt, 1, nodeID)
                    bindText(stmt, 2, sourceNodeID)
                }
            )
        } else {
            trustedByYourTrustedCount = 0
        }

        let mutualTrustCount: Int
        if let sourceNodeID {
            mutualTrustCount = try scalarInt(
                sql: """
                SELECT COUNT(*)
                FROM exchange_trust_edges a
                INNER JOIN exchange_trust_edges b
                    ON a.source_node_id = b.target_node_id
                   AND a.target_node_id = b.source_node_id
                WHERE a.source_node_id = ?1
                  AND a.target_node_id = ?2
                  AND a.revoked_at IS NULL
                  AND b.revoked_at IS NULL;
                """,
                bind: { stmt in
                    bindText(stmt, 1, sourceNodeID)
                    bindText(stmt, 2, nodeID)
                }
            )
        } else {
            mutualTrustCount = 0
        }

        let lastObservedAt = try scalarText(
            sql: """
            SELECT MAX(updated_at)
            FROM exchange_trust_edges
            WHERE target_node_id = ?1 AND revoked_at IS NULL;
            """,
            bind: { stmt in bindText(stmt, 1, nodeID) }
        ).flatMap(Self.isoDate)

        return ExchangeTrustedNodeProfile.NetworkTrust(
            trustedByCount: trustedByCount,
            trustedByHighTrustCount: trustedByHighTrustCount,
            trustedByYourTrustedCount: trustedByYourTrustedCount,
            mutualTrustCount: mutualTrustCount,
            lastObservedAt: lastObservedAt
        )
    }

    func computeScopedTrust(nodeID: String) throws -> [ExchangeTrustedNodeProfile.ScopedTrust] {
        var results: [ExchangeTrustedNodeProfile.ScopedTrust] = []

        try withStatement("""
            SELECT s.scope, COUNT(*), COALESCE(SUM(
                CASE e.trust_level
                    WHEN ?1 THEN 1.5
                    WHEN ?2 THEN 1.0
                    WHEN ?3 THEN 0.5
                    ELSE 1.0
                END
            ), 0)
            FROM exchange_trust_edge_scopes s
            INNER JOIN exchange_trust_edges e
                ON e.id = s.trust_edge_id
            WHERE e.target_node_id = ?4
              AND e.revoked_at IS NULL
            GROUP BY s.scope
            ORDER BY COUNT(*) DESC, s.scope ASC;
            """) { stmt in
            bindText(stmt, 1, ExchangeTrustEdge.TrustLevel.high.rawValue)
            bindText(stmt, 2, ExchangeTrustEdge.TrustLevel.standard.rawValue)
            bindText(stmt, 3, ExchangeTrustEdge.TrustLevel.low.rawValue)
            bindText(stmt, 4, nodeID)

            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW {
                    guard let rawScope = textColumn(stmt, index: 0),
                          let scope = ExchangeTrustEdge.TrustScope(rawValue: rawScope) else {
                        continue
                    }

                    let count = Int(sqlite3_column_int64(stmt, 1))
                    let weightedCount = sqlite3_column_double(stmt, 2)

                    results.append(
                        ExchangeTrustedNodeProfile.ScopedTrust(
                            scope: scope,
                            count: count,
                            weightedCount: weightedCount
                        )
                    )
                } else if rc == SQLITE_DONE {
                    break
                } else {
                    throw sqliteError()
                }
            }
        }

        return results
    }

    func isMutualTrust(
        sourceNodeID: String,
        targetNodeID: String
    ) throws -> Bool {
        try scalarInt(
            sql: """
            SELECT COUNT(*)
            FROM exchange_trust_edges
            WHERE source_node_id = ?1
              AND target_node_id = ?2
              AND revoked_at IS NULL;
            """,
            bind: { stmt in
                bindText(stmt, 1, targetNodeID)
                bindText(stmt, 2, sourceNodeID)
            }
        ) > 0
    }

    func gateForAccess() async {
        let currentToken = ExchangeStoreTaskContext.transactionToken

        while let activeTransactionToken, activeTransactionToken != currentToken {
            await withCheckedContinuation { continuation in
                transactionWaiters.append(continuation)
            }
        }
    }

    func gateForTransactionStart(token: UUID) async {
        while let activeTransactionToken, activeTransactionToken != token {
            await withCheckedContinuation { continuation in
                transactionWaiters.append(continuation)
            }
        }
    }

    func resumeTransactionWaiters() {
        let waiters = transactionWaiters
        transactionWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }

    func nextRevision(table: String, id: String) throws -> Int64 {
        let sql = "SELECT revision FROM \(table) WHERE id = ?1 LIMIT 1;"
        var current: Int64 = 0

        try withStatement(sql) { stmt in
            bindText(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW {
                current = sqlite3_column_int64(stmt, 0)
            }
        }

        return max(1, current + 1)
    }

    func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        try Self.encoder.encode(value)
    }

    func scalarInt(
        sql: String,
        bind: (OpaquePointer?) -> Void
    ) throws -> Int {
        var result = 0
        try withStatement(sql) { stmt in
            bind(stmt)
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                result = Int(sqlite3_column_int64(stmt, 0))
            } else if rc != SQLITE_DONE {
                throw sqliteError()
            }
        }
        return result
    }

    func scalarText(
        sql: String,
        bind: (OpaquePointer?) -> Void
    ) throws -> String? {
        var result: String?
        try withStatement(sql) { stmt in
            bind(stmt)
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                result = textColumn(stmt, index: 0)
            } else if rc != SQLITE_DONE {
                throw sqliteError()
            }
        }
        return result
    }

    func fetchHydratedThread(
        sql: String,
        bind: (OpaquePointer?) -> Void
    ) throws -> ExchangeThread? {
        var result: ExchangeThread?
        try withStatement(sql) { stmt in
            bind(stmt)
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                let snapshotData = try blobColumn(stmt, index: 0)
                let metadataData = try blobColumn(stmt, index: 1)
                result = try decodeHydratedThread(
                    snapshotData: snapshotData,
                    metadataColumnData: metadataData
                )
            } else if rc != SQLITE_DONE {
                throw sqliteError()
            }
        }
        return result
    }

    func queryHydratedThreads(
        sql: String,
        bind: (OpaquePointer?) -> Void
    ) throws -> [ExchangeThread] {
        var results: [ExchangeThread] = []

        try withStatement(sql) { stmt in
            bind(stmt)
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW {
                    let snapshotData = try blobColumn(stmt, index: 0)
                    let metadataData = try blobColumn(stmt, index: 1)
                    let decoded = try decodeHydratedThread(
                        snapshotData: snapshotData,
                        metadataColumnData: metadataData
                    )
                    results.append(decoded)
                } else if rc == SQLITE_DONE {
                    break
                } else {
                    throw sqliteError()
                }
            }
        }

        return results
    }

    func decodeHydratedThread(
        snapshotData: Data,
        metadataColumnData: Data
    ) throws -> ExchangeThread {
        var thread = try decode(ExchangeThread.self, from: snapshotData)
        guard !metadataColumnData.isEmpty else { return thread }

        let columnMetadata = try decode([String: String].self, from: metadataColumnData)
        let merged = ExchangeThreadDiscoveryGradeMetadata.mergeColumnMetadata(
            snapshotMetadata: thread.metadata,
            columnMetadata: columnMetadata
        )
        if merged != thread.metadata {
            thread.metadata = merged
        }
        return thread
    }

    func fetchSnapshot<T: Decodable & Sendable>(
        sql: String,
        bind: (OpaquePointer?) -> Void,
        as type: T.Type
    ) throws -> T? {
        var result: T?
        try withStatement(sql) { stmt in
            bind(stmt)
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                let data = try blobColumn(stmt, index: 0)
                result = try decode(T.self, from: data)
            } else if rc != SQLITE_DONE {
                throw sqliteError()
            }
        }
        return result
    }

    func querySnapshots<T: Decodable & Sendable>(
        sql: String,
        bind: (OpaquePointer?) -> Void,
        as type: T.Type
    ) throws -> [T] {
        var results: [T] = []

        try withStatement(sql) { stmt in
            bind(stmt)
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW {
                    let data = try blobColumn(stmt, index: 0)
                    let decoded: T = try decode(T.self, from: data)
                    results.append(decoded)
                } else if rc == SQLITE_DONE {
                    break
                } else {
                    throw sqliteError()
                }
            }
        }

        return results
    }

    func withStatement(
        _ sql: String,
        _ body: (OpaquePointer?) throws -> Void
    ) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError()
        }

        defer { sqlite3_finalize(stmt) }
        try body(stmt)
    }

    func stepDone(_ stmt: OpaquePointer?) throws {
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            throw sqliteError()
        }
    }

    func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard rc == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw ExchangeStoreError.storageFailure(reason: message)
        }
    }

    func sqliteError() -> ExchangeStoreError {
        ExchangeStoreError.storageFailure(reason: String(cString: sqlite3_errmsg(db)))
    }

    func encode<T: Encodable>(_ value: T) throws -> Data {
        try Self.encoder.encode(value)
    }

    func encodeOptional<T: Encodable>(_ value: T?) throws -> Data? {
        guard let value else { return nil }
        return try Self.encoder.encode(value)
    }

    func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T {
        try Self.decoder.decode(T.self, from: data)
    }

    func textColumn(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    func blobColumn(_ stmt: OpaquePointer?, index: Int32) throws -> Data {
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard count > 0, let raw = sqlite3_column_blob(stmt, index) else {
            return Data()
        }
        return Data(bytes: raw, count: count)
    }

    static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func isoString(from date: Date) -> String {
        makeISOFormatter().string(from: date)
    }

    static func isoDate(from string: String) -> Date? {
        makeISOFormatter().date(from: string)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(isoString(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = isoDate(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }()
}

private extension String {
    var nilIfBlankForSQLite: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
    sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
}

private func bindNullableText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
    if let value {
        bindText(stmt, index, value)
    } else {
        sqlite3_bind_null(stmt, index)
    }
}

private func bindBlob(_ stmt: OpaquePointer?, _ index: Int32, _ data: Data) {
    _ = data.withUnsafeBytes { bytes in
        sqlite3_bind_blob(stmt, index, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
    }
}

private func bindNullableBlob(_ stmt: OpaquePointer?, _ index: Int32, _ data: Data?) {
    if let data {
        bindBlob(stmt, index, data)
    } else {
        sqlite3_bind_null(stmt, index)
    }
}
