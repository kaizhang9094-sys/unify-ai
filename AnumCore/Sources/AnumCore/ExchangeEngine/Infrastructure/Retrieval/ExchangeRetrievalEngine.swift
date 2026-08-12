import Foundation

#if DEBUG
@inline(__always)
private func exRetrievalEngineLog(_ message: @autoclosure () -> String) {
    print("[ExchangeRetrievalEngine] \(message())")
}
#else
@inline(__always)
private func exRetrievalEngineLog(_ message: @autoclosure () -> String) { }
#endif

/// Hybrid retrieval engine:
/// - BM25 lexical retrieval
/// - Vector retrieval
/// - RRF fusion
/// - light reranking
/// - domain-correct hard gating only
///
/// Canonical rule:
/// - retrieval should be evidence-led, not heuristic-led
/// - BM25/vector/RRF do the heavy lifting
/// - reranking should be a soft bias layer, not a semantic choke point
/// - hard gates should only enforce real operational / explicit constraints
/// - fit remains downstream
public struct ExchangeRetrievalEngine: Sendable {
    public struct Candidate: Sendable, Hashable {
        public let document: ExchangeRetrievalDocument
        public let fusedScore: Double
        public let contributingSources: [String]
        public let bestRankBySource: [String: Int]
        /// Cosine similarity between `queryObjectText` embedding and an `offer_object` document embedding.
        public let objectEvidenceScore: Double?
        /// Competitively proven offer IDs for object-lane attachment (per-node top-1 among qualifiers).
        public let competitiveProvenObjectOfferScores: [String: Double]

        public init(
            document: ExchangeRetrievalDocument,
            fusedScore: Double,
            contributingSources: [String],
            bestRankBySource: [String: Int],
            objectEvidenceScore: Double? = nil,
            competitiveProvenObjectOfferScores: [String: Double] = [:]
        ) {
            self.document = document
            self.fusedScore = fusedScore
            self.contributingSources = contributingSources
            self.bestRankBySource = bestRankBySource
            self.objectEvidenceScore = objectEvidenceScore
            self.competitiveProvenObjectOfferScores = competitiveProvenObjectOfferScores
        }
    }

    private struct HardGateDecision: Sendable, Hashable {
        let passes: Bool
        let reason: String
    }

    private struct RerankBreakdown: Sendable, Hashable {
        let baseRRF: Double
        let surfaceBias: Double
        let docKindBias: Double
        let rawQueryOverlap: Double
        let semanticScore: Double
        let keywordScore: Double
        let constraintScore: Double
        let regionScore: Double
        let fulfillmentScore: Double
        let reachabilityScore: Double
        let freshnessScore: Double
        let objectLaneScore: Double
        let finalScore: Double
    }

    private let store: ExchangeRetrievalStore
    private let embeddingProvider: any MemoryEmbeddingProvider

    public init(
        store: ExchangeRetrievalStore,
        embeddingProvider: any MemoryEmbeddingProvider
    ) {
        self.store = store
        self.embeddingProvider = embeddingProvider
    }

