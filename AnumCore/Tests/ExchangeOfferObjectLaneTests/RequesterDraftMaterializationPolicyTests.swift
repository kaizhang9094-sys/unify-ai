import Foundation
import Testing
@testable import AnumCore

@Suite("RequesterDraftMaterializationPolicy")
struct RequesterDraftMaterializationPolicyTests {

    @Test("manualOnly automatic second-half skips LLM compose")
    func manualOnlyAutomaticSkipsLLM() {
        let policy = RequesterDraftMaterializationPolicy.evaluate(
            userAuthority: .manualOnly,
            trigger: .automaticSecondHalf,
            boundaryRequiresHumanApproval: false,
            moveNeedsApproval: false
        )
        #expect(policy.decision == .useExistingTemplateOnly)
        #expect(policy.shouldRunLLMCompose == false)
        #expect(policy.canAutoSend == false)
        #expect(policy.shouldPersistVisibleDraft == false)
    }

    @Test("manualOnly user explicit allows LLM for review")
    func manualOnlyUserExplicitAllowsLLM() {
        let policy = RequesterDraftMaterializationPolicy.evaluate(
            userAuthority: .manualOnly,
            trigger: .userExplicit,
            boundaryRequiresHumanApproval: false,
            moveNeedsApproval: false
        )
        #expect(policy.decision == .composeForUserReview)
        #expect(policy.shouldRunLLMCompose == true)
        #expect(policy.canAutoSend == false)
    }

    @Test("draftOnly allows LLM compose for user review")
    func draftOnlyAllowsLLMForReview() {
        let policy = RequesterDraftMaterializationPolicy.evaluate(
            userAuthority: .draftOnly,
            trigger: .automaticSecondHalf,
            boundaryRequiresHumanApproval: false,
            moveNeedsApproval: false
        )
        #expect(policy.decision == .composeForUserReview)
        #expect(policy.shouldRunLLMCompose == true)
        #expect(policy.canAutoSend == false)
        #expect(policy.shouldPersistVisibleDraft == true)
    }

    @Test("routineAutoRespond allows autonomous send compose")
    func routineAutoRespondAllowsCompose() {
        let policy = RequesterDraftMaterializationPolicy.evaluate(
            userAuthority: .routineAutoRespond,
            trigger: .automaticSecondHalf,
            boundaryRequiresHumanApproval: false,
            moveNeedsApproval: false
        )
        #expect(policy.decision == .composeForAutonomousSend)
        #expect(policy.shouldRunLLMCompose == true)
        #expect(policy.canAutoSend == true)
    }

    @Test("boundary approval forces user review compose")
    func boundaryApprovalForcesReview() {
        let policy = RequesterDraftMaterializationPolicy.evaluate(
            userAuthority: .routineAutoRespond,
            trigger: .automaticSecondHalf,
            boundaryRequiresHumanApproval: true,
            moveNeedsApproval: false
        )
        #expect(policy.decision == .composeForUserReview)
        #expect(policy.shouldRunLLMCompose == true)
        #expect(policy.canAutoSend == false)
    }

    @Test("trigger parses user let secretary handle source")
    func triggerParsesUserExplicitSource() {
        let trigger = RequesterDraftMaterializationPolicy.trigger(
            fromSecondHalfSource: "submit.user_let_secretary_handle"
        )
        #expect(trigger == .userExplicit)
    }

    @Test("trigger defaults to automatic second-half")
    func triggerDefaultsAutomatic() {
        let trigger = RequesterDraftMaterializationPolicy.trigger(
            fromSecondHalfSource: "submit.childCoordination"
        )
        #expect(trigger == .automaticSecondHalf)
    }
}
