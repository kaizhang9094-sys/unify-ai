import Foundation

/// Phase 7 (Identity Overlay): proposals are created from evidence, reviewed/gated, then optionally applied.
///
/// Backwards compatibility note:
/// - `kind`, `text`, and `knob` are the legacy v1 proposal payload.
/// - Newer proposal generators should prefer `patches` + evidence/stability/support fields.
struct IdentityProposal: Identifiable, Codable, Hashable {

    // MARK: - Legacy payload (v1)

    enum Kind: String, Codable {
        case addRule
        case addDoNot
        case adjustKnob
    }

    struct KnobChange: Codable, Hashable {
        /// Legacy knob key, e.g. "warmth", "directness", "initiative", "figurative", "refusalBias", "questionBudget".
        var key: String
        /// New value (typically 0..1 for most knobs; questionBudget may be an int encoded as double).
        var value: Double
    }

    // MARK: - Proposal scope + lifecycle

    enum Scope: String, Codable {
        /// App-level editable policy (while core invariants remain locked in code).
        case platformPolicy
        /// User-defined character identity (name/persona/baseline text).
        case character
        /// Adaptive overlay (learned patches).
        case overlay
    }

    enum Status: String, Codable {
        case proposed
        case applied
        case rejected
        case superseded
    }

    // MARK: - Evidence + gating stats

    struct SupportStats: Codable, Hashable {
        /// Number of distinct evidence events supporting this proposal.
        var supportCount: Int
        /// Approximate number of distinct days spanned by the evidence.
        var distinctDays: Int
        /// Earliest evidence timestamp (if known).
        var firstSeenAt: Date?
        /// Latest evidence timestamp (if known).
        var lastSeenAt: Date?

        init(supportCount: Int = 0, distinctDays: Int = 0, firstSeenAt: Date? = nil, lastSeenAt: Date? = nil) {
            self.supportCount = supportCount
            self.distinctDays = distinctDays
            self.firstSeenAt = firstSeenAt
            self.lastSeenAt = lastSeenAt
        }
    }

    struct GateStats: Codable, Hashable {
        /// A 0..1 estimate of how stable this change is across time.
        var stabilityScore: Double
        /// A 0..1 estimate of internal contradiction risk (higher = worse).
        var contradictionScore: Double
        /// Optional window size the generator used (days).
        var windowDays: Int?

        init(stabilityScore: Double = 0.0, contradictionScore: Double = 0.0, windowDays: Int? = nil) {
            self.stabilityScore = stabilityScore
            self.contradictionScore = contradictionScore
            self.windowDays = windowDays
        }
    }

    // MARK: - Rich patches (v2+)

    /// A general patch that can be applied to identity/overlay without baking behavior into code.
    /// Keep this payload simple and data-driven; interpretation happens in IdentityVault/Composer.
    struct IdentityPatch: Identifiable, Codable, Hashable {
        enum Kind: String, Codable {
            // Rules / constraints
            case addRule
            case removeRule
            case addDoNot
            case removeDoNot

            // Knobs
            case setKnob        // `key` + `number`
            case deltaKnob      // `key` + `number` (delta)
            case setQuestionBudget // `intNumber`

            // Mode / strategy
            case addModeTrigger     // `key` = trigger phrase, `text` = mode id
            case removeModeTrigger  // `key` = trigger phrase
            case setConversationStrategy // `text` = strategy id (e.g. quick/deep/story)

            // Exemplars (few-shot anchors)
            case addExemplar     // `text` = exemplar, optional `key` = tag
            case removeExemplar  // `key` = exemplar id/tag

            // Memory routing / retrieval policy
            case setRetrievalPolicy // `json`

            // Character identity updates
            case setCharacterName       // `text`
            case setCharacterBaseline   // `text`
            case setPlatformPolicy      // `text`
        }

        let id: String
        var kind: Kind

        /// Generic key (knob key, trigger phrase, tag, etc.).
        var key: String?
        /// Generic text payload (rule text, baseline text, exemplar text, etc.).
        var text: String?
        /// Generic numeric payload (knob value or delta).
        var number: Double?
        /// Generic int payload (question budget, etc.).
        var intNumber: Int?
        /// Optional list payload.
        var strings: [String]?
        /// Optional JSON payload for structured policies.
        var json: String?

        init(
            id: String = UUID().uuidString,
            kind: Kind,
            key: String? = nil,
            text: String? = nil,
            number: Double? = nil,
            intNumber: Int? = nil,
            strings: [String]? = nil,
            json: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.key = key
            self.text = text
            self.number = number
            self.intNumber = intNumber
            self.strings = strings
            self.json = json
        }
    }

