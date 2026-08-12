import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeRetrievalPhase4CRanking")
struct ExchangeRetrievalPhase4CRankingTests {
    @Test("capabilitySearch prefers capability over about")
    func capabilitySearchPrefersCapabilityOverAbout() async {
        let sharedText = "retail electronics reseller general background narrative"
        let capabilityDoc = makeRankingDocument(
            id: "profile-capability::seller-1",
            docKind: .profileCapability,
            surfaceType: .publicProfileCapability,
            entityType: .publicProfile,
            lexicalText: sharedText,
            capabilityTerms: ["retail", "electronics"]
        )
        let aboutDoc = makeRankingDocument(
            id: "profile-about::seller-1",
            docKind: .profileAbout,
            surfaceType: .publicProfileCapability,
            entityType: .publicProfile,
            lexicalText: sharedText,
            capabilityTerms: ["retail", "electronics"]
        )

        let query = ExchangeRetrievalQuery(
            queryText: "retail electronics",
            semanticEmbeddingText: "retail electronics",
            queryIntentClass: .capabilitySearch,
            surfacePreference: .capability,
            capabilityTerms: ["retail", "electronics"]
        )

        let results = await retrieve(query: query, documents: [aboutDoc, capabilityDoc])
        #expect(results.first?.document.docKind == .profileCapability)
    }

    @Test("providerSearch prefers intro and capability over about")
    func providerSearchPrefersIntroAndCapability() async {
        let sharedText = "multi seller retail electronics"
        let introDoc = makeRankingDocument(
            id: "profile-intro::seller-1",
            docKind: .profileIntro,
            surfaceType: .publicProfile,
            entityType: .publicProfile,
            lexicalText: sharedText,
            providerTerms: ["multi", "seller"]
        )
        let capabilityDoc = makeRankingDocument(
            id: "profile-capability::seller-1",
            docKind: .profileCapability,
            surfaceType: .publicProfileCapability,
            entityType: .publicProfile,
            lexicalText: sharedText,
            providerTerms: ["multi", "seller"]
        )
        let aboutDoc = makeRankingDocument(
            id: "profile-about::seller-1",
            docKind: .profileAbout,
            surfaceType: .publicProfileCapability,
            entityType: .publicProfile,
            lexicalText: sharedText,
            providerTerms: ["multi", "seller"]
        )

        let query = ExchangeRetrievalQuery(
            queryText: "multi seller",
            semanticEmbeddingText: "multi seller",
            queryIntentClass: .providerSearch,
            surfacePreference: .capability,
            providerTerms: ["multi", "seller"]
        )

        let results = await retrieve(query: query, documents: [aboutDoc, introDoc, capabilityDoc])
        let topKinds = results.prefix(2).compactMap(\.document.docKind)
        #expect(topKinds.contains(.profileIntro) || topKinds.contains(.profileCapability))
        #expect(topKinds.first != .profileAbout)
    }

    @Test("offerSearch prefers detail over FAQ when object lane inactive")
    func offerSearchPrefersDetailOverFAQ() async {
        let offerID = "offer-1"
        let sharedText = "macbook pro refurbished laptop"
        let detailDoc = makeRankingDocument(
            id: "offer-detail::\(offerID)",
            offerID: offerID,
            docKind: .offerDetail,
            lexicalText: sharedText
        )
        let faqDoc = makeRankingDocument(
            id: "offer-faq::\(offerID)::delivery",
            offerID: offerID,
            docKind: .offerFAQ,
            lexicalText: sharedText
        )

        let query = ExchangeRetrievalQuery(
            queryText: "macbook pro",
            semanticEmbeddingText: "macbook pro",
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            keywords: ["macbook", "pro"]
        )

        let results = await retrieve(query: query, documents: [faqDoc, detailDoc])
        #expect(results.first?.document.docKind == .offerDetail)
    }

    @Test("followUp prefers offer FAQ")
    func followUpPrefersOfferFAQ() async {
        let offerID = "offer-1"
        let sharedText = "macbook pro delivery included warranty"
        let detailDoc = makeRankingDocument(
            id: "offer-detail::\(offerID)",
            offerID: offerID,
            docKind: .offerDetail,
            lexicalText: sharedText
        )
        let faqDoc = makeRankingDocument(
            id: "offer-faq::\(offerID)::delivery",
            offerID: offerID,
            docKind: .offerFAQ,
            lexicalText: sharedText
        )

        let query = ExchangeRetrievalQuery(
            queryText: "delivery included",
            semanticEmbeddingText: "delivery included",
            queryIntentClass: .followUp,
            surfacePreference: .offer,
            keywords: ["delivery"]
        )

        let results = await retrieve(query: query, documents: [detailDoc, faqDoc])
        #expect(results.first?.document.docKind == .offerFAQ)
    }

