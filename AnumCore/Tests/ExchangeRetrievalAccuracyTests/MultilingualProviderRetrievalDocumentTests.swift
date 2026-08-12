import XCTest
@testable import AnumCore

final class MultilingualProviderRetrievalDocumentTests: XCTestCase {
    private let chineseOfferText =
        "屋顶维修师傅，服务Aurora和Newmarket，提供免费上门估价，可预约明天下午。"
    private let mockEnglishCarrier =
        "roofer, roof repair, roof estimate, free on-site estimate, service area Aurora and Newmarket, available tomorrow afternoon"

    func testChineseOfferWithMockEnglishCarrierProjectsEnglishObjectAndServiceAreas() {
        let aurora = ExchangeDeclaredServiceArea.fromSellerChip("Aurora")!
        let newmarket = ExchangeDeclaredServiceArea.fromSellerChip("Newmarket")!

        let offer = ExchangeOffer(
            id: "offer-roofer-zh",
            nodeID: "node-roofer",
            publicProfileID: "profile-roofer",
            title: chineseOfferText,
            summary: chineseOfferText,
            category: "roofing",
            tags: ["屋顶", "估价"],
            serviceAreas: [aurora, newmarket],
            semantic: .init(serviceKinds: ["roof repair"], notes: chineseOfferText),
            status: .active,
            visibility: .publicDiscoverable,
            commercialFacts: .init(
                priceDisplay: "Free estimate",
                serviceAreaNote: "Aurora and Newmarket",
                availabilityNote: "available tomorrow afternoon"
            )
        )

        let profile = ExchangePublicNodeProfile(
            id: "profile-roofer",
            nodeID: "node-roofer",
            displayName: "屋顶维修师傅",
            headline: chineseOfferText,
            summary: chineseOfferText,
            offers: [chineseOfferText],
            regionTags: ["aurora", "newmarket"],
            semantic: .init(domains: ["roofing"], notes: chineseOfferText)
        )

        var surface = ExchangeIndexedProviderSurfaceBuilder().build(profile: profile, offers: [offer])
        surface.offers[0].canonicalEnglishRetrievalText = mockEnglishCarrier
        surface.offers[0].semanticConcepts = [
            "roofer",
            "roof repair",
            "roof estimate",
            "free on-site estimate"
        ]
        surface.offers[0].objectIdentityTerms = ["roofer", "roof repair"]

        let docs = ExchangeRetrievalDocumentBuilder().build(from: surface, counterpartyID: "cp-roofer")
        let offerDocs = docs.filter { $0.offerID == offer.id }
        let detailDoc = offerDocs.first(where: { $0.docKind == .offerDetail })
        let objectDoc = offerDocs.first(where: { $0.docKind == .offerObject })

        XCTAssertNotNil(detailDoc)
        XCTAssertNotNil(objectDoc)

        let detailSearchable = detailDoc!.searchableText.lowercased()
        let objectSearchable = objectDoc!.searchableText.lowercased()
        let objectEmbedding = objectDoc!.retrievalEmbeddingText.lowercased()

        XCTAssertTrue(detailSearchable.contains("roofer"))
        XCTAssertTrue(objectSearchable.contains("roofer") || objectSearchable.contains("roof repair"))
        XCTAssertTrue(objectEmbedding.contains("roofer") || objectEmbedding.contains("roof repair"))
        XCTAssertEqual(detailDoc!.canonicalEnglishRetrievalText, mockEnglishCarrier)
        XCTAssertEqual(objectDoc!.canonicalEnglishRetrievalText, mockEnglishCarrier)

        let serviceAreaNames = detailDoc!.serviceAreas.map { $0.displayName.lowercased() }
        XCTAssertTrue(serviceAreaNames.contains("aurora"))
        XCTAssertTrue(serviceAreaNames.contains("newmarket"))

        XCTAssertTrue(surface.offers[0].sourceTextBlocks.joined(separator: " ").contains("屋顶"))
        XCTAssertFalse(objectEmbedding.contains("屋顶"))
        XCTAssertTrue(objectDoc!.usesEnglishOnlyRetrievalProjection)
    }
}
