import Foundation

/// Evaluated candidate result for a specific thread or discovery pass.
///
/// A match is not just "found or not found".
/// It captures:
/// - relevance
/// - fit quality
/// - trust contribution
/// - reasons for selection
/// - reasons for hesitation
/// - the scope of what was actually matched
/// - which public surface dominated the match
/// - what query class shaped the evaluation
///
/// This is a core part of legible discovery.
public struct ExchangeMatch: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var threadID: ExchangeThread.ID
    public var counterpartyID: ExchangeCounterparty.ID
    public var createdAt: Date

    /// What level this match is actually about.
    public var scope: Scope

    /// Optional attached public profile for this match.
    public var publicProfileID: String?

    /// Optional primary offer that this match is centered on.
    public var offerID: String?

    /// Optional surfaced offers relevant to this match.
    /// Keep ordered, with the first item usually representing the strongest offer candidate.
    public var matchedOfferIDs: [String]

    /// Offer IDs proven by `offer_object` embedding evidence for concrete object searches.
    public var provenObjectOfferIDs: [String]

    /// Object-lane cosine scores keyed by offer ID.
    public var objectEvidenceScoreByOfferID: [String: Double]

    public var status: Status
    public var strength: Strength

    /// Normalized score for ranking. Keep interpretation stable.
    public var score: Double

    /// Query-class framing that shaped this evaluation.
    /// Canonical ownership lives in ExchangeIntent.
    public var queryIntentClass: ExchangeIntent.QueryIntentClass?

    /// Dominant public surface under which this match was evaluated.
    /// Canonical ownership lives in ExchangeIntent.
    public var dominantSurface: ExchangeIntent.SurfacePreference?

    /// Why this candidate appears relevant.
    public var reasons: [Reason]

    /// Why this candidate may not be ideal.
    public var cautions: [Caution]

    /// Structured fit dimensions for this match record.
    public var fit: FitSnapshot

    /// Optional recommendation text for why this match should or should not advance.
    public var recommendation: String?

    public var metadata: [String: String]

    /// Semantic attach proof carried from discovery projection through fit and child coordination.
    public var semanticProof: ExchangeCandidateSemanticProof?

    public init(
        id: ID = UUID(),
        threadID: ExchangeThread.ID,
        counterpartyID: ExchangeCounterparty.ID,
        createdAt: Date = Date(),
        scope: Scope = .counterparty,
        publicProfileID: String? = nil,
        offerID: String? = nil,
        matchedOfferIDs: [String] = [],
        provenObjectOfferIDs: [String] = [],
        objectEvidenceScoreByOfferID: [String: Double] = [:],
        status: Status = .candidate,
        strength: Strength,
        score: Double,
        queryIntentClass: ExchangeIntent.QueryIntentClass? = nil,
        dominantSurface: ExchangeIntent.SurfacePreference? = nil,
        reasons: [Reason] = [],
        cautions: [Caution] = [],
        fit: FitSnapshot = .empty,
        recommendation: String? = nil,
        metadata: [String: String] = [:],
        semanticProof: ExchangeCandidateSemanticProof? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.counterpartyID = counterpartyID
        self.createdAt = createdAt
        self.scope = scope
        self.publicProfileID = publicProfileID?.exchangeNilIfBlank
        self.offerID = offerID?.exchangeNilIfBlank
        self.matchedOfferIDs = Self.normalizedIDs(matchedOfferIDs)
        self.provenObjectOfferIDs = Self.normalizedIDs(provenObjectOfferIDs)
        self.objectEvidenceScoreByOfferID = objectEvidenceScoreByOfferID
        self.status = status
        self.strength = strength
        self.score = Self.clampedScore(score)
        self.queryIntentClass = queryIntentClass
        self.dominantSurface = dominantSurface
        self.reasons = reasons
        self.cautions = cautions
        self.fit = fit
        self.recommendation = recommendation?.exchangeNilIfBlank
        self.metadata = metadata
        self.semanticProof = semanticProof

        // Keep the object internally coherent.
        if self.scope == .offer && self.offerID == nil {
            if !self.provenObjectOfferIDs.isEmpty {
                self.offerID = ExchangeOfferObjectLane.resolveSelectedOfferID(
                    provenObjectOfferIDs: Set(self.provenObjectOfferIDs),
                    objectEvidenceScoreByOfferID: self.objectEvidenceScoreByOfferID
                )
            } else if !self.matchedOfferIDs.isEmpty {
                self.offerID = self.matchedOfferIDs.first
            }
        }
    }
}

// MARK: - Backward-compatible persistence decoding

