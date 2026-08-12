import XCTest
@testable import AnumCore

final class ExchangeProviderInboundAssessmentProjectionTests: XCTestCase {

    func testRemovesGroundedReplyTitle() {
        XCTAssertTrue(
            ExchangeProviderInboundAssessmentProjection.isInternalProviderAssessmentLine(
                "Grounded reply (public facts)"
            )
        )
    }

    func testRemovesGroundingPublishedFactsPrefix() {
        let normalized = ExchangeProviderInboundAssessmentProjection.normalizedProviderAssessmentLine(
            "Grounding (published facts): We are open to purchasing a cat."
        )
        XCTAssertEqual(normalized, "We are open to purchasing a cat.")
        XCTAssertTrue(
            ExchangeProviderInboundAssessmentProjection.isProviderPerspectiveLeakLine(normalized)
        )
    }

    func testRoutineAnswerableRationaleIsInternal() {
        XCTAssertTrue(
            ExchangeProviderInboundAssessmentProjection.isInternalProviderAssessmentLine(
                "The inquiry is routine and answerable from known structured facts."
            )
        )
    }

    func testBuyerAskFirstPersonIsAllowed() {
        XCTAssertFalse(
            ExchangeProviderInboundAssessmentProjection.isProviderPerspectiveLeakLine(
                "I'd like to purchase a cat. I'm open to swimming and currently live in Aurora."
            )
        )
    }

    func testProviderPerspectiveLeakRejected() {
        XCTAssertTrue(
            ExchangeProviderInboundAssessmentProjection.isProviderPerspectiveLeakLine(
                "We are open to purchasing a cat."
            )
        )
    }

    func testSafeAssessmentLinesPreferRequesterAskAndDropInternalFields() {
        var display = makeMinimalProviderDisplay()
        display.providerReception = .init(
            title: "New inquiry",
            subtitle: "I'd like to purchase a cat.",
            inquirySummary: "User inquiry: purchase a cat.",
            requesterAsk: "I'd like to purchase a cat. I'm open to swimming and currently live in Aurora.",
            matchedAnchor: "cat offer",
            leadStrength: "promising",
            nextMoveTitle: "Grounded reply (public facts)",
            needsAttention: false,
            isStrongLead: true
        )
        display.plain.missingInfoSummary = "Location: Aurora"
        display.plain.recommendationSummary =
            "The inquiry is routine and answerable from known structured facts.\n\nGrounding (published facts): We are open to purchasing a cat."
        display.plain.followUpReason =
            "The inquiry is routine and answerable from known structured facts."

        let result = ExchangeProviderInboundAssessmentProjection.safeAssessmentLines(from: display)

        XCTAssertEqual(result.lines.filter { $0.contains("Grounded reply") }.count, 0)
        XCTAssertEqual(result.lines.filter { $0.contains("Grounding (published facts)") }.count, 0)
        XCTAssertEqual(result.lines.filter { $0.contains("routine and answerable") }.count, 0)
        XCTAssertEqual(result.lines.filter { $0.contains("We are open to purchasing") }.count, 0)
        XCTAssertEqual(result.lines.filter { $0.contains("I'd like to purchase a cat") }.count, 1)
        XCTAssertTrue(result.lines.contains(where: { $0.lowercased().contains("aurora") }))
    }

    func testRedundantInquirySummaryDroppedWhenSimilarToAsk() {
        var display = makeMinimalProviderDisplay()
        display.providerReception = .init(
            title: "New inquiry",
            subtitle: "I'd like to purchase a cat.",
            inquirySummary: "purchase a cat",
            requesterAsk: "I'd like to purchase a cat.",
            matchedAnchor: nil,
            leadStrength: "promising",
            needsAttention: false,
            isStrongLead: false
        )

        let result = ExchangeProviderInboundAssessmentProjection.safeAssessmentLines(from: display)
        XCTAssertEqual(result.lines.filter { $0.lowercased().contains("purchase a cat") }.count, 1)
    }

    private func makeMinimalProviderDisplay() -> ExchangeSecondHalfUIAdapter.DisplayModel {
        ExchangeSecondHalfUIAdapter.DisplayModel(
            placement: .activeCoordination,
            title: "Inquiry",
            subtitle: "Subtitle",
            summary: "Summary",
            postureSummary: "Posture",
            recommendation: "Recommendation",
            stateLabel: "State",
            roleLabel: ExchangeSecondHalfRole.provider.displayTitle,
            hero: .init(
                eyebrow: "Message for you",
                title: "Inquiry",
                subtitle: "Subtitle",
                statusLine: "In progress"
            ),
            status: .init(
                state: "In progress",
                role: ExchangeSecondHalfRole.provider.displayTitle,
                quality: "Promising",
                readiness: "Ready",
                isBlocking: false,
                isAutonomous: true,
                isDecisionReady: false,
                isTerminal: false
            ),
            operatingContext: .init(
                role: ExchangeSecondHalfRole.provider.displayTitle,
                postureSummary: "Posture",
                readiness: "Ready",
                urgency: "Normal",
                trust: "Normal",
                priceSensitivity: "Normal",
                flexibility: "Normal"
            ),
            boundary: .init(
                kind: "none",
                reason: "",
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                allowsAutonomousSending: false,
                externalEffectLine: ""
            ),
            needsHumanAttention: false,
            canRunAutonomously: true,
            hasDecisionPacket: false,
            hasProviderReception: true,
            hasRequesterReview: false,
            hasDraft: false,
            isTerminal: false
        )
    }
}
