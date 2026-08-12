import XCTest
@testable import AnumCore

final class ExchangeSecondHalfLocationResolverTests: XCTestCase {

    private var goldenCoordinate: ExchangeCoordinate {
        ExchangeCoordinate(
            latitude: ExchangeH3GoldenVectors.latitudeDegrees,
            longitude: ExchangeH3GoldenVectors.longitudeDegrees
        )
    }

    private func resolvedNearMeFacets(
        locationText: String? = "me",
        hardRequirements: [ExchangeIntentFacets.Requirement] = [
            .init(key: "locationText", value: "me")
        ],
        softPreferences: [ExchangeIntentFacets.Requirement] = [
            .init(key: "location", value: "me")
        ]
    ) -> ExchangeIntentFacets {
        let anchor = ExchangeRequesterSpatialAnchorBuilder.makeCurrentDeviceAnchor(coordinate: goldenCoordinate)
        let spatial = anchor.spatial
        return ExchangeIntentFacets(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            locationText: locationText,
            locationRequirement: ExchangeLocationRequirement(
                kind: .nearMe,
                strictness: .preferred,
                spatial: spatial
            ),
            requesterSpatialAnchor: anchor,
            hardRequirements: hardRequirements,
            softPreferences: softPreferences
        )
    }


    private func auroraFacets(
        hardRequirements: [ExchangeIntentFacets.Requirement] = [
            .init(key: "locationText", value: "Aurora")
        ],
        softPreferences: [ExchangeIntentFacets.Requirement] = [
            .init(key: "location", value: "Aurora")
        ]
    ) -> ExchangeIntentFacets {
        ExchangeIntentFacets(
            searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
                places: [.init(normalizedText: "Aurora", aliases: [], confidence: 0.9, isHard: true)],
                extractionSource: .heuristicFallback
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            locationText: "Aurora",
            placeName: "Aurora",
            locationRequirement: ExchangeLocationRequirement(
                displayName: "Aurora",
                normalizedName: "aurora",
                kind: .namedPlace,
                strictness: .required
            ),
            regionTerms: ["aurora"],
            hardRequirements: hardRequirements,
            softPreferences: softPreferences
        )
    }

