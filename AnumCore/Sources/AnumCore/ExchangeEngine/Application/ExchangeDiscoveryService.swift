import Foundation

#if DEBUG
@inline(__always)
private func exDiscoveryLog(_ message: @autoclosure () -> String) {
    print("[ExchangeDiscoveryService] \(message())")
}
#else
@inline(__always)
private func exDiscoveryLog(_ message: @autoclosure () -> String) { }
#endif

/// Higher-level discovery service that combines:
/// - request-side discovery shortlist from exposed public surfaces
/// - deeper fit scoring on shortlisted candidates only
/// - app-facing classification only
///
/// Clean boundary:
/// - ExchangeDiscoveryEngine = retrieval + cheap shortlist + domain-correct gating
/// - ExchangeFitEngine = deep scoring on shortlist
/// - ExchangeDiscoveryService = orchestration + final result shaping only
///
/// Important:
/// - This layer does NOT do retrieval
/// - This layer does NOT replace fit scoring
/// - This layer should preserve shortlist order and attach fit judgment
/// - Summary language should reflect the query class and dominant surface
public struct ExchangeDiscoveryService: Sendable {
    private let discoveryEngine: ExchangeDiscoveryEngine
    private let fitEngine: ExchangeFitEngine
    private let discoveryHeroProgressReporter: (any DiscoveryHeroProgressReporting)?

    public init(
        discoveryEngine: ExchangeDiscoveryEngine,
        fitEngine: ExchangeFitEngine,
        discoveryHeroProgressReporter: (any DiscoveryHeroProgressReporting)? = nil
    ) {
        self.discoveryEngine = discoveryEngine
        self.fitEngine = fitEngine
        self.discoveryHeroProgressReporter = discoveryHeroProgressReporter
    }

    public func discoverAndRank(
        thread: ExchangeThread,
        limit: Int = 12,
        progressContext: DiscoveryHeroProgressContext? = nil
    ) async throws -> ResultSet {
        exDiscoveryLog(
            "discoverAndRank start " +
            "threadID=\(thread.id.uuidString) " +
            "state=\(thread.state.phaseTitle) " +
            "mode=\(thread.mode.rawValue) " +
            "intent=\(thread.intent.kind.rawValue) " +
            "limit=\(limit)"
        )

        let shortlist = try await discoveryEngine.discover(
            thread: thread,
            limit: limit,
            progressContext: progressContext
        )

        switch shortlist {
        case .none(let none):
            exDiscoveryLog(
                "discoverAndRank result=none " +
                "summary=\(none.summary) " +
                "recommendation=\(none.recommendation) " +
                "sourceSummary=\(none.sourceSummary) " +
                "queryIntentClass=\(none.searchPlan.queryIntentClass.rawValue) " +
                "surfacePreference=\(none.searchPlan.surfacePreference.rawValue)"
            )

            return .none(
                .init(
                    summary: none.summary,
                    recommendation: none.recommendation,
                    sourceSummary: none.sourceSummary
                )
            )

        case .weak(let weak):
            return classifyShortlist(
                thread: thread,
                candidates: weak.candidates,
                summaryFallback: weak.summary,
                recommendationFallback: weak.recommendation,
                sourceSummary: weak.sourceSummary,
                modeHint: .weak,
                searchPlan: weak.searchPlan
            )

        case .found(let found):
            return classifyShortlist(
                thread: thread,
                candidates: found.candidates,
                summaryFallback: found.summary,
                recommendationFallback: nil,
                sourceSummary: found.sourceSummary,
                modeHint: .found,
                searchPlan: found.searchPlan
            )
        }
    }
}

public extension ExchangeDiscoveryService {
    /// Final app-facing item:
    /// - preserves discovery shortlist order
    /// - preserves fit evaluation
    /// - no service-owned ranking score
    struct RankedCandidate: Sendable, Hashable {
        public var candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
        public var match: ExchangeMatch
        public var isAdvanceable: Bool
        public var rankSummary: String

        public init(
            candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
            match: ExchangeMatch,
            isAdvanceable: Bool,
            rankSummary: String
        ) {
            self.candidate = candidate
            self.match = match
            self.isAdvanceable = isAdvanceable
            self.rankSummary = rankSummary
        }
    }

