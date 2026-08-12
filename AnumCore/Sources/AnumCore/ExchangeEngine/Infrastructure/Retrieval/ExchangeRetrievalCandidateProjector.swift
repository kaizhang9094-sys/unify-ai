import Foundation

#if DEBUG
@inline(__always)
private func exRetrievalProjectorLog(_ message: @autoclosure () -> String) {
    print("[ExchangeRetrievalCandidateProjector] \(message())")
}
#else
@inline(__always)
private func exRetrievalProjectorLog(_ message: @autoclosure () -> String) { }
#endif

/// Projects retrieval-layer candidates back into discovery-layer candidates.
///
/// Design rules:
/// - retrieval decides plausible surface docs
/// - projector restores domain objects without collapsing all surfaces into one blob
/// - coarse discovery signal stays query-class aware
/// - unrelated surfaces should not kill otherwise good candidates
/// - projector does not reinterpret the user request
public struct ExchangeRetrievalCandidateProjector: Sendable {
    public init() {}

    public func project(
        _ candidates: [ExchangeRetrievalEngine.Candidate],
        knownMatches: [ExchangeDirectoryMatch],
        thread: ExchangeThread
    ) -> [ExchangeDiscoveryEngine.DiscoveryCandidate] {
        let lookup = buildMatchLookup(from: knownMatches)
        let objectLaneActive = ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
        let competitiveProvenObjectOfferScores = objectLaneActive
            ? resolvedCompetitiveProvenObjectOfferScores(
                candidates: candidates,
                thread: thread
            )
            : [:]

        var projected: [ExchangeDiscoveryEngine.DiscoveryCandidate] = []
        projected.reserveCapacity(candidates.count)

        for candidate in candidates {
            guard let match = bestMatch(for: candidate.document, lookup: lookup) else {
                exRetrievalProjectorLog(
                    "drop candidate no_match " +
                    "documentID=\(candidate.document.id) " +
                    "surfaceType=\(candidate.document.surfaceType.rawValue) " +
                    "entityType=\(candidate.document.entityType.rawValue) " +
                    "publicProfileID=\(candidate.document.publicProfileID ?? "nil") " +
                    "offerID=\(candidate.document.offerID ?? "nil") " +
                    "counterpartyID=\(candidate.document.counterpartyID) " +
                    "fusedScore=\(String(format: "%.4f", candidate.fusedScore))"
                )
                continue
            }

            let counterparty = match.counterparty
            let publicProfile = match.publicProfile ?? counterparty.publicProfile
            let matchedOffers = selectMatchedOffers(
                for: candidate,
                from: match,
                thread: thread,
                publicProfile: publicProfile,
                competitiveProvenObjectOfferScores: competitiveProvenObjectOfferScores,
                objectLaneActive: objectLaneActive
            )
            let objectProvenance: (provenObjectOfferIDs: Set<String>, objectEvidenceScoreByOfferID: [String: Double]) = {
                guard objectLaneActive else { return ([], [:]) }
                return ExchangeOfferObjectLane.provenanceFromRetrievalHit(
                    document: candidate.document,
                    objectEvidenceScore: candidate.objectEvidenceScore,
                    matchedOffers: matchedOffers,
                    competitiveProvenObjectOfferScores: competitiveProvenObjectOfferScores
                )
            }()

            let scratch = compactRetrievalScratch(from: candidate.document)
            let coarse = buildCoarseSignal(
                document: candidate.document,
                counterparty: counterparty,
                publicProfile: publicProfile,
                matchedOffers: matchedOffers,
                thread: thread,
                fusedScore: candidate.fusedScore
            )

            let posture = buildContactPosture(
                counterparty: counterparty,
                publicProfile: publicProfile,
                thread: thread
            )

            let dominantSurface = dominantSurfaceType(
                document: candidate.document,
                coarse: coarse
            )

            let finalScore = finalProjectedScore(
                fusedScore: candidate.fusedScore,
                coarse: coarse,
                posture: posture,
                document: candidate.document,
                thread: thread
            )

            let semanticTarget = ExchangeSemanticTarget.from(thread: thread)
            let attachPath = ExchangeSemanticProofBuilder.resolveAttachPath(
                document: candidate.document,
                thread: thread,
                objectLaneActive: objectLaneActive,
                legacyProvenObjectOfferIDs: objectProvenance.provenObjectOfferIDs,
                recallObjectEvidenceScore: candidate.objectEvidenceScore
            )
            let semanticProof = ExchangeSemanticProofBuilder.build(
                target: semanticTarget,
                document: candidate.document,
                counterpartyID: counterparty.id,
                matchedOffers: matchedOffers,
                recallObjectEvidenceScore: candidate.objectEvidenceScore,
                coarse: coarse,
                dominantSurfaceKind: ExchangeSemanticProofBuilder.mapDominantSurfaceKind(
                    from: candidate.document,
                    dominantSurface: dominantSurface
                ),
                publicProfile: publicProfile,
                attachPath: attachPath
            )

            exRetrievalProjectorLog(
                "project candidate " +
                "documentID=\(candidate.document.id) " +
                "surfaceType=\(candidate.document.surfaceType.rawValue) " +
                "entityType=\(candidate.document.entityType.rawValue) " +
                "counterpartyID=\(counterparty.id) " +
                "publicProfileID=\(candidate.document.publicProfileID ?? "nil") " +
                "offerID=\(candidate.document.offerID ?? "nil") " +
                "matchedOffers=\(matchedOffers.count) " +
                "queryClass=\(queryIntentClass(from: thread).rawValue) " +
                "surfacePref=\(surfacePreference(from: thread).rawValue) " +
                "fusedScore=\(String(format: "%.4f", candidate.fusedScore)) " +
                "finalScore=\(String(format: "%.4f", finalScore)) " +
                "sources=\(candidate.contributingSources) " +
                "ranks=\(candidate.bestRankBySource) " +
                "queryOverlap=\(coarse.queryTokenOverlap) " +
                "explicitOverlap=\(coarse.explicitTokenOverlap) " +
                "regionOverlap=\(coarse.regionOverlap) " +
                "offerOverlap=\(coarse.offerOverlap) " +
                "capabilityOverlap=\(coarse.capabilityOverlap) " +
                "affinityOverlap=\(coarse.affinityOverlap) " +
                "kindCompatible=\(coarse.kindCompatible) " +
                "placeCompatible=\(coarse.placeCompatible) " +
                "postureBucket=\(posture.bucket.rawValue) " +
                "rationale=\(coarse.rationale)"
            )

            projected.append(
                ExchangeDiscoveryEngine.DiscoveryCandidate(
                    publicProfile: publicProfile,
                    counterparty: counterparty,
                    matchedOffers: matchedOffers,
                    coarse: coarse,
                    posture: posture,
                    dominantSurface: dominantSurface,
                    overallScore: finalScore,
                    provenance: .retrievalProjected,
                    directoryEvidence: .init(
                        retrievalDocuments: match.retrievalDocuments,
                        score: match.score,
                        matchReason: match.matchReason,
                        matchedTerms: match.matchedTerms,
                        reachability: match.reachability,
                        sourceMatchID: match.id,
                        retrievalScratchText: scratch.isEmpty ? nil : scratch
                    ),
                    provenObjectOfferIDs: objectProvenance.provenObjectOfferIDs,
                    objectEvidenceScoreByOfferID: objectProvenance.objectEvidenceScoreByOfferID,
                    semanticProof: semanticProof
                )
            )
        }

        return projected.sorted(by: projectedOrdering)
    }

