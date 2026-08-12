import XCTest
@testable import AnumCore

/// End-to-end requester canonical pipeline invariants (Phases 1–5 + leak cleanup).
/// Forbidden fused clause must not appear outside `searchIntent.rawUserText` / `intent.objective`.
final class CanonicalSearchRequesterInvariantTests: XCTestCase {
    private let fusedForbidden = "gta, and seller offers vendor take back mortgage"
    private let builder = ExchangeRetrievalQueryBuilder()
    private let discoveryEngine = ExchangeDiscoveryEngine()
    private let fitEngine = ExchangeFitEngine()

    private let canonicalQueries: [(id: String, text: String)] = [
        ("gta_vtb", "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."),
        ("house_gta_fin", "Looking for a house in GTA with seller financing."),
        ("roofer", "Find a roofer near Aurora who can come tomorrow."),
        ("robotics", "Find someone in Toronto with experience in commercial robotics."),
        ("vc_seed", "Help me find a VC interested in funding seed stage AI startups."),
        ("ski_buddy", "Find me a ski buddy who has time to go ski with me next Saturday to Mount St. Louis."),
        ("dating", "Find me a single woman looking to date who likes dogs.")
    ]

    func test_allCanonicalQueries_noForbiddenFusedPhraseOutsideRawUserText() async {
        let interpreter = ExchangeInterpreter(intelligenceProvider: ExchangeFallbackIntelligenceProvider())

        for item in canonicalQueries {
            let raw = item.text
            guard case .interpreted(let interpreted) = await interpreter.interpret(userText: raw, threadContext: nil) else {
                XCTFail("Expected interpretation for \(item.id)")
                continue
            }
            guard interpreted.facets.searchIntent != nil else {
                continue
            }

            assertNoForbiddenLeak(
                strings: requesterSurfacesExcludingAllowedRaw(interpreted, raw: raw),
                raw: raw,
                context: item.id
            )

            let thread = threadSnapshot(from: interpreted, objective: raw)
            let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)
            XCTAssertTrue(plan.usesCanonicalDirectoryRecall, "\(item.id) should use canonical directory recall")

            assertNoForbiddenLeak(
                strings: planSurfaces(plan),
                raw: raw,
                context: "\(item.id).SearchPlan"
            )

            let coarse = discoveryEngine.retrievalIntentTokens(for: plan)
            assertNoForbiddenLeak(
                strings: [coarse.sorted().joined(separator: " ")],
                raw: raw,
                context: "\(item.id).retrievalIntentTokens"
            )
            XCTAssertFalse(coarse.map { $0.lowercased() }.contains(raw.lowercased()), "coarse token equals full raw for \(item.id)")

            let rq = builder.build(from: thread)
            assertNoForbiddenLeak(
                strings: retrievalSurfaces(rq),
                raw: raw,
                context: "\(item.id).ExchangeRetrievalQuery"
            )

            let match = fitEngine.evaluate(
                thread: thread,
                candidates: [minimalCandidate(for: interpreted)]
            ).first!
            let fitBlob = (match.reasons.map(\.summary) + match.cautions.map(\.summary) + [match.recommendation].compactMap { $0 })
                .joined(separator: " ")
            assertNoForbiddenLeak(strings: [fitBlob], raw: raw, context: "\(item.id).ExchangeMatch")
        }
    }

    func test_gtaVtb_expectedCanonicalShape_and_financingSoft() async throws {
        let raw = "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."
        let interpreted = await interpret(raw)
        let si = try XCTUnwrap(interpreted.facets.searchIntent)

        XCTAssertEqual(si.domainCategory, .realEstate)
        XCTAssertEqual(si.objectType, "house")
        XCTAssertEqual(si.transactionIntent, .forSale)
        XCTAssertTrue(si.places.contains { $0.normalizedText.lowercased() == "gta" })
        XCTAssertTrue(si.attributes.contains { $0.key == "bedrooms" && $0.numericValue == 3 })
        let fin = try XCTUnwrap(si.commercialConstraints.first { $0.kind == .financing })
        XCTAssertFalse(fin.isHard)

        XCTAssertTrue(si.rawUserText.lowercased().contains("gta"))
        XCTAssertTrue(si.rawUserText.lowercased().contains("vendor take"))
    }

    // MARK: - Helpers

    private func interpret(_ raw: String) async -> ExchangeInterpreter.InterpretedRequest {
        let interpreter = ExchangeInterpreter(intelligenceProvider: ExchangeFallbackIntelligenceProvider())
        guard case .interpreted(let out) = await interpreter.interpret(userText: raw, threadContext: nil) else {
            XCTFail("interpret failed")
            return ExchangeInterpreter.InterpretedRequest(
                intent: ExchangeIntent(kind: .find, mode: .transactional, title: "t", objective: raw),
                posture: ExchangePosture(),
                facets: ExchangeIntentFacets()
            )
        }
        return out
    }

    private func threadSnapshot(from interpreted: ExchangeInterpreter.InterpretedRequest, objective: String) -> ExchangeThread {
        ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: interpreted.intent.kind,
                mode: interpreted.intent.mode,
                queryIntentClass: interpreted.facets.queryIntentClass,
                surfacePreference: interpreted.facets.surfacePreference,
                title: interpreted.intent.title,
                objective: objective,
                targetDescription: interpreted.intent.targetDescription
            ),
            posture: interpreted.posture,
            facets: interpreted.facets,
            interpretation: ExchangeThread.InterpretationSnapshot(
                semanticTags: interpreted.semanticTags,
                discoveryKeywords: interpreted.discoveryKeywords,
                targetTags: interpreted.targetTags
            ),
            state: .drafting
        )
    }

    private func requesterSurfacesExcludingAllowedRaw(
        _ interpreted: ExchangeInterpreter.InterpretedRequest,
        raw: String
    ) -> [String] {
        var s: [String] = []
        s.append(contentsOf: interpreted.semanticTags)
        s.append(contentsOf: interpreted.discoveryKeywords)
        s.append(contentsOf: interpreted.targetTags)
        s.append(contentsOf: interpreted.facets.regionTerms)
        s.append(contentsOf: interpreted.facets.primaryKeywords)
        s.append(contentsOf: interpreted.facets.secondaryKeywords)
        s.append(contentsOf: interpreted.facets.providerTerms)
        s.append(contentsOf: interpreted.facets.capabilityTerms)
        s.append(contentsOf: interpreted.facets.affinityTerms)
        if let td = interpreted.intent.targetDescription { s.append(td) }
        if let lt = interpreted.facets.locationText { s.append(lt) }
        if let pn = interpreted.facets.placeName { s.append(pn) }
        return s
    }

    private func planSurfaces(_ plan: ExchangeDiscoveryEngine.SearchPlan) -> [String] {
        var s: [String] = []
        s.append(contentsOf: plan.requestTokens)
        s.append(contentsOf: plan.regionTerms)
        s.append(contentsOf: plan.semanticTags)
        s.append(contentsOf: plan.targetTags)
        s.append(contentsOf: plan.discoveryKeywords)
        s.append(contentsOf: plan.providerTerms)
        s.append(contentsOf: plan.capabilityTerms)
        s.append(contentsOf: plan.affinityTerms)
        s.append(contentsOf: plan.primaryKeywords)
        s.append(contentsOf: plan.secondaryKeywords)
        if let q = plan.directoryQueryEmbeddingText { s.append(q) }
        if let q = plan.rawQueryText { s.append(q) }
        if let q = plan.targetDescription { s.append(q) }
        return s
    }

    private func retrievalSurfaces(_ q: ExchangeRetrievalQuery) -> [String] {
        var s: [String] = []
        if let t = q.queryText { s.append(t) }
        if let t = q.semanticText { s.append(t) }
        s.append(contentsOf: q.keywords)
        s.append(contentsOf: q.providerTerms)
        s.append(contentsOf: q.capabilityTerms)
        s.append(contentsOf: q.affinityTerms)
        s.append(contentsOf: q.softRegionTerms)
        s.append(contentsOf: q.commercialIntentTerms)
        s.append(contentsOf: q.timeTerms)
        return s
    }

    private func assertNoForbiddenLeak(strings: [String], raw: String, context: String) {
        let rawNorm = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for field in strings {
            let low = field.lowercased()
            XCTAssertFalse(low.contains(fusedForbidden), "\(context): \(field.prefix(120))")
            if low == rawNorm {
                XCTFail("\(context): raw full sentence in field")
            }
        }
    }

    private func minimalCandidate(for interpreted: ExchangeInterpreter.InterpretedRequest) -> ExchangeDiscoveryEngine.DiscoveryCandidate {
        let profile = ExchangePublicNodeProfile(
            id: "pub-min",
            nodeID: "node-min",
            displayName: "Min",
            headline: "Service provider",
            summary: "Fixture summary for pipeline test.",
            regionTags: []
        )
        let cp = ExchangeCounterparty(
            id: "cp-min",
            kind: .provider,
            displayName: "Min",
            source: .localDirectory,
            publicProfile: profile,
            trust: ExchangeCounterparty.TrustSnapshot(level: .moderate),
            status: .active
        )
        return ExchangeDiscoveryEngine.DiscoveryCandidate(
            publicProfile: profile,
            counterparty: cp,
            matchedOffers: [],
            coarse: .init(
                queryTokenOverlap: 1,
                explicitTokenOverlap: 0,
                regionOverlap: 0,
                offerOverlap: 0,
                capabilityOverlap: 0,
                affinityOverlap: 0,
                hasPublicProfile: true,
                hasOffers: false,
                kindCompatible: true,
                placeCompatible: true,
                trustHintScore: 0.5,
                retrievalScore: 0.5,
                rationale: "min"
            ),
            posture: .init(bucket: .contactable, preview: "x", explicitOpenness: true, requiresIntroduction: false),
            dominantSurface: .mixed,
            overallScore: 0.5
        )
    }
}