    enum ResultSet: Sendable, Hashable {
        case none(None)
        case weak(Weak)
        case found(Found)
    }

    struct None: Sendable, Hashable {
        public var summary: String
        public var recommendation: String
        public var sourceSummary: String

        public init(
            summary: String,
            recommendation: String,
            sourceSummary: String
        ) {
            self.summary = summary
            self.recommendation = recommendation
            self.sourceSummary = sourceSummary
        }
    }

    struct Weak: Sendable, Hashable {
        public var counterparties: [ExchangeCounterparty]
        public var candidates: [RankedCandidate]
        public var matches: [ExchangeMatch]
        public var bestAvailableMatch: ExchangeMatch?
        public var bestOverallMatch: ExchangeMatch?
        public var summary: String
        public var recommendation: String
        public var sourceSummary: String

        public init(
            counterparties: [ExchangeCounterparty],
            candidates: [RankedCandidate],
            matches: [ExchangeMatch],
            bestAvailableMatch: ExchangeMatch?,
            bestOverallMatch: ExchangeMatch?,
            summary: String,
            recommendation: String,
            sourceSummary: String
        ) {
            self.counterparties = counterparties
            self.candidates = candidates
            self.matches = matches
            self.bestAvailableMatch = bestAvailableMatch
            self.bestOverallMatch = bestOverallMatch
            self.summary = summary
            self.recommendation = recommendation
            self.sourceSummary = sourceSummary
        }
    }

    struct Found: Sendable, Hashable {
        public var counterparties: [ExchangeCounterparty]
        public var candidates: [RankedCandidate]
        public var matches: [ExchangeMatch]
        public var bestMatch: ExchangeMatch?
        public var summary: String
        public var sourceSummary: String
        public var classifyGrade: ExchangeThreadDiscoveryGradeMetadata.ClassifyGrade

        public init(
            counterparties: [ExchangeCounterparty],
            candidates: [RankedCandidate],
            matches: [ExchangeMatch],
            bestMatch: ExchangeMatch?,
            summary: String,
            sourceSummary: String,
            classifyGrade: ExchangeThreadDiscoveryGradeMetadata.ClassifyGrade
        ) {
            self.counterparties = counterparties
            self.candidates = candidates
            self.matches = matches
            self.bestMatch = bestMatch
            self.summary = summary
            self.sourceSummary = sourceSummary
            self.classifyGrade = classifyGrade
        }
    }
}

private extension ExchangeMatch.Strength {
    var sortPriority: Int {
        switch self {
        case .weak: return 0
        case .moderate: return 1
        case .strong: return 2
        }
    }
}

private extension ExchangeDiscoveryService {
    enum ClassificationHint: String {
        case weak
        case found
    }

    func resolvedQueryIntentClass(
        thread: ExchangeThread,
        searchPlan: ExchangeDiscoveryEngine.SearchPlan
    ) -> ExchangeIntent.QueryIntentClass {
        if let facets = thread.facets {
            return facets.queryIntentClass
        }
        return searchPlan.queryIntentClass
    }

    func resolvedSurfacePreference(
        thread: ExchangeThread,
        searchPlan: ExchangeDiscoveryEngine.SearchPlan
    ) -> ExchangeIntent.SurfacePreference {
        if let facets = thread.facets {
            return facets.surfacePreference
        }
        return searchPlan.surfacePreference
    }

    func candidateKey(for candidate: ExchangeDiscoveryEngine.DiscoveryCandidate) -> String {
        let counterpartyID = candidate.counterparty.id
        let publicProfileID = candidate.publicProfileID ?? "nil"
        let primaryOfferID = candidate.matchedOffers.first?.id ?? "nil"

        if primaryOfferID != "nil" {
            return "offer::\(counterpartyID)::\(publicProfileID)::\(primaryOfferID)"
        }

        if publicProfileID != "nil" {
            return "profile::\(counterpartyID)::\(publicProfileID)"
        }

        return "counterparty::\(counterpartyID)"
    }

    func candidateKey(for match: ExchangeMatch) -> String {
        let counterpartyID = match.counterpartyID
        let publicProfileID = match.publicProfileID ?? "nil"
        let offerID = match.offerID ?? match.matchedOfferIDs.first ?? "nil"

        switch match.scope {
        case .offer:
            return "offer::\(counterpartyID)::\(publicProfileID)::\(offerID)"
        case .publicProfile:
            return "profile::\(counterpartyID)::\(publicProfileID)"
        case .counterparty:
            return "counterparty::\(counterpartyID)"
        }
    }

