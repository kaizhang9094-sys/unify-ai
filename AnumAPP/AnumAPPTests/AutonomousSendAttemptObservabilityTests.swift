import XCTest
import AnumCore

/// Observability-only: `AutonomousSendAttempt`, audit trace factory, Pass-3 gate wrapper parity.
final class AutonomousSendAttemptObservabilityTests: XCTestCase {

    func test_autonomousSendAttempt_toMetadata_containsStableKeys() {
        let tid = UUID()
        let did = UUID()
        let attempt = AutonomousSendAttempt(
            lane: "lane_x",
            role: "Provider",
            threadID: tid,
            draftID: did,
            selectedOfferID: "offer1",
            selectedPublicProfileID: "prof1",
            lastInboundEnvelopeID: "env1",
            pass3Allowed: true,
            pass3BlockReason: "br",
            pass3Veto: "v",
            policyAllowed: true,
            policyOutcome: "allowed",
            eligibilityAllowed: false,
            eligibilityReason: "not yet",
            permitKind: "agencyAutonomy",
            queued: true,
            skipReason: nil,
            errorSummary: nil
        )
        let m = attempt.toMetadata()
        XCTAssertEqual(m["trace_kind"], "autonomous_send_attempt_v1")
        XCTAssertEqual(m["lane"], "lane_x")
        XCTAssertEqual(m["role"], "Provider")
        XCTAssertEqual(m["thread_id"], tid.uuidString)
        XCTAssertEqual(m["draft_id"], did.uuidString)
        XCTAssertEqual(m["selected_offer_id"], "offer1")
        XCTAssertEqual(m["selected_public_profile_id"], "prof1")
        XCTAssertEqual(m["last_inbound_envelope_id"], "env1")
        XCTAssertEqual(m["pass3_allowed"], "true")
        XCTAssertEqual(m["pass3_block_reason"], "br")
        XCTAssertEqual(m["pass3_veto"], "v")
        XCTAssertEqual(m["policy_allowed"], "true")
        XCTAssertEqual(m["policy_outcome"], "allowed")
        XCTAssertEqual(m["eligibility_allowed"], "false")
        XCTAssertEqual(m["eligibility_reason"], "not yet")
        XCTAssertEqual(m["permit_kind"], "agencyAutonomy")
        XCTAssertEqual(m["queued"], "true")
        XCTAssertNil(m["skip_reason"])
        XCTAssertNil(m["error_summary"])
    }

    func test_exchangeAuditRecord_autonomousSendAttemptTrace_mapsSummaryAndSchema() {
        let attempt = AutonomousSendAttempt(
            lane: "src",
            queued: true,
            skipReason: nil,
            errorSummary: nil
        )
        let row = ExchangeAuditRecord.autonomousSendAttemptTrace(attempt: attempt)
        XCTAssertEqual(row.direction, .localOnly)
        XCTAssertEqual(row.category, .blockedByPolicy)
        XCTAssertEqual(row.actor, .secretary)
        XCTAssertEqual(row.externalEffect, .none)
        XCTAssertEqual(row.summary, "Autonomous send trace — queued")
        XCTAssertEqual(row.metadata["trace_kind"], "autonomous_send_attempt_v1")
        XCTAssertFalse(row.detail?.isEmpty ?? true)
    }

    func test_exchangeAuditRecord_autonomousSendAttemptTrace_failedSummaryWhenError() {
        let attempt = AutonomousSendAttempt(
            lane: "src",
            queued: false,
            skipReason: "x",
            errorSummary: "boom"
        )
        let row = ExchangeAuditRecord.autonomousSendAttemptTrace(attempt: attempt)
        XCTAssertEqual(row.summary, "Autonomous send trace — failed")
    }

    func test_pass3Gate_missingAssessment_matchesBetweenProviderAndRequesterWrappers() {
        let display = Self.fixtureDisplay(
            role: .provider,
            assessment: nil
        )
        let p = ExchangeAgencyPlanner.evaluateAutonomousOutboundGate(display: display)
        let r = ExchangeAgencyPlanner.evaluateRequesterAutonomousOutboundGate(display: display)
        XCTAssertEqual(p.allowed, r.allowed)
        XCTAssertEqual(p.vetoReason, r.vetoReason)
        XCTAssertEqual(p.agencyBlockReason, r.agencyBlockReason)
        XCTAssertEqual(p.usedPublicFactsCount, r.usedPublicFactsCount)
    }

