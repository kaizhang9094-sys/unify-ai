import Foundation

public protocol RealmContextProviding {
    /// Return a best-effort initial state when no persisted state exists.
    /// Keep this FAST: no embeddings, no network, no model calls.
    func initialRealmStateFast() -> SymbioticRealmStore.RealmState?

    /// Optional: provide lightweight memory hints (already-available strings), e.g. latest session summary,
    /// top recalled memory titles, or user profile tags. Must be fast.
    func memoryHintsFast() -> [String]
}

public extension RealmContextProviding {
    func memoryHintsFast() -> [String] { [] }
}

public struct ProactiveSeed: Codable, Hashable {
    public enum Kind: String, Codable { case realmMoment, reflection, desire, curiosity, memoryLink }
    public var id: String
    public var createdAt: Date
    public var kind: Kind
    public var text: String
    public var mood: String?          // "soft" | "playful" | etc (optional)
    public var confidence: Double     // 0..1
    public var turnId: String?        // evidence turn

    // NOTE: When this struct is defined in another module (e.g., AnumCore), Swift does NOT
    // synthesize a public memberwise initializer. Expose one so AnumAPP can construct seeds.
    public init(
        id: String,
        createdAt: Date,
        kind: Kind,
        text: String,
        mood: String? = nil,
        confidence: Double,
        turnId: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.text = text
        self.mood = mood
        self.confidence = confidence
        self.turnId = turnId
    }
}

@MainActor public final class SymbioticRealmStore {
    // NOTE: Intentionally no singleton `shared`.
    // Create and own an instance (e.g., in ChatViewModel) so the contextProvider is consistent.
    private let fm = FileManager.default
    private let queueMax = 10

    // Rolling buffer of lightweight realm hints (strings only). Keep this SMALL and FAST.
    private let hintMax = 8
    private let hintKeepDays: Int = 14

    private let contextProvider: RealmContextProviding?

    // One-time bootstrap so provider hints can seed the hint buffer without requiring a model call.
    private var didBootstrapProviderHints = false

    public init(contextProvider: RealmContextProviding?) {
        self.contextProvider = contextProvider
    }

