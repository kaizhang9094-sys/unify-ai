import XCTest
import AnumCore

final class ExchangeRetrievalDocumentBuilderIndexedSurfaceTests: XCTestCase {
    private let builder = ExchangeRetrievalDocumentBuilder()
    private let now = Date(timeIntervalSince1970: 1_726_000_000)

    func test_providerSurfaceDoc_preservesOpenEndedPhrases() {
        let surface = makeIndexedSurface(
            semanticConcepts: [
                "works with first-time developers",
                "accepts small renovation budgets"
            ],
            sourceTextBlocks: [
                "Works with first-time developers.",
                "Accepts small renovation budgets."
            ]
        )

        let docs = builder.build(from: surface, counterpartyID: "cp-indexed", sourceKind: .local)
        let cap = try! XCTUnwrap(docs.first { $0.surfaceType == .publicProfileCapability })
        let haystack = [cap.semanticText, cap.lexicalText].joined(separator: " ").lowercased()
        XCTAssertTrue(haystack.contains("works with first-time developers"))
        XCTAssertTrue(haystack.contains("accepts small renovation budgets"))
        XCTAssertFalse(cap.providerTerms.contains("works with first-time developers"))
        XCTAssertFalse(cap.capabilityTerms.contains("accepts small renovation budgets"))
    }

    func test_offerDoc_preservesSellerFinancingVTB() {
        let offer = makeIndexedOffer(
            semanticConcepts: ["seller financing", "vendor take-back mortgage"],
            commercialConstraints: [
                .init(text: "seller financing", isHard: false),
                .init(text: "vendor take-back mortgage", isHard: false)
            ],
            sourceTextBlocks: ["Seller financing available via vendor take-back mortgage."]
        )
        let profile = makeIndexedSurface(offers: [offer])

        let doc = try! XCTUnwrap(
            builder.build(from: offer, parentSurface: profile, counterpartyID: "cp-indexed", sourceKind: .local)
        )
        let haystack = [doc.semanticText, doc.lexicalText].joined(separator: " ").lowercased()
        XCTAssertTrue(haystack.contains("seller financing"))
        XCTAssertTrue(haystack.contains("vendor take-back mortgage"))
        XCTAssertFalse(doc.capabilityTerms.contains("mortgage"))
    }

    func test_regionEvidence_mapsThrough() {
        let surface = makeIndexedSurface(
            regions: .init(
                regionTags: ["gta", "aurora"],
                canonicalRegionIDs: ["ca-on-gta"],
                parentRegionIDs: ["ca-on"],
                regionAliases: ["greater toronto area"]
            )
        )
        let docs = builder.build(from: surface, counterpartyID: "cp-indexed", sourceKind: .local)
        let cap = try! XCTUnwrap(docs.first { $0.surfaceType == .publicProfileCapability })
        XCTAssertEqual(cap.canonicalRegionIDs, ["ca-on-gta"])
        XCTAssertEqual(cap.parentRegionIDs, ["ca-on"])
        XCTAssertTrue(cap.regionAliases.contains("greater toronto area"))
        XCTAssertTrue(cap.filterTokens.contains("gta"))
    }

    func test_paritySmoke_oldPathVsIndexedPath_coreAnchorsAndSearchText() {
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            displayName: "Builder Profile",
            headline: "Local contractor network",
            summary: "Works with first-time developers",
            visibility: .discoverable,
            interests: ["housing"],
            offers: ["contractor matching"],
            openTo: ["home renovation help"],
            activityTags: ["contractor"],
            regionTags: ["gta"],
            semantic: .init(domains: ["real estate"], intentKinds: ["service"], notes: "accepts small renovation budgets"),
            availability: .open,
            updatedAt: now
        )
        let offer = ExchangeOffer(
            id: "offer-1",
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Home support offer",
            summary: "seller financing available",
            category: "contractor",
            tags: ["home", "renovation"],
            regionTags: ["gta"],
            semantic: .init(domains: ["real estate"], serviceKinds: ["contractor"], notes: "vendor take-back mortgage"),
            status: .active,
            visibility: .publicDiscoverable,
            updatedAt: now
        )

        let oldDocs = builder.buildDocuments(profile: profile, offers: [offer], counterpartyID: "cp-1", sourceKind: .local)
        let indexedSurface = ExchangeIndexedProviderSurfaceBuilder().build(profile: profile, offers: [offer])
        let newDocs = builder.build(from: indexedSurface, counterpartyID: "cp-1", sourceKind: .local)

