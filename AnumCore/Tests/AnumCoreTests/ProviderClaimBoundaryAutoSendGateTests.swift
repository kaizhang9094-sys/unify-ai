import XCTest
@testable import AnumCore

final class ProviderClaimBoundaryAutoSendGateTests: XCTestCase {

    private func passResult() -> ProviderClaimBoundaryValidationResult {
        .pass
    }

    private func blockResult() -> ProviderClaimBoundaryValidationResult {
        ProviderClaimBoundaryValidationResult(
            isValid: false,
            severity: .blockAutoSend,
            reasons: [.init(code: "discount_affirmative", message: "discount")],
            suggestedAction: .useFallback
        )
    }

    private func providerInput(
        existingCompareFirstAllowed: Bool,
        claimBoundaryBlocked: Bool
    ) -> ExchangeAutonomousSendPolicy.ProviderInput {
        let existing = existingCompareFirstAllowed
        let claimAllowed = !claimBoundaryBlocked
        return ExchangeAutonomousSendPolicy.ProviderInput(
            userAuthority: .fullWithinBoundaries,
            actionRaw: ExchangeSecondHalfAction.autoRespond.rawValue,
            canRunAutonomously: true,
            needsHumanAttention: false,
            boundaryRequiresApproval: false,
            pass3GateAllowed: true,
            hasVerifiedContextHold: false,
            hasCounterparty: true,
            hasDraft: true,
            isDuplicate: false,
            hasSelectedOfferAnchor: true,
            hasSelectedPublicProfileAnchor: false,
            providerAnswerability: nil,
            canonicalCompareFirstDirectGroundedSend: existing && claimAllowed,
            compareFirstDirectClaimBoundaryBlocked: existing && claimBoundaryBlocked
        )
    }

    func testClaimBoundaryAllowsAutoSend_nilPreservesTrue() {
        XCTAssertTrue(ProviderClaimBoundaryValidator.claimBoundaryAllowsAutoSend(nil))
    }

    func testValidCompareFirstPriceAnswer_keepsExistingAutoSendAllowed() {
        XCTAssertTrue(ProviderClaimBoundaryValidator.claimBoundaryAllowsAutoSend(passResult()))
        let decision = ExchangeAutonomousSendPolicy.evaluateProviderAutoResponse(
            providerInput(existingCompareFirstAllowed: true, claimBoundaryBlocked: false)
        )
        XCTAssertTrue(decision.allowed)
    }

    func testInvalidDiscountAnswer_blocksOnlyThisAutoSend() {
        XCTAssertFalse(ProviderClaimBoundaryValidator.claimBoundaryAllowsAutoSend(blockResult()))
        let decision = ExchangeAutonomousSendPolicy.evaluateProviderAutoResponse(
            providerInput(existingCompareFirstAllowed: true, claimBoundaryBlocked: true)
        )
        XCTAssertFalse(decision.allowed)
        if case .needsUserApproval = decision.outcome {
        } else {
            XCTFail("expected needsUserApproval, got \(decision.outcome)")
        }
    }

    func testInvalidCredentialAnswer_blocksOnlyThisAutoSend() {
        let result = ProviderClaimBoundaryValidationResult(
            isValid: false,
            severity: .blockAutoSend,
            reasons: [.init(code: "credential_licensed", message: "licensed")],
            suggestedAction: .useFallback
        )
        XCTAssertFalse(ProviderClaimBoundaryValidator.claimBoundaryAllowsAutoSend(result))
        let decision = ExchangeAutonomousSendPolicy.evaluateProviderAutoResponse(
            providerInput(existingCompareFirstAllowed: true, claimBoundaryBlocked: true)
        )
        XCTAssertFalse(decision.allowed)
    }

    func testCaveatedMissingCredential_keepsExistingAutoSendAllowed() {
        let result = ProviderClaimBoundaryValidationResult(
            isValid: true,
            severity: .pass,
            reasons: [],
            suggestedAction: .allow
        )
        XCTAssertTrue(ProviderClaimBoundaryValidator.claimBoundaryAllowsAutoSend(result))
        let decision = ExchangeAutonomousSendPolicy.evaluateProviderAutoResponse(
            providerInput(existingCompareFirstAllowed: true, claimBoundaryBlocked: false)
        )
        XCTAssertTrue(decision.allowed)
    }

    func testExistingGateFalse_remainsFalseEvenIfValidatorPasses() {
        let decision = ExchangeAutonomousSendPolicy.evaluateProviderAutoResponse(
            providerInput(existingCompareFirstAllowed: false, claimBoundaryBlocked: false)
        )
        XCTAssertFalse(decision.allowed)
    }

    func testNonCompareFirstPath_notAffectedByClaimBoundaryBlockFlag() {
        let decision = ExchangeAutonomousSendPolicy.evaluateProviderAutoResponse(
            ExchangeAutonomousSendPolicy.ProviderInput(
                userAuthority: .fullWithinBoundaries,
                actionRaw: ExchangeSecondHalfAction.autoRespond.rawValue,
                canRunAutonomously: true,
                needsHumanAttention: false,
                boundaryRequiresApproval: false,
                pass3GateAllowed: true,
                hasVerifiedContextHold: false,
                hasCounterparty: true,
                hasDraft: true,
                isDuplicate: false,
                hasSelectedOfferAnchor: true,
                hasSelectedPublicProfileAnchor: false,
                providerAnswerability: ExchangeProviderAnswerability(
                    answerability: .answerableFromPublicFacts,
                    knownFactsUsed: ["Service call $89"],
                    groundedFacts: [
                        ExchangeProviderGroundedFact(
                            text: "Service call $89",
                            source: .offer,
                            field: "price"
                        )
                    ],
                    missingFacts: [],
                    proposedAnswer: "Service call $89",
                    requiresHumanApproval: false,
                    allowsAutonomousDrafting: true,
                    allowsAutonomousSending: true,
                    boundaryReason: ""
                ),
                canonicalCompareFirstDirectGroundedSend: false,
                compareFirstDirectClaimBoundaryBlocked: false
            )
        )
        XCTAssertTrue(decision.allowed)
    }

    func testFutureValidDraftNotBlockedByPriorInvalidDraftMetadata() {
        var invalidDraft = ExchangeMessageDraft(
            threadID: UUID(),
            kind: .other,
            audience: .externalCounterparty,
            body: "Yes, we can offer a discount.",
            posture: ExchangePosture()
        )
        ProviderClaimBoundaryValidator.attachValidationMetadata(
            to: &invalidDraft.metadata,
            result: blockResult()
        )
        XCTAssertEqual(invalidDraft.metadata["claim_boundary_auto_send_blocked"], "true")

        var validDraft = ExchangeMessageDraft(
            threadID: UUID(),
            kind: .other,
            audience: .externalCounterparty,
            body: "Published pricing is a $89 service call.",
            posture: ExchangePosture()
        )
        ProviderClaimBoundaryValidator.attachValidationMetadata(
            to: &validDraft.metadata,
            result: passResult()
        )
        XCTAssertEqual(validDraft.metadata["claim_boundary_auto_send_blocked"], "false")

        let invalidCached = ProviderClaimBoundaryValidator.validationResultFromDraftMetadata(invalidDraft.metadata)
        let validCached = ProviderClaimBoundaryValidator.validationResultFromDraftMetadata(validDraft.metadata)
        XCTAssertFalse(ProviderClaimBoundaryValidator.claimBoundaryAllowsAutoSend(invalidCached))
        XCTAssertTrue(ProviderClaimBoundaryValidator.claimBoundaryAllowsAutoSend(validCached))
    }
}
