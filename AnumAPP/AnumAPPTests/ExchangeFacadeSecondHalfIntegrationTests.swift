import XCTest
@testable import AnumCore

/// ExchangeFacade app-level second-half integration around the real mutation path:
/// `attemptRequesterSecondHalfAutonomousOutbound` -> `runSecondHalfAfterThreadMutation`.
final class ExchangeFacadeSecondHalfIntegrationTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_720_000_123)
    private let threadAutonomyModeKey = "secretary.threadAutonomy.mode"
    private let discoveryModeKey = "secretary.discovery.mode"

    override func setUp() {
        super.setUp()
        setenv("ANUM_DISABLE_RUNTIME_PREWARM", "1", 1)
        setenv("ANUM_DISABLE_ONDEVICE_LLM", "1", 1)
    }

    // MARK: - Requester outbound (facade path)

    private static let rooferUserRequestSummary =
        "help me find a roofer in Aurora for tomorrow 2:30 to do an appraisal"

    func test_requesterKnownFacts_threadAutoSendOn_queuesSpecificOutboundInquiry() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000C201")!
        let data = try await seedRequesterOutboundRooferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: Self.rooferUserRequestSummary
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 1)

        let body = await Self.combinedOutboundDraftBody(outbox: outbox, store: harness.store)
        let ctx = await failureContext(
            harness: harness,
            threadID: data.threadID,
            expected: "requester outbound body should echo roofer request details"
        )
        let hasRoofing = body.contains("roof") || body.contains("roofing")
        let hasWhen = body.contains("2:30") || body.contains("tomorrow")
        let hasWhere = body.contains("aurora")
        let hasPurpose = body.contains("appraisal")
        guard hasRoofing, hasWhen, hasWhere, hasPurpose else {
            XCTFail(
                "Expected roofing + Aurora + time + appraisal in outbound body.\nbody=\(body)\n\(ctx)"
            )
            return
        }

        let forbiddenSnippets = ["confirmed", "booked", "i accept", "we will pay", "go ahead"]
        for snippet in forbiddenSnippets {
            XCTAssertFalse(
                body.contains(snippet),
                "Outbound must stay non-commitment; found \(snippet)."
            )
        }

        let thread = try await harness.store.requireThread(id: data.threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "allowed")
    }

    func test_requesterKnownFacts_threadAutoSendOff_doesNotQueueOutbound() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .manualOnly,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000C202")!
        try await seedRequesterOutboundRooferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: Self.rooferUserRequestSummary
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox.count, 0)
        let thread = try await harness.store.requireThread(id: threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "disabledByUserSetting")
    }

    func test_requesterKnownFacts_draftOnly_doesNotQueueOutbound() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .draftOnly,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000C207")!
        try await seedRequesterOutboundRooferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: Self.rooferUserRequestSummary
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let draftOnlyOutbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(draftOnlyOutbox.count, 0)
        let thread = try await harness.store.requireThread(id: threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "disabledByUserSetting")
    }

    func test_requesterKnownFacts_forYouDiscoveryModeDoesNotControlRequesterOutbound_part1_discoveryOffQueues() async throws {
        UserDefaults.standard.set(ExchangeModels.SecretaryDiscoveryMode.off.rawValue, forKey: discoveryModeKey)

        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000C203")!
        try await seedRequesterOutboundRooferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: Self.rooferUserRequestSummary
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let part1Outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(part1Outbox.count, 1)
        let thread = try await harness.store.requireThread(id: threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "allowed")
    }

    func test_requesterKnownFacts_forYouDiscoveryModeDoesNotControlRequesterOutbound_part2_safeAutoSendDoesNotOverrideOffAutonomy(
    ) async throws {
        UserDefaults.standard.set(
            ExchangeModels.SecretaryDiscoveryMode.safeAutoSend.rawValue,
            forKey: discoveryModeKey
        )

        let harness = try makeHarness(
            threadAutonomyMode: .manualOnly,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000C204")!
        try await seedRequesterOutboundRooferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: Self.rooferUserRequestSummary
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let part2Outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(part2Outbox.count, 0)
        let thread = try await harness.store.requireThread(id: threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "disabledByUserSetting")
    }

    func test_requesterCommitmentLanguage_needsApproval_noOutbound() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000C205")!
        let commitmentBlob =
            "I accept your roofing quote - please confirm we booked the slot tomorrow. Go ahead - we will pay the deposit immediately."
        try await seedRequesterOutboundRooferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: commitmentBlob,
            intentTitle: commitmentBlob,
            intentObjective: commitmentBlob
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let commitmentOutbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(commitmentOutbox.count, 0)
        let thread = try await harness.store.requireThread(id: threadID)
        let outcome = thread.metadata["autonomous_send_outcome"] ?? ""
        let commitCtx = await failureContext(
            harness: harness,
            threadID: threadID,
            expected: "commitment language should block requester autonomous outbound"
        )
        XCTAssertTrue(
            outcome == "needsUserApproval" || outcome == "blocked",
            "Expected needsUserApproval/blocked commitment hold, got \(outcome).\n\(commitCtx)"
        )
        XCTAssertEqual(thread.metadata["autonomous_send_allowed"], "false")
    }

    func test_requesterDuplicateMutation_doesNotQueueDuplicateOutbound() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000C206")!
        try await seedRequesterOutboundRooferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: Self.rooferUserRequestSummary
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)
        let afterFirstEnqueue = await harness.federation.callCounts()
        XCTAssertEqual(afterFirstEnqueue.queued, 1)

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let counts = await harness.federation.callCounts()
        XCTAssertEqual(counts.queued, 1, "Second mutation must not enqueue another federation outbound.")

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox.count, 1)
        let thread = try await harness.store.requireThread(id: threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "duplicate")
    }

    // MARK: - 1) requester match-found triggers second-half

    func test_requesterMatchFoundMutation_persistsSecondHalfAndBuildsDisplay() async throws {
        let harness = try makeHarness()
        let data = try await seedRequesterScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B101")!,
            requestText: "Find a reliable home visit provider."
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let persistedThread = try await harness.store.requireThread(id: data.threadID)
        XCTAssertNotNil(persistedThread.secondHalf)
        XCTAssertEqual(
            persistedThread.secondHalf?.currentStateRaw,
            ExchangeSecondHalfState.matchFound.rawValue,
            "Second-half snapshot should persist canonical state tokens."
        )
        XCTAssertEqual(persistedThread.secondHalf?.roleRaw.lowercased(), "requester")
        XCTAssertNotNil(persistedThread.secondHalf?.nextMoveActionRaw)
        XCTAssertTrue(
            persistedThread.secondHalf?.nextMoveActionRaw?.isEmpty == false,
            "Expected a concrete second-half next move action."
        )
        let detail = try await harness.facade.getThread(threadID: data.threadID)
        XCTAssertNotNil(detail.secondHalfDisplay)
        XCTAssertEqual(detail.secondHalfDisplay?.threadID, data.threadID)
    }

    // MARK: - 2) requester missing facts -> clarification/input need

    func test_requesterMissingFacts_persistsNeedsInputAndNoOutboundQueue() async throws {
        let harness = try makeHarness()
        let data = try await seedRequesterNeedsClarificationScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B102")!,
            clarificationQuestion: "Please confirm price, availability, and best contact details."
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let thread = try await harness.store.requireThread(id: data.threadID)
        let snapshot = try XCTUnwrap(thread.secondHalf)
        XCTAssertTrue(
            !snapshot.missingFacts.isEmpty ||
            !snapshot.requiredInputs.isEmpty ||
            !snapshot.unresolvedIssues.isEmpty ||
            snapshot.currentStateRaw.localizedCaseInsensitiveContains("clarification")
        )

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertTrue(outbox.isEmpty, "Requester clarification need should not queue outbound send.")
    }

    // MARK: - 3) requester decision-ready with sufficient facts

    func test_requesterDecisionReadyWithFacts_surfacesDecisionWithoutCommitmentSend() async throws {
        let harness = try makeHarness()
        let data = try await seedRequesterDecisionReadyScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B103")!
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let thread = try await harness.store.requireThread(id: data.threadID)
        let snapshot = try XCTUnwrap(thread.secondHalf)
        XCTAssertNotNil(snapshot.decisionSummary)
        XCTAssertTrue(
            snapshot.currentStateRaw.localizedCaseInsensitiveContains("decision") ||
            snapshot.currentStateRaw.localizedCaseInsensitiveContains("review"),
            "Expected requester-side decision/review framing."
        )

        let approvals = try await harness.store.fetchLatestApproval(threadID: data.threadID)
        if snapshot.requiresHumanApproval {
            XCTAssertNotNil(approvals, "Approval should exist when commitment approval is required.")
        }
        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertTrue(outbox.isEmpty, "No commitment-bearing external queueing without approval.")
    }

    // MARK: - 4) provider routine inquiry auto-answer inside boundary

    func test_providerRoutineInquiry_autoRespondDraftWithinBoundary() async throws {
        let harness = try makeHarness()
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B104")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let thread = try await harness.store.requireThread(id: data.threadID)
        let snapshot = try XCTUnwrap(thread.secondHalf)
        XCTAssertEqual(snapshot.roleRaw.lowercased(), "provider")
        XCTAssertFalse(snapshot.requiresHumanApproval)
        XCTAssertEqual(snapshot.nextMoveActionRaw, ExchangeSecondHalfAction.autoRespond.rawValue)

        let drafts = try await harness.store.listDrafts(threadID: data.threadID)
        let secondHalfDraft = drafts.first { $0.metadata["second_half_generated"] == "true" }
        XCTAssertNotNil(secondHalfDraft)
        XCTAssertEqual(secondHalfDraft?.metadata["second_half_action"], ExchangeSecondHalfAction.autoRespond.rawValue)

        let latestApproval = try await harness.store.fetchLatestApproval(threadID: data.threadID)
        XCTAssertNil(latestApproval, "Routine provider answer should not create commitment approval.")
    }

    // MARK: - 5) provider commitment-bearing inquiry escalates

    func test_providerCommitmentBearingInquiry_escalatesAndPreventsAutonomousSend() async throws {
        let harness = try makeHarness()
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B105")!,
            requestText: "Can we sign a contract with custom pricing and reserve a slot?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let thread = try await harness.store.requireThread(id: data.threadID)
        let snapshot = try XCTUnwrap(thread.secondHalf)
        XCTAssertEqual(snapshot.roleRaw.lowercased(), "provider")
        XCTAssertTrue(snapshot.requiresHumanApproval)
        XCTAssertTrue(
            snapshot.nextMoveActionRaw == ExchangeSecondHalfAction.escalateForApproval.rawValue ||
            snapshot.nextMoveActionRaw == ExchangeSecondHalfAction.requestUserInput.rawValue
        )

        let approval = try await harness.store.fetchLatestApproval(threadID: data.threadID)
        XCTAssertNotNil(approval, "Escalation path should surface a local approval/review artifact.")

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertTrue(outbox.isEmpty, "Commitment-bearing inquiry must not autonomously queue outbound.")
    }

    // MARK: - 6) provider unknown fact does not invent confident answer

    func test_providerUnknownFact_recordsMissingAndNeedsInput() async throws {
        let harness = try makeHarness()
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000B106")!
        try await seedProviderUnknownFactScenario(store: harness.store, threadID: threadID)

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: threadID,
            now: fixedNow
        )

        let thread = try await harness.store.requireThread(id: threadID)
        let snapshot = try XCTUnwrap(thread.secondHalf)
        XCTAssertEqual(snapshot.roleRaw.lowercased(), "provider")
        let drafts = try await harness.store.listDrafts(threadID: threadID)
        let latestSecondHalfDraft = drafts
            .filter { $0.metadata["second_half_generated"] == "true" }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first

        let body = latestSecondHalfDraft?.body.lowercased() ?? ""
        let asksForMoreContext =
            body.contains("clarif") ||
            body.contains("need") ||
            body.contains("share") ||
            body.contains("detail")

        XCTAssertTrue(
            !snapshot.missingFacts.isEmpty ||
            !snapshot.requiredInputs.isEmpty ||
            asksForMoreContext,
            "Unknown provider inquiry should avoid fabricated certainty."
        )
    }

    // MARK: - 7) display survives reload

    func test_secondHalfDisplaySurvivesReloadWithStablePlacement() async throws {
        let harness = try makeHarness()
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B107")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let first = try await harness.facade.getThread(threadID: data.threadID)
        let second = try await harness.facade.getThread(threadID: data.threadID)

        let firstDisplay = try XCTUnwrap(first.secondHalfDisplay)
        let secondDisplay = try XCTUnwrap(second.secondHalfDisplay)
        let persistedThread = try await harness.store.requireThread(id: data.threadID)
        let persisted = try XCTUnwrap(persistedThread.secondHalf)

        XCTAssertEqual(firstDisplay.threadID, secondDisplay.threadID)
        XCTAssertEqual(firstDisplay.threadID, data.threadID)
        XCTAssertEqual(firstDisplay.status.role, secondDisplay.status.role)
        XCTAssertEqual(firstDisplay.status.state, secondDisplay.status.state)
        XCTAssertEqual(firstDisplay.placement, secondDisplay.placement)
        XCTAssertEqual(
            ExchangeSecondHalfUIAdapter.canonicalSecondHalfActionRaw(for: firstDisplay),
            persisted.nextMoveActionRaw,
            "Snapshot should store machine action tokens; compare via canonical raw, not localized action title."
        )
        XCTAssertFalse(firstDisplay.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(firstDisplay.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - 8) action executor boundary behavior through facade path

    func test_actionExecutorPath_routineDraftButCommitmentNeverQueuesOutbound() async throws {
        let harness = try makeHarness()
        let routine = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B108")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: routine.threadID,
            now: fixedNow
        )

        let routineDrafts = try await harness.store.listDrafts(threadID: routine.threadID)
        XCTAssertTrue(
            routineDrafts.contains(where: { $0.metadata["second_half_action"] == ExchangeSecondHalfAction.autoRespond.rawValue }),
            "Routine provider flow should prepare a local second-half draft."
        )

        let commitment = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B109")!,
            requestText: "Please issue a contract with final price and schedule commitment."
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: commitment.threadID,
            now: fixedNow
        )

        let commitmentThread = try await harness.store.requireThread(id: commitment.threadID)
        let commitmentSnapshot = try XCTUnwrap(commitmentThread.secondHalf)
        XCTAssertTrue(commitmentSnapshot.requiresHumanApproval)

        let commitmentOutbox = try await harness.store.listOutboxItems(filter: .init(threadID: commitment.threadID))
        XCTAssertTrue(
            commitmentOutbox.isEmpty,
            "Commitment-bearing second-half plan must not send/queue outbound directly."
        )
    }

    func test_providerRoutineKnownFact_authorityOn_attemptsAutonomousQueue() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B110")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 1)
        guard let queued = outbox.first else {
            XCTFail(await failureContext(harness: harness, threadID: data.threadID, expected: "one queued outbox item for allowed routine provider send"))
            return
        }
        XCTAssertFalse(queued.payloadSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let thread = try await harness.store.requireThread(id: data.threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "allowed")
        XCTAssertEqual(thread.metadata["autonomous_send_allowed"], "true")
        let latestApproval = try await harness.store.fetchLatestApproval(threadID: data.threadID)
        XCTAssertNotEqual(latestApproval?.status, .pending)
    }

    // MARK: - Autonomous send audit persistence + provider reception DTO

    func test_autonomousSendAuditRows_persistAfterProviderRoutineQueue() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B121")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let audits = try await harness.store.listAuditRecords(
            filter: ExchangeAuditFilter(threadID: data.threadID, limit: 64)
        )
        let traces = audits.filter { $0.metadata["trace_kind"] == "autonomous_send_attempt_v1" }
        XCTAssertFalse(traces.isEmpty, "Expected autonomous send attempt audit rows after autonomous queue path.")
        XCTAssertTrue(
            traces.contains { $0.metadata["queued"] == "true" },
            "Expected at least one autonomous send trace with queued=true."
        )
    }

    func test_getThread_includesAutonomousSendAuditRecords() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B122")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let detail = try await harness.facade.getThread(threadID: data.threadID)
        let traces = detail.auditRecords.filter { $0.metadata["trace_kind"] == "autonomous_send_attempt_v1" }
        XCTAssertFalse(traces.isEmpty, "getThread should surface autonomous send traces for SecretaryThreadView.")
        XCTAssertTrue(
            traces.contains { $0.metadata["queued"] == "true" },
            "Expected queued autonomous send trace in ThreadDetail.auditRecords."
        )
    }

    func test_getThread_secondHalfDisplay_includesProviderReceptionWhenExpected() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B123")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let detail = try await harness.facade.getThread(threadID: data.threadID)
        let display = try XCTUnwrap(detail.secondHalfDisplay)
        XCTAssertTrue(
            display.hasProviderReception && display.providerReception != nil,
            "Provider routine inbound fixture should populate provider reception on DisplayModel."
        )
        let reception = try XCTUnwrap(display.providerReception)
        XCTAssertFalse(reception.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(reception.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        if let anchor = reception.matchedAnchor {
            XCTAssertFalse(anchor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if let ask = reception.requesterAsk {
            XCTAssertFalse(ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func test_discoveryModeOff_doesNotDisableThreadAutoSendWhenThreadAutonomyOn() async throws {
        UserDefaults.standard.set(ExchangeModels.SecretaryDiscoveryMode.off.rawValue, forKey: discoveryModeKey)
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B119")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 1)
        let thread = try await harness.store.requireThread(id: data.threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "allowed")
    }

    func test_providerRoutineKnownFact_authorityOff_doesNotQueueAndRecordsReason() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .manualOnly,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B111")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let thread = try await harness.store.requireThread(id: data.threadID)
        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 0)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "disabledByUserSetting")
        XCTAssertEqual(thread.metadata["autonomous_send_allowed"], "false")
    }

    func test_discoveryModeSafeAutoSend_doesNotEnableThreadAutoSendWhenThreadAutonomyOff() async throws {
        UserDefaults.standard.set(ExchangeModels.SecretaryDiscoveryMode.safeAutoSend.rawValue, forKey: discoveryModeKey)
        let harness = try makeHarness(
            threadAutonomyMode: .manualOnly,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B11A")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 0)
        let thread = try await harness.store.requireThread(id: data.threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "disabledByUserSetting")
    }

    func test_providerRoutineKnownFact_draftOnly_blocksQueueAndRecordsDisabledByUserSetting() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .draftOnly,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B115")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 0)
        let thread = try await harness.store.requireThread(id: data.threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "disabledByUserSetting")
    }

    func test_providerContextMissingAnchors_blocksAutoSendWithSetupReason() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000B112")!
        try await seedProviderUnknownFactScenario(store: harness.store, threadID: threadID)

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: threadID,
            now: fixedNow
        )

        let thread = try await harness.store.requireThread(id: threadID)
        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox.count, 0)
        XCTAssertEqual(thread.metadata["autonomous_send_allowed"], "false")
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "needsProviderSetup")
    }

    func test_duplicateMutationRun_doesNotQueueDuplicateAutonomousOutbound() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B113")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)
        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)

        let counts = await harness.federation.callCounts()
        XCTAssertEqual(counts.queued, 1, "Second pass should be deduped.")
        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 1)
        let thread = try await harness.store.requireThread(id: data.threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "duplicate")
    }

    func test_deliveryUnavailable_recordsDeliveryReasonAndSkipsQueue() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: false,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B114")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)

        let thread = try await harness.store.requireThread(id: data.threadID)
        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 0)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "deliveryUnavailable")
        XCTAssertEqual(thread.metadata["autonomous_send_allowed"], "false")
    }

    func test_providerUnknownFact_autonomyOn_noOutboxAndOutcomeInsufficientGrounding() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B116")!,
            requestText: "What is your submarine-certified emergency rate?",
            commercialFacts: SecondHalfEngineTestFixtures.restrictiveAutoAnswerFacts()
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 0)
        let thread = try await harness.store.requireThread(id: data.threadID)
        let outcome = thread.metadata["autonomous_send_outcome"]
        XCTAssertTrue(
            outcome == "insufficientGrounding" || outcome == "needsUserApproval",
            "Autonomous provider send should stay blocked for ungrounded asks; policy may surface needsUserApproval before insufficientGrounding. outcome=\(outcome ?? "nil")"
        )
    }

    func test_providerRoutineKnownFact_fullWithinBoundaries_eligibleRoute_outboxIncreasesAndAllowed() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B118")!,
            requestText: "What is your home visit price?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 1)
        guard let queued = outbox.first else {
            XCTFail(await failureContext(harness: harness, threadID: data.threadID, expected: "one queued outbox item for fullWithinBoundaries routine send"))
            return
        }
        XCTAssertFalse(queued.payloadSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let thread = try await harness.store.requireThread(id: data.threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "allowed")
    }

    func test_providerRoutineStructuredAnswer_flowsToDisplayMetadataAndOutboxBody() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000B120")!
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: threadID,
            requestText: "What is your home visit price and service area?"
        )

        let outboxBefore = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outboxBefore.count, 0)

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)

        let detail = try await harness.facade.getThread(threadID: data.threadID)
        let display = try XCTUnwrap(detail.secondHalfDisplay)
        XCTAssertEqual(
            ExchangeSecondHalfUIAdapter.canonicalSecondHalfActionRaw(for: display),
            ExchangeSecondHalfAction.autoRespond.rawValue
        )
        XCTAssertTrue(
            display.placement.rawValue.localizedCaseInsensitiveContains("provider"),
            "Expected provider-side reception placement; got \(display.placement.rawValue)"
        )

        let thread = try await harness.store.requireThread(id: data.threadID)
        XCTAssertEqual(thread.metadata["autonomous_send_outcome"], "allowed")
        XCTAssertEqual(thread.metadata["autonomous_send_allowed"], "true")

        let outboxAfter = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outboxAfter.count, outboxBefore.count + 1)

        let queuedBody = await Self.combinedOutboundDraftBody(outbox: outboxAfter, store: harness.store)
        let hasStructuredAnswerLine =
            queuedBody.contains("$120")
            || queuedBody.contains("120")
            || queuedBody.contains("metro east")
            || queuedBody.contains("weekdays 9-5")
            || queuedBody.contains("service area")
            || queuedBody.contains("availability")
        XCTAssertTrue(
            hasStructuredAnswerLine,
            "Expected queued body to include structured provider answer line(s), got: \(queuedBody)"
        )

        let forbiddenCommitmentSnippets = ["confirmed", "booked", "i accept", "we will pay", "go ahead"]
        for snippet in forbiddenCommitmentSnippets {
            XCTAssertFalse(
                queuedBody.contains(snippet),
                "Queued provider body must not include commitment language; found \(snippet)."
            )
        }

        let forbiddenInternalSnippets = ["trace", "debug", "internal", "agency_pass3", "planner"]
        for snippet in forbiddenInternalSnippets {
            XCTAssertFalse(
                queuedBody.contains(snippet),
                "Queued provider body must not include internal/debug words; found \(snippet)."
            )
        }
    }

    func test_providerCommitmentWithAutonomyOn_noOutboxAndOutcomeNeedsUserApproval() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let data = try await seedProviderRoutineScenario(
            store: harness.store,
            threadID: UUID(uuidString: "00000000-0000-4000-8000-00000000B117")!,
            requestText: "Can you commit to a fixed custom legal contract and schedule slot?"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: data.threadID, now: fixedNow)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: data.threadID))
        XCTAssertEqual(outbox.count, 0)
        let thread = try await harness.store.requireThread(id: data.threadID)
        let outcome = thread.metadata["autonomous_send_outcome"]
        if outcome == nil {
            let detail = try await harness.facade.getThread(threadID: data.threadID)
            let display = try XCTUnwrap(detail.secondHalfDisplay)
            let raw = ExchangeSecondHalfUIAdapter.canonicalSecondHalfActionRaw(for: display)
            XCTAssertNotEqual(
                raw,
                ExchangeSecondHalfAction.autoRespond.rawValue,
                "When no autonomous metadata is recorded, the surfaced plan should not be autoRespond (provider queue only evaluates that lane)."
            )
        } else {
            XCTAssertEqual(outcome, "needsUserApproval")
        }
    }

    // MARK: - For You safeAutoSend vs thread autonomy

    func test_forYouSafeAutoSend_threadAutonomyOff_doesNotQueueOutbound() async throws {
        let localNodeID = "local-for-you-autonomy"
        let cpNodeID = "cp-for-you-autonomy-1"
        let directory = StubForYouDirectoryClientForAutonomyTests(
            matches: [Self.makeForYouDirectoryMatch(counterpartyNodeID: cpNodeID, now: fixedNow)]
        )
        let harness = try makeHarness(
            threadAutonomyMode: .manualOnly,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true,
            directoryClient: directory,
            orchestratorDiscoveryDirectoryClient: directory,
            orchestratorDiscoveryLocalNodeID: localNodeID
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: fixedNow, localNodeID: localNodeID)

        let outboxBefore = try await harness.store.listOutboxItems(filter: .init(limit: 500))
        let result = try await harness.facade.runAutonomousForYouPass(
            localNodeID: localNodeID,
            mode: .safeAutoSend,
            recentContacts: [:],
            limit: 10,
            now: fixedNow,
            useStandingIntentAdapter: false
        )
        let outboxAfter = try await harness.store.listOutboxItems(filter: .init(limit: 500))
        XCTAssertEqual(outboxAfter.count, outboxBefore.count)
        XCTAssertEqual(result.sendOutcome, .disabledByThreadAutonomy)
        XCTAssertNotNil(result.contactedThreadID)
        let thread = try await harness.store.requireThread(id: result.contactedThreadID!)
        XCTAssertEqual(thread.metadata["for_you_send_blocked_reason"], "thread_autonomy")
        XCTAssertEqual(thread.metadata["for_you_thread_autonomy_authority"], "manualOnly")
    }

    func test_forYouSafeAutoSend_threadAutonomyDraftOnly_doesNotQueueOutbound() async throws {
        let localNodeID = "local-for-you-autonomy"
        let cpNodeID = "cp-for-you-autonomy-2"
        let directory = StubForYouDirectoryClientForAutonomyTests(
            matches: [Self.makeForYouDirectoryMatch(counterpartyNodeID: cpNodeID, now: fixedNow)]
        )
        let harness = try makeHarness(
            threadAutonomyMode: .draftOnly,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true,
            directoryClient: directory,
            orchestratorDiscoveryDirectoryClient: directory,
            orchestratorDiscoveryLocalNodeID: localNodeID
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: fixedNow, localNodeID: localNodeID)

        let outboxBefore = try await harness.store.listOutboxItems(filter: .init(limit: 500))
        let result = try await harness.facade.runAutonomousForYouPass(
            localNodeID: localNodeID,
            mode: .safeAutoSend,
            recentContacts: [:],
            limit: 10,
            now: fixedNow,
            useStandingIntentAdapter: false
        )
        let outboxAfter = try await harness.store.listOutboxItems(filter: .init(limit: 500))
        XCTAssertEqual(outboxAfter.count, outboxBefore.count)
        XCTAssertEqual(result.sendOutcome, .disabledByThreadAutonomy)
        XCTAssertNotNil(result.contactedThreadID)
        let thread = try await harness.store.requireThread(id: result.contactedThreadID!)
        XCTAssertEqual(thread.metadata["for_you_send_blocked_reason"], "thread_autonomy")
        XCTAssertEqual(thread.metadata["for_you_thread_autonomy_authority"], "draftOnly")
    }

    func test_forYouSafeAutoSend_threadAutonomyFullAuto_preservesExistingQueueBehavior() async throws {
        let localNodeID = "local-for-you-autonomy"
        let cpNodeID = "cp-for-you-autonomy-3"
        let directory = StubForYouDirectoryClientForAutonomyTests(
            matches: [Self.makeForYouDirectoryMatch(counterpartyNodeID: cpNodeID, now: fixedNow)]
        )
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true,
            directoryClient: directory,
            orchestratorDiscoveryDirectoryClient: directory,
            orchestratorDiscoveryLocalNodeID: localNodeID
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: fixedNow, localNodeID: localNodeID)

        let result = try await harness.facade.runAutonomousForYouPass(
            localNodeID: localNodeID,
            mode: .safeAutoSend,
            recentContacts: [:],
            limit: 10,
            now: fixedNow,
            useStandingIntentAdapter: false
        )
        XCTAssertNotEqual(
            result.sendOutcome,
            .disabledByThreadAutonomy,
            "Full thread autonomy must not hit the For You thread-autonomy gate."
        )
        if let tid = result.contactedThreadID {
            let thread = try await harness.store.requireThread(id: tid)
            XCTAssertNotEqual(thread.metadata["for_you_send_blocked_reason"], "thread_autonomy")
        }
    }

    func test_forYouDiscoveryOff_stillDoesNotQueue() async throws {
        let localNodeID = "local-for-you-autonomy"
        let cpNodeID = "cp-for-you-autonomy-4"
        let directory = StubForYouDirectoryClientForAutonomyTests(
            matches: [Self.makeForYouDirectoryMatch(counterpartyNodeID: cpNodeID, now: fixedNow)]
        )
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true,
            directoryClient: directory
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: fixedNow, localNodeID: localNodeID)

        let outboxBefore = try await harness.store.listOutboxItems(filter: .init(limit: 500))
        let result = try await harness.facade.runAutonomousForYouPass(
            localNodeID: localNodeID,
            mode: .off,
            recentContacts: [:],
            limit: 10,
            now: fixedNow,
            useStandingIntentAdapter: false
        )
        let outboxAfter = try await harness.store.listOutboxItems(filter: .init(limit: 500))
        XCTAssertEqual(outboxAfter.count, outboxBefore.count)
        XCTAssertEqual(result.sendOutcome, .noAction)
        XCTAssertTrue(result.forYouItems.isEmpty)
    }

    // MARK: - For You discoveryFactLines pipeline

    func test_discoverForYou_populatesDiscoveryFactLines_fromProfileSignals() async throws {
        let now = fixedNow
        let localNodeID = "local-for-you-discovery-profile"
        let cpNodeID = "cp-for-you-discovery-profile-1"
        let match = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpNodeID,
            now: now,
            profileSummary: "Early-stage robotics founder",
            openTo: ["VC intros", "pilot customers", "retail partners"],
            interests: ["automation", "hardware startups", "retail operations"],
            activityTags: ["founder", "robotics"],
            regionTags: ["Toronto", "North America"],
            semanticDomains: ["robotics"],
            semanticIntentKinds: ["partnerships"],
            matchedTerms: ["automation"]
        )

        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [match])
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: now, localNodeID: localNodeID)

        let items = try await harness.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        XCTAssertEqual(items.count, 1)
        guard let item = items.first else { return }

        let lines = item.discoveryFactLines
        XCTAssertTrue(lines.contains(where: { $0.contains("About:") && $0.localizedCaseInsensitiveContains("robotics founder") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("Open to:") && $0.localizedCaseInsensitiveContains("VC intros") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("Interests:") && $0.localizedCaseInsensitiveContains("automation") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("Roles:") || $0.contains("Shared themes:") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("Region:") }) || lines.count == 6)
    }

    func test_discoverForYou_includesOfferDescriptorsWithoutOperationalDetails() async throws {
        let now = fixedNow
        let localNodeID = "local-for-you-discovery-offers"
        let cpNodeID = "cp-for-you-discovery-offers-1"
        let offer = Self.makeOffer(
            nodeID: cpNodeID,
            title: "Commercial robotics pilot program",
            category: "Robotics",
            tags: ["automation", "retail", "B2B"],
            now: now
        )
        let match = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpNodeID,
            now: now,
            offers: [offer],
            matchedTerms: ["retail robotics"]
        )

        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [match])
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: now, localNodeID: localNodeID)

        let items = try await harness.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        guard let item = items.first else {
            XCTFail("Expected one For You item.")
            return
        }

        XCTAssertTrue(item.discoveryFactLines.contains(where: { $0.contains("Offers:") && $0.localizedCaseInsensitiveContains("robotics pilot") }))
        XCTAssertTrue(
            item.discoveryFactLines.contains(where: {
                $0.contains("Industries/categories:")
                    && ($0.localizedCaseInsensitiveContains("robotics")
                        || $0.localizedCaseInsensitiveContains("automation")
                        || $0.localizedCaseInsensitiveContains("retail")
                        || $0.localizedCaseInsensitiveContains("b2b"))
            })
        )
        XCTAssertFalse(item.discoveryFactLines.contains(where: { $0.lowercased().contains("price") }))
        XCTAssertFalse(item.discoveryFactLines.contains(where: { $0.lowercased().contains("fulfillment") }))
    }

    func test_discoverForYou_filtersForbiddenTermsFromDiscoveryFactLines() async throws {
        let now = fixedNow
        let localNodeID = "local-for-you-discovery-forbidden"
        let cpNodeID = "cp-for-you-discovery-forbidden-1"
        let forbiddenBlob =
            "Price: $2000 pricing commercial facts fulfillment required buyer inputs retrieval score fit score route requirement access requirement directContactAllowedOnly federationCapable query class standing intent schema state logs delivery approval autonomy"
        let offer = Self.makeOffer(
            nodeID: cpNodeID,
            title: forbiddenBlob,
            category: forbiddenBlob,
            tags: [forbiddenBlob],
            now: now
        )
        let match = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpNodeID,
            now: now,
            profileSummary: forbiddenBlob,
            openTo: [forbiddenBlob],
            interests: [forbiddenBlob],
            activityTags: [forbiddenBlob],
            regionTags: [forbiddenBlob],
            semanticDomains: [forbiddenBlob],
            semanticIntentKinds: [forbiddenBlob],
            offers: [offer],
            matchedTerms: [forbiddenBlob]
        )
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [match])
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: now, localNodeID: localNodeID)

        let items = try await harness.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        guard let item = items.first else {
            XCTFail("Expected one For You item.")
            return
        }

        let joined = item.discoveryFactLines.joined(separator: " ").lowercased()
        let forbiddenNeedles = [
            "price",
            "pricing",
            "commercial facts",
            "fulfillment",
            "required buyer inputs",
            "retrieval score",
            "fit score",
            "route requirement",
            "access requirement",
            "directcontactallowedonly",
            "federationcapable",
            "query class",
            "standing intent",
            "schema",
            "state logs",
            "delivery",
            "approval",
            "autonomy"
        ]
        for needle in forbiddenNeedles {
            XCTAssertFalse(
                joined.contains(needle),
                "Discovery lines must not contain forbidden content: \(needle)"
            )
        }
    }

    func test_discoverForYou_discoveryFactLinesDedupedAndCapped() async throws {
        let now = fixedNow
        let localNodeID = "local-for-you-discovery-caps"
        let cpNodeID = "cp-for-you-discovery-caps-1"
        let offer = Self.makeOffer(
            nodeID: cpNodeID,
            title: "Robotics",
            category: " robotics ",
            tags: ["ROBOTICS", "automation", "automation", "retail", "b2b"],
            now: now
        )
        let match = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpNodeID,
            now: now,
            profileSummary: "Robotics",
            openTo: ["Robotics", " robotics ", "ROBOTICS", "pilots", "partnerships"],
            interests: ["Robotics", "automation", "automation", "hardware", "retail"],
            activityTags: ["Founder", " founder ", "FOUNDER", "robotics"],
            regionTags: ["Toronto", " toronto ", "North America", "Canada"],
            semanticDomains: ["robotics", "robotics", "supply chain"],
            semanticIntentKinds: ["pilots", "Pilots", "partnerships"],
            offers: [offer],
            matchedTerms: ["ROBOTICS", " robotics ", "automation", "supply chain"]
        )

        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [match])
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: now, localNodeID: localNodeID)

        let items = try await harness.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        guard let item = items.first else {
            XCTFail("Expected one For You item.")
            return
        }

        XCTAssertLessThanOrEqual(item.discoveryFactLines.count, 6)
        for line in item.discoveryFactLines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let values = line[line.index(after: colon)...]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            XCTAssertLessThanOrEqual(values.count, 3, "Each discovery line should cap at three values.")
        }
    }

    func test_discoverForYou_emptyProfileAndOffers_yieldsEmptyDiscoveryFactLines() async throws {
        let now = fixedNow
        let localNodeID = "local-for-you-discovery-empty"
        let cpNodeID = "cp-for-you-discovery-empty-1"
        let match = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpNodeID,
            now: now,
            profileSummary: nil,
            openTo: [],
            interests: [],
            activityTags: [],
            regionTags: [],
            semanticDomains: [],
            semanticIntentKinds: [],
            offers: [],
            matchedTerms: []
        )
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [match])
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: now, localNodeID: localNodeID)

        let items = try await harness.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        guard let item = items.first else {
            XCTFail("Expected one For You item.")
            return
        }

        XCTAssertTrue(item.discoveryFactLines.isEmpty)
        let fallbackItem = ExchangeModels.ForYouItem(
            id: item.id,
            displayName: item.displayName,
            headline: item.headline,
            matchReasonSummary: item.matchReasonSummary,
            accessMode: item.accessMode,
            dominantTags: item.dominantTags,
            topOfferTitle: item.topOfferTitle,
            nodeID: item.nodeID,
            publicProfileID: item.publicProfileID,
            acceptingInbound: item.acceptingInbound,
            discoveredAt: item.discoveredAt,
            canAutonomouslyContact: item.canAutonomouslyContact,
            blockedReason: item.blockedReason,
            linkedThreadID: item.linkedThreadID,
            primaryImageURL: item.primaryImageURL,
            publicOfferContactInfo: item.publicOfferContactInfo,
            discoveryMatchedTerms: item.discoveryMatchedTerms,
            discoveryFactLines: [],
            publicFactLines: ["Fallback: public fact line"],
            suggestedBuyerInputHints: item.suggestedBuyerInputHints,
            retrievalFitScore: item.retrievalFitScore,
            discoverySourceLabel: item.discoverySourceLabel
        )
        XCTAssertEqual(fallbackItem.publicFactLines, ["Fallback: public fact line"])
    }

    func test_discoverForYou_mapsForYouItemFieldsAndKeepsPublicFactsSeparate() async throws {
        let now = fixedNow
        let localNodeID = "local-for-you-discovery-mapping"
        let cpNodeID = "cp-for-you-discovery-mapping-1"
        let offer = Self.makeOffer(
            nodeID: cpNodeID,
            title: "Commercial robotics pilot program",
            category: "Robotics",
            tags: ["automation", "retail", "B2B"],
            imageURL: "https://example.com/offer.jpg",
            commercialFacts: .init(
                priceDisplay: "$2,000",
                requiredBuyerInputs: ["site dimensions"]
            ),
            contactInfo: .init(
                email: "robotics@example.com",
                preferredContactMethod: .email,
                serviceAddressOrArea: "Toronto + GTA"
            ),
            now: now
        )
        let match = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpNodeID,
            now: now,
            profileSummary: "Robotics network for retail pilots",
            offers: [offer],
            matchedTerms: ["robotics", "retail pilots"],
            score: 0.82,
            matchReason: "Shared robotics and retail pilot themes",
            profileImageURL: "https://example.com/profile.jpg"
        )
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [match])
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: now, localNodeID: localNodeID)

        let items = try await harness.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        XCTAssertEqual(items.count, 1)
        guard let item = items.first else { return }

        XCTAssertFalse(item.discoveryFactLines.isEmpty)
        XCTAssertFalse(item.publicFactLines.isEmpty, "publicFactLines should remain populated separately.")
        XCTAssertEqual(item.displayName, "Fixture \(cpNodeID)")
        XCTAssertEqual(item.headline, "Roofing services")
        XCTAssertEqual(item.topOfferTitle, "Commercial robotics pilot program")
        XCTAssertEqual(item.nodeID, cpNodeID)
        XCTAssertEqual(item.publicProfileID, "pp-\(cpNodeID)")
        XCTAssertEqual(item.retrievalFitScore ?? 0, 0.82, accuracy: 0.000_1)
        XCTAssertEqual(item.linkedThreadID, nil)
        XCTAssertEqual(
            item.primaryImageURL,
            "https://example.com/profile.jpg",
            "Mixed profile + commercial listing cues should prefer the public profile image."
        )
        XCTAssertEqual(item.publicOfferContactInfo?.email, "robotics@example.com")
        XCTAssertEqual(item.publicOfferContactInfo?.preferredContactMethod, .email)
        XCTAssertTrue(item.dominantTags.contains("robotics"))
    }

    // MARK: - For You primaryImageURL surface awareness

    func test_discoverForYou_primaryImageURL_profileBiasedWhenSocialCuesAndPlainOfferListing() async throws {
        let now = fixedNow
        let localNodeID = "local-for-you-image-profile-bias"
        let cpNodeID = "cp-for-you-image-profile-bias-1"
        let plainOffer = Self.makeOffer(
            nodeID: cpNodeID,
            title: "Weekend photography walks",
            imageURL: "https://example.com/plain-offer.jpg",
            now: now
        )
        let match = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpNodeID,
            now: now,
            profileSummary: "Organizer for casual photo walks downtown.",
            openTo: ["weekend explorers"],
            interests: ["street photography"],
            offers: [plainOffer],
            matchedTerms: ["photography", "meetups"],
            matchReason: "Social hobby clubs networking match",
            profileImageURL: "https://example.com/profile-photo.jpg"
        )
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [match])
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: now, localNodeID: localNodeID)

        let items = try await harness.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        XCTAssertEqual(items.first?.primaryImageURL, "https://example.com/profile-photo.jpg")
    }

    func test_discoverForYou_primaryImageURL_offerPreferredWhenCommercialCuesDominant() async throws {
        let now = fixedNow
        let localNodeID = "local-for-you-image-offer-bias"
        let cpNodeID = "cp-for-you-image-offer-bias-1"
        let commercialOffer = Self.makeOffer(
            nodeID: cpNodeID,
            title: "Managed IT procurement desk",
            category: "Enterprise IT",
            imageURL: "https://example.com/commercial-offer.jpg",
            now: now
        )
        let match = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpNodeID,
            now: now,
            profileSummary: nil,
            openTo: [],
            interests: [],
            activityTags: [],
            regionTags: [],
            semanticDomains: [],
            semanticIntentKinds: [],
            offers: [commercialOffer],
            matchedTerms: [],
            matchReason: "B2B commercial supplier and marketplace fit",
            profileImageURL: "https://example.com/corp-profile.jpg"
        )
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [match])
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: now, localNodeID: localNodeID)

        let items = try await harness.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        XCTAssertEqual(items.first?.primaryImageURL, "https://example.com/commercial-offer.jpg")
    }

    func test_discoverForYou_primaryImageURL_unknownNeutralPrefersProfileFirst() async throws {
        let now = fixedNow
        let localNodeID = "local-for-you-image-unknown-neutral"
        let cpNodeID = "cp-for-you-image-unknown-neutral-1"
        let neutralOffer = Self.makeOffer(
            nodeID: cpNodeID,
            title: "Peer skill swap",
            imageURL: "https://example.com/neutral-offer.jpg",
            now: now
        )
        let match = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpNodeID,
            now: now,
            profileSummary: nil,
            openTo: [],
            interests: [],
            activityTags: [],
            regionTags: [],
            semanticDomains: [],
            semanticIntentKinds: [],
            offers: [neutralOffer],
            matchedTerms: [],
            matchReason: nil,
            profileImageURL: "https://example.com/neutral-profile.jpg"
        )
        let harness = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [match])
        )
        try await Self.seedForYouLocalProfile(store: harness.store, now: now, localNodeID: localNodeID)

        let items = try await harness.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        XCTAssertEqual(items.first?.primaryImageURL, "https://example.com/neutral-profile.jpg")
    }

    func test_discoverForYou_primaryImageURL_fallsBackWhenPreferredImageMissing() async throws {
        let now = fixedNow
        let localNodeID = "local-for-you-image-fallback"
        let cpProfileMissing = "cp-for-you-image-fallback-profile-missing"
        let offerNoImage = Self.makeOffer(
            nodeID: cpProfileMissing,
            title: "Warehouse wholesale pallets",
            category: "Logistics",
            imageURL: nil,
            now: now
        )
        let matchOfferBiased = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpProfileMissing,
            now: now,
            profileSummary: nil,
            openTo: [],
            interests: [],
            activityTags: [],
            regionTags: [],
            semanticDomains: [],
            semanticIntentKinds: [],
            offers: [offerNoImage],
            matchedTerms: [],
            matchReason: "B2B wholesale procurement introduction",
            profileImageURL: "https://example.com/profile-only.jpg"
        )
        let harnessOfferBias = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [matchOfferBiased])
        )
        try await Self.seedForYouLocalProfile(store: harnessOfferBias.store, now: now, localNodeID: localNodeID)
        let offerBiasItems = try await harnessOfferBias.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        XCTAssertEqual(offerBiasItems.first?.primaryImageURL, "https://example.com/profile-only.jpg")

        let cpOfferMissing = "cp-for-you-image-fallback-offer-missing"
        let plainOfferWithImage = Self.makeOffer(
            nodeID: cpOfferMissing,
            title: "Low signal listing",
            imageURL: "https://example.com/offer-fallback.jpg",
            now: now
        )
        let matchProfileBiased = Self.makeForYouDirectoryMatch(
            counterpartyNodeID: cpOfferMissing,
            now: now,
            profileSummary: "Community garden volunteer.",
            interests: ["native plants"],
            offers: [plainOfferWithImage],
            matchedTerms: ["garden"],
            matchReason: "Community volunteer social match",
            profileImageURL: nil
        )
        let harnessProfileBias = try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false,
            directoryClient: StubForYouDirectoryClientForAutonomyTests(matches: [matchProfileBiased])
        )
        try await Self.seedForYouLocalProfile(store: harnessProfileBias.store, now: now, localNodeID: localNodeID)
        let profileBiasItems = try await harnessProfileBias.facade.discoverForYou(
            localNodeID: localNodeID,
            limit: 10,
            now: now,
            useStandingIntentAdapter: false
        )
        XCTAssertEqual(profileBiasItems.first?.primaryImageURL, "https://example.com/offer-fallback.jpg")
    }
}

