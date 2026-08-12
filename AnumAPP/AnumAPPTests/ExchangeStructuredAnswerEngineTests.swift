import XCTest
import AnumCore

/// Pure `ExchangeStructuredAnswerEngine` coverage: routine facts from operating memory,
/// and conservative nil when nothing matches (no invention).
final class ExchangeStructuredAnswerEngineTests: XCTestCase {
    private let engine = ExchangeStructuredAnswerEngine()

    // MARK: - Routine answers

    func test_pricing_returnsStructuredLines() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let q = ExchangeStructuredAnswerEngine.Query(
            rawText: "What is the home visit rate?",
            kind: .pricing
        )
        let answer = engine.answer(query: q, memory: memory)
        XCTAssertNotNil(answer)
        XCTAssertTrue(answer?.text.contains("$120") == true)
        XCTAssertTrue(answer?.sourcedFacts.contains(where: { $0.contains("Home visit") }) == true)
    }

    func test_availability_returnsWindowsOrCapacity() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let q = ExchangeStructuredAnswerEngine.Query(
            rawText: "Are you open on weekdays?",
            kind: .availability
        )
        let answer = engine.answer(query: q, memory: memory)
        XCTAssertNotNil(answer)
        XCTAssertTrue(answer?.text.contains("Weekdays") == true)
    }

    func test_serviceArea_returnsCoverage() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let q = ExchangeStructuredAnswerEngine.Query(
            rawText: "Do you cover metro east?",
            kind: .serviceArea
        )
        let answer = engine.answer(query: q, memory: memory)
        XCTAssertNotNil(answer)
        XCTAssertTrue(answer?.text.contains("Metro East") == true)
    }

    func test_standardPolicy_returnsMatchingPolicy() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let q = ExchangeStructuredAnswerEngine.Query(
            rawText: "What is your cancellation policy?",
            kind: .standardPolicy
        )
        let answer = engine.answer(query: q, memory: memory)
        XCTAssertNotNil(answer)
        XCTAssertTrue(answer?.text.contains("Cancellation") == true)
        XCTAssertTrue(answer?.text.contains("24 hours") == true)
    }

    func test_generalQuery_returnsAvailabilityWhenPromptAsksWhen() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let q = ExchangeStructuredAnswerEngine.Query(
            rawText: "weekdays availability",
            kind: .general
        )
        let answer = engine.answer(query: q, memory: memory)
        XCTAssertNotNil(answer)
        XCTAssertTrue(answer?.text.contains("Weekdays") == true)
        XCTAssertFalse(answer?.sourcedFacts.isEmpty ?? true)
    }

    func test_generalQuery_returnsCoverageWhenPromptAsksWhere() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let q = ExchangeStructuredAnswerEngine.Query(
            rawText: "metro east service area",
            kind: .general
        )
        let answer = engine.answer(query: q, memory: memory)
        XCTAssertNotNil(answer)
        XCTAssertTrue(answer?.text.contains("Coverage/service area") == true)
        XCTAssertTrue(answer?.sourcedFacts.contains("Metro East") == true)
    }

    /// `memory.exclusions` is not consulted by the structured answer engine today;
    /// queries must not synthesize text from exclusions alone.
    func test_exclusionsOnly_doesNotInventAnswer() {
        let memory = ExchangeStructuredOperatingMemory(
            exclusions: ["No hazardous materials", "No weekend emergency calls"]
        )
        let q = ExchangeStructuredAnswerEngine.Query(
            rawText: "What are your exclusions?",
            kind: .general
        )
        XCTAssertNil(engine.answer(query: q, memory: memory))
    }

    // MARK: - Missing memory

    func test_emptyMemory_pricingReturnsNil() {
        let q = ExchangeStructuredAnswerEngine.Query(rawText: "price", kind: .pricing)
        XCTAssertNil(engine.answer(query: q, memory: .empty))
    }

    func test_emptyMemory_availabilityReturnsNil() {
        let q = ExchangeStructuredAnswerEngine.Query(rawText: "availability", kind: .availability)
        XCTAssertNil(engine.answer(query: q, memory: .empty))
    }

    func test_emptyMemory_serviceAreaReturnsNil() {
        let q = ExchangeStructuredAnswerEngine.Query(rawText: "where", kind: .serviceArea)
        XCTAssertNil(engine.answer(query: q, memory: .empty))
    }

    func test_emptyMemory_policyReturnsNil() {
        let q = ExchangeStructuredAnswerEngine.Query(rawText: "cancel", kind: .standardPolicy)
        XCTAssertNil(engine.answer(query: q, memory: .empty))
    }

    func test_noMatchingPolicyTitle_returnsNil() {
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let q = ExchangeStructuredAnswerEngine.Query(
            rawText: "warranty",
            kind: .standardPolicy
        )
        XCTAssertNil(engine.answer(query: q, memory: memory))
    }
}