    func classifyShortlist(
        thread: ExchangeThread,
        candidates: [ExchangeDiscoveryEngine.DiscoveryCandidate],
        summaryFallback: String,
        recommendationFallback: String?,
        sourceSummary: String,
        modeHint: ClassificationHint,
        searchPlan: ExchangeDiscoveryEngine.SearchPlan
    ) -> ResultSet {
        let queryIntentClass = resolvedQueryIntentClass(
            thread: thread,
            searchPlan: searchPlan
        )
        let surfacePreference = resolvedSurfacePreference(
            thread: thread,
            searchPlan: searchPlan
        )

        exDiscoveryLog(
            "classifyShortlist start " +
            "threadID=\(thread.id.uuidString) " +
            "candidates=\(candidates.count) " +
            "modeHint=\(modeHint.rawValue) " +
            "queryIntentClass=\(queryIntentClass.rawValue) " +
            "surfacePreference=\(surfacePreference.rawValue)"
        )

        guard !candidates.isEmpty else {
            let summary = "I understood the request, but I could not find relevant public surfaces yet."
            let recommendation = "Refine the request, widen the scope, or wait for better public surfaces."

            exDiscoveryLog(
                "classifyShortlist empty " +
                "summary=\(summary) " +
                "recommendation=\(recommendation)"
            )

            return .none(
                .init(
                    summary: summary,
                    recommendation: recommendation,
                    sourceSummary: sourceSummary
                )
            )
        }

        let fitMatches = fitEngine.evaluate(
            thread: thread,
            candidates: candidates
        )

        var matchByCandidateKey: [String: ExchangeMatch] = [:]
        matchByCandidateKey.reserveCapacity(fitMatches.count)

        for match in fitMatches {
            let key = candidateKey(for: match)

            if let existing = matchByCandidateKey[key] {
                let keepNew: Bool
                if match.score != existing.score {
                    keepNew = match.score > existing.score
                } else {
                    let newStrength = match.strength.sortPriority
                    let oldStrength = existing.strength.sortPriority

                    if newStrength != oldStrength {
                        keepNew = newStrength > oldStrength
                    } else {
                        let newMatchedOffers = match.matchedOfferIDs.count
                        let oldMatchedOffers = existing.matchedOfferIDs.count

                        if newMatchedOffers != oldMatchedOffers {
                            keepNew = newMatchedOffers > oldMatchedOffers
                        } else {
                            keepNew = false
                        }
                    }
                }

                exDiscoveryLog(
                    "classifyShortlist duplicateMatchKey " +
                    "key=\(key) " +
                    "existingScope=\(existing.scope.rawValue) " +
                    "newScope=\(match.scope.rawValue) " +
                    "existingScore=\(String(format: "%.3f", existing.score)) " +
                    "newScore=\(String(format: "%.3f", match.score)) " +
                    "existingStrength=\(existing.strength.rawValue) " +
                    "newStrength=\(match.strength.rawValue) " +
                    "keeping=\(keepNew ? "new" : "existing")"
                )

                if keepNew {
                    matchByCandidateKey[key] = match
                }
            } else {
                matchByCandidateKey[key] = match
            }
        }

        var hydrated: [RankedCandidate] = []
        hydrated.reserveCapacity(candidates.count)

        var seenCandidateKeys = Set<String>()
        seenCandidateKeys.reserveCapacity(candidates.count)

        for candidate in candidates {
            let key = candidateKey(for: candidate)

            if seenCandidateKeys.contains(key) {
                exDiscoveryLog(
                    "classifyShortlist duplicateCandidateKey " +
                    "counterpartyID=\(candidate.counterparty.id) " +
                    "publicProfileID=\(candidate.publicProfileID ?? "nil") " +
                    "offerID=\(candidate.matchedOffers.first?.id ?? "nil") " +
                    "surface=\(candidate.dominantSurface.rawValue) " +
                    "candidateKey=\(key) " +
                    "action=skipDuplicateCandidate"
                )
                continue
            }
            seenCandidateKeys.insert(key)

            guard let match = matchByCandidateKey[key] else {
                exDiscoveryLog(
                    "classifyShortlist missingMatch " +
                    "counterpartyID=\(candidate.counterparty.id) " +
                    "publicProfileID=\(candidate.publicProfileID ?? "nil") " +
                    "offerID=\(candidate.matchedOffers.first?.id ?? "nil") " +
                    "surface=\(candidate.dominantSurface.rawValue) " +
                    "candidateKey=\(key)"
                )
                continue
            }

            let advanceable = isAdvanceable(
                candidate: candidate,
                match: match,
                thread: thread,
                searchPlan: searchPlan
            )
            let summary = candidateSummary(
                candidate: candidate,
                match: match,
                advanceable: advanceable,
                queryIntentClass: queryIntentClass
            )

            exDiscoveryLog(
                "classifyShortlist candidate " +
                "counterpartyID=\(candidate.counterparty.id) " +
                "scope=\(match.scope.rawValue) " +
                "surface=\(candidate.dominantSurface.rawValue) " +
                "publicProfileID=\(match.publicProfileID ?? "nil") " +
                "offerID=\(match.offerID ?? "nil") " +
                "matchedOfferIDs=\(match.matchedOfferIDs) " +
                "candidateKey=\(key) " +
                "discoveryScore=\(String(format: "%.3f", candidate.overallScore)) " +
                "fitScore=\(String(format: "%.3f", match.score)) " +
                "strength=\(match.strength.rawValue) " +
                "bucket=\(candidate.posture.bucket.rawValue) " +
                "advanceable=\(advanceable) " +
                "offerOverlap=\(candidate.coarse.offerOverlap) " +
                "capabilityOverlap=\(candidate.coarse.capabilityOverlap) " +
                "affinityOverlap=\(candidate.coarse.affinityOverlap) " +
                "summary=\(summary)"
            )

            hydrated.append(
                RankedCandidate(
                    candidate: candidate,
                    match: match,
                    isAdvanceable: advanceable,
                    rankSummary: summary
                )
            )
        }

        let bestAvailable = selectBestMatch(
            thread: thread,
            hydrated: hydrated
        )
        let bestOverall = hydrated.first?.match

        let strongAdvanceable = hydrated.filter {
            $0.isAdvanceable && $0.match.strength == .strong
        }

        let moderateAdvanceable = hydrated.filter {
            $0.isAdvanceable && $0.match.strength == .moderate
        }

        let blockedButGood = hydrated.filter {
            !$0.isAdvanceable &&
            ($0.match.strength == .strong || $0.match.strength == .moderate)
        }

        exDiscoveryLog(
            "classifyShortlist buckets " +
            "hydrated=\(hydrated.count) " +
            "strongAdvanceable=\(strongAdvanceable.count) " +
            "moderateAdvanceable=\(moderateAdvanceable.count) " +
            "blockedButGood=\(blockedButGood.count)"
        )

        if let top = hydrated.first {
            exDiscoveryLog(
                "classifyShortlist top " +
                "counterpartyID=\(top.match.counterpartyID) " +
                "scope=\(top.match.scope.rawValue) " +
                "surface=\(top.candidate.dominantSurface.rawValue) " +
                "publicProfileID=\(top.match.publicProfileID ?? "nil") " +
                "offerID=\(top.match.offerID ?? "nil") " +
                "fitScore=\(String(format: "%.3f", top.match.score)) " +
                "discoveryScore=\(String(format: "%.3f", top.candidate.overallScore)) " +
                "advanceable=\(top.isAdvanceable) " +
                "strength=\(top.match.strength.rawValue)"
            )
        }

        if let selected = bestAvailable {
            exDiscoveryLog(
                "classifyShortlist selectedBest " +
                "counterpartyID=\(selected.counterpartyID) " +
                "offerID=\(selected.offerID ?? "nil") " +
                "fitScore=\(String(format: "%.3f", selected.score)) " +
                "strength=\(selected.strength.rawValue)"
            )
        }

        if !strongAdvanceable.isEmpty {
            let summary = buildFoundSummary(
                from: strongAdvanceable,
                fallback: summaryFallback,
                queryIntentClass: queryIntentClass,
                reviewNeeded: false
            )

            exDiscoveryLog(
                "classifyShortlist result=found " +
                "grade=strong " +
                "summary=\(summary)"
            )

            return .found(
                .init(
                    counterparties: hydrated.map(\.candidate.counterparty),
                    candidates: hydrated,
                    matches: hydrated.map(\.match),
                    bestMatch: bestAvailable ?? bestOverall,
                    summary: summary,
                    sourceSummary: sourceSummary,
                    classifyGrade: .strong
                )
            )
        }

        if !moderateAdvanceable.isEmpty {
            let summary = buildFoundSummary(
                from: moderateAdvanceable,
                fallback: summaryFallback,
                queryIntentClass: queryIntentClass,
                reviewNeeded: true
            )

            exDiscoveryLog(
                "classifyShortlist result=found " +
                "grade=moderate_review_needed " +
                "summary=\(summary)"
            )

            return .found(
                .init(
                    counterparties: hydrated.map(\.candidate.counterparty),
                    candidates: hydrated,
                    matches: hydrated.map(\.match),
                    bestMatch: bestAvailable ?? bestOverall,
                    summary: summary,
                    sourceSummary: sourceSummary,
                    classifyGrade: .moderateReviewNeeded
                )
            )
        }

        let weakSummary: String
        let weakRecommendation: String

        if !blockedButGood.isEmpty {
            if blockedButGood.contains(where: { $0.candidate.posture.bucket == .introRequired }) {
                weakSummary = "I found relevant public surfaces, but the best paths require an introduction or trusted route."
                weakRecommendation = "Review the candidates and decide whether to pursue an introduction path."
            } else if blockedButGood.contains(where: { $0.candidate.posture.bucket == .visibleButBlocked }) {
                weakSummary = "I found relevant public surfaces, but they are not currently contactable under their public posture."
                weakRecommendation = "Review the visible candidates, widen the search, or choose a different path."
            } else {
                weakSummary = summaryFallback
                weakRecommendation = recommendationFallback ?? "Review the candidates carefully, refine the request, or widen the search."
            }
        } else {
            weakSummary = summaryFallback
            weakRecommendation = recommendationFallback ?? weakRecommendationForNoStrongResult(queryIntentClass)
        }

        exDiscoveryLog(
            "classifyShortlist result=weak " +
            "summary=\(weakSummary) " +
            "recommendation=\(weakRecommendation)"
        )

        return .weak(
            .init(
                counterparties: hydrated.map(\.candidate.counterparty),
                candidates: hydrated,
                matches: hydrated.map(\.match),
                bestAvailableMatch: bestAvailable,
                bestOverallMatch: bestOverall,
                summary: weakSummary,
                recommendation: weakRecommendation,
                sourceSummary: sourceSummary
            )
        )
    }