    public func retrieve(
        query: ExchangeRetrievalQuery,
        lexicalLimit: Int = 40,
        vectorLimit: Int = 40,
        fusedLimit: Int = 24
    ) async -> [Candidate] {
        exRetrievalEngineLog(
            "retrieve start " +
            "queryClass=\(query.queryIntentClass.rawValue) " +
            "surfacePref=\(query.surfacePreference.rawValue) " +
            "laneSurfaces=\(query.resolvedLaneSurfaceAllowList.map { $0.map(\.rawValue).joined(separator: ",") } ?? "nil") " +
            "queryText=\(query.queryText ?? "nil") " +
            "semanticText=\(query.semanticText ?? "nil") " +
            "keywords=\(query.keywords) " +
            "providerTerms=\(query.providerTerms) " +
            "capabilityTerms=\(query.capabilityTerms) " +
            "affinityTerms=\(query.affinityTerms) " +
            "regionTerms=\(query.regionTerms) " +
            "hardRegionIDs=\(query.hardRegionIDs) " +
            "softRegionTerms=\(query.softRegionTerms) " +
            "explicitHardConstraints=\(query.explicitHardConstraints.map { "\($0.key)=\($0.value)" }) " +
            "targetKind=\(query.targetKind ?? "nil") " +
            "fulfillmentMode=\(query.fulfillmentMode ?? "nil") " +
            "reachabilityRequirement=\(query.reachabilityRequirement.rawValue) " +
            "lexicalLimit=\(lexicalLimit) " +
            "vectorLimit=\(vectorLimit) " +
            "fusedLimit=\(fusedLimit)"
        )

        async let allDocumentsTask = store.listDocuments()
        async let lexicalHitsTask = store.searchBM25(
            query: query,
            limit: max(0, lexicalLimit)
        )

        let queryEmbedding: [Float]? = {
            let semanticText = query.normalizedSemanticEmbeddingText
            guard !semanticText.isEmpty else { return nil }
            return embeddingProvider.embed(semanticText)
        }()

        let objectLaneEmbedding: [Float]? = {
            guard let objectText = query.queryObjectText, !objectText.isEmpty else { return nil }
            return embeddingProvider.embed(objectText)
        }()

        if let queryEmbedding {
            exRetrievalEngineLog("query embedding dim=\(queryEmbedding.count)")
        } else {
            exRetrievalEngineLog("query embedding unavailable")
        }

        if let objectLaneEmbedding {
            exRetrievalEngineLog(
                "object lane embedding dim=\(objectLaneEmbedding.count) queryObjectText=\(query.queryObjectText ?? "nil")"
            )
        }

        let vectorHits: [ExchangeVectorIndex.SearchHit]
        if let queryEmbedding, !queryEmbedding.isEmpty {
            vectorHits = await store.searchVector(
                queryEmbedding: queryEmbedding,
                limit: max(0, vectorLimit)
            )
        } else {
            vectorHits = []
        }

        let documents = await allDocumentsTask
        let lexicalHits = await lexicalHitsTask

        exRetrievalEngineLog(
            "raw retrieval docs=\(documents.count) lexicalHits=\(lexicalHits.count) vectorHits=\(vectorHits.count)"
        )

        let objectLaneHits: [(documentID: String, score: Double)] = {
            guard let objectLaneEmbedding else { return [] }
            return ExchangeOfferObjectLane.rankOfferObjectDocuments(
                queryEmbedding: objectLaneEmbedding,
                documents: documents,
                limit: max(0, vectorLimit)
            )
        }()

        if !objectLaneHits.isEmpty {
            exRetrievalEngineLog(
                "object lane hits=\(objectLaneHits.count) top=\(objectLaneHits.prefix(3).map { "\($0.documentID):\(String(format: "%.3f", $0.score))" }.joined(separator: ","))"
            )
        }

        let documentMap = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        let vectorScoreMap = Dictionary(uniqueKeysWithValues: vectorHits.map { ($0.documentID, $0.score) })
        let objectLaneScoreMap = Dictionary(uniqueKeysWithValues: objectLaneHits.map { ($0.documentID, $0.score) })

        let allOfferObjectEvidenceScoresByDocumentID: [String: Double] = {
            guard let objectLaneEmbedding else { return [:] }
            var scores: [String: Double] = [:]
            scores.reserveCapacity(documents.count)
            for document in documents {
                guard let score = ExchangeOfferObjectLane.objectEvidenceScore(
                    queryEmbedding: objectLaneEmbedding,
                    document: document
                ) else {
                    continue
                }
                scores[document.id] = score
            }
            return scores
        }()

        let competitiveProvenObjectOfferScores = ExchangeOfferObjectLane.competitivelyProvenObjectOffers(
            documents: documents,
            objectEvidenceScoresByDocumentID: allOfferObjectEvidenceScoresByDocumentID
        )

        if !competitiveProvenObjectOfferScores.isEmpty {
            exRetrievalEngineLog(
                "object lane competitive proof offers=\(competitiveProvenObjectOfferScores.count) " +
                "top=\(competitiveProvenObjectOfferScores.sorted { $0.key < $1.key }.prefix(4).map { "\($0.key):\(String(format: "%.3f", $0.value))" }.joined(separator: ","))"
            )
        }

        var fusionSources: [[ExchangeRRF.RankedHit]] = [
            ExchangeRRF.rankedHits(
                documentIDs: lexicalHits.map(\.documentID),
                source: "bm25"
            ),
            ExchangeRRF.rankedHits(
                documentIDs: vectorHits.map(\.documentID),
                source: "vector"
            )
        ]
        if !objectLaneHits.isEmpty {
            fusionSources.append(
                ExchangeRRF.rankedHits(
                    documentIDs: objectLaneHits.map(\.documentID),
                    source: "object_lane"
                )
            )
        }

        let fused = ExchangeRRF.fuse(
            fusionSources,
            k: 60,
            limit: max(fusedLimit * 4, fusedLimit)
        )

        var reranked: [Candidate] = []
        reranked.reserveCapacity(fused.count)
        var rerankBreakdownByDocumentID: [String: RerankBreakdown] = [:]
        rerankBreakdownByDocumentID.reserveCapacity(fused.count)

        for result in fused {
            guard let document = documentMap[result.documentID] else {
                exRetrievalEngineLog("drop fused result missing document documentID=\(result.documentID)")
                continue
            }

            let gate = hardGateDecision(document: document, query: query)
            guard gate.passes else {
                exRetrievalEngineLog(
                    "drop fused result hard_filter " +
                    "documentID=\(document.id) " +
                    "entityType=\(document.entityType.rawValue) " +
                    "surfaceType=\(document.surfaceType.rawValue) " +
                    "offerID=\(document.offerID ?? "nil") " +
                    "publicProfileID=\(document.publicProfileID ?? "nil") " +
                    "reason=\(gate.reason)"
                )
                continue
            }

            let breakdown = rerankBreakdown(
                document: document,
                query: query,
                baseRRF: result.fusedScore,
                vectorScore: vectorScoreMap[document.id],
                objectEvidenceScore: objectLaneScoreMap[document.id]
            )

            exRetrievalEngineLog(
                "rerank " +
                "documentID=\(document.id) " +
                "docKind=\(document.docKind?.rawValue ?? "nil") " +
                "surfaceType=\(document.surfaceType.rawValue) " +
                "counterpartyID=\(document.counterpartyID) " +
                "offerID=\(document.offerID ?? "nil") " +
                "baseRRF=\(String(format: "%.4f", breakdown.baseRRF)) " +
                "bm25Rank=\(result.bestRankBySource["bm25"].map(String.init) ?? "nil") " +
                "vectorRank=\(result.bestRankBySource["vector"].map(String.init) ?? "nil") " +
                "objectLaneRank=\(result.bestRankBySource["object_lane"].map(String.init) ?? "nil") " +
                "surfaceBias=\(String(format: "%.4f", breakdown.surfaceBias)) " +
                "docKindBias=\(String(format: "%.4f", breakdown.docKindBias)) " +
                "rawQueryOverlap=\(String(format: "%.4f", breakdown.rawQueryOverlap)) " +
                "semantic=\(String(format: "%.4f", breakdown.semanticScore)) " +
                "keyword=\(String(format: "%.4f", breakdown.keywordScore)) " +
                "constraint=\(String(format: "%.4f", breakdown.constraintScore)) " +
                "region=\(String(format: "%.4f", breakdown.regionScore)) " +
                "fulfillment=\(String(format: "%.4f", breakdown.fulfillmentScore)) " +
                "reachability=\(String(format: "%.4f", breakdown.reachabilityScore)) " +
                "freshness=\(String(format: "%.4f", breakdown.freshnessScore)) " +
                "objectLaneScore=\(String(format: "%.4f", breakdown.objectLaneScore)) " +
                "final=\(String(format: "%.4f", breakdown.finalScore))"
            )

            rerankBreakdownByDocumentID[document.id] = breakdown

            ExchangeRetrievalDebugTrace.recordRankingRow(
                .init(
                    documentID: document.id,
                    docKind: document.docKind?.rawValue,
                    surfaceType: document.surfaceType.rawValue,
                    counterpartyID: document.counterpartyID,
                    nodeID: document.nodeID,
                    publicProfileID: document.publicProfileID,
                    offerID: document.offerID,
                    bm25Rank: result.bestRankBySource["bm25"],
                    vectorRank: result.bestRankBySource["vector"],
                    objectLaneRank: result.bestRankBySource["object_lane"],
                    bm25Score: nil,
                    vectorScore: vectorScoreMap[document.id],
                    objectLaneScore: objectLaneScoreMap[document.id],
                    surfaceBias: breakdown.surfaceBias,
                    docKindBias: breakdown.docKindBias,
                    finalScore: breakdown.finalScore
                )
            )

            reranked.append(
                Candidate(
                    document: document,
                    fusedScore: breakdown.finalScore,
                    contributingSources: result.contributingSources,
                    bestRankBySource: result.bestRankBySource,
                    objectEvidenceScore: objectLaneScoreMap[document.id],
                    competitiveProvenObjectOfferScores: competitiveProvenObjectOfferScores
                )
            )
        }

        let sortedCandidates = reranked.sorted { lhs, rhs in
            if lhs.fusedScore != rhs.fusedScore {
                return lhs.fusedScore > rhs.fusedScore
            }

            let lhsSurfaceOrder = preferredSurfaceOrder(
                lhs.document.surfaceType,
                for: query.queryIntentClass
            )
            let rhsSurfaceOrder = preferredSurfaceOrder(
                rhs.document.surfaceType,
                for: query.queryIntentClass
            )

            if lhsSurfaceOrder != rhsSurfaceOrder {
                return lhsSurfaceOrder < rhsSurfaceOrder
            }

            let lhsDocKindOrder = Self.preferredDocKindOrder(
                lhs.document.docKind,
                for: query
            )
            let rhsDocKindOrder = Self.preferredDocKindOrder(
                rhs.document.docKind,
                for: query
            )
            if lhsDocKindOrder != rhsDocKindOrder {
                return lhsDocKindOrder < rhsDocKindOrder
            }

            if lhs.document.updatedAt != rhs.document.updatedAt {
                return lhs.document.updatedAt > rhs.document.updatedAt
            }

            return lhs.document.id < rhs.document.id
        }

        let cappedCandidates = Self.applyPerOfferSliceCap(sortedCandidates)
        let finalCandidates = Array(cappedCandidates.prefix(max(0, fusedLimit)))

        for candidate in finalCandidates {
            let breakdown = rerankBreakdownByDocumentID[candidate.document.id]
            exRetrievalEngineLog(
                "final candidate " +
                "documentID=\(candidate.document.id) " +
                "docKind=\(candidate.document.docKind?.rawValue ?? "nil") " +
                "entityType=\(candidate.document.entityType.rawValue) " +
                "surfaceType=\(candidate.document.surfaceType.rawValue) " +
                "counterpartyID=\(candidate.document.counterpartyID) " +
                "offerID=\(candidate.document.offerID ?? "nil") " +
                "publicProfileID=\(candidate.document.publicProfileID ?? "nil") " +
                "score=\(String(format: "%.4f", candidate.fusedScore)) " +
                "surfaceBias=\(breakdown.map { String(format: "%.4f", $0.surfaceBias) } ?? "nil") " +
                "docKindBias=\(breakdown.map { String(format: "%.4f", $0.docKindBias) } ?? "nil") " +
                "objectLaneScore=\(breakdown.map { String(format: "%.4f", $0.objectLaneScore) } ?? "nil") " +
                "sources=\(candidate.contributingSources) " +
                "ranks=\(candidate.bestRankBySource)"
            )
        }

        exRetrievalEngineLog("retrieve done finalCandidates=\(finalCandidates.count)")
        return finalCandidates
    }
}

