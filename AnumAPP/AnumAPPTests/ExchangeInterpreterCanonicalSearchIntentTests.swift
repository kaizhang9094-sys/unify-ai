import XCTest
@testable import AnumCore

final class ExchangeInterpreterCanonicalSearchIntentTests: XCTestCase {
    private let fusedPhrase = "gta, and seller offers vendor take back mortgage"
    private let gtaVtbQuery = "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."
    private lazy var discoveryEngine = ExchangeDiscoveryEngine()

    func test_canonicalIntent_realEstate_vtbQuery_compilesAtomicLegacyRails() async {
        let interpreted = await interpret(gtaVtbQuery)

        let canonical = tryUnwrapCanonical(interpreted)
        XCTAssertEqual(canonical.domainCategory, .realEstate)
        XCTAssertEqual(canonical.objectType, "house")
        XCTAssertEqual(canonical.transactionIntent, .forSale)
        XCTAssertTrue(canonical.places.contains(where: { $0.normalizedText == "gta" }))
        XCTAssertTrue(canonical.attributes.contains(where: { $0.key == "bedrooms" && $0.numericValue == 3 }))
        XCTAssertTrue(canonical.commercialConstraints.contains(where: { $0.kind == .financing }))

        XCTAssertTrue(interpreted.facets.regionTerms.contains("gta"))
        XCTAssertEqual(interpreted.facets.locationText?.lowercased(), "gta")
        XCTAssertEqual(interpreted.facets.placeName?.lowercased(), "gta")
        XCTAssertFalse(tryUnwrapCanonical(interpreted).places.contains(where: { $0.isHard }), "Default locale extractions are soft unless must/only/exact wording")
        XCTAssertNoFusedPhrase(interpreted)
    }