    private func resolvedCompetitiveProvenObjectOfferScores(
        candidates: [ExchangeRetrievalEngine.Candidate],
        thread: ExchangeThread
    ) -> [String: Double] {
        guard ExchangeOfferObjectLane.isObjectLaneActive(thread: thread) else {
            return [:]
        }

        if let preset = candidates.first(where: { !$0.competitiveProvenObjectOfferScores.isEmpty })?
            .competitiveProvenObjectOfferScores {
            return preset
        }

        let scoreByDocumentID = Dictionary(
            uniqueKeysWithValues: candidates.compactMap { candidate -> (String, Double)? in
                guard let score = candidate.objectEvidenceScore else { return nil }
                return (candidate.document.id, score)
            }
        )

        return ExchangeOfferObjectLane.competitivelyProvenObjectOffers(
            documents: candidates.map(\.document),
            objectEvidenceScoresByDocumentID: scoreByDocumentID
        )
    }
}

private extension ExchangeRetrievalCandidateProjector {
    // MARK: - Lookup

    func buildMatchLookup(
        from matches: [ExchangeDirectoryMatch]
    ) -> [String: ExchangeDirectoryMatch] {
        var lookup: [String: ExchangeDirectoryMatch] = [:]

        for match in matches {
            let counterparty = match.counterparty
            let publicProfile = match.publicProfile ?? counterparty.publicProfile

            lookup["counterparty::\(counterparty.id)"] = match

            if let nodeID = counterparty.identity?.nodeID?.exTrimmed {
                lookup["node::\(nodeID)"] = match
            }

            if let profileID = publicProfile?.id.exTrimmed {
                lookup["profile::\(profileID)"] = match
                lookup["capability::\(profileID)"] = match
                lookup["seeking::\(profileID)"] = match
                lookup["affinity::\(profileID)"] = match
            }

            for offer in match.offers {
                lookup["offer::\(offer.id)"] = match
            }
        }

        return lookup
    }

    func bestMatch(
        for document: ExchangeRetrievalDocument,
        lookup: [String: ExchangeDirectoryMatch]
    ) -> ExchangeDirectoryMatch? {
        if let match = lookup[document.id] {
            return match
        }

        if let offerID = document.offerID,
           let match = lookup["offer::\(offerID)"] {
            return match
        }

        if let profileID = document.publicProfileID {
            switch document.surfaceType {
            case .publicProfileCapability:
                if let match = lookup["capability::\(profileID)"] { return match }
            case .publicProfileSeeking:
                if let match = lookup["seeking::\(profileID)"] { return match }
            case .publicProfileAffinity:
                if let match = lookup["affinity::\(profileID)"] { return match }
            case .publicProfile:
                if let match = lookup["capability::\(profileID)"] { return match }
                if let match = lookup["affinity::\(profileID)"] { return match }
            case .unknown:
                if let match = lookup["capability::\(profileID)"] { return match }
                if let match = lookup["affinity::\(profileID)"] { return match }
            case .offer:
                break
            }

            if let match = lookup["profile::\(profileID)"] {
                return match
            }
        }

        if let nodeID = document.nodeID,
           let match = lookup["node::\(nodeID)"] {
            return match
        }

        if let match = lookup["counterparty::\(document.counterpartyID)"] {
            return match
        }

        return nil
    }

    // MARK: - Surface-aware offer selection

