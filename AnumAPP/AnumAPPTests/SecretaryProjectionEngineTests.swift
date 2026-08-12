import Foundation
import XCTest
import AnumCore
@testable import AnumAPP

/// Deterministic coverage for `SecretaryProjectionEngine` inbox/card projection.
/// No store, network, LLM, or ONNX — fixtures only.
@MainActor
final class SecretaryProjectionEngineTests: XCTestCase {
    private let d = SecretaryProjectionTestSupport.fixtureDate

    // MARK: - Pending / approval

    func test_pendingApproval_secondHalf_bucketAndAttentionSurface() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .needsApproval,
            needsHumanAttention: true,
            agencyPhase: .needsUserApproval
        )
        let item = inbox(
            threadID: tid,
            title: "Legacy inbox title",
            subtitle: "Legacy subtitle",
            state: .drafting,
            stateTitle: "Drafting",
            hasPendingApproval: false,
            secondHalfDisplay: sh
        )

        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .pending)
        XCTAssertTrue(SecretaryProjectionEngine.isPending(item))
        let vs = SecretaryProjectionEngine.visibleThreadStatus(
            for: item,
            bucket: SecretaryProjectionEngine.bucket(for: item)
        )
        XCTAssertTrue(vs.label.lowercased().contains("approval"))
        XCTAssertEqual(SecretaryProjectionEngine.pendingCTA(for: item), "Approve")
        XCTAssertEqual(SecretaryProjectionEngine.pendingIcon(for: item), "exclamationmark.circle")
    }

    func test_secondHalfPlainFields_preferredForStatusSummaryAndNextMove() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .requesterReview,
            needsHumanAttention: true,
            agencyPhase: .needsUserInput
        )
        sh.plain = ExchangeSecondHalfUIAdapter.DisplayModel.PlainLanguage(
            plainStatusLabel: "Good match, but terms are missing",
            plainOneLineSummary: "Still missing: down payment, rate, term",
            primaryCTA: "Add detail",
            followUpReason: "Ask next: confirm VTB amount, rate, and term"
        )
        let item = inbox(
            threadID: tid,
            title: "VTB thread",
            subtitle: "legacy",
            state: .drafting,
            stateTitle: "Drafting",
            secondHalfDisplay: sh
        )

        let vs = SecretaryProjectionEngine.visibleThreadStatus(
            for: item,
            bucket: SecretaryProjectionEngine.bucket(for: item)
        )
        XCTAssertFalse(vs.label.isEmpty)
        XCTAssertNotNil(SecretaryProjectionEngine.secondHalfSummaryLine(sh))
        XCTAssertNotNil(SecretaryProjectionEngine.secondHalfNextMoveLine(sh))
        XCTAssertFalse(SecretaryProjectionEngine.secondHalfPrimaryCTA(sh).isEmpty)
        XCTAssertNotEqual(SecretaryProjectionEngine.bucket(for: item), .none)
    }

    func test_secondHalfContradictionPlainStatus_doesNotFallbackToGenericProviderReplied() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .providerReception
        )
        sh.hasProviderReception = true
        sh.plain = ExchangeSecondHalfUIAdapter.DisplayModel.PlainLanguage(
            plainStatusLabel: "They said no seller financing",
            plainOneLineSummary: "This match got weaker after their reply",
            contradictionSummary: "No seller financing",
            isPoorFit: true
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "Sub",
            state: .drafting,
            stateTitle: "Drafting",
            secondHalfDisplay: sh
        )
        XCTAssertEqual(SecretaryProjectionEngine.secondHalfSummaryLine(sh), "This match got weaker after their reply")
        let vs = SecretaryProjectionEngine.visibleThreadStatus(
            for: item,
            bucket: SecretaryProjectionEngine.bucket(for: item)
        )
        XCTAssertEqual(vs.primary, .replyReceived)
    }

    func test_secondHalfCommitmentBoundary_surfacesApprovalReasonAndReviewCTA() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .needsApproval,
            needsHumanAttention: true
        )
        sh.boundary.requiresHumanApproval = true
        sh.boundary.reason = "You need to approve this because it involves a payment commitment."
        sh.plain = ExchangeSecondHalfUIAdapter.DisplayModel.PlainLanguage(
            plainStatusLabel: "Needs your approval",
            primaryCTA: "Review now",
            approvalReason: "You need to approve this because it involves a payment commitment."
        )
        XCTAssertEqual(SecretaryProjectionEngine.secondHalfPrimaryCTA(sh), "Review now")
        XCTAssertNotNil(SecretaryProjectionEngine.secondHalfBoundaryLine(sh))
    }

    func test_pendingApproval_legacyHasPendingApproval_bucketAndBoundary() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Thread",
            subtitle: "Sub",
            state: .awaitingApproval(.init(requestedAt: d, summary: "Please review")),
            stateTitle: "Awaiting Approval",
            hasPendingApproval: true,
            hasDraft: true,
            secondHalfDisplay: nil
        )

        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .pending)
        XCTAssertTrue(SecretaryProjectionEngine.isPending(item))
        XCTAssertEqual(SecretaryProjectionEngine.pendingCTA(for: item), "Review draft")
        XCTAssertEqual(SecretaryProjectionEngine.boundaryLine(for: item), "Nothing has been sent yet.")
    }

    // MARK: - Clarification

    func test_clarification_bucketPending_andIcons() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Coordination",
            subtitle: "Need detail",
            state: .needsClarification(.init(question: "What is your budget?", askedAt: d, attempts: 1)),
            stateTitle: "Needs Clarification",
            needsClarification: true,
            secondHalfDisplay: nil
        )

        XCTAssertTrue(SecretaryProjectionEngine.isClarification(item))
        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .pending)
        XCTAssertTrue(SecretaryProjectionEngine.isPending(item))
        XCTAssertEqual(SecretaryProjectionEngine.pendingIcon(for: item), "questionmark.circle")
        XCTAssertEqual(SecretaryProjectionEngine.pendingCTA(for: item), "Answer")
    }

    // MARK: - Recovery

    func test_recovery_blockedState_bucketAndIsRecovery() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Thread",
            subtitle: "Delivery issue",
            state: .blockedByDeliveryFailure(.init(failedAt: d, failureID: UUID(), deliveryWasAttempted: true)),
            stateTitle: "Delivery Failed",
            hasFailure: true,
            secondHalfDisplay: nil
        )

        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .recovery)
        XCTAssertTrue(SecretaryProjectionEngine.isRecovery(item))
    }

    func test_recovery_secondHalfPlacementRecovery() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .recovery,
            summary: "Fixture blocked summary.",
            statusBlocking: true
        )
        let item = inbox(
            threadID: tid,
            title: "Looks active in legacy title",
            subtitle: "Legacy",
            state: .drafting,
            stateTitle: "Drafting",
            hasFailure: false,
            secondHalfDisplay: sh
        )

        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .recovery)
        XCTAssertTrue(SecretaryProjectionEngine.isRecovery(item))
    }

    // MARK: - Search result

    func test_searchResult_matchFound_bucket() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Search",
            subtitle: "Found",
            state: .matchFound(.init(foundAt: d, candidateCount: 1, summary: "A candidate path exists.")),
            stateTitle: "Match Found",
            secondHalfDisplay: nil
        )

        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .searchResult)
        XCTAssertTrue(SecretaryProjectionEngine.isSearchResult(item))
    }

    func test_searchResult_secondHalfDecisionReady_bucket() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady,
            hasDecisionPacket: true
        )
        let item = inbox(
            threadID: tid,
            title: "Legacy",
            subtitle: "Legacy",
            state: .drafting,
            stateTitle: "Drafting",
            secondHalfDisplay: sh
        )

        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .searchResult)
        XCTAssertTrue(SecretaryProjectionEngine.isSearchResult(item))
    }

    // MARK: - Active

    func test_active_drafting_noFailure_bucket() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Active thread",
            subtitle: "Drafting locally",
            state: .drafting,
            stateTitle: "Drafting",
            hasFailure: false,
            secondHalfDisplay: nil
        )

        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .active)
        XCTAssertTrue(SecretaryProjectionEngine.isActive(item))
    }

    func test_active_secondHalfCoordination_bucket() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .activeCoordination,
            canRunAutonomously: true
        )
        let item = inbox(
            threadID: tid,
            title: "Legacy",
            subtitle: "Legacy",
            state: .drafting,
            stateTitle: "Drafting",
            secondHalfDisplay: sh
        )

        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .active)
        XCTAssertTrue(SecretaryProjectionEngine.isActive(item))
    }

    // MARK: - Waiting

    func test_waiting_awaitingResponse_state() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Waiting",
            subtitle: "Reply",
            state: .awaitingResponse(.init(since: d)),
            stateTitle: "Awaiting Response",
            secondHalfDisplay: nil
        )

        XCTAssertTrue(SecretaryProjectionEngine.isWaiting(item))
    }

    func test_waiting_awaitingReplyFlag() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Thread",
            subtitle: "Sub",
            state: .drafting,
            stateTitle: "Drafting",
            awaitingReply: true,
            secondHalfDisplay: nil
        )

        XCTAssertTrue(SecretaryProjectionEngine.isWaiting(item))
    }

    // MARK: - Preferred thread

    func test_preferredThreadID_elevatesDraftingWithFailureToActive() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Thread",
            subtitle: "Sub",
            state: .drafting,
            stateTitle: "Drafting",
            hasFailure: true,
            secondHalfDisplay: nil
        )

        XCTAssertEqual(
            SecretaryProjectionEngine.bucket(for: item, preferredThreadID: nil),
            .recovery,
            "Non-preferred drafting + failure should surface as recovery."
        )
        XCTAssertEqual(
            SecretaryProjectionEngine.bucket(for: item, preferredThreadID: tid),
            .active,
            "Preferred thread uses the preferred-thread branch and stays active despite hasFailure."
        )
    }

    // MARK: - User-facing title (second-half machine titles must not replace the request)

    func test_displayTitle_prefersThreadTitleOverSecondHalfTitle() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .requesterReview,
            title: "Rich second-half title",
            summary: "SH summary beats legacy visible summary."
        )
        let item = inbox(
            threadID: tid,
            title: "Find a match",
            subtitle: "Generic subtitle",
            state: .drafting,
            stateTitle: "Drafting",
            visibleSummary: "Visible summary from facade",
            secondHalfDisplay: sh
        )

        XCTAssertEqual(SecretaryProjectionEngine.displayTitle(for: item), "Find a match")
    }

    func test_secondHalfDisplay_precedence_searchResultPrimaryLine_overVisibleSummary() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .requesterReview,
            summary: "Inspect the surfaced review details before you decide."
        )
        let item = inbox(
            threadID: tid,
            title: "Title",
            subtitle: "Sub",
            state: .matchFound(.init(foundAt: d, candidateCount: 1, summary: "Match found summary.")),
            stateTitle: "Match Found",
            visibleSummary: "Legacy visible summary",
            secondHalfDisplay: sh
        )

        XCTAssertEqual(
            SecretaryProjectionEngine.searchResultPrimaryLine(for: item),
            "Inspect the surfaced review details before you decide."
        )
    }

    // MARK: - Boundary line

    func test_boundaryLine_secondHalfExternalEffect_preferred() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .needsApproval,
            externalEffectLine: "No federation send; approval gate closed."
        )
        let item = inbox(
            threadID: tid,
            title: "T",
            subtitle: "S",
            state: .drafting,
            stateTitle: "Drafting",
            hasDraft: true,
            secondHalfDisplay: sh
        )

        let line = SecretaryProjectionEngine.boundaryLine(for: item)
        XCTAssertEqual(line, "No network send; approval gate closed.")
    }

    func test_boundaryLine_pendingApprovalLegacy_safeCopy() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "T",
            subtitle: "S",
            state: .awaitingApproval(.init(requestedAt: d, summary: "Review")),
            stateTitle: "Awaiting Approval",
            hasPendingApproval: true,
            secondHalfDisplay: nil
        )

        XCTAssertEqual(SecretaryProjectionEngine.boundaryLine(for: item), "Nothing has been sent yet.")
    }

    func test_blockedSystemArtifactText_filtersRequestedGarbagePhrases() {
        let blocked = [
            "coordination path",
            "system messages",
            "fit movement",
            "published seller surfaces not anchored",
            "snapshot",
            "capacity and throughput",
            "The exchange is strong enough to frame a decision",
            "New activity in this thread",
            "boundary",
            "schema",
            "deterministic",
            "outbound probe"
        ]
        for phrase in blocked {
            XCTAssertTrue(
                SecretaryProjectionEngine.isBlockedSystemArtifactText(phrase),
                "Expected phrase to be blocked: \(phrase)"
            )
        }
    }

    func test_blockedSystemArtifactText_allowsUserFacingAssessmentText() {
        XCTAssertFalse(
            SecretaryProjectionEngine.isBlockedSystemArtifactText(
                "Still missing: down payment, rate, and term."
            )
        )
        XCTAssertFalse(
            SecretaryProjectionEngine.isBlockedSystemArtifactText(
                "Suggested follow-up: ask them to confirm VTB terms."
            )
        )
    }

    // MARK: - Display title / visibleSummary

    func test_displayTitle_fallsBackToCapturedRequestWhenStoredTitleBlank() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "   ",
            subtitle: "Ignored for primary title",
            state: .drafting,
            stateTitle: "Drafting",
            capturedRequestText: "Subtitle-only title path",
            secondHalfDisplay: nil
        )

        XCTAssertEqual(SecretaryProjectionEngine.displayTitle(for: item), "Subtitle-only title path")
    }

    func test_displayTitle_visibleSummaryNotUsedByDisplayTitle() {
        // `displayTitle(for:)` prefers captured / interpretation / draft / stored title — not `visibleSummary`.
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Find a match",
            subtitle: "",
            state: .matchFound(.init(foundAt: d, candidateCount: 1, summary: "Found")),
            stateTitle: "Match Found",
            visibleSummary: "Richer visible summary from projection",
            secondHalfDisplay: nil
        )

        XCTAssertEqual(
            SecretaryProjectionEngine.displayTitle(for: item),
            "Find a match",
            "Legacy path still prefers `title` over `visibleSummary`; richer list copy is out of scope for `displayTitle`."
        )
    }

    // MARK: - Thread timeline presentation (Activity / UI-only)

    func test_timelinePresentedRow_deliveryStateSent_mapsToSent() {
        let item = ExchangeModels.ThreadTimelineItem(
            date: d,
            title: "Delivery state: Sent",
            summary: "The move went out successfully.",
            tone: .success
        )

        XCTAssertEqual(SecretaryProjectionEngine.presentedThreadTimelineRow(item: item).title, "Sent")
    }

    func test_timelinePresentedRow_deliveryStateFailed_mapsToCouldntSend() {
        let item = ExchangeModels.ThreadTimelineItem(
            date: d,
            title: "Delivery state: Failed",
            summary: "The move was attempted but failed.",
            tone: .blocked
        )

        XCTAssertEqual(
            SecretaryProjectionEngine.presentedThreadTimelineRow(item: item).title,
            "Couldn't send"
        )
    }

    func test_timelinePresentedRow_requestCaptured_mapsToYouAsked() {
        let item = ExchangeModels.ThreadTimelineItem(
            date: d,
            title: "Request captured",
            summary: "Find someone for this weekend.",
            tone: .active
        )

        XCTAssertEqual(SecretaryProjectionEngine.presentedThreadTimelineRow(item: item).title, "You asked")
    }

    func test_timelinePresentedRow_inboundMessage_mapsToTheyReplied() {
        let item = ExchangeModels.ThreadTimelineItem(
            date: d,
            title: "Inbound message",
            summary: "Sounds good.",
            tone: .success
        )

        XCTAssertEqual(SecretaryProjectionEngine.presentedThreadTimelineRow(item: item).title, "They replied")
    }

    func test_timelinePresentedRow_messageDrafted_mapsToNeutralDraftUpdate() {
        let item = ExchangeModels.ThreadTimelineItem(
            date: d,
            title: "Draft prepared",
            summary: "System recorded draft activity.",
            tone: .active
        )
        XCTAssertEqual(SecretaryProjectionEngine.presentedThreadTimelineRow(item: item).title, "Draft update")
    }

    func test_dashboardPendingReason_pendingApprovalWithoutPersistedOutbound_avoidsDraftReadyClaims() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .awaitingApproval(.init(requestedAt: d, summary: "Pending fixture")),
            stateTitle: "Awaiting approval",
            hasPendingApproval: true,
            hasDraft: true,
            hasActionableExternalOutboundDraft: false,
            draftedBodyPreview: "Phantom preview body"
        )
        let reason = SecretaryProjectionEngine.pendingReason(for: item).lowercased()
        XCTAssertTrue(reason.contains("approval"))
        XCTAssertFalse(reason.contains("draft"))
    }

    func test_activityBadge_secondHalfStaleDisplayDraftFlag_doesNotMapToReplyPrepared() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .activeCoordination,
            agencyPhase: .unknown,
            hasDraft: true
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .drafting,
            stateTitle: "Drafting",
            hasDraft: true,
            hasActionableExternalOutboundDraft: false,
            secondHalfDisplay: sh
        )
        XCTAssertNotEqual(
            SecretaryProjectionEngine.activityBadge(for: item),
            "Reply prepared",
            "Display-only draft placeholders must not surface Reply prepared."
        )
    }

    func test_exchangeThreadSubtitle_draftReady_withoutPersistedActionable_skipsDraftReadyPhrase() {
        let subtitle = ExchangeThreadCardTitleProjection.inboxCardSubtitle(
            primaryTitle: "Fixture",
            primaryStatusLine: "Needs review",
            deliveryStatusText: nil,
            outcomeStatusText: nil,
            opportunityShortLine: nil,
            threadID: nil,
            surface: "threads"
        )
        XCTAssertTrue(subtitle.localizedStandardContains("Needs review"))
        XCTAssertFalse(subtitle.localizedStandardContains("Draft ready"))
    }

    func test_visibleThreadStatus_selectedCounterparty_profileAnchor_withoutActionableDraft() {
        let tid = UUID()
        let cpID = "fixture-cp-aria"
        let counterparties = [
            ExchangeCounterparty(
                id: cpID,
                kind: .person,
                displayName: "Aria Kim",
                source: .manualEntry
            )
        ]
        let relayScratch = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .draft,
            kind: .inquiry,
            audience: .relayNode,
            body: "Internal coordination scratch — not outbound.",
            posture: ExchangePosture()
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .matchFound(.init(foundAt: d, candidateCount: 1, summary: "Fixture")),
            selectedCounterpartyID: cpID
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [relayScratch],
            matches: [],
            counterparties: counterparties,
            artifacts: [],
            summary: "Fixture summary"
        )
        XCTAssertFalse(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Pulled profile")
    }

    func test_visibleThreadStatus_detail_draftReadyWithoutPersistedOutbound_skipsDraftReadyLane() {
        let tid = UUID()
        let relayScratch = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .draft,
            kind: .followUp,
            audience: .relayNode,
            body: "Relay-only body",
            posture: ExchangePosture()
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .draftReady(.init(preparedAt: d, summary: "fixture"))
            ),
            turns: [],
            approvals: [],
            drafts: [relayScratch],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        XCTAssertFalse(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
        let vs = SecretaryProjectionEngine.visibleThreadStatus(for: detail)
        XCTAssertNotEqual(vs.label, "Draft ready")
        XCTAssertEqual(vs.label, "Needs review")
    }

    func test_visibleThreadStatus_providerNeedsInput_suppressesGhostSending_withoutOutbox() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .needsInput,
            needsHumanAttention: true
        )
        sh.status = ExchangeSecondHalfUIAdapter.Status(
            state: "Coordination",
            role: ExchangeSecondHalfRole.provider.displayTitle,
            quality: "Fixture quality",
            readiness: "Fixture readiness",
            isBlocking: false,
            isAutonomous: false,
            isDecisionReady: false,
            isTerminal: false
        )
        sh.operatingContext = ExchangeSecondHalfUIAdapter.OperatingContextSection(
            role: ExchangeSecondHalfRole.provider.displayTitle,
            postureSummary: "Fixture operating posture",
            readiness: "Ready enough",
            urgency: "Normal",
            trust: "Fixture trust",
            priceSensitivity: "Unknown",
            flexibility: "Moderate",
            missingFacts: ["Confirm your refund policy window."],
            userFacingMissingFacts: ["Confirm your refund policy window."]
        )

        var thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .sending(.init(startedAt: d, attemptNumber: 1, channelSummary: "Fixture send"))
        )
        thread = thread.settingDelivery(
            ExchangeThread.DeliverySnapshot(status: .readyToSend, note: "Fixture"),
            at: d
        )

        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            outboxItems: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        let vs = SecretaryProjectionEngine.visibleThreadStatus(for: detail)
        XCTAssertEqual(vs.primary, .needsYourInput)
        XCTAssertFalse(vs.label.localizedStandardContains("sending"))
    }

    func test_timelinePresentedRow_summary_UUIDRemoved() {
        let uuidChunk = "AABBCCDD-1122-3344-5566-778899001122"
        let item = ExchangeModels.ThreadTimelineItem(
            date: d,
            title: "Note",
            summary: "Related to \(uuidChunk) and wrapping up.",
            tone: .neutral
        )

        let presented = SecretaryProjectionEngine.presentedThreadTimelineRow(item: item)
        XCTAssertFalse(presented.summary?.contains(uuidChunk) ?? false)
        XCTAssertEqual(presented.summary, "Related to and wrapping up.")
    }

    func test_timelineSanitizedPresentationParagraph_parkingPassPreserved() {
        let cleaned = SecretaryProjectionEngine.sanitizedTimelinePresentationParagraph(
            "Show your parking pass at the gate."
        )
        XCTAssertEqual(cleaned, "Show your parking pass at the gate.")
    }

    func test_timelineSanitizedPresentationParagraph_pass2LayerStripped() {
        let cleaned = SecretaryProjectionEngine.sanitizedTimelinePresentationParagraph(
            "Used pass 2 results only."
        )
        XCTAssertFalse(cleaned.localizedStandardContains("pass 2"))
        XCTAssertFalse(cleaned.localizedStandardContains("pass2"))
    }

    func test_presentedThreadTimelineRow_userFacingStringsContainNoneOfBannedVocabulary() {
        let pollution = """
        relay envelope outbox metadata execution trace agency mutation pipeline second half autonomous second_half
        """
        let item = ExchangeModels.ThreadTimelineItem(
            date: d,
            title: "Update: \(pollution)",
            summary: "Detail repeats \(pollution)",
            secondary: "Footnote covers \(pollution)",
            tone: .neutral
        )
        let presented = SecretaryProjectionEngine.presentedThreadTimelineRow(item: item)
        let bundle = [presented.title, presented.summary ?? "", presented.secondary ?? ""].joined(separator: "\n")
        assertTimelineUserFacingBannedFree(bundle)
    }

    func test_secondHalfDisplay_decisionPacketProjectionAligned() {
        let sh = SecretaryProjectionTestSupport.secondHalfDisplayWithAlignedDecisionPacket()
        XCTAssertTrue(sh.hasDecisionPacket)
        XCTAssertNotNil(sh.decision)
        XCTAssertTrue(sh.decisionPacketProjectionAligned)
    }

    // MARK: - Exchange list / draft guards

    func test_exchangeListStatusLabel_searchResult_waitingPreferredOverDecisionWording() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .activeCoordination,
            hasDecisionPacket: false
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .awaitingResponse(.init(since: d)),
            stateTitle: "Awaiting reply",
            secondHalfDisplay: sh
        )

        XCTAssertEqual(
            SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .searchResult),
            "Waiting for reply"
        )
    }

    func test_exchangeListStatusLabel_searchResult_providerReception_mapsReplyReceived() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .providerReception
        )
        sh.hasProviderReception = true
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .matchFound(.init(foundAt: d, candidateCount: 1, summary: "Fixture match")),
            stateTitle: "Match",
            secondHalfDisplay: sh
        )

        XCTAssertEqual(
            SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .searchResult),
            "Reply received"
        )
    }

    func test_exchangeListStatusLabel_noneResolved_mapsCompleted() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .resolved(.init(resolvedAt: d, summary: "Done")),
            stateTitle: "Resolved",
            secondHalfDisplay: nil
        )
        XCTAssertEqual(
            SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .none),
            "Completed"
        )
    }

    func test_exchangeListStatusLabel_trusted_waitingUsesReplyWaitCopy() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .awaitingResponse(.init(since: d)),
            stateTitle: "Waiting",
            selectedCounterpartyName: "Ada",
            awaitingReply: true
        )
        XCTAssertEqual(
            SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .trusted),
            "Waiting for reply"
        )
    }

    func test_hasActionableExternalOutboundDraft_trueWhenDraftOpen() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Hello",
            posture: ExchangePosture()
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .draftReady(.init(preparedAt: d, summary: "ok")),
                selectedOfferID: "fixture-offer-anchor"
            ),
            turns: [],
            approvals: [],
            drafts: [draft],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        XCTAssertTrue(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
    }

    func test_hasActionableExternalOutboundDraft_falseWhenOpenButNoRecipientAnchor() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Orphan external body",
            posture: ExchangePosture()
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .drafting
            ),
            turns: [],
            approvals: [],
            drafts: [draft],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        XCTAssertTrue(ExchangeMessageDraft.hasActionableExternalOutboundDraft(in: detail.drafts))
        XCTAssertFalse(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
    }

    func test_hasActionableExternalOutboundDraft_falseWhenOnlySentDraft() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .sent,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Sent body",
            posture: ExchangePosture()
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .awaitingResponse(.init(since: d))
            ),
            turns: [],
            approvals: [],
            drafts: [draft],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        XCTAssertFalse(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
    }

    func test_visibleThreadStatus_listAndDetail_alignWaitingForReply() {
        let tid = UUID()
        let sentDraft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .sent,
            kind: .followUp,
            audience: .externalCounterparty,
            body: "Outbound",
            posture: ExchangePosture()
        )

        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .awaitingResponse(.init(since: d))
            ),
            turns: [],
            approvals: [],
            drafts: [sentDraft],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )

        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .awaitingResponse(.init(since: d)),
            stateTitle: "Waiting",
            awaitingReply: true,
            secondHalfDisplay: nil
        )

        let detailLabel = SecretaryProjectionEngine.visibleThreadStatus(for: detail).label
        let listLabel = SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .active).label
        XCTAssertEqual(detailLabel, "Waiting for reply")
        XCTAssertEqual(listLabel, "Waiting for reply")
    }

    func test_visibleThreadStatus_listAndDetail_alignPulledOffer() {
        let tid = UUID()
        let offerID: ExchangeOffer.ID = "fixture-offer-1"

        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .matchFound(.init(foundAt: d, candidateCount: 1, summary: "Fixture"))
            ),
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary",
            selectedOfferID: offerID
        )

        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .matchFound(.init(foundAt: d, candidateCount: 1, summary: "Fixture")),
            stateTitle: "Match",
            selectedOfferID: offerID,
            secondHalfDisplay: nil
        )

        XCTAssertEqual(
            SecretaryProjectionEngine.visibleThreadStatus(for: detail).label,
            SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .searchResult).label
        )
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Pulled offer")
    }

    func test_visibleThreadStatus_labelsExcludeBannedSystemPhrases() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .drafting,
            stateTitle: "Drafting",
            hasDraft: true,
            draftedBodyPreview: "Hello",
            secondHalfDisplay: nil
        )
        let label = SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .active).label
        let lower = label.lowercased()
        for phrase in ["coordination path", "system messages", "fit movement", "snapshot", "not anchored", "new activity"] {
            XCTAssertFalse(lower.contains(phrase), "Unexpected phrase in status: \(phrase)")
        }
    }

    func test_visibleThreadStatus_listAndDetail_alignDraftReady() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Hello there",
            posture: ExchangePosture()
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .drafting,
                selectedPublicProfileID: "fixture-profile-anchor"
            ),
            turns: [],
            approvals: [],
            drafts: [draft],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .drafting,
            stateTitle: "Drafting",
            selectedPublicProfileID: "fixture-profile-anchor",
            hasDraft: true,
            hasActionableExternalOutboundDraft: true,
            draftedBodyPreview: "Hello there",
            secondHalfDisplay: nil
        )
        XCTAssertTrue(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Draft ready")
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .active).label, "Draft ready")
    }

    func test_visibleThreadStatus_listAndDetail_sentOnlyNoDraftReadyLabel() {
        let tid = UUID()
        let sentDraft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .sent,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Already sent",
            posture: ExchangePosture()
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .awaitingResponse(.init(since: d))
            ),
            turns: [],
            approvals: [],
            drafts: [sentDraft],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .awaitingResponse(.init(since: d)),
            stateTitle: "Waiting",
            hasDraft: false,
            awaitingReply: true,
            deliveryStatusText: "Sent",
            secondHalfDisplay: nil
        )
        XCTAssertFalse(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
        XCTAssertNotEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Draft ready")
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Waiting for reply")
        XCTAssertNotEqual(SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .active).label, "Draft ready")
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .active).label, "Waiting for reply")
    }

    func test_visibleThreadStatus_listAndDetail_alignNeedsYourApproval() {
        let tid = UUID()
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .awaitingApproval(.init(requestedAt: d, summary: "Please review"))
            ),
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .awaitingApproval(.init(requestedAt: d, summary: "Please review")),
            stateTitle: "Approval",
            hasPendingApproval: true,
            secondHalfDisplay: nil
        )
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Needs your approval")
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .active).label, "Needs your approval")
    }

    func test_visibleThreadStatus_listAndDetail_alignNeedsAFix() {
        let tid = UUID()
        let failure = ExchangeFailure(
            kind: .deliveryFailure,
            summary: "Could not send",
            whatHappened: "Delivery failed.",
            whatDidNotHappen: "No message was sent.",
            recommendedNextStep: .retryDelivery,
            createdAt: d
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .drafting,
                latestFailure: failure
            ),
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .drafting,
            stateTitle: "Drafting",
            hasFailure: true,
            latestFailureSummary: "Could not send",
            secondHalfDisplay: nil
        )
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Needs a fix")
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .recovery).label, "Needs a fix")
    }

    func test_visibleThreadStatus_listAndDetail_alignNoConfirmedMatch() {
        let tid = UUID()
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .noViableMatch(.init(searchedAt: d, explanation: "None found"))
            ),
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .noViableMatch(.init(searchedAt: d, explanation: "None found")),
            stateTitle: "No match",
            hasFailure: true,
            secondHalfDisplay: nil
        )
        let detailLabel = SecretaryProjectionEngine.visibleThreadStatus(for: detail).label
        let listLabel = SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .active).label
        XCTAssertEqual(detailLabel, listLabel)
        XCTAssertEqual(detailLabel, "No confirmed match yet")
        let combined = detailLabel + listLabel
        XCTAssertFalse(combined.lowercased().contains("promising"))
        XCTAssertFalse(combined.lowercased().contains("strong"))
    }

    func test_visibleThreadStatus_noViableMatch_orphanExternalDraft_staysNoConfirmed_notNeedsFix() {
        let tid = UUID()
        let orphan = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Stale outbound text without anchor.",
            posture: ExchangePosture()
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .noViableMatch(.init(searchedAt: d, explanation: "None"))
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [orphan],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture"
        )
        XCTAssertTrue(ExchangeMessageDraft.hasActionableExternalOutboundDraft(in: detail.drafts))
        XCTAssertFalse(ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread))
        XCTAssertFalse(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
        let vs = SecretaryProjectionEngine.visibleThreadStatus(for: detail)
        XCTAssertEqual(vs.primary, .noConfirmedMatch)
        XCTAssertEqual(vs.label, "No confirmed match yet")
        XCTAssertNotEqual(vs.label, "Needs a fix")
        XCTAssertNotEqual(vs.label, "Needs your review")
        XCTAssertNotEqual(vs.label, "Draft ready")
        let transcriptRows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertFalse(transcriptRows.contains { $0.title == "Draft ready" })
    }

    func test_visibleThreadStatus_noViableMatch_secondHalfHasDraftPreview_notDraftReady() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .activeCoordination,
            hasDraft: true
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .noViableMatch(.init(searchedAt: d, explanation: "None"))
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        XCTAssertTrue(sh.hasDraft)
        XCTAssertFalse(ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread))
        let vs = SecretaryProjectionEngine.visibleThreadStatus(for: detail)
        XCTAssertEqual(vs.label, "No confirmed match yet")
        XCTAssertNotEqual(vs.label, "Draft ready")
    }

    func test_visibleThreadStatus_noViableMatch_secondHalfDecisionReady_withoutAnchor_notNeedsReview() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady,
            hasDecisionPacket: true
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .noViableMatch(.init(searchedAt: d, explanation: "None"))
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .noViableMatch(.init(searchedAt: d, explanation: "None")),
            stateTitle: "No match",
            secondHalfDisplay: sh
        )
        XCTAssertFalse(ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread))
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "No confirmed match yet")
        XCTAssertEqual(
            SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .searchResult).label,
            "No confirmed match yet"
        )
    }

    func test_visibleThreadStatus_noViableMatch_secondHalfRequesterReview_withoutAnchor_notNeedsReview() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .requesterReview
        )
        sh.hasRequesterReview = true
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .noViableMatch(.init(searchedAt: d, explanation: "None"))
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .noViableMatch(.init(searchedAt: d, explanation: "None")),
            stateTitle: "No match",
            secondHalfDisplay: sh
        )
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "No confirmed match yet")
        XCTAssertEqual(
            SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .searchResult).label,
            "No confirmed match yet"
        )
    }

    func test_visibleThreadStatus_matchCandidatesWeak_noAnchor_notNeedsReview_showsPotentialMatch() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .requesterReview
        )
        sh.hasRequesterReview = true
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak"))
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak")),
            stateTitle: "Weak",
            secondHalfDisplay: sh
        )
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Potential match")
        XCTAssertEqual(
            SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .searchResult).label,
            "Potential match"
        )
        XCTAssertNotEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Needs your review")
    }

    func test_visibleThreadStatus_noViableMatch_decisionReady_withAnchoredOffer_showsNeedsReview() {
        let tid = UUID()
        let offerID = "fixture-offer-anchor"
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady,
            hasDecisionPacket: true
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .noViableMatch(.init(searchedAt: d, explanation: "None")),
            selectedOfferID: offerID
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        XCTAssertTrue(ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread))
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Needs your review")
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .noViableMatch(.init(searchedAt: d, explanation: "None")),
            stateTitle: "No match",
            selectedOfferID: offerID,
            secondHalfDisplay: sh
        )
        XCTAssertEqual(
            SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .searchResult).label,
            "Needs your review"
        )
    }

    func test_visibleThreadStatus_staleHasDraftFlag_withoutActionable_doesNotShowDraftReady() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .drafting,
            stateTitle: "Drafting",
            hasDraft: true,
            hasActionableExternalOutboundDraft: false,
            draftedBodyPreview: "Stale preview only",
            secondHalfDisplay: nil
        )
        XCTAssertNotEqual(
            SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .active).label,
            "Draft ready"
        )
    }

    func test_exchangeMessageDraft_hasActionableExternalOutboundDraft_semantics() {
        let tid = UUID()
        let posture = ExchangePosture()
        let external = ExchangeMessageDraft(
            threadID: tid,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Hello",
            posture: posture
        )
        XCTAssertTrue(ExchangeMessageDraft.hasActionableExternalOutboundDraft(in: [external]))

        let sent = external.markingSent()
        XCTAssertFalse(ExchangeMessageDraft.hasActionableExternalOutboundDraft(in: [sent]))

        let relay = ExchangeMessageDraft(
            threadID: tid,
            kind: .inquiry,
            audience: .relayNode,
            body: "Internal",
            posture: posture
        )
        XCTAssertFalse(ExchangeMessageDraft.hasActionableExternalOutboundDraft(in: [relay]))

        let emptyExternal = ExchangeMessageDraft(
            threadID: tid,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "   ",
            posture: posture
        )
        XCTAssertFalse(ExchangeMessageDraft.hasActionableExternalOutboundDraft(in: [emptyExternal]))
    }

    func test_visibleThreadStatus_detail_emptyBodyExternal_notDraftReady() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            threadID: tid,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: " ",
            posture: ExchangePosture()
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .drafting
            ),
            turns: [],
            approvals: [],
            drafts: [draft],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        XCTAssertFalse(ExchangeMessageDraft.hasActionableExternalOutboundDraft(in: detail.drafts))
        XCTAssertNotEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Draft ready")
    }

    func test_visibleThreadStatus_approvalWins_whenActionableDraftAlsoPresent() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            threadID: tid,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Needs approval",
            posture: ExchangePosture()
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .directOutreach,
                    title: "Fixture",
                    objective: "",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .awaitingApproval(.init(requestedAt: d, summary: "Please review")),
                selectedCounterpartyID: "fixture-cp-anchor"
            ),
            turns: [],
            approvals: [],
            drafts: [draft],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture summary"
        )
        XCTAssertTrue(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).label, "Needs your approval")

        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .awaitingApproval(.init(requestedAt: d, summary: "Please review")),
            stateTitle: "Approval",
            selectedCounterpartyID: "fixture-cp-anchor",
            hasPendingApproval: true,
            hasDraft: true,
            hasActionableExternalOutboundDraft: true,
            draftedBodyPreview: "Needs approval",
            secondHalfDisplay: nil
        )
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: item, bucket: .active).label, "Needs your approval")
    }

    // MARK: - ThreadView requester assessment

    func test_threadViewRequesterAssessmentMode_noViableMatch_isCleanNoMatch() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady,
            hasDecisionPacket: true
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .noViableMatch(.init(searchedAt: d, explanation: "None"))
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).primary, .noConfirmedMatch)
        XCTAssertEqual(
            SecretaryProjectionEngine.threadViewRequesterAssessmentMode(for: detail),
            .cleanNoMatch
        )
    }

    func test_threadViewRequesterAssessmentMode_potentialMatch_unanchored_isHidden() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .requesterReview
        )
        sh.hasRequesterReview = true
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak"))
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).primary, .potentialMatch)
        XCTAssertFalse(ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread))
        XCTAssertEqual(
            SecretaryProjectionEngine.threadViewRequesterAssessmentMode(for: detail),
            .hidden
        )
    }

    func test_threadViewRequesterAssessmentMode_potentialMatch_anchored_isRich() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .activeCoordination
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak")),
            selectedCounterpartyID: "cp-weak-anchor"
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        XCTAssertEqual(SecretaryProjectionEngine.visibleThreadStatus(for: detail).primary, .potentialMatch)
        XCTAssertTrue(ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread))
        XCTAssertEqual(
            SecretaryProjectionEngine.threadViewRequesterAssessmentMode(for: detail),
            .rich
        )
    }

    func test_passesThreadViewAssessmentUXLinePolicy_blocksNoMatchLeaks() {
        XCTAssertFalse(
            SecretaryProjectionEngine.passesThreadViewAssessmentUXLinePolicy("Weak match so far · Ready for your review")
        )
        XCTAssertFalse(
            SecretaryProjectionEngine.passesThreadViewAssessmentUXLinePolicy("Has enough thread detail to work with.")
        )
        XCTAssertFalse(
            SecretaryProjectionEngine.passesThreadViewAssessmentUXLinePolicy("Missing: no viable match is anchored yet.")
        )
        XCTAssertTrue(
            SecretaryProjectionEngine.passesThreadViewAssessmentUXLinePolicy("Compare availability before you commit.")
        )
    }

    func test_threadViewRequesterAssessmentMode_actionableDraft_isRich() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            threadID: tid,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Real body content for fixture.",
            posture: ExchangePosture()
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .noViableMatch(.init(searchedAt: d, explanation: "None")),
            selectedCounterpartyID: "cp-fixture"
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [draft],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
                threadID: tid,
                placement: .decisionReady,
                hasDecisionPacket: true
            )
        )
        XCTAssertTrue(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
        XCTAssertEqual(
            SecretaryProjectionEngine.threadViewRequesterAssessmentMode(for: detail),
            .rich
        )
    }

    // MARK: - Safe auto-follow-ups nudge (projection-only)

    private func nudgeIsolatedDefaults() -> UserDefaults {
        let suite = "SecretaryProjectionEngineTests.Nudge.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private var specificSafeAutoFollowUpsNudgeCopy: String {
        "Auto-send is off. Turn on Safe auto-follow-ups to let Unify send low-risk clarification messages for you."
    }

    private var fallbackSafeAutoFollowUpsNudgeCopy: String {
        "Auto-send is off. You can enable Safe auto-follow-ups in Discovery settings."
    }

    private func nudgeBaselineExternalDraft(
        threadID: UUID,
        counterpartyID: String
    ) -> (thread: ExchangeThread, draft: ExchangeMessageDraft) {
        let outbound = ExchangeMessageDraft(
            id: UUID(),
            threadID: threadID,
            createdAt: d,
            updatedAt: d,
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Hello, quick question about availability.",
            posture: ExchangePosture()
        )
        let thread = ExchangeThread(
            id: threadID,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .matchFound(.init(foundAt: d, candidateCount: 1, summary: "Fixture")),
            selectedCounterpartyID: counterpartyID
        )
        return (thread, outbound)
    }

    func test_safeAutoFollowUpsNudge_showsWhenPotentialMatchDraftSafeAndAutonomyOff() {
        let defaults = nudgeIsolatedDefaults()
        defaults.set(
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue,
            forKey: AppServices.safeAutoFollowUpsUserDefaultsKey
        )

        let tid = UUID()
        let cpID = "fixture-cp-nudge"
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady
        )
        sh.boundary.requiresHumanApproval = false
        sh.boundary.allowsAutonomousSending = true

        let baseline = nudgeBaselineExternalDraft(threadID: tid, counterpartyID: cpID)
        let detail = ExchangeModels.ThreadDetail(
            thread: baseline.thread,
            turns: [],
            approvals: [],
            drafts: [baseline.draft],
            matches: [],
            counterparties: [
                ExchangeCounterparty(
                    id: cpID,
                    kind: .person,
                    displayName: "Alex Kim",
                    source: .manualEntry
                )
            ],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        let line = SecretaryProjectionEngine.safeAutoFollowUpsEnableNudgeLineIfApplicable(for: detail, defaults: defaults)
        XCTAssertEqual(line, specificSafeAutoFollowUpsNudgeCopy)
    }

    func test_safeAutoFollowUpsNudge_hiddenWhenAutonomyOn() {
        let defaults = nudgeIsolatedDefaults()
        defaults.set(
            ExchangeModels.ExchangeThreadAutonomyMode.routineAutoRespond.rawValue,
            forKey: AppServices.safeAutoFollowUpsUserDefaultsKey
        )

        let tid = UUID()
        let cpID = "fixture-cp-nudge-on"
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady
        )
        sh.boundary.requiresHumanApproval = false
        sh.boundary.allowsAutonomousSending = true

        let baseline = nudgeBaselineExternalDraft(threadID: tid, counterpartyID: cpID)
        let detail = ExchangeModels.ThreadDetail(
            thread: baseline.thread,
            turns: [],
            approvals: [],
            drafts: [baseline.draft],
            matches: [],
            counterparties: [
                ExchangeCounterparty(id: cpID, kind: .person, displayName: "Alex Kim", source: .manualEntry)
            ],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        XCTAssertNil(SecretaryProjectionEngine.safeAutoFollowUpsEnableNudgeLineIfApplicable(for: detail, defaults: defaults))
    }

    func test_safeAutoFollowUpsNudge_hiddenForNoMatchEvenWithDraftLikeData() {
        let defaults = nudgeIsolatedDefaults()
        defaults.set(
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue,
            forKey: AppServices.safeAutoFollowUpsUserDefaultsKey
        )

        let tid = UUID()
        let cpID = "fixture-cp-nudge-nomatch"
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady
        )
        sh.boundary.requiresHumanApproval = false
        sh.boundary.allowsAutonomousSending = true

        let baseline = nudgeBaselineExternalDraft(threadID: tid, counterpartyID: cpID)
        var thread = baseline.thread
        thread.state = .noViableMatch(.init(searchedAt: d, explanation: "None"))

        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [baseline.draft],
            matches: [],
            counterparties: [
                ExchangeCounterparty(id: cpID, kind: .person, displayName: "Alex Kim", source: .manualEntry)
            ],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        XCTAssertNil(SecretaryProjectionEngine.safeAutoFollowUpsEnableNudgeLineIfApplicable(for: detail, defaults: defaults))
    }

    func test_safeAutoFollowUpsNudge_hiddenWhenApprovalRequiredPlacement() {
        let defaults = nudgeIsolatedDefaults()
        defaults.set(
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue,
            forKey: AppServices.safeAutoFollowUpsUserDefaultsKey
        )

        let tid = UUID()
        let cpID = "fixture-cp-nudge-approval"
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .needsApproval
        )

        let baseline = nudgeBaselineExternalDraft(threadID: tid, counterpartyID: cpID)
        let detail = ExchangeModels.ThreadDetail(
            thread: baseline.thread,
            turns: [],
            approvals: [],
            drafts: [baseline.draft],
            matches: [],
            counterparties: [
                ExchangeCounterparty(id: cpID, kind: .person, displayName: "Alex Kim", source: .manualEntry)
            ],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        XCTAssertNil(SecretaryProjectionEngine.safeAutoFollowUpsEnableNudgeLineIfApplicable(for: detail, defaults: defaults))
    }

    func test_safeAutoFollowUpsNudge_hiddenWhenAlreadySentWaiting() {
        let defaults = nudgeIsolatedDefaults()
        defaults.set(
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue,
            forKey: AppServices.safeAutoFollowUpsUserDefaultsKey
        )

        let tid = UUID()
        let cpID = "fixture-cp-nudge-waiting"
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady
        )
        sh.boundary.requiresHumanApproval = false
        sh.boundary.allowsAutonomousSending = true

        let baseline = nudgeBaselineExternalDraft(threadID: tid, counterpartyID: cpID)
        var thread = baseline.thread
        thread.state = .awaitingResponse(.init(since: d))

        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [baseline.draft],
            matches: [],
            counterparties: [
                ExchangeCounterparty(id: cpID, kind: .person, displayName: "Alex Kim", source: .manualEntry)
            ],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        XCTAssertNil(SecretaryProjectionEngine.safeAutoFollowUpsEnableNudgeLineIfApplicable(for: detail, defaults: defaults))
    }

    func test_safeAutoFollowUpsNudge_hiddenWithoutRecipientAnchor() {
        let defaults = nudgeIsolatedDefaults()
        defaults.set(
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue,
            forKey: AppServices.safeAutoFollowUpsUserDefaultsKey
        )

        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady
        )
        sh.boundary.requiresHumanApproval = false
        sh.boundary.allowsAutonomousSending = true

        let outbound = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Unanchored outbound text.",
            posture: ExchangePosture()
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .matchFound(.init(foundAt: d, candidateCount: 1, summary: "Fixture"))
        )

        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [outbound],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        XCTAssertFalse(SecretaryProjectionEngine.hasActionableExternalOutboundDraft(in: detail))
        XCTAssertNil(SecretaryProjectionEngine.safeAutoFollowUpsEnableNudgeLineIfApplicable(for: detail, defaults: defaults))
    }

    func test_safeAutoFollowUpsNudge_usesFallbackWhenAutonomousSendCannotBeClaimedFromProjection() {
        let defaults = nudgeIsolatedDefaults()
        defaults.set(
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue,
            forKey: AppServices.safeAutoFollowUpsUserDefaultsKey
        )

        let tid = UUID()
        let cpID = "fixture-cp-nudge-fallback"
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady
        )
        sh.boundary.requiresHumanApproval = false
        sh.boundary.allowsAutonomousSending = false

        let baseline = nudgeBaselineExternalDraft(threadID: tid, counterpartyID: cpID)
        let detail = ExchangeModels.ThreadDetail(
            thread: baseline.thread,
            turns: [],
            approvals: [],
            drafts: [baseline.draft],
            matches: [],
            counterparties: [
                ExchangeCounterparty(id: cpID, kind: .person, displayName: "Alex Kim", source: .manualEntry)
            ],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        let line = SecretaryProjectionEngine.safeAutoFollowUpsEnableNudgeLineIfApplicable(for: detail, defaults: defaults)
        XCTAssertEqual(line, fallbackSafeAutoFollowUpsNudgeCopy)
    }

    func test_safeAutoFollowUpsNudge_hiddenWhenProviderReplyTurnExists() {
        let defaults = nudgeIsolatedDefaults()
        defaults.set(
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue,
            forKey: AppServices.safeAutoFollowUpsUserDefaultsKey
        )

        let tid = UUID()
        let cpID = "fixture-cp-nudge-reply"
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady
        )
        sh.boundary.requiresHumanApproval = false
        sh.boundary.allowsAutonomousSending = true

        let baseline = nudgeBaselineExternalDraft(threadID: tid, counterpartyID: cpID)
        let replyTurn = ExchangeTurn(
            threadID: tid,
            createdAt: d,
            actor: .counterparty,
            kind: .replyReceived,
            summary: "They replied."
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: baseline.thread,
            turns: [replyTurn],
            approvals: [],
            drafts: [baseline.draft],
            matches: [],
            counterparties: [
                ExchangeCounterparty(id: cpID, kind: .person, displayName: "Alex Kim", source: .manualEntry)
            ],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        XCTAssertNil(SecretaryProjectionEngine.safeAutoFollowUpsEnableNudgeLineIfApplicable(for: detail, defaults: defaults))
    }

    func test_safeAutoFollowUpsNudge_hiddenForProviderSecondHalfRole() {
        let defaults = nudgeIsolatedDefaults()
        defaults.set(
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue,
            forKey: AppServices.safeAutoFollowUpsUserDefaultsKey
        )

        let tid = UUID()
        let cpID = "fixture-cp-nudge-provider-role"
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady
        )
        sh.boundary.requiresHumanApproval = false
        sh.boundary.allowsAutonomousSending = true
        sh.status.role = ExchangeSecondHalfRole.provider.displayTitle

        let baseline = nudgeBaselineExternalDraft(threadID: tid, counterpartyID: cpID)
        let detail = ExchangeModels.ThreadDetail(
            thread: baseline.thread,
            turns: [],
            approvals: [],
            drafts: [baseline.draft],
            matches: [],
            counterparties: [
                ExchangeCounterparty(id: cpID, kind: .person, displayName: "Alex Kim", source: .manualEntry)
            ],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        XCTAssertNil(SecretaryProjectionEngine.safeAutoFollowUpsEnableNudgeLineIfApplicable(for: detail, defaults: defaults))
    }

    // MARK: - Draft ready / approve-send gates

    func test_actionableExternalOutboundDraft_excludesApprovedStatus() {
        let tid = UUID()
        let approved = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: d,
            updatedAt: d,
            status: .approved,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Hello anchor.",
            posture: ExchangePosture(),
            metadata: [:]
        )
        XCTAssertFalse(ExchangeMessageDraft.hasActionableExternalOutboundDraft(in: [approved]))

        var drafting = approved
        drafting.status = .draft
        XCTAssertTrue(ExchangeMessageDraft.hasActionableExternalOutboundDraft(in: [drafting]))
    }

    func test_passesApprovalSheetBoundaryPublicCopy_filtersSchemaWords() {
        XCTAssertFalse(SecretaryProjectionEngine.passesApprovalSheetBoundaryPublicCopy("schema v2 coordination path"))
        XCTAssertTrue(SecretaryProjectionEngine.passesApprovalSheetBoundaryPublicCopy("Needs review before sending."))
    }

    // MARK: - Dashboard / Exchange now (same APIs as `SecretaryDashboardView`)

    /// Home “Exchange now” uses `exchangeListStatusLabel` and `displayExchangeCardSubtitlePreferringVisibleStatus` with `pendingApprovalThreadIDs`.
    func test_dashboardExchangeNow_primaryLabel_potentialMatch_notNewMatch() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .requesterReview
        )
        sh.hasRequesterReview = true
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak")),
            stateTitle: "Weak",
            secondHalfDisplay: sh
        )
        let primary = SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .searchResult)
        XCTAssertEqual(primary, "Potential match")
        XCTAssertNotEqual(primary, "New match")
    }

    func test_dashboardExchangeNow_homeSubtitle_potentialMatch_doesNotEchoMisleadingSecondHalfPlainWaiting() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .requesterReview
        )
        sh.hasRequesterReview = true
        sh.plain = ExchangeSecondHalfUIAdapter.DisplayModel.PlainLanguage(
            plainStatusLabel: "Review",
            plainOneLineSummary: "Waiting for the provider's reply",
            primaryCTA: "Open thread",
            followUpReason: nil
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak")),
            stateTitle: "Weak",
            secondHalfDisplay: sh
        )
        let home = SecretaryProjectionEngine.displayExchangeCardSubtitlePreferringVisibleStatus(
            for: item,
            bucket: .searchResult,
            pendingApprovalThreadIDs: [],
            surface: "home"
        )
        XCTAssertFalse(home.localizedCaseInsensitiveContains("waiting for the provider"))
        XCTAssertFalse(home.localizedCaseInsensitiveContains("waiting for reply"))
    }

    func test_dashboardExchangeNow_primaryAndSubtitle_alignNoMatch() {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .decisionReady,
            hasDecisionPacket: true
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .noViableMatch(.init(searchedAt: d, explanation: "None")),
            stateTitle: "No match",
            secondHalfDisplay: sh
        )
        XCTAssertEqual(
            SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .searchResult),
            "No confirmed match yet"
        )
    }

    func test_dashboardExchangeNow_primaryLabel_draftReadyWhenActionableDraft() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak")),
            stateTitle: "Weak",
            hasDraft: true,
            hasActionableExternalOutboundDraft: true,
            draftedBodyPreview: "Hi — quick note about your listing."
        )
        XCTAssertEqual(
            SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .searchResult),
            "Draft ready"
        )
    }

    func test_dashboardExchangeNow_waitingForReply_requiresSentOrWaitEvidence_notJustWeakBucket() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .activeCoordination,
            hasDecisionPacket: false
        )
        sh.plain = ExchangeSecondHalfUIAdapter.DisplayModel.PlainLanguage(
            plainStatusLabel: "Active",
            plainOneLineSummary: "Waiting for their reply",
            primaryCTA: "Open",
            followUpReason: nil
        )
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak")),
            stateTitle: "Weak",
            secondHalfDisplay: sh
        )
        XCTAssertEqual(
            SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .searchResult),
            "Potential match"
        )
        XCTAssertNotEqual(
            SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .searchResult),
            "Waiting for reply"
        )
    }

    func test_dashboardExchangeNow_waiting_forRealAwaitingResponse() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .awaitingResponse(.init(since: d)),
            stateTitle: "Waiting",
            awaitingReply: true,
            secondHalfDisplay: nil
        )
        XCTAssertEqual(
            SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .searchResult),
            "Waiting for reply"
        )
    }

    func test_dashboardExchangeNow_bannedPrimaryStringsNotUsed_byVisibleStatus() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak")),
            stateTitle: "Weak",
            secondHalfDisplay: nil
        )
        let label = SecretaryProjectionEngine.exchangeListStatusLabel(for: item, bucket: .searchResult)
        let lower = label.lowercased()
        XCTAssertFalse(lower.contains("new match"))
        XCTAssertFalse(lower.contains("moving"))
        XCTAssertFalse(lower.contains("in progress"))
        XCTAssertFalse(lower.contains("new activity in this thread"))
    }

    // MARK: - Helpers

    private func assertTimelineUserFacingBannedFree(_ text: String) {
        let lower = text.lowercased()
        XCTAssertNil(
            lower.range(of: #"second(?:[\s_-]+half|_half)"#, options: [.regularExpression, .caseInsensitive]),
            "second-half wording should be scrubbed from timeline presentation."
        )
        let tokens = [
            "relay",
            "envelope",
            "outbox",
            "metadata",
            "execution",
            "trace",
            "agency",
            "mutation",
            "pipeline",
            "autonomous"
        ]
        for term in tokens {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            XCTAssertNil(
                lower.range(of: "\\b\(escaped)\\b", options: [.regularExpression, .caseInsensitive]),
                "'\(term)' leaked into timeline projection copy."
            )
        }
    }

    // MARK: - Inbound provider / approval outcome UX

    func test_inboundProviderCardTitleRewrite_avoidsRawInboundNodeTitle() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Inbound message from node-abcdef12",
            subtitle: "Legacy",
            state: .drafting,
            stateTitle: "Drafting",
            selectedCounterpartyName: "Weekend photo package",
            prefersInboundProviderCardTitleRewrite: true,
            cardInboundSenderLabel: "Alex Kim",
            cardInboundRequesterPreview: "Are you available June 14?"
        )

        let title = SecretaryProjectionEngine.displayTitle(for: item, surface: "threads")
        XCTAssertTrue(title.hasPrefix("New inquiry about"), "Expected hydrated offer/profile headline: \(title)")
        XCTAssertFalse(title.localizedCaseInsensitiveContains("Inbound message from node"))

        let subtitle = ExchangeThreadCardTitleProjection.inboxCardSubtitle(
            for: item,
            primaryTitle: title,
            surface: "threads"
        )
        XCTAssertTrue(
            subtitle.localizedCaseInsensitiveContains("June 14"),
            "Subtitle should surface requester preview: \(subtitle)"
        )
    }

    func test_providerNeedsInputWithoutDraft_beatsSendingAndDraftReady() {
        let tid = UUID()
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .needsInput,
            agencyPhase: .needsUserInput,
            statusRole: ExchangeSecondHalfRole.provider.displayTitle
        )
        sh.operatingContext.userFacingMissingFacts = ["Price range", "Timeline", "Capacity"]

        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .sending(.init(startedAt: d, attemptNumber: 1, channelSummary: "Fixture send")),
            stateTitle: "Sending",
            hasActionableExternalOutboundDraft: false,
            deliveryStatusText: "Sending now",
            secondHalfDisplay: sh
        )

        let vs = SecretaryProjectionEngine.visibleThreadStatus(
            for: item,
            bucket: SecretaryProjectionEngine.bucket(for: item)
        )
        XCTAssertEqual(vs.primary, SecretaryProjectionEngine.ExchangeVisibleThreadStatusPrimary.needsYourInput)
        XCTAssertEqual(vs.label, "Needs your input")
        XCTAssertFalse(vs.label.localizedCaseInsensitiveContains("Sending"))
        let sub = vs.subtitle?.lowercased() ?? ""
        XCTAssertTrue(sub.contains("price range") || sub.contains("needs"))
    }

    func test_threadLayout_offerHeroBeforeConversation_noConversationReorder() {
        let tid = UUID()
        let reply = ExchangeTurn(
            threadID: tid,
            createdAt: d,
            actor: .counterparty,
            kind: .replyReceived,
            summary: "They replied",
            detail: "Can we meet Tuesday?"
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .awaitingResponse(.init(since: d)),
            selectedCounterpartyID: "cp-fixture",
            selectedOfferID: "offer-fixture"
        )
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .activeCoordination
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [reply],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        XCTAssertFalse(SecretaryProjectionEngine.threadViewShouldPrioritizeConversationBeforeSurfaceHero(for: detail))
    }

    func test_compactInboundMessageStrip_providerInboundMetadata_surfacesLatestBody() {
        let tid = UUID()
        let reply = ExchangeTurn(
            threadID: tid,
            createdAt: d,
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Hey Hansen.",
            detail: "Hey Hansen."
        )
        var thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .awaitingResponse(.init(since: d)),
            selectedCounterpartyID: "cp-fixture",
            selectedOfferID: "offer-fixture",
            metadata: ["inbound_thread": "true"]
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [reply],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: nil
        )
        let strip = SecretaryProjectionEngine.compactInboundMessageStrip(for: detail)
        XCTAssertNotNil(strip)
        XCTAssertEqual(strip?.bodyLine, "Hey Hansen.")
    }

    func test_threadViewOutstandingPostApprovalNotice_whenSurfaceLeadsAndPipelineMissing() {
        let tid = UUID()
        let grant = ExchangeTurn(
            threadID: tid,
            createdAt: d.addingTimeInterval(50),
            actor: .user,
            kind: .approvalGranted,
            summary: "Approved",
            detail: "You approved sending the prepared reply."
        )
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .needsInput,
            agencyPhase: .needsUserInput,
            statusRole: ExchangeSecondHalfRole.provider.displayTitle
        )
        sh.hasProviderReception = false
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .draftReady(.init(preparedAt: d, summary: "Fixture")),
            selectedCounterpartyID: "cp-fixture",
            selectedOfferID: nil
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [grant],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        XCTAssertFalse(SecretaryProjectionEngine.threadViewShouldPrioritizeConversationBeforeSurfaceHero(for: detail))
        let line = SecretaryProjectionEngine.threadViewOutstandingPostApprovalNoticeLine(for: detail)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.localizedCaseInsensitiveContains("approval recorded"))
        XCTAssertTrue(line!.localizedCaseInsensitiveContains("input"))
    }

    func test_visibleThreadStatus_providerInboundAwaitingSecondHalf_listsNewMessageNotApproval() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Fixture",
            subtitle: "",
            state: .awaitingResponse(.init(since: d)),
            stateTitle: "Waiting for reply",
            hasPendingApproval: true,
            hasActionableExternalOutboundDraft: false,
            deliveryStatusText: "Prepared locally · waiting for approval",
            secondHalfDisplay: nil,
            prefersInboundProviderCardTitleRewrite: true,
            cardInboundRequesterPreview: "Hey Hansen."
        )
        let vs = SecretaryProjectionEngine.visibleThreadStatus(
            for: item,
            bucket: SecretaryProjectionEngine.bucket(for: item)
        )
        XCTAssertEqual(vs.label, "New message")
        XCTAssertFalse(vs.label.localizedCaseInsensitiveContains("approval"))
    }

    func test_providerReplyBarIntent_requestUserInputWithoutDraft_suggestsAnswer() {
        let tid = UUID()
        let turn = ExchangeTurn(
            threadID: tid,
            createdAt: d,
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Hi",
            detail: "Hey Hansen."
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: d,
            updatedAt: d,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .awaitingResponse(.init(since: d)),
            metadata: ["inbound_thread": "true"]
        )
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .needsInput,
            agencyPhase: .needsUserInput,
            statusRole: ExchangeSecondHalfRole.provider.displayTitle
        )
        sh.nextMove = ExchangeSecondHalfUIAdapter.NextMove(
            action: "Needs your input",
            actionRaw: ExchangeSecondHalfAction.requestUserInput.rawValue,
            title: "Add detail",
            rationale: "Missing facts.",
            requiredInputs: [],
            needsGeneration: false,
            needsUserInput: true,
            needsApproval: false,
            isAutonomous: false,
            isBlockingOnHuman: true
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [turn],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )
        XCTAssertEqual(
            SecretaryProjectionEngine.providerInboundReplyBarIntent(for: detail),
            .openInboundReplyComposer
        )
    }

    // MARK: - No-match visibility vs actionability

    func test_bucket_noViableMatch_mapsToSearchResult_notNone() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Find piano teacher",
            subtitle: "",
            state: .noViableMatch(.init(searchedAt: d, explanation: "No match")),
            stateTitle: "No match",
            capturedRequestText: "Find piano teacher"
        )
        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .searchResult)
    }

    func test_interactionPolicy_noViableMatch_isTerminalSearchReceipt() {
        let tid = UUID()
        let item = inbox(
            threadID: tid,
            title: "Find piano teacher",
            subtitle: "",
            state: .noViableMatch(.init(searchedAt: d, explanation: "No match")),
            stateTitle: "No match"
        )
        XCTAssertEqual(SecretaryProjectionEngine.interactionPolicy(for: item), .terminalSearchReceipt)
        XCTAssertTrue(SecretaryProjectionEngine.isTerminalSearchReceipt(item))
        XCTAssertFalse(SecretaryProjectionEngine.isOperationalThreadOpenAllowed(item))
    }

    func test_interactionPolicy_weakMatch_isOperational() {
        let tid = UUID()
        var item = inbox(
            threadID: tid,
            title: "Weak search",
            subtitle: "",
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak", suggestedRefinement: nil)),
            stateTitle: "Weak"
        )
        item.candidateCount = 2
        item.shouldDiscover = true
        XCTAssertEqual(SecretaryProjectionEngine.interactionPolicy(for: item), .operational)
        XCTAssertTrue(SecretaryProjectionEngine.isOperationalThreadOpenAllowed(item))
    }

    func test_showsDiscoveryCandidateReviewCTA_noViableMatch_isFalse_evenWithMultipleCandidates() {
        let tid = UUID()
        var item = inbox(
            threadID: tid,
            title: "Find piano teacher",
            subtitle: "",
            state: .noViableMatch(.init(searchedAt: d, explanation: "No match")),
            stateTitle: "No match"
        )
        item.candidateCount = 3
        XCTAssertFalse(SecretaryProjectionEngine.showsDiscoveryCandidateReviewCTA(for: item))
        XCTAssertNil(SecretaryProjectionEngine.discoveryCandidateReviewPrimaryLine(for: item))
    }

    func test_resolveCurrentFocusItem_pendingBeatsTerminalNoMatchPreferred() {
        let pendingID = UUID()
        let noMatchID = UUID()
        let threads = [
            inbox(
                threadID: noMatchID,
                title: "Find piano teacher",
                subtitle: "",
                state: .noViableMatch(.init(searchedAt: d, explanation: "No match")),
                stateTitle: "No match",
                updatedAt: d.addingTimeInterval(100),
                capturedRequestText: "Find piano teacher"
            ),
            inbox(
                threadID: pendingID,
                title: "Pending approval",
                subtitle: "",
                state: .awaitingApproval(.init(summary: "Approve")),
                stateTitle: "Pending",
                updatedAt: d,
                hasPendingApproval: true
            )
        ]
        let focus = SecretaryDeskSnapshot.resolveCurrentFocusItem(
            threads: threads,
            pendingApprovals: [],
            preferredThreadID: noMatchID
        )
        XCTAssertEqual(focus?.threadID, pendingID)
    }

    func test_buildImmediateStripInboxItem_weakMatch_isOperational() {
        let tid = UUID()
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: d,
                updatedAt: d,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .providerSearch,
                    title: "Fixture",
                    objective: "find provider",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak", suggestedRefinement: nil))
            ),
            turns: [],
            approvals: [],
            drafts: [],
            matches: [ExchangeMatch(
                threadID: tid,
                counterpartyID: UUID(),
                createdAt: d,
                score: 0.5,
                strength: .weak,
                status: .candidate
            )],
            counterparties: [],
            artifacts: [],
            summary: "Weak matches"
        )
        let item = SecretarySearchResultProjection.buildImmediateStripInboxItem(
            detail: detail,
            capturedRequestText: "Find me a piano teacher."
        )
        XCTAssertEqual(SecretaryProjectionEngine.bucket(for: item), .searchResult)
        XCTAssertTrue(SecretaryProjectionEngine.isOperationalThreadOpenAllowed(item))
    }

    private func inbox(
        threadID: UUID,
        title: String,
        subtitle: String,
        state: ExchangeState,
        stateTitle: String,
        capturedRequestText: String? = nil,
        updatedAt: Date? = nil,
        requiresHumanDecision: Bool = false,
        hasFailure: Bool = false,
        visibleSummary: String? = nil,
        selectedCounterpartyName: String? = nil,
        selectedCounterpartyID: ExchangeCounterparty.ID? = nil,
        selectedPublicProfileID: String? = nil,
        selectedOfferID: ExchangeOffer.ID? = nil,
        hasPendingApproval: Bool = false,
        hasDraft: Bool = false,
        hasActionableExternalOutboundDraft: Bool = false,
        awaitingReply: Bool = false,
        deliveryStatusText: String? = nil,
        latestFailureSummary: String? = nil,
        failureWhatHappened: String? = nil,
        draftedSubject: String? = nil,
        draftedBodyPreview: String? = nil,
        needsClarification: Bool = false,
        secondHalfDisplay: ExchangeSecondHalfUIAdapter.DisplayModel? = nil,
        prefersInboundProviderCardTitleRewrite: Bool = false,
        cardInboundSenderLabel: String? = nil,
        cardInboundRequesterPreview: String? = nil,
        prefersPreparedUserDirectedOutboundSend: Bool = false
    ) -> ExchangeModels.InboxItem {
        ExchangeModels.InboxItem(
            threadID: threadID,
            title: title,
            capturedRequestText: capturedRequestText,
            subtitle: subtitle,
            state: state,
            stateTitle: stateTitle,
            updatedAt: updatedAt ?? d,
            requiresHumanDecision: requiresHumanDecision,
            hasFailure: hasFailure,
            visibleSummary: visibleSummary,
            selectedCounterpartyID: selectedCounterpartyID,
            selectedCounterpartyName: selectedCounterpartyName,
            selectedPublicProfileID: selectedPublicProfileID,
            selectedOfferID: selectedOfferID,
            hasPendingApproval: hasPendingApproval,
            hasDraft: hasDraft,
            hasActionableExternalOutboundDraft: hasActionableExternalOutboundDraft,
            awaitingReply: awaitingReply,
            latestFailureSummary: latestFailureSummary,
            deliveryStatusText: deliveryStatusText,
            draftedSubject: draftedSubject,
            draftedBodyPreview: draftedBodyPreview,
            failureWhatHappened: failureWhatHappened,
            needsClarification: needsClarification,
            secondHalfDisplay: secondHalfDisplay,
            prefersInboundProviderCardTitleRewrite: prefersInboundProviderCardTitleRewrite,
            cardInboundSenderLabel: cardInboundSenderLabel,
            cardInboundRequesterPreview: cardInboundRequesterPreview,
            prefersPreparedUserDirectedOutboundSend: prefersPreparedUserDirectedOutboundSend
        )
    }
}
