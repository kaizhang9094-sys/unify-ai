import XCTest
@testable import AnumCore

final class ExchangeRequesterIntentGapReducerTests: XCTestCase {
    private let reducer = ExchangeRequesterIntentGapReducer()
    private let decisionEngine = ExchangeRequesterDecisionNeedsEngine()

    // MARK: - Roofer / Aurora multi-facet

    func test_rooferAurora_multiFacet_unknownsAndCombinedQuestion() {
        let raw =
            "Find me a roofer in Aurora who can come tomorrow at 2pm, has insurance, handles small leaks, and can give a quote under $300."

        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "roofing",
            transactionIntent: .inquire,
            places: [
                ExchangeIntentFacets.StructuredPlace(
                    normalizedText: "Aurora",
                    aliases: [],
                    confidence: 0.9,
                    isHard: true
                )
            ],
            attributes: [
                ExchangeIntentFacets.StructuredAttribute(key: "task", value: "small leak", numericValue: nil)
            ],
            preferences: [],
            timeConstraints: [
                ExchangeIntentFacets.StructuredTimeConstraint(kind: .specific, text: "tomorrow at 2pm")
            ],
            commercialConstraints: [
                ExchangeIntentFacets.StructuredCommercialConstraint(
                    kind: .budget,
                    key: "max",
                    value: "under $300",
                    isHard: true
                )
            ],
            broadRecallTokens: ["roofer", "roofing"],
            semanticConcepts: ["roof repair"],
            clarificationGaps: [],
            rawUserText: raw
        )

