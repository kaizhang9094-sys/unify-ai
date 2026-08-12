import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeRetrievalPhase4ACleanup")
struct ExchangeRetrievalPhase4ACleanupTests {
    @Test("local seeking doc emits profileSeeking docKind and sourceField")
    func localSeekingDocKind() {
        let profile = makeProfile(openTo: ["collaborate on robotics"])
        let counterparty = makeCounterparty(profile: profile)
        let doc = ExchangeRetrievalDocumentBuilder().buildDocuments(
            profile: profile,
            offers: [],
            counterpartyID: counterparty.id,
            sourceKind: .local
        ).first { $0.surfaceType == .publicProfileSeeking }

        #expect(doc?.docKind == .profileSeeking)
        #expect(doc?.sourceField == "profile_seeking")
    }

    @Test("local affinity doc emits profileAffinity docKind and sourceField")
    func localAffinityDocKind() {
        let profile = makeProfile(interests: ["robotics", "founders"])
        let counterparty = makeCounterparty(profile: profile)
        let doc = ExchangeRetrievalDocumentBuilder().buildDocuments(
            profile: profile,
            offers: [],
            counterpartyID: counterparty.id,
            sourceKind: .local
        ).first { $0.surfaceType == .publicProfileAffinity }

        #expect(doc?.docKind == .profileAffinity)
        #expect(doc?.sourceField == "profile_affinity")
    }

    @Test("indexed seeking and affinity docs emit docKind and sourceField")
    func indexedSeekingAffinityDocKinds() {
        let profile = makeProfile(
            openTo: ["mentorship"],
            interests: ["robotics"]
        )
        let indexed = ExchangeIndexedProviderSurfaceBuilder().build(profile: profile, offers: [])
        let builder = ExchangeRetrievalDocumentBuilder()
        let seeking = builder.build(from: indexed, counterpartyID: profile.nodeID, sourceKind: .local)
            .first { $0.surfaceType == .publicProfileSeeking }
        let affinity = builder.build(from: indexed, counterpartyID: profile.nodeID, sourceKind: .local)
            .first { $0.surfaceType == .publicProfileAffinity }

        #expect(seeking?.docKind == .profileSeeking)
        #expect(seeking?.sourceField == "profile_seeking")
        #expect(affinity?.docKind == .profileAffinity)
        #expect(affinity?.sourceField == "profile_affinity")
    }

    @Test("retrieval document Codable round-trip preserves profile docKind")
    func codableRoundTripPreservesDocKind() throws {
        let document = ExchangeRetrievalDocument(
            id: "profile-seeking::profile-1",
            counterpartyID: "seller-1",
            nodeID: "seller-1",
            publicProfileID: "profile-1",
            entityType: .publicProfile,
            surfaceType: .publicProfileSeeking,
            sourceKind: .remote,
            docKind: .profileSeeking,
            sourceField: "profile_seeking",
            title: "Seller",
            lexicalText: "mentorship"
        )
        let decoded = try JSONDecoder().decode(
            ExchangeRetrievalDocument.self,
            from: JSONEncoder().encode(document)
        )
        #expect(decoded.docKind == .profileSeeking)
        #expect(decoded.sourceField == "profile_seeking")
    }

    @Test("canonical query semantic embedding excludes template boilerplate")
    func semanticEmbeddingExcludesTemplateBoilerplate() {
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .product,
            objectType: "laptop",
            transactionIntent: .buy,
            semanticConcepts: ["MacBook Pro"],
            extractionSource: .heuristicFallback
        )
        let query = buildCanonicalQuery(searchIntent: si, queryIntentClass: .offerSearch)