// MARK: - For You autonomy test doubles

private struct NilMemoryEmbeddingForHarness: MemoryEmbeddingProvider, Sendable {
    func embed(_ text: String) -> [Float]? { nil }
}

private final class StubForYouDirectoryClientForAutonomyTests: ExchangeDirectoryClient, @unchecked Sendable {
    private let matches: [ExchangeDirectoryMatch]

    init(matches: [ExchangeDirectoryMatch]) {
        self.matches = matches
    }

    func search(_ request: ExchangeDirectorySearchRequest) async throws -> ExchangeDirectorySearchResponse {
        _ = request
        return ExchangeDirectorySearchResponse(matches: matches, source: .local, summary: "stub-for-you")
    }

    func publishSellerSurface(
        _ request: ExchangeSellerSurfacePublishRequest
    ) async throws -> ExchangeSellerSurfacePublishResponse {
        throw ExchangeDirectoryClientError.unavailable(reason: "stub")
    }

    func unpublishSellerSurface(
        nodeID: String,
        publicProfileID: String
    ) async throws -> ExchangeSellerSurfaceUnpublishResponse {
        _ = nodeID
        _ = publicProfileID
        throw ExchangeDirectoryClientError.unavailable(reason: "stub")
    }

    func publishRetrievalDocuments(
        _ request: ExchangeRetrievalDocumentPublishRequest
    ) async throws -> ExchangeRetrievalDocumentPublishResponse {
        throw ExchangeDirectoryClientError.unavailable(reason: "stub")
    }
}

