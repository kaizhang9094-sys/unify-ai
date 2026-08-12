import Foundation
import Testing
@testable import AnumCore

private let rerankComputerEmbedding: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
private let rerankCarEmbedding: [Float] = [0, 1, 0, 0, 0, 0, 0, 0]

@Suite("ExchangeFederationClientRerank")
struct ExchangeFederationClientRerankTests {
    @Test("hybrid directory search request encodes clientRerank mode")
    func hybridSearchRequestsClientRerankMode() throws {
        let request = ExchangeDirectorySearchRequest(
            mode: .transactional,
            intentKind: .find,
            queryText: "macbook computer",
            retrievalResponseMode: .clientRerank
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mode = json?["retrievalResponseMode"] as? String
        #expect(mode == "clientRerank")
    }

    @Test("remote candidate docs decode embeddings and provenance")
    func remoteCandidateDocsDecodeEmbeddingsAndProvenance() throws {
        let json = """
        {
          "retrievalDocuments": [{
            "id": "offer-object::computer-offer",
            "counterpartyID": "seller-1",
            "nodeID": "seller-1",
            "offerID": "computer-offer",
            "entityType": "offer",
            "surfaceType": "offer",
            "sourceKind": "remote",
            "docKind": "offer_object",
            "sourceField": "offer_object",
            "title": "MacBook Pro",
            "tags": [],
            "regionTags": [],
            "canonicalRegionIDs": [],
            "regionAliases": [],
            "parentRegionIDs": [],
            "serviceAreas": [],
            "primaryText": "MacBook Pro",
            "secondaryText": "",
            "lexicalText": "MacBook Pro computer",
            "semanticText": "computer",
            "providerTerms": [],
            "capabilityTerms": [],
            "affinityTerms": [],
            "filterTokens": [],
            "embedding": [1, 0, 0, 0]
          }],
          "retrievalHits": [{
            "retrievalDocID": "offer-object::computer-offer",
            "nodeID": "seller-1",
            "docKind": "offer_object",
            "sourceField": "offer_object",
            "offerID": "computer-offer",
            "embedding": [1, 0, 0, 0],
            "lexicalScore": 10,
            "retrievalScore": 20
          }],
          "candidateOfferIDsFromDocs": ["computer-offer"]
        }
        """
        struct Probe: Decodable {
            let retrievalDocuments: [ExchangeRetrievalDocument]
            let retrievalHits: [ExchangeDirectoryRetrievalHit]
            let candidateOfferIDsFromDocs: [String]
        }
        let probe = try JSONDecoder().decode(Probe.self, from: Data(json.utf8))
        #expect(probe.retrievalDocuments[0].docKind == .offerObject)
        #expect(probe.retrievalDocuments[0].hasEmbedding)
        #expect(probe.retrievalHits[0].embedding == [1, 0, 0, 0])
        #expect(probe.candidateOfferIDsFromDocs == ["computer-offer"])
    }

    @Test("remote offer_object docs flow into local object lane scoring after ingest")
    func remoteOfferObjectDocsFlowIntoObjectLaneScoring() async {
        let document = ExchangeRetrievalDocument(
            id: "offer-object::computer-offer",
            counterpartyID: "seller-1",
            nodeID: "seller-1",
            offerID: "computer-offer",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .remote,
            docKind: .offerObject,
            sourceField: "offer_object",
            title: "MacBook Pro",
            category: "computer",
            lexicalText: "MacBook Pro computer",
            semanticText: "computer",
            embedding: rerankComputerEmbedding
        )
        let match = makeRemoteDirectoryMatch(
            nodeID: "seller-1",
            offers: [makeRemoteOffer(id: "computer-offer", title: "MacBook Pro", category: "computer")],
            retrievalDocuments: [document],
            candidateOfferIDsFromDocs: ["computer-offer"]
        )

        let store = ExchangeRetrievalStore()
        let ingestor = ExchangeRetrievalIngestor(
            store: store,
            embeddingProvider: RerankNoOpEmbeddingProvider()
        )
        await ingestor.ingestDirectoryMatches([match], sourceKind: .remote)

        let hits = ExchangeOfferObjectLane.rankOfferObjectDocuments(
            queryEmbedding: rerankComputerEmbedding,
            documents: await store.listDocuments(),
            limit: 5
        )
        #expect(hits.count == 1)
        #expect(hits[0].documentID == document.id)
        #expect(hits[0].score >= ExchangeOfferObjectLane.minimumObjectEvidenceScore)
    }

    @Test("remote car and computer node proves computer only through client object lane")
    func remoteCarAndComputerNodeProvesComputerOnly() {
        let thread = makeRemoteObjectThread(objectType: "computer")
        let carOffer = makeRemoteOffer(id: "car-offer", title: "Honda Civic", category: "automotive")
        let computerOffer = makeRemoteOffer(id: "computer-offer", title: "MacBook Pro", category: "computer")
        let match = makeRemoteDirectoryMatch(
            nodeID: "seller-1",
            offers: [carOffer, computerOffer],
            retrievalDocuments: [
                makeRemoteRetrievalDocument(
                    id: "offer-object::computer-offer",
                    offerID: "computer-offer",
                    docKind: .offerObject,
                    title: "MacBook Pro",
                    category: "computer",
                    embedding: rerankComputerEmbedding
                ),
                makeRemoteRetrievalDocument(
                    id: "offer-object::car-offer",
                    offerID: "car-offer",
                    docKind: .offerObject,
                    title: "Honda Civic",
                    category: "automotive",
                    embedding: rerankCarEmbedding
                )
            ],
            candidateOfferIDsFromDocs: ["computer-offer", "car-offer"]
        )

        let computerDoc = match.retrievalDocuments.first { $0.id == "offer-object::computer-offer" }
        let carDoc = match.retrievalDocuments.first { $0.id == "offer-object::car-offer" }
        #expect(computerDoc != nil)
        #expect(carDoc != nil)

        let computerScore = ExchangeOfferObjectLane.objectEvidenceScore(
            queryEmbedding: rerankComputerEmbedding,
            document: computerDoc!
        )
        let carScore = ExchangeOfferObjectLane.objectEvidenceScore(
            queryEmbedding: rerankComputerEmbedding,
            document: carDoc!
        )
        #expect(computerScore != nil)
        #expect(carScore != nil)
        #expect(computerScore ?? 0 >= ExchangeOfferObjectLane.minimumObjectEvidenceScore)
        #expect((carScore ?? 1) < ExchangeOfferObjectLane.minimumObjectEvidenceScore)

        let projected = ExchangeRetrievalCandidateProjector().project(
            [
                makeRemoteCandidate(
                    document: computerDoc!,
                    objectEvidenceScore: computerScore
                ),
                makeRemoteCandidate(
                    document: carDoc!,
                    objectEvidenceScore: carScore
                )
            ],
            knownMatches: [match],
            thread: thread
        )

        let computerHit = projected.first { $0.matchedOffers.contains(where: { $0.id == "computer-offer" }) }
        #expect(computerHit != nil)
        #expect(computerHit?.matchedOffers.count == 1)
        #expect(
            ExchangeOfferObjectLane.resolveSelectedOfferID(
                provenObjectOfferIDs: computerHit?.provenObjectOfferIDs ?? [],
                objectEvidenceScoreByOfferID: computerHit?.objectEvidenceScoreByOfferID ?? [:]
            ) == "computer-offer"
        )
        #expect(projected.allSatisfy { !$0.matchedOffers.contains(where: { $0.id == "car-offer" }) })
        #expect(match.candidateOfferIDsFromDocs.contains("computer-offer"))
        #expect(match.candidateOfferIDsFromDocs.contains("car-offer"))
        #expect(match.offers.count == 2)
    }

