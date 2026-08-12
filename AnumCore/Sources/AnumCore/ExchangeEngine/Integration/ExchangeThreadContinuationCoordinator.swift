import Foundation

/// Thin coordinator that connects inbound interpretation to bounded
/// continuation decisions.
///
/// This layer should not become a second orchestrator.
/// It exists to convert inbound thread events into legible next actions.
public struct ExchangeThreadContinuationCoordinator: Sendable {
    private let expectationEngine: ExchangeExpectationEngine
    private let inboundInterpreter: ExchangeInboundInterpreter
    private let continuationEngine: ExchangeContinuationEngine

    public init(
        expectationEngine: ExchangeExpectationEngine = .init(),
        inboundInterpreter: ExchangeInboundInterpreter = .init(),
        continuationEngine: ExchangeContinuationEngine = .init()
    ) {
        self.expectationEngine = expectationEngine
        self.inboundInterpreter = inboundInterpreter
        self.continuationEngine = continuationEngine
    }

    public func evaluateInbound(
        thread: ExchangeThread,
        summary: String,
        body: String
    ) -> Evaluation {
        let baseExpectation =
            thread.expectation
            ?? expectationEngine.buildExpectation(
                intent: thread.intent,
                posture: thread.posture,
                facets: thread.facets
            )

        let inbound = inboundInterpreter.interpret(
            summary: summary,
            body: body,
            thread: thread,
            expectation: baseExpectation
        )

        let decision = continuationEngine.decideNextAction(
            thread: thread,
            expectation: baseExpectation,
            inbound: inbound
        )

        let updatedExpectation: ExchangeExpectation
        if decision.shouldIncrementAutoReplyBudget {
            updatedExpectation = expectationEngine.recordAutoReplyUsed(baseExpectation)
        } else {
            updatedExpectation = baseExpectation
        }

        return Evaluation(
            expectation: updatedExpectation,
            inbound: inbound,
            decision: decision
        )
    }
}

public extension ExchangeThreadContinuationCoordinator {
    struct Evaluation: Sendable, Hashable {
        public var expectation: ExchangeExpectation
        public var inbound: ExchangeInboundInterpreter.Result
        public var decision: ExchangeContinuationDecision

        public init(
            expectation: ExchangeExpectation,
            inbound: ExchangeInboundInterpreter.Result,
            decision: ExchangeContinuationDecision
        ) {
            self.expectation = expectation
            self.inbound = inbound
            self.decision = decision
        }
    }
}
