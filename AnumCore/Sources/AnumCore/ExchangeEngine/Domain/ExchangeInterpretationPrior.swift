import Foundation

/// Retrieval-backed interpretation prior for Exchange.
///
/// Purpose:
/// - carry the semantic prior produced before real surface retrieval
/// - keep it compact, inspectable, and cheap to persist/log
/// - bias downstream retrieval/query building without becoming semantic truth
///
/// Design rules:
/// - this is a soft prior, not a hard classifier
/// - raw user text remains first-class
/// - ambiguity must stay visible
/// - downstream layers may ignore or override weak prior signals
public struct ExchangeInterpretationPrior: Codable, Sendable, Hashable {
    /// Operational facts from the structural gate.
    public var structural: StructuralGate

    /// Main prior guess from exemplar retrieval.
    public var primaryQueryIntentClass: ExchangeIntent.QueryIntentClass
    public var primarySurfacePreference: ExchangeIntent.SurfacePreference

    /// Optional secondary lane when evidence is mixed.
    public var secondaryQueryIntentClass: ExchangeIntent.QueryIntentClass?
    public var secondarySurfacePreference: ExchangeIntent.SurfacePreference?

    /// Optional semantic/routing biases inferred from exemplar evidence.
    public var targetKindBias: ExchangeIntentFacets.TargetKind?
    public var fulfillmentBias: ExchangeIntentFacets.FulfillmentMode?

    /// Compact semantic hints carried forward as soft routing aids only.
    public var semanticHints: [String]

    /// Exemplar evidence summary.
    public var exemplarHits: [ExemplarHit]

    /// Confidence and ambiguity must be explicit.
    public var confidence: Double
    public var ambiguity: Ambiguity

    /// Whether the prior is strong enough to drive retrieval without LLM help.
    public var shouldEscalateToLLM: Bool

    /// Human/log-readable explanation of what the prior is saying.
    public var notes: String?

    public init(
        structural: StructuralGate = .init(),
        primaryQueryIntentClass: ExchangeIntent.QueryIntentClass = .generalDiscovery,
        primarySurfacePreference: ExchangeIntent.SurfacePreference = .mixed,
        secondaryQueryIntentClass: ExchangeIntent.QueryIntentClass? = nil,
        secondarySurfacePreference: ExchangeIntent.SurfacePreference? = nil,
        targetKindBias: ExchangeIntentFacets.TargetKind? = nil,
        fulfillmentBias: ExchangeIntentFacets.FulfillmentMode? = nil,
        semanticHints: [String] = [],
        exemplarHits: [ExemplarHit] = [],
        confidence: Double = 0.0,
        ambiguity: Ambiguity = .unknown,
        shouldEscalateToLLM: Bool = false,
        notes: String? = nil
    ) {
        self.structural = structural
        self.primaryQueryIntentClass = primaryQueryIntentClass
        self.primarySurfacePreference = primarySurfacePreference
        self.secondaryQueryIntentClass = secondaryQueryIntentClass
        self.secondarySurfacePreference = secondarySurfacePreference
        self.targetKindBias = targetKindBias
        self.fulfillmentBias = fulfillmentBias
        self.semanticHints = Self.normalizeHints(semanticHints, maxCount: 16)
        self.exemplarHits = Array(exemplarHits.prefix(8))
        self.confidence = Self.clamp(confidence)
        self.ambiguity = ambiguity
        self.shouldEscalateToLLM = shouldEscalateToLLM
        self.notes = notes?.exchangePriorNilIfBlank.map { String($0.prefix(300)) }
    }
}

public extension ExchangeInterpretationPrior {
    struct StructuralGate: Codable, Sendable, Hashable {
        /// Existing-thread / direct-lane facts only.
        public var selectedCounterpartyPresent: Bool
        public var isResumingExistingThread: Bool

        /// Literal constraints only.
        public var literalConstraints: [ExchangeIntent.Constraint]

        /// Explicit timing/privacy flags that are operationally obvious.
        public var urgencyBias: UrgencyBias?
        public var privacyBias: PrivacyBias?

        public init(
            selectedCounterpartyPresent: Bool = false,
            isResumingExistingThread: Bool = false,
            literalConstraints: [ExchangeIntent.Constraint] = [],
            urgencyBias: UrgencyBias? = nil,
            privacyBias: PrivacyBias? = nil
        ) {
            self.selectedCounterpartyPresent = selectedCounterpartyPresent
            self.isResumingExistingThread = isResumingExistingThread
            self.literalConstraints = Self.normalizeConstraints(literalConstraints)
            self.urgencyBias = urgencyBias
            self.privacyBias = privacyBias
        }
    }

    enum UrgencyBias: String, Codable, Sendable, CaseIterable, Hashable {
        case immediate
        case high
        case normal
        case low
    }

    enum PrivacyBias: String, Codable, Sendable, CaseIterable, Hashable {
        case guarded
        case balanced
        case open
    }