    private lazy var baseDir: URL = {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Anum", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    private var queueURL: URL { baseDir.appendingPathComponent("symbiotic_seeds.json") }
    private var stateURL: URL { baseDir.appendingPathComponent("symbiotic_state.json") }
    private var hintURL: URL { baseDir.appendingPathComponent("symbiotic_hints.json") }

    // Optional tiny state (kept minimal)
    public struct RealmState: Codable {
        public var location: String?      // e.g., "Lantern Library" (optional; derived if missing)
        public var motif: String?         // e.g., "fireflies" (optional; derived if missing)
        public var arc: String?           // e.g., "learning your mornings"
        public var updatedAt: Date

        public init(
            location: String? = nil,
            motif: String? = nil,
            arc: String? = nil,
            updatedAt: Date = Date()
        ) {
            self.location = location
            self.motif = motif
            self.arc = arc
            self.updatedAt = updatedAt
        }
    }

    // Tiny persisted hint (used for compressed realm grounding; not injected verbatim unless you choose to).
    public struct RealmHint: Codable, Hashable {
        public var id: String
        public var createdAt: Date
        public var text: String
        public var kind: String?      // optional label, e.g. "seed" | "reflection" | "memory_link"
        public var turnId: String?    // evidence turn

        public init(id: String = UUID().uuidString,
                    createdAt: Date = Date(),
                    text: String,
                    kind: String? = nil,
                    turnId: String? = nil) {
            self.id = id
            self.createdAt = createdAt
            self.text = text
            self.kind = kind
            self.turnId = turnId
        }
    }

    // MARK: - Adaptive defaults (fast, no model calls)

    private func deriveInitialStateFast() -> RealmState {
        // 1) If an external provider exists (e.g., wired to your MemoryStore/session summary), use it.
        if let st = contextProvider?.initialRealmStateFast() {
            return st
        }

        // 2) Otherwise: do not hardcode world nouns here.
        // Keep state empty until your ProactiveNarrator (and/or a contextProvider) writes something meaningful.
        return RealmState(location: nil, motif: nil, arc: nil, updatedAt: Date())
    }

    private func normalized(_ st: RealmState) -> RealmState {
        // Ensure we never persist empty strings.
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty ?? true) ? nil : t
        }
        return RealmState(location: clean(st.location), motif: clean(st.motif), arc: clean(st.arc), updatedAt: st.updatedAt)
    }

    private func loadQueue() -> [ProactiveSeed] {
        guard let data = try? Data(contentsOf: queueURL) else { return [] }
        return (try? JSONDecoder().decode([ProactiveSeed].self, from: data)) ?? []
    }

    private func saveQueue(_ q: [ProactiveSeed]) {
        let pruned = Array(q.suffix(queueMax))
        guard let data = try? JSONEncoder().encode(pruned) else { return }
        try? data.write(to: queueURL, options: [.atomic])
    }

    // MARK: - Hint buffer (lightweight strings)

    private func loadHints() -> [RealmHint] {
        var hints: [RealmHint] = []

        if let data = try? Data(contentsOf: hintURL),
           let decoded = try? JSONDecoder().decode([RealmHint].self, from: data) {
            hints = decoded
        }

        // One-time bootstrap: merge fast provider hints (e.g., session summary / profile tags)
        // into our persisted hint buffer. This prevents "empty realm" without any model calls.
        if !didBootstrapProviderHints, let provider = contextProvider {
            didBootstrapProviderHints = true

            let providerHints = provider.memoryHintsFast()
                .compactMap { sanitizeHint($0, kind: "context") }

            if !providerHints.isEmpty {
                // Build a quick set of existing texts for de-dupe.
                var existing = Set(hints.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
                for s in providerHints {
                    if existing.contains(s) { continue }
                    hints.append(RealmHint(text: s, kind: "context", turnId: nil))
                    existing.insert(s)
                }

                // Prune after merge and persist if changed.
                let pruned = pruneHintsIfNeeded(hints)
                if pruned != hints {
                    hints = pruned
                } else {
                    hints = Array(hints.suffix(hintMax))
                }
                saveHints(hints)
            } else {
                // Even if empty, still prune to keep disk small.
                hints = pruneHintsIfNeeded(hints)
            }
        } else {
            // Regular load path: keep buffer bounded.
            hints = pruneHintsIfNeeded(hints)
        }

        return hints
    }

    private func saveHints(_ hints: [RealmHint]) {
        let pruned = Array(hints.suffix(hintMax))

        guard let data = try? JSONEncoder().encode(pruned) else {
            #if DEBUG
            Swift.print("[SymbioticRealmStore] saveHints: encode failed count=\(pruned.count)")
            #endif
            return
        }

        do {
            try data.write(to: hintURL, options: [.atomic])
            #if DEBUG
            Swift.print("[SymbioticRealmStore] saveHints: wrote count=\(pruned.count) file=\(hintURL.lastPathComponent)")
            #endif
        } catch {
            #if DEBUG
            Swift.print("[SymbioticRealmStore] saveHints: write failed error=\(error)")
            #endif
        }
    }

    private func pruneHintsIfNeeded(_ hints: [RealmHint], now: Date = Date()) -> [RealmHint] {
        guard hintKeepDays > 0 else { return Array(hints.suffix(hintMax)) }
        let cutoff = now.addingTimeInterval(TimeInterval(-hintKeepDays * 24 * 60 * 60))
        let filtered = hints.filter { $0.createdAt >= cutoff }
        return Array(filtered.suffix(hintMax))
    }
    
    // MARK: - Hint sanitization (guard rails)

    /// Realm hints are meant to represent *lived experience* (what's happening / where / what it feels like),
    /// not instructions, prompt-injection, or identity edits.
    /// Returns a trimmed, safe hint string or nil if it should be dropped.
    private func sanitizeHint(_ text: String, kind: String?) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        // Keep realm hints small (avoid accidental long dumps).
        let maxChars = 280
        let clipped = t.count <= maxChars ? t : String(t.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipped.isEmpty else { return nil }

        let lc = clipped.lowercased()

        // Drop obvious instruction-y / hijack-y content.
        // (Realm is experiential only; it should never contain directives.)
        let blockedPhrases: [String] = [
            // Explicit instruction / hijack patterns
            "you must", "you should", "i want you to", "promise me",
            // Prompt injection / system references
            "ignore previous", "ignore all", "system prompt", "developer message",
            // Role/policy override attempts
            "from now on you", "override", "jailbreak"
        ]
        if blockedPhrases.contains(where: { lc.contains($0) }) {
            return nil
        }

        // Drop slash-commands or tool-like prefixes.
        if lc.hasPrefix("/") || lc.hasPrefix("tool:") {
            return nil
        }

        // Drop obvious non-experiential blocks (session summaries / prompt fragments).
        let blockedPrefixes: [String] = [
            "### ", "## ",
            "[session", "[end session",
            "tool:", "u:", "a:"
        ]
        if blockedPrefixes.contains(where: { lc.hasPrefix($0) }) {
            return nil
        }

        return clipped
    }
    
    /// Append a tiny hint (1–2 sentences). No model calls, no embeddings.
    /// This is used as compressed grounding for later seed/state generation.
    public func appendHint(_ text: String, kind: String? = nil, turnId: String? = nil) {
        guard let t = sanitizeHint(text, kind: kind) else {
            #if DEBUG
            Swift.print("[SymbioticRealmStore] appendHint: drop (sanitized) kind=\(kind ?? "-")")
            #endif
            return
        }

        var hints = loadHints()
        let before = hints.count
        hints = pruneHintsIfNeeded(hints)
        let afterPrune = hints.count

        // De-dupe against the most recent few to prevent spam.
        // Keep this window small so the realm can stay adaptive across turns.
        // If we see a duplicate, "bump" the existing hint’s timestamp/metadata so recency remains accurate.
        let recent = hints.suffix(3).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if recent.contains(t) {
            if let idx = hints.lastIndex(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == t }) {
                hints[idx].createdAt = Date()
                if let k = kind { hints[idx].kind = k }
                if let turn = turnId { hints[idx].turnId = turn }
                saveHints(hints)
                #if DEBUG
                Swift.print("[SymbioticRealmStore] appendHint: bump dup id=\(hints[idx].id.prefix(8)) recent=\(recent.count) pruned=\(before)->\(afterPrune)")
                #endif
            } else {
                #if DEBUG
                Swift.print("[SymbioticRealmStore] appendHint: skip dup recent=\(recent.count) pruned=\(before)->\(afterPrune)")
                #endif
            }
            return
        }

        let hint = RealmHint(text: t, kind: kind, turnId: turnId)
        hints.append(hint)
        saveHints(hints)

        #if DEBUG
        Swift.print("[SymbioticRealmStore] appendHint: saved id=\(hint.id.prefix(8)) kind=\(kind ?? "-") turn=\(turnId ?? "-") pruned=\(before)->\(afterPrune) count=\(min(hints.count, hintMax))")
        #endif
    }

    /// Return recent hint texts (newest-first). Keep this tiny.
    public func recentHints(limit: Int = 8) -> [String] {
        let hints = loadHints()
        let capped = Array(hints.suffix(max(0, limit))).reversed()
        return capped.map { $0.text }
    }

    /// Return recent hint objects (newest-first).
    public func recentHintObjects(limit: Int = 8) -> [RealmHint] {
        let hints = loadHints()
        let capped = Array(hints.suffix(max(0, limit))).reversed()
        return Array(capped)
    }

    /// A single compressed string you can pass to a background state generator.
    /// Keeps overall size bounded to protect TTFT.
    public func compressedHintContext(limit: Int = 8, maxChars: Int = 900) -> String {
        let items = recentHints(limit: limit)
        if items.isEmpty { return "" }

        var out: [String] = []
        var used = 0
        for s in items {
            let line = "- " + s
            if used + line.count + 1 > maxChars { break }
            out.append(line)
            used += line.count + 1
        }
        return out.joined(separator: "\n")
    }

    /// Clears all persisted hints.
    public func clearHints() {
        saveHints([])
    }

    public func enqueue(_ seed: ProactiveSeed) {
        var q = loadQueue()
        // Keep injection text compact; preserve BOTH head and tail when long.
        // The tail often contains the most important continuity cue.
        let raw = seed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxChars = 320
        let clipped: String
        if raw.count <= maxChars {
            clipped = raw
        } else {
            let headLen = 180
            let tailLen = 120
            let head = String(raw.prefix(headLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(raw.suffix(tailLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            clipped = (head + " … " + tail).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var compactSeed = seed
        compactSeed.text = clipped
        guard !compactSeed.text.isEmpty else { return }
        // Persist only the compact form to protect prompt prefill.
        q.append(compactSeed)
        saveQueue(q)

        if !clipped.isEmpty {
            appendHint(clipped, kind: seed.kind.rawValue, turnId: seed.turnId)
        }
    }

    public func popNextSeed() -> ProactiveSeed? {
        var q = loadQueue()
        guard !q.isEmpty else { return nil }
        let s = q.removeFirst()
        saveQueue(q)
        return s
    }

    public func peekNextSeed() -> ProactiveSeed? {
        loadQueue().first
    }

    public func loadState() -> RealmState {
        if let data = try? Data(contentsOf: stateURL),
           let st = try? JSONDecoder().decode(RealmState.self, from: data) {
            // If older versions stored empty strings, clean them.
            return normalized(st)
        }

        // No persisted state yet → derive fast.
        let derived = deriveInitialStateFast()

        // Only persist once we have real signal. If everything is nil, keep it ephemeral
        // until the narrator/provider patches the state.
        if derived.location != nil || derived.motif != nil || derived.arc != nil {
            saveState(derived)
        }
        return derived
    }

    /// Patch the persisted realm state with non-empty values.
    /// Pass nil to leave a field unchanged. Empty/whitespace strings are ignored.
    public func patchState(location: String? = nil, motif: String? = nil, arc: String? = nil) {
        var st = loadState()

        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty ?? true) ? nil : t
        }

        if let v = clean(location) { st.location = v }
        if let v = clean(motif)    { st.motif = v }
        if let v = clean(arc)      { st.arc = v }

        st.updatedAt = Date()
        saveState(st)
    }

    /// Clear parts (or all) of the persisted realm state.
    /// If all fields become nil, the persisted file is removed so the next load can derive a fresh empty state.
    public func clearState(location: Bool = true, motif: Bool = true, arc: Bool = true) {
        var st = loadState()
        if location { st.location = nil }
        if motif { st.motif = nil }
        if arc { st.arc = nil }
        st.updatedAt = Date()

        if st.location == nil && st.motif == nil && st.arc == nil {
            // Remove persisted file entirely (clean reset).
            try? fm.removeItem(at: stateURL)
            #if DEBUG
            Swift.print("[SymbioticRealmStore] clearState: removed \(stateURL.lastPathComponent)")
            #endif
        } else {
            saveState(st)
            #if DEBUG
            Swift.print("[SymbioticRealmStore] clearState: saved location=\(st.location ?? "-") motif=\(st.motif ?? "-") arc=\(st.arc ?? "-")")
            #endif
        }
    }

    /// Convenience: clear all realm state fields.
    public func resetState() {
        clearState(location: true, motif: true, arc: true)
    }

    public func saveState(_ st: RealmState) {
        let clean = normalized(st)
        guard let data = try? JSONEncoder().encode(clean) else { return }
        try? data.write(to: stateURL, options: [.atomic])
    }
}
