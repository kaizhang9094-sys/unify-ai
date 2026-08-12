import XCTest
@testable import AnumCore

final class ThreadTranscriptProviderInboundTests: XCTestCase {

    private let cleanOutbound = "Yes — we're open to hearing from early-stage founders, especially AI and pharmaceutical startups."

    private func providerInboundDetail(
        threadID: ExchangeThread.ID = UUID(),
        state: ExchangeState,
        turns: [ExchangeTurn],
        drafts: [ExchangeMessageDraft] = []
    ) -> ExchangeModels.ThreadDetail {
        var thread = ExchangeThread(
            id: threadID,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                title: "Inbound",
                objective: "Inbound"
            ),
            posture: ExchangePosture(privacy: .balanced),
            state: state
        )
        thread.metadata["inbound_thread"] = "true"
        return ExchangeModels.ThreadDetail(
            thread: thread,
            turns: turns,
            approvals: [],
            drafts: drafts,
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Inbound"
        )
    }

    private func inboundTurn(
        threadID: ExchangeThread.ID,
        summary: String,
        detail: String?,
        createdAt: Date
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .counterparty,
            kind: .replyReceived,
            summary: summary,
            detail: detail
        )
    }

    private func sentDraft(threadID: ExchangeThread.ID, body: String, updatedAt: Date) -> ExchangeMessageDraft {
        ExchangeMessageDraft(
            threadID: threadID,
            updatedAt: updatedAt,
            status: .sent,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: body,
            posture: ExchangePosture(privacy: .balanced)
        )
    }

    func testReplyReceivedSummaryScaffold_stripsToUserText() {
        let threadID = UUID()
        let detail = providerInboundDetail(
            threadID: threadID,
            state: .awaitingApproval(.init(summary: "Review")),
            turns: [
                inboundTurn(
                    threadID: threadID,
                    summary: "response - response received - Are you open to early-stage founders?",
                    detail: nil,
                    createdAt: Date(timeIntervalSince1970: 200)
                )
            ]
        )
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let inbound = rows.first { $0.id.hasPrefix("turn-reply-") }
        XCTAssertNotNil(inbound)
        XCTAssertTrue(inbound?.bodyPreview.contains("early-stage founders") == true)
        XCTAssertFalse(inbound?.bodyPreview.localizedCaseInsensitiveContains("response received") ?? true)
    }

    func testReplyReceivedStandaloneScaffold_usesNeutralFallback() {
        let threadID = UUID()
        let detail = providerInboundDetail(
            threadID: threadID,
            state: .awaitingApproval(.init(summary: "Review")),
            turns: [
                inboundTurn(
                    threadID: threadID,
                    summary: "Counterparty is asking for additional information.",
                    detail: nil,
                    createdAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let inbound = rows.first { $0.id.hasPrefix("turn-reply-") }
        XCTAssertEqual(inbound?.bodyPreview, "New inquiry received")
    }

    func testAwaitingResponse_sentDraftSortsAboveInboundScaffold() {
        let threadID = UUID()
        let detail = providerInboundDetail(
            threadID: threadID,
            state: .awaitingResponse(.init()),
            turns: [
                inboundTurn(
                    threadID: threadID,
                    summary: "response - response received - Counterparty is asking for additional information.",
                    detail: nil,
                    createdAt: Date(timeIntervalSince1970: 300)
                )
            ],
            drafts: [
                sentDraft(
                    threadID: threadID,
                    body: cleanOutbound,
                    updatedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )

        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertEqual(rows.first?.id.hasPrefix("draft-sent-"), true)
        XCTAssertEqual(rows.first?.bodyPreview, cleanOutbound)
    }

    func testRequesterThread_summaryUnchanged() {
        let threadID = UUID()
        var thread = ExchangeThread(
            id: threadID,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                title: "Find",
                objective: "Find"
            ),
            posture: ExchangePosture(privacy: .balanced),
            state: .searching(.init())
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [
                inboundTurn(
                    threadID: threadID,
                    summary: "response - response received - keep me",
                    detail: nil,
                    createdAt: Date(timeIntervalSince1970: 100)
                )
            ],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Search"
        )
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let inbound = rows.first { $0.id.hasPrefix("turn-reply-") }
        XCTAssertTrue(inbound?.bodyPreview.contains("response - response received") == true)
    }
}
