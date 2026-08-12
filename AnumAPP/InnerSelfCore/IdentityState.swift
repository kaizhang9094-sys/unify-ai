import Foundation

// Frequently updated learned state (small + structured)
//
// Phase 7+:
// - Keep legacy knobs + learnedRules/learnedDoNot for backward compatibility.
// - Add an applied patch set for richer, data-driven identity/overlay evolution.
struct IdentityState: Codable, Hashable {
    var version: Int
    var updatedAt: Date

    // MARK: - Legacy compact adaptive knobs (tunable, traceable)

    var warmth: Double          // 0..1
    var directness: Double      // 0..1
    var initiative: Double      // 0..1
    var figurative: Double      // 0..1
    var questionBudget: Int     // e.g. 0..2
    var refusalBias: Double     // 0..1

    // Small additive notes (kept bounded)
    var learnedRules: [String]  // 0..N, each short
    var learnedDoNot: [String]  // 0..N, each short

    // MARK: - Phase 7+ applied overlay (richer than knobs)

    /// Applied identity patches, interpreted by IdentityVault/Composer.
    /// These are persisted and versioned; proposals are separate.
    var appliedPatches: [IdentityProposal.IdentityPatch]

    // MARK: - Phase 7+ adaptive attributes (learner-driven, flexible key/value)

    /// A flexible, persisted attribute store for learner-driven identity.
    /// Keys are dot-delimited (e.g., "relationship.status", "persona.traits", "values.hierarchy", "tone.emotional_tone").
    /// This avoids hard-coding enums while still allowing structured stability controls.
    struct AdaptiveAttribute: Codable, Hashable {
        var value: String
        var confidence: Double          // 0..1
        var supportCount: Int           // reinforcing hits
        var distinctDays: Int           // day-bucketed reinforcement count
        var ema: Double                 // 0..1 smoothing
        var updatedAt: Date
        var lastReinforcedAt: Date?
        var source: String?             // "learner" | "explicit" | "heuristic" (optional)

        static func `default`(value: String, confidence: Double, source: String?) -> AdaptiveAttribute {
            AdaptiveAttribute(
                value: value,
                confidence: max(0.0, min(1.0, confidence)),
                supportCount: 1,
                distinctDays: 1,
                ema: max(0.0, min(1.0, confidence)),
                updatedAt: Date(),
                lastReinforcedAt: Date(),
                source: source
            )
        }
    }

    /// Active learner-driven identity attributes.
    var adaptiveAttributes: [String: AdaptiveAttribute]

    /// Anti-swing daily change budget bookkeeping.
    /// `lastChangeDay` uses a stable YYYY-MM-DD string in local time.
    var lastChangeDay: String?
    var changesToday: Int

    /// Optional bookkeeping to support scheduled evolution.
    /// - lastProposalRunAt: last time we *attempted* to generate a proposal (may produce none)
    /// - lastProposalAcceptedAt: last time the user accepted/applied a proposal
    /// - lastLearnerAttemptAt: last time the self-learning proposer was invoked (rate limit)
    var lastProposalRunAt: Date?
    var lastProposalAcceptedAt: Date?
    var lastLearnerAttemptAt: Date?
    var lastAppliedAt: Date?

    // MARK: - Prompt budget hygiene (keeps identity overlays compact)

    private static let maxLearnedRulesCount = 10
    private static let maxLearnedDoNotCount = 10
    private static let maxAppliedPatchesCount = 10
    private static let maxAdaptiveAttributesCount = 24
    private static let maxAdaptiveKeyChars = 48
    private static let maxAdaptiveValueChars = 220