    @Test("object lane active demotes non-object offer slices")
    func objectLaneActiveDemotesNonObjectOfferSlices() async {
        let offerID = "computer-offer"
        let sharedText = "macbook pro computer laptop"
        let objectDoc = makeRankingDocument(
            id: "offer-object::\(offerID)",
            offerID: offerID,
            docKind: .offerObject,
            lexicalText: "macbook pro computer",
            embedding: computerEmbedding
        )
        let detailDoc = makeRankingDocument(
            id: "offer-detail::\(offerID)",
            offerID: offerID,
            docKind: .offerDetail,
            lexicalText: sharedText,
            embedding: computerEmbedding
        )
        let faqDoc = makeRankingDocument(
            id: "offer-faq::\(offerID)::q1",
            offerID: offerID,
            docKind: .offerFAQ,
            lexicalText: sharedText,
            embedding: computerEmbedding
        )

        let query = ExchangeRetrievalQuery(
            queryText: "computer",
            semanticEmbeddingText: "computer",
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            keywords: ["computer"],
            queryObjectText: "computer"
        )

        let results = await retrieve(query: query, documents: [detailDoc, faqDoc, objectDoc])
        #expect(results.first?.document.docKind == .offerObject)
    }

    @Test("object lane only offer_object proves")
    func objectLaneOnlyOfferObjectProves() {
        let thread = makeRankingThread(
            queryIntentClass: .offerSearch,
            objectType: "computer"
        )
        let match = makeRankingMatch(nodeID: "seller-1", offers: [
            makeRankingOffer(id: "computer-offer", title: "MacBook Pro", category: "computer")
        ])

        for kind in [
            ExchangeRetrievalDocument.DocKind.offerDetail,
            .offerFAQ,
            .offerPackage,
            .profileIntro,
            .profileAbout,
            .profileCapability,
            nil
        ] {
            let doc = makeRankingDocument(
                id: "doc::\(kind?.rawValue ?? "legacy")",
                offerID: kind == nil ? "computer-offer" : (kind == .offerObject ? "computer-offer" : "computer-offer"),
                docKind: kind,
                surfaceType: kind?.isProfileKind == true ? .publicProfileCapability : .offer,
                entityType: kind?.isProfileKind == true ? .publicProfile : .offer,
                lexicalText: "macbook pro computer"
            )
            #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(doc))
        }

        let objectDoc = makeRankingDocument(
            id: "offer-object::computer-offer",
            offerID: "computer-offer",
            docKind: .offerObject,
            lexicalText: "macbook pro computer",
            embedding: computerEmbedding
        )
        #expect(ExchangeOfferObjectLane.canProveOfferObjectEvidence(objectDoc))

        let projected = ExchangeRetrievalCandidateProjector().project(
            [makeRankingCandidate(document: objectDoc, score: 0.9, objectEvidenceScore: 0.95)],
            knownMatches: [match],
            thread: thread
        )
        #expect(projected.first?.provenObjectOfferIDs == ["computer-offer"])
    }

    @Test("profile intro dominant surface is not affinity")
    func profileIntroDominantSurfaceNotAffinity() {
        let introDoc = makeRankingDocument(
            id: "profile-intro::seller-1",
            docKind: .profileIntro,
            surfaceType: .publicProfile,
            entityType: .publicProfile,
            lexicalText: "multi seller headline"
        )
        let thread = makeRankingThread(queryIntentClass: .providerSearch, objectType: nil)
        let match = makeRankingMatch(nodeID: "seller-1", offers: [])

        let projected = ExchangeRetrievalCandidateProjector().project(
            [makeRankingCandidate(document: introDoc, score: 0.5)],
            knownMatches: [match],
            thread: thread
        )

        #expect(projected.first?.dominantSurface != .affinity)
        #expect(projected.first?.dominantSurface == .capability)
    }

