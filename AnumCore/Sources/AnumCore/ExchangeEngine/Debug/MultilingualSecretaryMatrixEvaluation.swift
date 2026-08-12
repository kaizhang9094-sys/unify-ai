import Foundation

#if DEBUG

public struct MultilingualSecretaryMatrixEvaluationInputs: Sendable {
    public var fixture: MultilingualSecretaryMatrixFixture
    public var searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    public var thread: ExchangeThread
    public var sortedMatches: [ExchangeMatch]
    public var rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow]
    public var selectedOfferID: String?
    public var selectedCandidateID: String?
    public var objectLaneActive: Bool
    public var providerProjection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?
    public var secondHalf: MultilingualE2ESecondHalfSnapshot
    public var ui: AppSearchSmokeUIProjectionSnapshot

    public init(
        fixture: MultilingualSecretaryMatrixFixture,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        thread: ExchangeThread,
        sortedMatches: [ExchangeMatch],
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        selectedOfferID: String?,
        selectedCandidateID: String?,
        objectLaneActive: Bool,
        providerProjection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?,
        secondHalf: MultilingualE2ESecondHalfSnapshot,
        ui: AppSearchSmokeUIProjectionSnapshot
    ) {
        self.fixture = fixture
        self.searchIntent = searchIntent
        self.thread = thread
        self.sortedMatches = sortedMatches
        self.rankingTrace = rankingTrace
        self.selectedOfferID = selectedOfferID
        self.selectedCandidateID = selectedCandidateID
        self.objectLaneActive = objectLaneActive
        self.providerProjection = providerProjection
        self.secondHalf = secondHalf
        self.ui = ui
    }
}

public enum MultilingualSecretaryMatrixEvaluation {
    public static func makePassingInputs(
        for fixture: MultilingualSecretaryMatrixFixture
    ) -> MultilingualSecretaryMatrixEvaluationInputs {
        let catalog = MultilingualSecretaryMatrixCatalogBuilder.buildCatalog(for: fixture)
        let projection = providerProjectionAudit(catalog: catalog, fixture: fixture)
        let (thread, searchIntent) = MultilingualSecretaryMatrixRunner.makeThreadAndSearchIntent(for: fixture)
        return MultilingualSecretaryMatrixEvaluationInputs(
            fixture: fixture,
            searchIntent: searchIntent,
            thread: thread,
            sortedMatches: [],
            rankingTrace: [],
            selectedOfferID: fixture.expectedSelectedOfferID,
            selectedCandidateID: fixture.expectedSelectedNodeID,
            objectLaneActive: false,
            providerProjection: projection,
            secondHalf: MultilingualE2ESecondHalfSnapshot(
                missingFacts: ["availability confirmation"],
                forbiddenMissingFactsTriggered: [],
                clarificationText: nil,
                clarificationLanguage: nil,
                compareSucceeded: false
            ),
            ui: AppSearchSmokeUIProjectionSnapshot(
                selectedOfferID: fixture.expectedSelectedOfferID,
                matchedOffersByNode: [fixture.expectedSelectedNodeID: [fixture.expectedSelectedOfferID]],
                preferredMatchCounterpartyID: fixture.expectedSelectedNodeID,
                preferredMatchOfferID: fixture.expectedSelectedOfferID,
                cardOfferID: fixture.expectedSelectedOfferID,
                visiblePublicProfileID: "profile-\(fixture.expectedSelectedNodeID)",
                surfaceLead: "offer",
                displaySearchQuery: fixture.userText,
                capturedRequestText: fixture.userText,
                visibleSummary: "Matched provider",
                threadTitle: fixture.userText
            )
        )
    }

    public static func evaluate(inputs: MultilingualSecretaryMatrixEvaluationInputs) -> (passed: Bool, failures: [String]) {
        evaluate(
            fixture: inputs.fixture,
            searchIntent: inputs.searchIntent,
            thread: inputs.thread,
            sortedMatches: inputs.sortedMatches,
            rankingTrace: inputs.rankingTrace,
            selectedOfferID: inputs.selectedOfferID,
            selectedCandidateID: inputs.selectedCandidateID,
            objectLaneActive: inputs.objectLaneActive,
            providerProjection: inputs.providerProjection,
            secondHalf: inputs.secondHalf,
            ui: inputs.ui
        )
    }

    public static func stubDiscoveryMatch(
        threadID: ExchangeThread.ID,
        counterpartyID: String,
        offerID: String,
        score: Double
    ) -> ExchangeMatch {
        ExchangeMatch(
            threadID: threadID,
            counterpartyID: counterpartyID,
            scope: .offer,
            publicProfileID: "profile-\(counterpartyID)",
            offerID: offerID,
            matchedOfferIDs: [offerID],
            strength: .strong,
            score: score
        )
    }

