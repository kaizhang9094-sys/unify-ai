import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeRetrievalDocumentContamination")
struct ExchangeRetrievalDocumentContaminationTests {
    @Test("profile capability excludes sibling offer titles from embedding text")
    func profileCapabilityExcludesSiblingOfferTitles() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let carOffer = makeContaminationOffer(
            id: "car-offer",
            title: "Selling my car",
            category: "automotive"
        )
        let computerOffer = makeContaminationOffer(
            id: "computer-offer",
            title: "MacBook Pro",
            category: "computer"
        )
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "seller-1",
            displayName: "Multi seller",
            headline: "Electronics and vehicles",
            summary: "General reseller with broad inventory",
            interests: [],
            offers: ["Selling my car", "MacBook Pro"],
            openTo: [],
            activityTags: ["reselling"],
            regionTags: ["Toronto"],
            semantic: .init(
                domains: ["retail"],
                notes: "Experienced seller"
            )
        )

        let surface = builder.build(profile: profile, offers: [carOffer, computerOffer])
        let docs = ExchangeRetrievalDocumentBuilder().build(
            from: surface,
            counterpartyID: "seller-1",
            sourceKind: .local
        )
        let introDoc = docs.first { $0.docKind == ExchangeRetrievalDocument.DocKind.profileIntro }
        let aboutDoc = docs.first { $0.docKind == ExchangeRetrievalDocument.DocKind.profileAbout }
        let capabilityDoc = docs.first { $0.docKind == ExchangeRetrievalDocument.DocKind.profileCapability }
        #expect(introDoc != nil)
        #expect(aboutDoc != nil)

        let introEmbedding = introDoc?.retrievalEmbeddingText.lowercased() ?? ""
        let aboutEmbedding = aboutDoc?.retrievalEmbeddingText.lowercased() ?? ""
        let capabilityEmbedding = capabilityDoc?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(!introEmbedding.contains("selling my car"))
        #expect(!aboutEmbedding.contains("selling my car"))
        #expect(!capabilityEmbedding.contains("selling my car"))
        #expect(!capabilityEmbedding.contains("macbook pro"))
        #expect(introEmbedding.contains("electronics and vehicles") || aboutEmbedding.contains("general reseller"))
    }

    @Test("profile capability excludes commercialFacts text from embedding text")
    func profileCapabilityExcludesCommercialFacts() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let offer = makeContaminationOffer(
            id: "computer-offer",
            title: "MacBook Pro",
            category: "computer",
            commercialFacts: .init(
                priceDisplay: "$999",
                serviceAreaNote: "Greater Toronto Area",
                availabilityNote: "Available now",
                minimumEngagement: "Financing available", warrantyPolicy: "Free delivery"
            )
        )
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "seller-1",
            displayName: "Seller",
            interests: [],
            offers: [],
            openTo: [],
            activityTags: [],
            regionTags: ["Toronto"],
            semantic: .init(domains: ["retail"])
        )

        let surface = builder.build(profile: profile, offers: [offer])
        let docs = ExchangeRetrievalDocumentBuilder().build(
            from: surface,
            counterpartyID: "seller-1",
            sourceKind: .local
        )
        let capabilityDoc = docs.first { $0.docKind == ExchangeRetrievalDocument.DocKind.profileCapability }
        #expect(capabilityDoc != nil)

        let embedding = capabilityDoc?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(!embedding.contains("$999"))
        #expect(!embedding.contains("greater toronto"))
        #expect(!embedding.contains("available now"))
        #expect(!embedding.contains("financing available"))
        #expect(!embedding.contains("free delivery"))
    }

    @Test("offer_object embedding text is identity-only")
    func offerObjectEmbeddingIdentityOnly() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let offer = makeContaminationOffer(
            id: "computer-offer",
            title: "MacBook Pro",
            category: "computer",
            tags: ["laptop"],
            serviceKinds: ["computer"],
            summary: "Great laptop with delivery available",
            regionTags: ["Toronto"],
            commercialFacts: .init(
                priceDisplay: "$999",
                serviceAreaNote: "Greater Toronto Area",
                availabilityNote: "Available now"
            )
        )
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "seller-1",
            displayName: "Electronics seller headline",
            headline: "Best deals in town",
            interests: [],
            offers: [],
            openTo: [],
            activityTags: [],
            regionTags: ["Toronto"]
        )

        let surface = builder.build(profile: profile, offers: [offer])
        let docs = ExchangeRetrievalDocumentBuilder().build(
            from: surface,
            counterpartyID: "seller-1",
            sourceKind: .local
        )
        let objectDoc = docs.first { $0.docKind == ExchangeRetrievalDocument.DocKind.offerObject }
        #expect(objectDoc != nil)

        let embedding = objectDoc?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(embedding.contains("macbook pro"))
        #expect(embedding.contains("computer"))
        #expect(embedding.contains("laptop"))
        #expect(!embedding.contains("great laptop"))
        #expect(!embedding.contains("toronto"))
        #expect(!embedding.contains("$999"))
        #expect(!embedding.contains("available"))
        #expect(!embedding.contains("electronics seller"))
        #expect(!embedding.contains("best deals"))
    }

    @Test("offer_detail embedding excludes logistics metadata")
    func offerDetailEmbeddingExcludesLogistics() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let offer = makeContaminationOffer(
            id: "computer-offer",
            title: "MacBook Pro",
            category: "computer",
            summary: "Refurbished laptop in excellent condition",
            regionTags: ["Toronto"],
            commercialFacts: .init(
                priceDisplay: "$999",
                packages: [
                    .init(title: "Standard", summary: "Includes charger", priceDisplay: "$999")
                ],
                serviceAreaNote: "Greater Toronto Area",
                availabilityNote: "Available now"
            ),
            leadTimeNote: "Ships in 2 days",
            capacityNote: "Limited stock"
        )
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "seller-1",
            displayName: "Seller",
            interests: [],
            offers: [],
            openTo: [],
            activityTags: [],
            regionTags: ["Toronto"]
        )

        let surface = builder.build(profile: profile, offers: [offer])
        let docs = ExchangeRetrievalDocumentBuilder().build(
            from: surface,
            counterpartyID: "seller-1",
            sourceKind: .local
        )
        let detailDoc = docs.first { $0.docKind == ExchangeRetrievalDocument.DocKind.offerDetail }
        #expect(detailDoc != nil)

        let packageDoc = docs.first { $0.docKind == ExchangeRetrievalDocument.DocKind.offerPackage }
        #expect(packageDoc != nil)

        let embedding = detailDoc?.retrievalEmbeddingText.lowercased() ?? ""
        let packageEmbedding = packageDoc?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(embedding.contains("macbook pro"))
        #expect(embedding.contains("refurbished laptop"))
        #expect(!embedding.contains("includes charger"))
        #expect(packageEmbedding.contains("includes charger"))
        #expect(!packageEmbedding.contains("$999"))
        #expect(!embedding.contains("$999"))
        #expect(!embedding.contains("price:"))
        #expect(!embedding.contains("toronto"))
        #expect(!embedding.contains("greater toronto"))
        #expect(!embedding.contains("available now"))
        #expect(!embedding.contains("ships in 2 days"))
        #expect(!embedding.contains("limited stock"))
        #expect(!embedding.contains("service area"))
    }

    @Test("broad searchableText does not make non-offer_object docs prove object evidence")
    func searchableTextDoesNotProveObjectEvidence() {
        let detailDoc = makeContaminationRetrievalDocument(
            id: "offer::computer-offer",
            offerID: "computer-offer",
            docKind: .offerDetail,
            title: "MacBook Pro",
            category: "computer",
            summary: "computer laptop",
            lexicalText: "MacBook Pro computer laptop Toronto $999 Available now",
            semanticText: "computer laptop"
        )
        #expect(!detailDoc.searchableText.isEmpty)
        #expect(detailDoc.searchableText.localizedCaseInsensitiveContains("Toronto"))
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(detailDoc))

        let capabilityDoc = makeContaminationRetrievalDocument(
            id: "profile-capability::profile-1",
            offerID: nil,
            docKind: .profileCapability,
            surfaceType: .publicProfileCapability,
            entityType: .publicProfile,
            title: "Seller",
            lexicalText: "Seller MacBook Pro computer car automotive",
            semanticText: "MacBook Pro computer"
        )
        #expect(!capabilityDoc.searchableText.isEmpty)
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(capabilityDoc))
    }

    @Test("legacy docs without docKind decode safely but cannot prove object evidence")
    func legacyDocsBackwardCompatible() throws {
        let legacy = ExchangeRetrievalDocument(
            id: "offer::legacy",
            counterpartyID: "seller-1",
            nodeID: "seller-1",
            offerID: "legacy-offer",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .local,
            title: "Legacy offer",
            lexicalText: "Legacy offer",
            semanticText: "Legacy offer"
        )
        #expect(legacy.docKind == nil)

        let encoded = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(ExchangeRetrievalDocument.self, from: encoded)
        #expect(decoded.docKind == nil)
        #expect(decoded.offerID == "legacy-offer")
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(decoded))
        #expect(!decoded.retrievalEmbeddingText.isEmpty)
    }

    @Test("publication round trip preserves docKind sourceField and offerID")
    func publicationRoundTripPreservesProvenanceFields() throws {
        let document = ExchangeRetrievalDocument(
            id: "offer-object::computer-offer",
            counterpartyID: "seller-1",
            nodeID: "seller-1",
            publicProfileID: "profile-1",
            offerID: "computer-offer",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .local,
            docKind: .offerObject,
            sourceField: "offer_object",
            title: "MacBook Pro",
            category: "computer",
            lexicalText: "MacBook Pro computer",
            semanticText: "computer"
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(ExchangeRetrievalDocument.self, from: encoded)
        #expect(decoded.docKind == ExchangeRetrievalDocument.DocKind.offerObject)
        #expect(decoded.sourceField == "offer_object")
        #expect(decoded.offerID == "computer-offer")
    }
}

