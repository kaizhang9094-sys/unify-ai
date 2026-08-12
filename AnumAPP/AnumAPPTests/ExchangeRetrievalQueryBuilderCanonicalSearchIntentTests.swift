import XCTest
import AnumCore

/// Phase 4: canonical `facets.searchIntent` drives retrieval query construction without legacy sentence blobs.
final class ExchangeRetrievalQueryBuilderCanonicalSearchIntentTests: XCTestCase {
    private let builder = ExchangeRetrievalQueryBuilder()

    func test_canonical_GTAVTBRetrievalSplitsBroadVersusSemanticAndBlocksFusedFragments() {
        let fusedLeak = "gta, and seller offers vendor take back mortgage"
        let fullUser = "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."

        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .realEstate,
            objectType: "house",
            transactionIntent: .forSale,
            places: [
                ExchangeIntentFacets.StructuredPlace(
                    normalizedText: "gta",
                    aliases: [],
                    confidence: 0.92,
                    isHard: true
                )
            ],
            attributes: [
                ExchangeIntentFacets.StructuredAttribute(key: "bedrooms", value: "3 bedroom", numericValue: 3)
            ],
            commercialConstraints: [
                ExchangeIntentFacets.StructuredCommercialConstraint(
                    kind: .financing,
                    key: "sellerFinancing",
                    value: "seller financing",
                    isHard: false
                )
            ],
            broadRecallTokens: ["house", "home", "seller financing", "gta"],
            semanticConcepts: ["house", "seller financing"],
            clarificationGaps: [],
            rawUserText: fullUser
        )

        let facets = ExchangeIntentFacets(
            searchIntent: si,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            providerTerms: ["house", "home", "listing"],
            primaryKeywords: [fullUser, fusedLeak]
        )

        let thread = pollutedThread(fullUserObjective: fullUser, facets: facets)
        let query = builder.build(from: thread)

        let qtRaw = unwrapText(query.queryText)
        XCTAssertTrue(qtRaw.lowercased().contains("for sale"))
        XCTAssertTrue(qtRaw.lowercased().contains("greater toronto") || qtRaw.lowercased().contains("residential"))

        let stRaw = unwrapText(query.semanticText)
        let st = stRaw.lowercased()
        XCTAssertTrue(st.contains("3 bedroom") || st.contains("3 bedrooms"))
        XCTAssertTrue(st.contains("seller financing"))
        XCTAssertTrue(st.contains("vtb"))

        XCTAssertTrue(Set(query.commercialIntentTerms).isSuperset(of: Set(["seller financing"])))

        XCTAssertFalse(st.contains(fusedLeak))
        XCTAssertFalse(qtRaw.lowercased().contains(fusedLeak))

        XCTAssertFalse(query.providerTerms.contains { $0.contains("seller financing") })

        XCTAssertTrue(query.keywords.contains(where: { $0.contains("real estate") }))
        XCTAssertFalse(query.keywords.joined(separator: " ").lowercased().contains("help me find"))