    func test_canonicalLeakCleanup_gtaVtb_noRawSentenceInDiscoveryOrPrimaryOrCoarseTokens() async {
        let interpreted = await interpret(gtaVtbQuery)
        let fullLower = gtaVtbQuery.lowercased()

        for list in [interpreted.discoveryKeywords, interpreted.facets.primaryKeywords] {
            for item in list {
                let low = item.lowercased()
                XCTAssertFalse(low == fullLower, "Raw full sentence must not appear as a single rail: \(item)")
                XCTAssertFalse(low.contains(fusedPhrase), item)
            }
        }

        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread(from: interpreted, rawText: gtaVtbQuery))
        XCTAssertTrue(plan.usesCanonicalDirectoryRecall)
        let coarse = discoveryEngine.retrievalIntentTokens(for: plan)
        let aggregate = coarse.sorted().joined(separator: " ")
        XCTAssertFalse(aggregate.localizedCaseInsensitiveContains(fusedPhrase), "coarse tokens: \(aggregate)")
        XCTAssertFalse(aggregate.replacingOccurrences(of: " ", with: "").contains(fullLower.replacingOccurrences(of: " ", with: "")), "coarse aggregate")
    }

    func test_canonicalIntent_rooferAuroraTomorrow_compilesProviderAndRegionRails() async {
        let raw = "Find a roofer near Aurora who can come tomorrow."
        let interpreted = await interpret(raw)

        let canonical = tryUnwrapCanonical(interpreted)
        XCTAssertEqual(canonical.domainCategory, .homeService)
        XCTAssertEqual(canonical.objectType, "roofer")
        XCTAssertTrue(canonical.places.contains(where: { $0.normalizedText == "aurora" }))
        XCTAssertTrue(canonical.timeConstraints.contains(where: { $0.text == "tomorrow" }))

        XCTAssertTrue(interpreted.facets.providerTerms.contains("roofer"))
        XCTAssertTrue(interpreted.facets.regionTerms.contains("aurora"))
        XCTAssertNoFusedPhrase(interpreted)

        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread(from: interpreted, rawText: raw))
        let coarse = discoveryEngine.retrievalIntentTokens(for: plan)
        let blob = coarse.sorted().joined(separator: " ").lowercased()
        XCTAssertFalse(blob.contains(raw.lowercased()), "coarse tokens leaked raw sentence: \(blob)")
    }

    func test_canonicalIntent_commercialRoboticsToronto_compilesConceptsAndLocation() async {
        let interpreted = await interpret("Find someone in Toronto with experience in commercial robotics.")

        let canonical = tryUnwrapCanonical(interpreted)
        XCTAssertEqual(canonical.domainCategory, .professionalService)
        XCTAssertTrue(canonical.semanticConcepts.contains("commercial robotics"))
        XCTAssertTrue(canonical.places.contains(where: { $0.normalizedText == "toronto" }))

        XCTAssertEqual(interpreted.facets.locationText?.lowercased(), "toronto")
        XCTAssertTrue(interpreted.semanticTags.contains("commercial robotics"))
        XCTAssertNoFusedPhrase(interpreted)
    }

    func test_legacySearchPlan_retrievalIntentTokens_stillUsesFacetRailsWhenNotCanonical() {
        let objective = "enterprise integration platform urgent long sentence blob"
        let facets = ExchangeIntentFacets(
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            regionTerms: ["toronto"],
            primaryKeywords: ["enterprise", "integration"]
        )
        XCTAssertNil(facets.searchIntent)

        let thread = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .providerSearch,
                surfacePreference: .offer,
                title: "t",
                objective: objective
            ),
            posture: ExchangePosture(),
            facets: facets,
            interpretation: ExchangeThread.InterpretationSnapshot(
                semanticTags: ["saas"],
                discoveryKeywords: ["integration"],
                targetTags: ["provider"]
            ),
            state: .drafting
        )

        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)
        XCTAssertFalse(plan.usesCanonicalDirectoryRecall)
        let tokens = discoveryEngine.retrievalIntentTokens(for: plan)
        XCTAssertTrue(tokens.contains("integration") || tokens.contains("enterprise"), "\(tokens)")
        XCTAssertTrue(tokens.contains("saas") || tokens.contains("provider"), "\(tokens)")
    }

    func test_canonicalIntent_houseGTAWithSellerFinancing_hasFinancingConstraint() async {
        let interpreted = await interpret("Looking for a house in GTA with seller financing.")

        let canonical = tryUnwrapCanonical(interpreted)
        XCTAssertEqual(canonical.domainCategory, .realEstate)
        XCTAssertEqual(canonical.objectType, "house")
        XCTAssertTrue(canonical.places.contains(where: { $0.normalizedText == "gta" }))
        XCTAssertTrue(canonical.commercialConstraints.contains(where: { $0.kind == .financing }))

        XCTAssertTrue(interpreted.targetTags.contains("house"))
        XCTAssertTrue(interpreted.semanticTags.contains("seller financing"))
        XCTAssertNoFusedPhrase(interpreted)
    }

    func test_canonicalIntent_vcSeedAI_hasSearchIntent_noRawSentenceRails() async {
        let raw = "Help me find a VC interested in funding seed stage AI startups."
        let interpreted = await interpret(raw)
        guard interpreted.facets.searchIntent != nil else {
            XCTFail("Expected searchIntent for VC query under fallback classification")
            return
        }
        XCTAssertNoCommaAndFusedPollution(interpreted, raw: raw)
        XCTAssertNoFusedPhrase(interpreted)
        XCTAssertFalse(interpreted.discoveryKeywords.contains { $0.caseInsensitiveCompare(raw) == .orderedSame })
    }

    func test_canonicalIntent_skiBuddy_mountStLouis_timeAndPlace_noRawRails() async {
        let raw = "Find me a ski buddy who has time to go ski with me next Saturday to Mount St. Louis."
        let interpreted = await interpret(raw)
        guard let si = interpreted.facets.searchIntent else {
            XCTFail("Expected searchIntent")
            return
        }
        let rawCanon = si.rawUserText.lowercased()
        XCTAssertTrue(rawCanon.contains("mount st"), "Destination should remain in canonical rawUserText")
        XCTAssertNoCommaAndFusedPollution(interpreted, raw: raw)
        XCTAssertNoFusedPhrase(interpreted)
    }

    func test_canonicalIntent_datingQuery_hasSearchIntent_noFusedLeak() async {
        let raw = "Find me a single woman looking to date who likes dogs."
        let interpreted = await interpret(raw)
        guard interpreted.facets.searchIntent != nil else {
            XCTFail("Expected searchIntent for social/discovery query")
            return
        }
        XCTAssertNoCommaAndFusedPollution(interpreted, raw: raw)
        XCTAssertNoFusedPhrase(interpreted)
    }

    func test_canonicalIntent_houseGTASellerFinancing_interpreted_actionableShape() async throws {
        let raw = "Looking for a house in GTA with seller financing."
        let interpreted = await interpret(raw)
        let si = try XCTUnwrap(interpreted.facets.searchIntent)

        XCTAssertEqual(si.domainCategory, .realEstate)
        XCTAssertEqual(si.objectType, "house")
        XCTAssertTrue(si.places.contains { $0.normalizedText == "gta" })
        let fin = si.commercialConstraints.first { $0.kind == .financing }
        XCTAssertNotNil(fin)
        XCTAssertFalse(fin?.isHard ?? true)

        let financingBlob = (si.commercialConstraints.map(\.value) + si.semanticConcepts).joined(separator: " ").lowercased()
        XCTAssertTrue(
            financingBlob.contains("seller financing") || financingBlob.contains("owner") || financingBlob.contains("vendor"),
            financingBlob
        )
    }

    func test_ambiguous_helpMeFindSomething_stillNeedsClarification() async {
        let result = await interpretResult("help me find something")
        guard case .needsClarification = result else {
            XCTFail("Expected clarification for ambiguous generic ask")
            return
        }
    }

    func test_ambiguous_lookingForSomeone_stillNeedsClarification() async {
        let result = await interpretResult("looking for someone")
        guard case .needsClarification = result else {
            XCTFail("Expected clarification when discovery anchor is too thin")
            return
        }
    }
}