    func isAdvanceable(
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        match: ExchangeMatch,
        thread: ExchangeThread,
        searchPlan: ExchangeDiscoveryEngine.SearchPlan
    ) -> Bool {
        guard candidate.posture.bucket == .contactable && match.strength != .weak else {
            return false
        }

        let semanticTarget = searchPlan.semanticTarget ?? ExchangeSemanticTarget.from(thread: thread)
        if semanticTarget.minimumProofPolicy.requiresConcreteProof {
            let proof = resolvedSemanticProof(candidate: candidate, match: match)
            if !proof.isEmpty {
                guard proof.summary.satisfiesMinimumProof else {
                    return false
                }
            } else if !ExchangeOfferObjectLane.isObjectLaneActive(thread: thread) {
                return false
            }
        }

        if ExchangeOfferObjectLane.isObjectLaneActive(thread: thread) {
            guard !candidate.provenObjectOfferIDs.isEmpty else {
                return false
            }
            guard ExchangeOfferObjectLane.resolveSelectedOfferID(
                provenObjectOfferIDs: candidate.provenObjectOfferIDs,
                objectEvidenceScoreByOfferID: candidate.objectEvidenceScoreByOfferID
            ) != nil else {
                return false
            }
        }

        return true
    }

    func resolvedSemanticProof(
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        match: ExchangeMatch
    ) -> ExchangeCandidateSemanticProof {
        if !candidate.semanticProof.isEmpty {
            return candidate.semanticProof
        }
        return match.semanticProof ?? .empty
    }