    public static func evaluate(
        fixture: MultilingualSecretaryMatrixFixture,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        thread: ExchangeThread,
        sortedMatches: [ExchangeMatch],
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        selectedOfferID: String?,
        selectedCandidateID: String?,
        objectLaneActive: Bool,
        providerProjection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?,
        secondHalf: MultilingualE2ESecondHalfSnapshot,
        ui: AppSearchSmokeUIProjectionSnapshot
    ) -> (passed: Bool, failures: [String]) {
        let scenario = fixture.toMultilingualScenario()
        var failures: [String] = []
        failures.append(contentsOf: MultilingualRetrievalE2EEvaluation.evaluateCanonicalIntent(
            scenario: scenario,
            searchIntent: searchIntent,
            thread: thread
        ))
        failures.append(contentsOf: evaluateProviderProjection(fixture: fixture, projection: providerProjection))
        failures.append(contentsOf: evaluateDiscovery(
            fixture: fixture,
            sortedMatches: sortedMatches,
            rankingTrace: rankingTrace,
            selectedOfferID: selectedOfferID,
            selectedCandidateID: selectedCandidateID,
            objectLaneActive: objectLaneActive
        ))
        failures.append(contentsOf: MultilingualRetrievalE2EEvaluation.evaluateSecondHalf(
            scenario: scenario,
            secondHalf: secondHalf
        ))
        failures.append(contentsOf: evaluateUIProjection(fixture: fixture, searchIntent: searchIntent, ui: ui))
        failures = Array(Set(failures)).sorted()
        return (failures.isEmpty, failures)
    }

    public static func evaluateProviderProjection(
        fixture: MultilingualSecretaryMatrixFixture,
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?
    ) -> [String] {
        var failures: [String] = []
        guard let projection else {
            failures.append("provider projection audit missing")
            return failures
        }

        let carrier = projection.canonicalEnglishRetrievalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if carrier.isEmpty {
            failures.append("provider canonicalEnglishRetrievalText missing")
        }

        if !projection.offerObjectUsesEnglishOnlyRetrievalProjection {
            failures.append("offer_object lacks English-only retrieval projection")
        }

        if !projection.offerDetailUsesEnglishOnlyRetrievalProjection {
            failures.append("offer_detail lacks English-only retrieval projection")
        }

        let serviceAreas = projection.serviceAreas.map { $0.lowercased() }
        for expected in fixture.expectedServiceAreas {
            if !serviceAreas.contains(expected.lowercased()) {
                failures.append("serviceAreas missing \(expected) actual=\(projection.serviceAreas.joined(separator: ","))")
            }
        }

        let objectText = projection.offerObjectSearchableText?.lowercased() ?? ""
        let objectToken = fixture.expectedObjectType.lowercased()
        if !objectText.contains(objectToken) {
            let carrierHit = fixture.expectedEnglishCarrierTokens.contains { token in
                objectText.contains(token.lowercased())
            }
            if !carrierHit {
                failures.append("offer_object missing expected object/carrier tokens for \(fixture.vertical.rawValue)")
            }
        }

        if expectsChineseProvider(fixture.languagePair), !projection.preservedChineseInSourceBlocks {
            failures.append("original Chinese provider text not preserved in source blocks")
        }

        if projection.offerID != fixture.expectedSelectedOfferID {
            failures.append("provider projection offerID mismatch")
        }

        return failures
    }

    public static func evaluateUIProjection(
        fixture: MultilingualSecretaryMatrixFixture,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        ui: AppSearchSmokeUIProjectionSnapshot
    ) -> [String] {
        guard fixture.originalDisplayTextMustEqualUserText else { return [] }
        var failures: [String] = []
        let raw = fixture.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = ui.displaySearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let captured = ui.capturedRequestText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if display.isEmpty {
            failures.append("UI displaySearchQuery missing")
            return failures
        }

        if MultilingualRetrievalE2EEvaluation.containsCJK(raw) {
            if display == searchIntent?.canonicalEnglishSearchText {
                failures.append("UI primary request uses normalized English instead of original user text")
            }
            if !MultilingualRetrievalE2EEvaluation.containsCJK(display) {
                failures.append("UI displaySearchQuery is not original user request text")
            }
        }

        if display != raw && captured != raw {
            failures.append("UI request text does not preserve original user request")
        }

        if ui.selectedOfferID != fixture.expectedSelectedOfferID {
            failures.append(
                "UI selectedOfferID mismatch expected=\(fixture.expectedSelectedOfferID) actual=\(ui.selectedOfferID ?? "nil")"
            )
        }
        return failures
    }