// MARK: - Harness

private extension ExchangeFacadeSecondHalfIntegrationTests {
    struct Harness {
        let facade: ExchangeFacade
        let store: ExchangeSQLiteStore
        let federation: TestFederationService
    }

    actor TestFederationService: ExchangeFederationService {
        let store: ExchangeSQLiteStore
        let eligibilityAllowed: Bool
        let queueAllowed: Bool
        private(set) var evaluateEligibilityCalls = 0
        private(set) var queueApprovedOutboundCalls = 0

        init(
            store: ExchangeSQLiteStore,
            eligibilityAllowed: Bool,
            queueAllowed: Bool
        ) {
            self.store = store
            self.eligibilityAllowed = eligibilityAllowed
            self.queueAllowed = queueAllowed
        }

        func callCounts() -> (eligibility: Int, queued: Int) {
            (evaluateEligibilityCalls, queueApprovedOutboundCalls)
        }

        func evaluateSendEligibility(
            thread: ExchangeThread,
            counterparty: ExchangeCounterparty,
            draft: ExchangeMessageDraft
        ) async throws -> ExchangeFederationSendEligibility {
            _ = thread
            _ = counterparty
            _ = draft
            evaluateEligibilityCalls += 1
            return ExchangeFederationSendEligibility(
                isEligible: eligibilityAllowed,
                reason: eligibilityAllowed
                    ? "Eligible in test federation."
                    : "Test federation keeps outbound disabled."
            )
        }

        func queueApprovedOutbound(
            thread: ExchangeThread,
            counterparty: ExchangeCounterparty,
            draft: ExchangeMessageDraft,
            approval: ExchangeApproval,
            disclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
            priority: ExchangeDeliveryState.Priority,
            now: Date
        ) async throws -> ExchangeFederationQueueResult {
            _ = thread
            _ = counterparty
            _ = draft
            _ = approval
            _ = disclosureLevel
            _ = priority
            queueApprovedOutboundCalls += 1
            guard queueAllowed else {
                throw ExchangeFederationError.transportFailed(reason: "Disabled in tests.")
            }
            let outbox = ExchangeOutboxItem(
                createdAt: now,
                updatedAt: now,
                threadID: thread.id,
                draftID: draft.id,
                approvalID: approval.id,
                targetNodeID: counterparty.id,
                envelopeID: "test-envelope-\(thread.id.uuidString)-\(draft.id.uuidString)",
                deliveryState: .init(
                    phase: .queued,
                    priority: priority,
                    queuedAt: now
                ),
                payloadSummary: "Test queue payload"
            )
            try await store.saveOutboxItem(outbox)
            return ExchangeFederationQueueResult(
                outboxItem: outbox,
                auditRecords: []
            )
        }

        func cancelOutbound(
            outboxItemID: ExchangeOutboxItem.ID,
            reason: String?,
            now: Date
        ) async throws -> ExchangeFederationCancellationResult {
            _ = outboxItemID
            _ = reason
            _ = now
            throw ExchangeFederationError.transportFailed(reason: "Disabled in tests.")
        }

        func flushOutbox(now: Date) async throws -> ExchangeFederationFlushResult {
            _ = now
            return ExchangeFederationFlushResult()
        }

        func receiveEnvelope(
            _ envelope: ExchangeRelayEnvelope,
            route: ExchangeRelayRoute?,
            receivedAt: Date
        ) async throws -> ExchangeFederationReceiveResult {
            _ = envelope
            _ = route
            _ = receivedAt
            throw ExchangeFederationError.transportFailed(reason: "Disabled in tests.")
        }

        func reconcileInbox(now: Date) async throws -> ExchangeFederationReconcileResult {
            _ = now
            return ExchangeFederationReconcileResult()
        }

        func recentAudit(
            threadID: ExchangeThread.ID?,
            limit: Int
        ) async throws -> [ExchangeAuditRecord] {
            _ = threadID
            _ = limit
            return []
        }
    }

