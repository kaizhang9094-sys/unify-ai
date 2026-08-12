import XCTest
@testable import AnumCore

final class ExchangeThreadCardTitleProjectionTests: XCTestCase {

    func testRequesterQueryTitleStillWinsOverStoredStatus() {
        let pick = ExchangeThreadCardTitleProjection.inboxCardTitle(
            requestCapturedFromTurn: "Find me a VC",
            interpretationUserQuestion: nil,
            threadStoredTitle: "Response received",
            draftedSubject: nil,
            hydratedOpportunityTitle: nil,
            prioritizeHydratedOpportunityTitle: false,
            threadID: nil,
            surface: "test"
        )
        XCTAssertEqual(pick.title, "Find me a VC")
        XCTAssertEqual(pick.titleSource, "capturedRequest")
    }

    func testLifecycleStatusTitlesRejectedAsPrimaryCandidates() {
        XCTAssertTrue(ExchangeThreadCardTitleProjection.isExchangeLifecycleStatusTitle("Response received"))
        XCTAssertTrue(ExchangeThreadCardTitleProjection.isExchangeLifecycleStatusTitle("Waiting for reply"))
        XCTAssertTrue(
            ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate(
                "Counterparty is asking for additional information."
            )
        )
        XCTAssertFalse(ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate("Find me a cleaner tomorrow"))
    }

    func testProviderInboundRejectsResponseReceived() {
        let pick = ExchangeThreadCardTitleProjection.inboundProviderInquiryTitlePick(
            inboundRequesterAsk: nil,
            inquirySummary: nil,
            hydratedOpportunityTitle: nil,
            inboundSenderDisplay: nil,
            threadStoredTitle: "Response received",
            threadID: nil,
            surface: "test"
        )
        XCTAssertEqual(pick.title, "New inquiry")
        XCTAssertNotEqual(pick.title, "Response received")
    }

    func testProviderInboundUsesInboundAskWhenAvailable() {
        let ask = "Are you currently open to hearing from early-stage founders?"
        let pick = ExchangeThreadCardTitleProjection.inboundProviderInquiryTitlePick(
            inboundRequesterAsk: ask,
            inquirySummary: nil,
            hydratedOpportunityTitle: "VC",
            inboundSenderDisplay: "Kai",
            threadStoredTitle: "Response received",
            threadID: nil,
            surface: "test"
        )
        XCTAssertEqual(pick.title, ask)
        XCTAssertEqual(pick.titleSource, "inboundRequesterAsk")
    }

    func testProviderInboundFallsBackToInquiryFromSender() {
        let pick = ExchangeThreadCardTitleProjection.inboundProviderInquiryTitlePick(
            inboundRequesterAsk: nil,
            inquirySummary: nil,
            hydratedOpportunityTitle: nil,
            inboundSenderDisplay: "Kai",
            threadStoredTitle: "Response received",
            threadID: nil,
            surface: "test"
        )
        XCTAssertEqual(pick.title, "Inquiry from Kai")
        XCTAssertEqual(pick.titleSource, "inboundSenderDisplay")
    }

    func testProviderInboundUsesHydratedOpportunityTitle() {
        let pick = ExchangeThreadCardTitleProjection.inboundProviderInquiryTitlePick(
            inboundRequesterAsk: nil,
            inquirySummary: nil,
            hydratedOpportunityTitle: "VC inquiry",
            inboundSenderDisplay: "Kai",
            threadStoredTitle: "Response received",
            threadID: nil,
            surface: "test"
        )
        XCTAssertEqual(pick.title, "VC inquiry")
        XCTAssertEqual(pick.titleSource, "inboundInquiryHydrated")
    }

    func testProviderInboundDoesNotUseHumanRequesterTextAsStoredTitle() {
        let pick = ExchangeThreadCardTitleProjection.inboundProviderInquiryTitlePick(
            inboundRequesterAsk: nil,
            inquirySummary: nil,
            hydratedOpportunityTitle: nil,
            inboundSenderDisplay: nil,
            threadStoredTitle: "Shjshsbjshs",
            threadID: nil,
            surface: "test"
        )
        XCTAssertEqual(pick.title, "New inquiry")
        XCTAssertNotEqual(pick.title, "Shjshsbjshs")
    }

    func testDirectMessagePersonTitleViaRequesterLane() {
        let pick = ExchangeThreadCardTitleProjection.inboxCardTitle(
            requestCapturedFromTurn: nil,
            interpretationUserQuestion: nil,
            threadStoredTitle: "Kai",
            draftedSubject: nil,
            hydratedOpportunityTitle: nil,
            prioritizeHydratedOpportunityTitle: false,
            threadID: nil,
            surface: "test"
        )
        XCTAssertEqual(pick.title, "Kai")
    }

    func testIsProviderInboundThreadDetection() {
        XCTAssertTrue(
            ExchangeThreadCardTitleProjection.isProviderInboundThread(metadata: ["inbound_thread": "true"])
        )
        XCTAssertFalse(
            ExchangeThreadCardTitleProjection.isProviderInboundThread(metadata: ["inbound_thread": "false"])
        )
    }
}