    func selectMatchedOffers(
        for candidate: ExchangeRetrievalEngine.Candidate,
        from match: ExchangeDirectoryMatch,
        thread: ExchangeThread,
        publicProfile: ExchangePublicNodeProfile?,
        competitiveProvenObjectOfferScores: [String: Double],
        objectLaneActive: Bool
    ) -> [ExchangeOffer] {
        let document = candidate.document

        if objectLaneActive,
           ExchangeOfferObjectLane.canAttachOfferFromProvenance(
            document: document,
            objectEvidenceScore: candidate.objectEvidenceScore,
            competitiveProvenObjectOfferScores: competitiveProvenObjectOfferScores
        ) {
            guard let offerID = document.offerID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !offerID.isEmpty else {
                return []
            }
            return match.offers.filter { $0.id == offerID }
        }

        if objectLaneActive {
            #if DEBUG
            exRetrievalProjectorLog(
                "selectMatchedOffers object_lane_no_provenance " +
                "documentID=\(document.id) " +
                "docKind=\(document.docKind?.rawValue ?? "nil") " +
                "objectEvidenceScore=\(candidate.objectEvidenceScore.map { String(format: "%.3f", $0) } ?? "nil")"
            )
            #endif
            return []
        }

        switch document.surfaceType {
        case .offer:
            guard let offerID = document.offerID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !offerID.isEmpty else {
                return []
            }

            let exact = match.offers.filter { $0.id == offerID }

            #if DEBUG
            if exact.isEmpty {
                exRetrievalProjectorLog(
                    "offer document had no hydrated matching offer " +
                    "documentID=\(document.id) " +
                    "offerID=\(offerID) " +
                    "availableOffers=\(match.offers.map(\.id).joined(separator: ","))"
                )
            }
            #endif

            return exact

        case .publicProfileCapability, .publicProfileSeeking, .publicProfileAffinity, .publicProfile, .unknown:
            return inheritedOffersFromParentMatch(
                document: document,
                match: match,
                thread: thread,
                publicProfile: publicProfile
            )
        }
    }