private extension ExchangeRetrievalEngine {
    private func hardGateDecision(
        document: ExchangeRetrievalDocument,
        query: ExchangeRetrievalQuery
    ) -> HardGateDecision {
        if !query.visibilityAllowList.isEmpty {
            let allowedVisibility = Set(query.visibilityAllowList.map(\.normalizedLooseEnum))
            guard let visibility = document.visibility?.normalizedLooseEnum,
                  allowedVisibility.contains(visibility) else {
                return .init(passes: false, reason: "visibility")
            }
        }

        if !query.availabilityAllowList.isEmpty {
            let allowedAvailability = Set(query.availabilityAllowList.map(\.normalizedLooseEnum))
            guard let availability = document.availability?.normalizedLooseEnum,
                  allowedAvailability.contains(availability) else {
                return .init(passes: false, reason: "availability")
            }
        }

        switch query.reachabilityRequirement {
        case .any:
            break

        case .acceptingInboundOnly:
            if document.acceptingInbound == false {
                return .init(passes: false, reason: "acceptingInbound")
            }

        case .routeableOnly:
            if document.acceptingInbound == false {
                return .init(passes: false, reason: "routeableOnly.acceptingInboundFalse")
            }
            if document.accessMode?.normalizedLooseEnum == "closed" {
                return .init(passes: false, reason: "routeableOnly.closed")
            }

        case .directOnly:
            guard document.accessMode?.normalizedLooseEnum == "direct" else {
                return .init(passes: false, reason: "directOnly")
            }

        case .introAllowed:
            guard let accessMode = document.accessMode?.normalizedLooseEnum,
                  accessMode == "direct" ||
                    accessMode == "intropreferred" ||
                    accessMode == "introrequired" else {
                return .init(passes: false, reason: "introAllowed")
            }
        }

        if let laneSurfaces = query.resolvedLaneSurfaceAllowList, !laneSurfaces.isEmpty {
            let allowed = Set(laneSurfaces)
            if case .unknown = document.surfaceType {
#if DEBUG
                exRetrievalEngineLog(
                    "lane gate rejected unknown surface documentID=\(document.id) " +
                    "wire=\(document.surfaceType.rawValue) allowedLanes=\(laneSurfaces.map(\.rawValue))"
                )
#endif
                return .init(passes: false, reason: "laneSurfaceUnknown")
            }
            guard allowed.contains(document.surfaceType) else {
                return .init(passes: false, reason: "laneSurface")
            }
        }

        let queryHardRegionIDs = Set(query.hardRegionIDs.map(\.normalizedLooseEnum))
        let usesDeclaredAreaGate = query.explicitRegionRequired && queryHardRegionIDs.isEmpty
        if usesDeclaredAreaGate {
            // Declared service-area compatibility is enforced at fit/discovery; keep broad recall here.
        } else if !queryHardRegionIDs.isEmpty {
            let docCanonicalIDs = Set(document.canonicalRegionIDs.map(\.normalizedLooseEnum))
            let docParentIDs = Set(document.parentRegionIDs.map(\.normalizedLooseEnum))
            let docAliasSet = Set((document.regionAliases + document.regionTags).map(\.normalizedLooseEnum))
            let querySoftTerms = Set(
                (query.softRegionTerms + query.resolvedPlaces.flatMap(\.aliases))
                    .map(\.normalizedLooseEnum)
            )

            let canonicalMatch = !queryHardRegionIDs.isDisjoint(with: docCanonicalIDs)
            let parentMatch = !queryHardRegionIDs.isDisjoint(with: docParentIDs)
            let aliasMatch = !querySoftTerms.isEmpty && !querySoftTerms.isDisjoint(with: docAliasSet)

#if DEBUG
            exRetrievalEngineLog(
                "region hard_gate " +
                "documentID=\(document.id) " +
                "queryHard=\(Array(queryHardRegionIDs).sorted()) " +
                "querySoft=\(Array(querySoftTerms).sorted()) " +
                "docCanonical=\(Array(docCanonicalIDs).sorted()) " +
                "docParent=\(Array(docParentIDs).sorted()) " +
                "docAliases=\(Array(docAliasSet).sorted()) " +
                "canonicalMatch=\(canonicalMatch) " +
                "parentMatch=\(parentMatch) " +
                "aliasMatch=\(aliasMatch)"
            )
#endif

            guard canonicalMatch || parentMatch || aliasMatch else {
                return .init(passes: false, reason: "explicitRegionRequired")
            }
        }

        if query.explicitFulfillmentRequired,
           let wantedFulfillment = query.fulfillmentMode?.normalizedLooseEnum,
           !wantedFulfillment.isEmpty {
            let docFulfillment = Set(document.allFilterTokens.map(\.normalizedLooseEnum))
            if !docFulfillment.contains(wantedFulfillment) {
                return .init(passes: false, reason: "explicitFulfillmentRequired")
            }
        }

        for constraint in query.explicitHardConstraints where constraint.isHardConstraint {
            let key = constraint.key.normalizedLooseEnum
            let valueTokens = Set(tokenize(constraint.value).map(\.normalizedLooseEnum))
            if valueTokens.isEmpty { continue }

            let docUniverse = Set(document.searchableTextTokens.map(\.normalizedLooseEnum))
                .union(document.allFilterTokens.map(\.normalizedLooseEnum))

            if key.contains("location") || key.contains("region") || key.contains("place") || key.contains("city") {
                if valueTokens.isDisjoint(with: docUniverse) {
                    return .init(passes: false, reason: "hardConstraint.location")
                }
            }

            if key.contains("fulfillment") || key.contains("delivery") || key.contains("remote") || key.contains("local") {
                if valueTokens.isDisjoint(with: docUniverse) {
                    return .init(passes: false, reason: "hardConstraint.fulfillment")
                }
            }

            if key.contains("privacy") {
                if !docUniverse.contains("private") &&
                    !docUniverse.contains("discreet") &&
                    !docUniverse.contains("guarded") {
                    return .init(passes: false, reason: "hardConstraint.privacy")
                }
            }
        }

        return .init(passes: true, reason: "ok")
    }

