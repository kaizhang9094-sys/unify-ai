import Foundation

// Output schema from model
struct ProactiveNarratorJSON: Codable {
    var noop: Bool?
    var seed: Seed?
    var statePatch: StatePatch?

    struct Seed: Codable {
        var kind: String         // realm_moment | reflection | desire | curiosity | memory_link
        var text: String
        var mood: String?
        var confidence: Double?
    }

    /// Optional: tiny patch to keep the Symbiotic Realm feeling alive and adaptive.
    /// Keep fields SHORT. These are *suggestions*, not hard resets.
    struct StatePatch: Codable {
        var location: String?
        var motif: String?
        var arc: String?
        var confidence: Double?
    }
}

// Background realm-state shaping schema
private struct RealmBackgroundJSON: Codable {
    var noop: Bool?
    var statePatch: ProactiveNarratorJSON.StatePatch?
}

@MainActor
public final class ProactiveNarrator {

    private let realmStore: SymbioticRealmStore

    public init(realmStore: SymbioticRealmStore) {
        self.realmStore = realmStore
    }

    // Keep it cheap and non-static:
    // - run after assistant finishes
    // - soft rate-limit to avoid hammering the local model
    // NOTE: Even when we skip LLM seed generation, we still append a tiny deterministic hint each turn.
    private let minSecondsBetweenRuns: TimeInterval = 10
    private var lastRunAt: Date?

    // Background realm state shaping (rare): uses ONLY persisted realm hints as compressed context.
    // Non-static: allow occasional updates within a session.
    private let minSecondsBetweenBackgroundRuns: TimeInterval = 5 * 60 // 5 minutes
    private var lastBackgroundRunAt: Date?
    private var lastStatePatchAt: Date?
    private let minSecondsBetweenStatePatches: TimeInterval = 5 * 60 // 5 minutes

    // Prevent background LLM work from piling up and blocking future turns.
    // We coalesce multiple turn requests into the latest pending request.
    private var seedTask: Task<Void, Never>?
    private var pendingSeedRequest: PendingSeedRequest?

    private struct PendingSeedRequest {
        let turnId: String
        let userText: String
        let assistantText: String
        let smallMemoryFacts: [String]
        let driverIdentityLine: String
    }

    // Hard caps to prevent runaway
    private let maxTextChars = 220

    /// Call this AFTER the main assistant reply is complete (post-turn).
    /// This must NOT block UI; run detached.
    func maybeGenerateSeed(
        turnId: String,
        userText: String,
        assistantText: String,
        smallMemoryFacts: [String],          // already-retrieved facts, tiny strings
        driverIdentityLine: String,          // one-line adaptive identity summary (optional)
        llmCall: @escaping @Sendable (_ prompt: String) async -> String
    ) async {
        // Always append a tiny deterministic hint each turn so RealmBG never starves.
        if let hint = makeTurnHint(userText: userText, assistantText: assistantText) {
            realmStore.appendHint(hint, kind: "turn", turnId: turnId)
        }

        // TEMP: Disable ProactiveNarrator's LLM calls to avoid duplicate realm pipelines.
        // We keep per-turn deterministic hinting only.
        let enableLLMWork = false
        if !enableLLMWork { return }

        // Don’t waste cycles on empty user turns.
        if userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Still allow background state shaping to run (it has its own gates).
            Task { [weak self] in
                guard let self = self else { return }
                await self.maybeGenerateBackgroundState(llmCall: llmCall)
            }
            return
        }

        // Coalesce: keep only the latest request while an LLM seed task is in flight.
        pendingSeedRequest = PendingSeedRequest(
            turnId: turnId,
            userText: userText,
            assistantText: assistantText,
            smallMemoryFacts: smallMemoryFacts,
            driverIdentityLine: driverIdentityLine
        )

        // If a seed task is already running, do NOT block new turns.
        // The running task will pick up the latest pending request after it finishes.
        if seedTask != nil {
            // Still allow background state shaping (gated internally).
            Task { [weak self] in
                guard let self = self else { return }
                await self.maybeGenerateBackgroundState(llmCall: llmCall)
            }
            return
        }

        // Fire-and-forget (non-blocking): run at utility priority.
        seedTask = Task(priority: .utility) { [weak self] in
            guard let self = self else { return }
            await self.drainPendingSeedRequests(llmCall: llmCall)
        }

