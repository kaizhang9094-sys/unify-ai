import XCTest
@testable import AnumCore

final class ExchangeOfferImageURLNormalizationTests: XCTestCase {
    func test_limitedOrderedOfferImageURLs_primaryFirstThenGallery() {
        let urls = ExchangeOffer.limitedOrderedOfferImageURLs(
            primaryImageURL: "https://a.example/a.jpg",
            galleryImageURLs: ["https://b.example/b.jpg", "https://c.example/c.jpg"]
        )
        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls[0], "https://a.example/a.jpg")
        XCTAssertEqual(urls[1], "https://b.example/b.jpg")
        XCTAssertEqual(urls[2], "https://c.example/c.jpg")
    }

    func test_limitedOrderedOfferImageURLs_deduplicatesCaseInsensitive() {
        let urls = ExchangeOffer.limitedOrderedOfferImageURLs(
            primaryImageURL: "https://x.example/p.JPG",
            galleryImageURLs: ["https://x.example/p.jpg", "https://y.example/y.png"]
        )
        XCTAssertEqual(urls, ["https://x.example/p.JPG", "https://y.example/y.png"])
    }

    func test_limitedOrderedOfferImageURLs_clampsToFive() {
        let extras = (0 ..< 8).map { "https://z.example/\($0).jpg" }
        let urls = ExchangeOffer.limitedOrderedOfferImageURLs(
            primaryImageURL: "https://hero.example/0.jpg",
            galleryImageURLs: extras
        )
        XCTAssertEqual(urls.count, ExchangeOffer.maxPublicOfferImageCount)
        XCTAssertEqual(urls.first, "https://hero.example/0.jpg")
    }

    func test_normalizedGalleryStorage_excludesPrimaryFromExtras() {
        let primary = "https://same.example/x.jpg"
        let gallery = ExchangeOffer.normalizedGalleryStorage(
            primary: primary,
            gallery: [primary, "https://other.example/y.jpg"]
        )
        XCTAssertEqual(gallery, ["https://other.example/y.jpg"])
    }

    func test_decode_primaryOnly_backwardCompatible() throws {
        let json = """
        {
          "id": "offer-1",
          "nodeID": "node-1",
          "publicProfileID": "prof-1",
          "title": "T",
          "primaryImageURL": "https://img.example/p.png"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ExchangeOffer.self, from: json)
        XCTAssertEqual(decoded.primaryImageURL, "https://img.example/p.png")
        XCTAssertTrue(decoded.galleryImageURLs.isEmpty)
    }

    func test_decode_primaryAndGallery() throws {
        let json = """
        {
          "id": "offer-2",
          "nodeID": "node-2",
          "publicProfileID": "prof-2",
          "title": "T2",
          "primaryImageURL": "https://img.example/a.png",
          "galleryImageURLs": ["https://img.example/b.png", "https://img.example/c.png"]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ExchangeOffer.self, from: json)
        XCTAssertEqual(decoded.primaryImageURL, "https://img.example/a.png")
        XCTAssertEqual(decoded.galleryImageURLs, ["https://img.example/b.png", "https://img.example/c.png"])
    }

    func test_searchableText_doesNotIncludeImageURLs() {
        let offer = ExchangeOffer(
            id: "o",
            nodeID: "n",
            publicProfileID: "p",
            title: "Photo lessons",
            summary: "Learn composition",
            primaryImageURL: "https://cdn.example/lesson.jpg",
            galleryImageURLs: ["https://cdn.example/extra.jpg"]
        )
        let text = offer.searchableText.lowercased()
        XCTAssertFalse(text.contains("cdn.example"))
        XCTAssertFalse(text.contains("https://"))
    }
}