    func makeHarness() throws -> Harness {
        try makeHarness(
            threadAutonomyMode: .fullWithinBoundaries,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false
        )
    }

    func makeHarness(
        threadAutonomyMode: ExchangeModels.ExchangeThreadAutonomyMode,
        federationEligibilityAllowed: Bool,
        federationQueueAllowed: Bool,
        directoryClient: (any ExchangeDirectoryClient)? = nil,
        orchestratorDiscoveryDirectoryClient: (any ExchangeDirectoryClient)? = nil,
        orchestratorDiscoveryLocalNodeID: String? = nil
    ) throws -> Harness {
        UserDefaults.standard.set(threadAutonomyMode.rawValue, forKey: threadAutonomyModeKey)
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exchange-facade-second-half-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbURL = tmp.appendingPathComponent("db-\(UUID().uuidString).sqlite")

        let store = try ExchangeSQLiteStore(databaseURL: dbURL)
        let intelligence = ExchangeFallbackIntelligenceProvider()
        let policyEngine = ExchangePolicyEngine()

        let discoveryEngine: ExchangeDiscoveryEngine
        if let orchDir = orchestratorDiscoveryDirectoryClient,
           let orchLocalID = orchestratorDiscoveryLocalNodeID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !orchLocalID.isEmpty {
            let capturedLocalNodeID = orchLocalID
            discoveryEngine = ExchangeDiscoveryEngine(
                store: store,
                directoryClient: orchDir,
                localNodeIDProvider: { capturedLocalNodeID },
                embeddingProvider: NilMemoryEmbeddingForHarness()
            )
        } else {
            discoveryEngine = ExchangeDiscoveryEngine()
        }

        let orchestrator = ExchangeOrchestrator(
            store: store,
            interpreter: ExchangeInterpreter(intelligenceProvider: intelligence),
            postureModeler: ExchangePostureModeler(intelligenceProvider: intelligence),
            discoveryService: ExchangeDiscoveryService(
                discoveryEngine: discoveryEngine,
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

        let federation = TestFederationService(
            store: store,
            eligibilityAllowed: federationEligibilityAllowed,
            queueAllowed: federationQueueAllowed
        )
        let facade = ExchangeFacade(
            orchestrator: orchestrator,
            federationService: federation,
            store: store,
            summaryEngine: ExchangeSummaryEngine(),
            sellerSurfaceService: ExchangeDefaultSellerSurfaceService(),
            publicationService: ExchangeDefaultPublicationService(),
            secondHalfFacade: ExchangeSecondHalfFacade(exchangeStore: store),
            intelligenceProvider: intelligence,
            directoryClient: directoryClient
        )

        return Harness(facade: facade, store: store, federation: federation)
    }

    static func seedForYouLocalProfile(
        store: ExchangeSQLiteStore,
        now: Date,
        localNodeID: String
    ) async throws {
        let localCounterpartyID = "\(localNodeID)-self-cp"
        let selfCounterparty = ExchangeCounterparty(
            id: localCounterpartyID,
            createdAt: now,
            updatedAt: now,
            kind: .person,
            displayName: "Local For You",
            source: .relayNetwork,
            identity: .init(nodeID: localNodeID, verification: .unverified)
        )
        try await store.upsertCounterparties([selfCounterparty])
        let profile = ExchangePublicNodeProfile(
            id: "pp-\(localNodeID)",
            nodeID: localNodeID,
            counterpartyID: localCounterpartyID,
            displayName: "Local For You",
            headline: "Looking for roofing help",
            summary: "Need a roofer for inspection.",
            interests: ["roofing", "home"],
            createdAt: now,
            updatedAt: now
        )
        try await store.savePublicProfile(profile)
    }

    static func makeOffer(
        nodeID: String,
        title: String,
        category: String? = nil,
        tags: [String] = [],
        imageURL: String? = nil,
        commercialFacts: ExchangeOffer.CommercialFacts = .empty,
        contactInfo: ExchangeOffer.ContactInfo? = nil,
        now: Date
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: "offer-\(UUID().uuidString)",
            nodeID: nodeID,
            publicProfileID: "pp-\(nodeID)",
            title: title,
            category: category,
            tags: tags,
            status: .active,
            visibility: .publicDiscoverable,
            createdAt: now,
            updatedAt: now,
            primaryImageURL: imageURL,
            commercialFacts: commercialFacts,
            contactInfo: contactInfo
        )
    }

    static func makeForYouDirectoryMatch(
        counterpartyNodeID: String,
        now: Date,
        profileSummary: String? = "We offer roof inspections and repairs.",
        openTo: [String] = ["home inspections"],
        interests: [String] = ["roofing"],
        activityTags: [String] = [],
        regionTags: [String] = [],
        semanticDomains: [String] = [],
        semanticIntentKinds: [String] = [],
        offers: [ExchangeOffer] = [],
        matchedTerms: [String] = ["roofing"],
        score: Double? = nil,
        matchReason: String? = "test fixture",
        profileImageURL: String? = nil
    ) -> ExchangeDirectoryMatch {
        let profile = ExchangePublicNodeProfile(
            id: "pp-\(counterpartyNodeID)",
            nodeID: counterpartyNodeID,
            counterpartyID: counterpartyNodeID,
            displayName: "Fixture \(counterpartyNodeID)",
            headline: "Roofing services",
            summary: profileSummary,
            interests: interests,
            openTo: openTo,
            activityTags: activityTags,
            regionTags: regionTags,
            semantic: .init(
                domains: semanticDomains,
                intentKinds: semanticIntentKinds
            ),
            createdAt: now,
            updatedAt: now,
            primaryImageURL: profileImageURL
        )
        let cp = ExchangeCounterparty(
            id: counterpartyNodeID,
            createdAt: now,
            updatedAt: now,
            kind: .person,
            displayName: profile.displayName ?? counterpartyNodeID,
            source: .relayNetwork,
            identity: .init(nodeID: counterpartyNodeID, verification: .unverified),
            publicProfile: profile
        )
        return ExchangeDirectoryMatch.fromCounterparty(
            cp,
            offers: offers,
            matchReason: matchReason,
            matchedTerms: matchedTerms,
            score: score
        )
    }

    func failureContext(
        harness: Harness,
        threadID: UUID,
        expected: String
    ) async -> String {
        let thread = try? await harness.store.requireThread(id: threadID)
        let detail = try? await harness.facade.getThread(threadID: threadID)
        let drafts = (try? await harness.store.listDrafts(threadID: threadID)) ?? []
        let outbox = (try? await harness.store.listOutboxItems(filter: .init(threadID: threadID))) ?? []
        let approval = try? await harness.store.fetchLatestApproval(threadID: threadID)

        let metadata = thread?.metadata ?? [:]
        let autonomous = metadata
            .filter { $0.key.hasPrefix("autonomous_send") }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")

        let placement = detail?.secondHalfDisplay?.placement.rawValue ?? "nil"
        let action = detail?.secondHalfDisplay?.nextMove?.action ?? "nil"
        let provider = detail?.secondHalfDisplay?.agencyAssessment?.providerAnswerability
        let providerSummary = provider.map {
            "answerability=\($0.answerability.rawValue) groundedFacts=\($0.groundedFacts.count) proposedAnswerEmpty=\(($0.proposedAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) requiresHumanApproval=\($0.requiresHumanApproval)"
        } ?? "nil"
        let readFacade = ExchangeSecondHalfFacade(exchangeStore: harness.store)
        let providerAgency = try? await readFacade.loadSecondHalfAgencySnapshot(
            forThreadID: threadID,
            role: .provider
        )
        let requesterAgency = try? await readFacade.loadSecondHalfAgencySnapshot(
            forThreadID: threadID,
            role: .requester
        )
        let providerAgencySummary = providerAgency?.providerAnswerability.map {
            "status=\($0.statusRaw ?? "nil") grounded=\($0.groundedFacts.count) proposedAnswerPreviewEmpty=\(($0.proposedAnswerPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) requiresHumanApproval=\($0.requiresHumanApproval)"
        } ?? "nil"
        let requesterAgencySummary = requesterAgency?.providerAnswerability.map {
            "status=\($0.statusRaw ?? "nil") grounded=\($0.groundedFacts.count) proposedAnswerPreviewEmpty=\(($0.proposedAnswerPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) requiresHumanApproval=\($0.requiresHumanApproval)"
        } ?? "nil"
        let latestDraftMetadata = drafts.last?.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ") ?? "nil"

        return """
        Expected: \(expected)
        autonomous metadata: \(autonomous)
        display placement/action: \(placement) / \(action)
        provider answerability: \(providerSummary)
        persisted agency provider role: \(providerAgencySummary)
        persisted agency requester role: \(requesterAgencySummary)
        counts: drafts=\(drafts.count) approvals=\(approval == nil ? 0 : 1) outbox=\(outbox.count)
        latest draft metadata: \(latestDraftMetadata)
        outcome=\(metadata["autonomous_send_outcome"] ?? "nil") reason=\(metadata["autonomous_send_reason"] ?? "nil")
        """
    }

    struct SeededIDs {
        let threadID: UUID
    }

    /// Collects persisted draft bodies for queued federation work (fixture `payloadSummary` alone is generic).
    static func combinedOutboundDraftBody(
        outbox: [ExchangeOutboxItem],
        store: ExchangeSQLiteStore
    ) async -> String {
        var parts: [String] = []
        for item in outbox {
            if let draft = try? await store.fetchDraft(id: item.draftID) {
                parts.append(draft.body)
            } else {
                parts.append(item.payloadSummary)
            }
        }
        return parts.joined(separator: "\n").lowercased()
    }

    func makeRequesterOutboundThread(
        threadID: UUID,
        state: ExchangeState,
        intentTitle: String,
        intentObjective: String,
        selectedCounterpartyID: String?,
        selectedPublicProfileID: String?,
        selectedOfferID: String?,
        lastInboundEnvelopeID: String?,
        visibleSummary: String?
    ) -> ExchangeThread {
        ExchangeThread(
            id: threadID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                title: intentTitle,
                objective: intentObjective
            ),
            posture: ExchangePosture(),
            state: state,
            selectedCounterpartyID: selectedCounterpartyID,
            selectedPublicProfileID: selectedPublicProfileID,
            selectedOfferID: selectedOfferID,
            visibleSummary: visibleSummary,
            lastInboundEnvelopeID: lastInboundEnvelopeID
        )
    }

