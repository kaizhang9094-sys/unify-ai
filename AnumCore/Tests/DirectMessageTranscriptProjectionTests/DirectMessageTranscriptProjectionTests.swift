import Foundation
import XCTest

@testable import AnumCore

final class DirectMessageTranscriptProjectionTests: XCTestCase {

    private var clearWatermarkNodeIDs: [String] = []

    override func tearDown() {
        for nodeID in clearWatermarkNodeIDs {
            UserDefaults.standard.removeObject(
                forKey: DirectMessageTranscriptProjection.clearWatermarkKey(for: nodeID)
            )
        }
        clearWatermarkNodeIDs.removeAll()
        super.tearDown()
    }

    private func makeDirectMessageThread() -> ExchangeThread {
        ExchangeThread(
            mode: .relational,
            intent: ExchangeIntent(
                kind: .message,
                mode: .relational,
                title: "Direct message",
                objective: "Chat"
            ),
            posture: ExchangePosture(),
            state: .drafting,
            metadata: ["direct_message_thread": "true"]
        )
    }

    private func makeDetail(
        thread: ExchangeThread,
        turns: [ExchangeTurn] = [],
        drafts: [ExchangeMessageDraft] = [],
        inboxItems: [ExchangeInboxItem] = []
    ) -> ExchangeModels.ThreadDetail {
        ExchangeModels.ThreadDetail(
            thread: thread,
            turns: turns,
            approvals: [],
            drafts: drafts,
            matches: [],
            counterparties: [],
            artifacts: [],
            inboxItems: inboxItems,
            summary: "DM"
        )
    }

    private func manualDraft(
        threadID: ExchangeThread.ID,
        body: String,
        updatedAt: Date,
        metadata: [String: String] = ["trusted_node_manual_message": "true"]
    ) -> ExchangeMessageDraft {
        ExchangeMessageDraft(
            threadID: threadID,
            updatedAt: updatedAt,
            status: .sent,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: body,
            posture: ExchangePosture(),
            metadata: metadata
        )
    }