private func makeContaminationOffer(
    id: String,
    title: String,
    category: String,
    tags: [String] = [],
    serviceKinds: [String] = [],
    summary: String? = nil,
    regionTags: [String] = [],
    commercialFacts: ExchangeOffer.CommercialFacts = .empty,
    leadTimeNote: String? = nil,
    capacityNote: String? = nil
) -> ExchangeOffer {
    var fulfillment = ExchangeOffer.Fulfillment(
        pricingMode: .fixed,
        commitmentMode: .exploratory,
        remoteFriendly: true
    )
    fulfillment.leadTimeNote = leadTimeNote
    fulfillment.capacityNote = capacityNote

    return ExchangeOffer(
        id: id,
        nodeID: "seller-1",
        title: title,
        summary: summary,
        category: category,
        tags: tags,
        regionTags: regionTags,
        semantic: .init(serviceKinds: serviceKinds),
        fulfillment: fulfillment,
        status: .active,
        visibility: .publicDiscoverable,
        commercialFacts: commercialFacts
    )
}

private func makeContaminationRetrievalDocument(
    id: String,
    offerID: String?,
    docKind: ExchangeRetrievalDocument.DocKind?,
    surfaceType: ExchangeRetrievalDocument.SurfaceType = .offer,
    entityType: ExchangeRetrievalDocument.EntityType = .offer,
    title: String,
    category: String? = nil,
    summary: String? = nil,
    lexicalText: String,
    semanticText: String
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
        title: title,
        summary: summary,
        category: category,
        lexicalText: lexicalText,
        semanticText: semanticText
    )
}