    func seedRequesterOutboundRooferScenario(
        store: ExchangeSQLiteStore,
        threadID: UUID,
        userRequestTurnSummary: String,
        intentTitle: String? = nil,
        intentObjective: String? = nil,
        visibleSummary: String? = nil
    ) async throws -> SeededIDs {
        let title = intentTitle ?? userRequestTurnSummary
        let objective = intentObjective ?? userRequestTurnSummary
        let summary = visibleSummary ?? userRequestTurnSummary

        let publicProfileID = "profile-\(threadID.uuidString)"
        let publicProfile = ExchangePublicNodeProfile(
            id: publicProfileID,
            nodeID: SecondHalfEngineTestFixtures.nodeID,
            displayName: "Aurora Roofing Match",
            summary: "Residential roofing inspections and repairs in Metro East.",
            offers: ["Roofing inspection", "Roof repair"],
            openTo: ["Appraisal and quote requests"],
            createdAt: fixedNow,
            updatedAt: fixedNow
        )

        var offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        offer.publicProfileID = publicProfileID
        offer.title = "Residential roofing inspection visit"

        let counterpartyID = "cp-\(threadID.uuidString)"
        let counterparty = ExchangeCounterparty(
            id: counterpartyID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            kind: .provider,
            displayName: "Aurora Roofing Co",
            source: .manualEntry
        )

        let thread = makeRequesterOutboundThread(
            threadID: threadID,
            state: .matchFound(
                .init(
                    foundAt: fixedNow,
                    candidateCount: 1,
                    summary: "Matched roofing provider for inspection request.",
                    selectedCounterpartyID: counterpartyID,
                    selectedPublicProfileID: publicProfileID,
                    selectedOfferID: offer.id
                )
            ),
            intentTitle: title,
            intentObjective: objective,
            selectedCounterpartyID: counterpartyID,
            selectedPublicProfileID: publicProfileID,
            selectedOfferID: offer.id,
            lastInboundEnvelopeID: nil,
            visibleSummary: summary
        )

        try await store.savePublicProfile(publicProfile)
        try await store.saveOffer(offer)
        try await store.createThread(thread)
        try await store.upsertCounterparties([counterparty])
        try await store.saveMatches([
            ExchangeMatch(
                threadID: threadID,
                counterpartyID: counterpartyID,
                createdAt: fixedNow,
                status: .selected,
                strength: .moderate,
                score: 0.82
            )
        ])
        try await store.appendTurn(
            ExchangeTurn(
                threadID: threadID,
                createdAt: fixedNow,
                actor: .user,
                kind: .requestCaptured,
                summary: userRequestTurnSummary
            )
        )

        return SeededIDs(threadID: threadID)
    }

