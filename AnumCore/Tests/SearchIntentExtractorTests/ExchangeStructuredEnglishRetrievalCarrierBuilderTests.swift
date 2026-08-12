import XCTest
@testable import AnumCore

final class ExchangeStructuredEnglishRetrievalCarrierBuilderTests: XCTestCase {
    func testMixedChineseDisplayWithEnglishStructuredFactsProducesCarrier() {
        let surface = makeMixedLanguageRooferSurface()
        let enriched = ExchangeStructuredEnglishRetrievalCarrierBuilder.apply(to: surface)
        XCTAssertNotNil(enriched)
        XCTAssertFalse(ExchangeStructuredEnglishRetrievalCarrierBuilder.buildOfferCarrier(from: surface.offers[0])?.isEmpty ?? true)
    }

    func testCarrierContainsExpectedEnglishFacts() {
        let surface = makeMixedLanguageRooferSurface()
        let carrier = ExchangeStructuredEnglishRetrievalCarrierBuilder.buildOfferCarrier(from: surface.offers[0]) ?? ""
        let lowered = carrier.lowercased()
        XCTAssertTrue(lowered.contains("roofing") || lowered.contains("roof repair"))
        XCTAssertTrue(lowered.contains("aurora"))
        XCTAssertTrue(lowered.contains("newmarket"))
        XCTAssertTrue(lowered.contains("free estimate"))
    }

    func testCarrierContainsNoCJK() {
        let surface = makeMixedLanguageRooferSurface()
        let offerCarrier = ExchangeStructuredEnglishRetrievalCarrierBuilder.buildOfferCarrier(from: surface.offers[0]) ?? ""
        let profileCarrier = ExchangeStructuredEnglishRetrievalCarrierBuilder.buildProfileCarrier(from: surface) ?? ""
        XCTAssertFalse(ExchangeRetrievalEnglishProjection.containsSignificantNonEnglish(offerCarrier))
        XCTAssertFalse(ExchangeRetrievalEnglishProjection.containsSignificantNonEnglish(profileCarrier))
    }

    func testRawChineseTitleSummarySourceBlocksExcluded() {
        let surface = makeMixedLanguageRooferSurface()
        let carrier = ExchangeStructuredEnglishRetrievalCarrierBuilder.buildOfferCarrier(from: surface.offers[0]) ?? ""
        XCTAssertFalse(carrier.contains("屋顶"))
        XCTAssertFalse(carrier.contains("估价"))
    }

    func testAllChineseStructuredFieldsProduceNilCarrier() {
        let offer = ExchangeIndexedOfferSurface(
            id: "offer-zh",
            offerID: "offer-zh",
            title: "中文服务",
            summary: "中文摘要",
            category: "中文类别",
            capabilityTerms: ["中文能力"],
            fulfillment: .init(pricingMode: "fixed", commitmentMode: "one_time", remoteFriendly: false),
            sourceTextBlocks: ["中文来源"],
            serviceAreas: [],
            visibility: "publicDiscoverable",
            status: "active"
        )
        XCTAssertNil(ExchangeStructuredEnglishRetrievalCarrierBuilder.buildOfferCarrier(from: offer))
    }

    func testPerOfferCarrierProduced() {
        let surface = makeMixedLanguageRooferSurface()
        let enriched = ExchangeStructuredEnglishRetrievalCarrierBuilder.apply(to: surface)!
        XCTAssertNotNil(enriched.offers[0].canonicalEnglishRetrievalText)
        XCTAssertFalse(enriched.offers[0].canonicalEnglishRetrievalText?.isEmpty ?? true)
    }

    private func makeMixedLanguageRooferSurface() -> ExchangeIndexedProviderSurface {
        let aurora = ExchangeDeclaredServiceArea.fromSellerChip("Aurora")!
        let newmarket = ExchangeDeclaredServiceArea.fromSellerChip("Newmarket")!
        let offer = ExchangeIndexedOfferSurface(
            id: "offer-test",
            offerID: "offer-test",
            title: "屋顶维修师傅",
            summary: "屋顶维修师傅，服务Aurora和Newmarket，提供免费上门估价",
            category: "roofing",
            objectIdentityTerms: ["屋顶", "roof repair", "roofing"],
            capabilityTerms: ["roof repair", "estimate"],
            commercialConstraints: [
                .init(text: "Free estimate", isHard: false),
                .init(text: "available tomorrow afternoon", isHard: false)
            ],
            fulfillment: .init(
                pricingMode: "quote",
                commitmentMode: "one_time",
                remoteFriendly: false,
                serviceAreaNote: "Aurora and Newmarket"
            ),
            sourceTextBlocks: ["屋顶维修师傅，服务Aurora和Newmarket，提供免费上门估价"],
            serviceAreas: [aurora, newmarket],
            visibility: "publicDiscoverable",
            status: "active"
        )
        return ExchangeIndexedProviderSurface(
            id: "profile-test",
            publicProfileID: "profile-test",
            nodeID: "node-test",
            displayName: "屋顶维修师傅",
            headline: "屋顶维修师傅",
            summary: "屋顶维修师傅，服务Aurora和Newmarket",
            visibility: "public",
            availability: "open",
            regions: .init(regionTags: ["aurora", "newmarket"]),
            capabilityTerms: ["roofing", "estimate"],
            semanticConcepts: ["roofing"],
            reachability: .init(
                accessMode: "direct",
                acceptingInbound: true,
                disclosureCeiling: "balanced",
                routeableOnly: false,
                intentCategoryPolicy: "open"
            ),
            offers: [offer],
            sourceTextBlocks: ["屋顶维修师傅，服务Aurora和Newmarket"]
        )
    }
}
