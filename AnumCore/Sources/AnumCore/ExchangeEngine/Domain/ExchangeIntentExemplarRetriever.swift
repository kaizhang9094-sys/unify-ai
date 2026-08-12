import Foundation

#if DEBUG
@inline(__always)
private func exIntentExemplarRetrieverLog(_ message: @autoclosure () -> String) {
    print("[ExchangeIntentExemplarRetriever] \(message())")
}
#else
@inline(__always)
private func exIntentExemplarRetrieverLog(_ message: @autoclosure () -> String) { }
#endif

/// Retrieval-backed intent exemplar retriever.
///
/// Purpose:
/// - produce a semantic prior, not a final interpretation
/// - bias later query building
/// - expose ambiguity instead of pretending certainty
///
/// This layer should be used before real public-surface retrieval.
public struct ExchangeIntentExemplarRetriever: Sendable {
    public struct Hit: Sendable, Hashable {
        public let exemplar: ExchangeIntentExemplar
        public let fusedScore: Double
        public let contributingSources: [String]
        public let bestRankBySource: [String: Int]

        public init(
            exemplar: ExchangeIntentExemplar,
            fusedScore: Double,
            contributingSources: [String],
            bestRankBySource: [String: Int]
        ) {
            self.exemplar = exemplar
            self.fusedScore = fusedScore
            self.contributingSources = contributingSources
            self.bestRankBySource = bestRankBySource
        }
    }

    public struct Result: Sendable, Hashable {
        public let hits: [Hit]
        public let primaryQueryIntentClass: ExchangeIntent.QueryIntentClass?
        public let primarySurfacePreference: ExchangeIntent.SurfacePreference?
        public let secondaryQueryIntentClass: ExchangeIntent.QueryIntentClass?
        public let confidence: Double
        public let ambiguity: Double
        public let targetKindBias: ExchangeIntentFacets.TargetKind?
        public let fulfillmentBias: ExchangeIntentFacets.FulfillmentMode?
        public let semanticHints: [String]

        public init(
            hits: [Hit],
            primaryQueryIntentClass: ExchangeIntent.QueryIntentClass?,
            primarySurfacePreference: ExchangeIntent.SurfacePreference?,
            secondaryQueryIntentClass: ExchangeIntent.QueryIntentClass?,
            confidence: Double,
            ambiguity: Double,
            targetKindBias: ExchangeIntentFacets.TargetKind?,
            fulfillmentBias: ExchangeIntentFacets.FulfillmentMode?,
            semanticHints: [String]
        ) {
            self.hits = hits
            self.primaryQueryIntentClass = primaryQueryIntentClass
            self.primarySurfacePreference = primarySurfacePreference
            self.secondaryQueryIntentClass = secondaryQueryIntentClass
            self.confidence = min(max(confidence, 0.0), 1.0)
            self.ambiguity = min(max(ambiguity, 0.0), 1.0)
            self.targetKindBias = targetKindBias
            self.fulfillmentBias = fulfillmentBias
            self.semanticHints = semanticHints
        }

        public var isLowConfidence: Bool {
            confidence < 0.55
        }

        public var isAmbiguous: Bool {
            ambiguity >= 0.35
        }
    }

    private let store: ExchangeIntentExemplarStore
    private let embeddingProvider: (any MemoryEmbeddingProvider)?

    public init(
        store: ExchangeIntentExemplarStore,
        embeddingProvider: (any MemoryEmbeddingProvider)? = nil
    ) {
        self.store = store
        self.embeddingProvider = embeddingProvider
    }

