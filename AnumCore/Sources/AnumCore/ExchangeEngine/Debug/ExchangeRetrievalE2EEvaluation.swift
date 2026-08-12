import Foundation

#if DEBUG

public struct RetrievalE2EEvaluationResult: Sendable, Hashable {
    public var passed: Bool
    public var structuralFailures: [String]
    public var rankingFailures: [String]
    public var strictFailures: [String]
    public var uiFailures: [String]
    public var allFailures: [String]
    public var fullEvaluateApplied: Bool

    public init(
        passed: Bool,
        structuralFailures: [String],
        rankingFailures: [String],
        strictFailures: [String],
        uiFailures: [String],
        allFailures: [String],
        fullEvaluateApplied: Bool
    ) {
        self.passed = passed
        self.structuralFailures = structuralFailures
        self.rankingFailures = rankingFailures
        self.strictFailures = strictFailures
        self.uiFailures = uiFailures
        self.allFailures = allFailures
        self.fullEvaluateApplied = fullEvaluateApplied
    }
}

public enum ExchangeRetrievalE2EEvaluation {
    public static func evaluate(
        scenario: ExchangeRetrievalE2EScenario,
        thread: ExchangeThread,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        sortedMatches: [ExchangeMatch],
        counterparties: [ExchangeCounterparty],
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        queryContext: ExchangeRetrievalDebugTrace.QueryContext,
        objectLaneActive: Bool,
        selectedOfferID: String?,
        matchedOffersByNode: [String: [String]],
        ui: AppSearchSmokeUIProjectionSnapshot
    ) -> RetrievalE2EEvaluationResult {
        let structuralFailures = evaluateStructural(
            expectation: scenario.structural,
            thread: thread,
            searchIntent: searchIntent,
            objectLaneActive: objectLaneActive,
            rankingTrace: rankingTrace,
            sortedMatches: sortedMatches,
            selectedOfferID: selectedOfferID
        )

        var rankingFailures: [String] = []
        var strictFailures: [String] = []
        var fullEvaluateApplied = false

        if let retrievalExpectation = scenario.retrieval {
            fullEvaluateApplied = true
            let rankedCandidates = rankedCandidates(from: sortedMatches, counterparties: counterparties)
            let evaluateResult = ExchangeRetrievalAccuracyReport.evaluate(
                expectation: retrievalExpectation,
                rankedCandidates: rankedCandidates,
                selectedOfferID: selectedOfferID,
                objectLaneActive: objectLaneActive,
                queryContext: queryContext,
                directoryRecall: nil,
                rankingTrace: rankingTrace
            )
            if let failureReason = evaluateResult.failureReason, !failureReason.isEmpty {
                rankingFailures = failureReason
                    .split(separator: ";")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }

            strictFailures = ExchangeRetrievalAccuracyReport.strictInvariantFailures(
                expectation: retrievalExpectation,
                result: evaluateResult,
                rankingTrace: rankingTrace
            )
        }

        let uiFailures = evaluateUIProjection(
            retrievalExpectation: scenario.retrieval,
            ui: ui,
            selectedOfferID: selectedOfferID,
            matchedOffersByNode: matchedOffersByNode
        )

        let allFailures = Array(
            Set(structuralFailures + rankingFailures + strictFailures + uiFailures)
        ).sorted()

        return RetrievalE2EEvaluationResult(
            passed: allFailures.isEmpty,
            structuralFailures: structuralFailures.sorted(),
            rankingFailures: rankingFailures.sorted(),
            strictFailures: strictFailures.sorted(),
            uiFailures: uiFailures.sorted(),
            allFailures: allFailures,
            fullEvaluateApplied: fullEvaluateApplied
        )
    }

