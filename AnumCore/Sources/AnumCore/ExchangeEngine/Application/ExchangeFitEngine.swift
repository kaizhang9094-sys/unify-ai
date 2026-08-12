import Foundation

#if DEBUG
@inline(__always)
private func exFitLog(_ message: @autoclosure () -> String) {
    print("[ExchangeFitEngine] \(message())")
}
#else
@inline(__always)
private func exFitLog(_ message: @autoclosure () -> String) { }
#endif

/// Fit scorer for already-shortlisted discovery candidates.
///
/// Contract:
/// - DiscoveryEngine decides what is plausibly relevant
/// - FitEngine refines an already-shortlisted set
/// - FitEngine must not become a second broad retrieval engine
///
/// Updated design:
/// - respects discovery prior
/// - respects dominant public surface for the current query class
/// - scores offer / capability / affinity evidence separately
/// - uses queryIntentClass-aware weighting
/// - keeps reasons / cautions / recommendation legible
public struct ExchangeFitEngine: Sendable {
    public init() {}

    // MARK: - Public entrypoints

    public func evaluate(
        thread: ExchangeThread,
        counterparties: [ExchangeCounterparty]
    ) -> [ExchangeMatch] {
        let candidates = counterparties.map { counterparty in
            ExchangeDiscoveryEngine.DiscoveryCandidate(
                publicProfile: counterparty.publicProfile,
                counterparty: counterparty,
                matchedOffers: [],
                coarse: .init(
                    queryTokenOverlap: 0,
                    explicitTokenOverlap: 0,
                    regionOverlap: 0,
                    offerOverlap: 0,
                    capabilityOverlap: 0,
                    affinityOverlap: 0,
                    hasPublicProfile: counterparty.publicProfile != nil,
                    hasOffers: false,
                    kindCompatible: true,
                    placeCompatible: true,
                    trustHintScore: 0,
                    retrievalScore: 0,
                    rationale: "legacy-fit-path"
                ),
                posture: .init(
                    bucket: counterparty.publicProfile == nil ? .visibleButWeak : .contactable,
                    preview: counterparty.publicProfile == nil
                        ? "No explicit public profile."
                        : "Public profile present.",
                    explicitOpenness: counterparty.publicProfile != nil,
                    requiresIntroduction: counterparty.requiresIntroductionInPrinciple
                ),
                dominantSurface: inferredLegacyDominantSurface(
                    for: counterparty,
                    thread: thread
                ),
                overallScore: 0
            )
        }

        return evaluate(
            thread: thread,
            candidates: candidates
        )
    }

    public func evaluate(
        thread: ExchangeThread,
        candidates: [ExchangeDiscoveryEngine.DiscoveryCandidate]
    ) -> [ExchangeMatch] {
        exFitLog(
            "evaluate start " +
            "threadID=\(thread.id.uuidString) " +
            "intent=\(thread.intent.kind.rawValue) " +
            "queryIntentClass=\((thread.facets?.queryIntentClass ?? thread.intent.queryIntentClass).rawValue) " +
            "candidates=\(candidates.count)"
        )

        let matches = candidates
            .map { evaluateSingle(thread: thread, candidate: $0, trustedProfile: nil) }
            .sorted(by: matchOrdering)

        if let top = matches.first {
            exFitLog(
                "evaluate done " +
                "matches=\(matches.count) " +
                "topCounterpartyID=\(top.counterpartyID) " +
                "topScore=\(String(format: "%.3f", top.score)) " +
                "strength=\(top.strength.rawValue)"
            )
        } else {
            exFitLog("evaluate done matches=0")
        }

        return matches
    }

    public func evaluate(
        thread: ExchangeThread,
        candidates: [ExchangeDiscoveryEngine.DiscoveryCandidate],
        store: any ExchangeStore,
        localNodeID: String?
    ) async throws -> [ExchangeMatch] {
        exFitLog(
            "evaluate trust-aware start " +
            "threadID=\(thread.id.uuidString) " +
            "candidates=\(candidates.count) " +
            "localNodeID=\(localNodeID ?? "nil")"
        )

        var profilesByCounterpartyID: [String: ExchangeTrustedNodeProfile] = [:]
        profilesByCounterpartyID.reserveCapacity(candidates.count)

        for candidate in candidates {
            let trustedNodeID = candidate.counterparty.identity?.nodeID ?? candidate.counterparty.id
            if let profile = try await store.fetchTrustedNodeProfile(
                nodeID: trustedNodeID,
                forSourceNodeID: localNodeID
            ) {
                profilesByCounterpartyID[candidate.counterparty.id] = profile
            }
        }

        let matches = candidates
            .map {
                evaluateSingle(
                    thread: thread,
                    candidate: $0,
                    trustedProfile: profilesByCounterpartyID[$0.counterparty.id]
                )
            }
            .sorted(by: matchOrdering)

        if let top = matches.first {
            exFitLog(
                "evaluate trust-aware done " +
                "matches=\(matches.count) " +
                "topCounterpartyID=\(top.counterpartyID) " +
                "topScore=\(String(format: "%.3f", top.score))"
            )
        } else {
            exFitLog("evaluate trust-aware done matches=0")
        }

        return matches
    }

    public func evaluate(
        thread: ExchangeThread,
        counterparties: [ExchangeCounterparty],
        store: any ExchangeStore,
        localNodeID: String?
    ) async throws -> [ExchangeMatch] {
        let candidates = counterparties.map { counterparty in
            ExchangeDiscoveryEngine.DiscoveryCandidate(
                publicProfile: counterparty.publicProfile,
                counterparty: counterparty,
                matchedOffers: [],
                coarse: .init(
                    queryTokenOverlap: 0,
                    explicitTokenOverlap: 0,
                    regionOverlap: 0,
                    offerOverlap: 0,
                    capabilityOverlap: 0,
                    affinityOverlap: 0,
                    hasPublicProfile: counterparty.publicProfile != nil,
                    hasOffers: false,
                    kindCompatible: true,
                    placeCompatible: true,
                    trustHintScore: 0,
                    retrievalScore: 0,
                    rationale: "legacy-fit-path"
                ),
                posture: .init(
                    bucket: counterparty.publicProfile == nil ? .visibleButWeak : .contactable,
                    preview: counterparty.publicProfile == nil
                        ? "No explicit public profile."
                        : "Public profile present.",
                    explicitOpenness: counterparty.publicProfile != nil,
                    requiresIntroduction: counterparty.requiresIntroductionInPrinciple
                ),
                dominantSurface: inferredLegacyDominantSurface(
                    for: counterparty,
                    thread: thread
                ),
                overallScore: 0
            )
        }

        return try await evaluate(
            thread: thread,
            candidates: candidates,
            store: store,
            localNodeID: localNodeID
        )
    }
}

private extension ExchangeFitEngine {
    // MARK: - Core evaluation
    
    func inferredLegacyDominantSurface(
        for counterparty: ExchangeCounterparty,
        thread: ExchangeThread
    ) -> ExchangeDiscoveryEngine.DiscoveryCandidate.SurfaceType {
        guard counterparty.publicProfile != nil else { return .unknown }

        let queryClass = thread.facets?.queryIntentClass ?? thread.intent.queryIntentClass

        switch queryClass {
        case .providerSearch, .offerSearch:
            return .offer
        case .capabilitySearch, .collaborationSearch:
            return .capability
        case .socialAffinitySearch, .relationshipSearch:
            return .affinity
        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return .mixed
        }
    }
    
