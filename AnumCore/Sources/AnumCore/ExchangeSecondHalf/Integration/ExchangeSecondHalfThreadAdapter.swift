import Foundation

#if DEBUG
@inline(__always)
private func exchSecondHalfThreadAdapterLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeSecondHalfThreadAdapter] \(message())")
}
#else
@inline(__always)
private func exchSecondHalfThreadAdapterLog(_ message: @autoclosure () -> String) {}
#endif

/// Compatibility adapter between the old world and the new second-half subsystem.
///
/// This file intentionally contains the messy boundary. The rest of the new
/// second-half module should not depend on old thread assumptions directly.
public struct ExchangeSecondHalfThreadAdapter: Sendable {
    public init() {}

    /// Neutral snapshot shape for whatever the current/old thread system provides.
    ///
    /// Keep this struct stable and map old thread data into it externally if needed.
    public struct LegacyThreadSnapshot: Codable, Hashable, Sendable {
        public var threadID: UUID
        public var role: ExchangeSecondHalfRole
        public var state: ExchangeSecondHalfState

        public var priorQuestionsAsked: [String]
        public var priorAnswersReceived: [String]
        public var currentConstraints: [String]
        public var priorNonCommitments: [String]

        public var knownFacts: [String]
        public var unresolvedIssues: [String]
        public var surfacedCandidateCount: Int

        public var clarificationRounds: Int
        public var followUpAttempts: Int
        public var autonomousRoundsSoFar: Int

        public var isTimeSensitive: Bool
        public var isPriceSensitive: Bool
        public var hasLowTrustSignals: Bool
        public var hasComparableAlternatives: Bool
        public var hasFreshProviderAnswer: Bool

        public var counterpartyName: String?
        public var subjectMatter: String?
        public var requestedItems: [String]
        public var clarifiedFacts: [String]

        public var inquiry: ExchangeInboundInquiry?
        public var structuredQuery: ExchangeStructuredAnswerEngine.Query?

        public var isCustomPricing: Bool
        public var includesSensitiveDisclosure: Bool
        public var includesScheduleCommitment: Bool
        public var includesLegalCommercialCommitment: Bool
        public var isPolicyException: Bool

        public var lastDecisionFrame: ExchangeDecisionFrame?
        public var latestDelta: ExchangeThreadDelta?
        public var lastKnownStance: ExchangeThreadStance?
        public var lastApprovedPosition: String?
        public var previousRecommendation: String?
        public var customInstructions: String?

        public var latestCounterpartyReplyText: String?
        public var isThreadExplicitlyCompleted: Bool

        public var selectedCounterpartyID: String?
        public var selectedPublicProfileID: String?
        public var selectedOfferID: String?
        public var lastInboundEnvelopeID: String?

        /// Set when compare-first prefetch ran for provider threads; used by `ExchangeSecondHalfProviderFlow`.
        public var providerCompareFirstStructuredPillarBypassPacket: ProviderCompareFirstStructuredPillarBypassPacket?

        /// Requester outbound: durable captured request text for first-contact body composition.
        public var requestCapturedText: String?
        /// Requester outbound: true when no prior external send/reply exists on this thread.
        public var isFirstExternalContact: Bool?

        public init(
            threadID: UUID,
            role: ExchangeSecondHalfRole,
            state: ExchangeSecondHalfState,
            priorQuestionsAsked: [String] = [],
            priorAnswersReceived: [String] = [],
            currentConstraints: [String] = [],
            priorNonCommitments: [String] = [],
            knownFacts: [String] = [],
            unresolvedIssues: [String] = [],
            surfacedCandidateCount: Int = 1,
            clarificationRounds: Int = 0,
            followUpAttempts: Int = 0,
            autonomousRoundsSoFar: Int = 0,
            isTimeSensitive: Bool = false,
            isPriceSensitive: Bool = false,
            hasLowTrustSignals: Bool = false,
            hasComparableAlternatives: Bool = false,
            hasFreshProviderAnswer: Bool = false,
            counterpartyName: String? = nil,
            subjectMatter: String? = nil,
            requestedItems: [String] = [],
            clarifiedFacts: [String] = [],
            inquiry: ExchangeInboundInquiry? = nil,
            structuredQuery: ExchangeStructuredAnswerEngine.Query? = nil,
            isCustomPricing: Bool = false,
            includesSensitiveDisclosure: Bool = false,
            includesScheduleCommitment: Bool = false,
            includesLegalCommercialCommitment: Bool = false,
            isPolicyException: Bool = false,
            lastDecisionFrame: ExchangeDecisionFrame? = nil,
            latestDelta: ExchangeThreadDelta? = nil,
            lastKnownStance: ExchangeThreadStance? = nil,
            lastApprovedPosition: String? = nil,
            previousRecommendation: String? = nil,
            customInstructions: String? = nil,
            latestCounterpartyReplyText: String? = nil,
            isThreadExplicitlyCompleted: Bool = false,
            selectedCounterpartyID: String? = nil,
            selectedPublicProfileID: String? = nil,
            selectedOfferID: String? = nil,
            lastInboundEnvelopeID: String? = nil,
            providerCompareFirstStructuredPillarBypassPacket: ProviderCompareFirstStructuredPillarBypassPacket? = nil,
            requestCapturedText: String? = nil,
            isFirstExternalContact: Bool? = nil
        ) {
            self.threadID = threadID
            self.role = role
            self.state = state
            self.priorQuestionsAsked = priorQuestionsAsked
            self.priorAnswersReceived = priorAnswersReceived
            self.currentConstraints = currentConstraints
            self.priorNonCommitments = priorNonCommitments
            self.knownFacts = knownFacts
            self.unresolvedIssues = unresolvedIssues
            self.surfacedCandidateCount = surfacedCandidateCount
            self.clarificationRounds = clarificationRounds
            self.followUpAttempts = followUpAttempts
            self.autonomousRoundsSoFar = autonomousRoundsSoFar
            self.isTimeSensitive = isTimeSensitive
            self.isPriceSensitive = isPriceSensitive
            self.hasLowTrustSignals = hasLowTrustSignals
            self.hasComparableAlternatives = hasComparableAlternatives
            self.hasFreshProviderAnswer = hasFreshProviderAnswer
            self.counterpartyName = counterpartyName
            self.subjectMatter = subjectMatter
            self.requestedItems = requestedItems
            self.clarifiedFacts = clarifiedFacts
            self.inquiry = inquiry
            self.structuredQuery = structuredQuery
            self.isCustomPricing = isCustomPricing
            self.includesSensitiveDisclosure = includesSensitiveDisclosure
            self.includesScheduleCommitment = includesScheduleCommitment
            self.includesLegalCommercialCommitment = includesLegalCommercialCommitment
            self.isPolicyException = isPolicyException
            self.lastDecisionFrame = lastDecisionFrame
            self.latestDelta = latestDelta
            self.lastKnownStance = lastKnownStance
            self.lastApprovedPosition = lastApprovedPosition
            self.previousRecommendation = previousRecommendation
            self.customInstructions = customInstructions
            self.latestCounterpartyReplyText = latestCounterpartyReplyText
            self.isThreadExplicitlyCompleted = isThreadExplicitlyCompleted
            self.selectedCounterpartyID = selectedCounterpartyID
            self.selectedPublicProfileID = selectedPublicProfileID
            self.selectedOfferID = selectedOfferID
            let trimmedInbound = lastInboundEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastInboundEnvelopeID = (trimmedInbound?.isEmpty == false) ? trimmedInbound : nil
            self.providerCompareFirstStructuredPillarBypassPacket = providerCompareFirstStructuredPillarBypassPacket
            let trimmedCaptured = requestCapturedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.requestCapturedText = (trimmedCaptured?.isEmpty == false) ? trimmedCaptured : nil
            self.isFirstExternalContact = isFirstExternalContact
        }
    }

