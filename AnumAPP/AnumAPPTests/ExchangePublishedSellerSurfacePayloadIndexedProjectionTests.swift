import XCTest
@testable import AnumCore

final class ExchangePublishedSellerSurfacePayloadIndexedProjectionTests: XCTestCase {
    func test_oldPayloadDecode_withoutIndexedFields_succeeds() throws {
        let json = """
        {
          "nodeID": "node-1",
          "displayName": "Builder",
          "publicProfile": {
            "id": "profile-1",
            "displayName": "Builder",
            "headline": "Contractor network",
            "summary": "Public summary",
            "visibility": "discoverable",
            "availability": "open",
            "interests": ["renovation"],
            "offers": ["contractor matching"],
            "openTo": ["local projects"],
            "excludedTopics": [],
            "activityTags": [],
            "regionTags": ["gta"],
            "semantic": {},
            "reachability": {
              "acceptingInbound": true,
              "accessMode": "direct",
              "disclosureCeiling": "balanced",
              "routeableOnly": false,
              "intentCategoryPolicy": "broad"
            }
          },
          "offers": [
            {
              "id": "offer-1",
              "title": "Home support",
              "summary": "Offer summary",
              "category": "services",
              "tags": ["home"],
              "regionTags": ["gta"],
              "visibility": "publicDiscoverable",
              "semantic": {},
              "fulfillment": {}
            }
          ],
          "publishedAt": 768715200,
          "fingerprint": "abc123"
        }
        """

        let payload = try JSONDecoder().decode(
            ExchangePublishedSellerSurfacePayload.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(payload.nodeID, "node-1")
        XCTAssertNil(payload.indexedSurfaceVersion)
        XCTAssertNil(payload.indexedProviderSurface)
        XCTAssertNil(payload.indexedOffers)
    }

    func test_newPayloadEncodeDecode_preservesIndexedFields() throws {
        let payload = ExchangePublishedSellerSurfacePayload(
            nodeID: "node-1",
            displayName: "Builder",
            publicProfile: .init(
                id: "profile-1",
                displayName: "Builder",
                headline: "Contractor network",
                summary: "Public summary",
                visibility: "discoverable",
                availability: "open",
                interests: ["renovation"],
                offers: ["contractor matching"],
                openTo: ["local projects"],
                excludedTopics: [],
                activityTags: [],
                regionTags: ["gta"],
                semantic: [:],
                reachability: .init(
                    acceptingInbound: true,
                    accessMode: "direct",
                    disclosureCeiling: "balanced",
                    routeableOnly: false
                )
            ),
            offers: [
                .init(
                    id: "offer-1",
                    title: "Home support",
                    summary: "Offer summary",
                    category: "services",
                    tags: ["home"],
                    regionTags: ["gta"],
                    visibility: "publicDiscoverable",
                    semantic: [:],
                    fulfillment: [:]
                )
            ],
            indexedSurfaceVersion: 1,
            indexedProviderSurface: .init(
                schemaVersion: 1,
                semanticConcepts: ["works with first-time developers"],
                broadRecallTokens: ["gta"],
                hardConstraints: [],
                softPreferences: ["accepts small renovation budgets"],
                commercialConstraints: [.init(text: "seller financing considered", isHard: false)],
                timeAvailabilityConstraints: [.init(text: "available weekends", isHard: false)],
                sourceTextBlocks: ["works with first-time developers"],
                regions: .init(regionTags: ["gta"], canonicalRegionIDs: ["ca-on-gta"])
            ),
            indexedOffers: [
                .init(
                    offerID: "offer-1",
                    schemaVersion: 1,
                    semanticConcepts: ["vendor take-back mortgage"],
                    broadRecallTokens: ["vtb"],
                    hardConstraints: [],
                    softPreferences: [],
                    commercialConstraints: [.init(text: "vendor take-back mortgage", isHard: false)],
                    timeAvailabilityConstraints: [],
                    fulfillment: .init(
                        pricingMode: "custom",
                        commitmentMode: "approvalRequired",
                        remoteFriendly: true
                    ),
                    sourceTextBlocks: ["seller financing considered"],
                    visibility: "publicDiscoverable",
                    status: "active"
                )
            ],
            publishedAt: Date(timeIntervalSince1970: 1_726_300_000),
            fingerprint: "abc123"
        )

        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ExchangePublishedSellerSurfacePayload.self, from: encoded)

        XCTAssertEqual(decoded.indexedSurfaceVersion, 1)
        XCTAssertEqual(decoded.indexedProviderSurface?.schemaVersion, 1)
        XCTAssertTrue(decoded.indexedProviderSurface?.semanticConcepts.contains("works with first-time developers") == true)
        XCTAssertEqual(decoded.indexedOffers?.first?.offerID, "offer-1")
        XCTAssertTrue(decoded.indexedOffers?.first?.semanticConcepts.contains("vendor take-back mortgage") == true)
    }
}
