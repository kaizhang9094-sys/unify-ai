import XCTest
import AnumCore

/// Deterministic `ExchangeRetrievalEngine` coverage: BM25 + vector + RRF fusion,
/// rerank signals, and hard gates exposed on the retrieval path. No network / ONNX / LLM.
final class ExchangeRetrievalEngineTests: XCTestCase {
    private let fixtureDate = SecretaryProjectionTestSupport.fixtureDate
    private let embedder = FixedEmbeddingProvider(dimensions: 24)

    // MARK: - Empty / weak results

    func test_emptyStore_returnsNoCandidates() async {
        let store = ExchangeRetrievalStore()
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "anything",
            semanticText: "anything",
            queryIntentClass: .generalDiscovery,
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertTrue(results.isEmpty)
    }

    func test_noLexicalOrSemanticOverlap_returnsEmpty() async {
        let store = ExchangeRetrievalStore()
        // No document embedding → vector channel cannot pull unrelated docs; BM25 has no shared tokens with the query.
        let doc = ExchangeRetrievalDocument(
            id: "doc-orphan",
            counterpartyID: "cp-orphan",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .local,
            title: "Orphan fixture",
            lexicalText: "onlyuniqueorphantermmmx",
            semanticText: "onlyuniqueorphantermmmx",
            embedding: nil,
            updatedAt: fixtureDate
        )
        await store.replaceAllDocuments([doc])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "completelydifferentyyyquery",
            semanticText: "completelydifferentzzzsemantic",
            queryIntentClass: .generalDiscovery,
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertTrue(results.isEmpty, "Without lexical overlap and without doc embeddings, retrieval should stay empty.")
    }

    // MARK: - Fusion + determinism

