import XCTest
import AnumCore

/// Inbound provider reception: structured memory, policy gates, escalation triggers,
/// and autonomous-send safety (no LLM / network).
final class ExchangeProviderAnswerabilityEngineTests: XCTestCase {
    private let engine = ExchangeProviderAnswerabilityEngine()

    // MARK: - Routine from memory

    func test_routinePrice_answerableFromStructuredMemory() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "What is your home visit price?",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .answerableFromPublicFacts)
        XCTAssertFalse(result.requiresHumanApproval)
        XCTAssertTrue(result.allowsAutonomousSending)
        XCTAssertTrue(result.proposedAnswer?.contains("$120") == true)
    }

    func test_routineServiceArea_answerableFromStructuredMemory() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "Where do you deliver in metro east?",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .answerableFromPublicFacts)
        XCTAssertTrue(result.proposedAnswer?.contains("Metro East") == true)
        XCTAssertTrue(result.allowsAutonomousSending)
    }

    func test_routineAvailability_answerableFromStructuredMemory() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "What are your weekdays availability windows?",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .answerableFromPublicFacts)
        XCTAssertFalse(result.requiresHumanApproval)
        XCTAssertTrue(result.allowsAutonomousSending)
        XCTAssertTrue(result.proposedAnswer?.lowercased().contains("availability") == true)
    }

    func test_routinePolicyFAQ_answerableFromOfferFAQWhenEnabled() {
        let memory = ExchangeStructuredOperatingMemory.empty
        var facts = SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        facts.autoAnswerPolicy.canAnswerFAQs = true
        facts.faqs = [
            .init(
                question: "What is your cancellation policy?",
                answer: "Cancel free up to 24 hours before the visit."
            )
        ]
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(commercialFacts: facts)
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "What is your cancellation policy?",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .answerableFromPublicFacts)
        XCTAssertFalse(result.requiresHumanApproval)
        XCTAssertTrue(result.allowsAutonomousSending)
        XCTAssertTrue(result.proposedAnswer?.contains("24 hours") == true)
    }

    // MARK: - Unknown / not confidently resolved

    func test_vagueInquiry_notAnswerableWithoutStructuredOverlap() {
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: .empty,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "Tell me more about your philosophy of service.",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .notAnswerable)
        XCTAssertFalse(result.requiresHumanApproval)
        XCTAssertFalse(result.allowsAutonomousSending)
        XCTAssertFalse(result.missingFacts.isEmpty)
    }

    func test_unknownFactInquiry_doesNotAutonomouslyAnswer() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "What is your submarine-certified emergency rate?",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .notAnswerable)
        XCTAssertFalse(result.requiresHumanApproval)
        XCTAssertFalse(result.allowsAutonomousSending)
        XCTAssertFalse(result.missingFacts.isEmpty)
    }

    // MARK: - Human approval paths

    func test_customPricing_requiresProviderApproval() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "Can you send custom pricing for my odd-shaped lot?",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .requiresProviderApproval)
        XCTAssertTrue(result.requiresHumanApproval)
        XCTAssertFalse(result.allowsAutonomousSending)
    }

    func test_pricingPolicyDisabled_blocksPricingAutonomousAnswerEvenWithMemoryPrice() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        var facts = SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        facts.autoAnswerPolicy.canAnswerPricing = false
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(commercialFacts: facts)
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "What is your home visit price?",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .requiresProviderApproval)
        XCTAssertTrue(result.requiresHumanApproval)
        XCTAssertFalse(result.allowsAutonomousSending)
    }

    func test_scheduleSensitiveInquiry_escalatesForSellerReview() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "Please send the final quote and we will issue a deposit today.",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .requiresProviderApproval)
        XCTAssertTrue(result.requiresHumanApproval)
        XCTAssertFalse(result.allowsAutonomousSending)
    }

    func test_availabilityNarrationBlocked_requiresApproval() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let facts = SecondHalfEngineTestFixtures.restrictiveAutoAnswerFacts()
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(commercialFacts: facts)
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "When can we schedule the first visit?",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .requiresProviderApproval)
        XCTAssertTrue(result.requiresHumanApproval)
        XCTAssertFalse(result.allowsAutonomousSending)
    }

    func test_policyNarrationBlocked_requiresApproval() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let facts = SecondHalfEngineTestFixtures.restrictiveAutoAnswerFacts()
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(commercialFacts: facts)
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "Can we get an exception to your cancellation policy?",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .requiresProviderApproval)
        XCTAssertTrue(result.requiresHumanApproval)
        XCTAssertFalse(result.allowsAutonomousSending)
    }

    func test_sensitiveLegalEscalation_requiresApproval() {
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: .empty,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "Our legal counsel needs an NDA before we proceed.",
            prefersDeterministicComposer: true
        )
        XCTAssertEqual(result.answerability, .requiresProviderApproval)
        XCTAssertTrue(result.requiresHumanApproval)
        XCTAssertFalse(result.allowsAutonomousSending)
    }

    /// `prefersDeterministicComposer` is currently unused in production; autonomous send
    /// must still stay off for commitment-sensitive escalations regardless of the flag.
    func test_prefersDeterministicComposerDoesNotEnableAutonomousSendOnEscalation() {
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: .empty,
            offer: offer
        )
        let withComposer = engine.evaluate(
            context: ctx,
            inquiryText: "Bind now on the terms you emailed.",
            prefersDeterministicComposer: true
        )
        let withoutComposer = engine.evaluate(
            context: ctx,
            inquiryText: "Bind now on the terms you emailed.",
            prefersDeterministicComposer: false
        )
        XCTAssertEqual(withComposer.answerability, .requiresProviderApproval)
        XCTAssertEqual(withoutComposer.answerability, .requiresProviderApproval)
        XCTAssertFalse(withComposer.allowsAutonomousSending)
        XCTAssertFalse(withoutComposer.allowsAutonomousSending)
    }

    func test_requesterSideContext_isNotAnswerable() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        var ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        ctx.side = .requester
        let result = engine.evaluate(context: ctx, inquiryText: "What is the price?")
        XCTAssertEqual(result.answerability, .notAnswerable)
        XCTAssertFalse(result.allowsAutonomousSending)
    }

    // MARK: - Escalation trigger regression (NDA / whole-word)

    func test_escalationTrigger_standardVisitPriceDoesNotFalsePositiveOnNDA() {
        let memory = ExchangeStructuredOperatingMemory(
            pricingRules: [
                ExchangeStructuredOperatingMemory.PricingRule(
                    label: "Standard visit",
                    amountDescription: "$120",
                    notes: nil
                )
            ]
        )
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: memory,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "What is your standard visit price?"
        )
        XCTAssertEqual(result.answerability, .answerableFromPublicFacts)
        XCTAssertFalse(result.requiresHumanApproval)
        XCTAssertTrue(result.allowsAutonomousSending)
    }

    func test_escalationTrigger_explicitNDAQuestionEscalates() {
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: .empty,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "Do you require an NDA?"
        )
        XCTAssertEqual(result.answerability, .requiresProviderApproval)
        XCTAssertTrue(result.requiresHumanApproval)
        XCTAssertFalse(result.allowsAutonomousSending)
    }

    func test_escalationTrigger_multiWordLegalPhraseStillEscalates() {
        let offer = SecondHalfEngineTestFixtures.fixtureOffer(
            commercialFacts: SecondHalfEngineTestFixtures.permissiveAutoAnswerFacts()
        )
        let ctx = SecondHalfEngineTestFixtures.providerContext(
            operatingMemory: .empty,
            offer: offer
        )
        let result = engine.evaluate(
            context: ctx,
            inquiryText: "Please involve legal counsel before we finalize anything."
        )
        XCTAssertEqual(result.answerability, .requiresProviderApproval)
        XCTAssertTrue(result.requiresHumanApproval)
        XCTAssertFalse(result.allowsAutonomousSending)
    }
}
