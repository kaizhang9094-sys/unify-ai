import Foundation

/// Canonical requester-side gap between multi-faceted user intent and a selected public surface.
public struct ExchangeRequesterIntentGap: Sendable, Hashable, Identifiable {
    public var id: UUID

    /// Stable key for dedupe (kind + normalized requested value).
    public var stableKey: String

    public var kind: Kind
    public var status: Status

    /// Short human-readable label (e.g. "Timing", "Insurance").
    public var label: String

    /// What the requester asked for (verbatim or compact paraphrase).
    public var requestedValue: String

    /// Supporting evidence from offer/profile/memory/match when status is satisfied or mismatch.
    public var evidence: String?

    /// Optional single-sentence question suitable for provider clarification.
    public var questionForProvider: String?

    /// Lower sorts earlier (more urgent).
    public var priority: Int

    /// Provenance: `canonicalIntent`, `constraint`, `llmCompare`, `matchCaution`, …
    public var source: String

    public init(
        id: UUID = UUID(),
        stableKey: String,
        kind: Kind,
        status: Status,
        label: String,
        requestedValue: String,
        evidence: String? = nil,
        questionForProvider: String? = nil,
        priority: Int,
        source: String
    ) {
        self.id = id
        self.stableKey = stableKey
        self.kind = kind
        self.status = status
        self.label = label
        self.requestedValue = requestedValue
        self.evidence = Self.nonBlank(evidence)
        self.questionForProvider = Self.nonBlank(questionForProvider)
        self.priority = priority
        self.source = source
    }
}

public extension ExchangeRequesterIntentGap {
    enum Kind: String, Sendable, Hashable, CaseIterable {
        case service
        case region
        case timing
        case budget
        case credential
        case taskDetail
        case availability
        case policy
        case preference
        case other
    }

    enum Status: String, Sendable, Hashable, CaseIterable {
        case satisfied
        case unknown
        case mismatch
        case optionalUnknown
    }
}

private extension ExchangeRequesterIntentGap {
    static func nonBlank(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
