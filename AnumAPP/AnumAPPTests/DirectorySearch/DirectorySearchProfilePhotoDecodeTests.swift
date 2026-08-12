import XCTest

/// Contract: `GET`-less `POST /v1/directory/search` JSON echoes `publicProfile.primaryImageURL`.
/// Production decoder: `ExchangeHTTPDirectoryClient.RemotePublicProfile` (`CodingKeys.primaryImageURL`).
///
/// UI consumes the mapped `ExchangeDirectoryMatch` profile/offer URLs in `ExchangeFacade.discoverForYou`,
/// using surface-aware `ExchangeModels.ForYouItem.primaryImageURL` selection, and renders via `SecretaryDashboardView` /
/// `SecretaryThreadView` / `SecretaryUIComponents` (`AsyncImage` when `URL(string:)` succeeds).
final class DirectorySearchProfilePhotoDecodeTests: XCTestCase {

    func test_searchJSON_publicProfile_primaryImageURL_roundTripsForCodableMirror() throws {
        let expectedURL = "https://federation.fixture.example/media/upload/abc123_node.png"
        let fixture = """
        {
          "ok": true,
          "count": 1,
          "source": "server_public_recall",
          "requestedLimit": 10,
          "recallLimit": 48,
          "searchedAt": "2026-01-02T03:04:05.067Z",
          "note": "Fixture",
          "results": [
            {
              "nodeID": "fixture-node-photo-1",
              "displayName": "Fixture Seller",
              "publicProfile": {
                "id": "fixture-profile-photo-1",
                "nodeID": "fixture-node-photo-1",
                "displayName": "Fixture Seller",
                "headline": "Fixture headline",
                "summary": "Fixture summary",
                "visibility": "discoverable",
                "availability": "open",
                "interests": [],
                "offers": [],
                "openTo": [],
                "excludedTopics": [],
                "activityTags": [],
                "regionTags": [],
                "canonicalRegionIDs": [],
                "parentRegionIDs": [],
                "regionAliases": [],
                "semantic": {
                  "domains": [],
                  "fulfillmentModes": [],
                  "audienceKinds": [],
                  "intentKinds": []
                },
                "reachability": {
                  "acceptingInbound": true,
                  "accessMode": "direct",
                  "disclosureCeiling": "balanced",
                  "routeableOnly": false,
                  "intentCategoryPolicy": "permissive"
                },
                "approach": {
                  "engagementStyle": "adaptive",
                  "decisionStyle": "collaborative",
                  "communicationStyle": "direct"
                },
                "primaryImageURL": "\(expectedURL)"
              },
              "offers": [],
              "retrievalDocuments": [],
              "retrievalScore": 12.5,
              "score": 12.5,
              "matchedTerms": ["fixture"],
              "matchReason": "Directory recall candidate. Final viability is decided locally."
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MirrorDirectorySearchResponse.self, from: fixture)
        XCTAssertTrue(decoded.ok)
        let profileURL = try XCTUnwrap(decoded.results.first?.publicProfile.primaryImageURL)
        XCTAssertEqual(profileURL, expectedURL)
    }

    /// Narrow mirror of the server search envelope + `publicProfile` keys the client decoder cares about.
    private struct MirrorDirectorySearchResponse: Decodable {
        let ok: Bool
        let results: [MirrorRow]

        private enum CodingKeys: String, CodingKey {
            case ok
            case results
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.ok = try c.decode(Bool.self, forKey: .ok)
            self.results = try c.decodeIfPresent([MirrorRow].self, forKey: .results) ?? []
        }
    }

    private struct MirrorRow: Decodable {
        let publicProfile: MirrorPublicProfile
    }

    private struct MirrorPublicProfile: Decodable {
        let primaryImageURL: String?
    }
}