    private func rerankBreakdown(
        document: ExchangeRetrievalDocument,
        query: ExchangeRetrievalQuery,
        baseRRF: Double,
        vectorScore: Double?,
        objectEvidenceScore: Double?
    ) -> RerankBreakdown {
        let surfaceBias = surfaceBias(
            surfaceType: document.surfaceType,
            queryClass: query.queryIntentClass,
            surfacePreference: query.surfacePreference
        )

        let rawQueryOverlap = rawQueryOverlapScore(
            document: document,
            query: query
        )

        let semanticScore = semanticScore(
            vectorScore: vectorScore
        )

        let keywordScore = keywordScore(
            document: document,
            query: query
        )

        let constraintScore = constraintScore(
            document: document,
            query: query
        )

        let regionScore = regionScore(
            document: document,
            query: query
        )

        let fulfillmentScore = fulfillmentScore(
            document: document,
            query: query
        )

        let reachabilityScore = reachabilityScore(
            document: document,
            query: query
        )

        let freshnessScore = freshnessScore(
            document: document
        )

        let docKindBias = Self.docKindBias(
            query: query,
            docKind: document.docKind
        )

        let objectLaneScore: Double = {
            guard query.queryObjectText != nil,
                  ExchangeOfferObjectLane.isOfferObjectDocument(document),
                  let score = objectEvidenceScore else {
                return 0
            }
            return score * 3.0
        }()

        let boostedBase = baseRRF * 5.0

        let final =
            boostedBase +
            surfaceBias +
            docKindBias +
            rawQueryOverlap +
            semanticScore +
            keywordScore +
            constraintScore +
            regionScore +
            fulfillmentScore +
            reachabilityScore +
            freshnessScore +
            objectLaneScore

        return RerankBreakdown(
            baseRRF: boostedBase,
            surfaceBias: surfaceBias,
            docKindBias: docKindBias,
            rawQueryOverlap: rawQueryOverlap,
            semanticScore: semanticScore,
            keywordScore: keywordScore,
            constraintScore: constraintScore,
            regionScore: regionScore,
            fulfillmentScore: fulfillmentScore,
            reachabilityScore: reachabilityScore,
            freshnessScore: freshnessScore,
            objectLaneScore: objectLaneScore,
            finalScore: final
        )
    }