    func test_retrieve_isDeterministicAcrossIdenticalCalls() async {
        let store = ExchangeRetrievalStore()
        let alpha = makeOfferDocument(
            id: "doc-alpha",
            lexicalText: "fixturealpha keywordone sharedtoken",
            semanticText: "fixturealpha keywordone sharedtoken",
            embeddingSource: "shared-semantic-anchor"
        )
        let beta = makeOfferDocument(
            id: "doc-beta",
            lexicalText: "unrelatedzzztext",
            semanticText: "unrelatedzzztext",
            embeddingSource: "shared-semantic-anchor"
        )
        await store.replaceAllDocuments([alpha, beta])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "fixturealpha keywordone",
            semanticText: "shared-semantic-anchor",
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            limit: 10
        )
        let first = await engine.retrieve(query: query, fusedLimit: 8)
        let second = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(first.map(\.document.id), second.map(\.document.id))
        XCTAssertFalse(first.isEmpty)
    }

    func test_lexicalAndVectorSignals_canSurfaceDistinctDocuments() async {
        let store = ExchangeRetrievalStore()
        let lexicalStrong = makeOfferDocument(
            id: "doc-lex",
            lexicalText: "retrievalfixture betazeta uniquelex",
            semanticText: "othersemantic",
            embeddingSource: "othersemantic"
        )
        let vectorBuddy = makeOfferDocument(
            id: "doc-vec",
            lexicalText: "zzzzminimallex",
            semanticText: "zzzzminimallex",
            embeddingSource: "retrievalfixture betazeta uniquelex"
        )
        await store.replaceAllDocuments([lexicalStrong, vectorBuddy])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "retrievalfixture betazeta uniquelex",
            semanticText: "retrievalfixture betazeta uniquelex",
            queryIntentClass: .generalDiscovery,
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        let ids = Set(results.map(\.document.id))
        XCTAssertTrue(ids.contains("doc-lex"))
        XCTAssertTrue(ids.contains("doc-vec"), "Vector channel should still surface the embedding-aligned doc.")
    }

    // MARK: - Query terms → ranking

    func test_capabilityTerms_shiftOrder_underCapabilitySearch() async {
        let store = ExchangeRetrievalStore()
        let without = makeOfferDocument(
            id: "doc-no-cap",
            lexicalText: "software consulting services fixturecap",
            semanticText: "software consulting services fixturecap",
            embeddingSource: "software consulting services fixturecap",
            capabilityTerms: []
        )
        let withCap = makeOfferDocument(
            id: "doc-with-cap",
            lexicalText: "software consulting services fixturecap",
            semanticText: "software consulting services fixturecap",
            embeddingSource: "software consulting services fixturecap",
            capabilityTerms: ["fixturecapterm"]
        )
        await store.replaceAllDocuments([without, withCap])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "software consulting services fixturecap",
            semanticText: "software consulting services fixturecap",
            queryIntentClass: .capabilitySearch,
            surfacePreference: .capability,
            capabilityTerms: ["fixturecapterm"],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 4)
        XCTAssertEqual(results.first?.document.id, "doc-with-cap")
    }

    func test_keywords_boostDocumentWithMatchingTag() async {
        let store = ExchangeRetrievalStore()
        let plain = ExchangeRetrievalDocument(
            id: "doc-plain",
            counterpartyID: "cp-plain",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .local,
            title: "Offer plain",
            tags: [],
            lexicalText: "fixturekeywordrank sharedbody",
            semanticText: "fixturekeywordrank sharedbody",
            embedding: embedder.embed("fixturekeywordrank sharedbody"),
            updatedAt: fixtureDate
        )
        let tagged = ExchangeRetrievalDocument(
            id: "doc-tagged",
            counterpartyID: "cp-tagged",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .local,
            title: "Offer tagged",
            tags: ["fixturetagtoken"],
            lexicalText: "fixturekeywordrank sharedbody",
            semanticText: "fixturekeywordrank sharedbody",
            embedding: embedder.embed("fixturekeywordrank sharedbody"),
            updatedAt: fixtureDate
        )
        await store.replaceAllDocuments([plain, tagged])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "fixturekeywordrank sharedbody",
            semanticText: "fixturekeywordrank sharedbody",
            queryIntentClass: .generalDiscovery,
            keywords: ["fixturetagtoken"],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 4)
        XCTAssertEqual(results.first?.document.id, "doc-tagged")
    }

    // MARK: - Hard gates

    func test_visibilityAllowList_dropsNonMatchingDocument() async {
        let store = ExchangeRetrievalStore()
        let visible = makeOfferDocument(
            id: "doc-visible",
            lexicalText: "gatefixturevisibility sharedgate",
            semanticText: "gatefixturevisibility sharedgate",
            embeddingSource: "gatefixturevisibility sharedgate",
            visibility: "public"
        )
        let hidden = makeOfferDocument(
            id: "doc-hidden",
            lexicalText: "gatefixturevisibility sharedgate",
            semanticText: "gatefixturevisibility sharedgate",
            embeddingSource: "gatefixturevisibility sharedgate",
            visibility: "hidden"
        )
        await store.replaceAllDocuments([visible, hidden])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "gatefixturevisibility sharedgate",
            semanticText: "gatefixturevisibility sharedgate",
            queryIntentClass: .generalDiscovery,
            visibilityAllowList: ["public"],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(results.map(\.document.id), ["doc-visible"])
    }

    func test_availabilityAllowList_dropsNonMatchingDocument() async {
        let store = ExchangeRetrievalStore()
        let open = makeOfferDocument(
            id: "doc-open",
            lexicalText: "gatefixtureavail sharedavail",
            semanticText: "gatefixtureavail sharedavail",
            embeddingSource: "gatefixtureavail sharedavail",
            availability: "available"
        )
        let paused = makeOfferDocument(
            id: "doc-paused",
            lexicalText: "gatefixtureavail sharedavail",
            semanticText: "gatefixtureavail sharedavail",
            embeddingSource: "gatefixtureavail sharedavail",
            availability: "paused"
        )
        await store.replaceAllDocuments([open, paused])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "gatefixtureavail sharedavail",
            semanticText: "gatefixtureavail sharedavail",
            queryIntentClass: .generalDiscovery,
            availabilityAllowList: ["available"],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(results.map(\.document.id), ["doc-open"])
    }

    func test_reachability_acceptingInboundOnly_dropsFalse() async {
        let store = ExchangeRetrievalStore()
        let accepting = makeOfferDocument(
            id: "doc-inbound-true",
            lexicalText: "reachfixture inboundtext",
            semanticText: "reachfixture inboundtext",
            embeddingSource: "reachfixture inboundtext",
            acceptingInbound: true
        )
        let closedInbound = makeOfferDocument(
            id: "doc-inbound-false",
            lexicalText: "reachfixture inboundtext",
            semanticText: "reachfixture inboundtext",
            embeddingSource: "reachfixture inboundtext",
            acceptingInbound: false
        )
        await store.replaceAllDocuments([accepting, closedInbound])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "reachfixture inboundtext",
            semanticText: "reachfixture inboundtext",
            queryIntentClass: .generalDiscovery,
            reachabilityRequirement: .acceptingInboundOnly,
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(results.map(\.document.id), ["doc-inbound-true"])
    }

    func test_reachability_routeableOnly_dropsClosedAccess() async {
        let store = ExchangeRetrievalStore()
        let open = makeOfferDocument(
            id: "doc-route-open",
            lexicalText: "routeclosedfixture sharedroute",
            semanticText: "routeclosedfixture sharedroute",
            embeddingSource: "routeclosedfixture sharedroute",
            accessMode: "direct",
            acceptingInbound: true
        )
        let closed = makeOfferDocument(
            id: "doc-route-closed",
            lexicalText: "routeclosedfixture sharedroute",
            semanticText: "routeclosedfixture sharedroute",
            embeddingSource: "routeclosedfixture sharedroute",
            accessMode: "closed",
            acceptingInbound: true
        )
        await store.replaceAllDocuments([open, closed])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "routeclosedfixture sharedroute",
            semanticText: "routeclosedfixture sharedroute",
            queryIntentClass: .generalDiscovery,
            reachabilityRequirement: .routeableOnly,
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(results.map(\.document.id), ["doc-route-open"])
    }

    func test_reachability_directOnly_requiresDirectAccessMode() async {
        let store = ExchangeRetrievalStore()
        let direct = makeOfferDocument(
            id: "doc-direct",
            lexicalText: "directonlyfixture shareddirect",
            semanticText: "directonlyfixture shareddirect",
            embeddingSource: "directonlyfixture shareddirect",
            accessMode: "direct",
            acceptingInbound: true
        )
        let intro = makeOfferDocument(
            id: "doc-introreq",
            lexicalText: "directonlyfixture shareddirect",
            semanticText: "directonlyfixture shareddirect",
            embeddingSource: "directonlyfixture shareddirect",
            accessMode: "introrequired",
            acceptingInbound: true
        )
        await store.replaceAllDocuments([direct, intro])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "directonlyfixture shareddirect",
            semanticText: "directonlyfixture shareddirect",
            queryIntentClass: .generalDiscovery,
            reachabilityRequirement: .directOnly,
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(results.map(\.document.id), ["doc-direct"])
    }

    func test_reachability_introAllowed_keepsIntroRequired() async {
        let store = ExchangeRetrievalStore()
        let intro = makeOfferDocument(
            id: "doc-intro-ok",
            lexicalText: "introallowedfixture sharedintro",
            semanticText: "introallowedfixture sharedintro",
            embeddingSource: "introallowedfixture sharedintro",
            accessMode: "introrequired",
            acceptingInbound: true
        )
        let bogus = makeOfferDocument(
            id: "doc-bogus-access",
            lexicalText: "introallowedfixture sharedintro",
            semanticText: "introallowedfixture sharedintro",
            embeddingSource: "introallowedfixture sharedintro",
            accessMode: "unknownmode",
            acceptingInbound: true
        )
        await store.replaceAllDocuments([intro, bogus])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "introallowedfixture sharedintro",
            semanticText: "introallowedfixture sharedintro",
            queryIntentClass: .generalDiscovery,
            reachabilityRequirement: .introAllowed,
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(results.map(\.document.id), ["doc-intro-ok"])
    }

    func test_hardRegionIDs_requireOverlap() async {
        let store = ExchangeRetrievalStore()
        let toronto = makeOfferDocument(
            id: "doc-toronto",
            lexicalText: "regiongatefixture sharedregion",
            semanticText: "regiongatefixture sharedregion",
            embeddingSource: "regiongatefixture sharedregion",
            canonicalRegionIDs: ["CA-ON-TORONTO"]
        )
        let elsewhere = makeOfferDocument(
            id: "doc-elsewhere",
            lexicalText: "regiongatefixture sharedregion",
            semanticText: "regiongatefixture sharedregion",
            embeddingSource: "regiongatefixture sharedregion",
            canonicalRegionIDs: ["US-NY-NYC"]
        )
        await store.replaceAllDocuments([toronto, elsewhere])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "regiongatefixture sharedregion",
            semanticText: "regiongatefixture sharedregion",
            queryIntentClass: .generalDiscovery,
            hardRegionIDs: ["CA-ON-TORONTO"],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(results.map(\.document.id), ["doc-toronto"])
    }

    func test_explicitFulfillmentRequired_gate() async {
        let store = ExchangeRetrievalStore()
        let remote = makeOfferDocument(
            id: "doc-remote",
            lexicalText: "fulfillfixture sharedfulfill",
            semanticText: "fulfillfixture sharedfulfill",
            embeddingSource: "fulfillfixture sharedfulfill",
            filterTokens: ["remote"]
        )
        let localOnly = makeOfferDocument(
            id: "doc-localonly",
            lexicalText: "fulfillfixture sharedfulfill",
            semanticText: "fulfillfixture sharedfulfill",
            embeddingSource: "fulfillfixture sharedfulfill",
            filterTokens: ["local"]
        )
        await store.replaceAllDocuments([remote, localOnly])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "fulfillfixture sharedfulfill",
            semanticText: "fulfillfixture sharedfulfill",
            queryIntentClass: .generalDiscovery,
            explicitFulfillmentRequired: true,
            fulfillmentMode: "remote",
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(results.map(\.document.id), ["doc-remote"])
    }

    func test_hardConstraint_location_requiresTokenOverlap() async {
        let store = ExchangeRetrievalStore()
        let sharedLexical = "hardlocsharedfixture xyz abc"
        let matchDoc = makeOfferDocument(
            id: "doc-in-toronto",
            lexicalText: "\(sharedLexical) torontocitytoken",
            semanticText: "\(sharedLexical) torontocitytoken",
            embeddingSource: "\(sharedLexical) torontocitytoken"
        )
        let missDoc = makeOfferDocument(
            id: "doc-not-in-toronto",
            lexicalText: "\(sharedLexical) vancouvercitytoken",
            semanticText: "\(sharedLexical) vancouvercitytoken",
            embeddingSource: "\(sharedLexical) vancouvercitytoken"
        )
        await store.replaceAllDocuments([matchDoc, missDoc])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let constraint = ExchangeIntent.Constraint(
            key: "placement_city",
            value: "torontocitytoken",
            isHardConstraint: true
        )
        let query = ExchangeRetrievalQuery(
            queryText: sharedLexical,
            semanticText: sharedLexical,
            queryIntentClass: .generalDiscovery,
            explicitHardConstraints: [constraint],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(results.map(\.document.id), ["doc-in-toronto"])
    }

    func test_hardConstraint_privacy_requiresSignal() async {
        let store = ExchangeRetrievalStore()
        let discreet = makeOfferDocument(
            id: "doc-discreet",
            lexicalText: "privacygatefixture sharedprivacy discreet",
            semanticText: "privacygatefixture sharedprivacy discreet",
            embeddingSource: "privacygatefixture sharedprivacy discreet"
        )
        let loud = makeOfferDocument(
            id: "doc-loud",
            lexicalText: "privacygatefixture sharedprivacy loud",
            semanticText: "privacygatefixture sharedprivacy loud",
            embeddingSource: "privacygatefixture sharedprivacy loud"
        )
        await store.replaceAllDocuments([discreet, loud])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let constraint = ExchangeIntent.Constraint(
            key: "privacy_posture",
            value: "private",
            isHardConstraint: true
        )
        let query = ExchangeRetrievalQuery(
            queryText: "privacygatefixture sharedprivacy",
            semanticText: "privacygatefixture sharedprivacy",
            queryIntentClass: .generalDiscovery,
            explicitHardConstraints: [constraint],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 8)
        XCTAssertEqual(results.map(\.document.id), ["doc-discreet"])
    }

    // MARK: - Entity / surface lane boundaries (expected future hard enforcement)

    /// Today retrieval still scores offer surfaces under social lanes; once gated, offer rows must disappear.
    func test_socialAffinitySearch_rejectsOfferOnlyDocument_expectedBoundary() async {
        let shared = "socialboundaryfixture person affinity circle picnic hiking friends community"
        let store = ExchangeRetrievalStore()
        let offerOnly = makeOfferDocument(
            id: "lane-offer-under-social-query",
            lexicalText: shared,
            semanticText: shared,
            embeddingSource: shared
        )
        await store.replaceAllDocuments([offerOnly])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: shared,
            semanticText: shared,
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            affinityTerms: ["socialboundaryfixture", "affinity", "friends", "community"],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 12)
        let offerHits = results.filter { $0.document.entityType == .offer }
        XCTAssertTrue(
            offerHits.isEmpty,
            "Social / people lane should not return offer-only retrieval documents once entity-type routing is enforced."
        )
    }

    /// Today affinity profile rows can still rank under commercial offer intent; future gate should drop them.
    func test_offerSearch_rejectsPureAffinityProfileDocument_expectedBoundary() async {
        let shared = "commercialboundaryfixture widget consulting hourly rate invoice procurement vendor"
        let store = ExchangeRetrievalStore()
        let affinityOnly = makeProfileSurfaceDocument(
            id: "lane-affinity-under-offer-query",
            surfaceType: .publicProfileAffinity,
            lexicalText: shared,
            semanticText: shared,
            embeddingSource: shared
        )
        await store.replaceAllDocuments([affinityOnly])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: shared,
            semanticText: shared,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            providerTerms: ["commercialboundaryfixture", "vendor", "procurement"],
            capabilityTerms: ["consulting", "widget"],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 12)
        let affinityHits = results.filter { $0.document.surfaceType == .publicProfileAffinity }
        XCTAssertTrue(
            affinityHits.isEmpty,
            "Commercial offer lane should not return pure affinity profile documents once surface routing is enforced."
        )
    }

    /// Same commercial / offer query shape as `test_offerSearch_rejectsPureAffinityProfileDocument_expectedBoundary`, with an offer row present.
    func test_offerSearch_returnsOfferDocument_laneAllowsOffer() async {
        let shared = "commercialboundaryfixture widget consulting hourly rate invoice procurement vendor"
        let store = ExchangeRetrievalStore()
        let offerDoc = makeOfferDocument(
            id: "lane-offer-allowed-commercial",
            lexicalText: shared,
            semanticText: shared,
            embeddingSource: shared
        )
        await store.replaceAllDocuments([offerDoc])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: shared,
            semanticText: shared,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            providerTerms: ["commercialboundaryfixture", "vendor", "procurement"],
            capabilityTerms: ["consulting", "widget"],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 12)
        XCTAssertTrue(
            results.contains { $0.document.id == offerDoc.id && $0.document.entityType == .offer },
            "Commercial offer queries should continue to surface offer documents."
        )
    }

    /// Same social / affinity query shape as `test_socialAffinitySearch_rejectsOfferOnlyDocument_expectedBoundary`, with an affinity profile row present.
    func test_socialAffinitySearch_returnsAffinityProfileDocument_laneAllowsAffinity() async {
        let shared = "socialboundaryfixture person affinity circle picnic hiking friends community"
        let store = ExchangeRetrievalStore()
        let affinityDoc = makeProfileSurfaceDocument(
            id: "lane-affinity-allowed-social",
            surfaceType: .publicProfileAffinity,
            lexicalText: shared,
            semanticText: shared,
            embeddingSource: shared
        )
        await store.replaceAllDocuments([affinityDoc])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: shared,
            semanticText: shared,
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            affinityTerms: ["socialboundaryfixture", "affinity", "friends", "community"],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 12)
        XCTAssertTrue(
            results.contains {
                $0.document.id == affinityDoc.id && $0.document.surfaceType == .publicProfileAffinity
            },
            "Social / relationship queries should continue to surface affinity profile documents."
        )
    }

    /// Provider lane should favor capability surfaces; pure affinity profiles should be excluded without social intent.
    func test_providerSearch_returnsCapability_notPureAffinity_expectedBoundary() async {
        let sharedPrefix = "provcapboundaryfixture consulting session enterprise"
        let capabilityToken = "engineeringleveranchorunique"
        let store = ExchangeRetrievalStore()
        let capabilityProfile = makeProfileSurfaceDocument(
            id: "lane-capability-under-provider",
            surfaceType: .publicProfileCapability,
            lexicalText: "\(sharedPrefix) \(capabilityToken) software platform integration",
            semanticText: "\(sharedPrefix) \(capabilityToken) software platform integration",
            embeddingSource: "\(sharedPrefix) \(capabilityToken)"
        )
        let affinityProfile = makeProfileSurfaceDocument(
            id: "lane-affinity-under-provider",
            surfaceType: .publicProfileAffinity,
            lexicalText: "\(sharedPrefix) hiking friends social circle bookclub picnic",
            semanticText: "\(sharedPrefix) hiking friends social circle bookclub picnic",
            embeddingSource: "\(sharedPrefix) hiking friends"
        )
        await store.replaceAllDocuments([capabilityProfile, affinityProfile])
        let engine = ExchangeRetrievalEngine(store: store, embeddingProvider: embedder)
        let query = ExchangeRetrievalQuery(
            queryText: "\(sharedPrefix) \(capabilityToken) software platform integration",
            semanticText: "\(sharedPrefix) \(capabilityToken) software platform integration",
            queryIntentClass: .providerSearch,
            surfacePreference: .capability,
            providerTerms: ["provcapboundaryfixture", "enterprise"],
            capabilityTerms: [capabilityToken, "software", "integration"],
            limit: 10
        )
        let results = await engine.retrieve(query: query, fusedLimit: 12)
        XCTAssertTrue(
            results.contains { $0.document.id == capabilityProfile.id },
            "Provider search should return capability profile surfaces."
        )
        let affinityHits = results.filter { $0.document.id == affinityProfile.id }
        XCTAssertTrue(
            affinityHits.isEmpty,
            "Provider / capability intent should not return pure affinity profile documents without explicit social intent."
        )
    }

    // MARK: - Helpers

    private func makeProfileSurfaceDocument(
        id: String,
        surfaceType: ExchangeRetrievalDocument.SurfaceType,
        lexicalText: String,
        semanticText: String,
        embeddingSource: String,
        visibility: String? = "public",
        availability: String? = "available",
        accessMode: String? = "direct",
        acceptingInbound: Bool? = true,
        capabilityTerms: [String] = [],
        affinityTerms: [String] = []
    ) -> ExchangeRetrievalDocument {
        ExchangeRetrievalDocument(
            id: id,
            counterpartyID: "cp-\(id)",
            publicProfileID: "pp-\(id)",
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: surfaceType,
            sourceKind: .local,
            visibility: visibility,
            availability: availability,
            accessMode: accessMode,
            acceptingInbound: acceptingInbound,
            title: "Fixture profile \(id)",
            tags: [],
            lexicalText: lexicalText,
            semanticText: semanticText,
            capabilityTerms: capabilityTerms,
            affinityTerms: affinityTerms,
            embedding: embedder.embed(embeddingSource),
            updatedAt: fixtureDate
        )
    }

    private func makeOfferDocument(
        id: String,
        lexicalText: String,
        semanticText: String,
        embeddingSource: String,
        visibility: String? = "public",
        availability: String? = "available",
        accessMode: String? = "direct",
        acceptingInbound: Bool? = true,
        canonicalRegionIDs: [String] = [],
        filterTokens: [String] = [],
        capabilityTerms: [String] = []
    ) -> ExchangeRetrievalDocument {
        ExchangeRetrievalDocument(
            id: id,
            counterpartyID: "cp-\(id)",
            publicProfileID: "pp-\(id)",
            offerID: "offer-\(id)",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .local,
            visibility: visibility,
            availability: availability,
            accessMode: accessMode,
            acceptingInbound: acceptingInbound,
            title: "Fixture \(id)",
            tags: [],
            canonicalRegionIDs: canonicalRegionIDs,
            lexicalText: lexicalText,
            semanticText: semanticText,
            capabilityTerms: capabilityTerms,
            filterTokens: filterTokens,
            embedding: embedder.embed(embeddingSource),
            updatedAt: fixtureDate
        )
    }
}