    public static func providerProjectionAudit(
        catalog: [ExchangeDirectoryMatch],
        fixture: MultilingualSecretaryMatrixFixture
    ) -> MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit? {
        guard let match = catalog.first(where: { $0.id == fixture.expectedSelectedNodeID }) else { return nil }
        let offerDocs = match.retrievalDocuments.filter { $0.offerID == fixture.expectedSelectedOfferID }
        let detailDoc = offerDocs.first(where: { $0.docKind == .offerDetail })
        let objectDoc = offerDocs.first(where: { $0.docKind == .offerObject })
        let serviceAreas = detailDoc?.serviceAreas.map(\.displayName) ?? fixture.expectedServiceAreas
        let joinedSource = (
            [match.offers.first?.summary, match.offers.first?.title].compactMap { $0 }
            + match.retrievalDocuments.flatMap { [$0.primaryText, $0.summary].compactMap { $0 } }
        ).joined(separator: " ")
        let chinesePreserved = expectsChineseProvider(fixture.languagePair)
            ? MultilingualRetrievalE2EEvaluation.containsCJK(joinedSource)
            : true
        return MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit(
            nodeID: fixture.expectedSelectedNodeID,
            offerID: fixture.expectedSelectedOfferID,
            canonicalEnglishRetrievalText: detailDoc?.canonicalEnglishRetrievalText,
            offerDetailUsesEnglishOnlyRetrievalProjection: detailDoc?.usesEnglishOnlyRetrievalProjection ?? false,
            offerObjectUsesEnglishOnlyRetrievalProjection: objectDoc?.usesEnglishOnlyRetrievalProjection ?? false,
            serviceAreas: serviceAreas,
            offerObjectSearchableText: objectDoc?.searchableText,
            preservedChineseInSourceBlocks: chinesePreserved
        )
    }

    public static func evaluateDiscovery(
        fixture: MultilingualSecretaryMatrixFixture,
        sortedMatches: [ExchangeMatch],
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        selectedOfferID: String?,
        selectedCandidateID: String?,
        objectLaneActive: Bool
    ) -> [String] {
        let scenario = fixture.toMultilingualScenario()
        var failures: [String] = []

        if objectLaneActive != scenario.expectedObjectLaneActive {
            failures.append(
                "objectLaneActive mismatch expected=\(scenario.expectedObjectLaneActive) actual=\(objectLaneActive)"
            )
        }

        let selectedOffer = normalized(selectedOfferID)
        let expectedOffer = normalized(fixture.expectedSelectedOfferID)
        let noisyOffer = normalized(fixture.forbiddenNoisyOfferID)
        if selectedOffer == noisyOffer {
            failures.append("noisy profile/offer outranked exact object offer")
        } else if selectedOffer != expectedOffer {
            failures.append(
                "selected offer mismatch expected=\(fixture.expectedSelectedOfferID) actual=\(selectedOfferID ?? "nil")"
            )
        }

        let selectedNode = normalized(selectedCandidateID)
        let expectedNode = normalized(fixture.expectedSelectedNodeID)
        let noisyNode = normalized(fixture.forbiddenNoisyNodeID)
        if selectedNode == noisyNode {
            if !failures.contains(where: { $0.contains("noisy profile/offer outranked exact object offer") }) {
                failures.append("noisy profile/offer outranked exact object offer")
            }
        } else if selectedNode != expectedNode {
            failures.append(
                "selected candidate mismatch expected=\(fixture.expectedSelectedNodeID) actual=\(selectedCandidateID ?? "nil")"
            )
        }

        if let noisyRank = rankOfNode(fixture.forbiddenNoisyNodeID, in: sortedMatches),
           let exactRank = rankOfNode(fixture.expectedSelectedNodeID, in: sortedMatches),
           noisyRank < exactRank {
            let reason =
                "noisy profile/offer outranked exact object offer (rank noisy=\(noisyRank + 1) exact=\(exactRank + 1))"
            if !failures.contains(reason) {
                failures.append(reason)
            }
        }

        if let noisyTraceRank = rankOfNodeInTrace(fixture.forbiddenNoisyNodeID, trace: rankingTrace),
           let exactTraceRank = rankOfNodeInTrace(fixture.expectedSelectedNodeID, trace: rankingTrace),
           noisyTraceRank < exactTraceRank {
            let reason =
                "noisy profile/offer outranked exact object offer in retrieval trace (rank noisy=\(noisyTraceRank + 1) exact=\(exactTraceRank + 1))"
            if !failures.contains(reason) {
                failures.append(reason)
            }
        }

        return failures
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rankOfNode(_ nodeID: String, in matches: [ExchangeMatch]) -> Int? {
        for (index, match) in matches.enumerated() where match.counterpartyID == nodeID {
            return index
        }
        return nil
    }

    private static func rankOfNodeInTrace(
        _ nodeID: String,
        trace: [ExchangeRetrievalDebugTrace.RankingRow]
    ) -> Int? {
        for (index, row) in trace.enumerated() where row.counterpartyID == nodeID {
            return index
        }
        return nil
    }

    private static func expectsChineseProvider(_ pair: MultilingualSecretaryMatrixLanguagePair) -> Bool {
        switch pair {
        case .enUserEnProvider, .zhUserEnProvider:
            return false
        case .enUserZhProvider, .zhUserZhProvider, .mixedUserMixedProvider:
            return true
        }
    }
}

#endif