    @Test("profile-only remote hit keeps provider candidate without matched offer")
    func profileOnlyRemoteHitKeepsProviderWithoutMatchedOffer() {
        let thread = makeRemoteObjectThread(objectType: "computer")
        let carOffer = makeRemoteOffer(id: "car-offer", title: "Honda Civic", category: "automotive")
        let match = makeRemoteDirectoryMatch(
            nodeID: "seller-1",
            offers: [carOffer],
            retrievalDocuments: [
                makeRemoteRetrievalDocument(
                    id: "profile-capability::seller-1",
                    offerID: nil,
                    docKind: .profileCapability,
                    surfaceType: .publicProfileCapability,
                    entityType: .publicProfile,
                    title: "Electronics shop",
                    category: "electronics"
                )
            ],
            candidateOfferIDsFromDocs: []
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [makeRemoteCandidate(document: match.retrievalDocuments[0], objectEvidenceScore: nil)],
            knownMatches: [match],
            thread: thread
        )

        #expect(projected.count == 1)
        #expect(projected[0].matchedOffers.isEmpty)
        #expect(projected[0].provenObjectOfferIDs.isEmpty)
        #expect(
            ExchangeOfferObjectLane.resolveSelectedOfferID(
                provenObjectOfferIDs: projected[0].provenObjectOfferIDs,
                objectEvidenceScoreByOfferID: projected[0].objectEvidenceScoreByOfferID
            ) == nil
        )
    }

    @Test("client rerank path does not add token overlap or taxonomy helpers")
    func clientRerankPathDoesNotAddTokenOverlapOrTaxonomy() {
        let sources = [
            String(describing: ExchangeHTTPDirectoryClient.self),
            String(describing: ExchangeDiscoveryEngine.self),
            String(describing: ExchangeRetrievalIngestor.self)
        ]
        for source in sources {
            #expect(!source.localizedCaseInsensitiveContains("tokenOverlapGate"))
            #expect(!source.localizedCaseInsensitiveContains("genericWordList"))
            #expect(!source.localizedCaseInsensitiveContains("computerCarSpecialCase"))
        }
        #expect(ExchangeOfferObjectLane.canProveOfferObjectEvidence(
            ExchangeRetrievalDocument(
                id: "offer::legacy",
                counterpartyID: "seller-1",
                nodeID: "seller-1",
                offerID: "legacy",
                entityType: .offer,
                surfaceType: .offer,
                sourceKind: .remote,
                title: "Legacy",
                category: "computer",
                lexicalText: "computer"
            )
        ) == false)
    }
}

