import Foundation

/// Compare-first prefetch diagnostics + eligibility for skipping structured-pillar downgrade in provider flow.
///
/// Built in `ExchangeFacade` when compare-first runs; `isEligible` reflects governed compare + snapshot safety gates.
public struct ProviderCompareFirstStructuredPillarBypassPacket: Codable, Hashable, Sendable {
    public var isEligible: Bool
    public var compareNormalizedAction: String
    public var recommendedDisposition: String?
    public var answerableFromOffer: Bool
    public var missingFactsCount: Int
    public var needsProviderInput: Bool
    public var canSendWithinConsent: Bool?
    public var requiresBoundaryApproval: Bool?
    public var hasCompareGroundedDraft: Bool

    public init(
        isEligible: Bool,
        compareNormalizedAction: String,
        recommendedDisposition: String?,
        answerableFromOffer: Bool,
        missingFactsCount: Int,
        needsProviderInput: Bool,
        canSendWithinConsent: Bool?,
        requiresBoundaryApproval: Bool?,
        hasCompareGroundedDraft: Bool
    ) {
        self.isEligible = isEligible
        self.compareNormalizedAction = compareNormalizedAction
        self.recommendedDisposition = recommendedDisposition
        self.answerableFromOffer = answerableFromOffer
        self.missingFactsCount = missingFactsCount
        self.needsProviderInput = needsProviderInput
        self.canSendWithinConsent = canSendWithinConsent
        self.requiresBoundaryApproval = requiresBoundaryApproval
        self.hasCompareGroundedDraft = hasCompareGroundedDraft
    }
}

/// Shared execution packet for the second-half subsystem.
///
/// This avoids giant argument lists and keeps requester/provider flows working
/// from the same canonical context object.
public struct ExchangeSecondHalfExecutionContext: Sendable {
    public var threadID: UUID
    public var role: ExchangeSecondHalfRole
    public var currentState: ExchangeSecondHalfState

    public var styleProfile: ExchangeSecretaryStyleProfile
    public var operatingMemory: ExchangeStructuredOperatingMemory

    /// Raw prior inputs used to build compact thread priors.
    public var priorQuestionsAsked: [String]
    public var priorAnswersReceived: [String]
    public var currentConstraints: [String]
    public var priorNonCommitments: [String]
    public var lastDecisionFrame: ExchangeDecisionFrame?
    public var lastApprovedPosition: String?
    public var latestDelta: ExchangeThreadDelta?
    public var lastKnownStance: ExchangeThreadStance?

    /// Current thread state inputs.
    public var knownFacts: [String]
    public var unresolvedIssues: [String]
    public var surfacedCandidateCount: Int
    public var hasComparableAlternatives: Bool
    public var hasFreshProviderAnswer: Bool

    /// Cheap thread heuristics.
    public var clarificationRounds: Int
    public var followUpAttempts: Int
    public var autonomousRoundsSoFar: Int
    public var isTimeSensitive: Bool
    public var isPriceSensitive: Bool
    public var hasLowTrustSignals: Bool

    /// Query/inquiry inputs.
    public var inquiry: ExchangeInboundInquiry?
    public var structuredQuery: ExchangeStructuredAnswerEngine.Query?

    /// Boundary hint inputs.
    public var isCustomPricing: Bool
    public var includesSensitiveDisclosure: Bool
    public var includesScheduleCommitment: Bool
    public var includesLegalCommercialCommitment: Bool
    public var isPolicyException: Bool

    /// Durable anchors for outbound provider clarification (mirror `ExchangeThread` selection fields).
    public var selectedCounterpartyID: String?
    public var selectedPublicProfileID: String?
    public var selectedOfferID: String?
    /// Federation/intake routing — present when an inbound provider envelope exists.
    public var lastInboundEnvelopeID: String?

    /// Draft inputs.
    public var counterpartyName: String?
    public var subjectMatter: String?
    public var requestedItems: [String]
    public var clarifiedFacts: [String]
    public var customInstructions: String?
    public var previousRecommendation: String?

    /// Latest counterparty `replyReceived` body (detail preferred), for deterministic pause resolution.
    public var latestCounterpartyReplyText: String?

    /// `ExchangeThread` is explicitly resolved/completed (not inferred from reply text).
    public var isThreadExplicitlyCompleted: Bool

    /// When non-nil, compare-first prefetch ran; see `isEligible` for structured-pillar bypass in provider flow.
    public var providerCompareFirstStructuredPillarBypassPacket: ProviderCompareFirstStructuredPillarBypassPacket?

    /// Requester outbound: captured request text for first-contact body composition.
    public var requestCapturedText: String?
    /// Requester outbound: true when no prior external send/reply exists on this thread.
    public var isFirstExternalContact: Bool