        #expect((query.semanticText ?? "").localizedCaseInsensitiveContains("Search for relevant offers and profiles"))
        #expect(!(query.semanticEmbeddingText ?? "").localizedCaseInsensitiveContains("Search for relevant offers and profiles"))
        #expect((query.semanticEmbeddingText ?? "").localizedCaseInsensitiveContains("MacBook Pro"))
        #expect(query.queryObjectText == "laptop")
    }

    @Test("real estate template for sale stays out of semantic embedding text")
    func realEstateTemplateNotInSemanticEmbedding() {
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .realEstate,
            objectType: "condo",
            transactionIntent: .forSale,
            semanticConcepts: ["waterfront condo"],
            extractionSource: .heuristicFallback
        )
        let query = buildCanonicalQuery(searchIntent: si, queryIntentClass: .offerSearch)

        #expect((query.semanticText ?? "").localizedCaseInsensitiveContains("for sale"))
        #expect(!(query.semanticEmbeddingText ?? "").localizedCaseInsensitiveContains("for sale"))
        #expect((query.semanticEmbeddingText ?? "").localizedCaseInsensitiveContains("waterfront condo"))
    }

    @Test("legacy query keywords exclude routing enum raw values")
    func legacyKeywordsExcludeRoutingEnums() {
        let facets = ExchangeIntentFacets(
            queryIntentClass: .offerSearch,
            surfacePreference: .mixed,
            primaryKeywords: ["macbook", "computer"]
        )
        let thread = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                surfacePreference: .mixed,
                title: "test",
                objective: "test"
            ),
            posture: ExchangePosture(),
            facets: facets,
            state: .searching(.init())
        )
        let query = ExchangeRetrievalQueryBuilder().build(from: thread)

        #expect(!query.keywords.contains("offersearch"))
        #expect(!query.keywords.contains("mixed"))
        #expect(query.keywords.contains("macbook"))
    }

    @Test("profile about embedding includes approach note and excludes operational labels")
    func profileAboutEmbeddingParity() {
        let profile = makeProfile(
            summary: "Software builder",
            approachNote: "Prefer async intro messages"
        )
        let counterparty = makeCounterparty(profile: profile)
        let doc = ExchangeRetrievalDocumentBuilder().buildDocuments(
            profile: profile,
            offers: [],
            counterpartyID: counterparty.id,
            sourceKind: .local
        ).first { $0.docKind == .profileAbout }
        #expect(doc != nil)

        let embeddingText = ExchangeRetrievalDocumentEmbeddingPolicy.retrievalEmbeddingText(for: doc!)
        #expect(embeddingText.localizedCaseInsensitiveContains("async intro"))
        #expect(!embeddingText.localizedCaseInsensitiveContains("direct"))
        #expect(!embeddingText.localizedCaseInsensitiveContains("discoverable"))
    }
}

private func makeProfile(
    openTo: [String] = [],
    interests: [String] = [],
    summary: String = "Summary",
    approachNote: String? = nil
) -> ExchangePublicNodeProfile {
    ExchangePublicNodeProfile(
        id: "profile-1",
        nodeID: "seller-1",
        displayName: "Seller",
        headline: "Headline",
        summary: summary,
        visibility: .discoverable,
        interests: interests,
        offers: [],
        openTo: openTo,
        excludedTopics: [],
        activityTags: [],
        regionTags: [],
        semantic: .init(),
        reachability: .init(
            accessMode: .direct,
            acceptingInbound: true,
            disclosureCeiling: .balanced,
            routeableOnly: false
        ),
        approach: .init(note: approachNote)
    )
}

private func makeCounterparty(profile: ExchangePublicNodeProfile) -> ExchangeCounterparty {
    ExchangeCounterparty(
        id: profile.nodeID,
        kind: .secretaryNode,
        displayName: profile.displayName ?? "Seller",
        source: .relayNetwork,
        identity: .init(nodeID: profile.nodeID, publicKeyID: nil, verification: .unverified),
        publicProfile: profile,
        tags: [],
        semantic: .init(),
        contactRoutes: [],
        status: .active
    )
}

private func buildCanonicalQuery(
    searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
    queryIntentClass: ExchangeIntent.QueryIntentClass
) -> ExchangeRetrievalQuery {
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: queryIntentClass,
        surfacePreference: .mixed
    )
    let thread = ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: queryIntentClass,
            title: "test",
            objective: "test"
        ),
        posture: ExchangePosture(),
        facets: facets,
        state: .searching(.init())
    )
    return ExchangeRetrievalQueryBuilder().build(from: thread)
}

