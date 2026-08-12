import XCTest
@testable import AnumCore

/// Phase 5: canonical `facets.searchIntent` drives fit hard/soft split and avoids fused raw objective as evidence.
final class ExchangeFitEngineCanonicalSearchIntentTests: XCTestCase {
    private let engine = ExchangeFitEngine()

    // MARK: - GTA + VTB (soft bedrooms / financing)

    func test_canonical_GTAVTB_softGapsProduceCautionsNotWeakFit() {
        let fusedLeak = "gta, and seller offers vendor take back mortgage"
        let raw = "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."

        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .realEstate,
            objectType: "house",
            transactionIntent: .forSale,
            places: [
                ExchangeIntentFacets.StructuredPlace(
                    normalizedText: "gta",
                    aliases: [],
                    confidence: 0.93,
                    isHard: false
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
            broadRecallTokens: ["house", "gta"],
            semanticConcepts: ["house", "seller financing"],
            clarificationGaps: [],
            rawUserText: raw
        )

        let facets = ExchangeIntentFacets(
            searchIntent: si,
            fulfillmentMode: .unknown,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            providerTerms: [raw],
            primaryKeywords: [raw, fusedLeak]
        )

        let thread = makeThread(fullObjective: raw, facets: facets)
        let profile = fixtureProfile(
            headline: "Detached home for sale",
            summary: "Beautiful detached home Greater Toronto Area. MLS listing. Open house weekend.",
            regionTags: ["GTA"],
            activityTags: ["real estate listing"]
        )
        let cp = fixtureCounterparty(
            idSuffix: "gta-home",
            publicProfile: profile,
            headlineText: profile.headline
        )
        let candidate = fixtureCandidate(counterparty: cp, profile: profile, retrievalScore: 0.82, surface: .offer)

        let match = engine.evaluate(thread: thread, candidates: [candidate]).first!

        XCTAssertGreaterThanOrEqual(match.score, 0.52, "Soft bedroom/financing gaps must not collapse fit.")
        XCTAssertNotEqual(match.strength, ExchangeMatch.Strength.weak, "GTA listing candidate should remain at least moderate when core intent matches.")

        let cautionText = match.cautions.map { $0.summary }.joined(separator: " ").lowercased()
        XCTAssertTrue(cautionText.contains("bedroom") || cautionText.contains("seller financing"), "\(match.cautions)")

        let leakBlob = aggregatedFitNarratives(match).lowercased()
        XCTAssertFalse(leakBlob.contains(fusedLeak.lowercased()))

        XCTAssertTrue(hasSpecializationWithoutFusedLeak(match), match.reasons.map { $0.summary }.joined(separator: " | "))
    }

    func test_canonical_hardFinancing_missIsPunitiveVersusSoft_financing() {
        let baseSI = fixtureSearchIntentMinimalRealEstate()
        var soft = baseSI
        soft.commercialConstraints = [
            .init(kind: .financing, key: "fin", value: "seller financing", isHard: false)
        ]
        let hardVariant = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: soft.domainCategory,
            objectType: soft.objectType,
            transactionIntent: soft.transactionIntent,
            places: soft.places,
            attributes: soft.attributes,
            preferences: soft.preferences,
            timeConstraints: soft.timeConstraints,
            commercialConstraints: [
                .init(kind: .financing, key: "fin", value: "seller financing", isHard: true)
            ],
            broadRecallTokens: soft.broadRecallTokens,
            semanticConcepts: soft.semanticConcepts,
            hardConstraints: soft.hardConstraints,
            softPreferences: soft.softPreferences,
            clarificationGaps: soft.clarificationGaps,
            rawUserText: soft.rawUserText
        )

        let profile = fixtureProfile(
            headline: "Suburban townhouse",
            summary: "Quiet neighborhood home for sale Ottawa region.",
            regionTags: ["Ottawa"]
        )

        func match(for si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent) -> ExchangeMatch {
            let facets = ExchangeIntentFacets(searchIntent: si, queryIntentClass: .offerSearch, surfacePreference: .offer)
            let thread = makeThread(fullObjective: "polluted fused objective blob", facets: facets)
            let cp = fixtureCounterparty(idSuffix: "fin-ex", publicProfile: profile)
            let candidate = fixtureCandidate(counterparty: cp, profile: profile, retrievalScore: 0.78, surface: .offer)
            return engine.evaluate(thread: thread, candidates: [candidate]).first!
        }

        let softM = match(for: soft)
        let hardM = match(for: hardVariant)

        XCTAssertGreaterThan(
            softM.score + 1e-9,
            hardM.score,
            "Soft financing miss should remain strictly ahead of hard financing miss on identical weak evidence."
        )
    }

