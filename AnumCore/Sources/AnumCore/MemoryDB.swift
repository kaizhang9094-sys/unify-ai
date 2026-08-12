import Foundation
import SQLite3
import os

// SwiftPM/Xcode sometimes does not expose the SQLITE_TRANSIENT macro to Swift.
// Define it explicitly so sqlite3_bind_text can safely copy Swift strings.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private let memDBLogger = Logger(subsystem: "Anum", category: "MemoryDB")

private func _sqlPreview(_ sql: String, limit: Int = 160) -> String {
    let oneLine = sql.replacingOccurrences(of: "\n", with: " ")
    if oneLine.count <= limit { return oneLine }
    return String(oneLine.prefix(limit)) + "…"
}

final class MemoryDB {
    enum DBError: Error, LocalizedError {
        case openFailed(String)
        case execFailed(String)
        case prepareFailed(String)
        case stepFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let s): return "DB open failed: \(s)"
            case .execFailed(let s): return "DB exec failed: \(s)"
            case .prepareFailed(let s): return "DB prepare failed: \(s)"
            case .stepFailed(let s): return "DB step failed: \(s)"
            }
        }
    }

    private var db: OpaquePointer?

    // MARK: - Maintenance (export / wipe support)

    /// Force WAL contents into the main DB file and truncate the WAL.
    /// This is used to create a clean, single-file snapshot for export.
    func checkpointWalTruncate() throws {
        guard let db else {
            throw DBError.execFailed("wal checkpoint failed: db=nil")
        }
        var nLog: Int32 = 0
        var nCkpt: Int32 = 0

        // Prefer the v2 API for reliability.
        // If the SQLite constants are not imported into Swift, use literal 3 for TRUNCATE.
        let truncateMode: Int32 = 3
        let rc = sqlite3_wal_checkpoint_v2(db, nil, truncateMode, &nLog, &nCkpt)
        if rc != SQLITE_OK {
            let msg = sqliteErrorDetails(rc: rc)
            memDBLogger.error("[MemoryDB] wal_checkpoint(TRUNCATE) FAILED err=\(msg, privacy: .public)")
            debugPrint("[MemoryDB] wal_checkpoint(TRUNCATE) FAILED err=\(msg)")
            throw DBError.execFailed("wal checkpoint failed: \(msg)")
        }

        memDBLogger.info("[MemoryDB] wal_checkpoint(TRUNCATE) OK logPages=\(nLog) ckptPages=\(nCkpt)")
        debugPrint("[MemoryDB] wal_checkpoint(TRUNCATE) OK logPages=\(nLog) ckptPages=\(nCkpt)")
    }

    /// Close the underlying SQLite handle. Safe to call multiple times.
    /// Used before deleting the DB file(s) on a full wipe.
    func close() {
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
        memDBLogger.info("[MemoryDB] close()")
        debugPrint("[MemoryDB] close()")
    }

    private func sqliteErrorDetails(rc: Int32? = nil) -> String {
        guard let db else {
            if let rc { return "rc=\(rc) (db=nil)" }
            return "(db=nil)"
        }
        let code = sqlite3_errcode(db)
        let xcode = sqlite3_extended_errcode(db)
        let msg = String(cString: sqlite3_errmsg(db))
        if let rc {
            return "rc=\(rc) code=\(code) xcode=\(xcode) msg=\(msg)"
        }
        return "code=\(code) xcode=\(xcode) msg=\(msg)"
    }

#if DEBUG
    private func debugPrint(_ s: String) {
        print(s)
    }
#else
    private func debugPrint(_ s: String) { }
