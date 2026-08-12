import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeOfferObjectLane")
struct ExchangeOfferObjectLaneTests {

    @Test("product object offer search normalizes hire to buy and activates object lane")
    func productObjectHireNormalizesToBuy() {
        var canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .product,
            objectType: "computer",
            transactionIntent: .hire,
            rawUserText: "find me a computer under 500 tomorrow"
        )
        canonical = ExchangeOfferObjectLane.normalizeProductObjectTransactionForLiveInterpretation(
            canonical,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            source: "unitTest"
        )
        #expect(canonical.transactionIntent == .buy)
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: canonical.domainCategory,
            transactionIntent: canonical.transactionIntent,
            objectType: canonical.objectType,
            rawUserText: canonical.rawUserText ?? "test"
        )
        #expect(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
    }

    @Test("cleaner service request does not activate product object lane")
    func cleanerServiceDoesNotActivateObjectLane() {
        let thread = makeThread(
            queryIntentClass: .providerSearch,
            domainCategory: .homeService,
            transactionIntent: .hire,
            objectType: "cleaner",
            semanticConcepts: ["cleaning"]
        )
        #expect(!ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
    }

    @Test("projected offer aggregation keeps best match per node without sibling union")
    func projectedOfferAggregationKeepsBestMatchPerNode() {
        let nodeID = "node-multi-seller"
        let computer = ExchangeMatch(
            threadID: UUID(),
            counterpartyID: nodeID,
            scope: .offer,
            offerID: "offer-multi-computer",
            matchedOfferIDs: ["offer-multi-computer"],
            status: .candidate,
            strength: .strong,
            score: 0.95
        )
        let car = ExchangeMatch(
            threadID: UUID(),
            counterpartyID: nodeID,
            scope: .offer,
            offerID: "offer-multi-car",
            matchedOfferIDs: ["offer-multi-car"],
            status: .candidate,
            strength: .moderate,
            score: 0.70
        )
        let aggregated = ExchangeDebugProjectionMerge.aggregateProjectedOffersByNode(from: [computer, car])
        #expect(aggregated[nodeID] == ["offer-multi-computer"])
    }

    @Test("object lane activates only for concrete product offer searches")
    func objectLaneActivation() {
        let active = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        #expect(ExchangeOfferObjectLane.isObjectLaneActive(thread: active))
        #expect(ExchangeOfferObjectLane.queryObjectText(thread: active) == "computer")

        let provider = makeThread(
            queryIntentClass: .providerSearch,
            domainCategory: .professionalService,
            transactionIntent: .hire,
            objectType: nil,
            semanticConcepts: ["plumber"]
        )
        #expect(!ExchangeOfferObjectLane.isObjectLaneActive(thread: provider))
    }

    @Test("query object text uses canonical intent fields only")
    func queryObjectTextUsesCanonicalFields() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "laptop",
            semanticConcepts: ["computer", "laptop"],
            rawUserText: "I want to buy a cheap computer near me"
        )
        let text = ExchangeOfferObjectLane.queryObjectText(thread: thread)
        #expect(text == "laptop")
    }

    @Test("legacy offer docs cannot prove offer object evidence")
    func legacyOfferDocsCannotProveObjectEvidence() {
        let legacy = makeRetrievalDocument(
            id: "offer::car",
            offerID: "car-offer",
            docKind: nil
        )
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(legacy))

        let detail = makeRetrievalDocument(
            id: "offer::car",
            offerID: "car-offer",
            docKind: .offerDetail
        )
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(detail))
    }

    @Test("computer query against car-only node does not attach offers")
    func computerQueryAgainstCarOnlyNode() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let carOffer = makeOffer(id: "car-offer", title: "Selling my car", category: "automotive")
        let match = makeMatch(nodeID: "seller-1", offers: [carOffer])

        let carObjectDoc = makeRetrievalDocument(
            id: "offer-object::car-offer",
            offerID: "car-offer",
            docKind: .offerObject,
            title: "Selling my car",
            category: "automotive",
            embedding: carEmbedding
        )
        let profileDoc = makeRetrievalDocument(
            id: "profile::seller-1",
            offerID: nil,
            docKind: .profileCapability,
            surfaceType: .publicProfileCapability,
            entityType: .publicProfile,
            title: "Electronics seller"
        )

        let projector = ExchangeRetrievalCandidateProjector()
        let projected = projector.project(
            [
                makeCandidate(document: carObjectDoc, objectEvidenceScore: 0.05),
                makeCandidate(document: profileDoc, objectEvidenceScore: nil)
            ],
            knownMatches: [match],
            thread: thread
        )

        #expect(projected.count == 2)
        for candidate in projected {
            #expect(candidate.matchedOffers.isEmpty)
        }
    }

    @Test("computer query against car and computer offers attaches only computer")
    func computerQueryAgainstMixedOffers() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let carOffer = makeOffer(id: "car-offer", title: "Selling my car", category: "automotive")
        let computerOffer = makeOffer(id: "computer-offer", title: "MacBook Pro", category: "computer")
        let match = makeMatch(nodeID: "seller-1", offers: [carOffer, computerOffer])

        let computerObjectDoc = makeRetrievalDocument(
            id: "offer-object::computer-offer",
            offerID: "computer-offer",
            docKind: .offerObject,
            title: "MacBook Pro",
            category: "computer",
            embedding: computerEmbedding
        )
        let carObjectDoc = makeRetrievalDocument(
            id: "offer-object::car-offer",
            offerID: "car-offer",
            docKind: .offerObject,
            title: "Selling my car",
            category: "automotive",
            embedding: carEmbedding
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [
                makeCandidate(document: computerObjectDoc, objectEvidenceScore: 0.98),
                makeCandidate(document: carObjectDoc, objectEvidenceScore: 0.05)
            ],
            knownMatches: [match],
            thread: thread
        )

        let computerHit = projected.first { $0.matchedOffers.contains(where: { $0.id == "computer-offer" }) }
        #expect(computerHit != nil)
        #expect(computerHit?.matchedOffers.count == 1)
        #expect(computerHit?.matchedOffers.first?.id == "computer-offer")

        let carHit = projected.first { $0.matchedOffers.contains(where: { $0.id == "car-offer" }) }
        #expect(carHit == nil)
    }

    @Test("car query attaches car offer through offer_object doc")
    func carQueryAttachesCarOffer() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "car"
        )
        let carOffer = makeOffer(id: "car-offer", title: "Selling my car", category: "automotive")
        let match = makeMatch(nodeID: "seller-1", offers: [carOffer])
        let carObjectDoc = makeRetrievalDocument(
            id: "offer-object::car-offer",
            offerID: "car-offer",
            docKind: .offerObject,
            title: "Selling my car",
            category: "automotive",
            embedding: carEmbedding
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [makeCandidate(document: carObjectDoc, objectEvidenceScore: 0.95)],
            knownMatches: [match],
            thread: thread
        )

        #expect(projected.count == 1)
        #expect(projected[0].matchedOffers.map(\.id) == ["car-offer"])
    }

    @Test("profile-only hit does not attach sibling offers for concrete object search")
    func profileOnlyHitDoesNotAttachSiblingOffers() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let carOffer = makeOffer(id: "car-offer", title: "Selling my car", category: "automotive")
        let match = makeMatch(nodeID: "seller-1", offers: [carOffer])
        let profileDoc = makeRetrievalDocument(
            id: "profile::seller-1",
            offerID: nil,
            docKind: .profileCapability,
            surfaceType: .publicProfileCapability,
            entityType: .publicProfile,
            title: "Electronics and cars"
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [makeCandidate(document: profileDoc, objectEvidenceScore: nil)],
            knownMatches: [match],
            thread: thread
        )

        #expect(projected.count == 1)
        #expect(projected[0].matchedOffers.isEmpty)
    }

    @Test("offer_detail hit without offer_object hit does not select offer")
    func offerDetailWithoutOfferObjectDoesNotAttach() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let carOffer = makeOffer(id: "car-offer", title: "Selling my car", category: "automotive")
        let match = makeMatch(nodeID: "seller-1", offers: [carOffer])
        let detailDoc = makeRetrievalDocument(
            id: "offer::car-offer",
            offerID: "car-offer",
            docKind: .offerDetail,
            title: "Selling my car",
            category: "automotive"
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [makeCandidate(document: detailDoc, objectEvidenceScore: nil)],
            knownMatches: [match],
            thread: thread
        )

        #expect(projected.count == 1)
        #expect(projected[0].matchedOffers.isEmpty)
    }

    @Test("selected offer id resolves only from matched offer object hits")
    func selectedOfferIDRequiresObjectLaneMatch() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )

        let unprovenMatch = makeExchangeMatch(
            counterpartyID: "seller-1",
            offerID: "car-offer",
            matchedOfferIDs: ["car-offer"],
            strength: .weak
        )
        #expect(ExchangeOfferObjectLane.resolveSelectedOfferID(from: unprovenMatch, thread: thread) == nil)

        let matched = makeExchangeMatch(
            counterpartyID: "seller-1",
            offerID: "computer-offer",
            matchedOfferIDs: ["computer-offer"],
            provenObjectOfferIDs: ["computer-offer"],
            objectEvidenceScoreByOfferID: ["computer-offer": 0.95],
            strength: .strong
        )
        #expect(
            ExchangeOfferObjectLane.resolveSelectedOfferID(from: matched, thread: thread) == "computer-offer"
        )
    }

    @Test("broad provider search is not blocked by offer object lane")
    func broadProviderSearchUnblocked() {
        let thread = makeThread(
            queryIntentClass: .providerSearch,
            domainCategory: .professionalService,
            transactionIntent: .hire,
            objectType: nil,
            semanticConcepts: ["coder"]
        )
        #expect(!ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))

        let offer = makeOffer(id: "coding-offer", title: "Software development", category: "coding")
        let match = makeMatch(nodeID: "coder-1", offers: [offer])
        let detailDoc = makeRetrievalDocument(
            id: "offer::coding-offer",
            offerID: "coding-offer",
            docKind: .offerDetail,
            title: "Software development",
            category: "coding"
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [makeCandidate(document: detailDoc, objectEvidenceScore: nil)],
            knownMatches: [match],
            thread: thread
        )

        #expect(projected.count == 1)
        #expect(projected[0].matchedOffers.map(\.id) == ["coding-offer"])
    }

    @Test("implementation does not contain generic word lists or taxonomies")
    func implementationHasNoForbiddenSemanticLists() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AnumCore/ExchangeEngine/Application/ExchangeOfferObjectLane.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let forbiddenPatterns = [
            "genericQueryTokens",
            "genericObjectPhrases",
            "stopword",
            "productFamil",
            "objectEnum",
            "hasObjectFamilyOverlap",
            "filterCompatibleOffers"
        ]
        for pattern in forbiddenPatterns {
            #expect(!source.localizedCaseInsensitiveContains(pattern), "Forbidden pattern found: \(pattern)")
        }
    }

    @Test("document builder emits offer_object docs with identity-only text")
    func documentBuilderEmitsOfferObjectDocs() {
        let builder = ExchangeRetrievalDocumentBuilder()
        let offer = makeOffer(
            id: "computer-offer",
            title: "MacBook Pro",
            category: "computer",
            tags: ["laptop"],
            serviceKinds: ["computer"],
            summary: "Great laptop with delivery available",
            regionTags: ["Toronto"]
        )

        let docs = builder.buildDocuments(
            profile: ExchangePublicNodeProfile(
                id: "profile-1",
                nodeID: "seller-1",
                displayName: "Seller",
                headline: "Electronics",
                summary: "We sell computers and cars",
                interests: [],
                offers: [],
                openTo: [],
                activityTags: [],
                regionTags: ["Toronto"]
            ),
            offers: [offer],
            counterpartyID: "seller-1",
            sourceKind: .local
        )

        let objectDoc = docs.first { $0.docKind == ExchangeRetrievalDocument.DocKind.offerObject }
        #expect(objectDoc != nil)
        #expect(objectDoc?.offerID == "computer-offer")
        #expect(objectDoc?.sourceField == "offer_object")
        #expect(objectDoc?.lexicalText.localizedCaseInsensitiveContains("MacBook Pro") == true)
        #expect(objectDoc?.lexicalText.localizedCaseInsensitiveContains("Toronto") == false)
        #expect(objectDoc?.lexicalText.localizedCaseInsensitiveContains("delivery") == false)
    }
}


    @Test("queryObjectText ignores untyped semanticConcepts")
    func queryObjectTextIgnoresUntypedSemanticConcepts() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: nil,
            semanticConcepts: ["Toronto"]
        )
        #expect(ExchangeOfferObjectLane.queryObjectText(thread: thread) == nil)
        #expect(!ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
    }

    @Test("indexed offer_object identity excludes summary price and region")
    func indexedOfferObjectIdentityOnly() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let offer = makeOffer(
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

        let surface = builder.build(
            profile: ExchangePublicNodeProfile(
                id: "profile-1",
                nodeID: "seller-1",
                displayName: "Seller",
                interests: [],
                offers: [],
                openTo: [],
                activityTags: [],
                regionTags: ["Toronto"]
            ),
            offers: [offer]
        )

        let docs = ExchangeRetrievalDocumentBuilder().build(
            from: surface,
            counterpartyID: "seller-1",
            sourceKind: .local
        )
        let objectDoc = docs.first { $0.docKind == ExchangeRetrievalDocument.DocKind.offerObject }
        #expect(objectDoc != nil)
        let text = objectDoc?.lexicalText.lowercased() ?? ""
        #expect(text.contains("macbook pro"))
        #expect(text.contains("computer"))
        #expect(!text.contains("toronto"))
        #expect(!text.contains("delivery"))
        #expect(!text.contains("$999"))
        #expect(!text.contains("available"))
    }

    @Test("selectedOfferID does not fall back to matchedOfferIDs.first")
    func selectedOfferIDNoFirstFallback() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let match = makeExchangeMatch(
            counterpartyID: "seller-1",
            offerID: "car-offer",
            matchedOfferIDs: ["car-offer"],
            provenObjectOfferIDs: [],
            objectEvidenceScoreByOfferID: [:],
            strength: .moderate
        )
        #expect(ExchangeOfferObjectLane.resolveSelectedOfferID(from: match, thread: thread) == nil)
    }

    @Test("fit engine does not choose matchedOffers.first without object provenance")
    func fitEngineDoesNotChooseUnprovenOffer() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let offer = makeOffer(id: "car-offer", title: "Selling my car", category: "automotive")
        let candidate = makeDiscoveryCandidate(
            counterpartyID: "seller-1",
            matchedOffers: [offer],
            provenObjectOfferIDs: [],
            objectEvidenceScoreByOfferID: [:]
        )
        let matches = ExchangeFitEngine().evaluate(thread: thread, candidates: [candidate])
        #expect(matches.count == 1)
        let match = matches[0]
        #expect(match.offerID == nil)
        #expect(match.strength == ExchangeMatch.Strength.weak)
    }

    @Test("legacy attachment policy returns empty offers without object provenance")
    func legacyAttachmentPolicyWithoutProvenance() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let carOffer = makeOffer(id: "car-offer", title: "Selling my car", category: "automotive")
        let attachment = ExchangeOfferObjectLane.applyObjectLaneOfferAttachmentPolicy(
            thread: thread,
            offers: [carOffer],
            provenObjectOfferIDs: [],
            objectEvidenceScoreByOfferID: [:]
        )
        #expect(attachment.matchedOffers.isEmpty)
        #expect(attachment.provenObjectOfferIDs.isEmpty)
    }

    @Test("directory fallback attachment returns empty without offer_object hit")
    func directoryFallbackWithoutObjectHit() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let offers = [
            makeOffer(id: "car-offer", title: "Selling my car", category: "automotive")
        ]
        let attachment = ExchangeOfferObjectLane.applyObjectLaneOfferAttachmentPolicy(
            thread: thread,
            offers: offers,
            provenObjectOfferIDs: [],
            objectEvidenceScoreByOfferID: [:]
        )
        #expect(attachment.matchedOffers.isEmpty)
        #expect(
            ExchangeOfferObjectLane.resolveSelectedOfferID(
                provenObjectOfferIDs: attachment.provenObjectOfferIDs,
                objectEvidenceScoreByOfferID: attachment.objectEvidenceScoreByOfferID
            ) == nil
        )
    }

    @Test("multi-offer node attaches only proven computer offer")
    func multiOfferNodeAttachesOnlyProvenComputer() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let carOffer = makeOffer(id: "car-offer", title: "Selling my car", category: "automotive")
        let computerOffer = makeOffer(id: "computer-offer", title: "MacBook Pro", category: "computer")
        let match = makeMatch(nodeID: "seller-1", offers: [carOffer, computerOffer])

        let computerObjectDoc = makeRetrievalDocument(
            id: "offer-object::computer-offer",
            offerID: "computer-offer",
            docKind: .offerObject,
            title: "MacBook Pro",
            category: "computer",
            embedding: computerEmbedding
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [makeCandidate(document: computerObjectDoc, objectEvidenceScore: 0.98)],
            knownMatches: [match],
            thread: thread
        )

        #expect(projected.count == 1)
        #expect(projected[0].matchedOffers.map(\.id) == ["computer-offer"])
        #expect(projected[0].provenObjectOfferIDs == ["computer-offer"])
        #expect(
            ExchangeOfferObjectLane.resolveSelectedOfferID(
                provenObjectOfferIDs: projected[0].provenObjectOfferIDs,
                objectEvidenceScoreByOfferID: projected[0].objectEvidenceScoreByOfferID
            ) == "computer-offer"
        )
    }

    @Test("competitive proof keeps only top sibling qualifier")
    func siblingObjectProofKeepsOnlyTopQualifier() {
        let scores: [String: Double] = [
            "offer-object::winner": 0.90,
            "offer-object::loser": 0.75
        ]
        let docs = [
            makeRetrievalDocument(id: "offer-object::winner", offerID: "winner-offer", docKind: .offerObject),
            makeRetrievalDocument(id: "offer-object::loser", offerID: "loser-offer", docKind: .offerObject)
        ]
        let proven = ExchangeOfferObjectLane.competitivelyProvenObjectOffers(
            documents: docs,
            objectEvidenceScoresByDocumentID: scores
        )
        #expect(proven.keys.sorted() == ["winner-offer"])
        #expect(proven["winner-offer"] == 0.90)
    }

    @Test("reverse competitive proof keeps only reversed top sibling")
    func reverseSiblingObjectProofKeepsOnlyTopQualifier() {
        let scores: [String: Double] = [
            "offer-object::winner": 0.75,
            "offer-object::loser": 0.90
        ]
        let docs = [
            makeRetrievalDocument(id: "offer-object::winner", offerID: "winner-offer", docKind: .offerObject),
            makeRetrievalDocument(id: "offer-object::loser", offerID: "loser-offer", docKind: .offerObject)
        ]
        let proven = ExchangeOfferObjectLane.competitivelyProvenObjectOffers(
            documents: docs,
            objectEvidenceScoresByDocumentID: scores
        )
        #expect(proven.keys.sorted() == ["loser-offer"])
    }

    @Test("single offer node still proves with absolute threshold")
    func singleOfferNodeStillProves() {
        let scores = ["offer-object::only": 0.25]
        let docs = [makeRetrievalDocument(id: "offer-object::only", offerID: "only-offer", docKind: .offerObject)]
        let proven = ExchangeOfferObjectLane.competitivelyProvenObjectOffers(
            documents: docs,
            objectEvidenceScoresByDocumentID: scores
        )
        #expect(proven == ["only-offer": 0.25])
    }

    @Test("below threshold competitive proof proves none")
    func belowThresholdStillDoesNotProve() {
        let scores = ["offer-object::only": 0.19]
        let docs = [makeRetrievalDocument(id: "offer-object::only", offerID: "only-offer", docKind: .offerObject)]
        let proven = ExchangeOfferObjectLane.competitivelyProvenObjectOffers(
            documents: docs,
            objectEvidenceScoresByDocumentID: scores
        )
        #expect(proven.isEmpty)
    }

    @Test("profile or offer detail cannot competitively prove")
    func profileOrOfferDetailCannotProve() {
        let scores = ["offer-detail::car": 0.95, "profile::seller": 0.99]
        let docs = [
            makeRetrievalDocument(id: "offer-detail::car", offerID: "car-offer", docKind: .offerDetail),
            makeRetrievalDocument(id: "profile::seller", offerID: nil, docKind: .profileCapability, surfaceType: .publicProfileCapability, entityType: .publicProfile)
        ]
        let proven = ExchangeOfferObjectLane.competitivelyProvenObjectOffers(
            documents: docs,
            objectEvidenceScoresByDocumentID: scores
        )
        #expect(proven.isEmpty)
    }

    @Test("computer query sibling false proof regression")
    func siblingFalseProofRegressionComputerCar() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let carOffer = makeOffer(id: "offer-multi-car", title: "Used Car", category: "car")
        let computerOffer = makeOffer(id: "offer-multi-computer", title: "Refurbished Computer", category: "computer")
        let match = makeMatch(nodeID: "seller-1", offers: [carOffer, computerOffer])

        let computerDoc = makeRetrievalDocument(
            id: "offer-object::offer-multi-computer",
            offerID: "offer-multi-computer",
            docKind: .offerObject,
            title: "Refurbished Computer",
            category: "computer"
        )
        let carDoc = makeRetrievalDocument(
            id: "offer-object::offer-multi-car",
            offerID: "offer-multi-car",
            docKind: .offerObject,
            title: "Used Car",
            category: "car"
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [
                makeCandidate(document: computerDoc, objectEvidenceScore: 0.904),
                makeCandidate(document: carDoc, objectEvidenceScore: 0.755)
            ],
            knownMatches: [match],
            thread: thread
        )

        let attachedOfferIDs = Set(projected.flatMap { $0.matchedOffers.map(\.id) })
        #expect(attachedOfferIDs == ["offer-multi-computer"])
        let proven = Set(projected.flatMap { $0.provenObjectOfferIDs })
        #expect(proven == ["offer-multi-computer"])
    }

    @Test("car query sibling false proof regression")
    func siblingFalseProofRegressionCarComputer() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "car"
        )
        let carOffer = makeOffer(id: "offer-multi-car", title: "Used Car", category: "car")
        let computerOffer = makeOffer(id: "offer-multi-computer", title: "Refurbished Computer", category: "computer")
        let match = makeMatch(nodeID: "seller-1", offers: [carOffer, computerOffer])

        let computerDoc = makeRetrievalDocument(
            id: "offer-object::offer-multi-computer",
            offerID: "offer-multi-computer",
            docKind: .offerObject,
            title: "Refurbished Computer",
            category: "computer"
        )
        let carDoc = makeRetrievalDocument(
            id: "offer-object::offer-multi-car",
            offerID: "offer-multi-car",
            docKind: .offerObject,
            title: "Used Car",
            category: "car"
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [
                makeCandidate(document: carDoc, objectEvidenceScore: 0.941),
                makeCandidate(document: computerDoc, objectEvidenceScore: 0.739)
            ],
            knownMatches: [match],
            thread: thread
        )

        let attachedOfferIDs = Set(projected.flatMap { $0.matchedOffers.map(\.id) })
        #expect(attachedOfferIDs == ["offer-multi-car"])
        let proven = Set(projected.flatMap { $0.provenObjectOfferIDs })
        #expect(proven == ["offer-multi-car"])
    }

    @Test("losing sibling offer_object row keeps empty matched offers under object lane")
    func losingSiblingOfferObjectRowDoesNotAttach() {
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            domainCategory: .product,
            transactionIntent: .buy,
            objectType: "computer"
        )
        let carOffer = makeOffer(id: "offer-multi-car", title: "Used Car", category: "car")
        let computerOffer = makeOffer(id: "offer-multi-computer", title: "Refurbished Computer", category: "computer")
        let match = makeMatch(nodeID: "seller-1", offers: [carOffer, computerOffer])

        let computerDoc = makeRetrievalDocument(
            id: "offer-object::offer-multi-computer",
            offerID: "offer-multi-computer",
            docKind: .offerObject
        )
        let carDoc = makeRetrievalDocument(
            id: "offer-object::offer-multi-car",
            offerID: "offer-multi-car",
            docKind: .offerObject
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [
                makeCandidate(document: computerDoc, objectEvidenceScore: 0.904),
                makeCandidate(document: carDoc, objectEvidenceScore: 0.755)
            ],
            knownMatches: [match],
            thread: thread
        )

        let carRow = projected.first { $0.matchedOffers.contains(where: { $0.id == "offer-multi-car" }) }
        #expect(carRow == nil)
        let carOnlyRows = projected.filter { $0.provenObjectOfferIDs.isEmpty && $0.matchedOffers.isEmpty }
        #expect(carOnlyRows.count >= 1)
    }


