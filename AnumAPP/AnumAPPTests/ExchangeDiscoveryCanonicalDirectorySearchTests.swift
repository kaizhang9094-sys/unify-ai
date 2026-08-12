import XCTest
@testable import AnumCore

/// Phase 3: canonical `facets.searchIntent` drives directory `SearchPlan` / HTTP payload shaping.
final class ExchangeDiscoveryCanonicalDirectorySearchTests: XCTestCase {
    private let discoveryEngine = ExchangeDiscoveryEngine()

    func test_searchPlan_canonicalGTAVTB_broadRecallAndAtomicRegions() {
        let full = "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."
        let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
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
            broadRecallTokens: ["house", "home", "gta", "seller financing", "3 bedroom", "extra noise token"],
            semanticConcepts: ["house"],
            rawUserText: full
        )
        let facets = pollutedFacets(searchIntent: searchIntent, pollution: full)
        let thread = pollutedThread(fullUserText: full, facets: facets, targetDesc: "house in gta")
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)

        XCTAssertTrue(plan.usesCanonicalDirectoryRecall)
        XCTAssertNotNil(plan.directoryQueryEmbeddingText)

        let tokens = Set(plan.requestTokens.map { $0.lowercased() })
        let requiredBroad: Set<String> = ["home", "house", "property", "real estate", "for sale", "gta", "greater toronto area"]
        XCTAssertTrue(requiredBroad.isSubset(of: tokens), "requestTokens=\(plan.requestTokens)")

        XCTAssertFalse(plan.requestTokens.joined(separator: " ").lowercased().contains("gta, and seller"))
        XCTAssertFalse(plan.requestTokens.contains(where: { $0.lowercased().contains("seller financing") }))
        XCTAssertFalse(plan.requestTokens.contains(where: { $0.lowercased().contains("3 bedroom") }))

        let regions = Set(plan.regionTerms.map { $0.lowercased() })
        XCTAssertEqual(regions, Set(["gta", "greater toronto area"]))
        XCTAssertFalse(plan.regionTerms.joined(separator: "|").contains("gta, and seller"))

        XCTAssertFalse(plan.requestTokens.contains { $0.caseInsensitiveCompare(full) == .orderedSame })
        XCTAssertFalse(plan.requestTokens.contains { $0.lowercased().contains("help me find") })

        let coarse = discoveryEngine.retrievalIntentTokens(for: plan)
        let blob = coarse.sorted().joined(separator: " ").lowercased()
        XCTAssertFalse(blob.contains("gta, and seller"))
        XCTAssertFalse(blob.contains(full.lowercased()))
    }

    func test_searchPlan_canonicalHouseGTASellerFinancing_noNarrowChips() {
        let full = "Looking for a house in GTA with seller financing."
        let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .realEstate,
            objectType: "house",
            transactionIntent: .forSale,
            places: [ExchangeIntentFacets.StructuredPlace(normalizedText: "gta", aliases: [])],
            broadRecallTokens: ["house", "gta", "seller financing"],
            rawUserText: full
        )
        let facets = pollutedFacets(searchIntent: searchIntent, pollution: full)
        let thread = pollutedThread(fullUserText: full, facets: facets, targetDesc: "house gta financing")
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)

        XCTAssertFalse(plan.requestTokens.joined(separator: " ").lowercased().contains("seller financing"))
        let regions = Set(plan.regionTerms.map { $0.lowercased() })
        XCTAssertEqual(regions, Set(["gta", "greater toronto area"]))
    }

    func test_searchPlan_canonicalRooferAuroraTomorrow_filtersTemporalRecall() {
        let full = "Find a roofer near Aurora who can come tomorrow."
        let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "roofer",
            transactionIntent: nil,
            places: [ExchangeIntentFacets.StructuredPlace(normalizedText: "aurora", aliases: [])],
            timeConstraints: [ExchangeIntentFacets.StructuredTimeConstraint(kind: .day, text: "tomorrow")],
            broadRecallTokens: ["roofer", "aurora", "tomorrow"],
            rawUserText: full
        )
        let facets = pollutedFacets(searchIntent: searchIntent, pollution: full)
        var merged = facets
        merged.providerTerms = ["roofer"]
        let thread = pollutedThread(fullUserText: full, facets: merged, targetDesc: "roofer near aurora")
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)

        XCTAssertFalse(plan.requestTokens.map { $0.lowercased() }.contains("tomorrow"))
        XCTAssertTrue(plan.requestTokens.map { $0.lowercased() }.contains("roofing"))
        XCTAssertEqual(Set(plan.regionTerms.map { $0.lowercased() }), Set(["aurora"]))
    }

    func test_searchPlan_withoutSearchIntent_legacyRequestTokenFusion() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            locationText: "montreal quebec",
            placeName: "montreal",
            providerTerms: ["plumber"],
            affinityTerms: ["family owned"],
            primaryKeywords: ["fix leak"],
            secondaryKeywords: ["urgent"]
        )
        let interpretation = ExchangeThread.InterpretationSnapshot(
            semanticTags: ["fixture"],
            discoveryKeywords: ["pipe burst"],
            targetTags: ["trades"]
        )
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "legacy",
            objective: "Emergency pipe burst in Montreal Quebec",
            targetDescription: nil
        )
        let thread = ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            interpretation: interpretation,
            state: .drafting
        )

        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)

        XCTAssertFalse(plan.usesCanonicalDirectoryRecall)
        XCTAssertNil(plan.directoryQueryEmbeddingText)
        XCTAssertFalse(plan.semanticTags.isEmpty)
        let semanticLC = plan.semanticTags.map { $0.lowercased() }
        let targetLC = plan.targetTags.map { $0.lowercased() }
        let regionLC = plan.regionTerms.map { $0.lowercased() }
        let primaryLC = plan.primaryKeywords.map { $0.lowercased() }
        let merged = Set(semanticLC + targetLC + regionLC + primaryLC)
        XCTAssertTrue(merged.contains("fixture"))
        XCTAssertTrue(merged.contains("montreal") || merged.contains("trades"))
    }

    func test_directoryRequest_canonicalPayloadSkipsKeywordPollution() async throws {
        let full = "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."
        let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .realEstate,
            objectType: "house",
            transactionIntent: .forSale,
            places: [ExchangeIntentFacets.StructuredPlace(normalizedText: "gta", aliases: [])],
            broadRecallTokens: ["house", "home", "gta", "seller financing", "3 bedroom"],
            rawUserText: full
        )
        let facets = pollutedFacets(searchIntent: searchIntent, pollution: full)
        let thread = pollutedThread(fullUserText: full, facets: facets, targetDesc: "house in gta")

        let capture = CapturingDirectoryClient(matches: [])
        let engine = ExchangeDiscoveryEngine(
            directoryClient: capture,
            localNodeIDProvider: { nil },
            embeddingProvider: NilEmbeddingForDiscoveryTests(),
            retrievalStore: nil,
            retrievalEngine: nil,
            retrievalIngestor: nil
        )

        _ = try await engine.discover(thread: thread, limit: 4)
        let request = try XCTUnwrap(capture.lastSearch)

        let tagBlob = request.tags.joined(separator: " ").lowercased()
        XCTAssertFalse(tagBlob.contains("gta, and seller"))
        XCTAssertFalse(tagBlob.contains("help me find"))
        XCTAssertTrue(tagBlob.contains("real estate"))
        XCTAssertTrue(tagBlob.contains("for sale"))

        let regionBlob = request.regionTags.joined(separator: "|").lowercased()
        XCTAssertTrue(regionBlob.contains("gta"))
        XCTAssertTrue(regionBlob.contains("greater toronto area"))
        XCTAssertFalse(regionBlob.contains("gta, and seller"))
    }

    func test_directoryRequest_canonical_openToAndOfferTagsAvoidPrimaryKeywordPollution() async throws {
        let full = "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."
        let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .realEstate,
            objectType: "house",
            transactionIntent: .forSale,
            places: [ExchangeIntentFacets.StructuredPlace(normalizedText: "gta", aliases: [])],
            broadRecallTokens: ["house", "home", "gta"],
            rawUserText: full
        )
        let facets = pollutedFacets(searchIntent: searchIntent, pollution: full)
        var merged = facets
        merged.primaryKeywords = [full, "gta, and seller offers vendor take back mortgage"]
        merged.secondaryKeywords = ["secondary soup blob"]
        merged.providerTerms = ["house", "listing"]
        merged.affinityTerms = ["fixture affinity"]
        let thread = pollutedThread(fullUserText: full, facets: merged, targetDesc: "house in gta")

        let capture = CapturingDirectoryClient(matches: [])
        let engine = ExchangeDiscoveryEngine(
            directoryClient: capture,
            localNodeIDProvider: { nil },
            embeddingProvider: NilEmbeddingForDiscoveryTests(),
            retrievalStore: nil,
            retrievalEngine: nil,
            retrievalIngestor: nil
        )

        _ = try await engine.discover(thread: thread, limit: 4)
        let request = try XCTUnwrap(capture.lastSearch)

        let offerJoined = request.offerTags.joined(separator: " ").lowercased()
        XCTAssertFalse(offerJoined.contains(full.lowercased()))
        XCTAssertTrue(offerJoined.contains("house") || offerJoined.contains("listing"))

        let openJoined = request.openToTags.joined(separator: " ").lowercased()
        XCTAssertFalse(openJoined.contains(full.lowercased()))
        XCTAssertTrue(openJoined.contains("fixture affinity") || openJoined.contains("affinity"))

        let qText = (request.queryText ?? "").lowercased()
        XCTAssertFalse(qText.contains(full.lowercased()))
        XCTAssertFalse(qText.contains("gta, and seller"))
    }
}

