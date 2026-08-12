import XCTest
@testable import AnumCore

final class RequesterOutboundSendSafetyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func scaffoldThread(title: String = "Find Provider") -> ExchangeThread {
        ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .generalDiscovery,
                surfacePreference: .offer,
                title: title,
                objective: title
            ),
            posture: ExchangePosture(privacy: .balanced),
            state: .drafting,
            metadata: [:]
        )
    }

    private func forbiddenOutboundNeedles() -> [String] {
        [
            "close to a decision",
            "find provider",
            "public-surface-aligned",
            "match review",
            "reconcile this concern"
        ]
    }

    private func assertCleanOutboundBody(_ body: String, file: StaticString = #filePath, line: UInt = #line) {
        let lower = body.lowercased()
        for needle in forbiddenOutboundNeedles() {
            XCTAssertFalse(lower.contains(needle), "Body contains forbidden copy: \(needle)", file: file, line: line)
        }
        XCTAssertFalse(body.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":"), file: file, line: line)
    }

    func testSubjectResolverPrefersCapturedRequestOverFindProviderTitle() {
        let thread = scaffoldThread(title: "Find Provider")
        let turns = [
            ExchangeTurn.requestCaptured(
                threadID: thread.id,
                summary: "Find me a vc.",
                createdAt: now
            )
        ]

        let result = RequesterOutboundSubjectResolver.resolve(
            thread: thread,
            turns: turns,
            offer: nil,
            publicProfile: nil,
            counterpartyDisplayName: nil
        )

        XCTAssertEqual(result.source, .requestCaptured)
        XCTAssertTrue(result.usedCapturedRequest)
        XCTAssertTrue(result.label.localizedCaseInsensitiveContains("vc"))
        XCTAssertFalse(result.label.localizedCaseInsensitiveContains("find provider"))
    }

    func testFirstContactFrameDecisionBodyUsesCapturedRequestNotGenericTitle() {
        let composer = ExchangeDraftComposer()
        let body = composer.compose(
            input: .init(
                role: .requester,
                action: .frameDecision,
                priors: .init(),
                style: .default,
                operatingMemory: .empty,
                counterpartyName: "Hansen",
                subjectMatter: "Find Provider",
                isFirstExternalContact: true,
                requestCapturedText: "Find me a VC connected to AI startups.",
                profileDisplayName: "Hansen"
            )
        ).body

        assertCleanOutboundBody(body)
        XCTAssertTrue(body.localizedCaseInsensitiveContains("ai"))
        XCTAssertFalse(body.localizedCaseInsensitiveContains("find provider"))
    }

    func testPass2AugmentDoesNotAppendRecommendedQuestionsToSendableBody() {
        let base = ExchangeDraftComposer.Draft(
            body: "Hi Hansen, I'm looking for a VC connected to AI startups and came across your profile. Are you currently open to hearing from early-stage founders?",
            notes: []
        )
        let assessment = ExchangeAgencyAssessment(
            requesterDecisionNeeds: ExchangeRequesterDecisionNeeds(
                knownDecisionFacts: [],
                missingDecisionFacts: [],
                recommendedQuestions: [
                    "Could you reconcile this concern from the match review: pricing mismatch",
                    "Public-surface-aligned follow-up"
                ],
                decisionReadiness: .needsFacts,
                rationale: "test"
            )
        )

        let merged = ExchangeSecondHalfPass2DraftAugment.merge(
            base: base,
            assessment: assessment,
            role: .requester
        )

        XCTAssertEqual(merged?.body, base.body)
        XCTAssertTrue(merged?.notes.contains(where: { $0.contains("not appended to sendable body") }) == true)
        XCTAssertEqual(assessment.requesterDecisionNeeds?.recommendedQuestions.count, 2)
    }

    func testMatchCautionGapDoesNotEmitExternalProviderQuestion() {
        let thread = scaffoldThread()
        let match = ExchangeMatch(
            threadID: thread.id,
            counterpartyID: "provider-1",
            publicProfileID: "profile-1",
            strength: .strong,
            score: 0.6,
            cautions: [
                ExchangeMatch.Caution(kind: .priceMismatch, summary: "Budget may not align with listing price")
            ]
        )

        let output = ExchangeRequesterIntentGapReducer().reduce(
            input: .init(
                thread: thread,
                operatingMemory: .empty,
                selectedMatch: match
            )
        )
        let gaps = output.gaps

        let cautionGap = gaps.first { $0.source == "matchCaution" }
        XCTAssertNotNil(cautionGap)
        XCTAssertNil(cautionGap?.questionForProvider)
    }

    func testFirstContactComposerProducesCleanVCInquiryBody() {
        let body = RequesterOutboundFirstContactComposer.compose(
            .init(
                greeting: "Hi Hansen,",
                signoff: "Thank you,",
                capturedRequestText: "Find me a VC connected to AI startups.",
                subjectMatter: "Find Provider",
                profileDisplayName: "Hansen"
            )
        )

        assertCleanOutboundBody(body)
        XCTAssertTrue(body.localizedCaseInsensitiveContains("hansen"))
        XCTAssertTrue(body.localizedCaseInsensitiveContains("profile"))
    }
}