    func makeMatchMetadata(
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> [String: String] {
        var metadata: [String: String] = [:]

        func put(_ key: String, _ value: String?) {
            guard let value else { return }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            metadata[key] = String(trimmed.prefix(500))
        }

        func putList(_ key: String, _ values: [String]) {
            let cleaned = values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !cleaned.isEmpty else { return }

            metadata[key] = String(cleaned.joined(separator: ", ").prefix(500))
        }

        put("counterparty_id", candidate.counterparty.id)
        put("counterparty_name", candidate.counterparty.bestDisplayLine)

        if let profile = candidate.publicProfile {
            put("public_profile_id", profile.id)
            put("public_profile_display_name", profile.displayName)
            put("public_profile_headline", profile.headline)
            put("public_profile_summary", profile.summary)
            putList("public_profile_interests", profile.interests)
            putList("public_profile_offers", profile.offers)
            putList("public_profile_open_to", profile.openTo)
            putList("public_profile_activity_tags", profile.activityTags)
            putList("public_profile_regions", profile.regionTags)
            put("public_profile_visibility", profile.visibility.rawValue)
            put("public_profile_availability", profile.availability.rawValue)
            put("public_profile_access_mode", profile.reachability.accessMode.rawValue)
        }

        if let offer = candidate.matchedOffers.first {
            put("selected_offer_id", offer.id)
            put("selected_offer_title", offer.title)
            put("selected_offer_summary", offer.summary)
            put("selected_offer_category", offer.category)
            putList("selected_offer_tags", offer.tags)
            putList("selected_offer_regions", offer.regionTags)
            put("selected_offer_status", offer.status.rawValue)
            put("selected_offer_visibility", offer.visibility.rawValue)
        }

        if candidate.matchedOffers.count > 1 {
            let titles = candidate.matchedOffers.map(\.title)
            putList("matched_offer_titles", titles)
        }

        return metadata
    }
    
    func evaluateSingle(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        trustedProfile: ExchangeTrustedNodeProfile?
    ) -> ExchangeMatch {
        let queryClass: ExchangeIntent.QueryIntentClass =
            thread.facets?.queryIntentClass ?? thread.intent.queryIntentClass

        let canonicalSI = thread.facets?.searchIntent

        let retrievalPrior = scoreRetrievalPrior(candidate: candidate)
        let lexicalOfferEvidence = scoreOfferEvidence(thread: thread, candidate: candidate)
        var offerEvidence = lexicalOfferEvidence
        let capabilityEvidence = scoreCapabilityEvidence(thread: thread, candidate: candidate)
        let affinityEvidence = scoreAffinityEvidence(thread: thread, candidate: candidate)

        var forcedWeakDueToObjectMismatch = false
        var maxObjectEvidence: Double = 0
        var objectLaneOfferEvidence: Double?
        let objectLaneActive = ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
        if objectLaneActive {
            if candidate.provenObjectOfferIDs.isEmpty {
                forcedWeakDueToObjectMismatch = true
            } else if candidate.matchedOffers.contains(where: { !candidate.provenObjectOfferIDs.contains($0.id) }) {
                forcedWeakDueToObjectMismatch = true
            } else {
                objectLaneOfferEvidence = scoreObjectLaneOfferEvidence(
                    thread: thread,
                    candidate: candidate,
                    lexicalOfferEvidence: lexicalOfferEvidence
                )
                maxObjectEvidence = maxQualifyingObjectEvidenceScore(for: candidate)
                exFitLog(
                    "[FitObjectEvidence] threadID=\(thread.id.uuidString) " +
                    "counterpartyID=\(candidate.counterparty.id) " +
                    "offerIDs=\(Array(candidate.provenObjectOfferIDs).sorted().joined(separator: ",")) " +
                    "maxObjectEvidence=\(String(format: "%.3f", maxObjectEvidence)) " +
                    "lexicalOfferEvidence=\(String(format: "%.3f", lexicalOfferEvidence)) " +
                    "finalOfferEvidence=\(String(format: "%.3f", objectLaneOfferEvidence ?? lexicalOfferEvidence))"
                )
            }
        }

        let proof = candidate.semanticProof
        let proofShaping = applySemanticProofOfferShaping(
            thread: thread,
            candidate: candidate,
            lexicalOfferEvidence: lexicalOfferEvidence,
            objectLaneActive: objectLaneActive,
            objectLaneOfferEvidence: objectLaneOfferEvidence,
            forcedWeakDueToObjectMismatch: forcedWeakDueToObjectMismatch
        )
        offerEvidence = proofShaping.offerEvidence
        if proofShaping.forcedWeak {
            forcedWeakDueToObjectMismatch = true
        }
        if objectLaneActive, forcedWeakDueToObjectMismatch {
            offerEvidence = min(offerEvidence, 0.10)
        }

        let surfaceFit = scoreSurfaceFit(
            queryClass: queryClass,
            candidate: candidate,
            offerEvidence: offerEvidence,
            capabilityEvidence: capabilityEvidence,
            affinityEvidence: affinityEvidence
        )

        let constraintFit = if let facets = thread.facets, let si = facets.searchIntent {
            scoreCanonicalConstraintFit(
                si: si,
                thread: thread,
                facets: facets,
                candidate: candidate
            )
        } else {
            scoreLegacyConstraintFit(thread: thread, candidate: candidate)
        }

        let trustFit = scoreTrustFit(candidate: candidate, trustedProfile: trustedProfile)
        let contactFit = scoreContactFit(candidate: candidate)

        let timingFit: Double = if let si = canonicalSI {
            scoreCanonicalTimingFit(si: si, thread: thread, candidate: candidate)
        } else {
            scoreTimingFit(thread: thread, candidate: candidate)
        }

        let finalScore = weightedScore(
            queryClass: queryClass,
            retrievalPrior: retrievalPrior,
            offerEvidence: offerEvidence,
            capabilityEvidence: capabilityEvidence,
            affinityEvidence: affinityEvidence,
            surfaceFit: surfaceFit,
            constraintFit: constraintFit,
            trustFit: trustFit,
            contactFit: contactFit,
            timingFit: timingFit
        )

        let strength = forcedWeakDueToObjectMismatch ? .weak : strengthForScore(finalScore)

        let profileFitValue: Double? = {
            guard candidate.publicProfile != nil else { return nil }
            return max(capabilityEvidence, affinityEvidence)
        }()

        let fit = ExchangeMatch.FitSnapshot(
            retrievalFit: retrievalPrior,
            offerFit: candidate.matchedOffers.isEmpty ? nil : offerEvidence,
            profileFit: profileFitValue,
            constraintFit: constraintFit,
            trustFit: trustFit,
            postureFit: contactFit,
            timingFit: timingFit
        )

        let reasons = buildReasons(
            thread: thread,
            candidate: candidate,
            canonicalSI: canonicalSI,
            trustedProfile: trustedProfile,
            retrievalPrior: retrievalPrior,
            offerEvidence: offerEvidence,
            capabilityEvidence: capabilityEvidence,
            affinityEvidence: affinityEvidence,
            surfaceFit: surfaceFit,
            constraintFit: constraintFit,
            trustFit: trustFit,
            contactFit: contactFit,
            timingFit: timingFit
        )

        let cautions = buildCautions(
            thread: thread,
            candidate: candidate,
            canonicalSI: canonicalSI,
            trustedProfile: trustedProfile,
            retrievalPrior: retrievalPrior,
            offerEvidence: offerEvidence,
            capabilityEvidence: capabilityEvidence,
            affinityEvidence: affinityEvidence,
            surfaceFit: surfaceFit,
            constraintFit: constraintFit,
            trustFit: trustFit,
            contactFit: contactFit,
            timingFit: timingFit,
            finalScore: finalScore,
            forcedConcreteObjectMismatch: forcedWeakDueToObjectMismatch
        )

        let recommendation = buildRecommendation(
            candidate: candidate,
            trustedProfile: trustedProfile,
            strength: strength,
            cautions: cautions
        )

        let matchedOfferIDs: [String] = {
            if objectLaneActive {
                return candidate.matchedOffers
                    .filter { candidate.provenObjectOfferIDs.contains($0.id) }
                    .map(\.id)
            }
            if proof.summary.satisfiesMinimumProof,
               let primary = proof.summary.primaryOfferID {
                let qualifying = proof.offerAttachments
                    .filter(\.satisfiesMinimumProof)
                    .map(\.offerID)
                if qualifying.contains(primary) {
                    return [primary]
                }
            }
            return candidate.matchedOffers.map(\.id)
        }()
        let primaryOfferID: String? = {
            if objectLaneActive {
                return ExchangeOfferObjectLane.resolveSelectedOfferID(
                    provenObjectOfferIDs: candidate.provenObjectOfferIDs,
                    objectEvidenceScoreByOfferID: candidate.objectEvidenceScoreByOfferID
                )
            }
            if proof.summary.satisfiesMinimumProof,
               let primary = proof.summary.primaryOfferID {
                return primary
            }
            return candidate.matchedOffers.first?.id
        }()

        let scope: ExchangeMatch.Scope
        if primaryOfferID != nil || !matchedOfferIDs.isEmpty {
            scope = .offer
        } else if candidate.publicProfileID != nil {
            scope = .publicProfile
        } else {
            scope = .counterparty
        }

        exFitLog(
            "[FitScoreBreakdown] threadID=\(thread.id.uuidString) " +
            "counterpartyID=\(candidate.counterparty.id) " +
            "fitScore=\(String(format: "%.3f", finalScore)) " +
            "offerEvidence=\(String(format: "%.3f", offerEvidence)) " +
            "capabilityEvidence=\(String(format: "%.3f", capabilityEvidence)) " +
            "retrievalPrior=\(String(format: "%.3f", retrievalPrior)) " +
            "constraintFit=\(String(format: "%.3f", constraintFit)) " +
            "strength=\(strength.rawValue) " +
            "objectLaneActive=\(objectLaneActive) " +
            "maxObjectEvidence=\(String(format: "%.3f", maxObjectEvidence))"
        )

        exFitLog(
            "candidate final " +
            "counterpartyID=\(candidate.counterparty.id) " +
            "scope=\(scope.rawValue) " +
            "surface=\(candidate.dominantSurface.rawValue) " +
            "queryClass=\(queryClass.rawValue) " +
            "publicProfileID=\(candidate.publicProfileID ?? "nil") " +
            "offerID=\(primaryOfferID ?? "nil") " +
            "matchedOffers=\(matchedOfferIDs.count) " +
            "retrieval=\(String(format: "%.3f", retrievalPrior)) " +
            "offer=\(String(format: "%.3f", offerEvidence)) " +
            "capability=\(String(format: "%.3f", capabilityEvidence)) " +
            "affinity=\(String(format: "%.3f", affinityEvidence)) " +
            "surfaceFit=\(String(format: "%.3f", surfaceFit)) " +
            "constraint=\(String(format: "%.3f", constraintFit)) " +
            "trust=\(String(format: "%.3f", trustFit)) " +
            "contact=\(String(format: "%.3f", contactFit)) " +
            "timing=\(String(format: "%.3f", timingFit)) " +
            "final=\(String(format: "%.3f", finalScore)) " +
            "strength=\(strength.rawValue)"
        )

        return ExchangeMatch(
            threadID: thread.id,
            counterpartyID: candidate.counterparty.id,
            scope: scope,
            publicProfileID: candidate.publicProfileID,
            offerID: primaryOfferID,
            matchedOfferIDs: matchedOfferIDs,
            provenObjectOfferIDs: Array(candidate.provenObjectOfferIDs).sorted(),
            objectEvidenceScoreByOfferID: candidate.objectEvidenceScoreByOfferID,
            status: .candidate,
            strength: strength,
            score: finalScore,
            reasons: reasons,
            cautions: cautions,
            fit: fit,
            recommendation: recommendation,
            metadata: makeMatchMetadata(candidate: candidate),
            semanticProof: proof.isEmpty ? nil : proof
        )
    }

    // MARK: - Scoring dimensions

    func scoreRetrievalPrior(
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        let raw = max(candidate.coarse.retrievalScore, candidate.overallScore)

        let normalized = raw <= 1.0 ? raw : min(raw / 2.5, 1.0)
        let boosted = normalized
            + min(Double(candidate.coarse.explicitTokenOverlap) * 0.02, 0.08)
            + min(Double(candidate.coarse.queryTokenOverlap) * 0.015, 0.06)

        return clamp(boosted)
    }

    func scoreOfferEvidence(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        guard !candidate.matchedOffers.isEmpty else {
            return candidate.dominantSurface == .offer ? 0.16 : 0.08
        }

        let requestTokens = requestIntentTokens(thread)
        guard !requestTokens.isEmpty else { return 0.42 }

        var best = 0.08

        for offer in candidate.matchedOffers {
            let explicitTokens = explicitOfferTokens(offer)
            let overlap = requestTokens.intersection(explicitTokens).count

            var score = overlapScore(
                overlap: overlap,
                high: 5,
                medium: 3,
                low: 1,
                none: 0.16
            )

            if let category = offer.category,
               hasTokenOverlap(category, in: requestTokens) {
                score += 0.10
            }

            if !offer.tags.isEmpty {
                score += min(Double(requestTokens.intersection(Set(offer.tags.flatMap(\.tokens))).count) * 0.025, 0.08)
            }

            if offer.visibility == .publicDiscoverable {
                score += 0.04
            }

            if offer.semantic.fulfillmentModes.contains(.localOnly) ||
                offer.semantic.fulfillmentModes.contains(.localPreferred) ||
                offer.semantic.fulfillmentModes.contains(.inPerson) ||
                offer.semantic.fulfillmentModes.contains(.remoteFriendly) ||
                offer.semantic.fulfillmentModes.contains(.digitalDelivery) ||
                offer.semantic.fulfillmentModes.contains(.shippable) {
                score += 0.03
            }

            best = max(best, clamp(score))
        }

        return best
    }

    private func maxQualifyingObjectEvidenceScore(
        for candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        candidate.objectEvidenceScoreByOfferID
            .filter { entry in
                candidate.provenObjectOfferIDs.contains(entry.key)
                    && entry.value >= ExchangeOfferObjectLane.minimumObjectEvidenceScore
            }
            .values
            .max() ?? 0
    }

    private func scoreObjectLaneOfferEvidence(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        lexicalOfferEvidence: Double
    ) -> Double {
        guard ExchangeOfferObjectLane.isObjectLaneActive(thread: thread) else {
            return lexicalOfferEvidence
        }

        let queryClass = thread.facets?.queryIntentClass ?? thread.intent.queryIntentClass
        guard queryClass == .offerSearch else {
            return lexicalOfferEvidence
        }

        guard !candidate.provenObjectOfferIDs.isEmpty else {
            return lexicalOfferEvidence
        }

        let maxObjectEvidence = maxQualifyingObjectEvidenceScore(for: candidate)
        return clamp(max(lexicalOfferEvidence, maxObjectEvidence))
    }

    func scoreCapabilityEvidence(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        guard let profile = candidate.publicProfile else {
            return candidate.counterparty.publicProfile == nil ? 0.08 : 0.20
        }

        let requestTokens = requestIntentTokens(thread)
        guard !requestTokens.isEmpty else { return 0.38 }

        let explicitTokens = explicitCapabilityTokens(profile)
        let overlap = requestTokens.intersection(explicitTokens).count

        var score = overlapScore(
            overlap: overlap,
            high: 5,
            medium: 3,
            low: 1,
            none: 0.16
        )

        if profile.visibility == .discoverable {
            score += 0.04
        }

        if candidate.posture.explicitOpenness {
            score += 0.05
        }

        if !profile.openTo.isEmpty {
            score += 0.03
        }

        return clamp(score)
    }

    func scoreAffinityEvidence(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        guard let profile = candidate.publicProfile else { return 0.06 }

        let requestTokens = requestIntentTokens(thread)
        guard !requestTokens.isEmpty else { return 0.34 }

        let affinityTokens = explicitAffinityTokens(profile)
        let overlap = requestTokens.intersection(affinityTokens).count

        var score = overlapScore(
            overlap: overlap,
            high: 4,
            medium: 2,
            low: 1,
            none: 0.12
        )

        if !profile.interests.isEmpty {
            score += 0.04
        }

        if !profile.activityTags.isEmpty {
            score += 0.03
        }

        return clamp(score)
    }

    func scoreSurfaceFit(
        queryClass: ExchangeIntent.QueryIntentClass,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        offerEvidence: Double,
        capabilityEvidence: Double,
        affinityEvidence: Double
    ) -> Double {
        let dominantBonus: Double = {
            switch queryClass {
            case .providerSearch, .offerSearch:
                switch candidate.dominantSurface {
                case .offer: return 0.18
                case .capability: return 0.05
                case .affinity: return -0.10
                case .mixed: return 0.08
                case .unknown: return 0.0
                }
            case .capabilitySearch, .collaborationSearch:
                switch candidate.dominantSurface {
                case .offer: return 0.04
                case .capability: return 0.18
                case .affinity: return -0.02
                case .mixed: return 0.08
                case .unknown: return 0.0
                }
            case .socialAffinitySearch, .relationshipSearch:
                switch candidate.dominantSurface {
                case .offer: return -0.10
                case .capability: return 0.05
                case .affinity: return 0.18
                case .mixed: return 0.08
                case .unknown: return 0.0
                }
            case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
                switch candidate.dominantSurface {
                case .offer: return 0.06
                case .capability: return 0.08
                case .affinity: return 0.04
                case .mixed: return 0.08
                case .unknown: return 0.0
                }
            }
        }()

        let evidenceBlend: Double = {
            switch queryClass {
            case .providerSearch, .offerSearch:
                return (offerEvidence * 0.68) + (capabilityEvidence * 0.25) + (affinityEvidence * 0.07)
            case .capabilitySearch, .collaborationSearch:
                return (offerEvidence * 0.20) + (capabilityEvidence * 0.62) + (affinityEvidence * 0.18)
            case .socialAffinitySearch, .relationshipSearch:
                return (offerEvidence * 0.08) + (capabilityEvidence * 0.26) + (affinityEvidence * 0.66)
            case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
                return (offerEvidence * 0.30) + (capabilityEvidence * 0.45) + (affinityEvidence * 0.25)
            }
        }()

        return clamp(evidenceBlend + dominantBonus)
    }

    func scoreLegacyConstraintFit(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        let counterparty = candidate.counterparty
        let offers = candidate.matchedOffers
        let facets = thread.facets

        var score = 0.60

        if candidate.coarse.placeCompatible { score += 0.10 }
        if candidate.coarse.kindCompatible { score += 0.08 }
        if candidate.coarse.regionOverlap > 0 {
            score += min(Double(candidate.coarse.regionOverlap) * 0.05, 0.12)
        }

        if let facets {
            score += localityAlignmentBonus(
                facets: facets,
                counterparty: counterparty,
                offers: offers
            )
            score += fulfillmentAlignmentBonus(
                facets: facets,
                counterparty: counterparty,
                offers: offers
            )
            score += requirementAlignmentBonus(
                facets: facets,
                counterparty: counterparty,
                offers: offers
            )
            score += timeAlignmentBonus(
                facets: facets,
                counterparty: counterparty,
                offers: offers
            ) * 0.5
            score += surfaceSpecificConstraintBonus(
                facets: facets,
                candidate: candidate
            )
        }

        for constraint in thread.intent.constraints {
            let key = constraint.key.lowercased()
            let value = constraint.value.lowercased()

            if key.contains("location") || key.contains("region") || key.contains("city") || key.contains("place") {
                let locationTokens = offerAndProfileLocationTokens(candidate)
                if !Set(value.tokens).intersection(locationTokens).isEmpty {
                    score += 0.10
                } else if constraint.isHardConstraint {
                    score -= 0.18
                }
            }

            if key.contains("timing") || key.contains("time") {
                if thread.posture.urgency == .immediate && counterparty.status != .active {
                    score -= 0.10
                }
            }
        }

        return clamp(score)
    }

    /// Phase 5: canonical `searchIntent` is semantic truth; soft structured slots never penalize.
    func scoreCanonicalConstraintFit(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        thread: ExchangeThread,
        facets: ExchangeIntentFacets,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        let counterparty = candidate.counterparty
        let offers = candidate.matchedOffers

        var score = 0.60

        if candidate.coarse.placeCompatible { score += 0.10 }
        if candidate.coarse.kindCompatible { score += 0.08 }
        if candidate.coarse.regionOverlap > 0 {
            score += min(Double(candidate.coarse.regionOverlap) * 0.05, 0.12)
        }

        score += canonicalLocalityScore(si: si, candidate: candidate)
        score += fulfillmentAlignmentBonus(
            facets: facets,
            counterparty: counterparty,
            offers: offers
        )
        score += canonicalStructuredAlignment(si: si, candidate: candidate)
        score += surfaceSpecificConstraintBonus(
            facets: facets,
            candidate: candidate
        )

        return clamp(score)
    }

    func scoreCanonicalTimingFit(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        let evidenceTokens = durableFitEvidenceTokens(candidate: candidate)
        let haystack = durableFitEvidenceText(candidate: candidate).lowercased()

        if canonicalHasHardTimingRequirement(si: si) {
            var score: Double
            switch thread.posture.urgency {
            case .immediate:
                score = candidate.counterparty.status == .active ? 0.86 : 0.28
            case .high:
                score = candidate.counterparty.status == .active ? 0.74 : 0.40
            case .normal, .low:
                score = 0.58
            }

            let anyMatched = si.timeConstraints.contains {
                canonicalTimeslotMatches($0, evidenceTokens: evidenceTokens, haystackLowercased: haystack)
            }
            if anyMatched {
                score += 0.10
            } else if thread.posture.urgency == .immediate {
                score -= 0.12
            }

            if candidate.matchedOffers.contains(where: { $0.fulfillment.remoteFriendly }) {
                score += 0.04
            }

            return clamp(score)
        }

        var score = 0.64
        if candidate.counterparty.status == .active { score += 0.06 }
        if si.timeConstraints.contains(where: {
            canonicalTimeslotMatches($0, evidenceTokens: evidenceTokens, haystackLowercased: haystack)
        }) {
            score += 0.12
        }
        if candidate.matchedOffers.contains(where: { $0.fulfillment.remoteFriendly }) {
            score += 0.05
        }
        return clamp(score)
    }

    func canonicalHasHardTimingRequirement(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        for c in si.hardConstraints where c.isHardConstraint {
            let k = c.key.lowercased()
            if k.contains("time") || k.contains("timing") || k.contains("schedule") ||
                k.contains("availability") || k.contains("deadline") {
                return true
            }
        }
        for p in si.preferences where p.strength == .required {
            let k = p.key.lowercased()
            if k.contains("time") || k.contains("timing") || k.contains("availability") ||
                k.contains("schedule") {
                return true
            }
        }
        return false
    }

    func canonicalLocalityScore(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        guard !si.places.isEmpty else { return 0.0 }

        let evidenceText = durableFitEvidenceText(candidate: candidate).lowercased()
        let evidenceTokens = durableFitEvidenceTokens(candidate: candidate)

        var delta = 0.0
        for place in si.places {
            let needles = canonicalPlaceEvidenceNeedles(place)
            let hit = needles.contains { needle in
                !needle.isEmpty && (evidenceText.contains(needle) || hasTokenOverlap(needle, in: evidenceTokens))
            }
            if hit {
                delta += place.isHard ? 0.14 : 0.08
            } else if place.isHard {
                delta -= 0.22
            }
        }

        return delta
    }

    func canonicalPlaceEvidenceNeedles(
        _ place: ExchangeIntentFacets.StructuredPlace
    ) -> [String] {
        var phrases: [String] = []

        func push(_ raw: String) {
            let t = ExchangeIntentFacets.normalizeWhitespace(raw).lowercased()
            guard t.count >= 2 else { return }
            phrases.append(t)
        }

        push(place.normalizedText)
        place.aliases.forEach { push($0) }
        if let cid = place.canonicalID { push(cid.replacingOccurrences(of: "_", with: " ")) }

        let lower = place.normalizedText.lowercased()
        if lower == "gta" || place.aliases.contains(where: { $0.lowercased() == "gta" }) {
            push("gta")
            push("greater toronto")
            push("greater toronto area")
            push("toronto")
        }

        return Array(Set(phrases))
    }

    func canonicalStructuredAlignment(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        let evidenceTokens = durableFitEvidenceTokens(candidate: candidate)
        let timingRigid = canonicalHasHardTimingRequirement(si: si)
        let hayLower = durableFitEvidenceText(candidate: candidate).lowercased()

        var delta = 0.0

        let hardCount = max(
            si.hardConstraints.filter(\.isHardConstraint).count,
            1
        )
        for c in si.hardConstraints where c.isHardConstraint {
            if canonicalIntentConstraintMatches(c, evidenceTokens: evidenceTokens) {
                delta += 0.12 / Double(hardCount)
            } else {
                delta -= 0.20 / Double(hardCount)
            }
        }

        for c in si.softPreferences {
            if canonicalIntentConstraintMatches(c, evidenceTokens: evidenceTokens) {
                delta += 0.06
            }
        }

        let requiredPrefs = si.preferences.filter { $0.strength == .required }
        let reqDen = max(requiredPrefs.count, 1)
        for p in requiredPrefs {
            if canonicalStructuredPreferenceMatches(p, evidenceTokens: evidenceTokens) {
                delta += 0.08 / Double(reqDen)
            } else {
                delta -= 0.18 / Double(reqDen)
            }
        }

        for p in si.preferences where p.strength != .required {
            if canonicalStructuredPreferenceMatches(p, evidenceTokens: evidenceTokens) {
                delta += 0.05
            }
        }

        let hardCommercial = si.commercialConstraints.filter(\.isHard)
        let hcDen = max(hardCommercial.count, 1)
        for cc in hardCommercial {
            if canonicalCommercialMatches(cc, evidenceTokens: evidenceTokens) {
                delta += 0.10 / Double(hcDen)
            } else {
                delta -= 0.22 / Double(hcDen)
            }
        }

        for cc in si.commercialConstraints where !cc.isHard {
            if canonicalCommercialMatches(cc, evidenceTokens: evidenceTokens) {
                delta += 0.07
            }
        }

        for attr in si.attributes where canonicalAttributeIsBedroomAligned(attr) {
            if canonicalAttributeMatches(attr, evidenceTokens: evidenceTokens) {
                delta += 0.06
            }
        }

        for concept in si.semanticConcepts {
            if canonicalSemanticConceptMatches(concept, si: si, evidenceTokens: evidenceTokens) {
                delta += 0.04
            }
        }

        for tc in si.timeConstraints where !timingRigid {
            if canonicalTimeslotMatches(tc, evidenceTokens: evidenceTokens, haystackLowercased: hayLower) {
                delta += 0.05
            }
        }

        return delta
    }

    func canonicalIntentConstraintMatches(
        _ constraint: ExchangeIntent.Constraint,
        evidenceTokens: Set<String>
    ) -> Bool {
        let kt = constraint.key.tokens
        let vt = constraint.value.tokens
        guard !kt.isEmpty || !vt.isEmpty else { return false }
        var pool = Set(kt).union(Set(vt))
        pool.remove("")
        return !pool.intersection(evidenceTokens).isEmpty
    }

    func canonicalStructuredPreferenceMatches(
        _ pref: ExchangeIntentFacets.StructuredPreference,
        evidenceTokens: Set<String>
    ) -> Bool {
        var pool = Set(pref.key.tokens)
        if let v = pref.value { pool.formUnion(v.tokens) }
        pool.remove("")
        return !pool.intersection(evidenceTokens).isEmpty
    }

    func canonicalCommercialMatches(
        _ cc: ExchangeIntentFacets.StructuredCommercialConstraint,
        evidenceTokens: Set<String>
    ) -> Bool {
        var pool = Set(cc.key.tokens)
        pool.formUnion(cc.value.tokens)
        if cc.kind == .financing {
            pool.formUnion(canonicalFinancingExpansionTokens())
        }
        pool.remove("")
        return !pool.intersection(evidenceTokens).isEmpty
    }

    func canonicalFinancingExpansionTokens() -> Set<String> {
        ["financing", "finance", "mortgage", "vendor", "takeback", "take", "back", "vtb", "seller", "carry", "creative"]
    }

    func canonicalAttributeIsBedroomAligned(_ attr: ExchangeIntentFacets.StructuredAttribute) -> Bool {
        attr.key.lowercased().contains("bedroom") || attr.key.lowercased().contains("bed")
    }

    func canonicalAttributeMatches(
        _ attr: ExchangeIntentFacets.StructuredAttribute,
        evidenceTokens: Set<String>
    ) -> Bool {
        let keyTokens = Set(attr.key.tokens)
        let valueTokens = Set(attr.value.tokens)
        if let n = attr.numericValue {
            let asInt = Int(n.rounded())
            if !keyTokens.intersection(evidenceTokens).isEmpty { return true }
            if evidenceTokens.contains("\(asInt)") { return true }
            if evidenceTokens.contains("\(asInt)br") { return true }
            if evidenceTokens.contains("\(asInt)bd") { return true }
        }
        return !keyTokens.union(valueTokens).intersection(evidenceTokens).isEmpty
    }

    func canonicalSemanticConceptMatches(
        _ concept: String,
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        evidenceTokens: Set<String>
    ) -> Bool {
        var pool = Set(concept.tokens)
        pool.formUnion(canonicalConceptExpansionLegacy(concept, domain: si.domainCategory, objectType: si.objectType))
        pool.remove("")
        return !pool.intersection(evidenceTokens).isEmpty
    }

    /// Small synonym roots for fit-only recall (not broad retrieval).
    func canonicalConceptExpansionLegacy(
        _ concept: String,
        domain: ExchangeIntentFacets.DomainCategory,
        objectType: String?
    ) -> Set<String> {
        var extra: Set<String> = []
        let lower = concept.lowercased()
        let ot = (objectType ?? "").lowercased()

        if lower.contains("roof") || ot.contains("roof") {
            extra.formUnion(["roof", "roofing", "roofer", "shingle", "shingles", "gutter", "eavestrough"])
        }
        if lower.contains("contractor") || ot.contains("contractor") {
            extra.formUnion(["contractor", "construction", "technician", "technicians"])
        }
        if domain == .realEstate {
            extra.formUnion(["listing", "listings", "property", "home", "house", "residential"])
        }
        if domain == .homeService && (ot.contains("roof") || lower.contains("roof")) {
            extra.formUnion(["repair", "repairs", "replacement"])
        }

        return extra
    }

    func canonicalTimeslotMatches(
        _ tc: ExchangeIntentFacets.StructuredTimeConstraint,
        evidenceTokens: Set<String>,
        haystackLowercased: String
    ) -> Bool {
        let needle = ExchangeIntentFacets.normalizeWhitespace(tc.text).lowercased()
        if needle.count >= 2, haystackLowercased.contains(needle) {
            return true
        }

        let tcTokens = Set(tc.text.tokens).filter { !$0.isEmpty }
        if !tcTokens.isEmpty, !tcTokens.intersection(evidenceTokens).isEmpty {
            return true
        }

        let extras = canonicalTimePhraseExpansions(tc.text)
        return extras.contains(where: { t in !t.isEmpty && haystackLowercased.contains(t) })
    }

    func canonicalTimePhraseExpansions(_ phrase: String) -> [String] {
        let p = phrase.lowercased()
        var out: [String] = []
        if p.contains("tomorrow") {
            out.append(contentsOf: ["tomorrow", "next day", "following day"])
        }
        return out
    }

    func durableFitEvidenceTokens(candidate: ExchangeDiscoveryEngine.DiscoveryCandidate) -> Set<String> {
        var tokens = durableEntityTokens(candidate.counterparty)
        for offer in candidate.matchedOffers {
            tokens.formUnion(explicitOfferTokens(offer))
        }
        return tokens
    }

    func durableFitEvidenceText(candidate: ExchangeDiscoveryEngine.DiscoveryCandidate) -> String {
        let profile = candidate.publicProfile ?? candidate.counterparty.publicProfile
        return [
            candidate.counterparty.displayName,
            candidate.counterparty.bio,
            candidate.counterparty.location?.summaryLine,
            profile.map(profileEvidenceJoin),
            candidate.matchedOffers.map(offerEvidenceJoin).joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func profileEvidenceJoin(_ p: ExchangePublicNodeProfile) -> String {
        [
            p.headline,
            p.summary,
            p.offers.joined(separator: " "),
            p.openTo.joined(separator: " "),
            p.activityTags.joined(separator: " "),
            p.regionTags.joined(separator: " "),
            p.interests.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    func offerEvidenceJoin(_ o: ExchangeOffer) -> String {
        [
            o.title,
            o.summary,
            o.category,
            o.tags.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    func canonicalSemanticConceptMatchCount(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Int {
        let evidence = durableFitEvidenceTokens(candidate: candidate)
        var n = 0
        for c in si.semanticConcepts where canonicalSemanticConceptMatches(c, si: si, evidenceTokens: evidence) {
            n += 1
        }
        return n
    }

    func canonicalBroadLocalityHits(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Int {
        let evidenceText = durableFitEvidenceText(candidate: candidate).lowercased()
        let evidenceTokens = durableFitEvidenceTokens(candidate: candidate)
        var hits = 0
        for place in si.places {
            let needles = canonicalPlaceEvidenceNeedles(place)
            if needles.contains(where: { !$0.isEmpty && (evidenceText.contains($0) || hasTokenOverlap($0, in: evidenceTokens)) }) {
                hits += 1
            }
        }
        return hits
    }

    func canonicalHardPlaceUnsatisfied(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Bool {
        let evidenceText = durableFitEvidenceText(candidate: candidate).lowercased()
        let evidenceTokens = durableFitEvidenceTokens(candidate: candidate)

        return si.places.contains { place in
            guard place.isHard else { return false }
            let needles = canonicalPlaceEvidenceNeedles(place)
            let hit = needles.contains { needle in
                !needle.isEmpty && (evidenceText.contains(needle) || hasTokenOverlap(needle, in: evidenceTokens))
            }
            return !hit
        }
    }

    func canonicalMissingFactCautions(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> [ExchangeMatch.Caution] {
        let evidenceTokens = durableFitEvidenceTokens(candidate: candidate)
        var out: [ExchangeMatch.Caution] = []

        for attr in si.attributes where canonicalAttributeIsBedroomAligned(attr) {
            if !canonicalAttributeMatches(attr, evidenceTokens: evidenceTokens) {
                out.append(.init(
                    kind: .missingData,
                    summary: "Bedroom count not confirmed in visible listing or profile evidence."
                ))
            }
        }

        for cc in si.commercialConstraints where !cc.isHard {
            if canonicalCommercialMatches(cc, evidenceTokens: evidenceTokens) { continue }
            if cc.kind == .financing {
                out.append(.init(
                    kind: .missingData,
                    summary: "Seller financing preference not confirmed in visible evidence."
                ))
            } else {
                out.append(.init(
                    kind: .missingData,
                    summary: "Commercial preference (“\(cc.key)”) not confirmed in visible evidence."
                ))
            }
        }

        if !canonicalHasHardTimingRequirement(si: si), !si.timeConstraints.isEmpty {
            let hay = durableFitEvidenceText(candidate: candidate).lowercased()
            let allHit = si.timeConstraints.allSatisfy {
                canonicalTimeslotMatches($0, evidenceTokens: evidenceTokens, haystackLowercased: hay)
            }
            if !allHit {
                out.append(.init(
                    kind: .unclearAvailability,
                    summary: "Requested timing or availability not confirmed in visible evidence."
                ))
            }
        }

        for p in si.preferences where p.strength != .required {
            if canonicalStructuredPreferenceMatches(p, evidenceTokens: evidenceTokens) { continue }
            let value = (p.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 2 else { continue }
            out.append(.init(
                kind: .missingData,
                summary: "Unconfirmed preference: \(p.key)."
            ))
        }

        return out
    }

    func scoreTrustFit(
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        trustedProfile: ExchangeTrustedNodeProfile?
    ) -> Double {
        let counterparty = candidate.counterparty

        var score: Double
        switch counterparty.trust.level {
        case .high:
            score = 0.92
        case .moderate:
            score = 0.76
        case .low:
            score = 0.52
        case .unverified:
            score = counterparty.identity?.verification == .cryptographicallyVerified ? 0.66 : 0.30
        }

        if let trustedProfile {
            if let localTrust = trustedProfile.localTrust {
                switch localTrust.trustLevel {
                case .high: score += 0.10
                case .standard: score += 0.05
                case .low: score += 0.01
                }

                if localTrust.isMutual {
                    score += 0.04
                }
            }

            score += min(Double(trustedProfile.networkTrust.trustedByYourTrustedCount) * 0.02, 0.08)
            score += min(Double(trustedProfile.networkTrust.trustedByHighTrustCount) * 0.015, 0.05)
        }

        return clamp(score)
    }

    func scoreContactFit(
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        switch candidate.posture.bucket {
        case .contactable:
            return candidate.posture.explicitOpenness ? 0.95 : 0.80
        case .introRequired:
            return 0.58
        case .visibleButBlocked:
            return 0.18
        case .visibleButWeak:
            return 0.32
        case .unusable:
            return 0.05
        }
    }

    func scoreTimingFit(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        let counterparty = candidate.counterparty

        var score: Double
        switch thread.posture.urgency {
        case .immediate:
            score = counterparty.status == .active ? 0.88 : 0.25
        case .high:
            score = counterparty.status == .active ? 0.78 : 0.42
        case .normal:
            score = 0.62
        case .low:
            score = 0.56
        }

        if candidate.matchedOffers.contains(where: { $0.fulfillment.remoteFriendly }) {
            score += 0.05
        }

        return clamp(score)
    }

    // MARK: - Score composition

    func weightedScore(
        queryClass: ExchangeIntent.QueryIntentClass,
        retrievalPrior: Double,
        offerEvidence: Double,
        capabilityEvidence: Double,
        affinityEvidence: Double,
        surfaceFit: Double,
        constraintFit: Double,
        trustFit: Double,
        contactFit: Double,
        timingFit: Double
    ) -> Double {
        switch queryClass {
        case .providerSearch, .offerSearch:
            return clamp(
                (retrievalPrior * 0.16) +
                (offerEvidence * 0.26) +
                (capabilityEvidence * 0.08) +
                (affinityEvidence * 0.02) +
                (surfaceFit * 0.18) +
                (constraintFit * 0.16) +
                (trustFit * 0.06) +
                (contactFit * 0.06) +
                (timingFit * 0.02)
            )

        case .capabilitySearch, .collaborationSearch:
            return clamp(
                (retrievalPrior * 0.16) +
                (offerEvidence * 0.05) +
                (capabilityEvidence * 0.22) +
                (affinityEvidence * 0.05) +
                (surfaceFit * 0.18) +
                (constraintFit * 0.16) +
                (trustFit * 0.08) +
                (contactFit * 0.07) +
                (timingFit * 0.03)
            )

        case .socialAffinitySearch, .relationshipSearch:
            return clamp(
                (retrievalPrior * 0.14) +
                (offerEvidence * 0.03) +
                (capabilityEvidence * 0.08) +
                (affinityEvidence * 0.24) +
                (surfaceFit * 0.18) +
                (constraintFit * 0.12) +
                (trustFit * 0.09) +
                (contactFit * 0.09) +
                (timingFit * 0.03)
            )

        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return clamp(
                (retrievalPrior * 0.18) +
                (offerEvidence * 0.12) +
                (capabilityEvidence * 0.14) +
                (affinityEvidence * 0.06) +
                (surfaceFit * 0.16) +
                (constraintFit * 0.14) +
                (trustFit * 0.10) +
                (contactFit * 0.08) +
                (timingFit * 0.02)
            )
        }
    }

    func strengthForScore(_ score: Double) -> ExchangeMatch.Strength {
        if score >= 0.78 { return .strong }
        if score >= 0.56 { return .moderate }
        return .weak
    }

    // MARK: - Reasons / cautions / recommendation

    func buildReasons(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        canonicalSI: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        trustedProfile: ExchangeTrustedNodeProfile?,
        retrievalPrior: Double,
        offerEvidence: Double,
        capabilityEvidence: Double,
        affinityEvidence: Double,
        surfaceFit: Double,
        constraintFit: Double,
        trustFit: Double,
        contactFit: Double,
        timingFit: Double
    ) -> [ExchangeMatch.Reason] {
        let queryClass = thread.facets?.queryIntentClass ?? thread.intent.queryIntentClass
        var reasons: [ExchangeMatch.Reason] = []

        if retrievalPrior >= 0.72 {
            reasons.append(.init(
                kind: .other,
                summary: "This candidate surfaced strongly through retrieval."
            ))
        }

        switch queryClass {
        case .providerSearch, .offerSearch:
            if offerEvidence >= 0.72 {
                reasons.append(.init(
                    kind: .offer,
                    summary: "Matched offers explicitly overlap with the request."
                ))
            } else if capabilityEvidence >= 0.70 {
                reasons.append(.init(
                    kind: .profile,
                    summary: "The public profile still supports the provider request."
                ))
            }

        case .capabilitySearch, .collaborationSearch:
            if capabilityEvidence >= 0.72 {
                reasons.append(.init(
                    kind: .profile,
                    summary: "The public profile explicitly overlaps with the requested capability."
                ))
            } else if offerEvidence >= 0.68 {
                reasons.append(.init(
                    kind: .offer,
                    summary: "Visible offers still support the broader capability request."
                ))
            }

        case .socialAffinitySearch, .relationshipSearch:
            if affinityEvidence >= 0.70 {
                reasons.append(.init(
                    kind: .profile,
                    summary: "The visible affinity and interest surface overlaps with the request."
                ))
            } else if capabilityEvidence >= 0.62 {
                reasons.append(.init(
                    kind: .profile,
                    summary: "The public profile still carries useful social or activity signal."
                ))
            }

        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            if offerEvidence >= 0.70 {
                reasons.append(.init(
                    kind: .offer,
                    summary: "Visible public evidence overlaps with the request."
                ))
            } else if capabilityEvidence >= 0.68 || affinityEvidence >= 0.68 {
                reasons.append(.init(
                    kind: .profile,
                    summary: "The public profile overlaps with the request."
                ))
            }
        }

        if surfaceFit >= 0.76 {
            reasons.append(.init(
                kind: .specialization,
                summary: "The strongest public surface matches the current query type well."
            ))
        }

        if constraintFit >= 0.76 {
            reasons.append(.init(
                kind: .specialization,
                summary: "The visible surface appears to satisfy the main request constraints."
            ))
        }

        if trustFit >= 0.80 {
            reasons.append(.init(
                kind: .trust,
                summary: "Trust signal is comparatively strong."
            ))
        }

        if contactFit >= 0.85 {
            reasons.append(.init(
                kind: .other,
                summary: "The current public posture appears directly advanceable."
            ))
        }

        if timingFit >= 0.78 && thread.posture.urgency != .low {
            reasons.append(.init(
                kind: .timing,
                summary: "The candidate appears usable within the current timing posture."
            ))
        }

        if let trustedProfile, trustedProfile.localTrust != nil {
            reasons.append(.init(
                kind: .trust,
                summary: "This node is already trusted locally."
            ))
        }

        if let si = canonicalSI {
            if canonicalSemanticConceptMatchCount(si: si, candidate: candidate) > 0 {
                reasons.append(.init(
                    kind: .specialization,
                    summary: "Visible evidence aligns with canonical structured search themes."
                ))
            }

            if canonicalBroadLocalityHits(si: si, candidate: candidate) > 0 {
                reasons.append(.init(
                    kind: .location,
                    summary: "Location or region signal matches canonical place targets."
                ))
            }

            let evTokens = durableFitEvidenceTokens(candidate: candidate)

            switch si.domainCategory {
            case .realEstate:
                let cues: Set<String> = ["listing", "listings", "property", "home", "house", "residential", "sale", "condo"]
                if !evTokens.intersection(cues).isEmpty {
                    reasons.append(.init(
                        kind: .offer,
                        summary: "Listing-oriented evidence overlaps the canonical real-estate intent."
                    ))
                }

            case .homeService:
                let requestCue = canonicalRequestTokens(si)
                if !requestCue.intersection(evTokens).isEmpty {
                    reasons.append(.init(
                        kind: .capability,
                        summary: "Service-oriented evidence aligns with the structured home-service request."
                    ))
                }

            case .professionalService, .product, .general:
                break
            }
        }

        if reasons.isEmpty {
            reasons.append(.init(
                kind: .other,
                summary: "Some relevance exists, but the visible evidence is still limited."
            ))
        }

        return reasons
    }

    func buildCautions(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        canonicalSI: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        trustedProfile: ExchangeTrustedNodeProfile?,
        retrievalPrior: Double,
        offerEvidence: Double,
        capabilityEvidence: Double,
        affinityEvidence: Double,
        surfaceFit: Double,
        constraintFit: Double,
        trustFit: Double,
        contactFit: Double,
        timingFit: Double,
        finalScore: Double,
        forcedConcreteObjectMismatch: Bool = false
    ) -> [ExchangeMatch.Caution] {
        let counterparty = candidate.counterparty
        let queryClass = thread.facets?.queryIntentClass ?? thread.intent.queryIntentClass
        var cautions: [ExchangeMatch.Caution] = []

        if forcedConcreteObjectMismatch {
            cautions.append(.init(
                kind: .offerMismatch,
                summary: "The selected offer does not match the requested product or object."
            ))
        }

        if retrievalPrior < 0.40 {
            cautions.append(.init(
                kind: .lowSignal,
                summary: "Retrieval signal for this candidate is still weak."
            ))
        }

        switch queryClass {
        case .providerSearch, .offerSearch:
            if offerEvidence < 0.45 && capabilityEvidence < 0.45 {
                cautions.append(.init(
                    kind: candidate.matchedOffers.isEmpty ? .profileWeakness : .offerMismatch,
                    summary: "Explicit provider-facing public evidence is weak."
                ))
            }

        case .capabilitySearch, .collaborationSearch:
            if capabilityEvidence < 0.45 && offerEvidence < 0.45 {
                cautions.append(.init(
                    kind: .profileWeakness,
                    summary: "Explicit capability-oriented evidence is weak."
                ))
            }

        case .socialAffinitySearch, .relationshipSearch:
            if affinityEvidence < 0.45 {
                cautions.append(.init(
                    kind: .weakFit,
                    summary: "Affinity and interest evidence is still weak."
                ))
            }

        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            if offerEvidence < 0.40 && capabilityEvidence < 0.40 && affinityEvidence < 0.40 {
                cautions.append(.init(
                    kind: .lowSignal,
                    summary: "Explicit public evidence is weak."
                ))
            }
        }

        if surfaceFit < 0.42 {
            cautions.append(.init(
                kind: .weakFit,
                summary: "The strongest visible surface does not match this query type very well."
            ))
        }

        if trustFit < 0.50 {
            cautions.append(.init(
                kind: .limitedTrust,
                summary: "Trust and verification signal is limited."
            ))
        }

        if canonicalSI == nil, constraintFit < 0.55 {
            cautions.append(.init(
                kind: .missingData,
                summary: "The visible surface does not clearly satisfy the key constraints."
            ))
        }

        if contactFit < 0.40 {
            cautions.append(.init(
                kind: .limitedTrust,
                summary: candidate.posture.preview
            ))
        }

        if timingFit < 0.45 && thread.posture.urgency != .low {
            cautions.append(.init(
                kind: .timing,
                summary: "Timing signal is weak for the current urgency."
            ))
        }

        if finalScore < 0.50 {
            cautions.append(.init(
                kind: .lowSignal,
                summary: "Overall fit is still too weak to advance confidently."
            ))
        }

        if let facets = thread.facets {
            if isTargetKindMismatch(facets: facets, counterparty: counterparty) {
                cautions.append(.init(
                    kind: .weakFit,
                    summary: "The candidate type does not match the request very well."
                ))
            }

            if isFulfillmentMismatch(facets: facets, counterparty: counterparty, offers: candidate.matchedOffers) {
                cautions.append(.init(
                    kind: .missingData,
                    summary: "Fulfillment style appears mismatched with the request."
                ))
            }

            if canonicalSI != nil {
                if let si = canonicalSI, canonicalHardPlaceUnsatisfied(si: si, candidate: candidate) {
                    cautions.append(.init(
                        kind: .location,
                        summary: "Hard canonical place targets are not clearly reflected in visible evidence."
                    ))
                }
            } else {
                if isPlaceMismatch(facets: facets, counterparty: counterparty, offers: candidate.matchedOffers) {
                    cautions.append(.init(
                        kind: .location,
                        summary: "Location signal does not clearly match the requested place."
                    ))
                }

                if isTimeMismatch(facets: facets, counterparty: counterparty) {
                    cautions.append(.init(
                        kind: .timing,
                        summary: "Timing signal does not clearly match the requested time window."
                    ))
                }
            }
        }

        if let si = canonicalSI {
            cautions.append(contentsOf: canonicalMissingFactCautions(si: si, candidate: candidate))
        }

        if let trustedProfile,
           trustedProfile.networkTrust.trustedByCount == 0,
           trustedProfile.localTrust == nil,
           counterparty.trust.level == .unverified,
           counterparty.identity?.verification != .cryptographicallyVerified {
            cautions.append(.init(
                kind: .limitedTrust,
                summary: "There is no visible trust graph support for this node yet."
            ))
        }

        return cautions
    }

    func buildRecommendation(
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        trustedProfile: ExchangeTrustedNodeProfile?,
        strength: ExchangeMatch.Strength,
        cautions: [ExchangeMatch.Caution]
    ) -> String {
        switch strength {
        case .strong:
            if candidate.posture.bucket != .contactable {
                return "Strong relevance exists, but do not advance until the contact path is resolved."
            }

            if let trustedProfile, trustedProfile.localTrust != nil {
                return "This trusted node is worth advancing to shortlist or approval."
            }

            return "This candidate is worth advancing to shortlist or approval."

        case .moderate:
            if candidate.posture.bucket == .introRequired {
                return "Potentially good, but introduction is required before advancing."
            }

            if candidate.posture.bucket == .visibleButBlocked {
                return "Potentially relevant, but public posture blocks contact right now."
            }

            if cautions.isEmpty {
                return "Potentially usable, but still review manually before advancing."
            }

            return "Review manually before advancing."

        case .weak:
            return "Do not advance without refining the request or widening discovery."
        }
    }

    // MARK: - Ordering

    func matchOrdering(_ lhs: ExchangeMatch, _ rhs: ExchangeMatch) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.strength != rhs.strength { return strengthRank(lhs.strength) > strengthRank(rhs.strength) }
        return lhs.counterpartyID < rhs.counterpartyID
    }

    func strengthRank(_ value: ExchangeMatch.Strength) -> Int {
        switch value {
        case .strong: return 3
        case .moderate: return 2
        case .weak: return 1
        }
    }

    // MARK: - Tokens

    func requestIntentTokens(_ thread: ExchangeThread) -> Set<String> {
        guard let si = thread.facets?.searchIntent else {
            return legacyRequestIntentTokens(thread)
        }
        return canonicalRequestTokens(si)
    }

    /// Phase 5: lexical request tokens compiled from canonical semantics only (no fused raw objective).
    func canonicalRequestTokens(_ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent) -> Set<String> {
        var values: [String] = []

        values.append(contentsOf: si.broadRecallTokens)
        values.append(contentsOf: si.semanticConcepts)

        values.append(si.domainCategory.rawValue)
        if let tx = si.transactionIntent { values.append(tx.rawValue) }

        switch si.domainCategory {
        case .realEstate:
            values.append(contentsOf: ["listing", "listings", "property", "home", "house", "residential", "real", "estate"])
        case .homeService:
            values.append(contentsOf: ["repair", "service", "contractor", "install", "installation"])
        case .professionalService:
            values.append(contentsOf: ["professional", "consulting", "advisory"])
        case .product:
            values.append(contentsOf: ["product", "goods", "item"])
        case .general:
            break
        }

        if let objectType = si.objectType { values.append(objectType) }

        for place in si.places {
            values.append(place.normalizedText)
            values.append(contentsOf: place.aliases)
            if let cid = place.canonicalID { values.append(cid) }
        }

        for attr in si.attributes {
            values.append(attr.key)
            values.append(attr.value)
        }

        for pref in si.preferences {
            values.append(pref.key)
            if let v = pref.value { values.append(v) }
        }

        for tc in si.timeConstraints {
            values.append(tc.text)
        }

        for cc in si.commercialConstraints {
            values.append(cc.key)
            values.append(cc.value)
            if cc.kind == .financing {
                values.append(contentsOf: Array(canonicalFinancingExpansionTokens()))
            }
        }

        for c in si.hardConstraints {
            values.append(c.key)
            values.append(c.value)
        }

        for c in si.softPreferences {
            values.append(c.key)
            values.append(c.value)
        }

        return Set(values.flatMap(\.tokens).filter { !$0.isEmpty })
    }

    func legacyRequestIntentTokens(_ thread: ExchangeThread) -> Set<String> {
        var values: [String] = []

        if let interpretation = thread.interpretation {
            values.append(contentsOf: interpretation.semanticTags)
            values.append(contentsOf: interpretation.targetTags)
            values.append(contentsOf: interpretation.discoveryKeywords)
            if let summary = interpretation.userSummary { values.append(summary) }
            if let question = interpretation.userQuestion { values.append(question) }
        }

        if let facets = thread.facets, facets.hasMeaningfulStructure {
            values.append(contentsOf: facets.allKeywords)
            values.append(contentsOf: facets.providerTerms)
            values.append(contentsOf: facets.capabilityTerms)
            values.append(contentsOf: facets.affinityTerms)

            if let targetRole = facets.targetRole { values.append(targetRole) }
            if let activity = facets.activity { values.append(activity) }
            if let serviceCategory = facets.serviceCategory { values.append(serviceCategory) }
            if let productCategory = facets.productCategory { values.append(productCategory) }
            if let placeName = facets.placeName { values.append(placeName) }
            if let locationText = facets.locationText { values.append(locationText) }
            if let timeText = facets.timeText { values.append(timeText) }
        }

        values.append(thread.intent.title)
        if let target = thread.intent.targetDescription { values.append(target) }
        values.append(thread.intent.objective)

        return Set(values.flatMap(\.tokens).filter { !$0.isEmpty })
    }

    func explicitOfferTokens(_ offer: ExchangeOffer) -> Set<String> {
        Set(
            [
                offer.title,
                offer.summary,
                offer.category,
                offer.tags.joined(separator: " "),
                offer.regionTags.joined(separator: " "),
                offer.semantic.searchableTerms.joined(separator: " "),
                offer.semantic.domains.joined(separator: " "),
                offer.semantic.serviceKinds.joined(separator: " ")
            ]
            .compactMap { $0 }
            .flatMap(\.tokens)
        )
    }

    func explicitCapabilityTokens(_ profile: ExchangePublicNodeProfile) -> Set<String> {
        Set(
            [
                profile.displayName,
                profile.headline,
                profile.summary,
                profile.offers.joined(separator: " "),
                profile.openTo.joined(separator: " "),
                profile.activityTags.joined(separator: " "),
                profile.regionTags.joined(separator: " "),
                profile.semantic.searchableTerms.joined(separator: " "),
                profile.semantic.notes,
                profile.semantic.domains.joined(separator: " "),
                profile.semantic.intentKinds.joined(separator: " ")
            ]
            .compactMap { $0 }
            .flatMap(\.tokens)
        )
    }

    func explicitAffinityTokens(_ profile: ExchangePublicNodeProfile) -> Set<String> {
        Set(
            [
                profile.interests.joined(separator: " "),
                profile.activityTags.joined(separator: " "),
                profile.openTo.joined(separator: " "),
                profile.summary,
                profile.headline
            ]
            .compactMap { $0 }
            .flatMap(\.tokens)
        )
    }

    func offerAndProfileLocationTokens(
        _ candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Set<String> {
        var values: [String] = []

        values.append(candidate.counterparty.location?.summaryLine ?? "")

        if let profile = candidate.publicProfile {
            values.append(profile.regionTags.joined(separator: " "))
            values.append(profile.summary ?? "")
            values.append(profile.headline ?? "")
        }

        for offer in candidate.matchedOffers {
            values.append(offer.regionTags.joined(separator: " "))
            values.append(offer.summary ?? "")
            values.append(offer.category ?? "")
        }

        return Set(values.flatMap(\.tokens))
    }

    func durableEntityTokens(_ counterparty: ExchangeCounterparty) -> Set<String> {
        var values: [String] = [
            counterparty.displayName,
            counterparty.handle ?? "",
            counterparty.bio ?? "",
            counterparty.location?.summaryLine ?? "",
            counterparty.tags.joined(separator: " "),
            counterparty.capabilities.map(\.label).joined(separator: " "),
            counterparty.capabilities.compactMap(\.category).joined(separator: " "),
            counterparty.capabilities.compactMap(\.notes).joined(separator: " "),
            counterparty.semantic.searchableTerms.joined(separator: " "),
            counterparty.semantic.notes ?? ""
        ]

        if let profile = counterparty.publicProfile {
            values.append(profile.displayName ?? "")
            values.append(profile.headline ?? "")
            values.append(profile.summary ?? "")
            values.append(profile.offers.joined(separator: " "))
            values.append(profile.openTo.joined(separator: " "))
            values.append(profile.activityTags.joined(separator: " "))
            values.append(profile.regionTags.joined(separator: " "))
            values.append(profile.interests.joined(separator: " "))
        }

        return Set(values.flatMap(\.tokens))
    }

    func counterpartyLocationText(_ counterparty: ExchangeCounterparty) -> String {
        [
            counterparty.location?.summaryLine.lowercased(),
            counterparty.bio?.lowercased(),
            counterparty.tags.joined(separator: " ").lowercased(),
            counterparty.publicProfile?.regionTags.joined(separator: " ").lowercased(),
            counterparty.publicProfile?.summary?.lowercased(),
            counterparty.publicProfile?.headline?.lowercased()
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    func overlapScore(
        overlap: Int,
        high: Int,
        medium: Int,
        low: Int,
        none: Double
    ) -> Double {
        if overlap >= high { return 0.95 }
        if overlap >= medium { return 0.80 }
        if overlap >= low { return 0.58 }
        return none
    }

    // MARK: - Alignment bonuses

    func localityAlignmentBonus(
        facets: ExchangeIntentFacets,
        counterparty: ExchangeCounterparty,
        offers: [ExchangeOffer]
    ) -> Double {
        let requirement = facets.locationRequirement
            ?? ExchangeLocationRequirementMapping.buildFromFacets(facets)
        let serviceAreas = offers.flatMap(\.effectiveServiceAreas)
        let remoteFriendly = offers.contains(where: \.fulfillment.remoteFriendly)

        if let requirement, requirement.kind != .none {
            let match = ExchangeServiceAreaMatcher.match(
                requirement: requirement,
                serviceAreas: serviceAreas,
                fulfillmentRemoteFriendly: remoteFriendly
            )
            var bonus = match.scoreDelta
            if match.isHardMismatch {
                bonus -= 0.12
            }
            if match.tier == .requiresClarification {
                bonus += 0.02
            }
            return bonus
        }

        var bonus = 0.0
        if (facets.prefersLocalFirst && counterparty.location != nil) || !offers.isEmpty {
            bonus += 0.05
        }
        return bonus
    }

    func fulfillmentAlignmentBonus(
        facets: ExchangeIntentFacets,
        counterparty: ExchangeCounterparty,
        offers: [ExchangeOffer]
    ) -> Double {
        switch facets.fulfillmentMode {
        case .localOnly:
            if offers.contains(where: {
                $0.semantic.fulfillmentModes.contains(.localOnly) ||
                $0.semantic.fulfillmentModes.contains(.localPreferred) ||
                $0.semantic.fulfillmentModes.contains(.inPerson)
            }) {
                return 0.14
            }
            return counterparty.location != nil ? 0.05 : -0.12

        case .localPreferred:
            if offers.contains(where: {
                $0.semantic.fulfillmentModes.contains(.localOnly) ||
                $0.semantic.fulfillmentModes.contains(.localPreferred) ||
                $0.semantic.fulfillmentModes.contains(.inPerson)
            }) {
                return 0.10
            }
            return counterparty.location != nil ? 0.04 : -0.06

        case .remoteFriendly:
            if offers.contains(where: {
                $0.fulfillment.remoteFriendly ||
                $0.semantic.fulfillmentModes.contains(.remoteFriendly) ||
                $0.semantic.fulfillmentModes.contains(.digitalDelivery)
            }) {
                return 0.10
            }
            return 0.0

        case .shippable:
            if offers.contains(where: { $0.semantic.fulfillmentModes.contains(.shippable) }) {
                return 0.10
            }
            return 0.0

        case .digitalDelivery:
            if offers.contains(where: { $0.semantic.fulfillmentModes.contains(.digitalDelivery) }) {
                return 0.10
            }
            return 0.0

        case .unknown:
            return 0.0
        }
    }

    func timeAlignmentBonus(
        facets: ExchangeIntentFacets,
        counterparty: ExchangeCounterparty,
        offers: [ExchangeOffer]
    ) -> Double {
        guard let timePreference = facets.timePreference else { return 0.0 }

        switch timePreference {
        case .immediate:
            return counterparty.status == .active ? 0.12 : -0.10
        case .today, .tonight, .thisWeek, .weekend, .nextWeek:
            return counterparty.status == .active ? 0.06 : -0.04
        case .flexible:
            return 0.03
        }
    }

    func requirementAlignmentBonus(
        facets: ExchangeIntentFacets,
        counterparty: ExchangeCounterparty,
        offers: [ExchangeOffer]
    ) -> Double {
        let hard = requirementScore(
            facets.hardRequirements,
            counterparty: counterparty,
            offers: offers,
            positiveWeight: 0.14,
            negativeWeight: 0.16
        )

        let soft = requirementScore(
            facets.softPreferences,
            counterparty: counterparty,
            offers: offers,
            positiveWeight: 0.08,
            negativeWeight: 0.00
        )

        return hard + soft
    }

    func surfaceSpecificConstraintBonus(
        facets: ExchangeIntentFacets,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        switch facets.queryIntentClass {
        case .providerSearch, .offerSearch:
            return candidate.dominantSurface == .offer ? 0.08 : -0.04
        case .capabilitySearch, .collaborationSearch:
            return candidate.dominantSurface == .capability ? 0.08 : 0.0
        case .socialAffinitySearch, .relationshipSearch:
            return candidate.dominantSurface == .affinity ? 0.08 : -0.04
        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return 0.0
        }
    }

    func requirementScore(
        _ requirements: [ExchangeIntentFacets.Requirement],
        counterparty: ExchangeCounterparty,
        offers: [ExchangeOffer],
        positiveWeight: Double,
        negativeWeight: Double
    ) -> Double {
        guard !requirements.isEmpty else { return 0.0 }

        var tokens = durableEntityTokens(counterparty)
        for offer in offers {
            tokens.formUnion(explicitOfferTokens(offer))
        }

        var score = 0.0

        for requirement in requirements {
            let requirementTokens = Set(requirement.value.tokens)
            if requirementTokens.isEmpty { continue }

            if !requirementTokens.intersection(tokens).isEmpty {
                score += positiveWeight / Double(requirements.count)
            } else if requirement.isHard {
                score -= negativeWeight / Double(requirements.count)
            }
        }

        return score
    }

    // MARK: - Mismatch helpers

    func isTargetKindMismatch(
        facets: ExchangeIntentFacets,
        counterparty: ExchangeCounterparty
    ) -> Bool {
        switch facets.targetKind {
        case .person:
            return counterparty.kind != .person
        case .provider:
            return !(counterparty.kind == .provider || counterparty.kind == .business || counterparty.kind == .organization)
        case .business:
            return counterparty.kind != .business
        case .organization:
            return counterparty.kind != .organization
        case .group:
            return counterparty.kind != .group
        case .secretaryNode:
            return counterparty.kind != .secretaryNode
        case .unknown:
            return false
        }
    }

    func isFulfillmentMismatch(
        facets: ExchangeIntentFacets,
        counterparty: ExchangeCounterparty,
        offers: [ExchangeOffer]
    ) -> Bool {
        switch facets.fulfillmentMode {
        case .localOnly:
            if offers.isEmpty { return counterparty.location == nil }
            return !offers.contains {
                $0.semantic.fulfillmentModes.contains(.localOnly) ||
                $0.semantic.fulfillmentModes.contains(.localPreferred) ||
                $0.semantic.fulfillmentModes.contains(.inPerson)
            }

        case .localPreferred:
            if offers.isEmpty { return counterparty.location == nil }
            return !offers.contains {
                $0.semantic.fulfillmentModes.contains(.localOnly) ||
                $0.semantic.fulfillmentModes.contains(.localPreferred) ||
                $0.semantic.fulfillmentModes.contains(.inPerson)
            } && counterparty.location == nil

        case .remoteFriendly:
            if offers.isEmpty { return false }
            return !offers.contains {
                $0.fulfillment.remoteFriendly ||
                $0.semantic.fulfillmentModes.contains(.remoteFriendly) ||
                $0.semantic.fulfillmentModes.contains(.digitalDelivery)
            }

        case .shippable:
            if offers.isEmpty { return false }
            return !offers.contains { $0.semantic.fulfillmentModes.contains(.shippable) }

        case .digitalDelivery:
            if offers.isEmpty { return false }
            return !offers.contains { $0.semantic.fulfillmentModes.contains(.digitalDelivery) }

        case .unknown:
            return false
        }
    }

    func isPlaceMismatch(
        facets: ExchangeIntentFacets,
        counterparty: ExchangeCounterparty,
        offers: [ExchangeOffer]
    ) -> Bool {
        let offerRegionText = offers
            .map { ($0.regionTags + [$0.summary ?? "", $0.category ?? ""]).joined(separator: " ") }
            .joined(separator: " ")

        let locationText = [
            counterpartyLocationText(counterparty),
            offerRegionText.lowercased()
        ]
        .joined(separator: " ")

        let candidateTokens = Set(locationText.tokens)

        if let placeName = facets.placeName?.lowercased(),
           !placeName.isEmpty {
            if locationText.contains(placeName) || hasTokenOverlap(placeName, in: candidateTokens) {
                return false
            }
            return true
        }

        if let requestedLocation = facets.locationText?.lowercased(),
           !requestedLocation.isEmpty {
            let requestedTokens = Set(requestedLocation.tokens)
            if requestedTokens.isEmpty { return false }
            return requestedTokens.intersection(candidateTokens).isEmpty
        }

        return false
    }

    func isTimeMismatch(
        facets: ExchangeIntentFacets,
        counterparty: ExchangeCounterparty
    ) -> Bool {
        guard facets.timePreference != nil else { return false }

        if counterparty.status != .active &&
            (facets.timePreference == .immediate || facets.timePreference == .today || facets.timePreference == .tonight) {
            return true
        }

        return false
    }

    // MARK: - Utilities

    func hasTokenOverlap(_ phrase: String, in candidateTokens: Set<String>) -> Bool {
        let tokens = phrase.tokens
        guard !tokens.isEmpty else { return false }
        return !Set(tokens).intersection(candidateTokens).isEmpty
    }

    func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private extension String {
    var tokens: [String] {
        components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !$0.isFitStopWord }
    }

    var isFitStopWord: Bool {
        [
            "the", "a", "an", "for", "to", "with", "and", "or", "of", "in", "on",
            "my", "me", "someone", "somebody", "person", "people", "need", "want",
            "help", "find", "looking", "look", "request", "arrange", "please"
        ].contains(self)
    }
}