    func proofAwareBestMatchSelectionActive(thread: ExchangeThread) -> Bool {
        ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
            || ExchangeSemanticTarget.from(thread: thread).minimumProofPolicy.requiresConcreteProof
    }

    func objectLaneBestMatchSelectionActive(thread: ExchangeThread) -> Bool {
        ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
    }

    func maxQualifyingObjectEvidenceScore(
        for ranked: RankedCandidate
    ) -> Double {
        let candidate = ranked.candidate
        let scores = ranked.match.objectEvidenceScoreByOfferID.isEmpty
            ? candidate.objectEvidenceScoreByOfferID
            : ranked.match.objectEvidenceScoreByOfferID
        return scores
            .filter { entry in
                candidate.provenObjectOfferIDs.contains(entry.key)
                    && entry.value >= ExchangeOfferObjectLane.minimumObjectEvidenceScore
            }
            .values
            .max() ?? 0
    }

    var objectLaneObjectEvidenceTieBand: Double { 0.12 }

    func proofValidSpecificityPrefers(
        lhs: RankedCandidate,
        rhs: RankedCandidate
    ) -> Bool {
        let lhsProof = resolvedSemanticProof(candidate: lhs.candidate, match: lhs.match)
        let rhsProof = resolvedSemanticProof(candidate: rhs.candidate, match: rhs.match)
        guard lhsProof.summary.satisfiesMinimumProof,
              rhsProof.summary.satisfiesMinimumProof else {
            return false
        }

        let lhsSpecificity = fitEngine.proofSpecificityOfferBonus(
            proof: lhsProof,
            candidate: lhs.candidate
        )
        let rhsSpecificity = fitEngine.proofSpecificityOfferBonus(
            proof: rhsProof,
            candidate: rhs.candidate
        )
        let delta = lhsSpecificity - rhsSpecificity
        guard abs(delta) >= 0.04 else { return false }
        return delta > 0
    }