private extension ExchangeInterpreterCanonicalSearchIntentTests {
    func interpret(_ text: String) async -> ExchangeInterpreter.InterpretedRequest {
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: ExchangeFallbackIntelligenceProvider()
        )

        let result = await interpreter.interpret(userText: text, threadContext: nil)
        guard case .interpreted(let interpreted) = result else {
            XCTFail("Expected interpreted result for canonical search test")
            return ExchangeInterpreter.InterpretedRequest(
                intent: ExchangeIntent(kind: .find, mode: .transactional, title: "fallback", objective: text),
                posture: ExchangePosture(),
                facets: ExchangeIntentFacets()
            )
        }

        return interpreted
    }

    func interpretResult(_ text: String) async -> ExchangeInterpreter.InterpretationResult {
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: ExchangeFallbackIntelligenceProvider()
        )
        return await interpreter.interpret(userText: text, threadContext: nil)
    }

    func tryUnwrapCanonical(
        _ interpreted: ExchangeInterpreter.InterpretedRequest
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        guard let canonical = interpreted.facets.searchIntent else {
            XCTFail("Expected canonical search intent in facets")
            return .init(rawUserText: interpreted.intent.objective)
        }
        return canonical
    }

    func XCTAssertNoFusedPhrase(
        _ interpreted: ExchangeInterpreter.InterpretedRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let allFields = (
            interpreted.semanticTags +
            interpreted.discoveryKeywords +
            interpreted.targetTags +
            interpreted.facets.regionTerms +
            interpreted.facets.primaryKeywords +
            interpreted.facets.secondaryKeywords +
            interpreted.facets.providerTerms +
            interpreted.facets.capabilityTerms +
            [interpreted.intent.targetDescription, interpreted.facets.locationText, interpreted.facets.placeName].compactMap { $0 }
        ).map { $0.lowercased() }

        XCTAssertFalse(
            allFields.contains { $0.contains(fusedPhrase) },
            "Fused phrase leaked into legacy or canonical rails",
            file: file,
            line: line
        )
    }

    func XCTAssertNoCommaAndFusedPollution(
        _ interpreted: ExchangeInterpreter.InterpretedRequest,
        raw: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rawLower = raw.lowercased()
        let fields = (
            interpreted.semanticTags +
            interpreted.discoveryKeywords +
            interpreted.targetTags +
            interpreted.facets.primaryKeywords +
            interpreted.facets.secondaryKeywords
        )
        for f in fields {
            let low = f.lowercased()
            XCTAssertFalse(low.contains(", and"), "comma-and in rail: \(f)", file: file, line: line)
            XCTAssertFalse(low == rawLower, "full raw sentence as single rail: \(f.prefix(80))", file: file, line: line)
        }
    }

    func thread(from interpreted: ExchangeInterpreter.InterpretedRequest, rawText: String) -> ExchangeThread {
        ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: interpreted.intent.kind,
                mode: interpreted.intent.mode,
                queryIntentClass: interpreted.facets.queryIntentClass,
                surfacePreference: interpreted.facets.surfacePreference,
                title: interpreted.intent.title,
                objective: rawText,
                targetDescription: interpreted.intent.targetDescription
            ),
            posture: interpreted.posture,
            facets: interpreted.facets,
            interpretation: ExchangeThread.InterpretationSnapshot(
                semanticTags: interpreted.semanticTags,
                discoveryKeywords: interpreted.discoveryKeywords,
                targetTags: interpreted.targetTags,
                userSummary: interpreted.userSummary,
                userQuestion: interpreted.userQuestion
            ),
            state: .drafting
        )
    }
}