    // MARK: - Roofer / Aurora / tomorrow (soft timing)

    func test_canonical_rooferAuroraTomorrow_timingSoftUncertainty() {
        let raw = "Find a roofer near Aurora who can come tomorrow."

        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "roofer",
            transactionIntent: .hire,
            places: [
                ExchangeIntentFacets.StructuredPlace(
                    normalizedText: "aurora",
                    aliases: [],
                    confidence: 0.92,
                    isHard: false
                )
            ],
            attributes: [],
            preferences: [],
            timeConstraints: [ExchangeIntentFacets.StructuredTimeConstraint(kind: .day, text: "tomorrow")],
            commercialConstraints: [],
            broadRecallTokens: ["roofer", "aurora"],
            semanticConcepts: ["roofing contractor"],
            clarificationGaps: [],
            rawUserText: raw
        )

        let facets = ExchangeIntentFacets(
            searchIntent: si,
            fulfillmentMode: .localPreferred,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            primaryKeywords: [raw]
        )

        let thread = makeThread(fullObjective: raw, facets: facets)
        let profile = fixtureProfile(
            headline: "Roof repair and replacement specialist",
            summary: "Serving Aurora and York Region. Residential shingle roofing.",
            regionTags: ["Aurora", "ON"]
        )

        let cp = fixtureCounterparty(
            idSuffix: "roof-aurora",
            publicProfile: profile,
            location: ExchangeCounterparty.Location(city: "Aurora", region: "ON")
        )

        let candidate = fixtureCandidate(
            counterparty: cp,
            profile: profile,
            retrievalScore: 0.82,
            surface: .capability
        )

        let match = engine.evaluate(thread: thread, candidates: [candidate]).first!

        XCTAssertGreaterThanOrEqual(match.score, 0.58)

        let reasonJoined = match.reasons.map { $0.summary }.joined(separator: " ").lowercased()
        XCTAssertTrue(
            reasonJoined.contains("service") ||
                reasonJoined.contains("roof") ||
                reasonJoined.contains("canonical") ||
                reasonJoined.contains("location"),
            "\(match.reasons.map { $0.summary })"
        )

        XCTAssertTrue(match.cautions.contains { $0.summary.lowercased().contains("timing") || $0.summary.lowercased().contains("availability") })

