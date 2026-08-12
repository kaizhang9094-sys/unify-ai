import XCTest
@testable import AnumCore

final class ExchangeSellerSurfaceIndexedRetrievalParityTests: XCTestCase {
    private let service = ExchangeDefaultSellerSurfaceService()
    private let now = Date(timeIntervalSince1970: 1_726_100_000)

    func test_parity_coreAnchorsAndPostureStable() {
        let profile = fixtureProfile()
        let offers = [fixtureOffer(id: "offer-1"), fixtureOffer(id: "offer-2", visibility: .limitedSurface)]

        let oldDocs = service.buildRetrievalDocumentsLegacyDirect(
            ownerNodeID: "cp-1",
            publicProfile: profile,
            offers: offers
        )
        let newDocs = service.buildRetrievalDocumentsFromIndexedSurface(
            ownerNodeID: "cp-1",
            publicProfile: profile,
            offers: offers
        )

        let oldOfferIDs = Set(oldDocs.compactMap(\.offerID))
        let newOfferIDs = Set(newDocs.compactMap(\.offerID))
        XCTAssertEqual(oldOfferIDs, newOfferIDs)

        XCTAssertEqual(
            Set(oldDocs.map(\.surfaceType.rawValue)),
            Set(newDocs.map(\.surfaceType.rawValue))
        )

        XCTAssertTrue(newDocs.allSatisfy { $0.nodeID == "node-1" })
        XCTAssertTrue(newDocs.allSatisfy { $0.publicProfileID == "profile-1" || $0.publicProfileID == nil })
        XCTAssertTrue(newDocs.allSatisfy { $0.sourceKind == .local })
    }

    func test_indexedPath_preservesOldSearchableText_andAddsOpenEndedEvidence() {
        let profile = fixtureProfile(
            summary: "Works with first-time developers.",
            notes: "Accepts small renovation budgets."
        )
        let offer = fixtureOffer(
            id: "offer-vtb",
            summary: "Seller financing available.",
            semanticNotes: "Vendor take-back mortgage considered."
        )

        let oldDocs = service.buildRetrievalDocumentsLegacyDirect(
            ownerNodeID: "cp-1",
            publicProfile: profile,
            offers: [offer]
        )
        let newDocs = service.buildRetrievalDocumentsFromIndexedSurface(
            ownerNodeID: "cp-1",
            publicProfile: profile,
            offers: [offer]
        )

        let oldText = oldDocs.map(\.searchableText).joined(separator: " ").lowercased()
        let newText = newDocs.map(\.searchableText).joined(separator: " ").lowercased()
        XCTAssertTrue(newText.contains("seller financing"))
        XCTAssertTrue(newText.contains("vendor take-back mortgage"))
        XCTAssertTrue(newText.contains("works with first-time developers"))
        XCTAssertTrue(newText.contains("accepts small renovation budgets"))
        XCTAssertTrue(oldText.contains("seller financing"))
    }

    func test_hiddenInactiveFiltering_matchesExistingBehavior() {
        let profile = fixtureProfile()
        let activeVisible = fixtureOffer(id: "offer-live", status: .active, visibility: .publicDiscoverable)
        let activeHidden = fixtureOffer(id: "offer-hidden", status: .active, visibility: .hidden)
        let pausedVisible = fixtureOffer(id: "offer-paused", status: .paused, visibility: .publicDiscoverable)

        let oldDocs = service.buildRetrievalDocumentsLegacyDirect(
            ownerNodeID: "cp-1",
            publicProfile: profile,
            offers: [activeVisible, activeHidden, pausedVisible]
        )
        let newDocs = service.buildRetrievalDocumentsFromIndexedSurface(
            ownerNodeID: "cp-1",
            publicProfile: profile,
            offers: [activeVisible, activeHidden, pausedVisible]
        )

        let oldOfferIDs = Set(oldDocs.filter { $0.surfaceType == .offer }.compactMap(\.offerID))
        let newOfferIDs = Set(newDocs.filter { $0.surfaceType == .offer }.compactMap(\.offerID))
        XCTAssertEqual(oldOfferIDs, newOfferIDs)
        XCTAssertTrue(newOfferIDs.contains("offer-live"))
        XCTAssertFalse(newOfferIDs.contains("offer-hidden"))
        XCTAssertFalse(newOfferIDs.contains("offer-paused"))
    }
}

private extension ExchangeSellerSurfaceIndexedRetrievalParityTests {
    func fixtureProfile(
        summary: String = "Profile summary",
        notes: String = "Open-ended profile note"
    ) -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            displayName: "Builder Profile",
            headline: "Local contractor network",
            summary: summary,
            visibility: .discoverable,
            interests: ["housing"],
            offers: ["contractor matching"],
            openTo: ["home renovation help"],
            activityTags: ["contractor"],
            regionTags: ["gta"],
            canonicalRegionIDs: ["ca-on-gta"],
            parentRegionIDs: ["ca-on"],
            regionAliases: ["greater toronto area"],
            semantic: .init(
                domains: ["real estate"],
                intentKinds: ["service"],
                notes: notes
            ),
            availability: .open,
            updatedAt: now
        )
    }

    func fixtureOffer(
        id: String,
        summary: String = "Offer summary",
        semanticNotes: String = "Offer semantic note",
        status: ExchangeOffer.Status = .active,
        visibility: ExchangeOffer.Visibility = .publicDiscoverable
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: id,
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Home support offer",
            summary: summary,
            category: "contractor",
            tags: ["home", "renovation"],
            regionTags: ["gta"],
            semantic: .init(
                domains: ["real estate"],
                serviceKinds: ["contractor"],
                notes: semanticNotes
            ),
            status: status,
            visibility: visibility,
            updatedAt: now
        )
    }
}