    func objectLaneBestMatchOrdering(
        lhs: RankedCandidate,
        rhs: RankedCandidate
    ) -> Bool {
        let lhsObject = maxQualifyingObjectEvidenceScore(for: lhs)
        let rhsObject = maxQualifyingObjectEvidenceScore(for: rhs)
        let objectEvidenceDelta = abs(lhsObject - rhsObject)

        if objectEvidenceDelta > objectLaneObjectEvidenceTieBand {
            return lhsObject > rhsObject
        }

        if proofValidSpecificityPrefers(lhs: lhs, rhs: rhs) {
            return true
        }
        if proofValidSpecificityPrefers(lhs: rhs, rhs: lhs) {
            return false
        }

        if lhs.match.score != rhs.match.score {
            return lhs.match.score > rhs.match.score
        }

        if objectEvidenceDelta > 0 {
            return lhsObject > rhsObject
        }

        if lhs.candidate.overallScore != rhs.candidate.overallScore {
            return lhs.candidate.overallScore > rhs.candidate.overallScore
        }

        if lhs.match.strength.sortPriority != rhs.match.strength.sortPriority {
            return lhs.match.strength.sortPriority > rhs.match.strength.sortPriority
        }

        if lhs.match.counterpartyID != rhs.match.counterpartyID {
            return lhs.match.counterpartyID < rhs.match.counterpartyID
        }

        let lhsOffer = lhs.match.offerID ?? lhs.match.matchedOfferIDs.first ?? ""
        let rhsOffer = rhs.match.offerID ?? rhs.match.matchedOfferIDs.first ?? ""
        return lhsOffer < rhsOffer
    }