    @Test("per-offer slice cap reduces FAQ spam")
    func perOfferSliceCapReducesFAQSpam() {
        let offerID = "offer-1"
        let faqA = makeRankingCandidate(
            document: makeRankingDocument(
                id: "offer-faq::\(offerID)::a",
                offerID: offerID,
                docKind: .offerFAQ,
                lexicalText: "faq a"
            ),
            score: 0.80
        )
        let faqB = makeRankingCandidate(
            document: makeRankingDocument(
                id: "offer-faq::\(offerID)::b",
                offerID: offerID,
                docKind: .offerFAQ,
                lexicalText: "faq b"
            ),
            score: 0.75
        )
        let package = makeRankingCandidate(
            document: makeRankingDocument(
                id: "offer-package::\(offerID)::std",
                offerID: offerID,
                docKind: .offerPackage,
                lexicalText: "package"
            ),
            score: 0.70
        )

        let capped = ExchangeRetrievalEngine.applyPerOfferSliceCap([faqA, faqB, package])
        let commercialAux = capped.filter {
            $0.document.docKind == .offerFAQ || $0.document.docKind == .offerPackage
        }
        #expect(commercialAux.count == 1)
        #expect(commercialAux.first?.document.id == faqA.document.id)
    }

    @Test("profile docs never attach offers under object lane")
    func profileDocsNeverAttachUnderObjectLane() {
        let thread = makeRankingThread(
            queryIntentClass: .offerSearch,
            objectType: "computer"
        )
        let offer = makeRankingOffer(id: "computer-offer", title: "MacBook Pro", category: "computer")
        let match = makeRankingMatch(nodeID: "seller-1", offers: [offer])

        for kind in [ExchangeRetrievalDocument.DocKind.profileIntro, .profileAbout, .profileCapability] {
            let doc = makeRankingDocument(
                id: "profile::\(kind.rawValue)",
                offerID: nil,
                docKind: kind,
                surfaceType: kind == .profileIntro ? .publicProfile : .publicProfileCapability,
                entityType: .publicProfile,
                lexicalText: "electronics seller macbook pro computer"
            )
            let projected = ExchangeRetrievalCandidateProjector().project(
                [makeRankingCandidate(document: doc, score: 0.95, objectEvidenceScore: nil)],
                knownMatches: [match],
                thread: thread
            )
            #expect(projected.first?.matchedOffers.isEmpty == true)
        }
    }

    @Test("mixed query does not hard drop doc kinds")
    func mixedQueryNoHardDocKindDrop() async {
        let docs = [
            makeRankingDocument(id: "profile-cap::1", docKind: .profileCapability, surfaceType: .publicProfileCapability, entityType: .publicProfile, lexicalText: "retail"),
            makeRankingDocument(id: "profile-about::1", docKind: .profileAbout, surfaceType: .publicProfileCapability, entityType: .publicProfile, lexicalText: "retail"),
            makeRankingDocument(id: "offer-detail::1", offerID: "o1", docKind: .offerDetail, lexicalText: "retail"),
            makeRankingDocument(id: "offer-faq::1::q", offerID: "o1", docKind: .offerFAQ, lexicalText: "retail")
        ]

        let query = ExchangeRetrievalQuery(
            queryText: "retail",
            semanticEmbeddingText: "retail",
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            keywords: ["retail"]
        )

        let results = await retrieve(query: query, documents: docs)
        let kinds = Set(results.compactMap(\.document.docKind))
        #expect(kinds.contains(.profileCapability))
        #expect(kinds.contains(.profileAbout))
        #expect(kinds.contains(.offerDetail))
    }

    @Test("legacy nil docKind ranks without crash")
    func legacyNilDocKindUnchanged() async {
        let legacyDoc = makeRankingDocument(
            id: "offer::legacy",
            offerID: "legacy-offer",
            docKind: nil,
            lexicalText: "legacy offer text"
        )

        let query = ExchangeRetrievalQuery(
            queryText: "legacy offer",
            semanticEmbeddingText: "legacy offer",
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            keywords: ["legacy"]
        )

        let results = await retrieve(query: query, documents: [legacyDoc])
        #expect(results.count == 1)
        #expect(results.first?.document.docKind == nil)
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(legacyDoc))
    }

    @Test("docKind bias magnitudes stay within soft prior bounds")
    func docKindBiasMagnitudeBounds() {
        let queryClasses: [ExchangeIntent.QueryIntentClass] = [
            .capabilitySearch, .collaborationSearch, .providerSearch,
            .socialAffinitySearch, .relationshipSearch, .offerSearch,
            .followUp, .statusCheck, .generalDiscovery
        ]
        let docKinds = ExchangeRetrievalDocument.DocKind.allCases

        for queryClass in queryClasses {
            let objectLaneActive = queryClass == .offerSearch
            let query = ExchangeRetrievalQuery(
                queryIntentClass: queryClass,
                queryObjectText: objectLaneActive ? "computer" : nil
            )
            for docKind in docKinds {
                let bias = ExchangeRetrievalEngine.docKindBias(query: query, docKind: docKind)
                #expect(abs(bias) <= 0.08)
            }
        }
    }
}