extension ExchangeMatch {
    private enum CodingKeys: String, CodingKey {
        case id
        case threadID
        case counterpartyID
        case createdAt
        case scope
        case publicProfileID
        case offerID
        case matchedOfferIDs
        case provenObjectOfferIDs
        case objectEvidenceScoreByOfferID
        case status
        case strength
        case score
        case queryIntentClass
        case dominantSurface
        case reasons
        case cautions
        case fit
        case recommendation
        case metadata
        case semanticProof
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(ID.self, forKey: .id)
        let threadID = try container.decode(ExchangeThread.ID.self, forKey: .threadID)
        let counterpartyID = try container.decode(ExchangeCounterparty.ID.self, forKey: .counterpartyID)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let scope = try container.decode(Scope.self, forKey: .scope)
        let publicProfileID = try container.decodeIfPresent(String.self, forKey: .publicProfileID)
        let offerID = try container.decodeIfPresent(String.self, forKey: .offerID)
        let matchedOfferIDs = try container.decodeIfPresent([String].self, forKey: .matchedOfferIDs) ?? []
        let provenObjectOfferIDs = try container.decodeIfPresent([String].self, forKey: .provenObjectOfferIDs) ?? []
        let objectEvidenceScoreByOfferID = try container.decodeIfPresent(
            [String: Double].self,
            forKey: .objectEvidenceScoreByOfferID
        ) ?? [:]
        let status = try container.decode(Status.self, forKey: .status)
        let strength = try container.decode(Strength.self, forKey: .strength)
        let score = try container.decode(Double.self, forKey: .score)
        let queryIntentClass = try container.decodeIfPresent(
            ExchangeIntent.QueryIntentClass.self,
            forKey: .queryIntentClass
        )
        let dominantSurface = try container.decodeIfPresent(
            ExchangeIntent.SurfacePreference.self,
            forKey: .dominantSurface
        )
        let reasons = try container.decodeIfPresent([Reason].self, forKey: .reasons) ?? []
        let cautions = try container.decodeIfPresent([Caution].self, forKey: .cautions) ?? []
        let fit = try container.decodeIfPresent(FitSnapshot.self, forKey: .fit) ?? .empty
        let recommendation = try container.decodeIfPresent(String.self, forKey: .recommendation)
        let metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        let semanticProof = try container.decodeIfPresent(
            ExchangeCandidateSemanticProof.self,
            forKey: .semanticProof
        )

        self.init(
            id: id,
            threadID: threadID,
            counterpartyID: counterpartyID,
            createdAt: createdAt,
            scope: scope,
            publicProfileID: publicProfileID,
            offerID: offerID,
            matchedOfferIDs: matchedOfferIDs,
            provenObjectOfferIDs: provenObjectOfferIDs,
            objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID,
            status: status,
            strength: strength,
            score: score,
            queryIntentClass: queryIntentClass,
            dominantSurface: dominantSurface,
            reasons: reasons,
            cautions: cautions,
            fit: fit,
            recommendation: recommendation,
            metadata: metadata,
            semanticProof: semanticProof
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(counterpartyID, forKey: .counterpartyID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(scope, forKey: .scope)
        try container.encodeIfPresent(publicProfileID, forKey: .publicProfileID)
        try container.encodeIfPresent(offerID, forKey: .offerID)
        try container.encode(matchedOfferIDs, forKey: .matchedOfferIDs)
        try container.encode(provenObjectOfferIDs, forKey: .provenObjectOfferIDs)
        try container.encode(objectEvidenceScoreByOfferID, forKey: .objectEvidenceScoreByOfferID)
        try container.encode(status, forKey: .status)
        try container.encode(strength, forKey: .strength)
        try container.encode(score, forKey: .score)
        try container.encodeIfPresent(queryIntentClass, forKey: .queryIntentClass)
        try container.encodeIfPresent(dominantSurface, forKey: .dominantSurface)
        try container.encode(reasons, forKey: .reasons)
        try container.encode(cautions, forKey: .cautions)
        try container.encode(fit, forKey: .fit)
        try container.encodeIfPresent(recommendation, forKey: .recommendation)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(semanticProof, forKey: .semanticProof)
    }
}

public extension ExchangeMatch {
    enum Scope: String, Codable, Sendable, CaseIterable, Hashable {
        case counterparty
        case publicProfile
        case offer
    }

    enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case candidate
        case shortlisted
        case selected
        case rejected
        case archived
    }

    enum Strength: String, Codable, Sendable, CaseIterable, Hashable {
        case weak
        case moderate
        case strong
    }

    struct Reason: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var kind: Kind
        public var summary: String