    public static func evaluateStructural(
        expectation: ExchangeRetrievalE2EStructuralExpectation,
        thread: ExchangeThread,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        objectLaneActive: Bool,
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        sortedMatches: [ExchangeMatch],
        selectedOfferID: String?
    ) -> [String] {
        var failures: [String] = []

        if let requiredObjectType = expectation.requiredObjectType {
            let actualObjectType = searchIntent?.objectType?.trimmingCharacters(in: .whitespacesAndNewlines)
            if actualObjectType?.isEmpty != false {
                failures.append("objectType expected=\(requiredObjectType) actual=nil")
            } else if actualObjectType != requiredObjectType {
                failures.append("objectType expected=\(requiredObjectType) actual=\(actualObjectType ?? "nil")")
            }
        }

        if objectLaneActive != expectation.expectedObjectLaneActive {
            failures.append(
                "objectLaneActive expected=\(expectation.expectedObjectLaneActive) actual=\(objectLaneActive)"
            )
        }

        let routeClass = thread.intent.queryIntentClass.rawValue
        if let allowed = expectation.allowedRouteClasses, !allowed.isEmpty {
            if !allowed.contains(routeClass) {
                failures.append("routeClass expected one of [\(allowed.joined(separator: ","))] actual=\(routeClass)")
            }
        } else if let required = expectation.requiredRouteClass, routeClass != required {
            failures.append("routeClass expected=\(required) actual=\(routeClass)")
        }

        let surface = thread.facets?.surfacePreference.rawValue ?? thread.intent.surfacePreference.rawValue
        if let required = expectation.requiredSurfacePreference, surface != required {
            failures.append("surfacePreference expected=\(required) actual=\(surface)")
        }

        let domain = searchIntent?.domainCategory.rawValue
        if let required = expectation.requiredDomainCategory, domain != required {
            failures.append("domainCategory expected=\(required) actual=\(domain ?? "nil")")
        }
        if let forbidden = expectation.forbiddenDomainCategory, domain == forbidden {
            failures.append("domainCategory forbidden=\(forbidden) actual=\(domain ?? "nil")")
        }

        let transaction = searchIntent?.transactionIntent?.rawValue
        if let required = expectation.requiredTransactionIntent, transaction != required {
            failures.append("transactionIntent expected=\(required) actual=\(transaction ?? "nil")")
        }
        if let transaction,
           expectation.forbiddenTransactionIntents.contains(transaction) {
            failures.append("transactionIntent forbidden=\(transaction)")
        }

        if expectation.forbidIncorrectProductBuyLane {
            if objectLaneActive {
                failures.append("incorrect product buy object lane forced on service-like query")
            }
            if domain == ExchangeIntentFacets.DomainCategory.product.rawValue,
               transaction == ExchangeIntentFacets.TransactionIntent.buy.rawValue
                || transaction == ExchangeIntentFacets.TransactionIntent.forSale.rawValue {
                failures.append("product+buy canonical combination forbidden on service query")
            }
        }

        if expectation.requireTimeConstraint {
            let hasTime = !(searchIntent?.timeConstraints.isEmpty ?? true)
            if !hasTime {
                failures.append("missing preserved time constraint")
            }
        }

        if expectation.requireBudgetConstraint {
            let hasBudget = !(searchIntent?.commercialConstraints.isEmpty ?? true)
            if !hasBudget {
                failures.append("missing preserved budget constraint")
            }
        }

        if expectation.requireFAQDocsDoNotProveObject {
            failures.append(contentsOf: nonOfferObjectProofFailures(
                rankingTrace: rankingTrace,
                sortedMatches: sortedMatches,
                selectedOfferID: selectedOfferID,
                objectLaneActive: objectLaneActive
            ))
        }

        return failures
    }

    public static func evaluateUIProjection(
        retrievalExpectation: ExchangeRetrievalAccuracyScenarioExpectation?,
        ui: AppSearchSmokeUIProjectionSnapshot,
        selectedOfferID: String?,
        matchedOffersByNode: [String: [String]]
    ) -> [String] {
        var failures: [String] = []
        let uiCardOfferID = normalized(ui.cardOfferID)
        let projectedSelected = normalized(selectedOfferID)
        let uiSelected = normalized(ui.selectedOfferID)

        if let expectedOffer = retrievalExpectation?.selectedOfferID {
            if uiCardOfferID != normalized(expectedOffer) {
                failures.append(
                    "uiCardOfferID mismatch expected=\(expectedOffer) actual=\(ui.cardOfferID ?? "nil")"
                )
            }
        }

        if let uiCardOfferID {
            if let projectedSelected, uiCardOfferID != projectedSelected {
                failures.append(
                    "uiCardOfferID mismatch expected=\(projectedSelected) actual=\(uiCardOfferID)"
                )
            } else if projectedSelected == nil {
                let projectedOffers = Set(matchedOffersByNode.values.flatMap { $0 })
                if !projectedOffers.isEmpty, !projectedOffers.contains(uiCardOfferID) {
                    failures.append(
                        "uiCardOfferID mismatch expected one of [\(projectedOffers.sorted().joined(separator: ","))] actual=\(uiCardOfferID)"
                    )
                }
            }

            if let uiSelected, uiCardOfferID != uiSelected {
                failures.append(
                    "uiCardOfferID mismatch expected=\(uiSelected) actual=\(uiCardOfferID)"
                )
            }
        }

        if let retrievalExpectation {
            for forbidden in retrievalExpectation.forbiddenAttachments where uiCardOfferID == normalized(forbidden.offerID) {
                failures.append(
                    "uiCardOfferID forbidden attachment offerID=\(forbidden.offerID) nodeID=\(forbidden.nodeID)"
                )
            }
        }

        return Array(Set(failures)).sorted()
    }