    func selectBestMatch(
        thread: ExchangeThread,
        hydrated: [RankedCandidate]
    ) -> ExchangeMatch? {
        let advanceable = hydrated.filter(\.isAdvanceable)
        guard !advanceable.isEmpty else { return nil }

        let semanticTarget = ExchangeSemanticTarget.from(thread: thread)

        let anySemanticProof = advanceable.contains {
            !resolvedSemanticProof(candidate: $0.candidate, match: $0.match).isEmpty
        }

        guard proofAwareBestMatchSelectionActive(thread: thread),
              objectLaneBestMatchSelectionActive(thread: thread) || anySemanticProof else {
            return advanceable.first?.match
        }

        let discoveryTop = hydrated.first
        let fitTop = hydrated.max(by: { $0.match.score < $1.match.score })
        let selected = advanceable.max(by: { lhs, rhs in
            !proofAwareBestMatchOrdering(lhs: lhs, rhs: rhs, target: semanticTarget, thread: thread)
        })

        if let selected {
            let proof = resolvedSemanticProof(candidate: selected.candidate, match: selected.match)
            exDiscoveryLog(
                "[DiscoveryFitDivergence] " +
                "discoveryTop=\(discoveryTop?.match.counterpartyID ?? "nil") " +
                "fitTop=\(fitTop?.match.counterpartyID ?? "nil") " +
                "selected=\(selected.match.counterpartyID) " +
                "selectedOfferID=\(selected.match.offerID ?? "nil") " +
                "selectedObjectEvidence=\(String(format: "%.3f", maxQualifyingObjectEvidenceScore(for: selected))) " +
                "selectedProofStrength=\(proof.summary.maxProofStrength.rawValue) " +
                "selectedSatisfiesMinimumProof=\(proof.summary.satisfiesMinimumProof) " +
                "selectedFitScore=\(String(format: "%.3f", selected.match.score)) " +
                "selectedDiscoveryScore=\(String(format: "%.3f", selected.candidate.overallScore))"
            )
        }

        return selected?.match
    }

    func proofAwareBestMatchOrdering(
        lhs: RankedCandidate,
        rhs: RankedCandidate,
        target: ExchangeSemanticTarget,
        thread: ExchangeThread
    ) -> Bool {
        if ExchangeOfferObjectLane.isObjectLaneActive(thread: thread) {
            return objectLaneBestMatchOrdering(lhs: lhs, rhs: rhs)
        }

        if target.minimumProofPolicy.requiresConcreteProof {
            let lhsProof = resolvedSemanticProof(candidate: lhs.candidate, match: lhs.match)
            let rhsProof = resolvedSemanticProof(candidate: rhs.candidate, match: rhs.match)

            if lhsProof.summary.satisfiesMinimumProof != rhsProof.summary.satisfiesMinimumProof {
                return lhsProof.summary.satisfiesMinimumProof
            }

            if lhsProof.summary.maxProofStrength.selectionPriority
                != rhsProof.summary.maxProofStrength.selectionPriority {
                return lhsProof.summary.maxProofStrength.selectionPriority
                    > rhsProof.summary.maxProofStrength.selectionPriority
            }
        }

        if lhs.match.score != rhs.match.score {
            return lhs.match.score > rhs.match.score
        }

        if lhs.candidate.overallScore != rhs.candidate.overallScore {
            return lhs.candidate.overallScore > rhs.candidate.overallScore
        }

        if lhs.match.strength.sortPriority != rhs.match.strength.sortPriority {
            return lhs.match.strength.sortPriority > rhs.match.strength.sortPriority
        }

        if lhs.match.counterpartyID != rhs.match.counterpartyID {
            return lhs.match.counterpartyID < rhs.match.counterpartyID
        }

        let lhsOffer = lhs.match.offerID ?? lhs.match.matchedOfferIDs.first ?? ""
        let rhsOffer = rhs.match.offerID ?? rhs.match.matchedOfferIDs.first ?? ""
        return lhsOffer < rhsOffer
    }

    func candidateSummary(
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        match: ExchangeMatch,
        advanceable: Bool,
        queryIntentClass: ExchangeIntent.QueryIntentClass
    ) -> String {
        if advanceable {
            switch queryIntentClass {
            case .providerSearch, .offerSearch:
                if match.strength == .strong && candidate.dominantSurface == .offer {
                    return "Strong provider-facing fit and currently advanceable."
                }
                if match.strength == .strong {
                    return "Strong provider search fit and currently advanceable."
                }
                return "Relevant provider-facing path, but still needs review."

            case .capabilitySearch, .collaborationSearch:
                if match.strength == .strong && candidate.dominantSurface == .capability {
                    return "Strong capability-oriented fit and currently advanceable."
                }
                if match.strength == .strong {
                    return "Strong collaboration fit and currently advanceable."
                }
                return "Relevant capability-oriented path, but still needs review."

            case .socialAffinitySearch, .relationshipSearch:
                if match.strength == .strong && candidate.dominantSurface == .affinity {
                    return "Strong affinity-oriented fit and currently advanceable."
                }
                if match.strength == .strong {
                    return "Strong social fit and currently advanceable."
                }
                return "Relevant social path, but still needs review."

            case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
                if match.strength == .strong && candidate.coarse.explicitTokenOverlap > 0 {
                    return "Strong explicit public fit and currently advanceable."
                }
                if match.strength == .strong {
                    return "Strong fit and currently advanceable."
                }
                return "Relevant and advanceable, but still needs review."
            }
        }

        switch candidate.posture.bucket {
        case .introRequired:
            return "Relevant, but requires introduction before advancing."
        case .visibleButBlocked:
            return "Relevant, but currently blocked by public posture."
        case .visibleButWeak:
            return "Relevant, but explicit openness is weak."
        case .unusable:
            return "Signal exists, but not usable as a current path."
        case .contactable:
            return "Contactable, but fit is still too weak to advance."
        }
    }