    func surfaceBias(
        surfaceType: ExchangeRetrievalDocument.SurfaceType,
        queryClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference
    ) -> Double {
        let preferenceBoost: Double = {
            switch surfacePreference {
            case .offer:
                return surfaceType == .offer ? 0.22 : 0.0
            case .capability:
                return surfaceType == .publicProfileCapability || surfaceType == .publicProfileSeeking || surfaceType == .publicProfile ? 0.22 : 0.0
            case .affinity:
                return surfaceType == .publicProfileAffinity || surfaceType == .publicProfile ? 0.22 : 0.0
            case .mixed:
                return 0.0
            }
        }()

        let base: Double
        switch queryClass {
        case .providerSearch, .offerSearch:
            switch surfaceType {
            case .offer: base = 0.34
            case .publicProfile: base = 0.08
            case .publicProfileCapability: base = 0.14
            case .publicProfileSeeking: base = 0.14
            case .publicProfileAffinity: base = 0.02
            case .unknown: base = 0.01
            }

        case .capabilitySearch, .collaborationSearch:
            switch surfaceType {
            case .offer: base = 0.10
            case .publicProfile: base = 0.18
            case .publicProfileCapability: base = 0.30
            case .publicProfileSeeking: base = 0.30
            case .publicProfileAffinity: base = 0.06
            case .unknown: base = 0.01
            }

        case .socialAffinitySearch, .relationshipSearch:
            switch surfaceType {
            case .offer: base = 0.02
            case .publicProfile: base = 0.22
            case .publicProfileCapability: base = 0.10
            case .publicProfileSeeking: base = 0.10
            case .publicProfileAffinity: base = 0.34
            case .unknown: base = 0.01
            }

        case .directOutreach, .followUp, .statusCheck:
            switch surfaceType {
            case .offer: base = 0.06
            case .publicProfile: base = 0.13
            case .publicProfileCapability: base = 0.18
            case .publicProfileSeeking: base = 0.18
            case .publicProfileAffinity: base = 0.08
            case .unknown: base = 0.01
            }

        case .generalDiscovery:
            switch surfaceType {
            case .offer: base = 0.12
            case .publicProfile: base = 0.11
            case .publicProfileCapability: base = 0.12
            case .publicProfileSeeking: base = 0.12
            case .publicProfileAffinity: base = 0.10
            case .unknown: base = 0.01
            }
        }

        return base + preferenceBoost
    }