    public static func nonOfferObjectProofFailures(
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        sortedMatches: [ExchangeMatch],
        selectedOfferID: String?,
        objectLaneActive: Bool
    ) -> [String] {
        var failures: [String] = []
        let minimumObjectEvidence = ExchangeOfferObjectLane.minimumObjectEvidenceScore
        let provenOfferIDs = Set(sortedMatches.flatMap(\.provenObjectOfferIDs))
        let selected = normalized(selectedOfferID)

        for row in rankingTrace {
            guard let docKind = row.docKind else { continue }
            guard docKind != ExchangeRetrievalDocument.DocKind.offerObject.rawValue else { continue }
            guard let offerID = normalized(row.offerID) else { continue }

            if let score = row.objectLaneScore, score >= minimumObjectEvidence {
                failures.append("nonOfferObjectProof docKind=\(docKind) offerID=\(offerID)")
            }
        }

        if !objectLaneActive, !provenOfferIDs.isEmpty {
            failures.append(
                "nonOfferObjectProof docKind=aggregate offerID=\(provenOfferIDs.sorted().joined(separator: ","))"
            )
        }

        if !objectLaneActive, let selected, provenOfferIDs.contains(selected) {
            failures.append("nonOfferObjectProof docKind=selectedOffer offerID=\(selected)")
        }

        return Array(Set(failures)).sorted()
    }

    public static func buildTransientEvaluation(
        fallbackReason: String?
    ) -> RetrievalE2EEvaluationResult {
        var failures = ["transientNonPersistent"]
        if let fallbackReason {
            failures.append("fallbackReason=\(fallbackReason)")
        }
        return RetrievalE2EEvaluationResult(
            passed: false,
            structuralFailures: failures,
            rankingFailures: [],
            strictFailures: [],
            uiFailures: [],
            allFailures: failures,
            fullEvaluateApplied: false
        )
    }

    private static func rankedCandidates(
        from matches: [ExchangeMatch],
        counterparties: [ExchangeCounterparty]
    ) -> [ExchangeDiscoveryService.RankedCandidate] {
        let counterpartyByID = ExchangeDebugProjectionMerge.keepFirstByID(counterparties) { $0.id }
        return matches.map { match in
            let counterparty = counterpartyByID[match.counterpartyID]
                ?? ExchangeCounterparty(
                    id: match.counterpartyID,
                    kind: .organization,
                    displayName: match.counterpartyID,
                    source: .localDirectory
                )
            let matchedOffers = match.matchedOfferIDs.map { offerID in
                ExchangeOffer(
                    id: offerID,
                    nodeID: match.counterpartyID,
                    title: offerID
                )
            }
            let candidate = ExchangeDiscoveryEngine.DiscoveryCandidate(
                publicProfile: counterparty.publicProfile,
                counterparty: counterparty,
                matchedOffers: matchedOffers,
                coarse: ExchangeDiscoveryEngine.CoarseSignal(
                    queryTokenOverlap: 0,
                    explicitTokenOverlap: 0,
                    regionOverlap: 0,
                    offerOverlap: matchedOffers.isEmpty ? 0 : 1,
                    capabilityOverlap: 0,
                    affinityOverlap: 0,
                    hasPublicProfile: counterparty.publicProfile != nil,
                    hasOffers: !matchedOffers.isEmpty,
                    kindCompatible: true,
                    placeCompatible: true,
                    trustHintScore: 0,
                    retrievalScore: match.score,
                    rationale: "retrieval-e2e-smoke"
                ),
                posture: ExchangeDiscoveryEngine.ContactPosture(
                    bucket: .contactable,
                    preview: "retrieval-e2e-smoke",
                    explicitOpenness: true,
                    requiresIntroduction: false
                ),
                dominantSurface: .offer,
                overallScore: match.score,
                provenance: .retrievalProjected,
                provenObjectOfferIDs: Set(match.provenObjectOfferIDs),
                objectEvidenceScoreByOfferID: match.objectEvidenceScoreByOfferID
            )
            return ExchangeDiscoveryService.RankedCandidate(
                candidate: candidate,
                match: match,
                isAdvanceable: match.status == .selected,
                rankSummary: "retrieval-e2e-smoke"
            )
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

#endif