        let oldOffer = try! XCTUnwrap(oldDocs.first { $0.surfaceType == .offer })
        let newOffer = try! XCTUnwrap(newDocs.first { $0.surfaceType == .offer })
        XCTAssertEqual(oldOffer.nodeID, newOffer.nodeID)
        XCTAssertEqual(oldOffer.publicProfileID, newOffer.publicProfileID)
        XCTAssertEqual(oldOffer.offerID, newOffer.offerID)
        XCTAssertEqual(oldOffer.visibility, newOffer.visibility)
        XCTAssertEqual(oldOffer.entityType, newOffer.entityType)
        XCTAssertEqual(oldOffer.sourceKind, newOffer.sourceKind)

        let oldSearch = oldOffer.searchableText.lowercased()
        let newSearch = newOffer.searchableText.lowercased()
        XCTAssertTrue(newSearch.contains("seller financing"))
        XCTAssertTrue(newSearch.contains("vendor take-back mortgage"))
        let allNewSearch = newDocs.map(\.searchableText).joined(separator: " ").lowercased()
        XCTAssertTrue(allNewSearch.contains("works with first-time developers") || allNewSearch.contains("accepts small renovation budgets"))
        XCTAssertTrue(oldSearch.contains("seller financing"))
    }

    func test_hiddenInactiveOffers_notIncludedInIndexedBuildDocuments() {
        let hidden = makeIndexedOffer(id: "offer-hidden", visibility: "hidden", status: "active")
        let paused = makeIndexedOffer(id: "offer-paused", visibility: "publicdiscoverable", status: "paused")
        let active = makeIndexedOffer(id: "offer-live", visibility: "publicdiscoverable", status: "active")
        let surface = makeIndexedSurface(offers: [hidden, paused, active])

        let docs = builder.build(from: surface, counterpartyID: "cp-indexed", sourceKind: .local)
        XCTAssertTrue(docs.contains { $0.id == "offer::offer-live" })
        XCTAssertFalse(docs.contains { $0.id == "offer::offer-hidden" })
        XCTAssertFalse(docs.contains { $0.id == "offer::offer-paused" })
    }
}

private extension ExchangeRetrievalDocumentBuilderIndexedSurfaceTests {
    func makeIndexedSurface(
        regions: ExchangeIndexedProviderSurface.RegionEvidence = .init(regionTags: ["gta"]),
        semanticConcepts: [String] = [],
        sourceTextBlocks: [String] = [],
        offers: [ExchangeIndexedOfferSurface] = []
    ) -> ExchangeIndexedProviderSurface {
        ExchangeIndexedProviderSurface(
            id: "profile-1",
            publicProfileID: "profile-1",
            nodeID: "node-1",
            displayName: "Builder Profile",
            headline: "Local contractor network",
            summary: "Provider summary",
            visibility: "discoverable",
            availability: "open",
            regions: regions,
            providerTerms: ["builder profile", "local contractor network"],
            capabilityTerms: ["real estate", "contractor matching"],
            affinityTerms: ["housing"],
            broadRecallTokens: ["gta", "renovation"],
            semanticConcepts: semanticConcepts,
            hardConstraints: [],
            softPreferences: [],
            commercialConstraints: [],
            timeAvailabilityConstraints: [],
            reachability: .init(
                accessMode: "direct",
                acceptingInbound: true,
                disclosureCeiling: "balanced",
                routeableOnly: false,
                intentCategoryPolicy: "permissive"
            ),
            offers: offers,
            sourceTextBlocks: sourceTextBlocks,
            updatedAt: now,
            schemaVersion: 1
        )
    }

    func makeIndexedOffer(
        id: String = "offer-1",
        visibility: String = "publicdiscoverable",
        status: String = "active",
        semanticConcepts: [String] = [],
        commercialConstraints: [ExchangeIndexedOfferSurface.CommercialConstraint] = [],
        sourceTextBlocks: [String] = []
    ) -> ExchangeIndexedOfferSurface {
        ExchangeIndexedOfferSurface(
            id: id,
            offerID: id,
            title: "Home support offer",
            summary: "Offer summary",
            category: "contractor",
            freeTextCategory: "contractor",
            providerTerms: ["home support offer", "contractor"],
            capabilityTerms: ["real estate", "renovation"],
            affinityTerms: ["gta"],
            broadRecallTokens: ["home", "gta"],
            semanticConcepts: semanticConcepts,
            hardConstraints: [],
            softPreferences: [],
            commercialConstraints: commercialConstraints,
            fulfillment: .init(
                pricingMode: "quoteRequired",
                commitmentMode: "exploratory",
                remoteFriendly: false,
                leadTimeNote: "can come tomorrow",
                capacityNote: nil,
                serviceAreaNote: "gta"
            ),
            timeAvailabilityConstraints: [],
            contactOrPolicyText: [],
            sourceTextBlocks: sourceTextBlocks,
            visibility: visibility,
            status: status,
            updatedAt: now,
            schemaVersion: 1
        )
    }
}