private struct FixedRankingEmbeddingProvider: MemoryEmbeddingProvider {
    let vector: [Float]

    func embed(_ text: String) -> [Float]? {
        vector
    }
}

private let computerEmbedding: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]

private func retrieve(
    query: ExchangeRetrievalQuery,
    documents: [ExchangeRetrievalDocument]
) async -> [ExchangeRetrievalEngine.Candidate] {
    let store = ExchangeRetrievalStore()
    await store.replaceAllDocuments(documents)
    let engine = ExchangeRetrievalEngine(
        store: store,
        embeddingProvider: FixedRankingEmbeddingProvider(vector: computerEmbedding)
    )
    return await engine.retrieve(query: query, lexicalLimit: 20, vectorLimit: 20, fusedLimit: 10)
}

private func makeRankingDocument(
    id: String,
    offerID: String? = nil,
    docKind: ExchangeRetrievalDocument.DocKind?,
    surfaceType: ExchangeRetrievalDocument.SurfaceType = .offer,
    entityType: ExchangeRetrievalDocument.EntityType = .offer,
    lexicalText: String,
    providerTerms: [String] = [],
    capabilityTerms: [String] = [],
    affinityTerms: [String] = [],
    embedding: [Float]? = nil
) -> ExchangeRetrievalDocument {
    ExchangeRetrievalDocument(
        id: id,
        counterpartyID: "seller-1",
        nodeID: "seller-1",
        publicProfileID: offerID == nil ? "profile-1" : nil,
        offerID: offerID,
        entityType: entityType,
        surfaceType: surfaceType,
        sourceKind: .local,
        docKind: docKind,
        sourceField: docKind?.rawValue,
        title: lexicalText,
        lexicalText: lexicalText,
        semanticText: lexicalText,
        providerTerms: providerTerms,
        capabilityTerms: capabilityTerms,
        affinityTerms: affinityTerms,
        embedding: embedding
    )
}

private func makeRankingCandidate(
    document: ExchangeRetrievalDocument,
    score: Double,
    objectEvidenceScore: Double? = nil
) -> ExchangeRetrievalEngine.Candidate {
    ExchangeRetrievalEngine.Candidate(
        document: document,
        fusedScore: score,
        contributingSources: ["test"],
        bestRankBySource: ["test": 1],
        objectEvidenceScore: objectEvidenceScore
    )
}

private func makeRankingThread(
    queryIntentClass: ExchangeIntent.QueryIntentClass,
    objectType: String?
) -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: .product,
        objectType: objectType,
        transactionIntent: .buy,
        semanticConcepts: objectType.map { [$0] } ?? [],
        rawUserText: "test"
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: queryIntentClass,
        surfacePreference: queryIntentClass == .offerSearch ? .offer : .mixed
    )
    return ExchangeThread(
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
}

private func makeRankingOffer(
    id: String,
    title: String,
    category: String
) -> ExchangeOffer {
    ExchangeOffer(
        id: id,
        nodeID: "seller-1",
        title: title,
        category: category,
        status: .active,
        visibility: .publicDiscoverable
    )
}

private func makeRankingMatch(
    nodeID: String,
    offers: [ExchangeOffer]
) -> ExchangeDirectoryMatch {
    let counterparty = ExchangeCounterparty(
        id: nodeID,
        kind: .secretaryNode,
        displayName: "Seller",
        source: .relayNetwork,
        identity: .init(nodeID: nodeID, publicKeyID: nil, verification: .unverified),
        publicProfile: nil,
        tags: [],
        semantic: .init(),
        contactRoutes: [],
        status: .active
    )
    return ExchangeDirectoryMatch(
        counterparty: counterparty,
        offers: offers,
        reachability: .init(
            isDiscoverable: true,
            isRouteableInPrinciple: true,
            allowsDirectContactInPrinciple: true,
            requiresIntroductionInPrinciple: false,
            accessMode: .direct,
            disclosureCeiling: .balanced,
            hasRouteHint: true
        )
    )
}

private extension ExchangeRetrievalDocument.DocKind {
    var isProfileKind: Bool {
        switch self {
        case .profileIntro, .profileAbout, .profileCapability, .profileSeeking, .profileAffinity:
            return true
        default:
            return false
        }
    }
}