        XCTAssertFalse(aggregatedFitNarratives(match).lowercased().contains(raw.lowercased()))
    }

    // MARK: - Semantic synonyms (roofing vs repair wording)

    func test_canonical_semanticSynonym_boostsOverlappingEvidence() {
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "roofing contractor",
            transactionIntent: .hire,
            places: [],
            semanticConcepts: ["roofing contractor"],
            clarificationGaps: [],
            rawUserText: ""
        )

        let facets = ExchangeIntentFacets(
            searchIntent: si,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer
        )
        let thread = makeThread(fullObjective: "", facets: facets)

        let weakroof = evaluateMatch(
            thread: thread,
            summary: "Residential electrical panel upgrades.",
            headline: "Licensed electrician — panel swaps"
        )
        let weakScore = weakroof.score

        let strongroof = evaluateMatch(
            thread: thread,
            summary: "Roof repair and replacement specialists. Full tear-offs.",
            headline: "GAF-certified roof repair Aurora"
        )

        XCTAssertGreaterThan(strongroof.score, weakScore + 0.04)
        XCTAssertGreaterThan(conceptOverlapReasonCount(strongroof), 0)
    }

    func test_canonical_ownerFinancingSynonym_upliftsVersusPlainListing() {
        let raw = "GTA home for sale with seller financing preference"
        var si = gtaVtbSearchIntentFixture(raw: raw)
        let facets = ExchangeIntentFacets(searchIntent: si, queryIntentClass: .offerSearch, surfacePreference: .offer)
        let thread = makeThread(fullObjective: raw, facets: facets)

        let plain = fixtureProfile(
            headline: "Detached for sale",
            summary: "GTA MLS listing. Open house.",
            regionTags: ["GTA"]
        )
        let withOwnerFin = fixtureProfile(
            headline: "Detached for sale",
            summary: "GTA MLS listing. Owner financing available. Creative financing considered.",
            regionTags: ["GTA"]
        )

        let cp1 = fixtureCounterparty(idSuffix: "a", publicProfile: plain)
        let cp2 = fixtureCounterparty(idSuffix: "b", publicProfile: withOwnerFin)
        let m1 = engine.evaluate(thread: thread, candidates: [fixtureCandidate(counterparty: cp1, profile: plain, retrievalScore: 0.8, surface: .offer)]).first!
        let m2 = engine.evaluate(thread: thread, candidates: [fixtureCandidate(counterparty: cp2, profile: withOwnerFin, retrievalScore: 0.8, surface: .offer)]).first!

        XCTAssertGreaterThan(m2.score, m1.score)
        XCTAssertGreaterThan(m2.score - m1.score, 0.005, "Owner-financing wording should lift versus plain listing when financing is a soft intent signal.")
    }

    func test_canonical_requiredFinancingPreference_penalizesMissingEvidence() {
        let raw = "fixture financing required"
        let base = gtaVtbSearchIntentFixture(raw: raw)

        var softIntent = base
        softIntent.preferences = []

        let requiredIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: base.domainCategory,
            objectType: base.objectType,
            transactionIntent: base.transactionIntent,
            places: base.places,
            attributes: base.attributes,
            preferences: [
                ExchangeIntentFacets.StructuredPreference(key: "financing", value: "seller financing", strength: .required)
            ],
            timeConstraints: base.timeConstraints,
            commercialConstraints: [],
            broadRecallTokens: base.broadRecallTokens,
            semanticConcepts: base.semanticConcepts,
            hardConstraints: base.hardConstraints,
            softPreferences: base.softPreferences,
            clarificationGaps: base.clarificationGaps,
            rawUserText: raw
        )

        let profile = fixtureProfile(
            headline: "House for sale",
            summary: "GTA residential. No financing wording.",
            regionTags: ["GTA"]
        )
        let cp = fixtureCounterparty(idSuffix: "req", publicProfile: profile)
        let candidate = fixtureCandidate(counterparty: cp, profile: profile, retrievalScore: 0.78, surface: .offer)

        func score(for si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent) -> Double {
            let facets = ExchangeIntentFacets(searchIntent: si, queryIntentClass: .offerSearch, surfacePreference: .offer)
            let thread = makeThread(fullObjective: raw, facets: facets)
            return engine.evaluate(thread: thread, candidates: [candidate]).first!.score
        }

        let softMissing = score(for: softIntent)
        let hardMissing = score(for: requiredIntent)

        XCTAssertLessThan(hardMissing, softMissing)
        XCTAssertGreaterThan(softMissing - hardMissing, 0.005, "Required financing should penalize missing evidence more than soft financing.")
    }

    private func gtaVtbSearchIntentFixture(raw: String) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .realEstate,
            objectType: "house",
            transactionIntent: .forSale,
            places: [
                ExchangeIntentFacets.StructuredPlace(normalizedText: "gta", aliases: [], confidence: 0.9, isHard: false)
            ],
            attributes: [ExchangeIntentFacets.StructuredAttribute(key: "bedrooms", value: "3 bedroom", numericValue: 3)],
            commercialConstraints: [
                .init(kind: .financing, key: "sellerFinancing", value: "seller financing", isHard: false)
            ],
            broadRecallTokens: ["house", "gta"],
            semanticConcepts: ["house", "seller financing"],
            clarificationGaps: [],
            rawUserText: raw
        )
    }

    // MARK: - Legacy regression

    func test_legacy_objectiveFeedsTokens_whenSearchIntentNil() {
        let token = "legacyonlytoken_xy42"
        let objective = "I need \(token) plumber help asap"

        let facets = ExchangeIntentFacets(
            fulfillmentMode: .unknown,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            primaryKeywords: [objective]
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
            state: .drafting
        )

        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "plumber",
            transactionIntent: .hire,
            places: [],
            semanticConcepts: ["plumbing service"],
            clarificationGaps: [],
            rawUserText: objective
        )
        let canonFacets = ExchangeIntentFacets(
            searchIntent: si,
            fulfillmentMode: .unknown,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer
        )
        let canonThread = makeThread(fullObjective: objective, facets: canonFacets)

        let profile = fixtureProfile(headline: "\(token) certified master plumber", summary: "")
        let cp = fixtureCounterparty(idSuffix: "plumb", publicProfile: profile)
        let candidate = fixtureCandidate(counterparty: cp, profile: profile, retrievalScore: 0.7, surface: .capability)

        let legacy = engine.evaluate(thread: thread, candidates: [candidate]).first!
        let canonical = engine.evaluate(thread: canonThread, candidates: [candidate]).first!

        XCTAssertGreaterThan(legacy.score, canonical.score + 0.02)
    }

    // MARK: - Fixtures

    private func evaluateMatch(
        thread: ExchangeThread,
        summary: String,
        headline: String
    ) -> ExchangeMatch {
        let profile = fixtureProfile(headline: headline, summary: summary, regionTags: [])
        let cp = fixtureCounterparty(idSuffix: UUID().uuidString, publicProfile: profile)
        let candidate = fixtureCandidate(counterparty: cp, profile: profile, retrievalScore: 0.75, surface: .capability)
        return engine.evaluate(thread: thread, candidates: [candidate]).first!
    }

    private func conceptOverlapReasonCount(_ match: ExchangeMatch) -> Int {
        match.reasons.filter { r in
            let s = r.summary.lowercased()
            return s.contains("theme") || s.contains("canonical") || s.contains("specialization")
        }.count
    }

    private func fixtureSearchIntentMinimalRealEstate() -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .realEstate,
            objectType: "house",
            transactionIntent: .forSale,
            places: [
                ExchangeIntentFacets.StructuredPlace(
                    normalizedText: "ottawa",
                    aliases: [],
                    confidence: 0.8,
                    isHard: false
                )
            ],
            broadRecallTokens: ["house"],
            semanticConcepts: ["residential listing"],
            clarificationGaps: [],
            rawUserText: ""
        )
    }

    private func makeThread(fullObjective: String, facets: ExchangeIntentFacets) -> ExchangeThread {
        ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: facets.queryIntentClass,
                surfacePreference: facets.surfacePreference,
                title: "fit fixture",
                objective: fullObjective
            ),
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )
    }

    private func fixtureProfile(
        headline: String?,
        summary: String?,
        regionTags: [String] = [],
        activityTags: [String] = []
    ) -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: "pub-\(UUID().uuidString.prefix(8))",
            nodeID: "node-\(UUID().uuidString.prefix(8))",
            displayName: "Fixture Vendor",
            headline: headline,
            summary: summary,
            activityTags: activityTags,
            regionTags: regionTags
        )
    }

    private func fixtureCounterparty(
        idSuffix: String,
        publicProfile: ExchangePublicNodeProfile?,
        headlineText: String? = nil,
        location: ExchangeCounterparty.Location? = nil
    ) -> ExchangeCounterparty {
        var semantic = ExchangeCounterparty.SemanticProfile.empty
        if let headlineText {
            semantic.notes = headlineText
        }
        return ExchangeCounterparty(
            id: "cp-\(idSuffix)",
            kind: .provider,
            displayName: publicProfile?.displayName ?? "Fixture CP",
            source: .localDirectory,
            publicProfile: publicProfile,
            location: location,
            semantic: semantic,
            trust: ExchangeCounterparty.TrustSnapshot(level: .moderate),
            status: .active
        )
    }

    private func fixtureCandidate(
        counterparty: ExchangeCounterparty,
        profile: ExchangePublicNodeProfile?,
        retrievalScore: Double,
        surface: ExchangeDiscoveryEngine.DiscoveryCandidate.SurfaceType
    ) -> ExchangeDiscoveryEngine.DiscoveryCandidate {
        ExchangeDiscoveryEngine.DiscoveryCandidate(
            publicProfile: profile,
            counterparty: counterparty,
            matchedOffers: [],
            coarse: .init(
                queryTokenOverlap: 3,
                explicitTokenOverlap: 2,
                regionOverlap: 2,
                offerOverlap: 0,
                capabilityOverlap: 2,
                affinityOverlap: 0,
                hasPublicProfile: profile != nil,
                hasOffers: false,
                kindCompatible: true,
                placeCompatible: true,
                trustHintScore: 1,
                retrievalScore: retrievalScore,
                rationale: "fixture"
            ),
            posture: .init(
                bucket: .contactable,
                preview: "fixture posture",
                explicitOpenness: true,
                requiresIntroduction: false
            ),
            dominantSurface: surface,
            overallScore: retrievalScore
        )
    }

    private func aggregatedFitNarratives(_ match: ExchangeMatch) -> String {
        let parts = match.reasons.map { $0.summary } + match.cautions.map { $0.summary }
            + [match.recommendation].compactMap { $0 }
        return parts.joined(separator: " ")
    }

    private func hasSpecializationWithoutFusedLeak(_ match: ExchangeMatch) -> Bool {
        match.reasons.contains { r in
            r.summary.lowercased().contains("theme") ||
                r.summary.lowercased().contains("canonical") ||
                r.summary.lowercased().contains("listing")
        }
    }
}