    enum Ambiguity: String, Codable, Sendable, CaseIterable, Hashable {
        case low
        case medium
        case high
        case unknown
    }

    struct ExemplarHit: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var exemplarID: String
        public var rawExampleText: String
        public var queryIntentClass: ExchangeIntent.QueryIntentClass
        public var surfacePreference: ExchangeIntent.SurfacePreference
        public var targetKindBias: ExchangeIntentFacets.TargetKind?
        public var fulfillmentBias: ExchangeIntentFacets.FulfillmentMode?
        public var semanticHints: [String]

        /// Provenance from the exemplar retrieval layer.
        public var fusedScore: Double
        public var contributingSources: [String]
        public var bestRankBySource: [String: Int]

        public init(
            id: String? = nil,
            exemplarID: String,
            rawExampleText: String,
            queryIntentClass: ExchangeIntent.QueryIntentClass,
            surfacePreference: ExchangeIntent.SurfacePreference,
            targetKindBias: ExchangeIntentFacets.TargetKind? = nil,
            fulfillmentBias: ExchangeIntentFacets.FulfillmentMode? = nil,
            semanticHints: [String] = [],
            fusedScore: Double,
            contributingSources: [String] = [],
            bestRankBySource: [String: Int] = [:]
        ) {
            self.exemplarID = exemplarID
            self.id = id ?? exemplarID
            self.rawExampleText = rawExampleText.exchangePriorNilIfBlank
                .map { String($0.prefix(220)) } ?? ""
            self.queryIntentClass = queryIntentClass
            self.surfacePreference = surfacePreference
            self.targetKindBias = targetKindBias
            self.fulfillmentBias = fulfillmentBias
            self.semanticHints = ExchangeInterpretationPrior.normalizeHints(semanticHints, maxCount: 10)
            self.fusedScore = max(0.0, fusedScore)
            self.contributingSources = Array(contributingSources.prefix(4))
            self.bestRankBySource = bestRankBySource
        }
    }
}

public extension ExchangeInterpretationPrior {
    var hasSecondaryLane: Bool {
        secondaryQueryIntentClass != nil
    }

    var hasStrongPrimary: Bool {
        confidence >= 0.72 && ambiguity == .low
    }

    var isMixed: Bool {
        switch ambiguity {
        case .medium, .high:
            return true
        case .low, .unknown:
            return false
        }
    }

    var allSemanticHints: [String] {
        var values = semanticHints
        for hit in exemplarHits {
            values.append(contentsOf: hit.semanticHints)
        }
        return Self.normalizeHints(values, maxCount: 24)
    }

    var summaryLine: String {
        var parts: [String] = [
            "primary=\(primaryQueryIntentClass.rawValue)",
            "surface=\(primarySurfacePreference.rawValue)",
            "confidence=\(String(format: "%.2f", confidence))",
            "ambiguity=\(ambiguity.rawValue)"
        ]

        if let secondaryQueryIntentClass {
            parts.append("secondary=\(secondaryQueryIntentClass.rawValue)")
        }

        if shouldEscalateToLLM {
            parts.append("llm=yes")
        } else {
            parts.append("llm=no")
        }

        return parts.joined(separator: " ")
    }

    func withLLMEscalation(_ value: Bool) -> ExchangeInterpretationPrior {
        var copy = self
        copy.shouldEscalateToLLM = value
        return copy
    }

    func withNotes(_ value: String?) -> ExchangeInterpretationPrior {
        var copy = self
        copy.notes = value?.exchangePriorNilIfBlank.map { String($0.prefix(300)) }
        return copy
    }
}

private extension ExchangeInterpretationPrior {
    static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    static func normalizeHints(
        _ values: [String],
        maxCount: Int
    ) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for raw in values {
            guard let cleaned = raw.exchangePriorNilIfBlank?
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            else {
                continue
            }

            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }

            seen.insert(key)
            output.append(String(cleaned.prefix(120)))

            if output.count >= maxCount {
                break
            }
        }

        return output
    }
}

private extension ExchangeInterpretationPrior.StructuralGate {
    static func normalizeConstraints(
        _ values: [ExchangeIntent.Constraint]
    ) -> [ExchangeIntent.Constraint] {
        var seen = Set<String>()
        var output: [ExchangeIntent.Constraint] = []

        for item in values {
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !key.isEmpty, !value.isEmpty else { continue }

            let dedupe = "\(key.lowercased())|||\(value.lowercased())|||\(item.isHardConstraint)"
            guard !seen.contains(dedupe) else { continue }

            seen.insert(dedupe)
            output.append(
                ExchangeIntent.Constraint(
                    id: item.id,
                    key: String(key.prefix(80)),
                    value: String(value.prefix(200)),
                    isHardConstraint: item.isHardConstraint
                )
            )

            if output.count >= 12 {
                break
            }
        }

        return output
    }
}

private extension String {
    var exchangePriorNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