        public init(
            id: UUID = UUID(),
            kind: Kind,
            summary: String
        ) {
            self.id = id
            self.kind = kind
            self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
            case capability
            case location
            case timing
            case trust
            case tone
            case availability
            case specialization
            case sharedContext
            case offer
            case profile
            case other
        }
    }

    struct Caution: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var kind: Kind
        public var summary: String

        public init(
            id: UUID = UUID(),
            kind: Kind,
            summary: String
        ) {
            self.id = id
            self.kind = kind
            self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
            case weakFit
            case limitedTrust
            case unclearAvailability
            case priceMismatch
            case location
            case timing
            case toneMismatch
            case lowSignal
            case missingData
            case offerMismatch
            case profileWeakness
            case other
        }
    }

    /// Match-local fit breakdown.
    ///
    /// These scores are for explaining this specific candidate evaluation.
    /// They are not the source of truth for the global trust graph.
    struct FitSnapshot: Codable, Sendable, Hashable {
        public var retrievalFit: Double?
        public var surfaceFit: Double?
        public var offerFit: Double?
        public var capabilityFit: Double?
        public var affinityFit: Double?
        public var profileFit: Double?
        public var constraintFit: Double?
        public var trustFit: Double?
        public var postureFit: Double?
        public var timingFit: Double?

        public init(
            retrievalFit: Double? = nil,
            surfaceFit: Double? = nil,
            offerFit: Double? = nil,
            capabilityFit: Double? = nil,
            affinityFit: Double? = nil,
            profileFit: Double? = nil,
            constraintFit: Double? = nil,
            trustFit: Double? = nil,
            postureFit: Double? = nil,
            timingFit: Double? = nil
        ) {
            self.retrievalFit = retrievalFit.map { Self.clamp($0) }
            self.surfaceFit = surfaceFit.map { Self.clamp($0) }
            self.offerFit = offerFit.map { Self.clamp($0) }
            self.capabilityFit = capabilityFit.map { Self.clamp($0) }
            self.affinityFit = affinityFit.map { Self.clamp($0) }
            self.profileFit = profileFit.map { Self.clamp($0) }
            self.constraintFit = constraintFit.map { Self.clamp($0) }
            self.trustFit = trustFit.map { Self.clamp($0) }
            self.postureFit = postureFit.map { Self.clamp($0) }
            self.timingFit = timingFit.map { Self.clamp($0) }
        }

        public static let empty = FitSnapshot()

        public var average: Double? {
            let values = [
                retrievalFit,
                surfaceFit,
                offerFit,
                capabilityFit,
                affinityFit,
                profileFit,
                constraintFit,
                trustFit,
                postureFit,
                timingFit
            ].compactMap { $0 }

            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        public var strongestDimension: String? {
            let pairs: [(String, Double?)] = [
                ("retrieval", retrievalFit),
                ("surface", surfaceFit),
                ("offer", offerFit),
                ("capability", capabilityFit),
                ("affinity", affinityFit),
                ("profile", profileFit),
                ("constraint", constraintFit),
                ("trust", trustFit),
                ("posture", postureFit),
                ("timing", timingFit)
            ]

            return pairs
                .compactMap { label, value in value.map { (label, $0) } }
                .max(by: { $0.1 < $1.1 })?
                .0
        }

        private static func clamp(_ value: Double) -> Double {
            min(max(value, 0), 1)
        }
    }
}

public extension ExchangeMatch {
    /// Whether this candidate remains eligible to advance within the thread.
    ///
    /// Final advancement policy should still live in the fit/policy/orchestration
    /// layer, not only here.
    var isAdvanceable: Bool {
        switch status {
        case .candidate, .shortlisted, .selected:
            return true
        case .rejected, .archived:
            return false
        }
    }

    /// Conservative helper for identifying weak candidates in UI and summary logic.
    var isWeakMatch: Bool {
        strength == .weak
    }

    var hasMeaningfulCautions: Bool {
        !cautions.isEmpty
    }

    var hasOfferContext: Bool {
        offerID != nil || !matchedOfferIDs.isEmpty
    }

    var hasProfileContext: Bool {
        publicProfileID != nil
    }

    var hasSurfaceContext: Bool {
        dominantSurface != nil
    }

    var primaryMatchedOfferID: String? {
        if !provenObjectOfferIDs.isEmpty {
            return ExchangeOfferObjectLane.resolveSelectedOfferID(
                provenObjectOfferIDs: Set(provenObjectOfferIDs),
                objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID,
                preferredOfferID: offerID
            )
        }
        return offerID ?? matchedOfferIDs.first
    }

    var summaryLine: String {
        recommendation
            ?? reasons.first?.summary
            ?? "Match score: \(String(format: "%.2f", score))"
    }