    func buildFoundSummary(
        from candidates: [RankedCandidate],
        fallback: String,
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        reviewNeeded: Bool
    ) -> String {
        guard let first = candidates.first else {
            return fallback
        }

        switch queryIntentClass {
        case .providerSearch, .offerSearch:
            if reviewNeeded {
                if first.candidate.dominantSurface == .offer {
                    return "I found provider-facing public surfaces with a usable path, but they still need review."
                }
                return "I found relevant public surfaces for the provider search, but the best path still needs review."
            }

            if first.candidate.dominantSurface == .offer {
                return "I found relevant provider-facing public surfaces with a usable path."
            }
            return "I found relevant public surfaces for the provider search."

        case .capabilitySearch, .collaborationSearch:
            if reviewNeeded {
                if first.candidate.dominantSurface == .capability {
                    return "I found capability-oriented public surfaces with a usable path, but they still need review."
                }
                return "I found relevant public surfaces for the collaboration search, but the best path still needs review."
            }

            if first.candidate.dominantSurface == .capability {
                return "I found relevant capability-oriented public surfaces with a usable path."
            }
            return "I found relevant public surfaces for the collaboration search."

        case .socialAffinitySearch, .relationshipSearch:
            if reviewNeeded {
                if first.candidate.dominantSurface == .affinity {
                    return "I found social and affinity-oriented public surfaces with usable paths, but they still need review."
                }
                return "I found relevant public surfaces for the affinity search, but the best path still needs review."
            }

            if first.candidate.dominantSurface == .affinity {
                return "I found relevant social and affinity-oriented public surfaces with a usable path."
            }
            return "I found relevant public surfaces for the affinity search."

        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            if reviewNeeded {
                if first.candidate.coarse.explicitTokenOverlap > 0 {
                    return "I found relevant public surfaces with usable paths, but they still need review."
                }
                return "I found relevant public surfaces, but the best path still needs review."
            }

            if first.candidate.coarse.explicitTokenOverlap > 0 {
                return "I found relevant public surfaces with explicit openness and a contactable path."
            }
            if first.match.strength == .strong {
                return "I found relevant public surfaces with a contactable path."
            }
            return fallback
        }
    }

    func weakRecommendationForNoStrongResult(
        _ queryIntentClass: ExchangeIntent.QueryIntentClass
    ) -> String {
        switch queryIntentClass {
        case .providerSearch, .offerSearch:
            return "Review the weak provider candidates, refine the request, or widen the search."
        case .capabilitySearch, .collaborationSearch:
            return "Review the weak capability candidates, refine the request, or widen the search."
        case .socialAffinitySearch, .relationshipSearch:
            return "Review the weak social candidates, refine the request, or widen the search."
        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return "Review the weak candidates, refine the request, or widen the search."
        }
    }
}

extension ExchangeDiscoveryService {
    func evaluateAdvanceabilityForTests(
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        match: ExchangeMatch,
        thread: ExchangeThread,
        searchPlan: ExchangeDiscoveryEngine.SearchPlan
    ) -> Bool {
        isAdvanceable(
            candidate: candidate,
            match: match,
            thread: thread,
            searchPlan: searchPlan
        )
    }

    func selectBestMatchForTests(
        thread: ExchangeThread,
        hydrated: [RankedCandidate]
    ) -> ExchangeMatch? {
        selectBestMatch(
            thread: thread,
            hydrated: hydrated
        )
    }
}