    public func retrieve(
        text: String,
        lexicalLimit: Int = 8,
        vectorLimit: Int = 8,
        fusedLimit: Int = 5
    ) -> Result {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        exIntentExemplarRetrieverLog(
            "retrieve start chars=\(normalized.count) lexicalLimit=\(lexicalLimit) vectorLimit=\(vectorLimit) fusedLimit=\(fusedLimit)"
        )

        guard !normalized.isEmpty, !store.isEmpty else {
            return Result(
                hits: [],
                primaryQueryIntentClass: nil,
                primarySurfacePreference: nil,
                secondaryQueryIntentClass: nil,
                confidence: 0.0,
                ambiguity: 1.0,
                targetKindBias: nil,
                fulfillmentBias: nil,
                semanticHints: []
            )
        }

        let lexicalHits = store.searchLexical(
            text: normalized,
            limit: max(0, lexicalLimit)
        )

        let vectorHits: [ExchangeIntentExemplarStore.VectorHit]
        if let embeddingProvider {
            vectorHits = store.searchVector(
                text: normalized,
                embeddingProvider: embeddingProvider,
                limit: max(0, vectorLimit)
            )
        } else {
            vectorHits = []
        }

        exIntentExemplarRetrieverLog(
            "raw hits lexical=\(lexicalHits.count) vector=\(vectorHits.count)"
        )

        let fused = ExchangeRRF.fuse(
            [
                ExchangeRRF.rankedHits(
                    documentIDs: lexicalHits.map(\.exemplarID),
                    source: "bm25"
                ),
                ExchangeRRF.rankedHits(
                    documentIDs: vectorHits.map(\.exemplarID),
                    source: "vector"
                )
            ],
            k: 60,
            limit: max(fusedLimit * 3, fusedLimit)
        )

        let finalHits: [Hit] = fused
            .compactMap { item in
                guard let exemplar = store.exemplar(for: item.documentID) else { return nil }
                return Hit(
                    exemplar: exemplar,
                    fusedScore: item.fusedScore,
                    contributingSources: item.contributingSources,
                    bestRankBySource: item.bestRankBySource
                )
            }
            .sorted {
                if $0.fusedScore != $1.fusedScore { return $0.fusedScore > $1.fusedScore }
                return $0.exemplar.id < $1.exemplar.id
            }
            .prefix(max(0, fusedLimit))
            .map { $0 }

        for hit in finalHits {
            exIntentExemplarRetrieverLog(
                "hit exemplarID=\(hit.exemplar.id) class=\(hit.exemplar.queryIntentClass.rawValue) surface=\(hit.exemplar.surfacePreference.rawValue) score=\(String(format: "%.4f", hit.fusedScore)) sources=\(hit.contributingSources)"
            )
        }

        let prior = buildResult(from: finalHits)

        exIntentExemplarRetrieverLog(
            "retrieve done primaryClass=\(prior.primaryQueryIntentClass?.rawValue ?? "nil") primarySurface=\(prior.primarySurfacePreference?.rawValue ?? "nil") secondaryClass=\(prior.secondaryQueryIntentClass?.rawValue ?? "nil") confidence=\(String(format: "%.3f", prior.confidence)) ambiguity=\(String(format: "%.3f", prior.ambiguity))"
        )

        return prior
    }
}

private extension ExchangeIntentExemplarRetriever {
    func buildResult(
        from hits: [Hit]
    ) -> Result {
        guard !hits.isEmpty else {
            return Result(
                hits: [],
                primaryQueryIntentClass: nil,
                primarySurfacePreference: nil,
                secondaryQueryIntentClass: nil,
                confidence: 0.0,
                ambiguity: 1.0,
                targetKindBias: nil,
                fulfillmentBias: nil,
                semanticHints: []
            )
        }

        var classWeights: [ExchangeIntent.QueryIntentClass: Double] = [:]
        var surfaceWeights: [ExchangeIntent.SurfacePreference: Double] = [:]
        var targetKindWeights: [ExchangeIntentFacets.TargetKind: Double] = [:]
        var fulfillmentWeights: [ExchangeIntentFacets.FulfillmentMode: Double] = [:]
        var hintWeights: [String: Double] = [:]

        let rankedHits = normalizeHitWeights(hits)

        for (index, pair) in rankedHits.enumerated() {
            let hit = pair.hit
            let weight = pair.weight
            let positionBonus = max(0.0, 0.12 - (Double(index) * 0.02))
            let totalWeight = weight + positionBonus

            classWeights[hit.exemplar.queryIntentClass, default: 0] += totalWeight
            surfaceWeights[hit.exemplar.surfacePreference, default: 0] += totalWeight

            if let targetKind = hit.exemplar.targetKind {
                targetKindWeights[targetKind, default: 0] += totalWeight
            }

            if let fulfillmentMode = hit.exemplar.fulfillmentMode {
                fulfillmentWeights[fulfillmentMode, default: 0] += totalWeight
            }

            for hint in hit.exemplar.semanticHints {
                hintWeights[hint, default: 0] += totalWeight
            }
        }

        let sortedClasses = classWeights.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.rawValue < $1.key.rawValue
        }