    func selecting() -> ExchangeMatch {
        var copy = self
        copy.status = .selected
        return copy
    }

    func shortlisting() -> ExchangeMatch {
        var copy = self
        copy.status = .shortlisted
        return copy
    }

    func rejecting() -> ExchangeMatch {
        var copy = self
        copy.status = .rejected
        return copy
    }

    func archiving() -> ExchangeMatch {
        var copy = self
        copy.status = .archived
        return copy
    }

    func withOfferContext(
        offerID: String?,
        matchedOfferIDs: [String]
    ) -> ExchangeMatch {
        var copy = self
        copy.offerID = offerID?.exchangeNilIfBlank
        copy.matchedOfferIDs = Self.normalizedIDs(matchedOfferIDs)
        if copy.offerID == nil {
            if !copy.provenObjectOfferIDs.isEmpty {
                copy.offerID = ExchangeOfferObjectLane.resolveSelectedOfferID(
                    provenObjectOfferIDs: Set(copy.provenObjectOfferIDs),
                    objectEvidenceScoreByOfferID: copy.objectEvidenceScoreByOfferID
                )
            } else {
                copy.offerID = copy.matchedOfferIDs.first
            }
        }
        if copy.offerID != nil || !copy.matchedOfferIDs.isEmpty {
            copy.scope = .offer
        }
        return copy
    }

    func withProfileContext(
        publicProfileID: String?
    ) -> ExchangeMatch {
        var copy = self
        copy.publicProfileID = publicProfileID?.exchangeNilIfBlank
        if copy.scope == .counterparty, copy.publicProfileID != nil {
            copy.scope = .publicProfile
        }
        return copy
    }

    func withEvaluationContext(
        queryIntentClass: ExchangeIntent.QueryIntentClass?,
        dominantSurface: ExchangeIntent.SurfacePreference?
    ) -> ExchangeMatch {
        var copy = self
        copy.queryIntentClass = queryIntentClass
        copy.dominantSurface = dominantSurface
        return copy
    }

    /// Copies this umbrella match onto a child coordination thread.
    ///
    /// The umbrella row keeps its original `id`; the child row gets a new `id` while
    /// `ExchangeThread.sourceMatchID` continues to reference the umbrella match row.
    /// Nested reason/caution IDs are regenerated so persistence never reuses
    /// `exchange_match_reasons.id` / `exchange_match_cautions.id` across rows.
    func copyingForChildCoordinationThread(
        threadID: ExchangeThread.ID,
        createdAt: Date = Date()
    ) -> ExchangeMatch {
        var child = ExchangeMatch(
            id: UUID(),
            threadID: threadID,
            counterpartyID: counterpartyID,
            createdAt: createdAt,
            scope: scope,
            publicProfileID: publicProfileID,
            offerID: offerID,
            matchedOfferIDs: matchedOfferIDs,
            provenObjectOfferIDs: provenObjectOfferIDs,
            objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID,
            status: .selected,
            strength: strength,
            score: score,
            queryIntentClass: queryIntentClass,
            dominantSurface: dominantSurface,
            reasons: reasons,
            cautions: cautions,
            fit: fit,
            recommendation: recommendation,
            metadata: metadata,
            semanticProof: semanticProof
        )
        child = child.withFreshReasonAndCautionIDs()
        return child
    }

    /// Regenerates nested reason/caution primary keys (e.g. before persisting a cloned match).
    func withFreshReasonAndCautionIDs() -> ExchangeMatch {
        var copy = self
        copy.reasons = reasons.map {
            Reason(id: UUID(), kind: $0.kind, summary: $0.summary)
        }
        copy.cautions = cautions.map {
            Caution(id: UUID(), kind: $0.kind, summary: $0.summary)
        }
        return copy
    }

    /// Ensures nested IDs are unique across a multi-match persistence batch.
    func ensuringUniqueNestedIDs(
        seenReasonIDs: inout Set<UUID>,
        seenCautionIDs: inout Set<UUID>
    ) -> ExchangeMatch {
        var copy = self
        copy.reasons = reasons.map { reason in
            var updated = reason
            if seenReasonIDs.contains(updated.id) {
                updated.id = UUID()
            }
            seenReasonIDs.insert(updated.id)
            return updated
        }
        copy.cautions = cautions.map { caution in
            var updated = caution
            if seenCautionIDs.contains(updated.id) {
                updated.id = UUID()
            }
            seenCautionIDs.insert(updated.id)
            return updated
        }
        return copy
    }
}

private extension ExchangeMatch {
    static func clampedScore(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func normalizedIDs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            guard let cleaned = value.exchangeNilIfBlank else { continue }
            guard !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            output.append(cleaned)
        }

        return output
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
