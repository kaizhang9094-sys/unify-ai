import Foundation
import XCTest
@testable import AnumCore

final class ExchangeContactSignalClassifierTests: XCTestCase {

    private func inboxItem(metadata: [String: String]) -> ExchangeInboxItem {
        ExchangeInboxItem(
            envelopeID: "env-\(UUID().uuidString)",
            senderNodeID: "node-remote",
            senderDisplayName: "Remote",
            receivedAt: Date(),
            metadata: metadata
        )
    }

    func testLegacyIntroductionContactRequest_classifiedAsContactSignal() {
        let item = inboxItem(metadata: [
            "contact_request": "true",
            "payload_kind": ExchangeRelayEnvelope.Payload.Kind.introduction.rawValue
        ])
        XCTAssertTrue(ExchangeContactSignalClassifier.isInboundContactRequest(item))
    }

    func testFriendRequestPayloadKind_classifiedAsContactSignal() {
        let item = inboxItem(metadata: [
            "payload_kind": ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue
        ])
        XCTAssertTrue(ExchangeContactSignalClassifier.isInboundContactRequest(item))
    }

    func testFriendRequestAccepted_notPendingContactRequest() {
        let item = inboxItem(metadata: [
            "payload_kind": ExchangeRelayEnvelope.Payload.Kind.friendRequestAccepted.rawValue
        ])
        XCTAssertTrue(ExchangeContactSignalClassifier.isInboundContactRequestAcceptance(item))
        XCTAssertFalse(ExchangeContactSignalClassifier.isInboundContactRequest(item))
    }
}