        let sortedSurfaces = surfaceWeights.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.rawValue < $1.key.rawValue
        }

        let primaryClass = sortedClasses.first?.key
        let secondaryClass = sortedClasses.dropFirst().first?.key
        let primarySurface = sortedSurfaces.first?.key

        let confidence = computeConfidence(
            hits: hits,
            sortedClasses: sortedClasses
        )

        let ambiguity = computeAmbiguity(
            sortedClasses: sortedClasses,
            sortedSurfaces: sortedSurfaces
        )

        let targetKindBias = targetKindWeights.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key.rawValue > rhs.key.rawValue
        })?.key

        let fulfillmentBias = fulfillmentWeights.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key.rawValue > rhs.key.rawValue
        })?.key

        let semanticHints = hintWeights
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .prefix(8)
            .map(\.key)

        return Result(
            hits: hits,
            primaryQueryIntentClass: primaryClass,
            primarySurfacePreference: primarySurface,
            secondaryQueryIntentClass: secondaryClass,
            confidence: confidence,
            ambiguity: ambiguity,
            targetKindBias: targetKindBias,
            fulfillmentBias: fulfillmentBias,
            semanticHints: semanticHints
        )
    }

    func normalizeHitWeights(
        _ hits: [Hit]
    ) -> [(hit: Hit, weight: Double)] {
        guard let best = hits.first?.fusedScore, best > 0 else {
            let fallbackWeight = hits.isEmpty ? 0.0 : (1.0 / Double(hits.count))
            return hits.map { ($0, fallbackWeight) }
        }

        return hits.map { hit in
            let normalized = max(0.0, min(1.0, hit.fusedScore / best))
            return (hit, normalized)
        }
    }

    func computeConfidence(
        hits: [Hit],
        sortedClasses: [(key: ExchangeIntent.QueryIntentClass, value: Double)]
    ) -> Double {
        guard !hits.isEmpty else { return 0.0 }

        let topHitStrength: Double = {
            guard let first = hits.first else { return 0.0 }
            guard let second = hits.dropFirst().first else {
                return min(max(first.fusedScore * 8.0, 0.0), 1.0)
            }

            let gap = max(first.fusedScore - second.fusedScore, 0.0)
            return min(gap * 20.0, 0.35) + min(first.fusedScore * 8.0, 0.45)
        }()

        let classSeparation: Double = {
            guard let first = sortedClasses.first else { return 0.0 }
            guard let second = sortedClasses.dropFirst().first else { return 0.85 }
            let total = max(first.value + second.value, 0.0001)
            return max(0.0, min((first.value - second.value) / total, 1.0))
        }()

        let multiSourceBonus: Double = {
            guard let first = hits.first else { return 0.0 }
            return first.contributingSources.count >= 2 ? 0.10 : 0.0
        }()

        return min(max((topHitStrength * 0.55) + (classSeparation * 0.35) + multiSourceBonus, 0.0), 1.0)
    }

    func computeAmbiguity(
        sortedClasses: [(key: ExchangeIntent.QueryIntentClass, value: Double)],
        sortedSurfaces: [(key: ExchangeIntent.SurfacePreference, value: Double)]
    ) -> Double {
        let classAmbiguity: Double = {
            guard let first = sortedClasses.first else { return 1.0 }
            guard let second = sortedClasses.dropFirst().first else { return 0.05 }
            let total = max(first.value + second.value, 0.0001)
            let separation = max(0.0, min((first.value - second.value) / total, 1.0))
            return 1.0 - separation
        }()

        let surfaceAmbiguity: Double = {
            guard let first = sortedSurfaces.first else { return 1.0 }
            guard let second = sortedSurfaces.dropFirst().first else { return 0.05 }
            let total = max(first.value + second.value, 0.0001)
            let separation = max(0.0, min((first.value - second.value) / total, 1.0))
            return 1.0 - separation
        }()

        return min(max((classAmbiguity * 0.7) + (surfaceAmbiguity * 0.3), 0.0), 1.0)
    }
}