    // MARK: - Core fields

    let id: String
    let createdAt: Date
    
    /// Where this proposal intends to apply.
    var scope: Scope

    /// Current lifecycle status.
    /// For legacy callers, `appliedAt != nil` still implies applied.
    var status: Status

    // Legacy discriminator (v1)
    var kind: Kind

    // Legacy payload (v1)
    var text: String?
    var knob: KnobChange?

    // New payload (v2+)
    var patches: [IdentityPatch]?

    // Traceability (v1)
    var evidence: String
    var confidence: Double
    var appliedAt: Date?

    // Traceability (v2+)
    /// References to `mem_items.id` that support this proposal.
    var evidenceMemIds: [String]?
    /// Optional turn ids that produced the evidence.
    var evidenceTurnIds: [String]?
    /// Generator support stats (counts, span).
    var support: SupportStats?
    /// Gating stats (stability, contradictions, window).
    var gate: GateStats?

    /// Optional expiry for auto-sunsetting temporary patches.
    var expiresAt: Date?

    var isApplied: Bool { appliedAt != nil || status == .applied }

    // MARK: - Initializers

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        scope: Scope = .overlay,
        status: Status = .proposed,
        kind: Kind,
        text: String? = nil,
        knob: KnobChange? = nil,
        patches: [IdentityPatch]? = nil,
        evidence: String,
        confidence: Double,
        appliedAt: Date? = nil,
        evidenceMemIds: [String]? = nil,
        evidenceTurnIds: [String]? = nil,
        support: SupportStats? = nil,
        gate: GateStats? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.scope = scope
        self.status = status
        self.kind = kind
        self.text = text
        self.knob = knob
        self.patches = patches
        self.evidence = evidence
        self.confidence = confidence
        self.appliedAt = appliedAt
        self.evidenceMemIds = evidenceMemIds
        self.evidenceTurnIds = evidenceTurnIds
        self.support = support
        self.gate = gate
        self.expiresAt = expiresAt
    }

    // MARK: - Codable (backward compatible defaults)

    /// Ensure older JSON files (missing new fields) decode safely.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()

        self.scope = (try? c.decode(Scope.self, forKey: .scope)) ?? .overlay
        self.status = (try? c.decode(Status.self, forKey: .status)) ?? .proposed

        self.kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .addRule

        self.text = try? c.decodeIfPresent(String.self, forKey: .text)
        self.knob = try? c.decodeIfPresent(KnobChange.self, forKey: .knob)
        self.patches = try? c.decodeIfPresent([IdentityPatch].self, forKey: .patches)

        self.evidence = (try? c.decode(String.self, forKey: .evidence)) ?? ""
        self.confidence = (try? c.decode(Double.self, forKey: .confidence)) ?? 0.5
        self.appliedAt = try? c.decodeIfPresent(Date.self, forKey: .appliedAt)

        self.evidenceMemIds = try? c.decodeIfPresent([String].self, forKey: .evidenceMemIds)
        self.evidenceTurnIds = try? c.decodeIfPresent([String].self, forKey: .evidenceTurnIds)
        self.support = try? c.decodeIfPresent(SupportStats.self, forKey: .support)
        self.gate = try? c.decodeIfPresent(GateStats.self, forKey: .gate)
        self.expiresAt = try? c.decodeIfPresent(Date.self, forKey: .expiresAt)

        // Legacy compatibility: if appliedAt exists but status wasn't stored, treat as applied.
        if self.appliedAt != nil, (try? c.decodeIfPresent(Status.self, forKey: .status)) == nil {
            self.status = .applied
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(scope, forKey: .scope)
        try c.encode(status, forKey: .status)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(knob, forKey: .knob)
        try c.encodeIfPresent(patches, forKey: .patches)
        try c.encode(evidence, forKey: .evidence)
        try c.encode(confidence, forKey: .confidence)
        try c.encodeIfPresent(appliedAt, forKey: .appliedAt)
        try c.encodeIfPresent(evidenceMemIds, forKey: .evidenceMemIds)
        try c.encodeIfPresent(evidenceTurnIds, forKey: .evidenceTurnIds)
        try c.encodeIfPresent(support, forKey: .support)
        try c.encodeIfPresent(gate, forKey: .gate)
        try c.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt
        case scope, status
        case kind, text, knob
        case patches
        case evidence, confidence, appliedAt
        case evidenceMemIds, evidenceTurnIds
        case support, gate
        case expiresAt
    }
}
