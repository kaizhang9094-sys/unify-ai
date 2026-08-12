import XCTest
@testable import AnumCore

final class SocialDiscoveryOpenRoutingTests: XCTestCase {
    func testSocialConnectionLaneOpensProfileDetailNotThreadRoute() {
        let thread = makeThread(lane: .socialConnection)
        XCTAssertTrue(SocialDiscoveryOpenRouting.shouldPresentProfileDetail(for: thread))
    }

    func testCommercialInquiryLaneStillOpensThreadRoute() {
        let thread = makeThread(lane: .commercialInquiry)
        XCTAssertFalse(SocialDiscoveryOpenRouting.shouldPresentProfileDetail(for: thread))
    }

    func testDirectMessageLaneDoesNotOpenSocialProfileDetail() {
        var thread = makeThread(lane: .directMessage)
        thread.metadata["direct_message_thread"] = "true"
        XCTAssertFalse(SocialDiscoveryOpenRouting.shouldPresentProfileDetail(for: thread))
    }

    private func makeThread(lane: ExchangeThreadLane) -> ExchangeThread {
        ExchangeThread(
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
            metadata: [
                ExchangeThreadLaneResolver.metadataKey: lane.rawValue
            ]
        )
    }
}
