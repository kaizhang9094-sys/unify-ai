import Foundation
import XCTest
@testable import AnumCore

/// `ExchangeFacade.nextStepText` / `requiresAttentionReason` must follow user-facing
/// renderable outbound draft truth — not `latestDraft != nil`.
@MainActor
final class ExchangeFacadeInboxDraftCopyTests: XCTestCase {
    private let fixtureDate = SecretaryProjectionTestSupport.fixtureDate

    // MARK: - Harness

    private func makeFacade() throws -> ExchangeFacade {
        UserDefaults.standard.set(
            ExchangeModels.ExchangeThreadAutonomyMode.fullWithinBoundaries.rawValue,
            forKey: "secretary.threadAutonomy.mode"
        )
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exchange-inbox-draft-copy-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbURL = tmp.appendingPathComponent("db-\(UUID().uuidString).sqlite")

        let store = try ExchangeSQLiteStore(databaseURL: dbURL)
        let intelligence = ExchangeFallbackIntelligenceProvider()
        let policyEngine = ExchangePolicyEngine()

        let orchestrator = ExchangeOrchestrator(
            store: store,
            interpreter: ExchangeInterpreter(intelligenceProvider: intelligence),
            postureModeler: ExchangePostureModeler(intelligenceProvider: intelligence),
            discoveryService: ExchangeDiscoveryService(
                discoveryEngine: ExchangeDiscoveryEngine(),
                fitEngine: ExchangeFitEngine()
            ),
            messageComposer: ExchangeMessageComposer(
                draftEngine: ExchangeDraftEngine(intelligenceProvider: intelligence),
                policyEngine: policyEngine
            ),
            approvalEngine: ExchangeApprovalEngine(),
            policyEngine: policyEngine,
            threadEngine: ExchangeThreadEngine(),
            failureResolver: ExchangeFailureResolver(),
            summaryEngine: ExchangeSummaryEngine()
        )

        final class FederationNoop: ExchangeFederationService {
            func evaluateSendEligibility(
                thread _: ExchangeThread,
                counterparty _: ExchangeCounterparty,
                draft _: ExchangeMessageDraft
            ) async throws -> ExchangeFederationSendEligibility {
                ExchangeFederationSendEligibility(isEligible: false, reason: "test noop")
            }
            func queueApprovedOutbound(
                thread _: ExchangeThread,
                counterparty _: ExchangeCounterparty,
                draft _: ExchangeMessageDraft,
                approval _: ExchangeApproval,
                disclosureLevel _: ExchangeRelayEnvelope.Payload.DisclosureLevel,
                priority _: ExchangeDeliveryState.Priority,
                now _: Date
            ) async throws -> ExchangeFederationQueueResult {
                throw ExchangeFederationError.transportFailed(reason: "tests")
            }
            func cancelOutbound(outboxItemID _: ExchangeOutboxItem.ID, reason _: String?, now _: Date) async throws
                -> ExchangeFederationCancellationResult { throw ExchangeFederationError.transportFailed(reason: "tests") }
            func flushOutbox(now _: Date) async throws -> ExchangeFederationFlushResult { ExchangeFederationFlushResult() }
            func receiveEnvelope(_: ExchangeRelayEnvelope, route _: ExchangeRelayRoute?, receivedAt _: Date) async throws
                -> ExchangeFederationReceiveResult { throw ExchangeFederationError.transportFailed(reason: "tests") }
            func reconcileInbox(now _: Date) async throws -> ExchangeFederationReconcileResult {
                ExchangeFederationReconcileResult()
            }
            func recentAudit(threadID _: ExchangeThread.ID?, limit _: Int) async throws -> [ExchangeAuditRecord] { [] }
        }

        return ExchangeFacade(
            orchestrator: orchestrator,
            federationService: FederationNoop(),
            store: store,
            summaryEngine: ExchangeSummaryEngine(),
            sellerSurfaceService: ExchangeDefaultSellerSurfaceService(),
            publicationService: ExchangeDefaultPublicationService(),
            secondHalfFacade: ExchangeSecondHalfFacade(exchangeStore: store),
            intelligenceProvider: intelligence
        )
    }