    func compactRetrievalScratch(from document: ExchangeRetrievalDocument) -> String {
        let parts: [String] = [
            document.title,
            document.lexicalText,
            document.semanticText,
            document.primaryText,
            document.secondaryText,
            document.tags.joined(separator: " "),
            document.category ?? "",
            document.regionTags.joined(separator: " ")
        ]
        let joined = parts.joined(separator: " ")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(900))
    }

    /// Active discoverable offers on the directory match that align with the query and/or the fused retrieval row.
    func inheritedOffersFromParentMatch(
        document: ExchangeRetrievalDocument,
        match: ExchangeDirectoryMatch,
        thread: ExchangeThread,
        publicProfile: ExchangePublicNodeProfile?
    ) -> [ExchangeOffer] {
        let lane = ExchangeThreadLaneResolver.lane(for: thread)
        if ExchangeThreadLaneResolver.clearsCommercialOfferAnchor(for: lane) {
            return []
        }

        if ExchangeOfferObjectLane.isProductObjectOfferSearchShape(
            queryIntentClass: queryIntentClass(from: thread),
            surfacePreference: surfacePreference(from: thread),
            searchIntent: thread.facets?.searchIntent
        ) {
            return []
        }

        if ExchangeOfferObjectLane.isObjectLaneActive(thread: thread) {
            return []
        }

        let pool = match.offers.filter {
            $0.status == .active &&
            ($0.visibility == .publicDiscoverable || $0.visibility == .limitedSurface)
        }

        guard !pool.isEmpty else { return [] }

        let requestTokens = retrievalTokens(from: thread)
        let regionRequestTokens = Set(tokenize(regionTerms(from: thread).joined(separator: " ")))
        let hitTokens = retrievalHitTokensForOfferBridge(document: document, publicProfile: publicProfile)

        guard !requestTokens.isEmpty || !regionRequestTokens.isEmpty else {
            #if DEBUG
            exRetrievalProjectorLog(
                "inheritedRemoteOffers count=0 candidate=\(document.id) pool=\(pool.count) reason=no_query_context"
            )
            #endif
            return []
        }

        struct ScoredOffer {
            let offer: ExchangeOffer
            let rank: Int
        }

        var scored: [ScoredOffer] = []
        scored.reserveCapacity(pool.count)

        for offer in pool {
            let offerTok = offerTokens(from: [offer], fallbackDocument: nil)
            let queryHits = requestTokens.intersection(offerTok).count
            let regionHit: Int = {
                guard !regionRequestTokens.isEmpty else { return 0 }
                return regionRequestTokens.intersection(offerTok).isEmpty ? 0 : 1
            }()
            let bridgeHit: Int = {
                guard !hitTokens.isEmpty else { return 0 }
                guard !requestTokens.intersection(hitTokens).isEmpty else { return 0 }
                return hitTokens.intersection(offerTok).isEmpty ? 0 : 1
            }()

            if queryHits > 0 || regionHit > 0 || bridgeHit > 0 {
                let rank = queryHits * 100 + regionHit * 40 + bridgeHit * 25
                scored.append(ScoredOffer(offer: offer, rank: rank))
            }
        }

        let ordered = scored.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
            if lhs.offer.updatedAt != rhs.offer.updatedAt { return lhs.offer.updatedAt > rhs.offer.updatedAt }
            return lhs.offer.id < rhs.offer.id
        }
        .map(\.offer)

        let limit = 8
        let result = Array(ordered.prefix(limit))

        #if DEBUG
        exRetrievalProjectorLog(
            "inheritedRemoteOffers count=\(result.count) candidate=\(document.id) pool=\(pool.count)"
        )
        #endif

        return result
    }

    func retrievalHitTokensForOfferBridge(
        document: ExchangeRetrievalDocument,
        publicProfile: ExchangePublicNodeProfile?
    ) -> Set<String> {
        switch document.surfaceType {
        case .publicProfileCapability, .publicProfile, .unknown:
            return capabilityTokens(from: publicProfile, fallbackDocument: document)
        case .publicProfileSeeking:
            return seekingTokens(from: publicProfile, fallbackDocument: document)
        case .publicProfileAffinity:
            return affinityTokens(from: publicProfile, fallbackDocument: document)
        case .offer:
            return offerTokens(from: [], fallbackDocument: document)
        }
    }

    // MARK: - Coarse signal

    func buildCoarseSignal(
        document: ExchangeRetrievalDocument,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile?,
        matchedOffers: [ExchangeOffer],
        thread: ExchangeThread,
        fusedScore: Double
    ) -> ExchangeDiscoveryEngine.CoarseSignal {
        let queryClass = queryIntentClass(from: thread)

        let requestTokens = retrievalTokens(from: thread)

        let preferredSurfaceTokens = preferredTokens(
            for: document,
            publicProfile: publicProfile,
            matchedOffers: matchedOffers
        )

        let supportingSurfaceTokens = supportingTokens(
            for: document,
            publicProfile: publicProfile,
            matchedOffers: matchedOffers
        )

        let allTokens = preferredSurfaceTokens.union(supportingSurfaceTokens)

        let requestedRegionTokens = Set(
            tokenize(regionTerms(from: thread).joined(separator: " "))
        )

        let candidateRegionTokens = Set(
            tokenize(
                regionText(
                    document: document,
                    publicProfile: publicProfile,
                    matchedOffers: matchedOffers,
                    counterparty: counterparty
                )
            )
        )

        let preferredOverlap = requestTokens.intersection(preferredSurfaceTokens).count
        let supportingOverlap = requestTokens.intersection(supportingSurfaceTokens).count
        let totalOverlap = requestTokens.intersection(allTokens).count
        let regionOverlap = requestedRegionTokens.intersection(candidateRegionTokens).count

        let offerSurfaceTokens = offerTokens(
            from: matchedOffers,
            fallbackDocument: document.surfaceType == .offer ? document : nil
        )
        let capabilityFallbackDocument: ExchangeRetrievalDocument? = {
            switch document.surfaceType {
            case .publicProfileCapability, .publicProfileSeeking, .publicProfile, .unknown:
                return document
            default:
                return nil
            }
        }()
        let affinityFallbackDocument: ExchangeRetrievalDocument? = {
            switch document.surfaceType {
            case .publicProfileAffinity, .publicProfile, .unknown:
                return document
            default:
                return nil
            }
        }()

        let capabilitySurfaceTokens = capabilityTokens(
            from: publicProfile,
            fallbackDocument: capabilityFallbackDocument
        )
        let affinitySurfaceTokens = affinityTokens(
            from: publicProfile,
            fallbackDocument: affinityFallbackDocument
        )

        let offerOverlap = requestTokens.intersection(offerSurfaceTokens).count
        let capabilityOverlap = requestTokens.intersection(capabilitySurfaceTokens).count
        let affinityOverlap = requestTokens.intersection(affinitySurfaceTokens).count

        let explicitOverlap = preferredOverlap
        let queryOverlap = totalOverlap

        let kindCompatible = isKindCompatible(
            document: document,
            counterparty: counterparty,
            thread: thread
        )

        let placeCompatible = isPlaceCompatible(
            document: document,
            publicProfile: publicProfile,
            matchedOffers: matchedOffers,
            counterparty: counterparty,
            thread: thread
        )

        let surfacePrior = surfacePriorScore(
            document: document,
            queryClass: queryClass
        )

        let overlapScore = weightedOverlapScore(
            preferredOverlap: preferredOverlap,
            supportingOverlap: supportingOverlap,
            regionOverlap: regionOverlap,
            queryClass: queryClass
        )

        let compatibilityBonus =
            (kindCompatible ? 0.12 : 0.0) +
            (placeCompatible ? 0.10 : 0.0)

        var retrievalScore = fusedScore + surfacePrior + overlapScore + compatibilityBonus

        let providerAreas: [ExchangeDeclaredServiceArea] = {
            let fromOffers = matchedOffers.flatMap(\.effectiveServiceAreas)
            if !fromOffers.isEmpty { return fromOffers }
            return document.serviceAreas
        }()
        let explicitRegionRequired = thread.facets?.explicitRegionRequired ?? false
        let spatialAdjustment = ExchangeSpatialOverlapScoring.evaluate(
            requesterAnchor: thread.facets?.requesterSpatialAnchor,
            providerAreas: providerAreas,
            explicitRegionRequired: explicitRegionRequired,
            textRegionMatchSucceeded: regionOverlap > 0
        )
        retrievalScore += spatialAdjustment.boost
        retrievalScore -= spatialAdjustment.demotion

        #if DEBUG
        if thread.facets?.requesterSpatialAnchor?.hasResolvedSpatial == true
            || ExchangeSpatialOverlapScoring.providerHasResolvedH3(providerAreas) {
            print(
                ExchangeSpatialOverlapScoring.discoveryLogLine(
                    adjustment: spatialAdjustment,
                    requesterResolved: thread.facets?.requesterSpatialAnchor?.hasResolvedSpatial == true,
                    providerHasResolvedH3: ExchangeSpatialOverlapScoring.providerHasResolvedH3(providerAreas)
                )
            )
        }
        #endif

        return ExchangeDiscoveryEngine.CoarseSignal(
            queryTokenOverlap: queryOverlap,
            explicitTokenOverlap: explicitOverlap,
            regionOverlap: regionOverlap,
            offerOverlap: offerOverlap,
            capabilityOverlap: capabilityOverlap,
            affinityOverlap: affinityOverlap,
            hasPublicProfile: publicProfile != nil,
            hasOffers: !matchedOffers.isEmpty,
            kindCompatible: kindCompatible,
            placeCompatible: placeCompatible,
            trustHintScore: 0,
            retrievalScore: retrievalScore,
            rationale: coarseRationale(
                queryClass: queryClass,
                document: document,
                preferredOverlap: preferredOverlap,
                supportingOverlap: supportingOverlap,
                regionOverlap: regionOverlap,
                kindCompatible: kindCompatible,
                placeCompatible: placeCompatible
            )
        )
    }

    func weightedOverlapScore(
        preferredOverlap: Int,
        supportingOverlap: Int,
        regionOverlap: Int,
        queryClass: ExchangeIntent.QueryIntentClass
    ) -> Double {
        let preferredWeight: Double
        let supportingWeight: Double

        switch queryClass {
        case .providerSearch, .offerSearch:
            preferredWeight = 0.10
            supportingWeight = 0.03

        case .capabilitySearch, .collaborationSearch:
            preferredWeight = 0.09
            supportingWeight = 0.05

        case .socialAffinitySearch, .relationshipSearch:
            preferredWeight = 0.10
            supportingWeight = 0.03

        case .directOutreach, .followUp, .statusCheck:
            preferredWeight = 0.06
            supportingWeight = 0.04

        case .generalDiscovery:
            preferredWeight = 0.08
            supportingWeight = 0.04
        }

        return
            min(Double(preferredOverlap) * preferredWeight, 0.40) +
            min(Double(supportingOverlap) * supportingWeight, 0.18) +
            min(Double(regionOverlap) * 0.08, 0.16)
    }

    func surfacePriorScore(
        document: ExchangeRetrievalDocument,
        queryClass: ExchangeIntent.QueryIntentClass
    ) -> Double {
        switch queryClass {
        case .providerSearch, .offerSearch:
            switch document.surfaceType {
            case .offer: return 0.22
            case .publicProfile: return 0.06
            case .publicProfileCapability: return 0.10
            case .publicProfileSeeking: return 0.10
            case .publicProfileAffinity: return 0.01
            case .unknown: return 0.02
            }

        case .capabilitySearch, .collaborationSearch:
            switch document.surfaceType {
            case .offer: return 0.08
            case .publicProfile: return 0.13
            case .publicProfileCapability: return 0.22
            case .publicProfileSeeking: return 0.22
            case .publicProfileAffinity: return 0.04
            case .unknown: return 0.02
            }

        case .socialAffinitySearch, .relationshipSearch:
            switch document.surfaceType {
            case .offer: return 0.01
            case .publicProfile: return 0.15
            case .publicProfileCapability: return 0.08
            case .publicProfileSeeking: return 0.08
            case .publicProfileAffinity: return 0.22
            case .unknown: return 0.02
            }

        case .directOutreach, .followUp, .statusCheck:
            switch document.surfaceType {
            case .offer: return 0.06
            case .publicProfile: return 0.07
            case .publicProfileCapability: return 0.12
            case .publicProfileSeeking: return 0.12
            case .publicProfileAffinity: return 0.02
            case .unknown: return 0.02
            }

        case .generalDiscovery:
            switch document.surfaceType {
            case .offer: return 0.10
            case .publicProfile: return 0.09
            case .publicProfileCapability: return 0.10
            case .publicProfileSeeking: return 0.10
            case .publicProfileAffinity: return 0.08
            case .unknown: return 0.02
            }
        }
    }

    func coarseRationale(
        queryClass: ExchangeIntent.QueryIntentClass,
        document: ExchangeRetrievalDocument,
        preferredOverlap: Int,
        supportingOverlap: Int,
        regionOverlap: Int,
        kindCompatible: Bool,
        placeCompatible: Bool
    ) -> String {
        if preferredOverlap > 0 {
            return "\(queryClass.rawValue) matched preferred \(document.surfaceType.rawValue) surface"
        }
        if supportingOverlap > 0 {
            return "\(queryClass.rawValue) matched supporting surface"
        }
        if regionOverlap > 0 {
            return "\(queryClass.rawValue) matched region only"
        }
        if kindCompatible && placeCompatible {
            return "\(queryClass.rawValue) kept by compatible surface posture"
        }
        return "\(queryClass.rawValue) weak retrieval signal"
    }

    // MARK: - Token surfaces

    func preferredTokens(
        for document: ExchangeRetrievalDocument,
        publicProfile: ExchangePublicNodeProfile?,
        matchedOffers: [ExchangeOffer]
    ) -> Set<String> {
        switch document.surfaceType {
        case .offer:
            return offerTokens(
                from: matchedOffers,
                fallbackDocument: document
            )

        case .publicProfileCapability:
            return capabilityTokens(
                from: publicProfile,
                fallbackDocument: document
            )

        case .publicProfileSeeking:
            return seekingTokens(
                from: publicProfile,
                fallbackDocument: document
            )

        case .publicProfileAffinity:
            return affinityTokens(
                from: publicProfile,
                fallbackDocument: document
            )

        case .publicProfile:
            return capabilityTokens(from: publicProfile, fallbackDocument: document)
                .union(seekingTokens(from: publicProfile, fallbackDocument: document))
                .union(affinityTokens(from: publicProfile, fallbackDocument: document))

        case .unknown:
            return capabilityTokens(from: publicProfile, fallbackDocument: document)
                .union(seekingTokens(from: publicProfile, fallbackDocument: document))
                .union(affinityTokens(from: publicProfile, fallbackDocument: document))
        }
    }

    func supportingTokens(
        for document: ExchangeRetrievalDocument,
        publicProfile: ExchangePublicNodeProfile?,
        matchedOffers: [ExchangeOffer]
    ) -> Set<String> {
        switch document.surfaceType {
        case .offer:
            return capabilityTokens(from: publicProfile, fallbackDocument: nil)

        case .publicProfileCapability:
            return offerTokens(from: matchedOffers, fallbackDocument: nil)
                .union(affinityTokens(from: publicProfile, fallbackDocument: nil))

        case .publicProfileSeeking:
            return offerTokens(from: matchedOffers, fallbackDocument: nil)
                .union(affinityTokens(from: publicProfile, fallbackDocument: nil))

        case .publicProfileAffinity:
            return capabilityTokens(from: publicProfile, fallbackDocument: nil)

        case .publicProfile:
            return offerTokens(from: matchedOffers, fallbackDocument: nil)

        case .unknown:
            return offerTokens(from: matchedOffers, fallbackDocument: nil)
        }
    }

    func offerTokens(
        from offers: [ExchangeOffer],
        fallbackDocument: ExchangeRetrievalDocument?
    ) -> Set<String> {
        var values: [String] = []

        for offer in offers {
            values.append(offer.title)
            if let summary = offer.summary { values.append(summary) }
            if let category = offer.category { values.append(category) }
            values.append(contentsOf: offer.tags)
            values.append(contentsOf: offer.regionTags)
            values.append(contentsOf: offer.regionAliases)
            values.append(contentsOf: offer.semantic.searchableTerms)
            if let note = offer.semantic.notes { values.append(note) }
            if let leadTime = offer.fulfillment.leadTimeNote { values.append(leadTime) }
            if let capacity = offer.fulfillment.capacityNote { values.append(capacity) }
        }

        if values.isEmpty, let fallbackDocument {
            values.append(fallbackDocument.title)
            if let summary = fallbackDocument.summary { values.append(summary) }
            if let category = fallbackDocument.category { values.append(category) }
            values.append(contentsOf: fallbackDocument.tags)
            values.append(contentsOf: fallbackDocument.regionTags)
            values.append(fallbackDocument.lexicalText)
            values.append(fallbackDocument.semanticText)
        }

        return Set(tokenize(values.joined(separator: " ")))
    }

    func capabilityTokens(
        from profile: ExchangePublicNodeProfile?,
        fallbackDocument: ExchangeRetrievalDocument?
    ) -> Set<String> {
        var values: [String] = []

        if let profile {
            if let displayName = profile.displayName { values.append(displayName) }
            if let headline = profile.headline { values.append(headline) }
            if let summary = profile.summary { values.append(summary) }
            values.append(contentsOf: profile.activityTags)
            values.append(contentsOf: profile.regionTags)
            values.append(contentsOf: profile.semantic.searchableTerms)
            if let note = profile.semantic.notes { values.append(note) }
            if let approach = profile.approach.note { values.append(approach) }
        }

        if values.isEmpty, let fallbackDocument {
            values.append(fallbackDocument.title)
            if let summary = fallbackDocument.summary { values.append(summary) }
            if let category = fallbackDocument.category { values.append(category) }
            values.append(contentsOf: fallbackDocument.tags)
            values.append(contentsOf: fallbackDocument.regionTags)
            values.append(fallbackDocument.lexicalText)
            values.append(fallbackDocument.semanticText)
        }

        return Set(tokenize(values.joined(separator: " ")))
    }

    func seekingTokens(
        from profile: ExchangePublicNodeProfile?,
        fallbackDocument: ExchangeRetrievalDocument?
    ) -> Set<String> {
        var values: [String] = []

        if let profile {
            values.append(contentsOf: profile.openTo)
        }

        if values.isEmpty, let fallbackDocument {
            values.append(fallbackDocument.primaryText)
            values.append(fallbackDocument.secondaryText)
            values.append(contentsOf: fallbackDocument.capabilityTerms)
            values.append(contentsOf: fallbackDocument.tags)
        }

        return Set(tokenize(values.joined(separator: " ")))
    }

    func affinityTokens(
        from profile: ExchangePublicNodeProfile?,
        fallbackDocument: ExchangeRetrievalDocument?
    ) -> Set<String> {
        var values: [String] = []

        if let profile {
            values.append(contentsOf: profile.interests)
            if let headline = profile.headline { values.append(headline) }
        }

        if values.isEmpty, let fallbackDocument {
            values.append(fallbackDocument.title)
            if let summary = fallbackDocument.summary { values.append(summary) }
            values.append(contentsOf: fallbackDocument.tags)
            values.append(contentsOf: fallbackDocument.regionTags)
            values.append(fallbackDocument.lexicalText)
            values.append(fallbackDocument.semanticText)
        }

        return Set(tokenize(values.joined(separator: " ")))
    }

    // MARK: - Compatibility

    func isKindCompatible(
        document: ExchangeRetrievalDocument,
        counterparty: ExchangeCounterparty,
        thread: ExchangeThread
    ) -> Bool {
        guard let targetKind = targetKind(from: thread), targetKind != .unknown else {
            return true
        }

        switch targetKind {
        case .provider:
            switch document.surfaceType {
            case .offer, .publicProfileCapability, .publicProfileSeeking, .publicProfile, .unknown:
                return true
            case .publicProfileAffinity:
                return false
            }

        case .business, .organization:
            return counterparty.kind == .business || counterparty.kind == .organization

        case .group:
            return counterparty.kind == .group

        case .person:
            switch document.surfaceType {
            case .publicProfileAffinity, .publicProfile, .unknown:
                return true
            case .offer:
                return false
            case .publicProfileCapability, .publicProfileSeeking:
                return counterparty.kind == .person
            }

        case .secretaryNode:
            return counterparty.kind == .secretaryNode

        case .unknown:
            return true
        }
    }

    func isPlaceCompatible(
        document: ExchangeRetrievalDocument,
        publicProfile: ExchangePublicNodeProfile?,
        matchedOffers: [ExchangeOffer],
        counterparty: ExchangeCounterparty,
        thread: ExchangeThread
    ) -> Bool {
        let regionRequirements = regionTerms(from: thread)
        guard !regionRequirements.isEmpty else { return true }

        let requested = Set(tokenize(regionRequirements.joined(separator: " ")))
        guard !requested.isEmpty else { return true }

        let candidate = Set(
            tokenize(
                regionText(
                    document: document,
                    publicProfile: publicProfile,
                    matchedOffers: matchedOffers,
                    counterparty: counterparty
                )
            )
        )

        return !requested.isDisjoint(with: candidate)
    }

    func regionText(
        document: ExchangeRetrievalDocument,
        publicProfile: ExchangePublicNodeProfile?,
        matchedOffers: [ExchangeOffer],
        counterparty: ExchangeCounterparty
    ) -> String {
        var values: [String] = []

        if let location = counterparty.location?.summaryLine {
            values.append(location)
        }

        if let publicProfile {
            values.append(publicProfile.regionTags.joined(separator: " "))
            if let summary = publicProfile.summary { values.append(summary) }
            if let headline = publicProfile.headline { values.append(headline) }
        }

        for offer in matchedOffers {
            values.append(offer.regionTags.joined(separator: " "))
            if let summary = offer.summary { values.append(summary) }
            if let category = offer.category { values.append(category) }
        }

        values.append(document.regionTags.joined(separator: " "))
        values.append(document.lexicalText)
        values.append(document.semanticText)

        return values.joined(separator: " ")
    }

    // MARK: - Contact posture

    func buildContactPosture(
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile?,
        thread: ExchangeThread
    ) -> ExchangeDiscoveryEngine.ContactPosture {
        guard let publicProfile else {
            return .init(
                bucket: .visibleButWeak,
                preview: "No explicit public profile is attached.",
                explicitOpenness: false,
                requiresIntroduction: false
            )
        }

        guard publicProfile.visibility != .hidden else {
            return .init(
                bucket: .unusable,
                preview: "The public surface is hidden.",
                explicitOpenness: false,
                requiresIntroduction: false
            )
        }

        if publicProfile.availability == .unavailable {
            return .init(
                bucket: .visibleButBlocked,
                preview: "The public surface exists, but is currently unavailable.",
                explicitOpenness: true,
                requiresIntroduction: false
            )
        }

        if publicProfile.reachability.acceptingInbound == false {
            return .init(
                bucket: .visibleButBlocked,
                preview: "The public surface exists, but is not currently accepting inbound coordination.",
                explicitOpenness: true,
                requiresIntroduction: false
            )
        }

        switch publicProfile.reachability.accessMode {
        case .direct:
            return .init(
                bucket: .contactable,
                preview: "Relevant public surface with direct contact allowed.",
                explicitOpenness: true,
                requiresIntroduction: false
            )

        case .introPreferred:
            return .init(
                bucket: .contactable,
                preview: "Relevant public surface with direct contact allowed; introduction is preferred.",
                explicitOpenness: true,
                requiresIntroduction: false
            )

        case .introRequired:
            let hasTrustedIntro = threadHasTrustedIntroduction(thread)
            return .init(
                bucket: hasTrustedIntro ? .contactable : .introRequired,
                preview: hasTrustedIntro
                    ? "Relevant public surface with an introduction-qualified path."
                    : "Relevant public surface found, but introduction is required.",
                explicitOpenness: true,
                requiresIntroduction: true
            )

        case .closed:
            return .init(
                bucket: .visibleButBlocked,
                preview: "Relevant public surface found, but contact is currently closed.",
                explicitOpenness: true,
                requiresIntroduction: false
            )
        }
    }

    func dominantSurfaceType(
        document: ExchangeRetrievalDocument,
        coarse: ExchangeDiscoveryEngine.CoarseSignal
    ) -> ExchangeDiscoveryEngine.DiscoveryCandidate.SurfaceType {
        if coarse.offerOverlap >= coarse.capabilityOverlap &&
            coarse.offerOverlap >= coarse.affinityOverlap &&
            coarse.offerOverlap > 0 {
            return .offer
        }

        if coarse.affinityOverlap >= coarse.offerOverlap &&
            coarse.affinityOverlap >= coarse.capabilityOverlap &&
            coarse.affinityOverlap > 0 {
            return .affinity
        }

        if coarse.capabilityOverlap > 0 {
            return .capability
        }

        switch document.surfaceType {
        case .offer:
            return .offer
        case .publicProfileCapability:
            return .capability
        case .publicProfileSeeking:
            return .capability
        case .publicProfileAffinity:
            return .affinity
        case .publicProfile:
            switch document.docKind {
            case .profileIntro, .profileAbout, .profileCapability, .profileSeeking:
                return .capability
            case .profileAffinity:
                return .affinity
            case nil, .offerObject, .offerDetail, .offerPackage, .offerFAQ, .offer:
                return .affinity
            }
        case .unknown:
            return .unknown
        }
    }

    func finalProjectedScore(
        fusedScore: Double,
        coarse: ExchangeDiscoveryEngine.CoarseSignal,
        posture: ExchangeDiscoveryEngine.ContactPosture,
        document: ExchangeRetrievalDocument,
        thread: ExchangeThread
    ) -> Double {
        let postureBonus: Double = {
            switch posture.bucket {
            case .contactable: return 0.20
            case .introRequired: return 0.08
            case .visibleButBlocked: return -0.02
            case .visibleButWeak: return -0.03
            case .unusable: return -0.20
            }
        }()

        let surfacePreferenceBonus: Double = {
            let preferred = surfacePreference(from: thread)
            switch (preferred, document.surfaceType) {
            case (.offer, .offer): return 0.08
            case (.capability, .publicProfileCapability), (.capability, .publicProfileSeeking), (.capability, .publicProfile): return 0.08
            case (.affinity, .publicProfileAffinity), (.affinity, .publicProfile): return 0.08
            case (.mixed, _): return 0.03
            default: return 0.0
            }
        }()

        return fusedScore + postureBonus + surfacePreferenceBonus + (coarse.explicitTokenOverlap > 0 ? 0.04 : 0.0)
    }

    // MARK: - Thread signal helpers

    func queryIntentClass(from thread: ExchangeThread) -> ExchangeIntent.QueryIntentClass {
        thread.facets?.queryIntentClass ?? thread.intent.queryIntentClass
    }

    func surfacePreference(from thread: ExchangeThread) -> ExchangeIntent.SurfacePreference {
        thread.facets?.surfacePreference ?? thread.intent.surfacePreference
    }
    
    func targetKind(from thread: ExchangeThread) -> ExchangeIntentFacets.TargetKind? {
        thread.facets?.targetKind
    }

    func retrievalTokens(from thread: ExchangeThread) -> Set<String> {
        let interpretationSemanticTags = thread.interpretation?.semanticTags ?? []
        let interpretationTargetTags = thread.interpretation?.targetTags ?? []
        let interpretationDiscoveryKeywords = thread.interpretation?.discoveryKeywords ?? []

        let facetPrimaryKeywords = thread.facets?.primaryKeywords ?? []
        let facetSecondaryKeywords = thread.facets?.secondaryKeywords ?? []
        let facetProviderTerms = thread.facets?.providerTerms ?? []
        let facetCapabilityTerms = thread.facets?.capabilityTerms ?? []
        let facetAffinityTerms = thread.facets?.affinityTerms ?? []
        let facetRegionTerms = thread.facets?.regionTerms ?? []

        let freeTextValues = [
            thread.intent.objective,
            thread.intent.targetDescription,
            thread.primarySearchText
        ].compactMap { $0 }

        let values =
            interpretationSemanticTags +
            interpretationTargetTags +
            interpretationDiscoveryKeywords +
            facetPrimaryKeywords +
            facetSecondaryKeywords +
            facetProviderTerms +
            facetCapabilityTerms +
            facetAffinityTerms +
            facetRegionTerms +
            freeTextValues

        return Set(tokenize(values.joined(separator: " ")))
    }

    func regionTerms(from thread: ExchangeThread) -> [String] {
        var values: [String] = []
        values.append(contentsOf: thread.facets?.regionTerms ?? [])

        if let placeName = thread.facets?.placeName?.exTrimmed {
            values.append(placeName)
        }

        if let locationText = thread.facets?.locationText?.exTrimmed {
            values.append(locationText)
        }

        for constraint in thread.intent.constraints {
            let key = constraint.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = constraint.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && (
                key.contains("location") ||
                key.contains("region") ||
                key.contains("place") ||
                key.contains("city")
            ) {
                values.append(value)
            }
        }

        return dedupe(values)
    }

    func threadHasTrustedIntroduction(_ thread: ExchangeThread) -> Bool {
        if let selectedPath = thread.selectedPath,
           selectedPath.accessMode == .introOnly && selectedPath.status == .selected {
            return true
        }

        if let mode = thread.metadata["contact_mode"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           mode == "introduced" || mode == "trusted_path" {
            return true
        }

        if let trustedPathID = thread.metadata["trusted_path_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !trustedPathID.isEmpty {
            return true
        }

        return false
    }

    // MARK: - Ordering

    func projectedOrdering(
        lhs: ExchangeDiscoveryEngine.DiscoveryCandidate,
        rhs: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Bool {
        if lhs.posture.bucket != rhs.posture.bucket {
            return lhs.posture.bucket.rawValue > rhs.posture.bucket.rawValue
        }
        if lhs.overallScore != rhs.overallScore {
            return lhs.overallScore > rhs.overallScore
        }
        if lhs.coarse.explicitTokenOverlap != rhs.coarse.explicitTokenOverlap {
            return lhs.coarse.explicitTokenOverlap > rhs.coarse.explicitTokenOverlap
        }
        if lhs.coarse.queryTokenOverlap != rhs.coarse.queryTokenOverlap {
            return lhs.coarse.queryTokenOverlap > rhs.coarse.queryTokenOverlap
        }
        return lhs.counterparty.id < rhs.counterparty.id
    }

    // MARK: - Utilities

    func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            guard let cleaned = value.exTrimmed else { continue }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(cleaned)
        }

        return output
    }

    func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter {
                !$0.isEmpty &&
                !$0.exProjectorStopWord &&
                !$0.exProjectorActionWord
            }
    }
}

private extension String {
    var exTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var exProjectorStopWord: Bool {
        [
            "the", "a", "an", "for", "to", "with", "and", "or", "of", "in", "on",
            "my", "me", "someone", "somebody", "person", "people", "company",
            "help", "need", "want", "looking", "look", "good", "best", "top"
        ].contains(self)
    }

    var exProjectorActionWord: Bool {
        [
            "find", "search", "source", "locate", "draft", "drafted", "outreach",
            "message", "messages", "email", "emails", "contact", "contacting",
            "send", "sending", "reach", "reaching", "prepare", "prepared", "show"
        ].contains(self)
    }
}