        let aggregate = aggregatedRetrievalTexts(query).lowercased()
        XCTAssertFalse(aggregate.contains(fusedLeak.lowercased()))
    }

    func test_canonical_rooferTomorrow_atomicBroadQueryAndTimingSoftRails() {
        let fullUser = "Find a roofer near Aurora who can come tomorrow."

        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "roofer",
            transactionIntent: nil,
            places: [
                ExchangeIntentFacets.StructuredPlace(
                    normalizedText: "aurora",
                    aliases: [],
                    confidence: 0.9,
                    isHard: true
                )
            ],
            timeConstraints: [ExchangeIntentFacets.StructuredTimeConstraint(kind: .day, text: "tomorrow")],
            broadRecallTokens: ["roofer", "aurora"],
            clarificationGaps: [],
            rawUserText: fullUser
        )

        let facets = ExchangeIntentFacets(
            searchIntent: si,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            primaryKeywords: [fullUser]
        )

        let thread = pollutedThread(fullUserObjective: fullUser, facets: facets)
        let query = builder.build(from: thread)

        let qt = unwrapText(query.queryText).lowercased()
        XCTAssertTrue(qt.contains("roofer") || qt.contains("roofing"))
        XCTAssertTrue(qt.contains("aurora"))

        XCTAssertTrue(query.softRegionTerms.contains("aurora"))

        XCTAssertTrue(query.timeTerms.contains("tomorrow"))
        let st = query.semanticText?.lowercased() ?? ""
        XCTAssertTrue(st.contains("tomorrow"))

        XCTAssertFalse(aggregatedRetrievalTexts(query).lowercased().contains(fullUser.lowercased()))
    }

    func test_canonical_vcSeedStartups_noRegionWhenNone_noRawLexicalLeak() {
        let raw = "Help me find a VC interested in funding seed stage AI startups."
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: nil,
            transactionIntent: .inquire,
            places: [],
            broadRecallTokens: ["venture", "capital", "seed", "startup"],
            semanticConcepts: ["venture capital", "seed funding", "ai startups"],
            clarificationGaps: [],
            rawUserText: raw
        )
        let facets = ExchangeIntentFacets(
            searchIntent: si,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            primaryKeywords: [raw]
        )
        let query = builder.build(from: pollutedThread(fullUserObjective: raw, facets: facets))
        XCTAssertFalse(aggregatedRetrievalTexts(query).lowercased().contains(raw.lowercased()))
        XCTAssertTrue(query.softRegionTerms.isEmpty && query.resolvedPlaces.isEmpty, "No inferred region for VC-only query")
    }

    func test_canonical_skiBuddy_mountDestination_softTime_noRawSentenceInLexical() {
        let raw = "Find me a ski buddy who has time to go ski with me next Saturday to Mount St. Louis."
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: "ski buddy",
            transactionIntent: nil,
            places: [
                ExchangeIntentFacets.StructuredPlace(
                    normalizedText: "mount st louis",
                    aliases: ["Mount St. Louis"],
                    confidence: 0.85,
                    isHard: false
                )
            ],
            timeConstraints: [ExchangeIntentFacets.StructuredTimeConstraint(kind: .day, text: "next saturday")],
            broadRecallTokens: ["ski", "buddy"],
            semanticConcepts: ["skiing", "ski buddy"],
            clarificationGaps: [],
            rawUserText: raw
        )
        let facets = ExchangeIntentFacets(
            searchIntent: si,
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            primaryKeywords: [raw]
        )
        let query = builder.build(from: pollutedThread(fullUserObjective: raw, facets: facets))
        let agg = aggregatedRetrievalTexts(query).lowercased()
        XCTAssertFalse(agg.contains(raw.lowercased()))
        XCTAssertFalse(agg.contains("who can"))
        let st = (query.semanticText ?? "").lowercased()
        let tt = query.timeTerms.joined(separator: " ").lowercased()
        XCTAssertTrue(st.contains("saturday") || tt.contains("saturday"), "semanticText=\(query.semanticText ?? "nil") timeTerms=\(query.timeTerms)")
    }

    func test_legacy_whenSearchIntentNil_pipelineMatchesExistingFacetRails() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .providerSearch,
            surfacePreference: .capability,
            providerTerms: ["enterprise"],
            capabilityTerms: ["integration", "platform"]
        )

        let query = builder.build(from: makeStandardThread(facets: facets))

        XCTAssertEqual(Set(query.providerTerms), Set(["enterprise"]))
        XCTAssertEqual(Set(query.capabilityTerms), Set(["integration", "platform"]))
        XCTAssertNil(facets.searchIntent)
    }
}

private extension ExchangeRetrievalQueryBuilderCanonicalSearchIntentTests {
    func unwrapText(_ value: String?, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let wrapped = value, !wrapped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            XCTFail("Expected non-empty string", file: file, line: line)
            return ""
        }
        return wrapped
    }

    func aggregatedRetrievalTexts(_ query: ExchangeRetrievalQuery) -> String {
        [
            query.queryText ?? "",
            query.semanticText ?? "",
            query.providerTerms.joined(separator: " "),
            query.capabilityTerms.joined(separator: " "),
            query.keywords.joined(separator: " "),
            query.softRegionTerms.joined(separator: " "),
            query.commercialIntentTerms.joined(separator: " "),
            query.timeTerms.joined(separator: " ")
        ].joined(separator: " ")
    }

    func pollutedThread(
        fullUserObjective: String,
        facets: ExchangeIntentFacets
    ) -> ExchangeThread {
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: facets.queryIntentClass,
            surfacePreference: facets.surfacePreference,
            title: "fixture",
            objective: fullUserObjective,
            targetDescription: "fixture target"
        )

        let interpretation = ExchangeThread.InterpretationSnapshot(
            semanticTags: ["pollution"],
            discoveryKeywords: [fullUserObjective],
            targetTags: ["gta leak tag"]
        )

        return ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            interpretation: interpretation,
            state: .drafting
        )
    }

    func makeStandardThread(facets: ExchangeIntentFacets) -> ExchangeThread {
        ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: facets.queryIntentClass,
                surfacePreference: facets.surfacePreference,
                title: "Pipeline fixture",
                objective: "fixture objective for retrieval query builder pipeline tests"
            ),
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )
    }
}