private struct RerankNoOpEmbeddingProvider: MemoryEmbeddingProvider {
    func embed(_ text: String) -> [Float]? { nil }
}

private func makeRemoteObjectThread(objectType: String) -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: .product,
        objectType: objectType,
        transactionIntent: .buy,
        semanticConcepts: [],
        rawUserText: "test"
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer
    )
    return ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .offerSearch,
            title: "test",
            objective: "test"
        ),
        posture: ExchangePosture(),
        facets: facets,
        state: .searching(.init())
    )
}

private func makeRemoteOffer(id: String, title: String, category: String) -> ExchangeOffer {
    ExchangeOffer(
        id: id,
        nodeID: "seller-1",
        title: title,
        summary: title,
        category: category,
        tags: [],
        regionTags: [],
        semantic: .init(),
        status: .active,
        visibility: .publicDiscoverable,
        commercialFacts: .empty
    )
}

private func makeRemoteRetrievalDocument(
    id: String,
    offerID: String?,
    docKind: ExchangeRetrievalDocument.DocKind?,
    surfaceType: ExchangeRetrievalDocument.SurfaceType = .offer,
    entityType: ExchangeRetrievalDocument.EntityType = .offer,
    title: String,
    category: String,
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
        sourceKind: .remote,
        docKind: docKind,
        sourceField: docKind?.rawValue,
        title: title,
        category: category,
        lexicalText: title,
        semanticText: category,
        embedding: embedding
    )
}

private func makeRemoteDirectoryMatch(
    nodeID: String,
    offers: [ExchangeOffer],
    retrievalDocuments: [ExchangeRetrievalDocument],
    candidateOfferIDsFromDocs: [String]
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
        retrievalDocuments: retrievalDocuments,
        reachability: .init(
            isDiscoverable: true,
            isRouteableInPrinciple: true,
            allowsDirectContactInPrinciple: true,
            requiresIntroductionInPrinciple: false,
            accessMode: .direct,
            disclosureCeiling: .balanced,
            hasRouteHint: true
        ),
        retrievalHits: retrievalDocuments.map { doc in
            ExchangeDirectoryRetrievalHit(
                retrievalDocID: doc.id,
                nodeID: nodeID,
                docKind: doc.docKind,
                sourceField: doc.sourceField,
                offerID: doc.offerID,
                embedding: doc.embedding
            )
        },
        candidateOfferIDsFromDocs: candidateOfferIDsFromDocs
    )
}

private func makeRemoteCandidate(
    document: ExchangeRetrievalDocument,
    objectEvidenceScore: Double?
) -> ExchangeRetrievalEngine.Candidate {
    ExchangeRetrievalEngine.Candidate(
        document: document,
        fusedScore: objectEvidenceScore ?? 0.5,
        contributingSources: ["test"],
        bestRankBySource: ["test": 1],
        objectEvidenceScore: objectEvidenceScore
    )
}