@Suite("ExchangeFederationRetrievalProvenance")
struct ExchangeFederationRetrievalProvenanceTests {
    @Test("RemoteDirectoryRow decodes retrievalHits with docKind and sourceField")
    func remoteDirectoryRowDecodesRetrievalHits() throws {
        let json = """
        {
          "nodeID": "seller-1",
          "displayName": "Seller",
          "publicProfile": {
            "id": "profile-1",
            "nodeID": "seller-1",
            "displayName": "Seller",
            "visibility": "discoverable",
            "availability": "open",
            "interests": [],
            "offers": [],
            "openTo": [],
            "activityTags": [],
            "regionTags": []
          },
          "offers": [],
          "retrievalDocuments": [{
            "id": "offer-object::computer-offer",
            "counterpartyID": "seller-1",
            "nodeID": "seller-1",
            "publicProfileID": "profile-1",
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
          }],
          "retrievalHits": [{
            "retrievalDocID": "offer-object::computer-offer",
            "docKind": "offer_object",
            "sourceField": "offer_object",
            "surfaceType": "offer",
            "entityType": "offer",
            "offerID": "computer-offer",
            "publicProfileID": "profile-1",
            "lexicalScore": 12.5,
            "vectorSimilarity": 0.88,
            "retrievalScore": 100.5,
            "matchedTerms": ["macbook"]
          }]
        }
        """
        struct DirectoryRowProbe: Decodable {
            let retrievalDocuments: [ExchangeRetrievalDocument]
            let retrievalHits: [ExchangeDirectoryRetrievalHit]
        }
        let row = try JSONDecoder().decode(
            DirectoryRowProbe.self,
            from: Data(json.utf8)
        )
        #expect(row.retrievalDocuments.count == 1)
        #expect(row.retrievalDocuments[0].docKind == ExchangeRetrievalDocument.DocKind.offerObject)
        #expect(row.retrievalDocuments[0].sourceField == "offer_object")
        #expect(row.retrievalHits.count == 1)
        #expect(row.retrievalHits[0].docKind == ExchangeRetrievalDocument.DocKind.offerObject)
        #expect(row.retrievalHits[0].sourceField == "offer_object")
        #expect(row.retrievalHits[0].offerID == "computer-offer")
    }