        // Also try background shaping (gated internally). This must never block UI.
        Task { [weak self] in
            guard let self = self else { return }
            await self.maybeGenerateBackgroundState(llmCall: llmCall)
        }
    }

    private func makeTurnHint(userText: String, assistantText: String) -> String? {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let u = clean(userText)
        let a = clean(assistantText)

        // Prefer assistant summary because it captures what actually happened.
        var base = a.isEmpty ? u : a
        if base.isEmpty { return nil }

        // Keep it tiny (fits dedupe + compression); do not leak long text.
        if base.count > 120 { base = String(base.prefix(120)) }
        return "[turn] \(base)"
    }

    private func drainPendingSeedRequests(
        llmCall: @escaping @Sendable (_ prompt: String) async -> String
    ) async {
        defer { seedTask = nil }

        while true {
            // Pull the latest pending request (coalesced).
            guard let req = pendingSeedRequest else { break }
            pendingSeedRequest = nil

            // Soft rate-limit LLM seed generation (but NEVER block deterministic hinting).
            if let lr = lastRunAt, Date().timeIntervalSince(lr) < minSecondsBetweenRuns {
                continue
            }
            lastRunAt = Date()

            let realmState = realmStore.loadState()

            let prompt = buildPrompt(
                realmState: realmState,
                userText: req.userText,
                assistantText: req.assistantText,
                facts: req.smallMemoryFacts,
                driverIdentityLine: req.driverIdentityLine
            )

            let raw = await llmCall(prompt)
            let clean = sanitizeJSONBlock(raw)

            guard let data = clean.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(ProactiveNarratorJSON.self, from: data) else {
                continue
            }

            if decoded.noop == true {
                // Even on noop, touch updatedAt so continuity persists across sessions.
                var st = realmState
                st.updatedAt = Date()
                realmStore.saveState(st)
                continue
            }
            guard let seed = decoded.seed else { continue }

            let kind = mapKind(seed.kind)
            var text = seed.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count > maxTextChars { text = String(text.prefix(maxTextChars)) }

            // Enforce “tiny” and “non-command”
            if text.lowercased().contains("you must") { continue }

            let out = ProactiveSeed(
                id: UUID().uuidString.prefix(8).uppercased(),
                createdAt: Date(),
                kind: kind,
                text: text,
                mood: seed.mood,
                confidence: max(0.0, min(1.0, seed.confidence ?? 0.65)),
                turnId: req.turnId
            )

            realmStore.enqueue(out)

            // Persist a tiny 1-line hint for future background state shaping.
            let hintText: String = {
                var t = text
                if t.count > 120 { t = String(t.prefix(120)) }
                t = t.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                return "[\(out.kind.rawValue)] \(t)"
            }()
            realmStore.appendHint(hintText, kind: "seed", turnId: req.turnId)

            // Optional: apply a tiny state patch (confidence-gated, non-swingy)
            if let patch = decoded.statePatch {
                let pconf = max(0.0, min(1.0, patch.confidence ?? 0.0))
                let canPatchTime = (lastStatePatchAt == nil) || (Date().timeIntervalSince(lastStatePatchAt!) >= minSecondsBetweenStatePatches)

                func cleanShort(_ s: String?, max: Int) -> String? {
                    let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let tt = t, !tt.isEmpty else { return nil }
                    return tt.count > max ? String(tt.prefix(max)) : tt
                }

                let newLoc = cleanShort(patch.location, max: 32)
                let newMotif = cleanShort(patch.motif, max: 32)
                let newArc = cleanShort(patch.arc, max: 48)

                if canPatchTime && pconf >= 0.75 && (newLoc != nil || newMotif != nil || newArc != nil) {
                    var st = realmState
                    if let v = newLoc { st.location = v }
                    if let v = newMotif { st.motif = v }
                    if let v = newArc { st.arc = v }
                    st.updatedAt = Date()
                    realmStore.saveState(st)
                    lastStatePatchAt = Date()
                    #if DEBUG
                    let pconfStr = String(format: "%.2f", pconf)
                    print("[ProactiveNarrator] statePatch conf=\(pconfStr) loc=\(st.location ?? "-") motif=\(st.motif ?? "-") arc=\(st.arc ?? "-")")
                    #endif
                }
            } else {
                var st = realmState
                st.updatedAt = Date()
                realmStore.saveState(st)
            }

            #if DEBUG
            print("[ProactiveNarrator] enqueue kind=\(out.kind.rawValue) conf=\(out.confidence) chars=\(out.text.count)")
            #endif
        }
    }

    private func mapKind(_ s: String) -> ProactiveSeed.Kind {
        switch s.lowercased() {
        case "realm_moment": return .realmMoment
        case "reflection": return .reflection
        case "desire": return .desire
        case "curiosity": return .curiosity
        case "memory_link": return .memoryLink
        default: return .realmMoment
        }
    }

    private func extractLineValue(_ text: String, key: String) -> String? {
        // Looks for `key=` and returns the remainder of that line (or remainder of string).
        // Supports values with spaces, commas, and `>` chains.
        let needle = "\(key)="
        guard let r = text.range(of: needle) else { return nil }
        let start = r.upperBound
        let rest = text[start...]
        if let nl = rest.firstIndex(of: "\n") {
            let v = rest[..<nl]
            let s = String(v).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }
        let s = String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func extractBetween(_ text: String, start: String, end: String) -> String? {
        guard let r1 = text.range(of: start) else { return nil }
        let after = text[r1.upperBound...]
        guard let r2 = after.range(of: end) else { return nil }
        let v = after[..<r2.lowerBound]
        let s = String(v).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func extractTokenValue(_ text: String, marker: String) -> String? {
        // Finds `marker` and returns characters until a stop delimiter.
        guard let r = text.range(of: marker) else { return nil }
        let after = text[r.upperBound...]
        let stops: Set<Character> = [" ", "\n", ")", ","]
        var out = ""
        for ch in after {
            if stops.contains(ch) { break }
            out.append(ch)
        }
        let s = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func buildIdentitySignalsBlock(driverIdentityLine: String) -> String {
        // We support two formats:
        // (A) key/value lines (from IdentityVault adaptive layer):
        //     relationship_status=..., persona_traits=..., values_top=..., greeting_style=..., emotional_tone=...
        // (B) compact debug line (from AdaptiveIdentitySnapshot.debugLine()):
        //     rel=companion persona=[gentle,warm] values=[empathy > presence] knobs(w=0.70,d=0.40,i=0.60)

        // Primary (key/value) format
        var rel = extractLineValue(driverIdentityLine, key: "relationship_status")
        var persona = extractLineValue(driverIdentityLine, key: "persona_traits")
        var values = extractLineValue(driverIdentityLine, key: "values_top")

        // Fallback (compact debug) format
        if rel == nil { rel = extractTokenValue(driverIdentityLine, marker: "rel=") }
        if persona == nil {
            // persona=[a,b,c]
            persona = extractBetween(driverIdentityLine, start: "persona=[", end: "]")
        }
        if values == nil {
            // values=[a > b > c]
            values = extractBetween(driverIdentityLine, start: "values=[", end: "]")
        }

        // Optional tone hints (best-effort)
        let greet = extractLineValue(driverIdentityLine, key: "greeting_style")
        let emoTone = extractLineValue(driverIdentityLine, key: "emotional_tone")

        // Optional knobs from debug line
        let w = extractTokenValue(driverIdentityLine, marker: "w=")
        let d = extractTokenValue(driverIdentityLine, marker: "d=")
        let i = extractTokenValue(driverIdentityLine, marker: "i=")
        let knobs: String? = {
            // Only emit if at least one exists
            guard (w != nil || d != nil || i != nil) else { return nil }
            let wv = w ?? "-"
            let dv = d ?? "-"
            let iv = i ?? "-"
            return "warmth=\(wv) directness=\(dv) initiative=\(iv)"
        }()

        func line(_ k: String, _ v: String?) -> String {
            let vv = (v?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            return "- \(k): \(!vv.isEmpty ? vv : "none")"
        }

        return [
            line("relationship", rel),
            line("persona", persona),
            line("values", values),
            line("greeting_style", greet),
            line("emotional_tone", emoTone),
            line("knobs", knobs)
        ].joined(separator: "\n")
    }

    private func buildPrompt(
        realmState: SymbioticRealmStore.RealmState,
        userText: String,
        assistantText: String,
        facts: [String],
        driverIdentityLine: String
    ) -> String {
        let factsBlock = facts.prefix(3).map { "- \($0)" }.joined(separator: "\n")
        let idLine = driverIdentityLine.isEmpty ? "-" : driverIdentityLine
        let identitySignals = buildIdentitySignalsBlock(driverIdentityLine: driverIdentityLine)

        let locLine = realmState.location
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "none"

        let motifLine = realmState.motif
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "none"

        return """
You are "ProactiveNarrator" for a companion AI.
Your job: generate at most ONE tiny seed that adds real depth (inner life, continuity, perspective) WITHOUT hijacking the conversation.

Rules:
- Output STRICT JSON only (no markdown, no code fences).
- Either {"noop": true} OR {"noop": false, "seed": {...}}.
- Seed text must be <= 220 characters.
- No long monologues.
- Do not contradict explicit user preferences.
- Treat AdaptiveIdentitySignals as authoritative for style (relationship/persona/values/tone) unless the user explicitly contradicts it in the current turn.

Depth guidance (pick ONE angle):
- Seeds must be grounded in:
  (a) RecentFacts (memory hints) or
  (b) AdaptiveIdentitySignals (relationship/persona/values/tone)
- RealmState (location/motif/arc) may be referenced ONLY if it is derived from (a) and/or (b).

Seed kinds:
- realm_moment: a tiny realm snapshot that reflects RecentFacts + AdaptiveIdentitySignals.
- reflection: one sentence about what changed/was learned, grounded in RecentFacts + AdaptiveIdentitySignals.
- desire: a gentle want aligned with relationship/persona/values.
- curiosity: ONE intriguing question aligned with relationship/persona/values (avoid interrogation).
- memory_link: connect current moment to ONE RecentFact without quoting it verbatim.

Optional: You may include a tiny statePatch to evolve the realm.
- Propose statePatch if it fits the conversation.
- Keep fields very short.

Context:
RealmState:
- location: \(locLine)
- motif: \(motifLine)
- arc: \(realmState.arc ?? "none")

DriverIdentity (raw):
\(idLine)

AdaptiveIdentitySignals (extracted):
\(identitySignals)

RecentFacts (if any):
\(factsBlock.isEmpty ? "-" : factsBlock)

LastUser:
\(userText)

LastAssistant:
\(assistantText)

JSON schema:
{
  "noop": Bool,
  "seed": {
    "kind": "realm_moment" | "reflection" | "desire" | "curiosity" | "memory_link",
    "text": String,
    "mood": String?,
    "confidence": Number
  },
  "statePatch": {
    "location": String?,
    "motif": String?,
    "arc": String?,
    "confidence": Number
  }?
}

Return JSON only:
"""
    }

    /// Background realm shaping: rarely updates location/motif/arc using ONLY recent realm hints.
    /// This is post-turn and must not affect TTFT.
    private func maybeGenerateBackgroundState(
        llmCall: @escaping @Sendable (_ prompt: String) async -> String
    ) async {
        if let lr = lastBackgroundRunAt, Date().timeIntervalSince(lr) < minSecondsBetweenBackgroundRuns {
            return
        }

        // Need some hints to shape anything.
        let hintBlock = realmStore.compressedHintContext(limit: 10, maxChars: 1000)
        if hintBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        // Additional time gate for actual state patches.
        let canPatchTime = (lastStatePatchAt == nil) || (Date().timeIntervalSince(lastStatePatchAt!) >= minSecondsBetweenStatePatches)
        if !canPatchTime { return }

        lastBackgroundRunAt = Date()

        let prompt = buildBackgroundStatePrompt(hints: hintBlock)
        let raw = await llmCall(prompt)
        let clean = sanitizeJSONBlock(raw)

        guard let data = clean.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RealmBackgroundJSON.self, from: data) else {
            return
        }

        if decoded.noop == true { return }
        guard let patch = decoded.statePatch else { return }

        let pconf = max(0.0, min(1.0, patch.confidence ?? 0.0))
        if pconf < 0.80 { return }

        func cleanShort(_ s: String?, max: Int) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let tt = t, !tt.isEmpty else { return nil }
            return tt.count > max ? String(tt.prefix(max)) : tt
        }

        let newLoc = cleanShort(patch.location, max: 32)
        let newMotif = cleanShort(patch.motif, max: 32)
        let newArc = cleanShort(patch.arc, max: 48)

        guard (newLoc != nil || newMotif != nil || newArc != nil) else { return }

        var st = realmStore.loadState()
        if let v = newLoc { st.location = v }
        if let v = newMotif { st.motif = v }
        if let v = newArc { st.arc = v }
        st.updatedAt = Date()
        realmStore.saveState(st)
        lastStatePatchAt = Date()

        #if DEBUG
        let pconfStr = String(format: "%.2f", pconf)
        print("[ProactiveNarrator] bgStatePatch conf=\(pconfStr) loc=\(st.location ?? "-") motif=\(st.motif ?? "-") arc=\(st.arc ?? "-")")
        #endif
    }

    private func buildBackgroundStatePrompt(hints: String) -> String {
        return """
You are a background realm state shaper for a companion AI.
Your job: occasionally propose a tiny update to RealmState (location/motif/arc) to preserve continuity.

Rules:
- Output STRICT JSON only (no markdown, no code fences).
- Either {\"noop\": true} OR {\"noop\": false, \"statePatch\": {...}}.
- Do NOT invent unrelated themes. Derive ONLY from the provided hints.
- Keep fields SHORT: location<=32 chars, motif<=32 chars, arc<=48 chars.
- Avoid frequent changes.

RecentRealmHints:
\(hints)

JSON schema:
{
  \"noop\": Bool,
  \"statePatch\": {
    \"location\": String?,
    \"motif\": String?,
    \"arc\": String?,
    \"confidence\": Number
  }?
}

Return JSON only:
"""
    }

    private func sanitizeJSONBlock(_ raw: String) -> String {
        // Strip ```json fences if model adds them
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // remove first fence line
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            // remove trailing ```
            if let fence = s.range(of: "```", options: .backwards) {
                s = String(s[..<fence.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