#endif

    init(url: URL) throws {
        try open(url: url)
        try createSchemaIfNeeded()
        try migrateSchemaIfNeeded()
    }

    deinit {
        close()
    }

    private func open(url: URL) throws {
        let path = url.path

        // Ensure parent directory exists (common cause of silent “new DB each run” if callers pass a non-existent folder).
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        memDBLogger.info("Opening MemoryDB at path: \(path, privacy: .public)")
        if path.contains("/tmp/") || path.contains("/Caches/") {
            memDBLogger.warning("MemoryDB path is under tmp/Caches; persistence across sessions is not guaranteed: \(path, privacy: .public)")
        }

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openRC = sqlite3_open_v2(path, &db, flags, nil)
        if openRC != SQLITE_OK {
            let msg = sqliteErrorDetails(rc: openRC)
            memDBLogger.error("[MemoryDB] open FAILED path=\(path, privacy: .public) err=\(msg, privacy: .public)")
            debugPrint("[MemoryDB] open FAILED path=\(path) err=\(msg)")
            throw DBError.openFailed(msg)
        }
        memDBLogger.info("MemoryDB open OK")
        // small perf knobs
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("PRAGMA temp_store=MEMORY;")
        try exec("PRAGMA foreign_keys=ON;")
    }

    private func createSchemaIfNeeded() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS mem_items (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            last_accessed INTEGER NOT NULL,
            importance REAL NOT NULL DEFAULT 0.2,
            salience REAL NOT NULL DEFAULT 0.2,
            stability REAL NOT NULL DEFAULT 0.2,
            pinned INTEGER NOT NULL DEFAULT 0,
            source_turn_id TEXT,
            hash TEXT NOT NULL
        );
        """)

        try exec("CREATE INDEX IF NOT EXISTS idx_mem_items_created ON mem_items(created_at);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_items_accessed ON mem_items(last_accessed);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_items_pinned ON mem_items(pinned);")
        try exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_mem_items_hash ON mem_items(hash);")

        // FTS5 (title/body) linked to mem_items via rowid
        try exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS mem_fts
        USING fts5(title, body, content='mem_items', content_rowid='rowid');
        """)

        // Triggers to keep FTS in sync
        try exec("""
        CREATE TRIGGER IF NOT EXISTS mem_items_ai AFTER INSERT ON mem_items BEGIN
            INSERT INTO mem_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
        END;
        """)
        try exec("""
        CREATE TRIGGER IF NOT EXISTS mem_items_ad AFTER DELETE ON mem_items BEGIN
            INSERT INTO mem_fts(mem_fts, rowid, title, body) VALUES('delete', old.rowid, old.title, old.body);
        END;
        """)
        try exec("""
        CREATE TRIGGER IF NOT EXISTS mem_items_au AFTER UPDATE ON mem_items BEGIN
            INSERT INTO mem_fts(mem_fts, rowid, title, body) VALUES('delete', old.rowid, old.title, old.body);
            INSERT INTO mem_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
        END;
        """)

        // --- Phase 4: Embeddings (quantized int8) ---
        // Stores a quantized embedding vector per memory item.
        // qbytes: int8 bytes (length = dim)
        // scale: dequant scale (float)
        // updated_at: unix seconds
        try exec("""
        CREATE TABLE IF NOT EXISTS mem_embeddings (
            mem_id TEXT PRIMARY KEY,
            dim INTEGER NOT NULL,
            qbytes BLOB NOT NULL,
            scale REAL NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY(mem_id) REFERENCES mem_items(id) ON DELETE CASCADE
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_embeddings_updated ON mem_embeddings(updated_at);")

        // --- Phase 5: Graph memory (SQLite-friendly) ---
        try exec("""
        CREATE TABLE IF NOT EXISTS graph_nodes (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL DEFAULT '',
            salience REAL NOT NULL DEFAULT 0.2,
            updated_at INTEGER NOT NULL
        );
        """)

        try exec("""
        CREATE TABLE IF NOT EXISTS graph_edges (
            src TEXT NOT NULL,
            dst TEXT NOT NULL,
            rel TEXT NOT NULL,
            weight REAL NOT NULL DEFAULT 0.2,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (src, dst, rel),
            FOREIGN KEY(src) REFERENCES graph_nodes(id) ON DELETE CASCADE,
            FOREIGN KEY(dst) REFERENCES graph_nodes(id) ON DELETE CASCADE
        );
        """)

        try exec("""
        CREATE TABLE IF NOT EXISTS graph_node_tags (
            node TEXT NOT NULL,
            tag TEXT NOT NULL,
            PRIMARY KEY (node, tag),
            FOREIGN KEY(node) REFERENCES graph_nodes(id) ON DELETE CASCADE
        );
        """)

        try exec("CREATE INDEX IF NOT EXISTS idx_graph_edges_src ON graph_edges(src);")
        try exec("CREATE INDEX IF NOT EXISTS idx_graph_edges_dst ON graph_edges(dst);")
        try exec("CREATE INDEX IF NOT EXISTS idx_graph_node_tags_tag ON graph_node_tags(tag);")
        try exec("CREATE INDEX IF NOT EXISTS idx_graph_nodes_type ON graph_nodes(type);")

        // Optional: link memories to extracted entities (Phase 5.2)
        try exec("""
        CREATE TABLE IF NOT EXISTS mem_entities (
            mem_id TEXT NOT NULL,
            entity TEXT NOT NULL,
            etype TEXT NOT NULL DEFAULT 'entity',
            weight REAL NOT NULL DEFAULT 0.2,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (mem_id, entity, etype),
            FOREIGN KEY(mem_id) REFERENCES mem_items(id) ON DELETE CASCADE
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_entities_entity ON mem_entities(entity);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_entities_mem ON mem_entities(mem_id);")
        
        // --- Phase 6: Memory Map meta (mind palace index) ---
        // Stores compact, stable summaries (e.g., memory_map_blurb) and timestamps.
        try exec("""
        CREATE TABLE IF NOT EXISTS mem_kv (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_kv_updated ON mem_kv(updated_at);")
    }

    // MARK: - Schema migration

    /// Adds new columns introduced after the initial schema shipped.
    /// NOTE: `CREATE TABLE IF NOT EXISTS` does not add columns; we must `ALTER TABLE`.
    private func migrateSchemaIfNeeded() throws {
        // mem_items new columns for richer memory objects
        try addColumnIfMissing(table: "mem_items", column: "scope", definition: "TEXT NOT NULL DEFAULT 'global'")
        try addColumnIfMissing(table: "mem_items", column: "kind", definition: "TEXT NOT NULL DEFAULT 'fact'")
        try addColumnIfMissing(table: "mem_items", column: "source", definition: "TEXT NOT NULL DEFAULT 'user'")
        try addColumnIfMissing(table: "mem_items", column: "confidence", definition: "REAL NOT NULL DEFAULT 0.75")
        // unix seconds
        try addColumnIfMissing(table: "mem_items", column: "updated_at", definition: "INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER))")

        // Phase 7-ish: deprecate + trust gate
        try addColumnIfMissing(table: "mem_items", column: "status", definition: "TEXT NOT NULL DEFAULT 'active'")
        try addColumnIfMissing(table: "mem_items", column: "trust", definition: "TEXT NOT NULL DEFAULT 'unconfirmed'")
        try addColumnIfMissing(table: "mem_items", column: "deprecated_at", definition: "INTEGER")
        try addColumnIfMissing(table: "mem_items", column: "replaced_by", definition: "TEXT")
        try addColumnIfMissing(table: "mem_items", column: "confirmed_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(table: "mem_items", column: "last_confirmed_at", definition: "INTEGER")

        // Optional indices to keep queries fast
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_items_scope ON mem_items(scope);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_items_kind ON mem_items(kind);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_items_updated ON mem_items(updated_at);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_items_status ON mem_items(status);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_items_trust ON mem_items(trust);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_items_deprecated_at ON mem_items(deprecated_at);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_items_replaced_by ON mem_items(replaced_by);")

        // Best-effort backfill: if kind exists but is still default, copy from legacy `type`.
        do {
            try exec("UPDATE mem_items SET kind = type WHERE (kind IS NULL OR kind = '' OR kind = 'fact');")
        } catch {
            memDBLogger.warning("[MemoryDB] kind backfill skipped/failed: \(String(describing: error), privacy: .public)")
        }
        
        // Best-effort backfill: ensure status/trust are set if older rows have NULL/empty.
        do {
            try exec("UPDATE mem_items SET status = 'active' WHERE (status IS NULL OR status = '');")
            try exec("UPDATE mem_items SET trust = 'unconfirmed' WHERE (trust IS NULL OR trust = '');")
        } catch {
            memDBLogger.warning("[MemoryDB] status/trust backfill skipped/failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func addColumnIfMissing(table: String, column: String, definition: String) throws {
        if try hasColumn(table: table, column: column) {
            return
        }
        let sql = "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);"
        memDBLogger.info("[MemoryDB] Migrating: \(sql, privacy: .public)")
        try exec(sql)
    }

    private func hasColumn(table: String, column: String) throws -> Bool {
        let sql = "PRAGMA table_info(\(table));"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            // PRAGMA table_info columns: 0=cid,1=name,2=type,...
            let name = MemoryDB.colText(stmt, 1)
            if name == column {
                return true
            }
        }
        return false
    }

    // MARK: - Exec / Prepare

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? sqliteErrorDetails(rc: rc)
            sqlite3_free(err)
            let preview = _sqlPreview(sql)
            memDBLogger.error("[MemoryDB] exec FAILED rc=\(rc) sql=\(preview, privacy: .public) err=\(msg, privacy: .public)")
            debugPrint("[MemoryDB] exec FAILED rc=\(rc) sql=\(preview) err=\(msg)")
            throw DBError.execFailed(msg)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            let msg = sqliteErrorDetails(rc: rc)
            let preview = _sqlPreview(sql)
            memDBLogger.error("[MemoryDB] prepare FAILED rc=\(rc) sql=\(preview, privacy: .public) err=\(msg, privacy: .public)")
            debugPrint("[MemoryDB] prepare FAILED rc=\(rc) sql=\(preview) err=\(msg)")
            throw DBError.prepareFailed(msg)
        }
        return stmt
    }

    func stepDone(_ stmt: OpaquePointer?) throws {
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            let msg = sqliteErrorDetails(rc: rc)
            memDBLogger.error("[MemoryDB] step FAILED \(msg, privacy: .public)")
            debugPrint("[MemoryDB] step FAILED \(msg)")
            throw DBError.stepFailed(msg)
        }
    }

    // MARK: - Transactions

    /// Runs `block` inside a BEGIN IMMEDIATE transaction.
    /// If `block` throws, the transaction is rolled back and the error is rethrown.
    @discardableResult
    func inTransaction<T>(_ label: String = "txn", _ block: () throws -> T) throws -> T {
        do {
            try exec("BEGIN IMMEDIATE;")
        } catch {
            memDBLogger.error("[MemoryDB] BEGIN failed (\(label, privacy: .public)) err=\(String(describing: error), privacy: .public)")
            throw error
        }

        do {
            let result = try block()
            try exec("COMMIT;")
            return result
        } catch {
            do {
                try exec("ROLLBACK;")
            } catch {
                memDBLogger.error("[MemoryDB] ROLLBACK failed (\(label, privacy: .public)) err=\(String(describing: error), privacy: .public)")
            }
            memDBLogger.error("[MemoryDB] txn failed (\(label, privacy: .public)) err=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    // MARK: - Writes (Phase 1+)

    /// Insert a memory item.
    ///
    /// - Uses the UNIQUE `hash` index for de-dupe. If an item already exists with the same hash,
    ///   we return the existing id instead of throwing.
    /// - FTS is kept in sync by DB triggers (mem_items_ai/au/ad).
    @discardableResult
    func insertMemItem(
        id: String,
        type: String,
        title: String,
        body: String,
        createdAt: Int64,
        lastAccessed: Int64,
        importance: Double = 0.2,
        salience: Double = 0.2,
        stability: Double = 0.2,
        pinned: Bool = false,
        sourceTurnId: String? = nil,
        hash: String,
        scope: String = "global",
        kind: String? = nil,
        source: String = "user",
        confidence: Double = 0.75,
        status: String = "active",
        trust: String = "unconfirmed",
        deprecatedAt: Int64? = nil,
        replacedBy: String? = nil,
        confirmedCount: Int = 0,
        lastConfirmedAt: Int64? = nil,
        updatedAt: Int64? = nil
    ) throws -> String {

        // Fast path: if the hash already exists, return its id.
        if let existing = try fetchMemIdByHash(hash) {
            memDBLogger.debug("[MemoryDB] insertMemItem deduped hash=\(hash, privacy: .public) -> id=\(existing, privacy: .public)")
            return existing
        }

        let sql = """
        INSERT INTO mem_items(
            id, type, title, body, created_at, last_accessed,
            importance, salience, stability, pinned, source_turn_id, hash,
            scope, kind, source, confidence, updated_at,
            status, trust, deprecated_at, replaced_by, confirmed_count, last_confirmed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        do {
            stmt = try prepare(sql)
        } catch {
            memDBLogger.error("[MemoryDB] insertMemItem prepare failed err=\(String(describing: error), privacy: .public)")
            throw error
        }

        defer { sqlite3_finalize(stmt) }

        // bind
        MemoryDB.bindText(stmt, 1, id)
        MemoryDB.bindText(stmt, 2, type)
        MemoryDB.bindText(stmt, 3, title)
        MemoryDB.bindText(stmt, 4, body)
        MemoryDB.bindInt(stmt, 5, createdAt)
        MemoryDB.bindInt(stmt, 6, lastAccessed)
        MemoryDB.bindDouble(stmt, 7, importance)
        MemoryDB.bindDouble(stmt, 8, salience)
        MemoryDB.bindDouble(stmt, 9, stability)
        MemoryDB.bindInt(stmt, 10, pinned ? 1 : 0)
        MemoryDB.bindText(stmt, 11, sourceTurnId)
        MemoryDB.bindText(stmt, 12, hash)

        let resolvedKind = (kind?.isEmpty == false) ? kind! : type
        let resolvedUpdatedAt = updatedAt ?? createdAt

        MemoryDB.bindText(stmt, 13, scope)
        MemoryDB.bindText(stmt, 14, resolvedKind)
        MemoryDB.bindText(stmt, 15, source)
        MemoryDB.bindDouble(stmt, 16, confidence)
        MemoryDB.bindInt(stmt, 17, resolvedUpdatedAt)
        MemoryDB.bindText(stmt, 18, status)
        MemoryDB.bindText(stmt, 19, trust)
        MemoryDB.bindInt(stmt, 20, deprecatedAt)
        MemoryDB.bindText(stmt, 21, replacedBy)
        sqlite3_bind_int(stmt, 22, Int32(max(0, confirmedCount)))
        MemoryDB.bindInt(stmt, 23, lastConfirmedAt)
        
        do {
            try stepDone(stmt)
        } catch {
            // If we raced with another insert on the same hash, try to resolve by reading.
            if let existing = try? fetchMemIdByHash(hash) {
                memDBLogger.debug("[MemoryDB] insertMemItem raced; resolved via hash -> id=\(existing, privacy: .public)")
                return existing
            }
            memDBLogger.error("[MemoryDB] insertMemItem step failed id=\(id, privacy: .public) hash=\(hash, privacy: .public) err=\(String(describing: error), privacy: .public)")
            throw error
        }

        memDBLogger.debug("[MemoryDB] insertMemItem OK id=\(id, privacy: .public) type=\(type, privacy: .public) kind=\(resolvedKind, privacy: .public) scope=\(scope, privacy: .public) source=\(source, privacy: .public) conf=\(confidence, privacy: .public) hash=\(hash, privacy: .public)")
        return id
    }

    // MARK: - Deprecate / Trust gate helpers

    /// Mark a memory as deprecated (excluded from retrieval/injection by default).
    /// Optionally link it to a replacement memory id.
    func deprecateMemItem(id: String, now: Int64, replacedBy: String? = nil) throws {
        let sql = """
        UPDATE mem_items
        SET status = 'deprecated',
            deprecated_at = ?,
            replaced_by = ?,
            updated_at = ?
        WHERE id = ?;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        MemoryDB.bindInt(stmt, 1, now)
        MemoryDB.bindText(stmt, 2, replacedBy)
        MemoryDB.bindInt(stmt, 3, now)
        MemoryDB.bindText(stmt, 4, id)

        try stepDone(stmt)
    }

    /// Mark a memory as confirmed (used for trust-gated personal facts/preferences).
    /// Increments confirmed_count and updates last_confirmed_at.
    func confirmMemItem(id: String, now: Int64) throws {
        let sql = """
        UPDATE mem_items
        SET trust = 'confirmed',
            confirmed_count = confirmed_count + 1,
            last_confirmed_at = ?,
            updated_at = ?
        WHERE id = ?;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        MemoryDB.bindInt(stmt, 1, now)
        MemoryDB.bindInt(stmt, 2, now)
        MemoryDB.bindText(stmt, 3, id)

        try stepDone(stmt)
    }

    /// Upsert an embedding row for a memory item.
    func upsertEmbedding(
        memId: String,
        dim: Int,
        qbytes: Data,
        scale: Double,
        updatedAt: Int64
    ) throws {
        let sql = """
        INSERT INTO mem_embeddings(mem_id, dim, qbytes, scale, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(mem_id) DO UPDATE SET
            dim=excluded.dim,
            qbytes=excluded.qbytes,
            scale=excluded.scale,
            updated_at=excluded.updated_at;
        """

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        MemoryDB.bindText(stmt, 1, memId)
        sqlite3_bind_int(stmt, 2, Int32(dim))
        MemoryDB.bindBlob(stmt, 3, qbytes)
        MemoryDB.bindDouble(stmt, 4, scale)
        MemoryDB.bindInt(stmt, 5, updatedAt)

        do {
            try stepDone(stmt)
            memDBLogger.debug("[MemoryDB] upsertEmbedding OK memId=\(memId, privacy: .public) dim=\(dim)")
        } catch {
            memDBLogger.error("[MemoryDB] upsertEmbedding FAILED memId=\(memId, privacy: .public) err=\(String(describing: error), privacy: .public)")
            throw error
        }
    }
    
    // MARK: - Meta KV (Phase 6)

    /// Upsert a small meta value (e.g., memory_map_blurb).
    func upsertKV(key: String, value: String, updatedAt: Int64) throws {
        let sql = """
        INSERT INTO mem_kv(key, value, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            value=excluded.value,
            updated_at=excluded.updated_at;
        """

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        MemoryDB.bindText(stmt, 1, key)
        MemoryDB.bindText(stmt, 2, value)
        MemoryDB.bindInt(stmt, 3, updatedAt)

        try stepDone(stmt)
    }

    /// Fetch a meta value by key.
    func fetchKV(_ key: String) throws -> (value: String, updatedAt: Int64)? {
        let sql = "SELECT value, updated_at FROM mem_kv WHERE key = ? LIMIT 1;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        MemoryDB.bindText(stmt, 1, key)

        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
            let v = MemoryDB.colText(stmt, 0)
            let ts = MemoryDB.colInt(stmt, 1)
            return (v, ts)
        }
        if rc == SQLITE_DONE { return nil }
        throw DBError.stepFailed(String(cString: sqlite3_errmsg(db)))
    }

    // MARK: - Proposal: Access & injection signals

    /// Increment access_count and update last_accessed for a set of memories.
    func markAccessed(memIds: [String], now: Int64) throws {
        guard !memIds.isEmpty else { return }
        let placeholders = memIds.map { _ in "?" }.joined(separator: ",")
        let sql = """
        UPDATE mem_items
        SET last_accessed = ?,
            access_count = access_count + 1
        WHERE id IN (\(placeholders));
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        MemoryDB.bindInt(stmt, 1, now)
        for (i, id) in memIds.enumerated() {
            MemoryDB.bindText(stmt, Int32(2 + i), id)
        }
        try stepDone(stmt)
    }

    /// Update last_injected_at for a set of memories (does not change access_count).
    func markInjected(memIds: [String], now: Int64) throws {
        guard !memIds.isEmpty else { return }
        let placeholders = memIds.map { _ in "?" }.joined(separator: ",")
        let sql = """
        UPDATE mem_items
        SET last_injected_at = ?
        WHERE id IN (\(placeholders));
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        MemoryDB.bindInt(stmt, 1, now)
        for (i, id) in memIds.enumerated() {
            MemoryDB.bindText(stmt, Int32(2 + i), id)
        }
        try stepDone(stmt)
    }

    /// Insert an injection log row for the current turn.
    func insertInjectionLog(turnId: String, queryHash: String, injectedIdsCSV: String, now: Int64) throws {
        let sql = """
        INSERT INTO mem_injection_log(id, turn_id, query_hash, injected_ids, created_at)
        VALUES(?, ?, ?, ?, ?);
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        MemoryDB.bindText(stmt, 1, UUID().uuidString)
        MemoryDB.bindText(stmt, 2, turnId)
        MemoryDB.bindText(stmt, 3, queryHash)
        MemoryDB.bindText(stmt, 4, injectedIdsCSV)
        MemoryDB.bindInt(stmt, 5, now)

        try stepDone(stmt)
    }

    // MARK: - Reads / helpers used by write-path

    /// Returns an existing mem_items.id for a given hash (dedupe key), or nil if not found.
    func fetchMemIdByHash(_ hash: String) throws -> String? {
        let sql = "SELECT id FROM mem_items WHERE hash = ? LIMIT 1;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        MemoryDB.bindText(stmt, 1, hash)

        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
            return MemoryDB.colText(stmt, 0)
        }
        if rc == SQLITE_DONE {
            return nil
        }
        throw DBError.stepFailed(String(cString: sqlite3_errmsg(db)))
    }

    /// Convenience: quickly count rows for debug.
    func countRows(_ table: String) throws -> Int64 {
        // NOTE: Only used for internal debug with trusted table names.
        let sql = "SELECT COUNT(*) FROM \(table);"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
            return MemoryDB.colInt(stmt, 0)
        }
        if rc == SQLITE_DONE {
            return 0
        }
        throw DBError.stepFailed(String(cString: sqlite3_errmsg(db)))
    }

    // MARK: - Bind helpers

    static func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ s: String?) {
        if let s {
            sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    static func bindInt(_ stmt: OpaquePointer?, _ idx: Int32, _ v: Int64) {
        sqlite3_bind_int64(stmt, idx, v)
    }

    static func bindInt(_ stmt: OpaquePointer?, _ idx: Int32, _ v: Int64?) {
        if let v {
            sqlite3_bind_int64(stmt, idx, v)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    static func bindDouble(_ stmt: OpaquePointer?, _ idx: Int32, _ v: Double) {
        sqlite3_bind_double(stmt, idx, v)
    }

    static func bindBlob(_ stmt: OpaquePointer?, _ idx: Int32, _ data: Data?) {
        if let data {
            data.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                sqlite3_bind_blob(stmt, idx, ptr, Int32(data.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    // MARK: - Column helpers

    static func colText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }

    static func colInt(_ stmt: OpaquePointer?, _ idx: Int32) -> Int64 {
        sqlite3_column_int64(stmt, idx)
    }

    static func colDouble(_ stmt: OpaquePointer?, _ idx: Int32) -> Double {
        sqlite3_column_double(stmt, idx)
    }

    static func colBlob(_ stmt: OpaquePointer?, _ idx: Int32) -> Data? {
        guard let ptr = sqlite3_column_blob(stmt, idx) else { return nil }
        let len = Int(sqlite3_column_bytes(stmt, idx))
        return Data(bytes: ptr, count: len)
    }

    static func colIsNull(_ stmt: OpaquePointer?, _ idx: Int32) -> Bool {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL
    }
}