    func rawQueryOverlapScore(
        document: ExchangeRetrievalDocument,
        query: ExchangeRetrievalQuery
    ) -> Double {
        guard let queryText = query.queryText?.nilIfBlank else { return 0.0 }

        let queryTokens = Set(tokenize(queryText).map(\.normalizedLooseEnum))
        guard !queryTokens.isEmpty else { return 0.0 }

        let docTokens = Set(document.searchableTextTokens.map(\.normalizedLooseEnum))
        let overlap = queryTokens.intersection(docTokens).count

        if overlap == 0 { return 0.0 }
        return min(Double(overlap) * 0.05, 0.30)
    }

    func keywordScore(
        document: ExchangeRetrievalDocument,
        query: ExchangeRetrievalQuery
    ) -> Double {
        let searchableTokens = Set(tokenize(document.searchableText).map(\.normalizedLooseEnum))
        let titleTokens = Set(tokenize(document.title).map(\.normalizedLooseEnum))
        let categoryTokens = Set(tokenize(document.category ?? "").map(\.normalizedLooseEnum))
        let tagTokens = Set(document.tags.map(\.normalizedLooseEnum))
        let filterTokens = Set(document.allFilterTokens.map(\.normalizedLooseEnum))

        let generalUniverse = searchableTokens.union(tagTokens).union(filterTokens)
        let titleUniverse = titleTokens.union(categoryTokens).union(tagTokens).union(filterTokens)

        let keywordOverlap = overlapScore(
            query.keywords,
            against: generalUniverse,
            weight: 0.04,
            cap: 0.20
        )

        let providerOverlap = overlapScore(
            query.providerTerms,
            against: titleUniverse.union(generalUniverse),
            weight: 0.05,
            cap: 0.20
        )

        let capabilityOverlap = overlapScore(
            query.capabilityTerms,
            against: generalUniverse,
            weight: 0.05,
            cap: 0.20
        )

        let affinityOverlap = overlapScore(
            query.affinityTerms,
            against: generalUniverse,
            weight: 0.05,
            cap: 0.20
        )

        let capabilityTermWeight = document.docKind == .profileCapability ? 1.12 : 1.0
        let providerTermWeight = document.docKind == .profileIntro ? 1.12 : 1.0
        let affinityTermWeight = document.docKind == .profileAffinity ? 1.12 : 1.0

        switch query.queryIntentClass {
        case .providerSearch, .offerSearch:
            return keywordOverlap
                + (providerOverlap * 1.2 * providerTermWeight)
                + (capabilityOverlap * 0.35 * capabilityTermWeight)
                + (affinityOverlap * 0.10 * affinityTermWeight)

        case .capabilitySearch, .collaborationSearch:
            return keywordOverlap
                + (providerOverlap * 0.25 * providerTermWeight)
                + (capabilityOverlap * 1.2 * capabilityTermWeight)
                + (affinityOverlap * 0.20 * affinityTermWeight)

        case .socialAffinitySearch, .relationshipSearch:
            return keywordOverlap
                + (providerOverlap * 0.10 * providerTermWeight)
                + (capabilityOverlap * 0.25 * capabilityTermWeight)
                + (affinityOverlap * 1.2 * affinityTermWeight)

        case .directOutreach, .followUp, .statusCheck:
            return keywordOverlap
                + (providerOverlap * 0.20 * providerTermWeight)
                + (capabilityOverlap * 0.45 * capabilityTermWeight)
                + (affinityOverlap * 0.30 * affinityTermWeight)

        case .generalDiscovery:
            return keywordOverlap
                + (providerOverlap * 0.50 * providerTermWeight)
                + (capabilityOverlap * 0.50 * capabilityTermWeight)
                + (affinityOverlap * 0.50 * affinityTermWeight)
        }
    }

    func semanticScore(
        vectorScore: Double?
    ) -> Double {
        guard let vectorScore else { return 0.0 }
        let normalized = max(0.0, min(1.0, vectorScore))
        return normalized * 0.55
    }

    func constraintScore(
        document: ExchangeRetrievalDocument,
        query: ExchangeRetrievalQuery
    ) -> Double {
        var targetTerms: [String] = []

        if let targetKind = query.targetKind?.nilIfBlank {
            targetTerms.append(targetKind)
        }

        targetTerms.append(contentsOf: query.explicitHardConstraints.map(\.value))

        guard !targetTerms.isEmpty else { return 0.0 }

        let docTokens = Set(document.allFilterTokens.map(\.normalizedLooseEnum))
            .union(tokenize(document.searchableText).map(\.normalizedLooseEnum))

        return overlapScore(
            targetTerms,
            against: docTokens,
            weight: 0.05,
            cap: 0.22
        )
    }