    func seedNoViableMatchNoSelectionRequesterScenario(
        store: ExchangeSQLiteStore,
        threadID: UUID,
        userRequestTurnSummary: String
    ) async throws -> SeededIDs {
        let thread = makeRequesterOutboundThread(
            threadID: threadID,
            state: .noViableMatch(
                .init(searchedAt: fixedNow, explanation: "No directory matches surfaced.")
            ),
            intentTitle: "Fixture find tutor",
            intentObjective: userRequestTurnSummary,
            selectedCounterpartyID: nil,
            selectedPublicProfileID: nil,
            selectedOfferID: nil,
            lastInboundEnvelopeID: nil,
            visibleSummary: userRequestTurnSummary
        )
        try await store.createThread(thread)
        try await store.appendTurn(
            ExchangeTurn(
                threadID: threadID,
                createdAt: fixedNow,
                actor: .user,
                kind: .requestCaptured,
                summary: userRequestTurnSummary
            )
        )
        return SeededIDs(threadID: threadID)
    }

    func seedRequesterScenario(
        store: ExchangeSQLiteStore,
        threadID: UUID,
        requestText: String
    ) async throws -> SeededIDs {
        let counterparty = makeCounterparty(id: "cp-\(threadID.uuidString)")
        let thread = makeThread(
            threadID: threadID,
            state: .matchFound(
                .init(
                    foundAt: fixedNow,
                    candidateCount: 1,
                    summary: "Found a promising provider.",
                    selectedCounterpartyID: counterparty.id
                )
            ),
            selectedCounterpartyID: counterparty.id,
            selectedOfferID: nil,
            lastInboundEnvelopeID: nil
        )

        try await store.createThread(thread)
        try await store.upsertCounterparties([counterparty])
        try await store.saveMatches([
            ExchangeMatch(
                threadID: threadID,
                counterpartyID: counterparty.id,
                createdAt: fixedNow,
                status: .selected,
                strength: .moderate,
                score: 0.78
            )
        ])
        try await store.appendTurn(
            ExchangeTurn(
                threadID: threadID,
                createdAt: fixedNow,
                actor: .user,
                kind: .requestCaptured,
                summary: requestText
            )
        )
        return SeededIDs(threadID: threadID)
    }

    func seedRequesterNeedsClarificationScenario(
        store: ExchangeSQLiteStore,
        threadID: UUID,
        clarificationQuestion: String
    ) async throws -> SeededIDs {
        let counterparty = makeCounterparty(id: "cp-\(threadID.uuidString)")
        let thread = makeThread(
            threadID: threadID,
            state: .needsClarification(
                .init(question: clarificationQuestion, askedAt: fixedNow, attempts: 1)
            ),
            selectedCounterpartyID: counterparty.id,
            selectedOfferID: nil,
            lastInboundEnvelopeID: nil
        )
        try await store.createThread(thread)
        try await store.upsertCounterparties([counterparty])
        try await store.appendTurn(
            ExchangeTurn(
                threadID: threadID,
                createdAt: fixedNow,
                actor: .secretary,
                kind: .clarificationAsked,
                summary: clarificationQuestion
            )
        )
        return SeededIDs(threadID: threadID)
    }

    func seedRequesterDecisionReadyScenario(
        store: ExchangeSQLiteStore,
        threadID: UUID
    ) async throws -> SeededIDs {
        let counterparty = makeCounterparty(id: "cp-\(threadID.uuidString)")
        let thread = makeThread(
            threadID: threadID,
            state: .draftReady(
                .init(
                    preparedAt: fixedNow,
                    summary: "Facts are complete for requester decision framing."
                )
            ),
            selectedCounterpartyID: counterparty.id,
            selectedOfferID: nil,
            lastInboundEnvelopeID: nil
        )
        try await store.createThread(thread)
        try await store.upsertCounterparties([counterparty])
        try await store.appendTurn(
            ExchangeTurn(
                threadID: threadID,
                createdAt: fixedNow,
                actor: .counterparty,
                kind: .clarificationAnswered,
                summary: "Price is $120. Availability is weekdays. Contact is hello@example.com."
            )
        )
        return SeededIDs(threadID: threadID)
    }