    private func baseIntent() -> ExchangeIntent {
        ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture",
            objective: "",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
    }

    private func baseThread(
        id: UUID,
        state: ExchangeState,
        selectedCounterpartyID: String? = "cp-fixture",
        selectedPublicProfileID: String? = "profile-fixture"
    ) -> ExchangeThread {
        ExchangeThread(
            id: id,
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            mode: .transactional,
            intent: baseIntent(),
            posture: ExchangePosture(),
            state: state,
            selectedCounterpartyID: selectedCounterpartyID,
            selectedPublicProfileID: selectedPublicProfileID,
            visibleSummary: "Visible summary line"
        )
    }

    // MARK: - Direct copy API (boolean contract)

    func test_nextStepText_pendingApproval_winsOverRenderableFlag() async throws {
        let facade = try makeFacade()
        let tid = UUID()
        let thread = baseThread(id: tid, state: .draftReady(.init(summary: "Ready")))
        let approval = ExchangeApproval(
            threadID: tid,
            kind: .outboundSend,
            requestedAction: .sendMessage,
            summary: "Approve outbound"
        )

        XCTAssertEqual(
            facade.nextStepText(
                for: thread,
                latestApproval: approval,
                hasUserFacingRenderableOutboundDraft: false,
                clarificationQuestion: nil
            ),
            "Review the draft"
        )
        XCTAssertEqual(
            facade.requiresAttentionReason(
                for: thread,
                latestApproval: approval,
                clarificationQuestion: nil,
                hasUserFacingRenderableOutboundDraft: false
            ),
            "Approval needed before anything goes out"
        )
    }

    func test_draftReady_withoutRenderable_noReviewCopy_usesFallbacks() async throws {
        let facade = try makeFacade()
        let tid = UUID()
        let thread = baseThread(id: tid, state: .draftReady(.init(summary: "Ready")))

        XCTAssertEqual(
            facade.nextStepText(
                for: thread,
                latestApproval: nil,
                hasUserFacingRenderableOutboundDraft: false,
                clarificationQuestion: nil
            ),
            "Visible summary line"
        )
        XCTAssertNil(
            facade.requiresAttentionReason(
                for: thread,
                latestApproval: nil,
                clarificationQuestion: nil,
                hasUserFacingRenderableOutboundDraft: false
            )
        )
    }

    func test_draftReady_withRenderable_reviewCopy() async throws {
        let facade = try makeFacade()
        let tid = UUID()
        let thread = baseThread(id: tid, state: .draftReady(.init(summary: "Ready")))

        XCTAssertEqual(
            facade.nextStepText(
                for: thread,
                latestApproval: nil,
                hasUserFacingRenderableOutboundDraft: true,
                clarificationQuestion: nil
            ),
            "Review the draft"
        )
        XCTAssertEqual(
            facade.requiresAttentionReason(
                for: thread,
                latestApproval: nil,
                clarificationQuestion: nil,
                hasUserFacingRenderableOutboundDraft: true
            ),
            "Draft is ready to review."
        )
    }

    func test_matchFound_withoutRenderable_continuePath_notReview() async throws {
        let facade = try makeFacade()
        let tid = UUID()
        let mf = ExchangeState.MatchFoundStatus(
            candidateCount: 1,
            summary: "Found",
            nextStep: nil,
            selectedCounterpartyID: "cp",
            selectedPublicProfileID: nil,
            selectedOfferID: nil
        )
        let thread = baseThread(id: tid, state: .matchFound(mf), selectedCounterpartyID: "cp")

        XCTAssertEqual(
            facade.nextStepText(
                for: thread,
                latestApproval: nil,
                hasUserFacingRenderableOutboundDraft: false,
                clarificationQuestion: nil
            ),
            "Continue on this found path"
        )
    }

