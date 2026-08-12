
import Foundation
import CryptoKit
import SQLite3

// -----------------------------
// DEBUG-only logging (shipping hygiene)
// -----------------------------
@inline(__always)
private func msLog(_ msg: @autoclosure () -> String) {
#if DEBUG
    print(msg())
#endif
}

/// Phase 4: sentence embedding provider (CoreML/ONNX/etc.).
/// Implement this in the App layer and inject it into MemoryStore.
public protocol MemoryEmbeddingProvider: Sendable {
    /// Returns a vector embedding for `text`.
    /// - Note: Return `nil` if the embedder is unavailable.
    func embed(_ text: String) -> [Float]?
}

public enum MemoryStoreError: Error {
    case databaseClosed
}

public actor MemoryStore {
    public static let shared = MemoryStore()
    
    private var db: MemoryDB
    private let dbURL: URL
    private let now: () -> Date

    // When true, the SQLite handle has been intentionally closed for a full wipe.
    // Call `reopenAfterWipe()` after deleting files to continue using MemoryStore in the same app process.
    private var dbClosedForWipe: Bool = false
    
    // Phase 4: optional embedding provider (CoreML/ONNX). If nil, we fall back to hashed embeddings.
    private var embeddingProvider: MemoryEmbeddingProvider? = nil
    
    // Phase 4: keep a fixed embedding dimensionality across providers for stable DB + rerank.
    // Most tiny sentence embedders use 384 dims; we normalize/shape whatever the provider returns.
    private let targetEmbeddingDim: Int = 384
    
    // Phase 4/5 schema guard
    private var didEnsurePhase45Tables = false
    
    // MARK: - Init
    
    private init(now: @escaping () -> Date = Date.init) {
        self.now = now
        
        let url = Self.makeDBURL()
        self.dbURL = url
        
#if DEBUG
        let exists = FileManager.default.fileExists(atPath: url.path)
        msLog("[MemoryStore] DB url=\(url.path) exists=\(exists)")
#endif

        
        do {
            self.db = try MemoryDB(url: url)
            self.dbClosedForWipe = false
        } catch {
            // If DB fails, crash loudly in dev; you can soften later.
            fatalError("MemoryDB init failed: \(error)")
        }

#if DEBUG
        // Dump counts at boot so we can verify we're opening the DB we think we are.
        // Must hop onto the actor after init finishes (can't call actor-isolated methods directly in init).
        Task { [weak self] in
            guard let self else { return }
            await self.debugDumpStats(tag: "boot")
        }
#endif
    }
    
    private static func makeDBURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Anum", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("memory.sqlite")
    }

    // MARK: - Export / Wipe support

    /// Create a clean, single-file snapshot of `memory.sqlite` suitable for export.
    /// Uses WAL checkpoint(TRUNCATE) so we don't need to include -wal/-shm sidecars.
    /// - Parameters:
    ///   - folderURL: destination folder (will be created if missing)
    ///   - filename: output filename inside `folderURL`
    /// - Returns: URL to the copied snapshot file.
    public func exportDatabaseSnapshot(to folderURL: URL, filename: String = "memory.sqlite") throws -> URL {
        if dbClosedForWipe {
            throw MemoryStoreError.databaseClosed
        }

        let fm = FileManager.default
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // Flush WAL -> main DB file, then truncate WAL.
        try db.checkpointWalTruncate()

        let dst = folderURL.appendingPathComponent(filename)
        if fm.fileExists(atPath: dst.path) {
            try? fm.removeItem(at: dst)
        }
        try fm.copyItem(at: dbURL, to: dst)

#if DEBUG
        msLog("[MemoryStore] exportDatabaseSnapshot wrote=\(dst.path)")
#endif
        return dst
    }

    /// Close the SQLite handle so the DB file(s) can be deleted on a full wipe.
    public func closeForWipe() {
        db.close()
        dbClosedForWipe = true
#if DEBUG
        msLog("[MemoryStore] closeForWipe")
#endif
    }

    /// Reopen the SQLite handle after a full wipe deleted the DB file.
    /// Call this after you delete `Application Support/Anum/` and before you use MemoryStore again.
    public func reopenAfterWipe() throws {
        guard dbClosedForWipe else { return }

        let fm = FileManager.default
        let dir = dbURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        self.db = try MemoryDB(url: dbURL)
        dbClosedForWipe = false
#if DEBUG
        msLog("[MemoryStore] reopenAfterWipe dbURL=\(dbURL.path)")
#endif
    }
    
    // MARK: - Public API (Phase 1)
    
    /// Configure an optional sentence embedding provider (CoreML/ONNX).
    /// If not set, MemoryStore uses a deterministic hashed embedding fallback.
    public func setEmbeddingProvider(_ provider: MemoryEmbeddingProvider?) {
        self.embeddingProvider = provider
#if DEBUG
        if let provider {
            msLog("[MemoryStore] setEmbeddingProvider provider=\(String(describing: Swift.type(of: provider)))")
        } else {
            msLog("[MemoryStore] setEmbeddingProvider provider=nil (will use hashed fallback)")
        }
#endif
        
        // Best-effort: once a real embedder is injected, warm up embeddings for recent memories.
        // This avoids having only hashed embeddings in the DB when you first enable Phase 4.
        if provider != nil {
            Task { [weak self] in
                guard let self else { return }
                await self.warmupEmbeddingsForExistingMemories(limit: 200)
            }
        }
    }
    
    /// Best-effort embedding warmup for existing memories.
    /// Safe on iOS: capped by `limit` and only embeds semantic + episodic items.
    public func warmupEmbeddingsForExistingMemories(limit: Int = 200) async {
#if DEBUG
        let pName = embeddingProvider.map { String(describing: type(of: $0)) } ?? "nil"
        msLog("[MemoryStore] warmupEmbeddingsForExistingMemories START provider=\(pName) limit=\(limit)")
#endif
        do {
            try ensurePhase45TablesIfNeeded()
            let items = try listRecent(limit: max(1, limit))
                .filter { $0.type == .semantic || $0.type == .episodic || $0.type == .procedural }
            
            var embedded = 0
            for it in items {
                do {
                    try upsertEmbeddingForMemoryIfEligible(id: it.id, type: it.type, title: it.title, body: it.body, force: true)
                    embedded += 1
                } catch {
                    // Keep going; warmup is best-effort.
                    continue
                }
            }
            
            msLog("[MemoryStore] warmupEmbeddingsForExistingMemories embedded=\(embedded) limit=\(limit)")
        } catch {
            msLog("[MemoryStore] warmupEmbeddingsForExistingMemories failed: \(error)")
        }
    }
    
    public func addMemory(
        type: MemoryItemType,
        title: String,
        body: String,
        importance: Double = 0.25,
        salience: Double = 0.25,
        stability: Double = 0.25,
        pinned: Bool = false,
        sourceTurnId: UUID? = nil
    ) throws -> String {
        let t = now()
        let created = Int64(t.timeIntervalSince1970)
        let accessed = created
        
        let normalized = "\(type.rawValue)|\(title.trimmingCharacters(in: .whitespacesAndNewlines))|\(body.trimmingCharacters(in: .whitespacesAndNewlines))"
        let hash = sha256Hex(normalized)
#if DEBUG
        msLog("[MemoryStore] addMemory requested type=\(type.rawValue) titleChars=\(title.count) bodyChars=\(body.count) pinned=\(pinned) sourceTurnId=\(sourceTurnId?.uuidString ?? "nil")")
#endif
        
        // Dedupe by hash
        if let existingId = try findIdByHash(hash) {
            try bumpExisting(id: existingId, importance: importance, salience: salience)
#if DEBUG
            // Helpful when diagnosing “memory not persistent across sessions”.
            self.debugDumpStats(tag: "after_add_dedupe")
#endif
            return existingId
        }
        
        let id = UUID().uuidString
#if DEBUG
        msLog("[MemoryStore] addMemory newId=\(id)")
#endif
        
        let stmt = try db.prepare("""
        INSERT INTO mem_items
        (id, type, title, body, created_at, last_accessed, importance, salience, stability, pinned, source_turn_id, hash)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """)
        
        defer { sqlite3_finalize(stmt) }
        
        MemoryDB.bindText(stmt, 1, id)
        MemoryDB.bindText(stmt, 2, type.rawValue)
        MemoryDB.bindText(stmt, 3, title)
        MemoryDB.bindText(stmt, 4, body)
        MemoryDB.bindInt(stmt, 5, created)
        MemoryDB.bindInt(stmt, 6, accessed)
        MemoryDB.bindDouble(stmt, 7, clamp01(importance))
        MemoryDB.bindDouble(stmt, 8, clamp01(salience))
        MemoryDB.bindDouble(stmt, 9, clamp01(stability))
        MemoryDB.bindInt(stmt, 10, pinned ? 1 : 0)
        MemoryDB.bindText(stmt, 11, sourceTurnId?.uuidString)
        MemoryDB.bindText(stmt, 12, hash)
        
        try db.stepDone(stmt)
        
        // Phase 5: lightweight entity + graph indexing (best-effort)
        do {
            try ensurePhase45TablesIfNeeded()
            try indexGraphForMemory(id: id, type: type, title: title, body: body)
        } catch {
            msLog("[MemoryStore] graph index failed: \(error)")
        }
        
        // Phase 4: embeddings (iOS-safe hashed embedding for now; swap later with real embedder)
        do {
            try ensurePhase45TablesIfNeeded()
            try upsertEmbeddingForMemoryIfEligible(id: id, type: type, title: title, body: body)
        } catch {
            msLog("[MemoryStore] embedding upsert failed: \(error)")
        }
        
        
        #if DEBUG
        // Helpful when diagnosing “memory not persistent across sessions”.
        self.debugDumpStats(tag: "after_add")
        #endif
        // Basic safety: keep the DB from growing without bound (best-effort).
        do {
            _ = try pruneMemItemsIfNeeded()
        } catch {
            msLog("[MemoryStore] prune (after_add) failed: \(error)")
        }
        return id
    }
    
    public func pinMemory(_ id: String, pinned: Bool) throws {
        let stmt = try db.prepare("UPDATE mem_items SET pinned = ? WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindInt(stmt, 1, pinned ? 1 : 0)
        MemoryDB.bindText(stmt, 2, id)
        try db.stepDone(stmt)
    }
    
    public func touchMemory(_ id: String) throws {
        let ts = Int64(now().timeIntervalSince1970)
        let stmt = try db.prepare("UPDATE mem_items SET last_accessed = ? WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindInt(stmt, 1, ts)
        MemoryDB.bindText(stmt, 2, id)
        try db.stepDone(stmt)
    }
    
    public func listRecent(limit: Int = 20) throws -> [MemoryItem] {
        let stmt = try db.prepare("""
        SELECT id, type, title, body, created_at, last_accessed, importance, salience, stability, pinned, source_turn_id, hash
        FROM mem_items
        ORDER BY last_accessed DESC, created_at DESC
        LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindInt(stmt, 1, Int64(max(1, limit)))
        
        var items: [MemoryItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            items.append(readItem(stmt))
        }
        return items
    }
    
    // MARK: - Basic growth control (Pruning v1)

    // Keep memory growth bounded on mobile.
    // This is intentionally conservative: never deletes pinned items, and avoids deleting high-stability/high-importance memories.
    private let maxMemItemsDefault: Int = 2000
    private let pruneBatchDefault: Int = 200

    private func countMemItems() throws -> Int {
        let stmt = try db.prepare("SELECT COUNT(*) FROM mem_items;")
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(MemoryDB.colInt(stmt, 0))
        }
        return 0
    }

    /// Prune low-value memories if we exceed `maxItems`.
    /// - Returns: number of pruned items.
    @discardableResult
    private func pruneMemItemsIfNeeded(maxItems: Int? = nil, batch: Int? = nil) throws -> Int {
        let cap = max(100, maxItems ?? maxMemItemsDefault)
        let batchN = max(1, min(500, batch ?? pruneBatchDefault))

        let total = try countMemItems()
        if total <= cap { return 0 }

        let need = min(batchN, total - cap)
        if need <= 0 { return 0 }

        // Select oldest/least-recent low-value items first.
        // NOTE: thresholds are tuned to avoid deleting stable facts/preferences.
        let idsToDelete: [String] = try {
            let stmt = try db.prepare("""
            SELECT id
            FROM mem_items
            WHERE pinned = 0
              AND stability < 0.55
              AND importance < 0.55
            ORDER BY last_accessed ASC, created_at ASC
            LIMIT ?;
            """)
            defer { sqlite3_finalize(stmt) }
            MemoryDB.bindInt(stmt, 1, Int64(need))

            var ids: [String] = []
            ids.reserveCapacity(need)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = MemoryDB.colText(stmt, 0)
                if !id.isEmpty { ids.append(id) }
            }
            return ids
        }()

        if idsToDelete.isEmpty { return 0 }

        // Delete in a single transaction (best-effort cleanup of related tables).
        let pruned: Int = try db.inTransaction("pruneMemItems") {
            var removed = 0

            // Prepared statements reused in the loop.
            let rowidStmt = try db.prepare("SELECT rowid FROM mem_items WHERE id = ? LIMIT 1;")
            defer { sqlite3_finalize(rowidStmt) }

            let delFtsStmt = try db.prepare("DELETE FROM mem_fts WHERE rowid = ?;")
            defer { sqlite3_finalize(delFtsStmt) }

            let delEmbStmt = try db.prepare("DELETE FROM mem_embeddings WHERE mem_id = ?;")
            defer { sqlite3_finalize(delEmbStmt) }

            let delEntStmt = try db.prepare("DELETE FROM mem_entities WHERE mem_id = ?;")
            defer { sqlite3_finalize(delEntStmt) }

            let delEdgesStmt = try db.prepare("DELETE FROM graph_edges WHERE src = ? OR dst = ?;")
            defer { sqlite3_finalize(delEdgesStmt) }

            let delNodeStmt = try db.prepare("DELETE FROM graph_nodes WHERE id = ?;")
            defer { sqlite3_finalize(delNodeStmt) }

            let delItemStmt = try db.prepare("DELETE FROM mem_items WHERE id = ?;")
            defer { sqlite3_finalize(delItemStmt) }

            for id in idsToDelete {
                // 1) If FTS is external content without triggers, delete the rowid explicitly.
                sqlite3_reset(rowidStmt)
                sqlite3_clear_bindings(rowidStmt)
                MemoryDB.bindText(rowidStmt, 1, id)

                var rowid: Int64? = nil
                if sqlite3_step(rowidStmt) == SQLITE_ROW {
                    rowid = MemoryDB.colInt(rowidStmt, 0)
                }

                if let rid = rowid {
                    sqlite3_reset(delFtsStmt)
                    sqlite3_clear_bindings(delFtsStmt)
                    MemoryDB.bindInt(delFtsStmt, 1, rid)
                    try db.stepDone(delFtsStmt)
                }

                // 2) Best-effort cleanup of related tables.
                sqlite3_reset(delEmbStmt)
                sqlite3_clear_bindings(delEmbStmt)
                MemoryDB.bindText(delEmbStmt, 1, id)
                try db.stepDone(delEmbStmt)

                sqlite3_reset(delEntStmt)
                sqlite3_clear_bindings(delEntStmt)
                MemoryDB.bindText(delEntStmt, 1, id)
                try db.stepDone(delEntStmt)

                let memNodeId = "mem:\(id)"
                sqlite3_reset(delEdgesStmt)
                sqlite3_clear_bindings(delEdgesStmt)
                MemoryDB.bindText(delEdgesStmt, 1, memNodeId)
                MemoryDB.bindText(delEdgesStmt, 2, memNodeId)
                try db.stepDone(delEdgesStmt)

                sqlite3_reset(delNodeStmt)
                sqlite3_clear_bindings(delNodeStmt)
                MemoryDB.bindText(delNodeStmt, 1, memNodeId)
                try db.stepDone(delNodeStmt)

                // 3) Delete the memory itself.
                sqlite3_reset(delItemStmt)
                sqlite3_clear_bindings(delItemStmt)
                MemoryDB.bindText(delItemStmt, 1, id)
                try db.stepDone(delItemStmt)

                removed += 1
            }

            return removed
        }

#if DEBUG
        if pruned > 0 {
            msLog("[MemoryStore] pruneMemItemsIfNeeded pruned=\(pruned) totalBefore=\(total) cap=\(cap)")
        }
#endif
        return pruned
    }

    // MARK: - Phase 1.5 (Ingest + Parsing)
    
    /// Ingest a single user utterance and, when it contains stable signals (facts/preferences/instructions),
    /// convert it into structured memory entries.
    ///
    /// Notes:
    /// - This does NOT run on every message unless the caller calls it (ChatViewModel should call this).
    /// - It is intentionally heuristic + conservative to avoid spamming the DB.
    /// - Returns the ids of created (or deduped) memory items.
    public func ingestUserText(_ text: String, sourceTurnId: UUID? = nil) throws -> [String] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        let lower = raw.lowercased()
        let isCorrection = containsCorrectionCue(lower)
        
        // Explicit forgetting: allow users to retract bad/test memories (e.g., "forget about alabala").
        // We treat this as a high-signal corrective action.
        let forgetTargets = extractForgetTargets(from: raw)

        let candidates = detectMemoryCandidates(from: raw)
        // Convert to a Sendable snapshot for safe capture in the DB transaction closure.
        let candidatesSnapshot: [IngestCandidateSnapshot] = candidates.map {
            IngestCandidateSnapshot(
                typeRaw: $0.type.rawValue,
                title: $0.title,
                body: $0.body,
                importance: $0.importance,
                salience: $0.salience,
                stability: $0.stability,
                pinned: $0.pinned
            )
        }
#if DEBUG
        msLog("[MemoryStore] ingestUserText textChars=\(raw.count) candidates=\(candidatesSnapshot.count) sourceTurnId=\(sourceTurnId?.uuidString ?? "nil")")
#endif
        // If there are no new candidates but the user asked to forget something, run deprecation anyway.
        if candidatesSnapshot.isEmpty {
            if !forgetTargets.isEmpty {
                let ts = Int64(now().timeIntervalSince1970)
                _ = try db.inTransaction("ingestUserText_forgetOnly") {
                    for term in forgetTargets {
                        // Use the existing retrieval pipeline to find likely matches.
                        // Prefer FTS when possible; otherwise fall back to recent/pinned candidates.
                        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
                        if q.isEmpty { continue }
                        
                        var hits: [MemoryCandidate] = []
                        if q.count >= 3 {
                            let ftsQ = ftsQueryFromUserText(q)
                            if !ftsQ.isEmpty {
                                hits += (try? searchFTS(ftsQ, limit: 25)) ?? []
                            }
                        }
                        if hits.isEmpty {
                            hits += (try? recentCandidates(limit: 25)) ?? []
                            hits += (try? pinnedCandidates(limit: 25)) ?? []
                        }

                        // Deprecate the top matches first.
                        // NOTE: MemoryDB provides `deprecateMemItem` in our Phase 6+ patch.
                        let ranked = hits.sorted { $0.score > $1.score }.prefix(12)
                        for h in ranked {
                            // Avoid deprecating the user's name by accident.
                            let t = h.item.title.lowercased()
                            if t == "user name" || t == "preferred name" { continue }
                            try? db.deprecateMemItem(id: h.item.id, now: ts, replacedBy: nil)
                        }
                    }
                    return true
                }
            }
            return []
        }

        let ts = Int64(now().timeIntervalSince1970)

        // Track which ids were updated in-place (so we can refresh embeddings).
        var updatedIds = Set<String>()

        // IMPORTANT: actual DB writes happen inside a single transaction.
        let ids: [String] = try db.inTransaction("ingestUserText") {
            var out: [String] = []
            out.reserveCapacity(candidatesSnapshot.count)

            // If the user asked to forget something, deprecate matching memories before we write new ones.
            if !forgetTargets.isEmpty {
                for term in forgetTargets {
                    let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
                    if q.isEmpty { continue }

                    var hits: [MemoryCandidate] = []
                    if q.count >= 3 {
                        let ftsQ = ftsQueryFromUserText(q)
                        if !ftsQ.isEmpty {
                            hits += (try? searchFTS(ftsQ, limit: 25)) ?? []
                        }
                    }
                    if hits.isEmpty {
                        hits += (try? recentCandidates(limit: 25)) ?? []
                        hits += (try? pinnedCandidates(limit: 25)) ?? []
                    }

                    let ranked = hits.sorted { $0.score > $1.score }.prefix(12)
                    for h in ranked {
                        let t = h.item.title.lowercased()
                        if t == "user name" || t == "preferred name" { continue }
                        try? db.deprecateMemItem(id: h.item.id, now: ts, replacedBy: nil)
                    }
                }
            }

            // If the user says "that's not my <key>" without giving a replacement, deprecate the existing canonical item.
            // This is primarily to clean up injected test identifiers that get latched onto.
            let denyKeys = extractNotMyKeys(from: raw)
            if isCorrection, !denyKeys.isEmpty {
                for k in denyKeys {
                    // If the same utterance provides a new value for the key, the upsert path below will handle it.
                    // Only deprecate when we have an existing canonical entry for that key.
                    if let existing = try? findExistingCanonical(typeRaw: MemoryItemType.semantic.rawValue, title: k) {
                        // `findExistingCanonical(...)` returns a tuple snapshot here (no `.title`), and we already know the key name `k`.
                        let t = k.lowercased()
                        if t == "user name" || t == "preferred name" { continue }
                        try? db.deprecateMemItem(id: existing.id, now: ts, replacedBy: nil)
                    }
                }
            }

            for c in candidatesSnapshot {
                // Stable dedupe hash
                let normalized = "\(c.typeRaw)|\(c.title.trimmingCharacters(in: .whitespacesAndNewlines))|\(c.body.trimmingCharacters(in: .whitespacesAndNewlines))"
                let hash = sha256Hex(normalized)

                // Canonical update path: when a user corrects something ("actually...") or when the candidate looks like
                // a stable slot (pinned/high-stability or known titles), update existing instead of duplicating.
                let shouldUpsertCanonical = isCorrection || c.pinned || c.stability >= 0.85 || isCanonicalTitle(c.title)

                if shouldUpsertCanonical, let existing = try findExistingCanonical(typeRaw: c.typeRaw, title: c.title) {
                    // Only update if body changed.
                    if existing.body.trimmingCharacters(in: .whitespacesAndNewlines) != c.body.trimmingCharacters(in: .whitespacesAndNewlines) {
                        try updateMemItem(
                            id: existing.id,
                            typeRaw: c.typeRaw,
                            title: c.title,
                            body: c.body,
                            createdAt: existing.createdAt,
                            lastAccessed: ts,
                            importance: clamp01(max(c.importance, existing.importance)),
                            salience: clamp01(max(c.salience, existing.salience)),
                            stability: clamp01(max(c.stability, existing.stability)),
                            pinned: (existing.pinned || c.pinned),
                            sourceTurnId: sourceTurnId?.uuidString,
                            hash: hash
                        )
                        updatedIds.insert(existing.id)
                    } else {
                        // Touch for recency.
                        try touchMemItem(id: existing.id, lastAccessed: ts)
                    }

                    out.append(existing.id)
                    // Corrections and canonical slots are high-signal: mark as confirmed.
                    if isCorrection || c.pinned || c.stability >= 0.75 || isCanonicalTitle(c.title) {
                        try? db.confirmMemItem(id: existing.id, now: ts)
                    }
                } else {
                    // Insert (or return existing id on hash conflict)
                    let newId = UUID().uuidString
                    let finalId = try db.insertMemItem(
                        id: newId,
                        type: c.typeRaw,
                        title: c.title,
                        body: c.body,
                        createdAt: ts,
                        lastAccessed: ts,
                        importance: clamp01(c.importance),
                        salience: clamp01(c.salience),
                        stability: clamp01(c.stability),
                        pinned: c.pinned,
                        sourceTurnId: sourceTurnId?.uuidString,
                        hash: hash
                    )

                    out.append(finalId)
                    // Newly stored stable memories should be confirmed when they come from explicit signals.
                    if isCorrection || c.pinned || c.stability >= 0.75 || isCanonicalTitle(c.title) {
                        try? db.confirmMemItem(id: finalId, now: ts)
                    }
                }

#if DEBUG
                let impStr = String(format: "%.2f", c.importance)
                let salStr = String(format: "%.2f", c.salience)
                let stabStr = String(format: "%.2f", c.stability)
                msLog("[MemoryStore] ingest tx insert type=\(c.typeRaw) id=\(String(out.last?.prefix(8) ?? "")) title=\(c.title) bodyChars=\(c.body.count) imp=\(impStr) sal=\(salStr) stab=\(stabStr) pinned=\(c.pinned)")
#endif
            }

            return out
        }

        // Phase 5 + Phase 4: index graph + embeddings for every ingested candidate.
        // IMPORTANT: use `finalId` returned by insertMemItem (may be an existing id due to hash dedupe).
        // Best-effort: failures should not break ingestion.
        do {
            try ensurePhase45TablesIfNeeded()
            for (i, finalId) in ids.enumerated() {
                guard i < candidatesSnapshot.count else { break }
                let c = candidatesSnapshot[i]

                // Graph indexing
                do {
                    try indexGraphForMemory(id: finalId, type: c.type, title: c.title, body: c.body)
                } catch {
                    msLog("[MemoryStore] graph index (ingest) failed id=\(String(finalId.prefix(8))): \(error)")
                }

                // Embedding upsert
                do {
                    try upsertEmbeddingForMemoryIfEligible(id: finalId, type: c.type, title: c.title, body: c.body, force: updatedIds.contains(finalId))
                } catch {
                    msLog("[MemoryStore] embedding upsert (ingest) failed id=\(String(finalId.prefix(8))): \(error)")
                }
            }
        } catch {
            msLog("[MemoryStore] ensurePhase45TablesIfNeeded (ingest) failed: \(error)")
        }

        // Basic safety: keep the DB from growing without bound (best-effort).
        do {
            _ = try pruneMemItemsIfNeeded()
        } catch {
            msLog("[MemoryStore] prune (after_ingest) failed: \(error)")
        }

#if DEBUG
        self.debugDumpStats(tag: "after_ingest")
#endif
        return ids
    }
    
    // Sendable snapshot used when capturing candidates into @Sendable / escaping closures.
    // Stores type as rawValue to avoid requiring MemoryItemType to be Sendable.
    private struct IngestCandidateSnapshot: Sendable {
        let typeRaw: String
        let title: String
        let body: String
        let importance: Double
        let salience: Double
        let stability: Double
        let pinned: Bool

        var type: MemoryItemType {
            MemoryItemType(rawValue: typeRaw) ?? .semantic
        }
    }

    private struct IngestCandidate {
        let type: MemoryItemType
        let title: String
        let body: String
        let importance: Double
        let salience: Double
        let stability: Double
        let pinned: Bool
    }
    
    /// Heuristic intent detection for memory-worthy signals.
    /// Goal: capture stable facts + preferences + do/don't instructions, without requiring the exact word "remember".
    private func detectMemoryCandidates(from text: String) -> [IngestCandidate] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        
        let lower = raw.lowercased()
        let isCorrection = containsCorrectionCue(lower)
        
        // If the utterance is a question and doesn't contain a memory cue, skip.
        // (Prevents the common case of "what is my ..." from being stored.)
        if raw.contains("?") && !containsMemoryCue(lower) {
            return []
        }
        
        var out: [IngestCandidate] = []
        out.reserveCapacity(6)
        
        // 1) Explicit cues: remember/note/save/keep in mind
        if containsExplicitRememberCue(lower) {
            if let payload = captureRememberPayload(from: raw) {
                let p = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty {
                    // Try to also extract key/value facts from within the remember payload.
                    out += extractKeyValueFacts(from: p)
                    
                    // Store the payload itself as a semantic note (low-ish stability by default).
                    out.append(IngestCandidate(
                        type: .semantic,
                        title: "Note",
                        body: p,
                        importance: 0.45,
                        salience: 0.45,
                        stability: 0.35,
                        pinned: false
                    ))
                }
            }
        }
        
        // 2) Self facts (name / identifiers)
        if let name = firstCapture("(?i)\\bmy\\s+name\\s+is\\s+([^\\.\\n\\r\\t\\,]+)", in: raw) {
            let v = cleanClause(name)
            if isReasonableValue(v, maxLen: 48) {
                out.append(IngestCandidate(type: .semantic, title: "User name", body: v, importance: 0.70, salience: 0.65, stability: 0.85, pinned: true))
            }
        }
        if let nick = firstCapture("(?i)\\bcall\\s+me\\s+([^\\.\\n\\r\\t\\,]+)", in: raw) {
            let v = cleanClause(nick)
            if isReasonableValue(v, maxLen: 48) {
                out.append(IngestCandidate(type: .semantic, title: "Preferred name", body: v, importance: 0.70, salience: 0.65, stability: 0.85, pinned: true))
            }
        }
        
        // 3) Generic key/value facts: "my X is Y" (scopekey, email handle, etc.)
        out += extractKeyValueFacts(from: raw)
        
        // 4) Preferences: like/love/enjoy/prefer
        if let liked = firstCapture("(?i)\\b(?:i\\s+)?(?:really\\s+)?(?:like|love|enjoy|prefer)\\s+([^\\.\\n\\r\\t\\?]+)", in: raw) {
            let v = cleanClause(liked)
            if isReasonableValue(v, maxLen: 120) {
                out.append(IngestCandidate(type: .semantic, title: "Preference", body: "Likes: \(v)", importance: 0.40, salience: 0.45, stability: 0.55, pinned: false))
            }
        }
        if let hated = firstCapture("(?i)\\b(?:i\\s+)?(?:really\\s+)?(?:hate|dislike|can\\s*not\\s*stand)\\s+([^\\.\\n\\r\\t\\?]+)", in: raw) {
            let v = cleanClause(hated)
            if isReasonableValue(v, maxLen: 120) {
                out.append(IngestCandidate(type: .semantic, title: "Aversion", body: "Dislikes: \(v)", importance: 0.45, salience: 0.45, stability: 0.55, pinned: false))
            }
        }
        if let dontLike = firstCapture("(?i)\\b(?:i\\s+)?(?:do\\s*not|don't)\\s+like\\s+([^\\.\\n\\r\\t\\?]+)", in: raw) {
            let v = cleanClause(dontLike)
            if isReasonableValue(v, maxLen: 120) {
                out.append(IngestCandidate(type: .semantic, title: "Aversion", body: "Dislikes: \(v)", importance: 0.45, salience: 0.45, stability: 0.55, pinned: false))
            }
        }

        // 4b) Subject preferences: "my cat prefers X" / "my dog likes X".
        // This helps store pet/thing preferences that don't start with "I ...".
        let subjPrefMatches = allCaptures("(?i)\\bmy\\s+([a-z0-9_]{2,32})\\s+prefers\\s+([^\\.\\n\\r\\t\\?]+)", in: raw)
        for (subjRaw, prefRaw) in subjPrefMatches {
            let subj = cleanClause(subjRaw)
            let v = cleanClause(prefRaw)
            if isReasonableValue(subj, maxLen: 32), isReasonableValue(v, maxLen: 120) {
                let imp = isCorrection ? 0.65 : 0.55
                let sal = isCorrection ? 0.60 : 0.50
                let stab = isCorrection ? 0.80 : 0.70
                out.append(IngestCandidate(type: .semantic, title: "Preference", body: "\(subj) prefers: \(v)", importance: imp, salience: sal, stability: stab, pinned: false))
            }
        }

        let subjLikeMatches = allCaptures("(?i)\\bmy\\s+([a-z0-9_]{2,32})\\s+(?:likes|loves|enjoys)\\s+([^\\.\\n\\r\\t\\?]+)", in: raw)
        for (subjRaw, likeRaw) in subjLikeMatches {
            let subj = cleanClause(subjRaw)
            let v = cleanClause(likeRaw)
            if isReasonableValue(subj, maxLen: 32), isReasonableValue(v, maxLen: 120) {
                let imp = isCorrection ? 0.60 : 0.50
                let sal = isCorrection ? 0.55 : 0.45
                let stab = isCorrection ? 0.75 : 0.65
                out.append(IngestCandidate(type: .semantic, title: "Preference", body: "\(subj) likes: \(v)", importance: imp, salience: sal, stability: stab, pinned: false))
            }
        }
        
        // 5) Behavioral instructions: stop / don't / do not / please don't
        if let stopAction = firstCapture("(?i)\\b(?:please\\s+)?stop\\s+([^\\.\\n\\r\\t\\?]+)", in: raw) {
            let v = cleanClause(stopAction)
            if isReasonableValue(v, maxLen: 160) {
                out.append(IngestCandidate(type: .procedural, title: "Do not", body: "Stop: \(v)", importance: 0.55, salience: 0.55, stability: 0.70, pinned: false))
            }
        }
        if let dontAction = firstCapture("(?i)\\b(?:please\\s+)?(?:do\\s*not|don't)\\s+([^\\.\\n\\r\\t\\?]+)", in: raw) {
            let v = cleanClause(dontAction)
            if isReasonableValue(v, maxLen: 160) {
                out.append(IngestCandidate(type: .procedural, title: "Do not", body: "Avoid: \(v)", importance: 0.55, salience: 0.55, stability: 0.70, pinned: false))
            }
        }

        // 5.5) Goals: "my training goal is ..." / "goal: ..." (store as stable-ish semantic intent).
        if let goal = firstCapture("(?i)\\b(?:my\\s+)?(?:training\\s+)?goal\\s*(?:is|=|:)\\s*([^\\.\\n\\r\\t\\?]+)", in: raw) {
            let v = cleanClause(goal)
            if isReasonableValue(v, maxLen: 180) {
                let imp = isCorrection ? 0.70 : 0.60
                let sal = isCorrection ? 0.65 : 0.55
                let stab = isCorrection ? 0.85 : 0.75
                out.append(IngestCandidate(type: .semantic, title: "Training goal", body: v, importance: imp, salience: sal, stability: stab, pinned: false))
            }
        }
        
        // 6) Feelings (episodic): "I feel ...". Low stability by default.
        if let feeling = firstCapture("(?i)\\b(?:i\\s+feel|i'm\\s+feeling)\\s+([^\\.\\n\\r\\t\\?]+)", in: raw) {
            let v = cleanClause(feeling)
            if isReasonableValue(v, maxLen: 160) {
                out.append(IngestCandidate(type: .episodic, title: "Feeling", body: v, importance: 0.25, salience: 0.35, stability: 0.15, pinned: false))
            }
        }
        
        // Deduplicate by (type,title,body) to avoid adding duplicates from overlapping patterns.
        var seen = Set<String>()
        var deduped: [IngestCandidate] = []
        for c in out {
            let key = "\(c.type.rawValue)|\(c.title.lowercased())|\(c.body.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            deduped.append(c)
        }
        
        // Conservative cap: never ingest more than 5 items from a single utterance.
        if deduped.count > 5 { return Array(deduped.prefix(5)) }
        return deduped
    }
    
    private func containsMemoryCue(_ lower: String) -> Bool {
        // Broad cues (stable preference/instruction shifts)
        return lower.contains("remember") || lower.contains("note") || lower.contains("save") || lower.contains("keep in mind") ||
               lower.contains("my name is") || lower.contains("call me") ||
               lower.contains("i like") || lower.contains("i love") || lower.contains("i prefer") ||
               lower.contains("i hate") || lower.contains("i dislike") || lower.contains("don't like") ||
               lower.contains("please stop") || lower.contains("do not") || lower.contains("don't ") ||
               lower.contains("i feel") || lower.contains("i'm feeling") ||
               lower.contains("goal is") || lower.contains("training goal") || lower.contains("goal:")
    }
    
    private func containsExplicitRememberCue(_ lower: String) -> Bool {
        return lower.contains("remember") || lower.contains("note") || lower.contains("save") || lower.contains("keep in mind")
    }
    
    private func containsCorrectionCue(_ lower: String) -> Bool {
        // Lightweight correction detector. Used to boost importance and prefer updating existing canonical memories.
        if lower.contains("actually") { return true }
        if lower.contains("i meant") { return true }
        if lower.contains("no, ") || lower.hasPrefix("no ") { return true }
        if lower.contains("not ") && (lower.contains("my ") || lower.contains("i ")) { return true }
        return false
    }

    private func captureRememberPayload(from text: String) -> String? {
        // Capture whatever comes after: remember / note / save / keep in mind
        // Example: "remember this exactly: my scopekey is scopetest001"
        if let m = firstCapture("(?i)\\bremember\\b[^:]*[:\\-]?\\s*(.+)$", in: text) { return m }
        if let m = firstCapture("(?i)\\bnote\\b[^:]*[:\\-]?\\s*(.+)$", in: text) { return m }
        if let m = firstCapture("(?i)\\bsave\\b[^:]*[:\\-]?\\s*(.+)$", in: text) { return m }
        if let m = firstCapture("(?i)\\bkeep\\s+in\\s+mind\\b[^:]*[:\\-]?\\s*(.+)$", in: text) { return m }
        return nil
    }
    
    private func extractKeyValueFacts(from text: String) -> [IngestCandidate] {
        // Extract: "my <key> is <value>" where <key> is a short identifier-ish token.
        // We keep this strict to reduce false positives.
        var out: [IngestCandidate] = []
        
        let lower = text.lowercased()
        // Avoid extracting from questions like "what is my ...".
        if lower.hasPrefix("what is my") || lower.hasPrefix("what's my") { return [] }
        
        let pattern = "(?i)\\bmy\\s+([a-z0-9_]{2,32})\\s+(?:is|=)\\s+([a-z0-9_\\-]{2,64})\\b"
        let matches = allCaptures(pattern, in: text)
        for (kRaw, vRaw) in matches {
            let k = cleanClause(kRaw)
            let v = cleanClause(vRaw)
            guard isReasonableValue(k, maxLen: 32), isReasonableValue(v, maxLen: 64) else { continue }
            out.append(IngestCandidate(
                type: .semantic,
                title: k,
                body: v,
                importance: 0.65,
                salience: 0.60,
                stability: 0.85,
                pinned: true
            ))
        }
        return out
    }
    
    private func cleanClause(_ s: String) -> String {
        // Remove leading/trailing punctuation and compress whitespace.
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’ ,;:"))
        let parts = stripped.split(whereSeparator: { $0.isWhitespace || $0 == "\n" || $0 == "\t" }).map(String.init)
        return parts.joined(separator: " ")
    }
    
    private func isReasonableValue(_ s: String, maxLen: Int) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        if t.count > maxLen { return false }
        // Avoid obviously unhelpful captures.
        if t.lowercased() == "it" || t.lowercased() == "that" || t.lowercased() == "this" { return false }
        return true
    }
    
    private func firstCapture(_ pattern: String, in text: String) -> String? {
        do {
            let re = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let m = re.firstMatch(in: text, options: [], range: range) else { return nil }
            guard m.numberOfRanges >= 2 else { return nil }
            if let r = Range(m.range(at: 1), in: text) {
                return String(text[r])
            }
            return nil
        } catch {
            return nil
        }
    }
    
    private func allCaptures(_ pattern: String, in text: String) -> [(String, String)] {
        do {
            let re = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let ms = re.matches(in: text, options: [], range: range)
            var out: [(String, String)] = []
            out.reserveCapacity(ms.count)
            for m in ms {
                guard m.numberOfRanges >= 3 else { continue }
                guard let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) else { continue }
                out.append((String(text[r1]), String(text[r2])))
            }
            return out
        } catch {
            return []
        }
    }
    
    // MARK: - Deprecate / Forget helpers (Phase 6+)

    private func extractForgetTargets(from text: String) -> [String] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return [] }

        // Support: "forget X", "forget about X", "please forget X"
        // Capture a short phrase; keep it conservative.
        var out: [String] = []
        if let t = firstCapture("(?i)\\b(?:please\\s+)?forget\\s+(?:about\\s+)?([^\\.\\n\\r\\t\\?]+)", in: raw) {
            let v = cleanClause(t)
            if isReasonableValue(v, maxLen: 80) { out.append(v) }
        }
        if let t = firstCapture("(?i)\\bdelete\\s+(?:that|this|it)\\b\\s*(?:about\\s+)?([^\\.\\n\\r\\t\\?]+)", in: raw) {
            let v = cleanClause(t)
            if isReasonableValue(v, maxLen: 80) { out.append(v) }
        }

        // De-dupe
        var seen = Set<String>()
        out = out.filter { seen.insert($0.lowercased()).inserted }
        return out
    }

    private func extractNotMyKeys(from text: String) -> [String] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return [] }

        // Capture: "that's not my <key>" or "not my <key>" where <key> is identifier-ish.
        let matches = allCaptures("(?i)\\b(?:that'?s\\s+)?not\\s+my\\s+([a-z0-9_]{2,32})\\b", in: raw)
        var out: [String] = []
        out.reserveCapacity(matches.count)
        for (k, _) in matches {
            let key = cleanClause(k)
            if isReasonableValue(key, maxLen: 32) { out.append(key) }
        }

        var seen = Set<String>()
        out = out.filter { seen.insert($0.lowercased()).inserted }
        return out
    }

    private func filterOutDeprecatedCandidates(_ candidates: [MemoryCandidate]) throws -> [MemoryCandidate] {
        if candidates.isEmpty { return candidates }

        // If the DB doesn't have the column, treat everything as active.
        // We probe using PRAGMA table_info which is cheap.
        let hasStatus: Bool = {
            do {
                let stmt = try db.prepare("PRAGMA table_info(mem_items);")
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let col = MemoryDB.colText(stmt, 1)
                    if col == "status" { return true }
                }
            } catch {
                return false
            }
            return false
        }()

        if !hasStatus { return candidates }

        // Batch check statuses for candidate ids.
        let ids = candidates.map { $0.id }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let stmt = try db.prepare("SELECT id, status FROM mem_items WHERE id IN (\(placeholders));")
        defer { sqlite3_finalize(stmt) }
        for (i, id) in ids.enumerated() {
            MemoryDB.bindText(stmt, Int32(i + 1), id)
        }

        var statusById: [String: String] = [:]
        statusById.reserveCapacity(ids.count)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = MemoryDB.colText(stmt, 0)
            let st = MemoryDB.colText(stmt, 1)
            statusById[id] = st
        }

        return candidates.filter { c in
            let st = statusById[c.id]?.lowercased() ?? "active"
            return st != "deprecated"
        }
    }

    // MARK: - Phase 2 (Retrieval + Context Pack)
    
    public func buildContextPack(
        query: String,
        maxItems: Int = 10,
        includeDebug: Bool = true
    ) throws -> MemoryContextPack {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let useFTS = q.count >= 4
#if DEBUG
        msLog("[MemoryStore] buildContextPack queryChars=\(q.count) useFTS=\(useFTS)")
#endif
        
        var candidates: [MemoryCandidate] = []
        
        // Phase 5: add related candidates via graph expansion (cheap 1-hop)
        do {
            try ensurePhase45TablesIfNeeded()
            // 1-hop via graph_edges (Neo4j-lite)
            candidates += try graphOneHopCandidatesViaEdges(query: q, limit: 40)
            // fallback/extra signal via mem_entities join
            candidates += try graphExpandCandidates(query: q, limit: 40)
        } catch {
            // ignore; we’ll fall back to FTS/recent/pinned
        }
        
        if useFTS {
            let ftsQ = ftsQueryFromUserText(q)
#if DEBUG
            msLog("[MemoryStore] buildContextPack ftsQuery=\(ftsQ)")
#endif
            if !ftsQ.isEmpty {
                candidates += try searchFTS(ftsQ, limit: 30)
            }
        }
        candidates += try recentCandidates(limit: 20)
        candidates += try pinnedCandidates(limit: 20)
#if DEBUG
        msLog("[MemoryStore] buildContextPack candidates preDedupe=\(candidates.count)")
#endif
        
        // de-dupe by id, keep highest score
        var best: [String: MemoryCandidate] = [:]
        for c in candidates {
            if let prev = best[c.id] {
                if c.score > prev.score { best[c.id] = c }
            } else {
                best[c.id] = c
            }
        }

        // materialize merged candidates after de-dupe
        var mergedCandidates = Array(best.values)

        #if DEBUG
        msLog("[MemoryStore] buildContextPack candidates postDedupe=\(mergedCandidates.count)")
        #endif
        
        // Drop deprecated memories so injected test identifiers don’t keep surfacing forever.
        // This is best-effort and will behave as a no-op on older DBs that don't have `status`.
        mergedCandidates = (try? filterOutDeprecatedCandidates(mergedCandidates)) ?? mergedCandidates

        // Phase 4: vector rerank (only over small candidate set)
        var vecApplied = false
        do {
            try ensurePhase45TablesIfNeeded()
            let out = try vectorRerankCandidates(query: q, candidates: mergedCandidates, maxScan: 200)
            mergedCandidates = out.candidates
            vecApplied = out.applied
        } catch {
            vecApplied = false
        }
#if DEBUG
        let sortedPreview = mergedCandidates.sorted { $0.score > $1.score }.prefix(maxItems)
        let preview = sortedPreview.map { c in
            let shortId = String(c.id.prefix(8))
            return "\(shortId):\(String(format: "%.3f", c.score))"
        }.joined(separator: ",")
        msLog("[MemoryStore] buildContextPack vecApplied=\(vecApplied) top=\(preview)")
#endif
        
        let merged = mergedCandidates
            .sorted { $0.score > $1.score }
            .prefix(maxItems)
        
        var facts: [String] = []
        var events: [String] = []
        var procedures: [String] = []
        
        var usedForDebug: [(String, Double, MemoryItemType, Bool)] = []
        
        for c in merged {
            let item = c.item
            let line = formatLine(item)
            switch item.type {
            case .semantic:   facts.append(line)
            case .episodic:   events.append(line)
            case .procedural: procedures.append(line)
            }
            usedForDebug.append((item.id, c.score, item.type, item.pinned))
        }
        
        let stratBase = useFTS ? "FTS+recent+pinned" : "recent+pinned"
        let strat = vecApplied ? stratBase + "+vec" : stratBase
        
        let dbg = includeDebug
        ? MemoryDebugInfo(used: usedForDebug, query: q, strategy: strat)
        : nil
        
        return MemoryContextPack(facts: facts, events: events, procedures: procedures, debug: dbg)
    }
    
    /// Phase 2: Simple retrieval API (FTS5-first), returning raw items.
    /// Uses the same candidate + scoring pipeline as `buildContextPack`.
    public func retrieve(query: String, limit: Int = 6) throws -> [MemoryItem] {
        let q0 = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q0.isEmpty else { return [] }
        
        // Use a conservative switch so we don't spam FTS for tiny inputs.
        let useFTS = q0.count >= 4
#if DEBUG
        msLog("[MemoryStore] retrieve queryChars=\(q0.count) useFTS=\(useFTS) limit=\(limit)")
#endif
        
        var candidates: [MemoryCandidate] = []
        
        // Phase 5: graph expansion candidates
        do {
            try ensurePhase45TablesIfNeeded()
            // 1-hop via graph_edges (Neo4j-lite)
            candidates += try graphOneHopCandidatesViaEdges(query: q0, limit: 40)
            // fallback/extra signal via mem_entities join
            candidates += try graphExpandCandidates(query: q0, limit: 40)
        } catch {
            // ignore
        }
        
        if useFTS {
            let ftsQ = ftsQueryFromUserText(q0)
#if DEBUG
            msLog("[MemoryStore] retrieve ftsQuery=\(ftsQ)")
#endif
            if !ftsQ.isEmpty {
                candidates += try searchFTS(ftsQ, limit: max(20, limit * 6))
            }
        }
        
        // Always include lightweight priors.
        candidates += try recentCandidates(limit: max(10, limit * 3))
        candidates += try pinnedCandidates(limit: max(10, limit * 3))
#if DEBUG
        msLog("[MemoryStore] retrieve candidates preDedupe=\(candidates.count)")
#endif

        // de-dupe by id, keep highest score
        var best: [String: MemoryCandidate] = [:]
        for c in candidates {
            if let prev = best[c.id] {
                if c.score > prev.score { best[c.id] = c }
            } else {
                best[c.id] = c
            }
        }
        
        var mergedCandidates = Array(best.values)
#if DEBUG
        msLog("[MemoryStore] retrieve candidates postDedupe=\(mergedCandidates.count)")
#endif
        
        // Drop deprecated memories so injected test identifiers don’t keep surfacing forever.
        // This is best-effort and will behave as a no-op on older DBs that don't have `status`.
        mergedCandidates = (try? filterOutDeprecatedCandidates(mergedCandidates)) ?? mergedCandidates

        // Phase 4: vector rerank
        do {
            try ensurePhase45TablesIfNeeded()
            let out = try vectorRerankCandidates(query: q0, candidates: mergedCandidates, maxScan: 200)
            mergedCandidates = out.candidates
        } catch {
            // ignore
        }
        
        let out = mergedCandidates
            .sorted { $0.score > $1.score }
            .prefix(max(1, limit))
            .map { $0.item }
#if DEBUG
        msLog("[MemoryStore] retrieve results=\(out.count)")
#endif
        return out
    }
    
    /// Turn arbitrary user text into a safer FTS5 query.
    /// Cleanup goals:
    /// - Drop common question filler words ("what", "is", "my", etc.) so we don't generate queries like: what* AND is* AND my*
    /// - Keep only meaningful tokens and cap the number of terms.
    private func ftsQueryFromUserText(_ text: String) -> String {
        let lowered = text.lowercased()
        // Tokenize by non-alphanumerics (more robust than whitespace-only).
        let rawTokens = lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        
        // Common stopwords that add noise and often kill recall.
        let stop: Set<String> = [
            "a","an","the","and","or","to","of","in","on","at","for","from","with",
            "i","me","my","mine","we","our","you","your","yours","it","this","that","these","those",
            "what","whats","what's","is","are","was","were","be","been","being",
            "who","whom","whose","why","how","when","where",
            "tell","show","explain","please","pls","kindly","exactly",
            "remember","note","save","mind",
            "do","does","did","can","could","would","should","will","shall"
        ]
        
        var terms: [String] = []
        terms.reserveCapacity(8)
        var seen = Set<String>()
        
        for tok in rawTokens {
            // Require >= 3 chars so we keep “scopekey” but drop “is”, “my”, etc.
            guard tok.count >= 3 else { continue }
            guard !stop.contains(tok) else { continue }
            if seen.insert(tok).inserted {
                terms.append("\(tok)*")
                if terms.count >= 8 { break }
            }
        }
        
        return terms.joined(separator: " AND ")
    }
    
    // MARK: - Phase 3 (Formatter for prompt injection)
    
    /// Formats a compact, structured, read-only memory block for prompt injection.
    /// Intentionally tiny for iOS: keep it factual; do not let it steer tone.
    public func formatForInjection(_ pack: MemoryContextPack, maxChars: Int = 900) -> String {
        var lines: [String] = []
        lines.reserveCapacity(32)
        
        // If nothing to inject, return empty string.
        if pack.facts.isEmpty && pack.events.isEmpty && pack.procedures.isEmpty {
            return ""
        }
        lines.append("### MEM (read-only)")
        lines.append("Use if relevant; don’t quote; don’t change tone.")
        
        func appendSection(_ tag: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            for (i, raw) in items.enumerated() {
                // Keep each item line short and single-line.
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let oneLine = trimmed.replacingOccurrences(of: "\n", with: " ")
                let clipped = oneLine.count > 160 ? String(oneLine.prefix(160)) + "…" : oneLine
                lines.append("\(tag)\(i+1): \(clipped)")
            }
        }
        
        appendSection("F", pack.facts)
        appendSection("E", pack.events)
        appendSection("P", pack.procedures)
        
        // Enforce maxChars by truncating the whole block safely.
        var block = lines.joined(separator: "\n")
        if block.count > maxChars {
            block = String(block.prefix(maxChars)) + "\n…"
        }
        return block
    }
    
    /// Convenience: retrieve + format in one call.
    public func buildInjectionBlock(query: String, maxItems: Int = 10, maxChars: Int = 900) throws -> String {
        let q0 = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q0.lowercased()
        // Skip memory injection for very short or low-signal inputs to keep prefill small.
        if q0.count < 10 {
            let hasDigits = lower.rangeOfCharacter(from: .decimalDigits) != nil
            let isQuestion = lower.contains("?")
            let cue = containsMemoryCue(lower) || containsExplicitRememberCue(lower) || containsCorrectionCue(lower)
            if !(hasDigits || isQuestion || cue) {
                return ""
            }
        }
        let pack = try buildContextPack(query: query, maxItems: maxItems, includeDebug: false)
        var block = formatForInjection(pack, maxChars: maxChars)

        // Phase 6: prepend a stable, compact “mind palace index” line if available.
        if let blurb = getMemoryMapBlurb() {
            let line = "### MAP\n\(blurb)\n"
            if !block.isEmpty {
                block = line + "\n" + block
            } else {
                block = line
            }

            // Enforce maxChars across both sections.
            if block.count > maxChars {
                block = String(block.prefix(maxChars)) + "\n…"
            }
        }

        return block
    }

    // MARK: - Phase 6 (Memory Map)

    private let memoryMapBlurbKey = "memory_map_blurb"
    private var didEnsurePhase6Tables = false

    private func ensurePhase6TablesIfNeeded() throws {
        if didEnsurePhase6Tables { return }
        try exec("""
        CREATE TABLE IF NOT EXISTS mem_kv (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """)
        didEnsurePhase6Tables = true
    }

    private func fetchKV(_ key: String) throws -> (value: String, updatedAt: Int64)? {
        try ensurePhase6TablesIfNeeded()
        let stmt = try db.prepare("SELECT value, updated_at FROM mem_kv WHERE key = ? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindText(stmt, 1, key)
        if sqlite3_step(stmt) == SQLITE_ROW {
            let v = MemoryDB.colText(stmt, 0)
            let ts = MemoryDB.colInt(stmt, 1)
            return (v, ts)
        }
        return nil
    }

    private func upsertKV(_ key: String, value: String, updatedAt: Int64) throws {
        try ensurePhase6TablesIfNeeded()
        let stmt = try db.prepare("""
        INSERT INTO mem_kv(key, value, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = excluded.updated_at;
        """)
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindText(stmt, 1, key)
        MemoryDB.bindText(stmt, 2, value)
        MemoryDB.bindInt(stmt, 3, updatedAt)
        try db.stepDone(stmt)
    }

    /// Generate / refresh the Memory Map (topics + blurb).
    /// - Parameters:
    ///   - isCharging: caller-supplied power gate (true on macOS; on iOS pass batteryState == .charging/.full).
    ///   - allowOnBattery: if true, allows running even when not charging (useful for manual dev testing).
    ///   - cadenceHours: only rebuild if older than this many hours (unless `force=true`).
    ///   - force: rebuild even if within cadence.
    public func runMemoryMapIfEligible(
        isCharging: Bool,
        allowOnBattery: Bool = false,
        cadenceHours: Double = 24.0,
        force: Bool = false
    ) async {
        do {
            try ensurePhase45TablesIfNeeded()
            try ensurePhase6TablesIfNeeded()

            let nowTs = Int64(now().timeIntervalSince1970)

            if !force {
                if let kv = try fetchKV(memoryMapBlurbKey) {
                    let age = Double(max(0, nowTs - kv.updatedAt))
                    if age < cadenceHours * 3600.0 {
                        return
                    }
                }
            }

            if !(isCharging || allowOnBattery) {
                return
            }

            // Build topic graph from embeddings (bounded for iOS).
            try buildTopicsFromEmbeddings(maxMemories: 200)

            // Generate and persist a compact blurb.
            let blurb = try generateMemoryMapBlurb(maxTopics: 4)
            if !blurb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try upsertKV(memoryMapBlurbKey, value: blurb, updatedAt: nowTs)
            }
        } catch {
#if DEBUG
            msLog("[MemoryStore] runMemoryMapIfEligible failed: \(error)")
#endif
        }
    }

    /// Fetch the stored memory map blurb (if any).
    public func getMemoryMapBlurb() -> String? {
        do {
            if let kv = try fetchKV(memoryMapBlurbKey) {
                let v = kv.value.trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Phase 6 internals (topic clustering)

    private func buildTopicsFromEmbeddings(maxMemories: Int) throws {
        // 1) Choose a bounded set of candidate memories.
        let recent = try listRecent(limit: max(20, maxMemories))
        var items: [MemoryItem] = []
        items.reserveCapacity(recent.count)
        for it in recent {
            if it.type == .semantic || it.type == .episodic || it.type == .procedural {
                items.append(it)
            }
        }
        if items.count < 8 { return }

        // 2) Load embeddings.
        let ids = items.map { $0.id }
        let embs = try loadEmbeddings(memIds: ids)
        if embs.count < 8 { return }

        // 3) Build vectors + align items.
        var byId: [String: MemoryItem] = [:]
        byId.reserveCapacity(items.count)
        for it in items { byId[it.id] = it }

        var vecs: [(id: String, item: MemoryItem, v: [Float])] = []
        vecs.reserveCapacity(embs.count)

        for (mid, e) in embs {
            guard let it = byId[mid], e.dim == targetEmbeddingDim else { continue }
            let v0 = dequantizeInt8(e.qbytes, scale: e.scale, dim: e.dim)
            vecs.append((id: mid, item: it, v: normalize(v0)))
        }
        if vecs.count < 8 { return }

        // 4) Pick K based on N (small + stable).
        let n = vecs.count
        let k = max(3, min(8, Int(round(sqrt(Double(n)) / 1.2))))

        // 5) Precompute a non-actor score for stable seeding/sorting.
        // Avoid calling `score(...)` inside `sorted {}` to satisfy Swift 6 concurrency checks.
        let nowTs = now().timeIntervalSince1970
        func topicSeedScore(_ item: MemoryItem, nowTs: Double) -> Double {
            let ageSec = max(0.0, nowTs - item.lastAccessed.timeIntervalSince1970)
            let recency = exp(-ageSec / (7.0 * 24.0 * 3600.0))
            var s = 0.0
            s += 0.40 * clamp01(item.importance)
            s += 0.25 * clamp01(item.salience)
            s += 0.20 * clamp01(recency)
            if item.pinned { s += 0.15 }
            return s
        }

        let seedScores: [Double] = vecs.map { topicSeedScore($0.item, nowTs: nowTs) }

        // Initialize centroids from top-scoring memories.
        let seededIdx = Array(0..<vecs.count).sorted { seedScores[$0] > seedScores[$1] }
        var centroids: [[Float]] = []
        centroids.reserveCapacity(k)
        for i in 0..<k {
            centroids.append(vecs[seededIdx[i % seededIdx.count]].v)
        }

        // 6) Run a few k-means iterations.
        var assign = Array(repeating: 0, count: n)
        for _ in 0..<6 {
            // assign
            for i in 0..<n {
                var bestJ = 0
                var best = -Double.infinity
                for j in 0..<k {
                    let sim = cosineSimFloat(vecs[i].v, centroids[j])
                    if sim > best {
                        best = sim
                        bestJ = j
                    }
                }
                assign[i] = bestJ
            }

            // recompute
            var sums = Array(repeating: Array(repeating: Float(0), count: targetEmbeddingDim), count: k)
            var counts = Array(repeating: 0, count: k)
            for i in 0..<n {
                let j = assign[i]
                addInPlace(&sums[j], vecs[i].v)
                counts[j] += 1
            }
            for j in 0..<k {
                if counts[j] == 0 { continue }
                scaleInPlace(&sums[j], 1.0 / Float(counts[j]))
                centroids[j] = normalize(sums[j])
            }
        }

        // 7) Build clusters.
        var clusters: [[Int]] = Array(repeating: [], count: k)
        for i in 0..<n { clusters[assign[i]].append(i) }

        // Drop tiny clusters.
        clusters = clusters.filter { $0.count >= 3 }
        if clusters.isEmpty { return }

        // 8) Upsert topic nodes + edges.
        let ts = Int64(now().timeIntervalSince1970)

        // Ensure memory nodes exist before creating edges.
        // `graph_edges` may enforce FK(src/dst)->graph_nodes(id), so "mem:<uuid>" must be present.
        for entry in vecs {
            let memNodeId = "mem:\(entry.id)"
            let t = entry.item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = t.isEmpty ? "Memory" : t
            let b = entry.item.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = b.count > 220 ? String(b.prefix(220)) + "…" : b
            try upsertGraphNode(
                id: memNodeId,
                type: "memory",
                title: title,
                summary: summary,
                salience: clamp01(entry.item.salience),
                updatedAt: ts
            )
        }

        var topicIds: [String] = []
        topicIds.reserveCapacity(clusters.count)

        for idxs in clusters {
            // Stable-ish topic ids: hash of top member ids.
            let topMembers = idxs
                .sorted { seedScores[$0] > seedScores[$1] }
                .prefix(12)
                .map { vecs[$0].id }
                .joined(separator: ",")

            let tid = "topic:" + String(sha256Hex(topMembers).prefix(12))
            topicIds.append(tid)

            // Title keywords from the cluster’s text.
            var titleText = ""
            for i in idxs.prefix(20) {
                titleText += vecs[i].item.title
                titleText += " "
                titleText += vecs[i].item.body
                titleText += "\n"
            }

            let kws = extractEntities(from: titleText)
            let shortTitle = kws.prefix(3).joined(separator: " · ")
            let topicTitle = shortTitle.isEmpty ? "Topic" : shortTitle

            let summary = buildTopicSummary(idxs: idxs, vecs: vecs, seedScores: seedScores, maxLen: 220)

            try upsertGraphNode(id: tid, type: "topic", title: topicTitle, summary: summary, salience: 0.30, updatedAt: ts)

            // mem -> topic and topic -> mem edges
            let centroid = centroidForCluster(idxs: idxs, vecs: vecs)
            for i in idxs {
                let mid = vecs[i].id
                let memNode = "mem:\(mid)"
                let sim = cosineSimFloat(vecs[i].v, centroid)
                let w = clamp01(0.5 * (sim + 1.0))
                try upsertGraphEdge(src: memNode, dst: tid, rel: "in_topic", weight: w, updatedAt: ts)
                try upsertGraphEdge(src: tid, dst: memNode, rel: "has_mem", weight: w, updatedAt: ts)
            }
        }

        // 9) Topic-to-topic similarity edges.
        var topicCentroids: [[Float]] = []
        topicCentroids.reserveCapacity(clusters.count)
        for idxs in clusters {
            topicCentroids.append(centroidForCluster(idxs: idxs, vecs: vecs))
        }

        for a in 0..<clusters.count {
            for b in (a+1)..<clusters.count {
                let sim = cosineSimFloat(topicCentroids[a], topicCentroids[b])
                let sim01 = 0.5 * (sim + 1.0)
                if sim01 >= 0.78 {
                    try upsertGraphEdge(src: topicIds[a], dst: topicIds[b], rel: "topic_sim", weight: sim01, updatedAt: ts)
                    try upsertGraphEdge(src: topicIds[b], dst: topicIds[a], rel: "topic_sim", weight: sim01, updatedAt: ts)
                }
            }
        }
    }

    private func buildTopicSummary(
        idxs: [Int],
        vecs: [(id: String, item: MemoryItem, v: [Float])],
        seedScores: [Double],
        maxLen: Int
    ) -> String {
        let titles = idxs
            .sorted { seedScores[$0] > seedScores[$1] }
            .prefix(3)
            .map { vecs[$0].item.title.isEmpty ? "(untitled)" : vecs[$0].item.title }

        let s = titles.joined(separator: " • ")
        if s.count > maxLen { return String(s.prefix(maxLen)) + "…" }
        return s
    }

    private func centroidForCluster(
        idxs: [Int],
        vecs: [(id: String, item: MemoryItem, v: [Float])]
    ) -> [Float] {
        var sum = Array(repeating: Float(0), count: targetEmbeddingDim)
        if idxs.isEmpty { return sum }
        for i in idxs { addInPlace(&sum, vecs[i].v) }
        scaleInPlace(&sum, 1.0 / Float(idxs.count))
        return normalize(sum)
    }

    private func generateMemoryMapBlurb(maxTopics: Int) throws -> String {
        let stmt = try db.prepare("""
        SELECT id, title
        FROM graph_nodes
        WHERE type = 'topic'
        ORDER BY updated_at DESC
        LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindInt(stmt, 1, Int64(max(1, maxTopics)))

        var titles: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let t = MemoryDB.colText(stmt, 1).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { titles.append(t) }
        }

        if titles.isEmpty { return "" }
        let joined = titles.prefix(maxTopics).joined(separator: "; ")
        return "Current themes: \(joined)."
    }

    private func upsertGraphNode(
        id: String,
        type: String,
        title: String,
        summary: String,
        salience: Double,
        updatedAt: Int64
    ) throws {
        let stmt = try db.prepare("""
        INSERT INTO graph_nodes(id, type, title, summary, salience, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            type = excluded.type,
            title = excluded.title,
            summary = excluded.summary,
            salience = excluded.salience,
            updated_at = excluded.updated_at;
        """)
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindText(stmt, 1, id)
        MemoryDB.bindText(stmt, 2, type)
        MemoryDB.bindText(stmt, 3, title)
        MemoryDB.bindText(stmt, 4, summary)
        MemoryDB.bindDouble(stmt, 5, salience)
        MemoryDB.bindInt(stmt, 6, updatedAt)
        try db.stepDone(stmt)
    }

    private func upsertGraphEdge(
        src: String,
        dst: String,
        rel: String,
        weight: Double,
        updatedAt: Int64
    ) throws {
        let stmt = try db.prepare("""
        INSERT INTO graph_edges(src, dst, rel, weight, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(src, dst, rel) DO UPDATE SET
            weight = excluded.weight,
            updated_at = excluded.updated_at;
        """)
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindText(stmt, 1, src)
        MemoryDB.bindText(stmt, 2, dst)
        MemoryDB.bindText(stmt, 3, rel)
        MemoryDB.bindDouble(stmt, 4, weight)
        MemoryDB.bindInt(stmt, 5, updatedAt)
        try db.stepDone(stmt)
    }

    private func dequantizeInt8(_ qbytes: Data, scale: Float, dim: Int) -> [Float] {
        if dim <= 0 || qbytes.count < dim { return Array(repeating: 0, count: max(0, dim)) }
        var out = Array(repeating: Float(0), count: dim)
        qbytes.withUnsafeBytes { rb in
            let ptr = rb.baseAddress!.assumingMemoryBound(to: Int8.self)
            for i in 0..<dim {
                out[i] = Float(ptr[i]) * scale
            }
        }
        return out
    }

    private func cosineSimFloat(_ a: [Float], _ b: [Float]) -> Double {
        if a.count != b.count || a.isEmpty { return 0 }
        var dot: Double = 0
        var na: Double = 0
        var nb: Double = 0
        for i in 0..<a.count {
            let x = Double(a[i])
            let y = Double(b[i])
            dot += x * y
            na += x * x
            nb += y * y
        }
        let denom = sqrt(max(1e-9, na)) * sqrt(max(1e-9, nb))
        return denom > 0 ? (dot / denom) : 0
    }

    private func addInPlace(_ acc: inout [Float], _ v: [Float]) {
        if acc.count != v.count { return }
        for i in 0..<acc.count { acc[i] += v[i] }
    }

    private func scaleInPlace(_ acc: inout [Float], _ s: Float) {
        for i in 0..<acc.count { acc[i] *= s }
    }
    
    // MARK: - Phase 4/5 (Embeddings + Graph) helpers
    
    private func exec(_ sql: String) throws {
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try db.stepDone(stmt)
    }
    
    private func ensurePhase45TablesIfNeeded() throws {
        if didEnsurePhase45Tables { return }
        
        // Embeddings
        try exec("""
        CREATE TABLE IF NOT EXISTS mem_embeddings (
            mem_id TEXT PRIMARY KEY,
            dim INTEGER NOT NULL,
            qbytes BLOB NOT NULL,
            scale REAL NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """)
        
        // Graph (Neo4j-lite)
        try exec("""
        CREATE TABLE IF NOT EXISTS graph_nodes (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            salience REAL NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """)
        
        try exec("""
        CREATE TABLE IF NOT EXISTS graph_edges (
            src TEXT NOT NULL,
            dst TEXT NOT NULL,
            rel TEXT NOT NULL,
            weight REAL NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """)
        
        try exec("""
        CREATE TABLE IF NOT EXISTS graph_node_tags (
            node TEXT NOT NULL,
            tag TEXT NOT NULL
        );
        """)
        
        // Memory↔Entity join
        try exec("""
        CREATE TABLE IF NOT EXISTS mem_entities (
            mem_id TEXT NOT NULL,
            entity TEXT NOT NULL,
            weight REAL NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """)
        
        // Indexes
        try exec("CREATE INDEX IF NOT EXISTS idx_graph_edges_src ON graph_edges(src);")
        try exec("CREATE INDEX IF NOT EXISTS idx_graph_edges_dst ON graph_edges(dst);")
        try exec("CREATE INDEX IF NOT EXISTS idx_graph_tags_tag ON graph_node_tags(tag);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_entities_entity ON mem_entities(entity);")
        try exec("CREATE INDEX IF NOT EXISTS idx_mem_entities_mem_id ON mem_entities(mem_id);")
        
        // Uniqueness guards (avoid duplicate spam on repeated indexing)
        try exec("CREATE UNIQUE INDEX IF NOT EXISTS uidx_graph_edges_triplet ON graph_edges(src, dst, rel);")
        try exec("CREATE UNIQUE INDEX IF NOT EXISTS uidx_graph_node_tags_pair ON graph_node_tags(node, tag);")
        try exec("CREATE UNIQUE INDEX IF NOT EXISTS uidx_mem_entities_pair ON mem_entities(mem_id, entity);")
        
        didEnsurePhase45Tables = true
    }
    
    // MARK: Embeddings (Phase 4)
    
    private func upsertEmbeddingForMemoryIfEligible(
        id: String,
        type: MemoryItemType,
        title: String,
        body: String,
        force: Bool = false
    ) throws {
        // Phase 4: allow embeddings for all memory types used in retrieval.
        // If you only store procedural items, warmup would otherwise print embedded=0.
        guard type == .semantic || type == .episodic || type == .procedural else { return }
        
        // If we already have an embedding and we're not forcing a refresh, skip work.
        if !force, (try hasEmbedding(memId: id)) {
            return
        }
        
        let text = (title + "\n" + body).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        let raw: [Float]
        if let p = embeddingProvider {
            if let v = p.embed(text), !v.isEmpty {
                raw = v
#if DEBUG
                msLog("[MemoryStore] embed(mem) USED_PROVIDER provider=\(String(describing: Swift.type(of: p))) memId=\(id) textChars=\(text.count) vecDim=\(v.count)")
#endif
            } else {
                raw = hashedEmbedding(text: text, dim: targetEmbeddingDim)
#if DEBUG
                msLog("[MemoryStore] embed(mem) PROVIDER_RETURNED_NIL_OR_EMPTY provider=\(String(describing: Swift.type(of: p))) memId=\(id) textChars=\(text.count) -> hashed")
#endif
            }
        } else {
            // iOS-safe fallback (no extra model run)
            raw = hashedEmbedding(text: text, dim: targetEmbeddingDim)
#if DEBUG
            msLog("[MemoryStore] embed(mem) NO_PROVIDER memId=\(id) textChars=\(text.count) -> hashed")
#endif
        }
        
        // Ensure stable dim, then normalize.
        let shaped = adaptEmbeddingDim(raw, to: targetEmbeddingDim)
        let vec = normalize(shaped)
        
        let q = quantizeInt8(vec)
        try upsertEmbedding(memId: id, dim: targetEmbeddingDim, qbytes: q.qbytes, scale: q.scale)
    }
    
    private func upsertEmbedding(memId: String, dim: Int, qbytes: Data, scale: Float) throws {
        let ts = Int64(now().timeIntervalSince1970)
        let stmt = try db.prepare("""
        INSERT INTO mem_embeddings(mem_id, dim, qbytes, scale, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(mem_id) DO UPDATE SET
            dim = excluded.dim,
            qbytes = excluded.qbytes,
            scale = excluded.scale,
            updated_at = excluded.updated_at;
        """)
        defer { sqlite3_finalize(stmt) }
        
        MemoryDB.bindText(stmt, 1, memId)
        MemoryDB.bindInt(stmt, 2, Int64(dim))
        bindBlob(stmt, 3, qbytes)
        MemoryDB.bindDouble(stmt, 4, Double(scale))
        MemoryDB.bindInt(stmt, 5, ts)
        
        try db.stepDone(stmt)
    }
    
    private func hasEmbedding(memId: String) throws -> Bool {
        let stmt = try db.prepare("SELECT 1 FROM mem_embeddings WHERE mem_id = ? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindText(stmt, 1, memId)
        return sqlite3_step(stmt) == SQLITE_ROW
    }
    
    /// Adapts an embedding vector to a fixed target dimension.
    /// - If input is longer: folds values into `target` buckets (preserves more info than truncation).
    /// - If input is shorter: pads with zeros.
    private func adaptEmbeddingDim(_ vec: [Float], to target: Int) -> [Float] {
        guard target > 0 else { return [] }
        if vec.count == target { return vec }
        if vec.count < target {
            return vec + Array(repeating: 0, count: target - vec.count)
        }
        
        var out = Array(repeating: Float(0), count: target)
        for (i, v) in vec.enumerated() {
            out[i % target] += v
        }
        return out
    }
    
    private func loadEmbeddings(memIds: [String]) throws -> [String: (dim: Int, qbytes: Data, scale: Float)] {
        guard !memIds.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: memIds.count).joined(separator: ",")
        let stmt = try db.prepare("""
        SELECT mem_id, dim, qbytes, scale
        FROM mem_embeddings
        WHERE mem_id IN (\(placeholders));
        """)
        defer { sqlite3_finalize(stmt) }
        
        for (i, id) in memIds.enumerated() {
            MemoryDB.bindText(stmt, Int32(i + 1), id)
        }
        
        var out: [String: (dim: Int, qbytes: Data, scale: Float)] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let mid = MemoryDB.colText(stmt, 0)
            let dim = Int(MemoryDB.colInt(stmt, 1))
            let blob = colBlob(stmt, 2)
            let scale = Float(MemoryDB.colDouble(stmt, 3))
            out[mid] = (dim: dim, qbytes: blob, scale: scale)
        }
        return out
    }
    
    private func vectorRerankCandidates(query: String, candidates: [MemoryCandidate], maxScan: Int) throws -> (candidates: [MemoryCandidate], applied: Bool) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return (candidates, false) }
        
        let raw: [Float]
        if let p = embeddingProvider {
            if let v = p.embed(q), !v.isEmpty {
                raw = v
#if DEBUG
                msLog("[MemoryStore] embed(query) USED_PROVIDER provider=\(String(describing: Swift.type(of: p))) queryChars=\(q.count) vecDim=\(v.count)")
#endif
            } else {
                raw = hashedEmbedding(text: q, dim: targetEmbeddingDim)
#if DEBUG
                msLog("[MemoryStore] embed(query) PROVIDER_RETURNED_NIL_OR_EMPTY provider=\(String(describing: Swift.type(of: p))) queryChars=\(q.count) -> hashed")
#endif
            }
        } else {
            raw = hashedEmbedding(text: q, dim: targetEmbeddingDim)
#if DEBUG
            msLog("[MemoryStore] embed(query) NO_PROVIDER queryChars=\(q.count) -> hashed")
#endif
        }
        
        let qVec = normalize(adaptEmbeddingDim(raw, to: targetEmbeddingDim))
        let dim = targetEmbeddingDim
        let qQ = quantizeInt8(qVec)
        
        let scan = candidates.sorted { $0.score > $1.score }.prefix(max(1, min(maxScan, candidates.count)))
        let scanIds = scan.map { $0.id }
        
#if DEBUG
        let embs = try loadEmbeddings(memIds: scanIds)
        msLog("[MemoryStore] vectorRerank scan=\(scanIds.count) loadedEmbeddings=\(embs.count)")
#else
        let embs = try loadEmbeddings(memIds: scanIds)
#endif
        if embs.isEmpty { return (candidates, false) }
        
        let alpha = 0.22 // modest boost
        
        var boosted = candidates
        var appliedAny = false
        
        for i in boosted.indices {
            let id = boosted[i].id
            guard let e = embs[id], e.dim == dim else { continue }
            
            let cos = cosineSimInt8(q: qQ.qbytes, v: e.qbytes, dim: dim)
            let sim01 = 0.5 * (cos + 1.0)
            boosted[i] = MemoryCandidate(item: boosted[i].item, ftsRankRaw: boosted[i].ftsRankRaw, score: boosted[i].score + alpha * sim01)
            appliedAny = true
        }
        
        return (boosted, appliedAny)
    }
    
    
    private func normalize(_ vec: [Float]) -> [Float] {
        if vec.isEmpty { return vec }
        var norm: Float = 0
        for v in vec { norm += v * v }
        norm = sqrt(max(1e-8, norm))
        return vec.map { $0 / norm }
    }
    
    // Deterministic hashed embedding (iOS-safe). Swap later with real embedder (CoreML/ONNX/llama embeddings).
    private func hashedEmbedding(text: String, dim: Int) -> [Float] {
        let tokens = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0) }
            .filter { $0.count >= 2 }
        
        if tokens.isEmpty {
            return Array(repeating: 0, count: dim)
        }
        
        var vec = Array(repeating: Float(0), count: dim)
        
        for t in tokens.prefix(64) {
            let digest = SHA256.hash(data: Data(t.utf8))
            let bytes = Array(digest)
            var x: UInt64 = 0
            for i in 0..<8 {
                x = (x << 8) | UInt64(bytes[i])
            }
            let idx = Int(x % UInt64(dim))
            let sign: Float = ((x >> 63) & 1) == 0 ? 1.0 : -1.0
            vec[idx] += sign
        }
        
        var norm: Float = 0
        for v in vec { norm += v * v }
        norm = sqrt(max(1e-8, norm))
        for i in vec.indices { vec[i] /= norm }
        return vec
    }
    
    private func quantizeInt8(_ vec: [Float]) -> (qbytes: Data, scale: Float) {
        var maxAbs: Float = 0
        for v in vec { maxAbs = max(maxAbs, abs(v)) }
        let scale: Float = maxAbs > 0 ? (maxAbs / 127.0) : 1.0
        
        var bytes = Data(count: vec.count)
        bytes.withUnsafeMutableBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: Int8.self) else { return }
            for i in 0..<vec.count {
                let q = vec[i] / scale
                let clamped = max(-127.0, min(127.0, q))
                ptr[i] = Int8(clamped.rounded())
            }
        }
        
        return (qbytes: bytes, scale: scale)
    }
    
    private func cosineSimInt8(q: Data, v: Data, dim: Int) -> Double {
        guard q.count >= dim, v.count >= dim else { return 0 }
        
        var dot: Double = 0
        var nq: Double = 0
        var nv: Double = 0
        
        q.withUnsafeBytes { qb in
            v.withUnsafeBytes { vb in
                let qptr = qb.baseAddress!.assumingMemoryBound(to: Int8.self)
                let vptr = vb.baseAddress!.assumingMemoryBound(to: Int8.self)
                for i in 0..<dim {
                    let qi = Double(qptr[i])
                    let vi = Double(vptr[i])
                    dot += qi * vi
                    nq += qi * qi
                    nv += vi * vi
                }
            }
        }
        
        let denom = sqrt(max(1e-9, nq)) * sqrt(max(1e-9, nv))
        return denom > 0 ? (dot / denom) : 0
    }
    
    private func bindBlob(_ stmt: OpaquePointer?, _ index: Int32, _ data: Data) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        // `withUnsafeBytes` returns a value; make it explicit so the compiler doesn't warn.
        // SQLite expects a NULL pointer when byte-count is 0.
        let _: Int32 = data.withUnsafeBytes { raw in
            let base = (data.count > 0) ? raw.baseAddress : nil
            return sqlite3_bind_blob(stmt, index, base, Int32(data.count), SQLITE_TRANSIENT)
        }
    }
    
    private func colBlob(_ stmt: OpaquePointer?, _ index: Int32) -> Data {
        guard let ptr = sqlite3_column_blob(stmt, Int32(index)) else { return Data() }
        let n = Int(sqlite3_column_bytes(stmt, Int32(index)))
        if n <= 0 { return Data() }
        return Data(bytes: ptr, count: n)
    }
    
    // MARK: Graph memory (Phase 5)

    private func normalizeEntityKey(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return folded.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    /// Phase 5: Minimal 1-hop expansion using `graph_edges`.
    /// Query entities -> ent:<key> nodes -> edges to mem:<id> nodes -> return boosted candidates.
    private func graphOneHopCandidatesViaEdges(query: String, limit: Int) throws -> [MemoryCandidate] {
        let ents = extractEntities(from: query)
        guard !ents.isEmpty else { return [] }
        
        // Build entity node ids.
        let nodeIds = ents.map { "ent:\(normalizeEntityKey($0))" }
        let placeholders = Array(repeating: "?", count: nodeIds.count).joined(separator: ",")
        
        // Map ent nodes -> mem nodes (1 hop). We store both directions, but this targets ent -> mem.
        // mem node id format: "mem:<uuid>". We strip the prefix to fetch mem_items.
        let stmt = try db.prepare("""
        SELECT substr(e.dst, 5) AS mem_id, MAX(e.weight) AS w
        FROM graph_edges e
        WHERE e.src IN (\(placeholders))
          AND e.dst LIKE 'mem:%'
        GROUP BY mem_id
        ORDER BY w DESC
        LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        
        for (i, nid) in nodeIds.enumerated() {
            MemoryDB.bindText(stmt, Int32(i + 1), nid)
        }
        MemoryDB.bindInt(stmt, Int32(nodeIds.count + 1), Int64(max(1, limit)))
        
        var scored: [(String, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let memId = MemoryDB.colText(stmt, 0)
            let w = MemoryDB.colDouble(stmt, 1)
            if !memId.isEmpty {
                scored.append((memId, w))
            }
        }
        
        guard !scored.isEmpty else { return [] }
        
        let items = try fetchItemsByIds(scored.map { $0.0 })
        var byId: [String: MemoryItem] = [:]
        for it in items { byId[it.id] = it }
        
        var out: [MemoryCandidate] = []
        out.reserveCapacity(items.count)
        
        for (mid, w) in scored {
            guard let item = byId[mid] else { continue }
            let base = score(item: item, ftsScore: nil)
            // Small, stable boost so graph recall feels “alive” but doesn’t dominate.
            let boosted = base + 0.20 + 0.12 * clamp01(w)
            out.append(MemoryCandidate(item: item, ftsRankRaw: nil, score: boosted))
        }
        
        return out
    }
    
    private func indexGraphForMemory(id: String, type: MemoryItemType, title: String, body: String) throws {
        let ts = Int64(now().timeIntervalSince1970)
        
        // Upsert memory node
        let memNodeId = "mem:\(id)"
        do {
            let stmt = try db.prepare("""
            INSERT INTO graph_nodes(id, type, title, summary, salience, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                summary = excluded.summary,
                salience = excluded.salience,
                updated_at = excluded.updated_at;
            """)
            defer { sqlite3_finalize(stmt) }
            
            let summary = (title + ": " + body).trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = summary.count > 220 ? String(summary.prefix(220)) + "…" : summary
            
            MemoryDB.bindText(stmt, 1, memNodeId)
            MemoryDB.bindText(stmt, 2, "memory")
            MemoryDB.bindText(stmt, 3, title.isEmpty ? id : title)
            MemoryDB.bindText(stmt, 4, clipped)
            MemoryDB.bindDouble(stmt, 5, 0.35)
            MemoryDB.bindInt(stmt, 6, ts)
            try db.stepDone(stmt)
        }
        
        // Entities
        let entities = extractEntities(from: title + "\n" + body)
        if entities.isEmpty { return }
        
        for e in entities {
            let entKey = normalizeEntityKey(e)
            let entNodeId = "ent:\(entKey)"
            
            // Upsert entity node
            do {
                let stmt = try db.prepare("""
                INSERT INTO graph_nodes(id, type, title, summary, salience, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    updated_at = excluded.updated_at;
                """)
                defer { sqlite3_finalize(stmt) }
                
                MemoryDB.bindText(stmt, 1, entNodeId)
                MemoryDB.bindText(stmt, 2, "entity")
                MemoryDB.bindText(stmt, 3, e)
                MemoryDB.bindText(stmt, 4, "")
                MemoryDB.bindDouble(stmt, 5, 0.25)
                MemoryDB.bindInt(stmt, 6, ts)
                try db.stepDone(stmt)
            }
            
            // Tag
            do {
                let stmt = try db.prepare("INSERT OR IGNORE INTO graph_node_tags(node, tag) VALUES (?, ?);")
                defer { sqlite3_finalize(stmt) }
                MemoryDB.bindText(stmt, 1, entNodeId)
                MemoryDB.bindText(stmt, 2, entKey)
                try db.stepDone(stmt)
            }
            
            // Edges (both directions)
            do {
                let stmt = try db.prepare("INSERT OR IGNORE INTO graph_edges(src, dst, rel, weight, updated_at) VALUES (?, ?, ?, ?, ?);")
                defer { sqlite3_finalize(stmt) }
                MemoryDB.bindText(stmt, 1, memNodeId)
                MemoryDB.bindText(stmt, 2, entNodeId)
                MemoryDB.bindText(stmt, 3, "mentions")
                MemoryDB.bindDouble(stmt, 4, 0.65)
                MemoryDB.bindInt(stmt, 5, ts)
                try db.stepDone(stmt)
            }
            do {
                let stmt = try db.prepare("INSERT OR IGNORE INTO graph_edges(src, dst, rel, weight, updated_at) VALUES (?, ?, ?, ?, ?);")
                defer { sqlite3_finalize(stmt) }
                MemoryDB.bindText(stmt, 1, entNodeId)
                MemoryDB.bindText(stmt, 2, memNodeId)
                MemoryDB.bindText(stmt, 3, "appears_in")
                MemoryDB.bindDouble(stmt, 4, 0.65)
                MemoryDB.bindInt(stmt, 5, ts)
                try db.stepDone(stmt)
            }
            
            // mem_entities join row
            do {
                let stmt = try db.prepare("""
                INSERT INTO mem_entities(mem_id, entity, weight, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(mem_id, entity) DO UPDATE SET
                    weight = MAX(weight, excluded.weight),
                    updated_at = excluded.updated_at;
                """)
                defer { sqlite3_finalize(stmt) }
                MemoryDB.bindText(stmt, 1, id)
                MemoryDB.bindText(stmt, 2, entKey)
                MemoryDB.bindDouble(stmt, 3, 0.60)
                MemoryDB.bindInt(stmt, 4, ts)
                try db.stepDone(stmt)
            }
        }
    }
    
    private func graphExpandCandidates(query: String, limit: Int) throws -> [MemoryCandidate] {
        let ents = extractEntities(from: query)
        guard !ents.isEmpty else { return [] }
        
        let placeholders = Array(repeating: "?", count: ents.count).joined(separator: ",")
        let stmt = try db.prepare("""
        SELECT mem_id, MAX(weight) as w
        FROM mem_entities
        WHERE entity IN (\(placeholders))
        GROUP BY mem_id
        ORDER BY w DESC
        LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        
        for (i, e) in ents.enumerated() {
            MemoryDB.bindText(stmt, Int32(i + 1), normalizeEntityKey(e))
        }
        MemoryDB.bindInt(stmt, Int32(ents.count + 1), Int64(max(1, limit)))
        
        var ids: [(String, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.append((MemoryDB.colText(stmt, 0), MemoryDB.colDouble(stmt, 1)))
        }
        if ids.isEmpty { return [] }
        
        let items = try fetchItemsByIds(ids.map { $0.0 })
        var byId: [String: MemoryItem] = [:]
        for it in items { byId[it.id] = it }
        
        var out: [MemoryCandidate] = []
        out.reserveCapacity(items.count)
        
        for (mid, w) in ids {
            guard let item = byId[mid] else { continue }
            let base = score(item: item, ftsScore: nil)
            let boosted = base + 0.18 + 0.12 * clamp01(w)
            out.append(MemoryCandidate(item: item, ftsRankRaw: nil, score: boosted))
        }
        return out
    }
    
    private func fetchItemsByIds(_ ids: [String]) throws -> [MemoryItem] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let stmt = try db.prepare("""
        SELECT id, type, title, body, created_at, last_accessed, importance, salience, stability, pinned, source_turn_id, hash
        FROM mem_items
        WHERE id IN (\(placeholders));
        """)
        defer { sqlite3_finalize(stmt) }
        
        for (i, id) in ids.enumerated() {
            MemoryDB.bindText(stmt, Int32(i + 1), id)
        }
        
        var out: [MemoryItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(readItem(stmt))
        }
        return out
    }
    
    private func extractEntities(from text: String) -> [String] {
        // Cheap heuristic: keep 3-24 char tokens (letters/digits), unique, cap.
        // Improvements:
        // - diacritic-insensitive folding ("Uni" -> "uni")
        // - filter common stopwords to reduce graph noise
        // - drop numeric-only tokens

        let stop: Set<String> = [
            "the","and","or","but","for","with","from","this","that","these","those",
            "what","whats","what's","why","how","when","where","who","whom","whose",
            "is","are","was","were","be","been","being","do","does","did","can","could","would","should","will","shall",
            "i","me","my","mine","we","our","you","your","yours","it","its","it's",
            "remember","note","save","mind","please","pls","kindly","tell","show","explain",
            "about","into","over","under","than","then","there","here"
        ]

        let raw = text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0) }
        
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(12)
        
        for t in raw {
            let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count < 3 || cleaned.count > 24 { continue }

            let k = normalizeEntityKey(cleaned)
            if k.isEmpty { continue }
            if stop.contains(k) { continue }
            if k.allSatisfy({ $0.isNumber }) { continue }

            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(k)
            if out.count >= 10 { break }
        }
        
        return out
    }
    
    // MARK: - Retrieval internals
    
    private func searchFTS(_ query: String, limit: Int) throws -> [MemoryCandidate] {
        // bm25(mem_fts) smaller = better
        let stmt = try db.prepare("""
        SELECT
            mem_items.id,
            mem_items.type,
            mem_items.title,
            mem_items.body,
            mem_items.created_at,
            mem_items.last_accessed,
            mem_items.importance,
            mem_items.salience,
            mem_items.stability,
            mem_items.pinned,
            mem_items.source_turn_id,
            mem_items.hash,
            bm25(mem_fts) as rank
        FROM mem_fts
        JOIN mem_items ON mem_items.rowid = mem_fts.rowid
        WHERE mem_fts MATCH ?
        ORDER BY rank
        LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        
        MemoryDB.bindText(stmt, 1, query)
        MemoryDB.bindInt(stmt, 2, Int64(max(1, limit)))
        
        var out: [MemoryCandidate] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let item = readItemFTS(stmt)
            let rank = MemoryDB.colDouble(stmt, 12)
            
            // convert rank into 0..1 score-ish
            let ftsScore = 1.0 / (1.0 + max(0.0, rank))
            let s = score(item: item, ftsScore: ftsScore)
            
            out.append(MemoryCandidate(item: item, ftsRankRaw: rank, score: s))
        }
        return out
    }
    
    private func recentCandidates(limit: Int) throws -> [MemoryCandidate] {
        let stmt = try db.prepare("""
        SELECT id, type, title, body, created_at, last_accessed, importance, salience, stability, pinned, source_turn_id, hash
        FROM mem_items
        ORDER BY last_accessed DESC, created_at DESC
        LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindInt(stmt, 1, Int64(max(1, limit)))
        
        var out: [MemoryCandidate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let item = readItem(stmt)
            let s = score(item: item, ftsScore: nil)
            out.append(MemoryCandidate(item: item, ftsRankRaw: nil, score: s))
        }
        return out
    }
    
    private func pinnedCandidates(limit: Int) throws -> [MemoryCandidate] {
        let stmt = try db.prepare("""
        SELECT id, type, title, body, created_at, last_accessed, importance, salience, stability, pinned, source_turn_id, hash
        FROM mem_items
        WHERE pinned = 1
        ORDER BY last_accessed DESC, created_at DESC
        LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindInt(stmt, 1, Int64(max(1, limit)))
        
        var out: [MemoryCandidate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let item = readItem(stmt)
            let s = score(item: item, ftsScore: nil) + 0.35 // pin boost
            out.append(MemoryCandidate(item: item, ftsRankRaw: nil, score: s))
        }
        return out
    }
    
    private func score(item: MemoryItem, ftsScore: Double?) -> Double {
        // Simple scoring: content relevance (fts) + importance/salience + recency + pinned
        let nowTs = now().timeIntervalSince1970
        let ageSec = max(0, nowTs - item.lastAccessed.timeIntervalSince1970)
        
        // recency decay ~ 7 days half-life-ish
        let recency = exp(-ageSec / (7.0 * 24.0 * 3600.0))
        
        var s = 0.0
        if let ftsScore { s += 0.60 * clamp01(ftsScore) }
        s += 0.18 * clamp01(item.importance)
        s += 0.12 * clamp01(item.salience)
        s += 0.10 * clamp01(recency)
        s += 0.06 * clamp01(item.stability)
        if item.pinned { s += 0.25 }
        
        return s
    }
    
    // MARK: - DB helpers
    
    private func isCanonicalTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return false }
        // Keep this list tight; these are the ones we prefer to UPDATE instead of duplicating.
        let canonical: Set<String> = [
            "user name",
            "preferred name",
            "training goal",
            "goal",
            "scopekey",
            "email",
            "car",
            "cat"
        ]
        return canonical.contains(t)
    }

    private func findExistingCanonical(typeRaw: String, title: String) throws -> (id: String, body: String, createdAt: Int64, importance: Double, salience: Double, stability: Double, pinned: Bool)? {
        let stmt = try db.prepare("""
        SELECT id, body, created_at, importance, salience, stability, pinned
        FROM mem_items
        WHERE type = ? AND lower(title) = lower(?)
        ORDER BY pinned DESC, stability DESC, last_accessed DESC, created_at DESC
        LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindText(stmt, 1, typeRaw)
        MemoryDB.bindText(stmt, 2, title)
        if sqlite3_step(stmt) == SQLITE_ROW {
            let id = MemoryDB.colText(stmt, 0)
            let body = MemoryDB.colText(stmt, 1)
            let createdAt = MemoryDB.colInt(stmt, 2)
            let imp = MemoryDB.colDouble(stmt, 3)
            let sal = MemoryDB.colDouble(stmt, 4)
            let stab = MemoryDB.colDouble(stmt, 5)
            let pinned = MemoryDB.colInt(stmt, 6) == 1
            return (id: id, body: body, createdAt: createdAt, importance: imp, salience: sal, stability: stab, pinned: pinned)
        }
        return nil
    }

    private func updateMemItem(
        id: String,
        typeRaw: String,
        title: String,
        body: String,
        createdAt: Int64,
        lastAccessed: Int64,
        importance: Double,
        salience: Double,
        stability: Double,
        pinned: Bool,
        sourceTurnId: String?,
        hash: String
    ) throws {
        let stmt = try db.prepare("""
        UPDATE mem_items
        SET type = ?,
            title = ?,
            body = ?,
            created_at = ?,
            last_accessed = ?,
            importance = ?,
            salience = ?,
            stability = ?,
            pinned = ?,
            source_turn_id = ?,
            hash = ?
        WHERE id = ?;
        """)
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindText(stmt, 1, typeRaw)
        MemoryDB.bindText(stmt, 2, title)
        MemoryDB.bindText(stmt, 3, body)
        MemoryDB.bindInt(stmt, 4, createdAt)
        MemoryDB.bindInt(stmt, 5, lastAccessed)
        MemoryDB.bindDouble(stmt, 6, clamp01(importance))
        MemoryDB.bindDouble(stmt, 7, clamp01(salience))
        MemoryDB.bindDouble(stmt, 8, clamp01(stability))
        MemoryDB.bindInt(stmt, 9, pinned ? 1 : 0)
        MemoryDB.bindText(stmt, 10, sourceTurnId)
        MemoryDB.bindText(stmt, 11, hash)
        MemoryDB.bindText(stmt, 12, id)
        try db.stepDone(stmt)
    }

    private func touchMemItem(id: String, lastAccessed: Int64) throws {
        let stmt = try db.prepare("UPDATE mem_items SET last_accessed = ? WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindInt(stmt, 1, lastAccessed)
        MemoryDB.bindText(stmt, 2, id)
        try db.stepDone(stmt)
    }

    private func findIdByHash(_ hash: String) throws -> String? {
        let stmt = try db.prepare("SELECT id FROM mem_items WHERE hash = ? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindText(stmt, 1, hash)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return MemoryDB.colText(stmt, 0)
        }
        return nil
    }
    
    private func bumpExisting(id: String, importance: Double, salience: Double) throws {
        let ts = Int64(now().timeIntervalSince1970)
        let stmt = try db.prepare("""
        UPDATE mem_items
        SET last_accessed = ?,
            importance = MIN(1.0, importance + ?),
            salience   = MIN(1.0, salience + ?)
        WHERE id = ?;
        """)
        defer { sqlite3_finalize(stmt) }
        MemoryDB.bindInt(stmt, 1, ts)
        MemoryDB.bindDouble(stmt, 2, clamp01(importance) * 0.10)
        MemoryDB.bindDouble(stmt, 3, clamp01(salience) * 0.10)
        MemoryDB.bindText(stmt, 4, id)
        try db.stepDone(stmt)
    }
    
    private func readItem(_ stmt: OpaquePointer?) -> MemoryItem {
        let id = MemoryDB.colText(stmt, 0)
        let typeRaw = MemoryDB.colText(stmt, 1)
        let title = MemoryDB.colText(stmt, 2)
        let body = MemoryDB.colText(stmt, 3)
        
        let created = Date(timeIntervalSince1970: TimeInterval(MemoryDB.colInt(stmt, 4)))
        let accessed = Date(timeIntervalSince1970: TimeInterval(MemoryDB.colInt(stmt, 5)))
        
        let importance = MemoryDB.colDouble(stmt, 6)
        let salience = MemoryDB.colDouble(stmt, 7)
        let stability = MemoryDB.colDouble(stmt, 8)
        let pinned = MemoryDB.colInt(stmt, 9) == 1
        
        let turnStr = MemoryDB.colText(stmt, 10)
        let sourceTurnId = UUID(uuidString: turnStr)
        
        let hash = MemoryDB.colText(stmt, 11)
        
        let type = MemoryItemType(rawValue: typeRaw) ?? .semantic
        
        return MemoryItem(
            id: id,
            type: type,
            title: title,
            body: body,
            createdAt: created,
            lastAccessed: accessed,
            importance: importance,
            salience: salience,
            stability: stability,
            pinned: pinned,
            sourceTurnId: sourceTurnId,
            hash: hash
        )
    }
    
    // FTS select has rank in col 12, so item columns shift
    private func readItemFTS(_ stmt: OpaquePointer?) -> MemoryItem {
        let id = MemoryDB.colText(stmt, 0)
        let typeRaw = MemoryDB.colText(stmt, 1)
        let title = MemoryDB.colText(stmt, 2)
        let body = MemoryDB.colText(stmt, 3)
        
        let created = Date(timeIntervalSince1970: TimeInterval(MemoryDB.colInt(stmt, 4)))
        let accessed = Date(timeIntervalSince1970: TimeInterval(MemoryDB.colInt(stmt, 5)))
        
        let importance = MemoryDB.colDouble(stmt, 6)
        let salience = MemoryDB.colDouble(stmt, 7)
        let stability = MemoryDB.colDouble(stmt, 8)
        let pinned = MemoryDB.colInt(stmt, 9) == 1
        
        let turnStr = MemoryDB.colText(stmt, 10)
        let sourceTurnId = UUID(uuidString: turnStr)
        
        let hash = MemoryDB.colText(stmt, 11)
        
        let type = MemoryItemType(rawValue: typeRaw) ?? .semantic
        
        return MemoryItem(
            id: id,
            type: type,
            title: title,
            body: body,
            createdAt: created,
            lastAccessed: accessed,
            importance: importance,
            salience: salience,
            stability: stability,
            pinned: pinned,
            sourceTurnId: sourceTurnId,
            hash: hash
        )
    }
    
    private func formatLine(_ item: MemoryItem) -> String {
        // Keep it compact for iOS prompt size
        let t = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return t }
        if t.isEmpty { return b }
        return "\(t): \(b)"
    }
    
    private func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func clamp01(_ x: Double) -> Double {
        min(1.0, max(0.0, x))
    }
    
    // MARK: - Debug / Diagnostics
    /// Helpful when diagnosing “memory not persistent across sessions”.
    /// Call this at boot and after a few writes.
    /// Since `MemoryStore` is an actor, call as: `await MemoryStore.shared.debugDumpStats(tag: "boot")`.
    public func debugDumpStats(tag: String = "") {
#if DEBUG
        do {
            let suffix = tag.isEmpty ? "" : " [\(tag)]"
            msLog("[MemoryStore] debugDumpStats\(suffix) db=\(dbURL.path)")
            
            // Total count
            do {
                let stmt = try db.prepare("SELECT COUNT(1) FROM mem_items;")
                defer { sqlite3_finalize(stmt) }
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let n = MemoryDB.colInt(stmt, 0)
                    msLog("[MemoryStore] mem_items total=\(n)")
                }
            }
            
            // Count by type
            do {
                let stmt = try db.prepare("SELECT type, COUNT(1) FROM mem_items GROUP BY type ORDER BY COUNT(1) DESC;")
                defer { sqlite3_finalize(stmt) }
                var parts: [String] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let t = MemoryDB.colText(stmt, 0)
                    let n = MemoryDB.colInt(stmt, 1)
                    parts.append("\(t)=\(n)")
                }
                if !parts.isEmpty {
                    msLog("[MemoryStore] mem_items byType { \(parts.joined(separator: ", ")) }")
                }
            }
            
            // Embedding rows count (Phase 4)
            do {
                try ensurePhase45TablesIfNeeded()
                let stmt = try db.prepare("SELECT COUNT(1) FROM mem_embeddings;")
                defer { sqlite3_finalize(stmt) }
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let n = MemoryDB.colInt(stmt, 0)
                    msLog("[MemoryStore] mem_embeddings total=\(n)")
                }
            }

            // Graph rows count (Phase 5)
            do {
                try ensurePhase45TablesIfNeeded()

                func count(_ sql: String) throws -> Int64 {
                    let stmt = try db.prepare(sql)
                    defer { sqlite3_finalize(stmt) }
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        return MemoryDB.colInt(stmt, 0)
                    }
                    return 0
                }

                let nNodes = try count("SELECT COUNT(1) FROM graph_nodes;")
                let nEdges = try count("SELECT COUNT(1) FROM graph_edges;")
                let nTags  = try count("SELECT COUNT(1) FROM graph_node_tags;")
                let nEnts  = try count("SELECT COUNT(1) FROM mem_entities;")

                msLog("[MemoryStore] graph_nodes total=\(nNodes)")
                msLog("[MemoryStore] graph_edges total=\(nEdges)")
                msLog("[MemoryStore] graph_node_tags total=\(nTags)")
                msLog("[MemoryStore] mem_entities total=\(nEnts)")
            }
        } catch {
            msLog("[MemoryStore] debugDumpStats failed: \(error)")
        }
#endif
    }
}
    