    func seedProviderRoutineScenario(
        store: ExchangeSQLiteStore,
        threadID: UUID,
        requestText: String,
        commercialFacts: ExchangeOffer.CommercialFacts = SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
    ) async throws -> SeededIDs {
        var groundedFacts = commercialFacts
        if groundedFacts.autoAnswerPolicy.canAnswerPricing {
            groundedFacts.autoAnswerPolicy.canAnswerFAQs = true
            groundedFacts.faqs = [
                .init(
                    question: requestText,
                    answer: "Our published home visit rate is $120, service area is Metro East, and availability is weekdays 9-5."
                )
            ]
        }
        let publicProfileID = "profile-\(threadID.uuidString)"
        let publicProfile = ExchangePublicNodeProfile(
            id: publicProfileID,
            nodeID: SecondHalfEngineTestFixtures.nodeID,
            displayName: "Fixture Provider",
            summary: "Published provider profile for deterministic second-half tests.",
            offers: ["Home visit service"],
            openTo: ["Routine pricing and availability inquiries"],
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        var offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: groundedFacts
        )
        offer.publicProfileID = publicProfileID
        let counterparty = makeCounterparty(id: "cp-\(threadID.uuidString)")
        let thread = makeThread(
            threadID: threadID,
            state: .matchFound(
                .init(
                    foundAt: fixedNow,
                    candidateCount: 1,
                    summary: "Inbound provider question requires handling.",
                    selectedCounterpartyID: counterparty.id,
                    selectedOfferID: offer.id
                )
            ),
            selectedCounterpartyID: counterparty.id,
            selectedPublicProfileID: publicProfileID,
            selectedOfferID: offer.id,
            lastInboundEnvelopeID: "inbound-\(threadID.uuidString)"
        )

        try await store.savePublicProfile(publicProfile)
        try await store.saveOffer(offer)
        try await store.createThread(thread)
        try await store.upsertCounterparties([counterparty])
        try await store.appendTurn(
            ExchangeTurn(
                threadID: threadID,
                createdAt: fixedNow,
                actor: .counterparty,
                kind: .requestCaptured,
                summary: requestText
            )
        )

        return SeededIDs(threadID: threadID)
    }

    func seedProviderUnknownFactScenario(
        store: ExchangeSQLiteStore,
        threadID: UUID
    ) async throws {
        let thread = makeThread(
            threadID: threadID,
            state: .needsClarification(
                .init(
                    question: "Need exact certification details and validated scope before replying.",
                    askedAt: fixedNow,
                    attempts: 1
                )
            ),
            selectedCounterpartyID: "unknown-\(threadID.uuidString)",
            selectedOfferID: nil,
            lastInboundEnvelopeID: "inbound-\(threadID.uuidString)",
            visibleSummary: nil
        )
        try await store.createThread(thread)
        try await store.appendTurn(
            ExchangeTurn(
                threadID: threadID,
                createdAt: fixedNow,
                actor: .counterparty,
                kind: .requestCaptured,
                summary: "What is your submarine-certified emergency rate?"
            )
        )
    }