        let facets = ExchangeIntentFacets(
            searchIntent: si,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer
        )

        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "Roof help",
            objective: raw,
            constraints: [
                ExchangeIntent.Constraint(key: "insurance", value: "must be insured", isHardConstraint: true)
            ],
            desiredOutcomes: [.quote]
        )

        let thread = ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )

        let offer = ExchangeOffer(
            id: "offer-roof-1",
            nodeID: "node-roof",
            title: "Residential roof repair",
            summary: "Asphalt shingle repair and inspections.",
            category: "roofing",
            tags: ["residential repair", "roofing"],
            regionTags: ["Aurora"],
            commercialFacts: .empty
        )

        let out = reducer.reduce(
            input: .init(
                thread: thread,
                offer: offer,
                publicProfile: nil,
                operatingMemory: .empty,
                knownFactLines: [],
                selectedMatch: nil,
                matchCompare: nil
            )
        )

        let kinds = Set(out.gaps.map(\.kind))
        XCTAssertTrue(kinds.contains(.timing), "Expected timing gap; got \(kinds)")
        XCTAssertTrue(kinds.contains(.budget), "Expected budget gap; got \(kinds)")
        XCTAssertTrue(kinds.contains(.credential), "Expected credential gap; got \(kinds)")

        let unknownBudget = out.gaps.contains {
            $0.kind == .budget && $0.status == .unknown
        }
        let unknownTiming = out.gaps.contains {
            $0.kind == .timing && $0.status == .unknown
        }
        let unknownCredential = out.gaps.contains {
            $0.kind == .credential && $0.status == .unknown
        }
        XCTAssertTrue(unknownBudget && unknownTiming && unknownCredential, "Expected unknown facets for thin surface.")

        let combined = out.combinedProviderQuestion?.lowercased() ?? ""
        XCTAssertTrue(
            combined.contains("2pm")
                || combined.contains("tomorrow")
                || combined.contains("availab")
                || combined.contains("insur")
                || combined.contains("300")
                || combined.contains("price"),
            "Combined question should surface timing, insurance, or budget: \(out.combinedProviderQuestion ?? "nil")"
        )

        let ctx = ExchangeAgencyContextBuilder.buildRequesterContext(
            threadID: thread.id,
            userIntent: raw,
            publicProfile: nil,
            offer: offer,
            operatingMemory: .empty,
            intentGaps: out.gaps,
            intentGapCombinedClarificationQuestion: out.combinedProviderQuestion
        )
        let needs = decisionEngine.evaluate(context: ctx)
        XCTAssertNotEqual(
            needs.decisionReadiness,
            .decisionReady,
            "Hard unknown facets should prevent decision-ready readiness."
        )
    }

    // MARK: - Budget satisfied on surface, timing still unknown

    func test_budgetSatisfied_whenPricePublished_timingStillUnknown() {
        let raw = "Quote under $300 tomorrow afternoon for a small patch."
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            transactionIntent: .inquire,
            places: [],
            attributes: [],
            preferences: [],
            timeConstraints: [
                ExchangeIntentFacets.StructuredTimeConstraint(kind: .day, text: "tomorrow afternoon")
            ],
            commercialConstraints: [
                ExchangeIntentFacets.StructuredCommercialConstraint(
                    kind: .budget,
                    key: "max",
                    value: "under $300",
                    isHard: true
                )
            ],
            broadRecallTokens: ["patch"],
            semanticConcepts: [],
            clarificationGaps: [],
            rawUserText: raw
        )
        let facets = ExchangeIntentFacets(searchIntent: si, queryIntentClass: .offerSearch, surfacePreference: .offer)
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            title: "Patch",
            objective: raw
        )
        let thread = ExchangeThread(mode: .transactional, intent: intent, posture: ExchangePosture(), facets: facets, state: .drafting)

        let cf = ExchangeOffer.CommercialFacts(priceDisplay: "Typical patch visits from $250")
        let offer = ExchangeOffer(
            id: "offer-priced",
            nodeID: "node-1",
            title: "Small roof patch",
            summary: "We patch minor leaks same week when possible.",
            commercialFacts: cf
        )

        let out = reducer.reduce(
            input: .init(thread: thread, offer: offer, publicProfile: nil, operatingMemory: .empty, knownFactLines: [])
        )

        let budgetGap = out.gaps.first { $0.kind == .budget }
        XCTAssertEqual(budgetGap?.status, .satisfied, "Published price display should satisfy budget facet probe.")

        let timingUnknown = out.gaps.contains { $0.kind == .timing && $0.status == .unknown }
        XCTAssertTrue(timingUnknown, "Timing should remain unknown without schedule copy.")

        let ctx = ExchangeAgencyContextBuilder.buildRequesterContext(
            threadID: thread.id,
            userIntent: raw,
            offer: offer,
            operatingMemory: .empty,
            intentGaps: out.gaps,
            intentGapCombinedClarificationQuestion: out.combinedProviderQuestion
        )
        let needs = decisionEngine.evaluate(context: ctx)
        XCTAssertNotEqual(needs.decisionReadiness, .decisionReady)
    }

    // MARK: - Soft preference optionalUnknown

    func test_softPreference_optionalUnknownLowerPriority() {
        let raw = "Prefer eco-friendly materials if possible."
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            transactionIntent: .inquire,
            places: [],
            attributes: [],
            preferences: [
                ExchangeIntentFacets.StructuredPreference(
                    key: "materials",
                    value: "eco-friendly",
                    strength: .preferred
                )
            ],
            timeConstraints: [],
            commercialConstraints: [],
            broadRecallTokens: ["roof"],
            semanticConcepts: [],
            clarificationGaps: [],
            rawUserText: raw
        )
        let facets = ExchangeIntentFacets(searchIntent: si, queryIntentClass: .offerSearch, surfacePreference: .offer)
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            title: "Eco",
            objective: raw
        )
        let thread = ExchangeThread(mode: .transactional, intent: intent, posture: ExchangePosture(), facets: facets, state: .drafting)

        let offer = ExchangeOffer(
            id: "offer-plain",
            nodeID: "node-1",
            title: "Standard shingle replacement",
            summary: "Traditional asphalt shingles. Fast turnaround.",
            commercialFacts: .empty
        )

        let out = reducer.reduce(
            input: .init(thread: thread, offer: offer, publicProfile: nil, operatingMemory: .empty, knownFactLines: [])
        )

        let pref = out.gaps.first { $0.kind == .preference && $0.requestedValue.lowercased().contains("eco") }
        XCTAssertEqual(pref?.status, .optionalUnknown)
        XCTAssertGreaterThanOrEqual(pref?.priority ?? 0, 10, "Soft gaps should sort after hard unknowns.")
    }

    // MARK: - Region mismatch

    func test_regionMismatch_whenPublishedAreasContradictHardPlace() {
        let raw = "Need service in Aurora."
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            transactionIntent: .inquire,
            places: [
                ExchangeIntentFacets.StructuredPlace(
                    normalizedText: "Aurora",
                    aliases: [],
                    confidence: 0.95,
                    isHard: true
                )
            ],
            broadRecallTokens: ["plumber"],
            semanticConcepts: [],
            clarificationGaps: [],
            rawUserText: raw
        )
        let facets = ExchangeIntentFacets(searchIntent: si, queryIntentClass: .providerSearch, surfacePreference: .offer)
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "Plumber",
            objective: raw
        )
        let thread = ExchangeThread(mode: .transactional, intent: intent, posture: ExchangePosture(), facets: facets, state: .drafting)

        let offer = ExchangeOffer(
            id: "offer-toronto",
            nodeID: "node-1",
            title: "GTA plumbing",
            summary: "Licensed plumbers.",
            regionTags: ["Toronto"],
            commercialFacts: .empty
        )

        let out = reducer.reduce(
            input: .init(thread: thread, offer: offer, publicProfile: nil, operatingMemory: .empty, knownFactLines: [])
        )

        let regionGap = out.gaps.first { $0.kind == .region && $0.requestedValue.lowercased().contains("aurora") }
        XCTAssertEqual(regionGap?.status, .mismatch)
    }
}