    func test_pass3Gate_allowAutonomousOutbound_stableAcrossWrappers() {
        let decision = ExchangeAgencyDecision(
            recommendedAction: nil,
            autonomyDisposition: .allowAutonomousOutbound,
            requiresUserApproval: false,
            requiresUserInput: false,
            blockReasons: [],
            permitReasons: ["ok"]
        )
        let assessment = ExchangeAgencyAssessment(
            groundedFactLines: ["a", "b"],
            agencyDecision: decision
        )
        let display = Self.fixtureDisplay(role: .provider, assessment: assessment)
        let p = ExchangeAgencyPlanner.evaluateAutonomousOutboundGate(display: display)
        let r = ExchangeAgencyPlanner.evaluateRequesterAutonomousOutboundGate(display: display)
        XCTAssertTrue(p.allowed && r.allowed)
        XCTAssertEqual(p.usedPublicFactsCount, 2)
        XCTAssertEqual(p.usedPublicFactsCount, r.usedPublicFactsCount)
        XCTAssertEqual(p.agencySuggestionKind, "ok")
        XCTAssertEqual(p.agencySuggestionKind, r.agencySuggestionKind)
    }

    func test_pass3Gate_blocked_pathsPreserveLegacySlugPrefixes() {
        let decision = ExchangeAgencyDecision(
            recommendedAction: .askClarification,
            autonomyDisposition: .holdForApproval,
            requiresUserApproval: true,
            requiresUserInput: false,
            blockReasons: ["block_a"],
            permitReasons: []
        )
        let assessment = ExchangeAgencyAssessment(
            groundedFactLines: ["x"],
            agencyDecision: decision
        )
        let display = Self.fixtureDisplay(role: .requester, assessment: assessment)
        let p = ExchangeAgencyPlanner.evaluateAutonomousOutboundGate(display: display)
        let r = ExchangeAgencyPlanner.evaluateRequesterAutonomousOutboundGate(display: display)
        XCTAssertFalse(p.allowed)
        XCTAssertFalse(r.allowed)
        XCTAssertEqual(p.agencyBlockReason, "agency_decision_block_a")
        XCTAssertEqual(r.agencyBlockReason, "agency_requester_decision_block_a")
        XCTAssertTrue(p.vetoReason?.contains("Pass 3:") == true)
        XCTAssertTrue(r.vetoReason?.contains("Pass 3 requester gate:") == true)
    }

    func test_pass3Gate_emptyBlockReasons_useDistinctDefaults() {
        let decision = ExchangeAgencyDecision(
            autonomyDisposition: .holdForApproval,
            requiresUserApproval: true,
            requiresUserInput: false,
            blockReasons: [],
            permitReasons: []
        )
        let assessment = ExchangeAgencyAssessment(agencyDecision: decision)
        let display = Self.fixtureDisplay(role: .provider, assessment: assessment)
        let p = ExchangeAgencyPlanner.evaluateAutonomousOutboundGate(display: display)
        let r = ExchangeAgencyPlanner.evaluateRequesterAutonomousOutboundGate(display: display)
        XCTAssertEqual(p.agencyBlockReason, "agency_decision_agency_no_safe_permit_decision")
        XCTAssertEqual(r.agencyBlockReason, "agency_requester_decision_agency_requester_no_safe_permit")
    }

    // MARK: - Fixtures

    private static func fixtureDisplay(
        role: ExchangeSecondHalfRole,
        assessment: ExchangeAgencyAssessment?
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel {
        ExchangeSecondHalfUIAdapter.DisplayModel(
            threadID: UUID(),
            placement: .activeCoordination,
            title: "Second-half title",
            subtitle: "Fixture subtitle",
            summary: "Second-half summary.",
            postureSummary: "Fixture posture",
            recommendation: "Fixture recommendation",
            stateLabel: "Fixture state",
            roleLabel: "Fixture role",
            hero: ExchangeSecondHalfUIAdapter.Hero(
                eyebrow: "Fixture",
                title: "Hero headline",
                subtitle: "Hero subtitle",
                statusLine: "Fixture status line"
            ),
            status: ExchangeSecondHalfUIAdapter.Status(
                state: "Coordination",
                role: role.displayTitle,
                quality: "Fixture quality",
                readiness: "Fixture readiness",
                isBlocking: false,
                isAutonomous: true,
                isDecisionReady: true,
                isTerminal: false
            ),
            operatingContext: ExchangeSecondHalfUIAdapter.OperatingContextSection(
                role: role.displayTitle,
                postureSummary: "Fixture operating posture",
                readiness: "Ready enough",
                urgency: "Normal",
                trust: "Fixture trust",
                priceSensitivity: "Unknown",
                flexibility: "Moderate"
            ),
            boundary: ExchangeSecondHalfUIAdapter.BoundarySection(
                kind: "coordination",
                reason: "Fixture boundary",
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                allowsAutonomousSending: true,
                externalEffectLine: "Fixture external effect"
            ),
            needsHumanAttention: false,
            canRunAutonomously: true,
            agencyPhase: .unknown,
            agencyPhaseTitle: nil,
            agencyPhaseDetail: nil,
            hasDecisionPacket: true,
            hasProviderReception: false,
            hasRequesterReview: false,
            hasDraft: true,
            isTerminal: false,
            agencyAssessment: assessment
        )
    }
}