    public func makeExecutionContext(
        from snapshot: LegacyThreadSnapshot,
        styleProfile: ExchangeSecretaryStyleProfile,
        operatingMemory: ExchangeStructuredOperatingMemory
    ) -> ExchangeSecondHalfExecutionContext {
        exchSecondHalfThreadAdapterLog(
            "makeExecutionContext thread=\(snapshot.threadID.uuidString) state=\(snapshot.state.rawValue) role=\(snapshot.role.rawValue)"
        )

        return ExchangeSecondHalfExecutionContext(
            threadID: snapshot.threadID,
            role: snapshot.role,
            currentState: snapshot.state,
            styleProfile: styleProfile,
            operatingMemory: operatingMemory,
            priorQuestionsAsked: snapshot.priorQuestionsAsked,
            priorAnswersReceived: snapshot.priorAnswersReceived,
            currentConstraints: snapshot.currentConstraints,
            priorNonCommitments: snapshot.priorNonCommitments,
            lastDecisionFrame: snapshot.lastDecisionFrame,
            lastApprovedPosition: snapshot.lastApprovedPosition,
            latestDelta: snapshot.latestDelta,
            lastKnownStance: snapshot.lastKnownStance,
            knownFacts: snapshot.knownFacts,
            unresolvedIssues: snapshot.unresolvedIssues,
            surfacedCandidateCount: snapshot.surfacedCandidateCount,
            hasComparableAlternatives: snapshot.hasComparableAlternatives,
            hasFreshProviderAnswer: snapshot.hasFreshProviderAnswer,
            clarificationRounds: snapshot.clarificationRounds,
            followUpAttempts: snapshot.followUpAttempts,
            autonomousRoundsSoFar: snapshot.autonomousRoundsSoFar,
            isTimeSensitive: snapshot.isTimeSensitive,
            isPriceSensitive: snapshot.isPriceSensitive,
            hasLowTrustSignals: snapshot.hasLowTrustSignals,
            inquiry: snapshot.inquiry,
            structuredQuery: snapshot.structuredQuery,
            isCustomPricing: snapshot.isCustomPricing,
            includesSensitiveDisclosure: snapshot.includesSensitiveDisclosure,
            includesScheduleCommitment: snapshot.includesScheduleCommitment,
            includesLegalCommercialCommitment: snapshot.includesLegalCommercialCommitment,
            isPolicyException: snapshot.isPolicyException,
            selectedCounterpartyID: snapshot.selectedCounterpartyID,
            selectedPublicProfileID: snapshot.selectedPublicProfileID,
            selectedOfferID: snapshot.selectedOfferID,
            lastInboundEnvelopeID: snapshot.lastInboundEnvelopeID,
            counterpartyName: snapshot.counterpartyName,
            subjectMatter: snapshot.subjectMatter,
            requestedItems: snapshot.requestedItems,
            clarifiedFacts: snapshot.clarifiedFacts,
            customInstructions: snapshot.customInstructions,
            previousRecommendation: snapshot.previousRecommendation,
            latestCounterpartyReplyText: snapshot.latestCounterpartyReplyText,
            isThreadExplicitlyCompleted: snapshot.isThreadExplicitlyCompleted,
            providerCompareFirstStructuredPillarBypassPacket: snapshot.providerCompareFirstStructuredPillarBypassPacket,
            requestCapturedText: snapshot.requestCapturedText,
            isFirstExternalContact: snapshot.isFirstExternalContact ?? false
        )
    }
}