    func regionScore(
        document: ExchangeRetrievalDocument,
        query: ExchangeRetrievalQuery
    ) -> Double {
        var declaredScore = 0.0
        let softTerms = query.softRegionTerms
        let serviceAreas = document.serviceAreas.isEmpty
            ? ExchangeDeclaredServiceAreaSupport.hydrate(fromRegionTags: document.regionTags)
            : document.serviceAreas
        if !softTerms.isEmpty {
            let requirement = ExchangeLocationRequirement(
                displayName: softTerms.first,
                normalizedName: softTerms.first,
                aliases: Array(softTerms.dropFirst()),
                kind: .namedPlace,
                strictness: query.explicitRegionRequired ? .required : .preferred
            )
            let match = ExchangeServiceAreaMatcher.match(
                requirement: requirement,
                serviceAreas: serviceAreas
            )
            declaredScore = match.scoreDelta
        }

        let queryHard = Set(query.hardRegionIDs.map(\.normalizedLooseEnum))
        let docCanonical = Set(document.canonicalRegionIDs.map(\.normalizedLooseEnum))
        let docParent = Set(document.parentRegionIDs.map(\.normalizedLooseEnum))
        let docAliases = Set((document.regionAliases + document.regionTags).map(\.normalizedLooseEnum))

        var legacyScore = 0.0
        if !queryHard.isEmpty {
            let hardHits = queryHard.intersection(docCanonical).count + queryHard.intersection(docParent).count
            if hardHits > 0 {
                legacyScore = 0.12
            } else {
                let softFallback = Set(query.softRegionTerms.map(\.normalizedLooseEnum))
                let aliasHits = softFallback.intersection(docAliases).count
                legacyScore = aliasHits > 0 ? 0.06 : 0.0
            }
        } else {
            let wantedSoft = Set((query.softRegionTerms + query.regionTerms).map(\.normalizedLooseEnum))
            if !wantedSoft.isEmpty {
                let overlapCount = wantedSoft.intersection(docAliases).count
                legacyScore = min(Double(overlapCount) * 0.08, 0.18)
            }
        }

        let textRegionMatchSucceeded = declaredScore > 0 || legacyScore > 0
        let spatialAdjustment = ExchangeSpatialOverlapScoring.evaluate(
            requesterAnchor: query.requesterSpatialAnchor,
            providerAreas: serviceAreas,
            explicitRegionRequired: query.explicitRegionRequired,
            textRegionMatchSucceeded: textRegionMatchSucceeded
        )
        let base = declaredScore + legacyScore * 0.3
        return min(
            base + spatialAdjustment.boost - spatialAdjustment.demotion,
            0.28 + ExchangeSpatialOverlapScoring.maxBoost
        )
    }

    func fulfillmentScore(
        document: ExchangeRetrievalDocument,
        query: ExchangeRetrievalQuery
    ) -> Double {
        guard let wanted = query.fulfillmentMode?.normalizedLooseEnum, !wanted.isEmpty else {
            return 0.0
        }

        let documentModes = Set(document.allFilterTokens.map(\.normalizedLooseEnum))
        guard !documentModes.isEmpty else {
            return query.explicitFulfillmentRequired ? -0.12 : 0.0
        }

        if documentModes.contains(wanted) {
            return 0.10
        }

        return query.explicitFulfillmentRequired ? -0.12 : -0.03
    }

    func reachabilityScore(
        document: ExchangeRetrievalDocument,
        query: ExchangeRetrievalQuery
    ) -> Double {
        var score = 0.0

        if document.acceptingInbound == true {
            score += 0.05
        }

        switch document.accessMode?.normalizedLooseEnum {
        case "direct":
            score += 0.10
        case "intropreferred":
            score += 0.07
        case "introrequired":
            score += (query.reachabilityRequirement == .introAllowed ? 0.04 : -0.02)
        case "closed":
            score -= 0.12
        default:
            break
        }

        if document.routeableOnly == true {
            score += 0.02
        }

        return score
    }

    func freshnessScore(
        document: ExchangeRetrievalDocument
    ) -> Double {
        let age = Date().timeIntervalSince(document.updatedAt)

        if age < 7 * 24 * 60 * 60 {
            return 0.06
        }
        if age < 30 * 24 * 60 * 60 {
            return 0.03
        }
        if age < 90 * 24 * 60 * 60 {
            return 0.01
        }

        return 0.0
    }

    func overlapScore(
        _ queryTerms: [String],
        against docTokens: Set<String>,
        weight: Double,
        cap: Double
    ) -> Double {
        guard !queryTerms.isEmpty, !docTokens.isEmpty else { return 0.0 }

        let normalizedTerms = queryTerms.map(\.normalizedLooseEnum)
        let overlap = normalizedTerms.filter { docTokens.contains($0) }.count
        return min(Double(overlap) * weight, cap)
    }

    func preferredSurfaceOrder(
        _ surfaceType: ExchangeRetrievalDocument.SurfaceType,
        for queryClass: ExchangeIntent.QueryIntentClass
    ) -> Int {
        switch queryClass {
        case .providerSearch, .offerSearch:
            switch surfaceType {
            case .offer: return 0
            case .publicProfileCapability: return 1
            case .publicProfileSeeking: return 2
            case .publicProfile: return 3
            case .publicProfileAffinity: return 4
            case .unknown: return 99
            }

        case .capabilitySearch, .collaborationSearch:
            switch surfaceType {
            case .publicProfileCapability: return 0
            case .publicProfileSeeking: return 1
            case .publicProfile: return 2
            case .offer: return 3
            case .publicProfileAffinity: return 4
            case .unknown: return 99
            }

        case .socialAffinitySearch, .relationshipSearch:
            switch surfaceType {
            case .publicProfileAffinity: return 0
            case .publicProfile: return 1
            case .publicProfileCapability: return 2
            case .publicProfileSeeking: return 3
            case .offer: return 4
            case .unknown: return 99
            }

        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            switch surfaceType {
            case .publicProfileCapability: return 0
            case .publicProfileSeeking: return 1
            case .publicProfile: return 2
            case .offer: return 3
            case .publicProfileAffinity: return 4
            case .unknown: return 99
            }
        }
    }

