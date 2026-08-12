import XCTest
@testable import AnumCore

final class ExchangeSupporterPresentationSafetyTests: XCTestCase {
    private func profileWithGuardianCrown() -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: "profile-guardian",
            nodeID: "node-guardian",
            displayName: "Guardian Provider",
            headline: "Headline",
            summary: "Summary",
            interests: ["interest-a"],
            offers: ["offer-a"],
            openTo: ["open-a"],
            activityTags: ["tag-a"],
            regionTags: ["region-a"],
            publicSupporterPresentation: .guardianCrown()
        )
    }

    func testSearchableTextIgnoresGuardianCrown() {
        let profile = profileWithGuardianCrown()
        let baseline = ExchangePublicNodeProfile(
            id: profile.id,
            nodeID: profile.nodeID,
            displayName: profile.displayName,
            headline: profile.headline,
            summary: profile.summary,
            interests: profile.interests,
            offers: profile.offers,
            openTo: profile.openTo,
            activityTags: profile.activityTags,
            regionTags: profile.regionTags
        )
        XCTAssertEqual(profile.searchableText, baseline.searchableText)
    }

    func testCoordinationTokensIgnoreGuardianCrown() {
        let profile = profileWithGuardianCrown()
        var without = profile
        without.publicSupporterPresentation = nil
        XCTAssertEqual(profile.coordinationTokens, without.coordinationTokens)
    }

    func testDecodeLegacyProfileWithoutSupporterPresentation() throws {
        let original = ExchangePublicNodeProfile(
            id: "legacy-profile",
            nodeID: "legacy-node",
            visibility: .discoverable,
            availability: .open
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExchangePublicNodeProfile.self, from: data)
        XCTAssertNil(decoded.publicSupporterPresentation)
    }

    func testRetrievalDocumentBuilderIgnoresGuardianCrown() {
        let profile = profileWithGuardianCrown()
        var without = profile
        without.publicSupporterPresentation = nil

        let counterpartyWith = ExchangeCounterparty(
            id: profile.nodeID,
            kind: .organization,
            displayName: profile.displayName ?? profile.nodeID,
            source: .relayNetwork,
            publicProfile: profile
        )
        let counterpartyWithout = ExchangeCounterparty(
            id: without.nodeID,
            kind: .organization,
            displayName: without.displayName ?? without.nodeID,
            source: .relayNetwork,
            publicProfile: without
        )

        let builder = ExchangeRetrievalDocumentBuilder()
        let docsWith = builder.buildDocuments(counterparties: [counterpartyWith], sourceKind: .local)
        let docsWithout = builder.buildDocuments(counterparties: [counterpartyWithout], sourceKind: .local)

        XCTAssertEqual(docsWith.count, docsWithout.count)
        let lexicalWith = docsWith.map(\.lexicalText).sorted()
        let lexicalWithout = docsWithout.map(\.lexicalText).sorted()
        XCTAssertEqual(lexicalWith, lexicalWithout)
    }

    func testPublishedPayloadOmitsCrownWhenInactive() {
        let profile = profileWithGuardianCrown()
        let service = ExchangeDefaultSellerSurfaceService()
        var inactive = profile
        inactive.publicSupporterPresentation = nil
        let payload = service.buildPublishedPayload(
            ownerNodeID: profile.nodeID,
            ownerDisplayName: profile.displayName,
            publicProfile: inactive,
            offers: [],
            publicationState: nil,
            now: Date()
        )
        XCTAssertNil(payload.publicProfile.publicSupporterPresentation)
    }

    func testPublishedPayloadIncludesCrownWhenActive() {
        let profile = profileWithGuardianCrown()
        let service = ExchangeDefaultSellerSurfaceService()
        let payload = service.buildPublishedPayload(
            ownerNodeID: profile.nodeID,
            ownerDisplayName: profile.displayName,
            publicProfile: profile,
            offers: [],
            publicationState: nil,
            now: Date()
        )
        XCTAssertEqual(payload.publicProfile.publicSupporterPresentation, .guardianCrown())
    }
}