    func makeThread(
        threadID: UUID,
        state: ExchangeState,
        selectedCounterpartyID: String?,
        selectedPublicProfileID: String? = nil,
        selectedOfferID: String?,
        lastInboundEnvelopeID: String?,
        visibleSummary: String? = "Fixture thread summary"
    ) -> ExchangeThread {
        ExchangeThread(
            id: threadID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                title: "Fixture intent",
                objective: "Exercise second-half integration"
            ),
            posture: ExchangePosture(),
            state: state,
            selectedCounterpartyID: selectedCounterpartyID,
            selectedPublicProfileID: selectedPublicProfileID,
            selectedOfferID: selectedOfferID,
            visibleSummary: visibleSummary,
            lastInboundEnvelopeID: lastInboundEnvelopeID
        )
    }

    func makeCounterparty(id: String) -> ExchangeCounterparty {
        ExchangeCounterparty(
            id: id,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            kind: .provider,
            displayName: "Fixture Provider \(id.suffix(6))",
            source: .manualEntry
        )
    }

    // MARK: - Requester inbound provider reply body → second-half facts

    func seedRequesterMatchFoundWithProviderReplyTurn(
        store: ExchangeSQLiteStore,
        threadID: UUID,
        requestText: String,
        providerSummary: String,
        providerDetail: String
    ) async throws -> SeededIDs {
        let counterparty = makeCounterparty(id: "cp-\(threadID.uuidString)")
        let thread = makeThread(
            threadID: threadID,
            state: .matchFound(
                .init(
                    foundAt: fixedNow,
                    candidateCount: 1,
                    summary: "Found a promising provider.",
                    selectedCounterpartyID: counterparty.id
                )
            ),
            selectedCounterpartyID: counterparty.id,
            selectedOfferID: nil,
            lastInboundEnvelopeID: nil,
            visibleSummary: requestText
        )

        try await store.createThread(thread)
        try await store.upsertCounterparties([counterparty])
        try await store.saveMatches([
            ExchangeMatch(
                threadID: threadID,
                counterpartyID: counterparty.id,
                createdAt: fixedNow,
                status: .selected,
                strength: .moderate,
                score: 0.78
            )
        ])
        try await store.appendTurn(
            ExchangeTurn(
                threadID: threadID,
                createdAt: fixedNow,
                actor: .user,
                kind: .requestCaptured,
                summary: requestText
            )
        )
        try await store.appendTurn(
            ExchangeTurn(
                threadID: threadID,
                createdAt: fixedNow,
                actor: .counterparty,
                kind: .replyReceived,
                summary: providerSummary,
                detail: providerDetail
            )
        )
        return SeededIDs(threadID: threadID)
    }

    private func userFacingSecondHalfBlob(
        from display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> String {
        var parts: [String] = [
            display.summary,
            display.subtitle,
            display.title,
            display.postureSummary,
            display.recommendation,
            display.summaryLines.joined(separator: " ")
        ]
        if let decision = display.decision {
            parts.append(decision.summary)
            parts.append(decision.recommendation)
            parts.append(contentsOf: decision.clarifiedFacts)
            parts.append(contentsOf: decision.unresolvedIssues)
        }
        if let review = display.requesterReview {
            parts.append(review.subtitle)
            if let rec = review.recommendation { parts.append(rec) }
            parts.append(contentsOf: review.strengthReasons)
            parts.append(contentsOf: review.missingFacts)
        }
        if let next = display.nextMove {
            parts.append(next.title)
            parts.append(next.rationale)
        }
        parts.append(contentsOf: display.operatingContext.strengthReasons)
        parts.append(contentsOf: display.operatingContext.weaknessReasons)
        parts.append(contentsOf: display.operatingContext.userFacingMissingFacts)
        return parts.joined(separator: " ").lowercased()
    }

    func test_requesterProviderReply_detailEntersSecondHalfClarifiedFacts() async throws {
        let harness = try makeHarness()
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000D301")!
        let providerDetail =
            "I teach piano in Aurora. My rate is $60/hour. I’m available weekday evenings. Lessons can be at my studio or online."
        let data = try await seedRequesterMatchFoundWithProviderReplyTurn(
            store: harness.store,
            threadID: threadID,
            requestText: "Find me a piano teacher in Aurora. Ask about price, availability, and lesson location.",
            providerSummary: "They replied.",
            providerDetail: providerDetail
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let persisted = try await harness.store.requireThread(id: data.threadID)
        let snapshot = try XCTUnwrap(persisted.secondHalf)
        let blob = snapshot.clarifiedFacts.joined(separator: " ").lowercased()
        XCTAssertTrue(blob.contains("provider answer:"), "Expected labeled provider detail in clarifiedFacts, got: \(snapshot.clarifiedFacts)")

        var hits = 0
        if blob.contains("piano") { hits += 1 }
        if blob.contains("aurora") { hits += 1 }
        if blob.contains("$60") || blob.contains("60/hour") { hits += 1 }
        if blob.contains("weekday") || blob.contains("evening") { hits += 1 }
        if blob.contains("studio") || blob.contains("online") { hits += 1 }
        XCTAssertGreaterThanOrEqual(
            hits,
            2,
            "Expected provider reply detail to surface multiple concrete facts in clarifiedFacts. clarifiedFacts=\(snapshot.clarifiedFacts)"
        )
    }

    func test_requesterProviderReply_secondHalfDisplayReflectsProviderFacts_noInternalLeakage() async throws {
        let harness = try makeHarness()
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000D302")!
        let providerDetail =
            "I teach piano in Aurora. My rate is $60/hour. I’m available weekday evenings. Lessons can be at my studio or online."
        let data = try await seedRequesterMatchFoundWithProviderReplyTurn(
            store: harness.store,
            threadID: threadID,
            requestText: "Find me a piano teacher in Aurora.",
            providerSummary: "They replied.",
            providerDetail: providerDetail
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let detail = try await harness.facade.getThread(threadID: data.threadID)
        let display = try XCTUnwrap(detail.secondHalfDisplay)
        let decisionFacts = display.decision?.clarifiedFacts.joined(separator: " ").lowercased() ?? ""
        XCTAssertTrue(
            decisionFacts.contains("provider answer:")
                && (decisionFacts.contains("piano") || decisionFacts.contains("$60") || decisionFacts.contains("aurora")),
            "Expected decision.clarifiedFacts to carry labeled provider body. clarifiedFacts=\(display.decision?.clarifiedFacts ?? [])"
        )

        let blob = userFacingSecondHalfBlob(from: display)
        let mentionsProviderFacts =
            blob.contains("piano") || blob.contains("$60") || blob.contains("60/hour") || blob.contains("aurora")
            || blob.contains("weekday") || blob.contains("studio") || blob.contains("online")
        XCTAssertTrue(
            mentionsProviderFacts,
            "Expected requester-facing copy to reference provider-supplied facts. blobPreview=\(String(blob.prefix(500)))"
        )

        let forbiddenSubstrings = [
            "knownfacts",
            "unresolvedissues",
            "qualificationstatus",
            "pass 2",
            "pass 3",
            "anchoring score",
            "offer row present"
        ]
        for phrase in forbiddenSubstrings {
            XCTAssertFalse(
                blob.contains(phrase),
                "Unexpected internal-style phrase in user-facing second-half blob: \(phrase)"
            )
        }
    }

    /// Provider body only states price; unresolved/missing lists may still repeat broader probes (known gap).
    func test_requesterProviderPartialReply_priceInFacts_missingListMayRemainBroad() async throws {
        let harness = try makeHarness()
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000D303")!
        let data = try await seedRequesterMatchFoundWithProviderReplyTurn(
            store: harness.store,
            threadID: threadID,
            requestText: "Find me a piano teacher in Aurora. Ask about price, availability, and lesson location.",
            providerSummary: "They replied.",
            providerDetail: "I charge $60/hour for piano lessons."
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(
            threadID: data.threadID,
            now: fixedNow
        )

        let persisted = try await harness.store.requireThread(id: data.threadID)
        let snapshot = try XCTUnwrap(persisted.secondHalf)
        let clarifiedBlob = snapshot.clarifiedFacts.joined(separator: " ").lowercased()
        XCTAssertTrue(
            clarifiedBlob.contains("$60") || clarifiedBlob.contains("60/hour"),
            "Expected price from provider detail in clarifiedFacts: \(snapshot.clarifiedFacts)"
        )
        // Architecture note: missingFacts / unresolvedIssues are not reply-diffed yet; do not require emptiness.
        _ = snapshot.missingFacts
    }

    func test_noViableMatch_noAnchoredRecipient_secondHalfMutation_doesNotCreateProviderDraft_orOutbox() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .draftOnly,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false
        )
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000F901")!
        let probe =
            "Find a math tutor near me for tomorrow afternoon. Confirm lesson pricing availability with the tutor."
        try await seedNoViableMatchNoSelectionRequesterScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: probe
        )

        await harness.facade.test_support_runSecondHalfAfterThreadMutation(threadID: threadID, source: "test", now: fixedNow)

        let persisted = try await harness.store.requireThread(id: threadID)
        let sh = try XCTUnwrap(
            persisted.secondHalf,
            "Expected persisted second-half after runSecondHalfAfterThreadMutation."
        )
        XCTAssertEqual(sh.nextMoveActionRaw, ExchangeSecondHalfAction.requestUserInput.rawValue)
        XCTAssertNotEqual(
            sh.currentStateRaw,
            ExchangeSecondHalfState.awaitingProviderClarification.rawValue
        )

        let drafts = try await harness.store.listDrafts(threadID: threadID)
        let secondHalfDrafts = drafts.filter { $0.metadata["second_half_generated"] == "true" }
        XCTAssertEqual(secondHalfDrafts.count, 0)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox.count, 0)

        let rationale = (
            "\(sh.recommendation ?? "") \(sh.nextMoveRationale ?? "") \(sh.decisionSummary ?? "")"
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        XCTAssertTrue(
            rationale.contains("refine")
                || rationale.contains("broaden")
                || rationale.contains("no matching seller")
                || rationale.contains("discovery")
                || rationale.contains("no viable match"),
            "Expected requester refine/no-anchor copy; rationaleBlob=\(rationale.prefix(420))"
        )
        let forbiddenOutboundWait = ["waiting for response", "review and send", "draft ready"]
        for phrase in forbiddenOutboundWait where !phrase.isEmpty {
            XCTAssertFalse(
                rationale.contains(phrase),
                "Unexpected outbound-wait phrasing \(phrase)."
            )
        }
    }

    // MARK: - Weak match recipient anchor hydration

    /// Weak potential match: surfaced `ExchangeMatch` row with a concrete offer, but the thread row has not
    /// yet persisted selected* IDs (common after the no-match draft leakage guardrails).
    private func seedWeakMatchOfferScenario(
        store: ExchangeSQLiteStore,
        threadID: UUID,
        userRequestTurnSummary: String
    ) async throws -> (offerID: String, publicProfileID: String) {
        let counterpartyID = "cp-weak-\(threadID.uuidString)"
        let counterparty = ExchangeCounterparty(
            id: counterpartyID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            kind: .provider,
            displayName: "Seller Financing Realty",
            source: .manualEntry
        )

        let publicProfileID = "profile-weak-\(threadID.uuidString)"

        var offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        offer.title = "VTB eligible listing — Metro East"
        offer.publicProfileID = publicProfileID

        let thread = makeRequesterOutboundThread(
            threadID: threadID,
            state: .matchCandidatesWeak(
                .init(candidateCount: 1, explanation: "Match signal is plausible but incomplete.")
            ),
            intentTitle: "Seller financing / VTB",
            intentObjective: userRequestTurnSummary,
            selectedCounterpartyID: nil,
            selectedPublicProfileID: nil,
            selectedOfferID: nil,
            lastInboundEnvelopeID: nil,
            visibleSummary: userRequestTurnSummary
        )

        let profile = ExchangePublicNodeProfile(
            id: publicProfileID,
            nodeID: SecondHalfEngineTestFixtures.nodeID,
            counterpartyID: counterpartyID,
            displayName: "VTB Realty",
            summary: "Real estate sales",
            createdAt: fixedNow,
            updatedAt: fixedNow
        )

        try await store.createThread(thread)
        try await store.upsertCounterparties([counterparty])
        try await store.savePublicProfile(profile)
        try await store.saveOffer(offer)

        try await store.saveMatches([
            ExchangeMatch(
                threadID: threadID,
                counterpartyID: counterpartyID,
                createdAt: fixedNow,
                scope: .offer,
                publicProfileID: publicProfileID,
                offerID: offer.id,
                matchedOfferIDs: [offer.id],
                status: .candidate,
                strength: .weak,
                score: 0.45
            )
        ])
        try await store.appendTurn(
            ExchangeTurn(
                threadID: threadID,
                createdAt: fixedNow,
                actor: .user,
                kind: .requestCaptured,
                summary: userRequestTurnSummary
            )
        )

        return (offer.id, publicProfileID)
    }

    func test_weakMatchWithoutStoredSelection_persistsAnchorAndPreparesSecondHalfDraft() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .draftOnly,
            federationEligibilityAllowed: false,
            federationQueueAllowed: false
        )
        let threadID = UUID()
        let ids = try await seedWeakMatchOfferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: "Looking for seller financing or VTB terms on an Aurora listing."
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let thread = try await harness.store.requireThread(id: threadID)
        XCTAssertEqual(thread.selectedOfferID, ids.offerID)
        XCTAssertEqual(thread.selectedPublicProfileID, ids.publicProfileID)
        XCTAssertEqual(thread.selectedCounterpartyID, "cp-weak-\(threadID.uuidString)")

        let drafts = try await harness.store.listDrafts(threadID: threadID)
        let shDrafts = drafts.filter { $0.metadata["second_half_generated"] == "true" }
        XCTAssertFalse(shDrafts.isEmpty, "Expected a persisted second-half draft for anchored weak match")

        let body = shDrafts.map(\.body).joined(separator: " ").lowercased()
        for banned in ["anchored snapshot", "published seller surfaces", "throughput", "deterministic", "schema"] {
            XCTAssertFalse(
                body.contains(banned),
                "Draft should not leak internal-only phrasing: \(banned)"
            )
        }

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertTrue(outbox.isEmpty, "draftOnly autonomy must not queue outbound")
    }

    func test_noViableMatch_doesNotHydrateSelectionFromDiscoveryMatchRows() async throws {
        let harness = try makeHarness()
        let threadID = UUID()
        try await seedWeakMatchOfferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: "Exploring seller financing."
        )
        var thread = try await harness.store.requireThread(id: threadID)
        thread.state = .noViableMatch(.init(searchedAt: fixedNow, explanation: "No confident routing yet."))
        try await harness.store.updateThread(thread)

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let reloaded = try await harness.store.requireThread(id: threadID)
        XCTAssertNil(reloaded.selectedOfferID)
        XCTAssertNil(reloaded.selectedPublicProfileID)
        XCTAssertNil(reloaded.selectedCounterpartyID)
    }

    // MARK: - Potential match: draft, transcript, auto-send

    /// Toggle OFF (`manualOnly`): anchor hydrates, persisted external draft, no outbox; transcript shows Draft ready (unsuppressed build).
    func test_potentialMatch_toggleOff_preparesDraftAndTranscriptShowsDraft() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .manualOnly,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID()
        try await seedWeakMatchOfferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: "Need VTB / seller financing clarity on an Aurora property."
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let reloaded = try await harness.store.requireThread(id: threadID)
        XCTAssertNotNil(reloaded.selectedOfferID)
        XCTAssertNotNil(reloaded.selectedCounterpartyID)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox.count, 0)

        let drafts = try await harness.store.listDrafts(threadID: threadID)
        let external = drafts.filter { $0.audience == .externalCounterparty }
        let actionable = external.filter { d in
            d.isActionable || d.status == .awaitingApproval
        }
        XCTAssertFalse(actionable.isEmpty, "Expected persisted actionable external draft")

        let detail = try await harness.facade.getThread(threadID: threadID)
        let rowsRaw = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let draftReadyRows = rowsRaw.filter { $0.title == "Draft ready" }
        XCTAssertEqual(draftReadyRows.count, 1, "Unsuppressed transcript should surface one Draft ready row")
        let draftBody = draftReadyRows.first?.bodyPreview.lowercased() ?? ""
        XCTAssertFalse(draftBody.isEmpty)
        for banned in [
            "published seller surfaces", "anchored snapshot", "throughput", "schema",
            "deterministic", "coordination path", "capacity"
        ] {
            XCTAssertFalse(draftBody.contains(banned), "Transcript draft leak: \(banned)")
        }

        let rowsAsView = ExchangeModels.ThreadTranscriptBuilder.build(
            from: detail,
            secondHalfDisplay: detail.secondHalfDisplay
        )
        let hasDraftInViewModel = rowsAsView.contains { $0.title == "Draft ready" }
        let hasDraftRaw = rowsRaw.contains { $0.title == "Draft ready" }
        if !hasDraftInViewModel, hasDraftRaw {
            let persisted = detail.drafts.contains {
                $0.audience == .externalCounterparty
                    && $0.metadata["second_half_generated"] == "true"
                    && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            XCTAssertTrue(
                persisted || !(detail.secondHalfDisplay?.draft?.bodyPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "When Conversation transcript dedupes Draft ready, draft should still exist in detail"
            )
        }
    }

    /// Safe auto-follow-ups ON + federation allows: queues outbound; transcript shows outbound progress (Sending… or sent), not an open draft.
    func test_potentialMatch_toggleOn_gateAllows_autoSendsAndTranscriptShowsSent() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID()
        try await seedWeakMatchOfferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: "Ask whether seller financing or VTB terms are available; no commitments."
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let outbox1 = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox1.count, 1, "Expected one queued outbound for routineAutoRespond")

        let threadAfter = try await harness.store.requireThread(id: threadID)
        XCTAssertEqual(threadAfter.metadata["autonomous_send_outcome"], "allowed")

        let detail1 = try await harness.facade.getThread(threadID: threadID)
        let rows1 = ExchangeModels.ThreadTranscriptBuilder.build(
            from: detail1,
            secondHalfDisplay: detail1.secondHalfDisplay
        )
        XCTAssertFalse(
            rows1.contains { $0.title == "Draft ready" },
            "Queued/sent outbound should surface Sending… / Sent / Unify sent, not Draft ready"
        )
        XCTAssertTrue(
            rows1.contains { $0.title == "Sending…" || $0.title == "Unify sent" || $0.title == "Sent" }
                || outbox1.contains { $0.deliveryState.phase == .queued },
            "Expected transcript or outbox to reflect outbound work"
        )

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let outbox2 = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox2.count, 1, "Duplicate autonomous pass should not queue a second outbox item")
    }

    /// Autonomy ON but autonomous send blocked (here: `inbound_requires_verified_context_hold` per existing policy).
    func test_potentialMatch_toggleOn_gateDenied_noAutoSend() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID()
        try await seedWeakMatchOfferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: "Inquire about VTB availability."
        )
        var t = try await harness.store.requireThread(id: threadID)
        t.metadata["inbound_requires_verified_context_hold"] = "true"
        try await harness.store.updateThread(t)

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox.count, 0, "Verified-context hold should block autonomous queue")
    }

    func test_potentialMatch_hydration_doesNotOverrideUserLockedSelectedOfferID() async throws {
        let harness = try makeHarness()
        let threadID = UUID()
        _ = try await seedWeakMatchOfferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: "Seller financing question."
        )
        var t = try await harness.store.requireThread(id: threadID)
        t.selectedOfferID = "user-pinned-offer-id"
        try await harness.store.updateThread(t)

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let reloaded = try await harness.store.requireThread(id: threadID)
        XCTAssertEqual(reloaded.selectedOfferID, "user-pinned-offer-id")
    }

    func test_noViableMatch_evenWithDiscoveryRows_noDraftNoTranscriptDraft() async throws {
        let harness = try makeHarness(
            threadAutonomyMode: .routineAutoRespond,
            federationEligibilityAllowed: true,
            federationQueueAllowed: true
        )
        let threadID = UUID()
        try await seedWeakMatchOfferScenario(
            store: harness.store,
            threadID: threadID,
            userRequestTurnSummary: "Exploring financing options."
        )
        var thread = try await harness.store.requireThread(id: threadID)
        thread.state = .noViableMatch(.init(searchedAt: fixedNow, explanation: "No confident routing yet."))
        try await harness.store.updateThread(thread)

        await harness.facade.attemptRequesterSecondHalfAutonomousOutbound(threadID: threadID, now: fixedNow)

        let reloaded = try await harness.store.requireThread(id: threadID)
        XCTAssertNil(reloaded.selectedOfferID)

        let drafts = try await harness.store.listDrafts(threadID: threadID)
        let shExternal = drafts.filter {
            $0.audience == .externalCounterparty && $0.metadata["second_half_generated"] == "true"
        }
        XCTAssertTrue(shExternal.isEmpty, "noViableMatch must not persist second-half external drafts")

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox.count, 0)

        let detail = try await harness.facade.getThread(threadID: threadID)
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertFalse(rows.contains { $0.title == "Draft ready" })
        XCTAssertTrue(rows.contains { $0.title == "You asked" })
    }
}