    // MARK: - Canonical boolean + thread state (integration-style)

    func test_integration_sentDraftLatest_row_noUserFacingDraft_noReviewCopy() async throws {
        let tid = UUID()
        let posture = ExchangePosture()
        let external = ExchangeMessageDraft(
            threadID: tid,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Hello",
            posture: posture
        )
        let sent = external.markingSent()
        let thread = baseThread(id: tid, state: .draftReady(.init(summary: "Ready")))
        XCTAssertFalse(
            ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(in: [sent], thread: thread)
        )

        let facade = try makeFacade()
        XCTAssertNotEqual(
            facade.nextStepText(
                for: thread,
                latestApproval: nil,
                hasUserFacingRenderableOutboundDraft: ExchangeMessageDraft
                    .hasUserFacingRenderableExternalOutboundDraft(in: [sent], thread: thread),
                clarificationQuestion: nil
            ),
            "Review the draft"
        )
        XCTAssertNil(
            facade.requiresAttentionReason(
                for: thread,
                latestApproval: nil,
                clarificationQuestion: nil,
                hasUserFacingRenderableOutboundDraft: ExchangeMessageDraft
                    .hasUserFacingRenderableExternalOutboundDraft(in: [sent], thread: thread)
            )
        )
    }

    func test_integration_relayOnly_noReviewCopy() async throws {
        let tid = UUID()
        let relay = ExchangeMessageDraft(
            threadID: tid,
            kind: .inquiry,
            audience: .relayNode,
            body: "Internal relay",
            posture: ExchangePosture()
        )
        let thread = baseThread(id: tid, state: .draftReady(.init(summary: "Ready")))
        XCTAssertFalse(
            ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(in: [relay], thread: thread)
        )

        let facade = try makeFacade()
        XCTAssertNil(
            facade.requiresAttentionReason(
                for: thread,
                latestApproval: nil,
                clarificationQuestion: nil,
                hasUserFacingRenderableOutboundDraft: ExchangeMessageDraft
                    .hasUserFacingRenderableExternalOutboundDraft(in: [relay], thread: thread)
            )
        )
    }

    func test_integration_externalDraft_noRecipientAnchor_noReviewCopy() async throws {
        let tid = UUID()
        let external = ExchangeMessageDraft(
            threadID: tid,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Hello world",
            posture: ExchangePosture()
        )
        let threadNoAnchor = ExchangeThread(
            id: tid,
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            mode: .transactional,
            intent: baseIntent(),
            posture: ExchangePosture(),
            state: .draftReady(.init(summary: "Ready")),
            selectedCounterpartyID: nil,
            selectedPublicProfileID: nil,
            visibleSummary: "Summary"
        )
        XCTAssertFalse(
            ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(in: [external], thread: threadNoAnchor)
        )

        let facade = try makeFacade()
        XCTAssertNotEqual(
            facade.nextStepText(
                for: threadNoAnchor,
                latestApproval: nil,
                hasUserFacingRenderableOutboundDraft: ExchangeMessageDraft
                    .hasUserFacingRenderableExternalOutboundDraft(in: [external], thread: threadNoAnchor),
                clarificationQuestion: nil
            ),
            "Review the draft"
        )
    }

    func test_integration_actionableAnchoredExternal_draftReady_reviewAllowed() async throws {
        let tid = UUID()
        let external = ExchangeMessageDraft(
            threadID: tid,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Hello world",
            posture: ExchangePosture()
        )
        let thread = baseThread(id: tid, state: .draftReady(.init(summary: "Ready")))
        XCTAssertTrue(
            ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(in: [external], thread: thread)
        )

        let facade = try makeFacade()
        XCTAssertEqual(
            facade.nextStepText(
                for: thread,
                latestApproval: nil,
                hasUserFacingRenderableOutboundDraft: ExchangeMessageDraft
                    .hasUserFacingRenderableExternalOutboundDraft(in: [external], thread: thread),
                clarificationQuestion: nil
            ),
            "Review the draft"
        )
    }
}
