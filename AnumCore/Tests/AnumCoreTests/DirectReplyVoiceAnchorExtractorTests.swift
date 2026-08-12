import XCTest
@testable import AnumCore

final class DirectReplyVoiceAnchorExtractorTests: XCTestCase {
    func testDropsBeenAMinuteLocalLine() {
        let anchors = DirectReplyVoiceAnchorExtractor.extract(from: [
            msg(.remoteContact, "Hey! Long time."),
            msg(.localUser, "Yeah it's been a minute."),
            msg(.remoteContact, "Want to grab coffee Saturday morning?"),
        ])
        XCTAssertTrue(anchors.isEmpty)
    }

    func testDropsCafeAtThreeLocalLine() {
        let anchors = DirectReplyVoiceAnchorExtractor.extract(from: [
            msg(.localUser, "See you at the cafe at 3."),
            msg(.remoteContact, "Still good?"),
        ])
        XCTAssertTrue(anchors.isEmpty)
    }

    func testDropsYesSevenWorksLocalLine() {
        let anchors = DirectReplyVoiceAnchorExtractor.extract(from: [
            msg(.localUser, "Yes — 7 works."),
            msg(.remoteContact, "Dinner Friday?"),
        ])
        XCTAssertTrue(anchors.isEmpty)
    }

    func testDropsDeckPromiseLocalLine() {
        let anchors = DirectReplyVoiceAnchorExtractor.extract(from: [
            msg(.localUser, "I'll pull the deck together tonight."),
            msg(.localUser, "Sounds good to me."),
        ])
        XCTAssertFalse(anchors.contains(where: { $0.text.contains("deck") }))
        XCTAssertTrue(anchors.contains(where: { $0.text == "Sounds good to me." }))
    }

    func testKeepsNoWorriesWhenNotInLatestTwo() {
        let anchors = DirectReplyVoiceAnchorExtractor.extract(from: [
            msg(.localUser, "No worries."),
            msg(.remoteContact, "Running late?"),
            msg(.localUser, "Yeah it's been a minute."),
            msg(.remoteContact, "Want coffee?"),
        ])
        XCTAssertTrue(anchors.contains(where: { $0.text == "No worries." }))
    }

    func testLatestTwoLocalMessagesAreNotUsedAsAnchors() {
        let anchors = DirectReplyVoiceAnchorExtractor.extract(from: [
            msg(.localUser, "No worries."),
            msg(.localUser, "Yeah it's been a minute."),
            msg(.remoteContact, "Want coffee?"),
        ])
        XCTAssertFalse(anchors.contains(where: { $0.text.contains("been a minute") }))
    }

    func testNeverUsesRemoteContactLines() {
        let anchors = DirectReplyVoiceAnchorExtractor.extract(from: [
            msg(.remoteContact, "Running about 10 min late — still good?"),
            msg(.remoteContact, "See you soon."),
        ])
        XCTAssertTrue(anchors.isEmpty)
    }

    private func msg(
        _ role: ExchangeModels.DirectReplyTranscriptRole,
        _ text: String
    ) -> ExchangeModels.DirectReplyTranscriptMessage {
        ExchangeModels.DirectReplyTranscriptMessage(role: role, text: text)
    }
}