    func testResolvedNearMe_noRawLocationGaps() {
        let facets = resolvedNearMeFacets()
        let thread = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                surfacePreference: .offer,
                title: "Roofer near me",
                objective: "Find roofer near me"
            ),
            posture: ExchangePosture(privacy: .balanced),
            facets: facets,
            state: .searching(.init())
        )
        let output = ExchangeRequesterIntentGapReducer().reduce(
            input: .init(
                thread: thread,
                facets: facets,
                operatingMemory: ExchangeStructuredOperatingMemory()
            )
        )

        let missing = ExchangeRequesterIntentGapReducer.userFacingMissingLines(from: output.gaps)
        XCTAssertFalse(missing.contains { $0.lowercased().contains("locationtext: me") }, missing.description)
        XCTAssertFalse(missing.contains { $0.lowercased().contains("location: me") }, missing.description)

        let questions = output.gaps.compactMap(\.questionForProvider)
        XCTAssertFalse(
            questions.contains { $0.lowercased().contains("confirm this requirement: locationtext") },
            questions.description
        )

        let context = ExchangeAgencyContextBuilder.buildRequesterContext(
            userIntent: "Find roofer near me",
            operatingMemory: ExchangeStructuredOperatingMemory(),
            intentGaps: output.gaps,
            facets: facets
        )
        XCTAssertTrue(
            context.knownFacts.contains { $0.contains("Near your current area") },
            context.knownFacts.description
        )

        let needs = ExchangeRequesterDecisionNeedsEngine().evaluate(context: context)
        XCTAssertFalse(
            needs.missingDecisionFacts.contains { $0.lowercased().contains("locationtext: me") },
            needs.missingDecisionFacts.description
        )
        XCTAssertFalse(
            needs.recommendedQuestions.contains { $0.lowercased().contains("confirm this requirement") },
            needs.recommendedQuestions.description
        )
    }

    func testUnresolvedNearMe_oneCleanQuestion() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            locationRequirement: ExchangeLocationRequirement(
                kind: .nearMe,
                strictness: .requiresClarification
            )
        )
        let fact = ExchangeSecondHalfLocationResolver.resolve(facets: facets)
        XCTAssertTrue(fact.shouldAskClarification)
        XCTAssertEqual(fact.clarificationQuestion, "What city or area should I search in?")

        let thread = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                surfacePreference: .offer,
                title: "Roofer near me",
                objective: "Find roofer near me"
            ),
            posture: ExchangePosture(privacy: .balanced),
            facets: facets,
            state: .searching(.init())
        )
        let output = ExchangeRequesterIntentGapReducer().reduce(
            input: .init(thread: thread, facets: facets, operatingMemory: ExchangeStructuredOperatingMemory())
        )
        let searchGaps = output.gaps.filter { $0.label == "Search area" }
        XCTAssertEqual(searchGaps.count, 1)
        XCTAssertEqual(searchGaps.first?.requestedValue, "What city or area should I search in?")
        XCTAssertNil(searchGaps.first?.questionForProvider)
    }

    func testExplicitAurora_preservedOverCurrentDevice() {
        let anchor = ExchangeRequesterSpatialAnchorBuilder.makeCurrentDeviceAnchor(coordinate: goldenCoordinate)
        let facets = ExchangeIntentFacets(
            searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
                places: [.init(normalizedText: "Aurora", aliases: [], confidence: 0.9, isHard: true)],
                extractionSource: .heuristicFallback
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            placeName: "Aurora",
            locationRequirement: ExchangeLocationRequirement(
                displayName: "Aurora",
                normalizedName: "aurora",
                kind: .namedPlace,
                strictness: .required
            ),
            requesterSpatialAnchor: anchor
        )
        let fact = ExchangeSecondHalfLocationResolver.resolve(facets: facets)
        XCTAssertEqual(fact.source, ExchangeSecondHalfLocationFact.Source.explicitPlace)
        XCTAssertTrue(fact.isSatisfiedForCurrentStep)
        XCTAssertEqual(fact.userFacingLocationPhrase, "Search area: Aurora")

        let thread = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                surfacePreference: .offer,
                title: "Roofer in Aurora",
                objective: "Find roofer in Aurora"
            ),
            posture: ExchangePosture(privacy: .balanced),
            facets: facets,
            state: .searching(.init())
        )
        let output = ExchangeRequesterIntentGapReducer().reduce(
            input: .init(
                thread: thread,
                facets: facets,
                searchIntent: facets.searchIntent,
                operatingMemory: ExchangeStructuredOperatingMemory()
            )
        )
        XCTAssertTrue(
            output.gaps.contains { $0.kind == ExchangeRequesterIntentGap.Kind.region && $0.requestedValue == "Aurora" },
            output.gaps.map(\.requestedValue).description
        )
        XCTAssertNotEqual(
            ExchangeSecondHalfLocationResolver.resolve(facets: facets).source,
            ExchangeSecondHalfLocationFact.Source.currentDevice
        )
    }

    func testPrivacy_noRawSpatialInPhrases() {
        let facets = resolvedNearMeFacets()
        let fact = ExchangeSecondHalfLocationResolver.resolve(facets: facets)
        let blobs = [
            fact.userFacingLocationPhrase,
            fact.modelSafeLocationPhrase,
            fact.clarificationQuestion,
            fact.debugSummary
        ].compactMap { $0 }

        for blob in blobs {
            XCTAssertFalse(blob.contains(String(ExchangeH3GoldenVectors.latitudeDegrees)), blob)
            XCTAssertFalse(blob.contains(String(ExchangeH3GoldenVectors.longitudeDegrees)), blob)
            for cell in facets.requesterSpatialAnchor?.spatial?.h3Cells ?? [] {
                XCTAssertFalse(blob.contains(cell), blob)
            }
        }

        let grounding = ExchangeRequesterCompareGroundingSummary.render(
            originalRequesterMessage: "near me",
            searchIntent: nil,
            thread: nil,
            facets: facets
        ) ?? ""
        XCTAssertFalse(grounding.contains(String(ExchangeH3GoldenVectors.latitudeDegrees)))
        XCTAssertFalse(grounding.lowercased().contains("locationtext: me"))
    }

    func testSanitizerStripsPoisonedLocationRails() {
        let facets = resolvedNearMeFacets()
        let sanitized = ExchangeNearMeLexicalSanitizer.sanitizeFacets(facets)
        XCTAssertNil(sanitized.locationText)
        XCTAssertTrue(sanitized.hardRequirements.isEmpty)
        XCTAssertTrue(sanitized.softPreferences.isEmpty)
    }

    func testResolvedNearMe_noSurface_emitsProviderCoverageMissOnly() {
        let facets = resolvedNearMeFacets()
        let context = ExchangeAgencyContextBuilder.buildRequesterContext(
            userIntent: "Find a roofer near me",
            operatingMemory: ExchangeStructuredOperatingMemory(),
            opportunitySurfaceAnchor: .counterpartyNode,
            facets: facets
        )
        let needs = ExchangeRequesterDecisionNeedsEngine().evaluate(context: context)

        XCTAssertFalse(
            needs.missingDecisionFacts.contains {
                $0.lowercased().contains("location fit boundaries")
                    && $0.lowercased().contains("your requirement")
            },
            needs.missingDecisionFacts.description
        )
        XCTAssertTrue(
            needs.missingDecisionFacts.contains {
                $0.contains("Provider service coverage is not anchored yet")
            },
            needs.missingDecisionFacts.description
        )
        XCTAssertFalse(
            needs.missingDecisionFacts.contains { $0.lowercased().contains("locationtext: me") },
            needs.missingDecisionFacts.description
        )
    }

    func testUnresolvedNearMe_noMisleadingLocationFitBoundaryTemplate() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            locationRequirement: ExchangeLocationRequirement(
                kind: .nearMe,
                strictness: .requiresClarification
            )
        )
        let context = ExchangeAgencyContextBuilder.buildRequesterContext(
            userIntent: "Find a roofer near me",
            operatingMemory: ExchangeStructuredOperatingMemory(),
            opportunitySurfaceAnchor: .counterpartyNode,
            intentGaps: [
                ExchangeRequesterIntentGap(
                    stableKey: "region|search-area-needed",
                    kind: .region,
                    status: .unknown,
                    label: "Search area",
                    requestedValue: "What city or area should I search in?",
                    questionForProvider: nil,
                    priority: 0,
                    source: "secondHalfLocation"
                )
            ],
            facets: facets
        )
        let needs = ExchangeRequesterDecisionNeedsEngine().evaluate(context: context)

        XCTAssertFalse(
            needs.missingDecisionFacts.contains { $0.lowercased().contains("location fit boundaries") },
            needs.missingDecisionFacts.description
        )
        XCTAssertTrue(
            needs.recommendedQuestions.contains { $0.contains("What city or area should I search in?") },
            needs.recommendedQuestions.description
        )
    }

    func testExplicitAurora_noDeviceOverrideInOpportunityQualification() {
        let anchor = ExchangeRequesterSpatialAnchorBuilder.makeCurrentDeviceAnchor(coordinate: goldenCoordinate)
        let facets = ExchangeIntentFacets(
            searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
                places: [.init(normalizedText: "Aurora", aliases: [], confidence: 0.9, isHard: true)],
                extractionSource: .heuristicFallback
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            placeName: "Aurora",
            locationRequirement: ExchangeLocationRequirement(
                displayName: "Aurora",
                normalizedName: "aurora",
                kind: .namedPlace,
                strictness: .required
            ),
            requesterSpatialAnchor: anchor
        )
        let context = ExchangeAgencyContextBuilder.buildRequesterContext(
            userIntent: "Find a roofer in Aurora",
            operatingMemory: ExchangeStructuredOperatingMemory(),
            opportunitySurfaceAnchor: .counterpartyNode,
            facets: facets
        )
        let fact = ExchangeSecondHalfLocationResolver.resolve(facets: facets)
        XCTAssertEqual(fact.source, ExchangeSecondHalfLocationFact.Source.explicitPlace)
        XCTAssertEqual(fact.userFacingLocationPhrase, "Search area: Aurora")

        let needs = ExchangeRequesterDecisionNeedsEngine().evaluate(context: context)
        XCTAssertFalse(
            needs.missingDecisionFacts.contains {
                $0.lowercased().contains("location fit boundaries")
                    && $0.lowercased().contains("your requirement")
            },
            needs.missingDecisionFacts.description
        )
        XCTAssertTrue(
            context.knownFacts.contains { $0.contains("Search area: Aurora") },
            context.knownFacts.description
        )
    }

    func testExplicitAurora_noProviderSurface_noRequesterLocationIntentGaps() {
        let facets = auroraFacets()
        let thread = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                surfacePreference: .offer,
                title: "Find a roofer in Aurora",
                objective: "Find a roofer in Aurora"
            ),
            posture: ExchangePosture(privacy: .balanced),
            facets: facets,
            state: .searching(.init(querySummary: "roofer aurora"))
        )

        let output = ExchangeRequesterIntentGapReducer().reduce(
            input: .init(
                thread: thread,
                facets: facets,
                searchIntent: facets.searchIntent,
                operatingMemory: ExchangeStructuredOperatingMemory()
            )
        )

        let missing = ExchangeRequesterIntentGapReducer.userFacingMissingLines(
            from: output.gaps,
            locationFact: ExchangeSecondHalfLocationResolver.resolve(facets: facets)
        )
        XCTAssertFalse(
            missing.contains { $0.lowercased().contains("locationtext: aurora") },
            missing.description
        )
        XCTAssertFalse(
            missing.contains { $0.lowercased().contains("location: aurora") },
            missing.description
        )
        XCTAssertFalse(
            missing.contains { $0.lowercased().contains("place / region") },
            missing.description
        )
        XCTAssertNil(output.combinedProviderQuestion)

        let context = ExchangeAgencyContextBuilder.buildRequesterContext(
            userIntent: "Find a roofer in Aurora",
            operatingMemory: ExchangeStructuredOperatingMemory(),
            opportunitySurfaceAnchor: .counterpartyNode,
            intentGaps: output.gaps,
            facets: facets
        )
        let needs = ExchangeRequesterDecisionNeedsEngine().evaluate(context: context)
        XCTAssertTrue(
            needs.missingDecisionFacts.contains {
                $0.contains("Provider service coverage is not anchored yet")
            },
            needs.missingDecisionFacts.description
        )
        XCTAssertFalse(
            needs.recommendedQuestions.contains {
                ExchangeSecondHalfLocationResolver.isProviderServeLocationQuestion($0)
            },
            needs.recommendedQuestions.description
        )
    }

    func testExplicitAurora_matchedProvider_noRequesterLocationMissingFacts() throws {
        let facets = auroraFacets()
        let thread = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                surfacePreference: .offer,
                title: "Find a roofer in Aurora",
                objective: "Find a roofer in Aurora"
            ),
            posture: ExchangePosture(privacy: .balanced),
            facets: facets,
            state: .matchFound(.init(candidateCount: 1, summary: "Match selected", selectedCounterpartyID: "cp-1"))
        )
        let offer = ExchangeOffer(
            id: "offer-1",
            nodeID: "node-1",
            title: "Roofer",
            summary: "General roofing services.",
            category: "roofing",
            tags: ["roofer"],
            regionTags: []
        )

        let output = ExchangeRequesterIntentGapReducer().reduce(
            input: .init(
                thread: thread,
                facets: facets,
                searchIntent: facets.searchIntent,
                offer: offer,
                operatingMemory: ExchangeStructuredOperatingMemory()
            )
        )

        let missing = ExchangeRequesterIntentGapReducer.userFacingMissingLines(
            from: output.gaps,
            locationFact: ExchangeSecondHalfLocationResolver.resolve(facets: facets)
        )
        XCTAssertFalse(
            missing.contains { $0.lowercased().contains("place / region · unknown") },
            missing.description
        )
        XCTAssertFalse(
            missing.contains { $0.lowercased().contains("locationtext: aurora") },
            missing.description
        )
}
}