    func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

extension ExchangeRetrievalEngine {
    /// Soft docKind prior keyed only on typed query routing signals (no raw query inspection).
    static func docKindBias(
        query: ExchangeRetrievalQuery,
        docKind: ExchangeRetrievalDocument.DocKind?
    ) -> Double {
        guard let docKind else { return 0.0 }

        let objectLaneActive = query.queryObjectText != nil

        switch query.queryIntentClass {
        case .capabilitySearch, .collaborationSearch:
            switch docKind {
            case .profileCapability, .profileSeeking:
                return 0.06
            case .profileAbout:
                return -0.05
            default:
                return 0.0
            }

        case .providerSearch:
            switch docKind {
            case .profileCapability, .profileIntro:
                return 0.05
            default:
                return 0.0
            }

        case .socialAffinitySearch, .relationshipSearch:
            switch docKind {
            case .profileAffinity:
                return 0.07
            default:
                return 0.0
            }

        case .offerSearch:
            if objectLaneActive {
                switch docKind {
                case .offerDetail, .offerPackage, .offerFAQ:
                    return -0.05
                default:
                    return 0.0
                }
            }
            switch docKind {
            case .offerDetail:
                return 0.06
            case .offerFAQ, .offerPackage:
                return -0.04
            default:
                return 0.0
            }

        case .followUp, .statusCheck:
            switch docKind {
            case .offerFAQ:
                return 0.06
            default:
                return 0.0
            }

        case .directOutreach, .generalDiscovery:
            return 0.0
        }
    }

    static func docKindSliceGroup(
        for docKind: ExchangeRetrievalDocument.DocKind?
    ) -> String? {
        guard let docKind else { return nil }
        switch docKind {
        case .offerObject:
            return "object"
        case .offerDetail, .offer:
            return "detail"
        case .offerPackage, .offerFAQ:
            return "commercialAux"
        case .profileIntro, .profileAbout, .profileCapability:
            return "profileCore"
        case .profileSeeking:
            return "profileSeeking"
        case .profileAffinity:
            return "profileAffinity"
        }
    }

    static func sliceCapKey(for document: ExchangeRetrievalDocument) -> String? {
        guard let group = docKindSliceGroup(for: document.docKind) else { return nil }
        guard let offerID = document.offerID?.nilIfBlank else {
            // Phase 4C-1: cap offer-scoped slices only; profile slices stay uncapped for broad recall.
            return nil
        }
        return "\(document.counterpartyID)|offer|\(offerID)|\(group)"
    }

    /// Keeps the best-scoring doc per counterparty/offer/docKind group after rerank sort.
    static func applyPerOfferSliceCap(_ sortedCandidates: [Candidate]) -> [Candidate] {
        var seenCapKeys: Set<String> = []
        seenCapKeys.reserveCapacity(sortedCandidates.count)
        var capped: [Candidate] = []
        capped.reserveCapacity(sortedCandidates.count)

        for candidate in sortedCandidates {
            if let capKey = sliceCapKey(for: candidate.document) {
                if seenCapKeys.contains(capKey) {
                    continue
                }
                seenCapKeys.insert(capKey)
            }
            capped.append(candidate)
        }

        return capped
    }

    static func preferredDocKindOrder(
        _ docKind: ExchangeRetrievalDocument.DocKind?,
        for query: ExchangeRetrievalQuery
    ) -> Int {
        guard let docKind else { return 50 }

        let objectLaneActive = query.queryObjectText != nil

        switch query.queryIntentClass {
        case .capabilitySearch, .collaborationSearch:
            switch docKind {
            case .profileCapability: return 0
            case .profileSeeking: return 1
            case .profileIntro: return 2
            case .profileAbout: return 3
            case .profileAffinity: return 4
            default: return 50
            }

        case .providerSearch:
            switch docKind {
            case .profileIntro: return 0
            case .profileCapability: return 1
            case .profileAbout: return 2
            case .profileSeeking: return 3
            case .profileAffinity: return 4
            default: return 50
            }

        case .socialAffinitySearch, .relationshipSearch:
            switch docKind {
            case .profileAffinity: return 0
            case .profileIntro: return 1
            case .profileCapability: return 2
            case .profileAbout: return 3
            case .profileSeeking: return 4
            default: return 50
            }

        case .offerSearch:
            if objectLaneActive {
                switch docKind {
                case .offerObject: return 0
                case .offerDetail: return 1
                case .offerPackage: return 2
                case .offerFAQ: return 3
                default: return 50
                }
            }
            switch docKind {
            case .offerDetail, .offer: return 0
            case .offerObject: return 1
            case .offerPackage: return 2
            case .offerFAQ: return 3
            default: return 50
            }

        case .followUp, .statusCheck:
            switch docKind {
            case .offerFAQ: return 0
            case .offerDetail: return 1
            case .offerPackage: return 2
            case .offerObject: return 3
            default: return 50
            }

        case .directOutreach, .generalDiscovery:
            return 50
        }
    }
}

private extension ExchangeRetrievalDocument {
    var searchableTextTokens: [String] {
        [
            title,
            summary ?? "",
            category ?? "",
            primaryText,
            secondaryText,
            lexicalText,
            semanticText,
            tags.joined(separator: " "),
            regionTags.joined(separator: " "),
            regionAliases.joined(separator: " "),
            providerTerms.joined(separator: " "),
            capabilityTerms.joined(separator: " "),
            affinityTerms.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
    }
}

private extension String {
    var normalizedLooseEnum: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
