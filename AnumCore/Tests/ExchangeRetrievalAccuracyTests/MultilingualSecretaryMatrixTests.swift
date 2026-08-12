import XCTest
@testable import AnumCore

#if DEBUG

final class MultilingualSecretaryMatrixTests: XCTestCase {
    func testMatrixContainsAllRequiredVerticalsAndLanguagePairs() {
        let fixtures = MultilingualSecretaryMatrixFixtures.all
        XCTAssertEqual(fixtures.count, 50)

        let verticals = Set(fixtures.map(\.vertical))
        XCTAssertEqual(verticals.count, MultilingualSecretaryMatrixVertical.allCases.count)
        XCTAssertEqual(verticals, Set(MultilingualSecretaryMatrixVertical.allCases))

        let pairs = Set(fixtures.map(\.languagePair))
        XCTAssertEqual(pairs.count, MultilingualSecretaryMatrixLanguagePair.allCases.count)
        XCTAssertEqual(pairs, Set(MultilingualSecretaryMatrixLanguagePair.allCases))

        let ids = Set(fixtures.map(\.id))
        XCTAssertEqual(ids.count, 50)
    }

    func testMultilingualSecretaryMatrixDeterministicAllRowsPass() async throws {
        let batch = try await MultilingualSecretaryMatrixRunner.runAll()
        XCTAssertEqual(batch.runs.count, 50)
        let failures = batch.runs.filter { !$0.passed }
        if !failures.isEmpty {
            let summary = failures.prefix(5).map { "\($0.fixtureID): \($0.failureReasons.joined(separator: "; "))" }.joined(separator: "\n")
            XCTFail("matrix failures=\(failures.count)/\(batch.runs.count)\n\(summary)")
        }
        XCTAssertEqual(batch.passCount, 50)
    }

    func testMatrixDetectsLostEnglishCarrier() async throws {
        let fixture = MultilingualSecretaryMatrixFixtures.all.first { $0.vertical == .roofer }!
        let result = try await MultilingualSecretaryMatrixRunner.run(
            fixture: fixture,
            forceMissingProviderCarrier: true
        )
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.failureReasons.contains(where: { $0.contains("canonicalEnglishRetrievalText missing") }))
        XCTAssertNil(result.providerCanonicalEnglishRetrievalText)
    }

    func testMatrixCatalogBuildsEnglishProjectionAndServiceAreas() {
        let fixture = MultilingualSecretaryMatrixFixtures.all.first { $0.vertical == .plumber }!
        let catalog = MultilingualSecretaryMatrixCatalogBuilder.buildCatalog(for: fixture)
        let audit = MultilingualSecretaryMatrixEvaluation.providerProjectionAudit(catalog: catalog, fixture: fixture)
        XCTAssertNotNil(audit)
        XCTAssertTrue(audit?.offerObjectUsesEnglishOnlyRetrievalProjection == true)
        XCTAssertTrue(audit?.offerDetailUsesEnglishOnlyRetrievalProjection == true)
        XCTAssertFalse(audit?.canonicalEnglishRetrievalText?.isEmpty ?? true)
        XCTAssertTrue(audit?.serviceAreas.contains("Mississauga") == true)
    }
    func testMatrixDetectsNoisyProfileOutrankingExactOffer() {
        let fixture = MultilingualSecretaryMatrixFixtures.all.first {
            $0.vertical == .plumber && $0.languagePair == .zhUserZhProvider
        }!
        var inputs = MultilingualSecretaryMatrixEvaluation.makePassingInputs(for: fixture)
        inputs.sortedMatches = [
            MultilingualSecretaryMatrixEvaluation.stubDiscoveryMatch(
                threadID: inputs.thread.id,
                counterpartyID: fixture.forbiddenNoisyNodeID,
                offerID: fixture.forbiddenNoisyOfferID,
                score: 0.99
            ),
            MultilingualSecretaryMatrixEvaluation.stubDiscoveryMatch(
                threadID: inputs.thread.id,
                counterpartyID: fixture.expectedSelectedNodeID,
                offerID: fixture.expectedSelectedOfferID,
                score: 0.40
            )
        ]
        inputs.selectedOfferID = fixture.forbiddenNoisyOfferID
        inputs.selectedCandidateID = fixture.forbiddenNoisyNodeID
        inputs.ui.selectedOfferID = fixture.forbiddenNoisyOfferID

        let evaluation = MultilingualSecretaryMatrixEvaluation.evaluate(inputs: inputs)
        XCTAssertFalse(evaluation.passed)
        XCTAssertTrue(
            evaluation.failures.contains(where: { $0.contains("noisy profile/offer outranked exact object offer") }),
            "expected noisy outranking failure, got: \(evaluation.failures.joined(separator: "; "))"
        )
    }

    func testMatrixDetectsForbiddenMissingFacts() {
        let fixture = MultilingualSecretaryMatrixFixtures.all.first {
            $0.vertical == .roofer && $0.languagePair == .zhUserZhProvider
        }!
        var inputs = MultilingualSecretaryMatrixEvaluation.makePassingInputs(for: fixture)
        let missingFacts = ["Need service location details", "Need the user's budget"]
        inputs.secondHalf = MultilingualE2ESecondHalfSnapshot(
            missingFacts: missingFacts,
            forbiddenMissingFactsTriggered: MultilingualRetrievalE2EEvaluation.classifyForbiddenMissingFacts(
                missingFacts: missingFacts,
                forbiddenCategories: fixture.forbiddenMissingFacts
            ),
            clarificationText: nil,
            clarificationLanguage: nil,
            compareSucceeded: false
        )

        let evaluation = MultilingualSecretaryMatrixEvaluation.evaluate(inputs: inputs)
        XCTAssertFalse(evaluation.passed)
        XCTAssertTrue(
            evaluation.failures.contains(where: { $0.contains("forbidden second-half missing facts") }),
            "expected forbidden missing-facts failure, got: \(evaluation.failures.joined(separator: "; "))"
        )
    }

}

#endif