    private static func clip(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        return String(t.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func dedupePreserveOrder(_ arr: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(arr.count)
        for raw in arr {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if seen.insert(t).inserted {
                out.append(t)
            }
        }
        return out
    }

    /// Clamp, de-dupe, and cap fields so downstream system/overlay text stays small.
    /// Safe to call repeatedly.
    mutating func sanitizeForPromptBudget(now: Date = Date()) {
        // Clamp knobs to their intended ranges.
        warmth = max(0.0, min(1.0, warmth))
        directness = max(0.0, min(1.0, directness))
        initiative = max(0.0, min(1.0, initiative))
        figurative = max(0.0, min(1.0, figurative))
        refusalBias = max(0.0, min(1.0, refusalBias))
        questionBudget = max(0, min(2, questionBudget))

        // Keep rule lists short, clean, and unique.
        learnedRules = Self.dedupePreserveOrder(learnedRules).map { Self.clip($0, max: 120) }
        if learnedRules.count > Self.maxLearnedRulesCount {
            learnedRules = Array(learnedRules.prefix(Self.maxLearnedRulesCount))
        }

        learnedDoNot = Self.dedupePreserveOrder(learnedDoNot).map { Self.clip($0, max: 120) }
        if learnedDoNot.count > Self.maxLearnedDoNotCount {
            learnedDoNot = Array(learnedDoNot.prefix(Self.maxLearnedDoNotCount))
        }

        // Keep applied patches bounded (prefer recency).
        if appliedPatches.count > Self.maxAppliedPatchesCount {
            appliedPatches = Array(appliedPatches.suffix(Self.maxAppliedPatchesCount))
        }

        // Keep adaptive attributes bounded and small.
        // Drop extremely low-confidence entries and cap key/value lengths.
        var cleaned: [(key: String, val: AdaptiveAttribute)] = []
        cleaned.reserveCapacity(adaptiveAttributes.count)
        for (kRaw, vRaw) in adaptiveAttributes {
            let k0 = kRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k0.isEmpty else { continue }
            let k = Self.clip(k0, max: Self.maxAdaptiveKeyChars)
            var v = vRaw
            // Normalize value and confidence bounds.
            v.value = Self.clip(v.value, max: Self.maxAdaptiveValueChars)
            v.confidence = max(0.0, min(1.0, v.confidence))
            v.ema = max(0.0, min(1.0, v.ema))
            v.supportCount = max(0, v.supportCount)
            v.distinctDays = max(0, v.distinctDays)
            if v.updatedAt > now.addingTimeInterval(60) { v.updatedAt = now }
            if let lr = v.lastReinforcedAt, lr > now.addingTimeInterval(60) { v.lastReinforcedAt = now }

            // Skip low-signal attributes to protect prompt budget.
            if v.confidence < 0.35 && v.ema < 0.35 && v.supportCount < 2 {
                continue
            }
            cleaned.append((key: k, val: v))
        }

        // Sort by signal strength and keep top N.
        cleaned.sort { (a, b) -> Bool in
            let sa = (a.val.ema * 0.6) + (a.val.confidence * 0.4) + Double(min(10, a.val.supportCount)) * 0.03
            let sb = (b.val.ema * 0.6) + (b.val.confidence * 0.4) + Double(min(10, b.val.supportCount)) * 0.03
            return sa > sb
        }
        if cleaned.count > Self.maxAdaptiveAttributesCount {
            cleaned = Array(cleaned.prefix(Self.maxAdaptiveAttributesCount))
        }
        adaptiveAttributes = Dictionary(uniqueKeysWithValues: cleaned.map { ($0.key, $0.val) })
    }

    // MARK: - Memberwise init (needed because we implement init(from:), which disables the synthesized memberwise init)
    init(
        version: Int,
        updatedAt: Date,
        warmth: Double,
        directness: Double,
        initiative: Double,
        figurative: Double,
        questionBudget: Int,
        refusalBias: Double,
        learnedRules: [String],
        learnedDoNot: [String],
        appliedPatches: [IdentityProposal.IdentityPatch],
        lastProposalRunAt: Date?,
        lastProposalAcceptedAt: Date?,
        lastLearnerAttemptAt: Date?,
        lastAppliedAt: Date?,
        adaptiveAttributes: [String: AdaptiveAttribute],
        lastChangeDay: String?,
        changesToday: Int
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.warmth = warmth
        self.directness = directness
        self.initiative = initiative
        self.figurative = figurative
        self.questionBudget = questionBudget
        self.refusalBias = refusalBias
        self.learnedRules = learnedRules
        self.learnedDoNot = learnedDoNot
        self.appliedPatches = appliedPatches
        self.lastProposalRunAt = lastProposalRunAt
        self.lastProposalAcceptedAt = lastProposalAcceptedAt
        self.lastLearnerAttemptAt = lastLearnerAttemptAt
        self.lastAppliedAt = lastAppliedAt
        self.adaptiveAttributes = adaptiveAttributes
        self.lastChangeDay = lastChangeDay
        self.changesToday = changesToday
    }

    static func `default`() -> IdentityState {
        IdentityState(
            version: 1,
            updatedAt: Date(),
            warmth: 0.55,
            directness: 0.70,
            initiative: 0.55,
            figurative: 0.25,
            questionBudget: 1,
            refusalBias: 0.15,
            learnedRules: [],
            learnedDoNot: [],
            appliedPatches: [],
            lastProposalRunAt: nil,
            lastProposalAcceptedAt: nil,
            lastLearnerAttemptAt: nil,
            lastAppliedAt: nil,
            adaptiveAttributes: [:],
            lastChangeDay: nil,
            changesToday: 0
        )
    }

    // MARK: - Codable (backward compatible defaults)

    /// Older identity_state.json files won't have the Phase 7+ fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        self.updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()

        self.warmth = (try? c.decode(Double.self, forKey: .warmth)) ?? 0.55
        self.directness = (try? c.decode(Double.self, forKey: .directness)) ?? 0.70
        self.initiative = (try? c.decode(Double.self, forKey: .initiative)) ?? 0.55
        self.figurative = (try? c.decode(Double.self, forKey: .figurative)) ?? 0.25
        self.questionBudget = (try? c.decode(Int.self, forKey: .questionBudget)) ?? 1
        self.refusalBias = (try? c.decode(Double.self, forKey: .refusalBias)) ?? 0.15

        self.learnedRules = (try? c.decode([String].self, forKey: .learnedRules)) ?? []
        self.learnedDoNot = (try? c.decode([String].self, forKey: .learnedDoNot)) ?? []

        self.appliedPatches = (try? c.decodeIfPresent([IdentityProposal.IdentityPatch].self, forKey: .appliedPatches)) ?? []
        self.lastProposalRunAt = try? c.decodeIfPresent(Date.self, forKey: .lastProposalRunAt)
        self.lastProposalAcceptedAt = try? c.decodeIfPresent(Date.self, forKey: .lastProposalAcceptedAt)
        self.lastLearnerAttemptAt = try? c.decodeIfPresent(Date.self, forKey: .lastLearnerAttemptAt)
        self.lastAppliedAt = try? c.decodeIfPresent(Date.self, forKey: .lastAppliedAt)

        self.adaptiveAttributes = (try? c.decode([String: AdaptiveAttribute].self, forKey: .adaptiveAttributes)) ?? [:]
        self.lastChangeDay = try? c.decodeIfPresent(String.self, forKey: .lastChangeDay)
        self.changesToday = (try? c.decode(Int.self, forKey: .changesToday)) ?? 0
        self.sanitizeForPromptBudget(now: Date())
    }

    func encode(to encoder: Encoder) throws {
        var s = self
        s.sanitizeForPromptBudget(now: Date())
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(s.version, forKey: .version)
        try c.encode(s.updatedAt, forKey: .updatedAt)

        try c.encode(s.warmth, forKey: .warmth)
        try c.encode(s.directness, forKey: .directness)
        try c.encode(s.initiative, forKey: .initiative)
        try c.encode(s.figurative, forKey: .figurative)
        try c.encode(s.questionBudget, forKey: .questionBudget)
        try c.encode(s.refusalBias, forKey: .refusalBias)

        try c.encode(s.learnedRules, forKey: .learnedRules)
        try c.encode(s.learnedDoNot, forKey: .learnedDoNot)

        try c.encode(s.appliedPatches, forKey: .appliedPatches)
        try c.encodeIfPresent(s.lastProposalRunAt, forKey: .lastProposalRunAt)
        try c.encodeIfPresent(s.lastProposalAcceptedAt, forKey: .lastProposalAcceptedAt)
        try c.encodeIfPresent(s.lastLearnerAttemptAt, forKey: .lastLearnerAttemptAt)
        try c.encodeIfPresent(s.lastAppliedAt, forKey: .lastAppliedAt)

        try c.encode(s.adaptiveAttributes, forKey: .adaptiveAttributes)
        try c.encodeIfPresent(s.lastChangeDay, forKey: .lastChangeDay)
        try c.encode(s.changesToday, forKey: .changesToday)
    }

    private enum CodingKeys: String, CodingKey {
        case version, updatedAt
        case warmth, directness, initiative, figurative, questionBudget, refusalBias
        case learnedRules, learnedDoNot
        case appliedPatches
        case lastProposalRunAt, lastProposalAcceptedAt, lastLearnerAttemptAt, lastAppliedAt
        case adaptiveAttributes
        case lastChangeDay, changesToday
    }
}
