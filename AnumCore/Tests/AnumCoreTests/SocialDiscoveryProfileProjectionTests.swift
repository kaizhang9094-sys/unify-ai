import XCTest
@testable import AnumCore

final class SocialDiscoveryProfileProjectionTests: XCTestCase {
    func testMapsCounterpartyAndPublicProfileIDsFromThreadDetail() {
        let counterpartyID = "node-social-1"
        let profileID = "profile-social-1"
        let detail = makeSocialThreadDetail(
            counterpartyID: counterpartyID,
            publicProfileID: profileID,
            displayName: "Alex Rivera",
            headline: "Product designer",
            summary: "Loves hiking and coffee.",
            matchWhy: "Shared interest in design"
        )

        let item = SocialDiscoveryProfileProjection.forYouItem(from: detail)

        XCTAssertEqual(item.nodeID, counterpartyID)
        XCTAssertEqual(item.publicProfileID, profileID)
        XCTAssertEqual(item.displayName, "Alex Rivera")
        XCTAssertEqual(item.headline, "Product designer")
        XCTAssertEqual(item.matchReasonSummary, "Shared interest in design")
        XCTAssertNil(item.linkedThreadID)
        XCTAssertNil(item.topOfferTitle)
        XCTAssertTrue(item.surfacedOfferImageURLs.isEmpty)
    }

    func testPreservesMatchReasonAndPublicSummaryInFactLines() {
        let detail = makeSocialThreadDetail(
            counterpartyID: "node-2",
            publicProfileID: "profile-2",
            displayName: "Sam",
            headline: nil,
            summary: "Builder and mentor.",
            matchWhy: "Aligned on mentorship"
        )

        let item = SocialDiscoveryProfileProjection.forYouItem(from: detail)

        XCTAssertTrue(
            item.discoveryFactLines.contains(where: { $0.contains("Match:") })
            || item.matchReasonSummary == "Aligned on mentorship"
        )
        XCTAssertTrue(item.publicFactLines.contains(where: { $0.contains("About: Builder and mentor.") }))
    }

    func testInboxProjectionDoesNotUseSelectedOfferIDForSocialProfileCTA() {
        let threadID = UUID()
        let inbox = ExchangeModels.InboxItem(
            threadID: threadID,
            title: "Find designers",
            subtitle: "Profile connection",
            state: .matchFound(.init(candidateCount: 1, summary: "Match found")),
            stateTitle: "Match found",
            updatedAt: Date(),
            requiresHumanDecision: false,
            hasFailure: false,
            selectedCounterpartyID: "node-3",
            selectedPublicProfileID: "profile-3",
            selectedOfferID: UUID(),
            selectedMatchWhy: "Profile-led match",
            surfaceListImageURLCandidates: ["https://example.com/hero.jpg"]
        )

        let item = SocialDiscoveryProfileProjection.forYouItem(from: inbox)

        XCTAssertEqual(item.nodeID, "node-3")
        XCTAssertEqual(item.publicProfileID, "profile-3")
        XCTAssertEqual(item.primaryImageURL, "https://example.com/hero.jpg")
        XCTAssertNil(item.topOfferTitle)
        XCTAssertNil(item.linkedThreadID)
    }

    private func makeSocialThreadDetail(
        counterpartyID: String,
        publicProfileID: String,
        displayName: String,
        headline: String?,
        summary: String,
        matchWhy: String
    ) -> ExchangeModels.ThreadDetail {
        let profile = ExchangePublicNodeProfile(
            id: publicProfileID,
            nodeID: counterpartyID,
            displayName: displayName,
            headline: headline,
            summary: summary,
            primaryImageURL: "https://example.com/profile.jpg"
        )
        let counterparty = ExchangeCounterparty(
            id: counterpartyID,
            kind: .person,
            displayName: displayName,
            source: .localDirectory,
            publicProfile: profile
        )
        let match = ExchangeMatch(
            threadID: UUID(),
            counterpartyID: counterpartyID,
            strength: .moderate,
            score: 0.82,
            publicProfileID: publicProfileID,
            recommendation: matchWhy,
            metadata: [
                "public_profile_display_name": displayName,
                "public_profile_summary": summary
            ]
        )
        let thread = ExchangeThread(
            mode: .relational,
            intent: ExchangeIntent(
                kind: .find,
                mode: .relational,
                queryIntentClass: .socialAffinitySearch,
                surfacePreference: .affinity,
                title: "Find people",
                objective: "Find people"
            ),
            posture: ExchangePosture(),
            state: .matchFound(.init(candidateCount: 1, summary: "Match found")),
            selectedCounterpartyID: counterpartyID,
            selectedPublicProfileID: publicProfileID,
            selectedMatchRationale: matchWhy,
            metadata: [
                ExchangeThreadLaneResolver.metadataKey: ExchangeThreadLane.socialConnection.rawValue
            ]
        )

        return ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [match],
            counterparties: [counterparty],
            artifacts: [],
            summary: "Profile connection",
            selectedCounterparty: counterparty,
            selectedPublicProfileID: publicProfileID,
            selectedMatch: match
        )
    }
}
