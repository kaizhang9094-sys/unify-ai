import XCTest
@testable import AnumCore

final class ExchangeInboundOpenRoutingTests: XCTestCase {

    func testInboundThreadWithProviderInquiryIntentRoutesToExchangeThread() {
        let decision = ExchangeInboundOpenRouting.routeDecision(
            threadMetadata: ["inbound_thread": "true"],
            intent: .providerInquiry
        )
        XCTAssertEqual(decision.route, .exchangeThread)
        XCTAssertEqual(decision.reason, "inbound_provider_desk")
    }

    func testInboundThreadWithDirectMessageIntentDoesNotRouteToExchangeThread() {
        let decision = ExchangeInboundOpenRouting.routeDecision(
            threadMetadata: ["inbound_thread": "true"],
            intent: .directMessage
        )
        XCTAssertEqual(decision.route, .directMessage)
        XCTAssertEqual(decision.reason, "direct_message_intent_ignore_exchange_metadata")
    }

    func testDirectMessageThreadWithDirectMessageIntentRoutesToDirectMessage() {
        let decision = ExchangeInboundOpenRouting.routeDecision(
            threadMetadata: ["direct_message_thread": "true"],
            intent: .directMessage
        )
        XCTAssertEqual(decision.route, .directMessage)
        XCTAssertEqual(decision.reason, "direct_message_thread")
    }

    func testExchangeSurfaceWithAutoIntentRoutesToExchangeThread() {
        let decision = ExchangeInboundOpenRouting.routeDecision(
            threadMetadata: ["conversation_surface": "exchange_thread"],
            intent: .auto
        )
        XCTAssertEqual(decision.route, .exchangeThread)
        XCTAssertEqual(decision.reason, "conversation_surface_exchange_thread")
    }

    func testDirectMessageThreadWinsOverInboundThreadMetadata() {
        let decision = ExchangeInboundOpenRouting.routeDecision(
            threadMetadata: [
                "direct_message_thread": "true",
                "inbound_thread": "true",
            ],
            intent: .auto
        )
        XCTAssertEqual(decision.route, .directMessage)
        XCTAssertEqual(decision.reason, "direct_message_thread")
    }

    func testDirectMessageThreadWinsOverInboundThreadWithProviderInquiryIntent() {
        let decision = ExchangeInboundOpenRouting.routeDecision(
            threadMetadata: [
                "direct_message_thread": "true",
                "inbound_thread": "true",
            ],
            intent: .providerInquiry
        )
        XCTAssertEqual(decision.route, .directMessage)
        XCTAssertEqual(decision.reason, "direct_message_thread")
    }

    func testNoIntentWrapperMatchesAutoForInboundThread() {
        let auto = ExchangeInboundOpenRouting.routeDecision(
            threadMetadata: ["inbound_thread": "true"],
            intent: .auto
        )
        let legacy = ExchangeInboundOpenRouting.routeDecision(
            threadMetadata: ["inbound_thread": "true"]
        )
        XCTAssertEqual(auto, legacy)
    }

    func testDirectMessageIntentPrefersResolvedCandidateOnly() {
        let linked = UUID()
        let canonical = UUID()
        let candidates = ExchangeInboundDirectMessageOpenResolver.routingCandidateThreadIDs(
            intent: .directMessage,
            rowLinkedThreadID: linked,
            resolvedThreadID: canonical
        )
        XCTAssertEqual(candidates, [canonical])
        XCTAssertTrue(
            ExchangeInboundDirectMessageOpenResolver.shouldSkipLinkedExchangeHydration(
                intent: .directMessage,
                rowLinkedThreadID: linked,
                resolvedThreadID: canonical
            )
        )
    }

    func testProviderInquiryIntentStillConsidersLinkedThreadFirst() {
        let linked = UUID()
        let other = UUID()
        let candidates = ExchangeInboundDirectMessageOpenResolver.routingCandidateThreadIDs(
            intent: .providerInquiry,
            rowLinkedThreadID: linked,
            resolvedThreadID: other
        )
        XCTAssertEqual(candidates, [linked, other])
    }

    func testDirectMessageIntentWithoutResolvedFallsBackToLinkedOnly() {
        let linked = UUID()
        let candidates = ExchangeInboundDirectMessageOpenResolver.routingCandidateThreadIDs(
            intent: .directMessage,
            rowLinkedThreadID: linked,
            resolvedThreadID: nil
        )
        XCTAssertEqual(candidates, [linked])
    }
}
