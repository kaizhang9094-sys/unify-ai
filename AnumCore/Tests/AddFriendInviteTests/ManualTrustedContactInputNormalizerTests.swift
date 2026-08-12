import XCTest
@testable import AnumCore

final class ManualTrustedContactInputNormalizerTests: XCTestCase {
    private let sampleNodeID = "node-test-add-friend-1"
    private let appStoreURL = "https://apps.apple.com/app/id6757502298"

    func testParsesRawNodeID() {
        let result = ManualTrustedContactInputNormalizer.parse(sampleNodeID)
        XCTAssertEqual(result.nodeID, sampleNodeID)
        XCTAssertTrue(result.source == .raw || result.source == .embedded)
    }

    func testParsesLegacyWebsiteInviteURL() {
        let legacy = AddFriendInviteBuilder.legacyInviteWebURL(nodeID: sampleNodeID)
        let result = ManualTrustedContactInputNormalizer.parse(legacy)
        XCTAssertEqual(result.nodeID, sampleNodeID)
        XCTAssertTrue(result.source == .link || result.source == .embedded)
    }

    func testParsesMultilineInviteShareText() {
        let inviteText = AddFriendInviteBuilder.inviteShareText(nodeID: sampleNodeID, displayName: "Kai")
        let result = ManualTrustedContactInputNormalizer.parse(inviteText)
        XCTAssertEqual(result.nodeID, sampleNodeID)
        XCTAssertEqual(result.source, .embedded)
    }

    func testDoesNotParseBareAppStoreURLWithoutNodeID() {
        let result = ManualTrustedContactInputNormalizer.parse(appStoreURL)
        XCTAssertNil(result.nodeID)
        XCTAssertEqual(result.source, .failed)
    }
}