private let computerEmbedding: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
private let carEmbedding: [Float] = [0, 1, 0, 0, 0, 0, 0, 0]

private func makeThread(
    queryIntentClass: ExchangeIntent.QueryIntentClass,
    domainCategory: ExchangeIntentFacets.DomainCategory,
    transactionIntent: ExchangeIntentFacets.TransactionIntent?,
    objectType: String?,
    semanticConcepts: [String] = [],
    rawUserText: String = "test"
) -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: domainCategory,
        objectType: objectType,
        transactionIntent: transactionIntent,
        semanticConcepts: semanticConcepts,
        rawUserText: rawUserText
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

private func makeOffer(
    id: String,
    title: String,
    category: String,
    tags: [String] = [],
    serviceKinds: [String] = [],
    summary: String? = nil,
    regionTags: [String] = [],
    commercialFacts: ExchangeOffer.CommercialFacts = .empty
) -> ExchangeOffer {
    ExchangeOffer(
        id: id,
        nodeID: "seller-1",
        title: title,
        summary: summary,
        category: category,
        tags: tags,
        regionTags: regionTags,
        semantic: .init(serviceKinds: serviceKinds),
        status: .active,
        visibility: .publicDiscoverable,
        commercialFacts: commercialFacts
    )
}

private func makeMatch(nodeID: String, offers: [ExchangeOffer]) -> ExchangeDirectoryMatch {
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

private func makeExchangeMatch(
    counterpartyID: String,
    offerID: String?,
    matchedOfferIDs: [String],
    provenObjectOfferIDs: [String] = [],
    objectEvidenceScoreByOfferID: [String: Double] = [:],
    strength: ExchangeMatch.Strength
) -> ExchangeMatch {
    ExchangeMatch(
        threadID: UUID(),
        counterpartyID: counterpartyID,
        offerID: offerID,
        matchedOfferIDs: matchedOfferIDs,
        provenObjectOfferIDs: provenObjectOfferIDs,
        objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID,
        strength: strength,
        score: strength == .strong ? 0.9 : 0.2
    )
}

private func makeDiscoveryCandidate(
    counterpartyID: String,
    matchedOffers: [ExchangeOffer],
    provenObjectOfferIDs: Set<String>,
    objectEvidenceScoreByOfferID: [String: Double]
) -> ExchangeDiscoveryEngine.DiscoveryCandidate {
    let counterparty = ExchangeCounterparty(
        id: counterpartyID,
        kind: .secretaryNode,
        displayName: "Seller",
        source: .relayNetwork,
        identity: .init(nodeID: counterpartyID, publicKeyID: nil, verification: .unverified),
        publicProfile: nil,
        tags: [],
        semantic: .init(),
        contactRoutes: [],
        status: .active
    )
    return ExchangeDiscoveryEngine.DiscoveryCandidate(
        publicProfile: nil,
        counterparty: counterparty,
        matchedOffers: matchedOffers,
        coarse: .init(
            queryTokenOverlap: 0,
            explicitTokenOverlap: 0,
            regionOverlap: 0,
            offerOverlap: 0,
            capabilityOverlap: 0,
            affinityOverlap: 0,
            hasPublicProfile: false,
            hasOffers: !matchedOffers.isEmpty,
            kindCompatible: true,
            placeCompatible: true,
            trustHintScore: 0.5,
            retrievalScore: 0.5,
            rationale: "test"
        ),
        posture: .init(
            bucket: .contactable,
            preview: "test",
            explicitOpenness: true,
            requiresIntroduction: false
        ),
        dominantSurface: .offer,
        overallScore: 0.5,
        provenObjectOfferIDs: provenObjectOfferIDs,
        objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID
    )
}

private func makeRetrievalDocument(
    id: String,
    offerID: String?,
    docKind: ExchangeRetrievalDocument.DocKind?,
    surfaceType: ExchangeRetrievalDocument.SurfaceType = .offer,
    entityType: ExchangeRetrievalDocument.EntityType = .offer,
    title: String = "title",
    category: String? = "category",
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
        title: title,
        category: category,
        lexicalText: title,
        semanticText: category ?? "",
        embedding: embedding
    )
}

private func makeCandidate(
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
