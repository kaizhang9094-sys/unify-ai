import Foundation
import AnumCore

/// Shared fixtures for second-half post-match integration tests (coordinator / flow / facade).
enum SecondHalfPostMatchTestSupport {
    static let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000A001")!

    static func routineInquiry() -> ExchangeInboundInquiry {
        ExchangeInboundInquiry(
            inquirySummary: "Pricing check",
            requesterAsk: "What is your home visit price?",
            matchedOfferOrProfileAnchor: "fixture-offer",
            answerabilityStatus: .answerableFromKnownFacts,
            classification: .routine
        )
    }

    static func providerRoutineContext(
        structuredQuery: ExchangeStructuredAnswerEngine.Query?,
        includesLegalCommercialCommitment: Bool = false
    ) -> ExchangeSecondHalfExecutionContext {
        ExchangeSecondHalfExecutionContext(
            threadID: threadID,
            role: .provider,
            currentState: .matchFound,
            operatingMemory: SecondHalfEngineTestFixtures.memoryWithRoutineFacts(),
            knownFacts: [],
            unresolvedIssues: ["Confirm installation window"],
            inquiry: routineInquiry(),
            structuredQuery: structuredQuery,
            includesLegalCommercialCommitment: includesLegalCommercialCommitment,
            counterpartyName: "Requester Co",
            subjectMatter: "Fixture plumbing match",
            clarifiedFacts: []
        )
    }

    static func requesterPostMatchContext(
        unresolvedIssues: [String],
        knownFacts: [String] = [],
        hasFreshProviderAnswer: Bool = false
    ) -> ExchangeSecondHalfExecutionContext {
        ExchangeSecondHalfExecutionContext(
            threadID: threadID,
            role: .requester,
            currentState: .matchFound,
            operatingMemory: .empty,
            knownFacts: knownFacts,
            unresolvedIssues: unresolvedIssues,
            hasFreshProviderAnswer: hasFreshProviderAnswer,
            counterpartyName: "Fixture Provider",
            subjectMatter: "Fixture match follow-up",
            clarifiedFacts: []
        )
    }

    static func providerSnapshot(
        structuredQuery: ExchangeStructuredAnswerEngine.Query?,
        includesLegalCommercialCommitment: Bool = false
    ) -> ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot {
        ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot(
            threadID: threadID,
            role: .provider,
            state: .matchFound,
            unresolvedIssues: ["Confirm installation window"],
            counterpartyName: "Requester Co",
            subjectMatter: "Fixture plumbing match",
            inquiry: routineInquiry(),
            structuredQuery: structuredQuery,
            includesLegalCommercialCommitment: includesLegalCommercialCommitment
        )
    }

    static func requesterPipelineContext(
        userRequest: String,
        unresolvedIssues: [String],
        knownFacts: [String],
        priorQuestionsAsked: [String] = [],
        priorAnswersReceived: [String] = [],
        surfacedCandidateCount: Int = 1,
        hasComparableAlternatives: Bool = false,
        hasFreshProviderAnswer: Bool = false,
        includesLegalCommercialCommitment: Bool = false
    ) -> ExchangeSecondHalfExecutionContext {
        ExchangeSecondHalfExecutionContext(
            threadID: threadID,
            role: .requester,
            currentState: .matchFound,
            operatingMemory: .empty,
            priorQuestionsAsked: priorQuestionsAsked,
            priorAnswersReceived: priorAnswersReceived,
            knownFacts: knownFacts,
            unresolvedIssues: unresolvedIssues,
            surfacedCandidateCount: surfacedCandidateCount,
            hasComparableAlternatives: hasComparableAlternatives,
            hasFreshProviderAnswer: hasFreshProviderAnswer,
            includesLegalCommercialCommitment: includesLegalCommercialCommitment,
            counterpartyName: "Fixture Provider",
            subjectMatter: userRequest,
            requestedItems: [userRequest],
            clarifiedFacts: knownFacts
        )
    }
}