    public init(
        threadID: UUID = UUID(),
        role: ExchangeSecondHalfRole,
        currentState: ExchangeSecondHalfState,
        styleProfile: ExchangeSecretaryStyleProfile = .default,
        operatingMemory: ExchangeStructuredOperatingMemory = .empty,
        priorQuestionsAsked: [String] = [],
        priorAnswersReceived: [String] = [],
        currentConstraints: [String] = [],
        priorNonCommitments: [String] = [],
        lastDecisionFrame: ExchangeDecisionFrame? = nil,
        lastApprovedPosition: String? = nil,
        latestDelta: ExchangeThreadDelta? = nil,
        lastKnownStance: ExchangeThreadStance? = nil,
        knownFacts: [String] = [],
        unresolvedIssues: [String] = [],
        surfacedCandidateCount: Int = 1,
        hasComparableAlternatives: Bool = false,
        hasFreshProviderAnswer: Bool = false,
        clarificationRounds: Int = 0,
        followUpAttempts: Int = 0,
        autonomousRoundsSoFar: Int = 0,
        isTimeSensitive: Bool = false,
        isPriceSensitive: Bool = false,
        hasLowTrustSignals: Bool = false,
        inquiry: ExchangeInboundInquiry? = nil,
        structuredQuery: ExchangeStructuredAnswerEngine.Query? = nil,
        isCustomPricing: Bool = false,
        includesSensitiveDisclosure: Bool = false,
        includesScheduleCommitment: Bool = false,
        includesLegalCommercialCommitment: Bool = false,
        isPolicyException: Bool = false,
        selectedCounterpartyID: String? = nil,
        selectedPublicProfileID: String? = nil,
        selectedOfferID: String? = nil,
        lastInboundEnvelopeID: String? = nil,
        counterpartyName: String? = nil,
        subjectMatter: String? = nil,
        requestedItems: [String] = [],
        clarifiedFacts: [String] = [],
        customInstructions: String? = nil,
        previousRecommendation: String? = nil,
        latestCounterpartyReplyText: String? = nil,
        isThreadExplicitlyCompleted: Bool = false,
        providerCompareFirstStructuredPillarBypassPacket: ProviderCompareFirstStructuredPillarBypassPacket? = nil,
        requestCapturedText: String? = nil,
        isFirstExternalContact: Bool = false
    ) {
        self.threadID = threadID
        self.role = role
        self.currentState = currentState
        self.styleProfile = styleProfile
        self.operatingMemory = operatingMemory
        self.priorQuestionsAsked = priorQuestionsAsked
        self.priorAnswersReceived = priorAnswersReceived
        self.currentConstraints = currentConstraints
        self.priorNonCommitments = priorNonCommitments
        self.lastDecisionFrame = lastDecisionFrame
        self.lastApprovedPosition = lastApprovedPosition
        self.latestDelta = latestDelta
        self.lastKnownStance = lastKnownStance
        self.knownFacts = knownFacts
        self.unresolvedIssues = unresolvedIssues
        self.surfacedCandidateCount = surfacedCandidateCount
        self.hasComparableAlternatives = hasComparableAlternatives
        self.hasFreshProviderAnswer = hasFreshProviderAnswer
        self.clarificationRounds = clarificationRounds
        self.followUpAttempts = followUpAttempts
        self.autonomousRoundsSoFar = autonomousRoundsSoFar
        self.isTimeSensitive = isTimeSensitive
        self.isPriceSensitive = isPriceSensitive
        self.hasLowTrustSignals = hasLowTrustSignals
        self.inquiry = inquiry
        self.structuredQuery = structuredQuery
        self.isCustomPricing = isCustomPricing
        self.includesSensitiveDisclosure = includesSensitiveDisclosure
        self.includesScheduleCommitment = includesScheduleCommitment
        self.includesLegalCommercialCommitment = includesLegalCommercialCommitment
        self.isPolicyException = isPolicyException
        self.selectedCounterpartyID = selectedCounterpartyID
        self.selectedPublicProfileID = selectedPublicProfileID
        self.selectedOfferID = selectedOfferID
        let trimmedInbound = lastInboundEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastInboundEnvelopeID = (trimmedInbound?.isEmpty == false) ? trimmedInbound : nil
        self.counterpartyName = counterpartyName
        self.subjectMatter = subjectMatter
        self.requestedItems = requestedItems
        self.clarifiedFacts = clarifiedFacts
        self.customInstructions = customInstructions
        self.previousRecommendation = previousRecommendation
        let trimmedReply = latestCounterpartyReplyText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latestCounterpartyReplyText = (trimmedReply?.isEmpty == true) ? nil : trimmedReply
        self.isThreadExplicitlyCompleted = isThreadExplicitlyCompleted
        self.providerCompareFirstStructuredPillarBypassPacket = providerCompareFirstStructuredPillarBypassPacket
        let trimmedCaptured = requestCapturedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requestCapturedText = (trimmedCaptured?.isEmpty == false) ? trimmedCaptured : nil
        self.isFirstExternalContact = isFirstExternalContact
    }

    /// When false, requester-role `.askClarification` cannot be routed to a specific provider/listing/recipient surface.
    public var hasAnchoredRecipientSurfaceForRequesterProviderOutbound: Bool {
        ExchangeOutboundRecipientAnchor.hasRecipientSurface(
            selectedCounterpartyID: selectedCounterpartyID,
            selectedPublicProfileID: selectedPublicProfileID,
            selectedOfferID: selectedOfferID,
            lastInboundEnvelopeID: lastInboundEnvelopeID
        )
    }
}
