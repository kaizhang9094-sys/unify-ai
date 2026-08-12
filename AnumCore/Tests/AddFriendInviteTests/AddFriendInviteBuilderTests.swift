import XCTest
@testable import AnumCore

final class AddFriendInviteBuilderTests: XCTestCase {
    private let sampleNodeID = "node-test-add-friend-1"
    private let appStoreURL = "https://apps.apple.com/app/id6757502298"

    func testAppStoreDownloadURL() {
        XCTAssertEqual(AddFriendInviteBuilder.appStoreDownloadURL, appStoreURL)
    }

    func testInviteShareTextContainsAppStoreURL() {
        let text = AddFriendInviteBuilder.inviteShareText(nodeID: sampleNodeID)
        XCTAssertTrue(text.contains("apps.apple.com/app/id6757502298"))
    }

    func testInviteShareTextContainsNodeID() {
        let text = AddFriendInviteBuilder.inviteShareText(nodeID: sampleNodeID)
        XCTAssertTrue(text.contains(sampleNodeID))
    }

    func testInviteShareTextDoesNotProduceWebsiteOnlyInvite() {
        let text = AddFriendInviteBuilder.inviteShareText(nodeID: sampleNodeID)
        XCTAssertFalse(text.contains("unify-now.com/invite/"))
    }

    func testInviteShareTextWithDisplayNameUsesPersonalizedIntro() {
        let text = AddFriendInviteBuilder.inviteShareText(nodeID: sampleNodeID, displayName: "Kai")
        XCTAssertTrue(text.contains("Kai invited you to connect on Unify."))
        XCTAssertTrue(text.contains(sampleNodeID))
        XCTAssertTrue(text.contains(appStoreURL))
    }

    func testNodeIDForCopyReturnsExactlyRawNodeID() {
        XCTAssertEqual(
            AddFriendInviteBuilder.nodeIDForCopy("  \(sampleNodeID)  "),
            sampleNodeID
        )
    }

    func testNodeIDForCopyDoesNotContainAppStoreURL() {
        let copied = AddFriendInviteBuilder.nodeIDForCopy(sampleNodeID)
        XCTAssertFalse(copied.contains("apps.apple.com"))
    }

    func testNodeIDForCopyDoesNotContainWebsiteInvite() {
        let copied = AddFriendInviteBuilder.nodeIDForCopy(sampleNodeID)
        XCTAssertFalse(copied.contains("unify-now.com"))
    }

    func testNodeIDQRPayloadReturnsExactlyRawNodeID() {
        XCTAssertEqual(
            AddFriendInviteBuilder.nodeIDQRPayload("  \(sampleNodeID)  "),
            sampleNodeID
        )
    }

    func testNodeIDQRPayloadDoesNotContainAppStoreURL() {
        let qr = AddFriendInviteBuilder.nodeIDQRPayload(sampleNodeID)
        XCTAssertFalse(qr.contains("apps.apple.com"))
    }

    func testNodeIDQRPayloadDoesNotContainWebsiteInvite() {
        let qr = AddFriendInviteBuilder.nodeIDQRPayload(sampleNodeID)
        XCTAssertFalse(qr.contains("unify-now.com"))
    }

    func testLegacyInviteWebURLStillReturnsWebsiteInvitePath() {
        XCTAssertEqual(
            AddFriendInviteBuilder.legacyInviteWebURL(nodeID: sampleNodeID),
            "https://unify-now.com/invite/\(sampleNodeID)"
        )
    }
}