// MARK: - Helpers

private func pollutedFacets(
    searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
    pollution: String
) -> ExchangeIntentFacets {
    ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer,
        providerTerms: [],
        capabilityTerms: [],
        affinityTerms: ["social noise"],
        primaryKeywords: [pollution],
        secondaryKeywords: ["extra secondary keyword soup"]
    )
}

private func pollutedThread(
    fullUserText: String,
    facets: ExchangeIntentFacets,
    targetDesc: String
) -> ExchangeThread {
    let intent = ExchangeIntent(
        kind: .find,
        mode: .transactional,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer,
        title: "canonical directory fixture",
        objective: fullUserText,
        targetDescription: targetDesc
    )
    let interpretation = ExchangeThread.InterpretationSnapshot(
        semanticTags: ["polluted semantic tag"],
        discoveryKeywords: [fullUserText],
        targetTags: ["gta, and seller offers vendor take back mortgage"]
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

private struct NilEmbeddingForDiscoveryTests: MemoryEmbeddingProvider, Sendable {
    func embed(_ text: String) -> [Float]? { nil }
}

private final class CapturingDirectoryClient: ExchangeDirectoryClient, @unchecked Sendable {
    private let matches: [ExchangeDirectoryMatch]
    private(set) var lastSearch: ExchangeDirectorySearchRequest?

    init(matches: [ExchangeDirectoryMatch]) {
        self.matches = matches
    }

    func search(_ request: ExchangeDirectorySearchRequest) async throws -> ExchangeDirectorySearchResponse {
        lastSearch = request
        return ExchangeDirectorySearchResponse(matches: matches, source: .local, summary: "capture")
    }

    func publishSellerSurface(
        _ request: ExchangeSellerSurfacePublishRequest
    ) async throws -> ExchangeSellerSurfacePublishResponse {
        throw ExchangeDirectoryClientError.unavailable(reason: "stub")
    }

    func unpublishSellerSurface(
        nodeID: String,
        publicProfileID: String
    ) async throws -> ExchangeSellerSurfaceUnpublishResponse {
        throw ExchangeDirectoryClientError.unavailable(reason: "stub")
    }

    func publishRetrievalDocuments(
        _ request: ExchangeRetrievalDocumentPublishRequest
    ) async throws -> ExchangeRetrievalDocumentPublishResponse {
        throw ExchangeDirectoryClientError.unavailable(reason: "stub")
    }
}