    @Test("ingest preserves remote docKind through directory match documents")
    func ingestPreservesRemoteDocKind() async {
        let document = ExchangeRetrievalDocument(
            id: "offer-object::computer-offer",
            counterpartyID: "seller-1",
            nodeID: "seller-1",
            publicProfileID: "profile-1",
            offerID: "computer-offer",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .remote,
            docKind: .offerObject,
            sourceField: "offer_object",
            title: "MacBook Pro",
            category: "computer",
            lexicalText: "MacBook Pro computer",
            semanticText: "computer"
        )
        let counterparty = ExchangeCounterparty(
            id: "seller-1",
            kind: .secretaryNode,
            displayName: "Seller",
            source: .relayNetwork,
            identity: .init(nodeID: "seller-1", publicKeyID: nil, verification: .unverified),
            publicProfile: nil,
            tags: [],
            semantic: .init(),
            contactRoutes: [],
            status: .active
        )
        let match = ExchangeDirectoryMatch(
            counterparty: counterparty,
            offers: [],
            retrievalDocuments: [document],
            reachability: .init(
                isDiscoverable: true,
                isRouteableInPrinciple: true,
                allowsDirectContactInPrinciple: true,
                requiresIntroductionInPrinciple: false,
                accessMode: .direct,
                disclosureCeiling: .balanced,
                hasRouteHint: true
            ),
            retrievalHits: [
                ExchangeDirectoryRetrievalHit(
                    retrievalDocID: document.id,
                    docKind: .offerObject,
                    sourceField: "offer_object",
                    offerID: "computer-offer"
                )
            ]
        )

        let store = ExchangeRetrievalStore()
        let ingestor = ExchangeRetrievalIngestor(store: store, embeddingProvider: ExchangeNoOpEmbeddingProvider())
        await ingestor.ingestDirectoryMatches([match], sourceKind: .remote)

        let stored = await store.listDocuments()
        #expect(stored.count == 1)
        #expect(stored[0].docKind == .offerObject)
        #expect(stored[0].sourceField == "offer_object")
        #expect(stored[0].offerID == "computer-offer")
    }

    @Test("remote docKind nil cannot prove object evidence")
    func remoteNilDocKindCannotProveObjectEvidence() {
        let document = ExchangeRetrievalDocument(
            id: "offer::legacy",
            counterpartyID: "seller-1",
            nodeID: "seller-1",
            offerID: "legacy-offer",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .remote,
            title: "Legacy offer",
            category: "computer",
            lexicalText: "computer"
        )
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(document))
    }

    @Test("remote offer_object without embedding cannot prove object evidence")
    func remoteOfferObjectWithoutEmbeddingCannotProveObjectEvidence() {
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
            lexicalText: "MacBook Pro computer"
        )
        let score = ExchangeOfferObjectLane.objectEvidenceScore(
            queryEmbedding: [1, 0, 0, 0],
            document: document
        )
        #expect(score == nil)
        #expect(!ExchangeOfferObjectLane.canAttachOfferFromProvenance(document: document, objectEvidenceScore: score))
    }
}

private struct ExchangeNoOpEmbeddingProvider: MemoryEmbeddingProvider {
    func embed(_ text: String) -> [Float]? { nil }
}
