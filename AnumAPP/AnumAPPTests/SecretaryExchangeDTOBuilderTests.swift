import XCTest
import Foundation
import AnumCore

final class SecretaryExchangeDTOBuilderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_720_000_000)

    func test_buildDetail_outboundUsesFullDraftBody() {
        let tid = UUID()
        let longBody = String(repeating: "Z", count: 400)
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(3),
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            subject: "Subject line",
            body: longBody,
            posture: ExchangePosture()
        )
        let detail = makeDetail(thread: baseThread(id: tid), drafts: [draft])
        let dto = SecretaryExchangeDTOBuilder.buildDetail(from: detail)
        XCTAssertNotNil(dto.outboundDraft, "Expected a draft card when a non-empty draft exists")
        XCTAssertEqual(dto.outboundDraft?.body, longBody)
        XCTAssertEqual(dto.outboundDraft?.subject, "Subject line")
    }

    func test_buildDetail_latestInbound_prefersReplyReceivedDetail() {
        let tid = UUID()
        let older = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(1),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Short summary",
            detail: "Older detail body"
        )
        let newer = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(10),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Newer summary",
            detail: "Full counterparty reply text here."
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [older, newer], drafts: [])
        let dto = SecretaryExchangeDTOBuilder.buildDetail(from: detail)
        XCTAssertEqual(dto.latestInbound?.body, "Full counterparty reply text here.")
    }

    func test_buildDetail_userFacingStringsScrubInternalTokens() {
        let tid = UUID()
        let polluted = """
        secondHalf pass2 agencyPhase threadID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
        fallbackMode bodyhash runtimeMode retrievalScore ExchangeState node id: ab12
        """
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(1),
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: polluted,
            posture: ExchangePosture()
        )
        let turn = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(2),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "retrievalScore=0.9 trace",
            detail: "LLM accepted body_hash exchange_state offerID: zz99"
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [turn], drafts: [draft])
        let dto = SecretaryExchangeDTOBuilder.buildDetail(from: detail)
        let bundle = [
            dto.headlineTitle,
            dto.subtitle,
            dto.phaseLabel,
            dto.originalRequest,
            dto.matchCard?.headline,
            dto.matchCard?.summary,
            dto.matchCard?.whyItFits,
            dto.outboundDraft?.body,
            dto.latestInbound?.body,
            dto.nextAction?.primaryLine,
            dto.nextAction?.detail
        ]
            .compactMap { $0 }
            .joined(separator: " ")
        let lower = bundle.lowercased()
        XCTAssertFalse(lower.contains("secondhalf"))
        XCTAssertFalse(lower.contains("pass2"))
        XCTAssertFalse(lower.contains("agencyphase"))
        XCTAssertFalse(lower.contains("threadid"))
        XCTAssertFalse(lower.contains("fallbackmode"))
        XCTAssertFalse(lower.contains("bodyhash"))
        XCTAssertFalse(lower.contains("exchangestate"))
        XCTAssertFalse(lower.contains("llm accepted"))
    }

    func test_buildDetail_preservesBenignCounterpartyProse() {
        let tid = UUID()
        let benign = """
        Thanks for your note.
        Could you confirm your pricing?
        I am interested in lessons.
        Please let me know your availability.
        We can meet in the second half of the day.
        A thread of conversation is fine to mention.
        If we need a fallback option, say so.
        The runtime mode of the simulator varies.
        The body hash is not something we say often.
        What is your retrieval score anyway?
        """
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(1),
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: benign,
            posture: ExchangePosture()
        )
        let detail = makeDetail(thread: baseThread(id: tid), drafts: [draft])
        let dto = SecretaryExchangeDTOBuilder.buildDetail(from: detail)
        XCTAssertEqual(dto.outboundDraft?.body, benign)
    }

    // MARK: - Helpers

    private func baseThread(id: UUID) -> ExchangeThread {
        ExchangeThread(
            id: id,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(60),
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture title",
                objective: "Fixture objective",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .draftReady(.init(preparedAt: t0, summary: "Fixture")),
            selectedOfferID: "fixture-exchange-dto-anchor"
        )
    }

    private func makeDetail(
        thread: ExchangeThread,
        turns: [ExchangeTurn] = [],
        drafts: [ExchangeMessageDraft] = []
    ) -> ExchangeModels.ThreadDetail {
        ExchangeModels.ThreadDetail(
            thread: thread,
            turns: turns,
            approvals: [],
            drafts: drafts,
            matches: [],
            counterparties: [],
            artifacts: [],
            outboxItems: [],
            inboxItems: [],
            summary: "Fixture summary"
        )
    }
}