    private func counterpartyReply(
        threadID: ExchangeThread.ID,
        body: String,
        createdAt: Date
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .counterparty,
            kind: .replyReceived,
            summary: body,
            detail: body
        )
    }

    private func inboxItem(
        threadID: ExchangeThread.ID?,
        body: String,
        receivedAt: Date,
        metadata: [String: String] = [:]
    ) -> ExchangeInboxItem {
        var merged = metadata
        merged["body_preview"] = body
        return ExchangeInboxItem(
            receivedAt: receivedAt,
            envelopeID: "env-\(UUID().uuidString)",
            threadID: threadID,
            visibleSummary: body,
            metadata: merged
        )
    }

    private func trackClearWatermark(nodeID: String, clearedAt: Date) {
        clearWatermarkNodeIDs.append(nodeID)
        DirectMessageTranscriptProjection.setClearWatermark(at: clearedAt, for: nodeID)
    }

    func testBuildTranscriptRowsOrdersFourVisibleBubbles() {
        let thread = makeDirectMessageThread()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(60)
        let t2 = t0.addingTimeInterval(120)
        let t3 = t0.addingTimeInterval(180)

        let detail = makeDetail(
            thread: thread,
            turns: [
                counterpartyReply(threadID: thread.id, body: "Hello", createdAt: t0),
                counterpartyReply(threadID: thread.id, body: "Second", createdAt: t2),
            ],
            drafts: [
                manualDraft(threadID: thread.id, body: "My draft", updatedAt: t1),
                manualDraft(threadID: thread.id, body: "Fourth visible", updatedAt: t3),
            ]
        )

        let rendered = DirectMessageTranscriptProjection.buildTranscriptRows(
            detail: detail,
            counterpartyNodeID: "peer-a"
        )

        XCTAssertEqual(rendered.rows.count, 4)
        XCTAssertEqual(rendered.rows.map(\.body), ["Hello", "My draft", "Second", "Fourth visible"])
    }

    func testLatestVisiblePreviewMatchesLastTranscriptBubble() {
        let thread = makeDirectMessageThread()
        let base = Date(timeIntervalSince1970: 1_700_000_100)
        let detail = makeDetail(
            thread: thread,
            turns: [counterpartyReply(threadID: thread.id, body: "Earlier", createdAt: base)],
            drafts: [
                manualDraft(
                    threadID: thread.id,
                    body: "Latest bubble text for inbound",
                    updatedAt: base.addingTimeInterval(300)
                ),
            ]
        )

        let rendered = DirectMessageTranscriptProjection.buildTranscriptRows(
            detail: detail,
            counterpartyNodeID: "peer-preview"
        )
        let preview = DirectMessageTranscriptProjection.latestVisiblePreview(
            from: rendered.rows,
            counterpartyNodeID: "peer-preview"
        )

        XCTAssertEqual(preview, "Latest bubble text for inbound")
    }

    func testClearWatermarkHidesOlderTranscriptAndPreview() {
        let nodeID = "peer-clear-\(UUID().uuidString)"
        let thread = makeDirectMessageThread()
        let old = Date(timeIntervalSince1970: 1_700_000_200)
        let fresh = old.addingTimeInterval(600)

        let detail = makeDetail(
            thread: thread,
            turns: [counterpartyReply(threadID: thread.id, body: "Stale before clear", createdAt: old)],
            drafts: [manualDraft(threadID: thread.id, body: "Fresh after clear", updatedAt: fresh)]
        )

        trackClearWatermark(nodeID: nodeID, clearedAt: old.addingTimeInterval(30))

        let rendered = DirectMessageTranscriptProjection.buildTranscriptRows(
            detail: detail,
            counterpartyNodeID: nodeID
        )
        let visible = DirectMessageTranscriptProjection.rowsAfterClearWatermark(
            rendered.rows,
            counterpartyNodeID: nodeID
        )
        let preview = DirectMessageTranscriptProjection.latestVisiblePreview(
            from: rendered.rows,
            counterpartyNodeID: nodeID
        )

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.body, "Fresh after clear")
        XCTAssertEqual(preview, "Fresh after clear")
    }

    func testClearWatermarkWithNoVisibleRowsYieldsEmptyPreview() {
        let nodeID = "peer-empty-\(UUID().uuidString)"
        let thread = makeDirectMessageThread()
        let old = Date(timeIntervalSince1970: 1_700_000_300)

        let detail = makeDetail(
            thread: thread,
            turns: [counterpartyReply(threadID: thread.id, body: "Only old message", createdAt: old)]
        )

        trackClearWatermark(nodeID: nodeID, clearedAt: old.addingTimeInterval(1))

        let rendered = DirectMessageTranscriptProjection.buildTranscriptRows(
            detail: detail,
            counterpartyNodeID: nodeID
        )
        let preview = DirectMessageTranscriptProjection.latestVisiblePreview(
            from: rendered.rows,
            counterpartyNodeID: nodeID
        )

        XCTAssertTrue(preview.isEmpty)
        XCTAssertTrue(
            DirectMessageTranscriptProjection.rowsAfterClearWatermark(
                rendered.rows,
                counterpartyNodeID: nodeID
            ).isEmpty
        )
    }

    func testContactRequestInboxRowExcludedFromTranscript() {
        let thread = makeDirectMessageThread()
        let at = Date(timeIntervalSince1970: 1_700_000_400)
        let detail = makeDetail(
            thread: thread,
            inboxItems: [
                inboxItem(
                    threadID: thread.id,
                    body: "Please add me",
                    receivedAt: at,
                    metadata: ["contact_request": "true"]
                ),
            ]
        )

        let rendered = DirectMessageTranscriptProjection.buildTranscriptRows(
            detail: detail,
            counterpartyNodeID: "peer-contact"
        )

        XCTAssertTrue(rendered.rows.isEmpty)
        XCTAssertEqual(rendered.skippedContactRequestRows, 1)
    }

    func testAgencyDraftExcludedOnDirectMessageSurface() {
        let thread = makeDirectMessageThread()
        let at = Date(timeIntervalSince1970: 1_700_000_500)
        let detail = makeDetail(
            thread: thread,
            drafts: [
                manualDraft(
                    threadID: thread.id,
                    body: "Autonomous outreach",
                    updatedAt: at,
                    metadata: [
                        "trusted_node_manual_message": "true",
                        "second_half_generated": "true",
                    ]
                ),
            ]
        )

        let rendered = DirectMessageTranscriptProjection.buildTranscriptRows(
            detail: detail,
            counterpartyNodeID: "peer-agency"
        )

        XCTAssertTrue(rendered.rows.isEmpty)
    }

    func testInboxFiledToOtherThreadExcludedOnDMSurface() {
        let thread = makeDirectMessageThread()
        let otherThreadID = UUID()
        let at = Date(timeIntervalSince1970: 1_700_000_600)

        let detail = makeDetail(
            thread: thread,
            inboxItems: [
                inboxItem(threadID: otherThreadID, body: "Discovery leak", receivedAt: at),
                inboxItem(threadID: thread.id, body: "On-thread message", receivedAt: at.addingTimeInterval(10)),
            ]
        )

        let rendered = DirectMessageTranscriptProjection.buildTranscriptRows(
            detail: detail,
            counterpartyNodeID: "peer-thread-scope"
        )

        XCTAssertEqual(rendered.rows.count, 1)
        XCTAssertEqual(rendered.rows.first?.body, "On-thread message")
    }

    func testIsGenericInboundPlaceholderBody() {
        XCTAssertTrue(DirectMessageTranscriptProjection.isGenericInboundPlaceholderBody("Inbound message received."))
        XCTAssertTrue(DirectMessageTranscriptProjection.isGenericInboundPlaceholderBody("inbound message received"))
        XCTAssertFalse(DirectMessageTranscriptProjection.isGenericInboundPlaceholderBody("Photo caption"))
    }

    func testMediaInboundTurnSuppressesGenericPlaceholderBody() {
        let thread = makeDirectMessageThread()
        var metadata: [String: String] = [:]
        let attachment = DirectMessageAttachmentDescriptor(
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            byteSize: 1234,
            storageKey: "media/test.jpg",
            downloadPath: "/v1/dm-attachments/media/test.jpg"
        )
        DirectMessageAttachmentMetadata.apply(descriptors: [attachment], to: &metadata)

        let turn = ExchangeTurn(
            threadID: thread.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_900),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Inbound message received.",
            detail: nil,
            metadata: metadata
        )

        let rendered = DirectMessageTranscriptProjection.buildTranscriptRows(
            detail: makeDetail(thread: thread, turns: [turn]),
            counterpartyNodeID: "peer-media"
        )

        XCTAssertEqual(rendered.rows.count, 1)
        XCTAssertTrue(rendered.rows[0].body.isEmpty)
        XCTAssertEqual(rendered.rows[0].attachments.count, 1)
    }

    func testMediaInboundTurnPreservesRealCaption() {
        let thread = makeDirectMessageThread()
        var metadata: [String: String] = [:]
        let attachment = DirectMessageAttachmentDescriptor(
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            byteSize: 1234,
            storageKey: "media/test.jpg",
            downloadPath: "/v1/dm-attachments/media/test.jpg"
        )
        DirectMessageAttachmentMetadata.apply(descriptors: [attachment], to: &metadata)

        let turn = ExchangeTurn(
            threadID: thread.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_901),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Check this out",
            detail: "Check this out",
            metadata: metadata
        )

        let rendered = DirectMessageTranscriptProjection.buildTranscriptRows(
            detail: makeDetail(thread: thread, turns: [turn]),
            counterpartyNodeID: "peer-media-caption"
        )

        XCTAssertEqual(rendered.rows.count, 1)
        XCTAssertEqual(rendered.rows[0].body, "Check this out")
    }
}
