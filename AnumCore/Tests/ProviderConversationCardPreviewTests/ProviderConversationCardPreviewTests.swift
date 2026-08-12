import XCTest
@testable import AnumCore

final class ProviderConversationCardPreviewTests: XCTestCase {

    private let cleanOutbound = "Yes — we're open to hearing from early-stage founders, especially AI and pharmaceutical startups."

    private func providerInboundThread(state: ExchangeState) -> ExchangeThread {
        var t = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                title: "response - response received - Counterparty is asking for additional information.",
                objective: "Inbound"
            ),
            posture: ExchangePosture(privacy: .balanced),
            state: state,
            visibleSummary: "Counterparty is asking for additional information."
        )
        t.metadata["inbound_thread"] = "true"
        return t
    }

    private func inboundTurn(threadID: ExchangeThread.ID) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: Date(timeIntervalSince1970: 100),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "response - response received - Counterparty is asking for additional information.",
            detail: "Are you currently open to hearing from early-stage founders?",
            visibility: .userVisible
        )
    }

    private func sentOutboundDraft(threadID: ExchangeThread.ID) -> ExchangeMessageDraft {
        ExchangeMessageDraft(
            threadID: threadID,
            updatedAt: Date(timeIntervalSince1970: 200),
            status: .sent,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: cleanOutbound,
            posture: ExchangePosture(privacy: .balanced)
        )
    }

    func testAutoReplySent_prefersCleanOutboundBody() {
        let thread = providerInboundThread(state: .awaitingResponse(.init()))
        let turns = [inboundTurn(threadID: thread.id)]
        let drafts = [sentOutboundDraft(threadID: thread.id)]

        let pick = ProviderConversationCardPreviewProjection.pick(
            ProviderConversationCardPreviewProjection.Input(
                thread: thread,
                turns: turns,
                drafts: drafts
            )
        )
        XCTAssertNotNil(pick)
        XCTAssertEqual(pick?.title, "Auto-replied")
        XCTAssertEqual(pick?.statusTitle, "Waiting for reply")
        XCTAssertEqual(pick?.previewLine, cleanOutbound)
        XCTAssertEqual(pick?.selectedSource, "latestOutboundBodyAwaitingResponse")
        XCTAssertFalse((pick?.previewLine ?? "").localizedCaseInsensitiveContains("response received"))
        XCTAssertFalse((pick?.previewLine ?? "").localizedCaseInsensitiveContains("counterparty is asking"))
    }

    func testNeedsInput_showsRequesterAskWithoutInternalLabels() {
        let thread = providerInboundThread(
            state: .awaitingApproval(.init(summary: "Review outbound draft"))
        )
        let turns = [inboundTurn(threadID: thread.id)]

        let pick = ProviderConversationCardPreviewProjection.pick(
            ProviderConversationCardPreviewProjection.Input(
                thread: thread,
                turns: turns,
                drafts: [],
                hasUserFacingRenderableOutboundDraft: false
            )
        )
        XCTAssertEqual(pick?.title, "Needs your input")
        XCTAssertTrue(pick?.previewLine?.contains("early-stage founders") == true)
        XCTAssertFalse(pick?.previewLine?.localizedCaseInsensitiveContains("response received") ?? true)
        XCTAssertFalse(pick?.previewLine?.localizedCaseInsensitiveContains("counterparty is asking") ?? true)
    }

    func testWaitingAfterOutbound_usesOutboundNotStaleInboundSummary() {
        let thread = providerInboundThread(state: .awaitingResponse(.init()))
        let turns = [inboundTurn(threadID: thread.id)]
        let drafts = [sentOutboundDraft(threadID: thread.id)]

        let pick = ProviderConversationCardPreviewProjection.pick(
            ProviderConversationCardPreviewProjection.Input(
                thread: thread,
                turns: turns,
                drafts: drafts
            )
        )
        XCTAssertEqual(pick?.previewLine, cleanOutbound)
        XCTAssertNotEqual(pick?.previewLine, thread.visibleSummary)
    }

    func testSanitizer_stripsInternalPhrases() {
        let raw = "response - response received - Counterparty is asking for additional information."
        let cleaned = ExchangeUserFacingCopySanitizer.sanitizeConversationCardPreview(raw)
        XCTAssertNil(cleaned)
        XCTAssertTrue(ExchangeUserFacingCopySanitizer.isInternalConversationCardStatusPhrase(raw))
    }

    func testQuotedNoneStyleInternalSummary_stillDrops() {
        let raw = "Counterparty is asking for additional information."
        XCTAssertTrue(ExchangeUserFacingCopySanitizer.isInternalConversationCardStatusPhrase(raw))
        XCTAssertNil(ExchangeUserFacingCopySanitizer.sanitizeConversationCardPreview(raw))
    }

    func testRequesterThread_pickIsNil() {
        var t = providerInboundThread(state: .awaitingResponse(.init()))
        t.metadata.removeValue(forKey: "inbound_thread")
        XCTAssertNil(
            ProviderConversationCardPreviewProjection.pick(
                ProviderConversationCardPreviewProjection.Input(thread: t, turns: [])
            )
        )
    }
}
