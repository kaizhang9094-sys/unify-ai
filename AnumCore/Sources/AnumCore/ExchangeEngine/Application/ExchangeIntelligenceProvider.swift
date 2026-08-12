import Foundation

/// Protocol boundary for AI-backed secretary judgment.
///
/// Meaning-heavy exchange work should depend on this seam rather than on any
/// specific model runtime. The execution layer stays deterministic; this layer
/// only produces structured judgment artifacts that can be validated and
/// clamped by callers.
public protocol ExchangeIntelligenceProvider: Sendable {
    func classifyIntentFast(
        _ request: ExchangeIntelligenceFastClassificationRequest
    ) async throws -> ExchangeIntelligenceFastClassificationResponse

    func extractProviderInboundIntent(
        _ request: ProviderInboundIntentExtractionRequest
    ) async throws -> ProviderInboundIntentExtraction

    func interpret(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse

    func modelPosture(
        _ request: ExchangeIntelligencePostureRequest
    ) async throws -> ExchangeIntelligencePostureResponse

    func composeDraft(
        _ request: ExchangeIntelligenceDraftRequest
    ) async throws -> ExchangeIntelligenceDraftResponse

    func classifyInboundInquiry(
        _ request: ExchangeIntelligenceInboundInquiryRequest
    ) async throws -> ExchangeIntelligenceInboundInquiryResponse
}

extension ExchangeIntelligenceProvider {
    /// Default for test doubles and fallback provider; `OnDeviceExchangeIntelligenceProvider` overrides with LLM extraction.
    public func extractProviderInboundIntent(
        _ request: ProviderInboundIntentExtractionRequest
    ) async throws -> ProviderInboundIntentExtraction {
        ProviderInboundIntentExtractor.conservativeDecodeFailed(rawRequesterAsk: request.rawRequesterAsk)
    }
}

// MARK: - Fast interpretation gate

/// Selects which fast-classification prompt variant to run (same JSON output shape).
public enum ExchangeFastClassificationPurpose: String, Codable, Sendable, Hashable {
    /// Standard requester-side routing (existing behavior).
    case standardRequesterInterpretation
    /// Latest inbound message on a provider thread: counterparty anchor must not dominate lane/surface.
    case providerInboundAsk
}

public struct ExchangeIntelligenceFastClassificationRequest: Codable, Sendable, Hashable {
    public var userText: String
    public var threadContext: ExchangeInterpreter.ThreadContext?
    public var purpose: ExchangeFastClassificationPurpose

    enum CodingKeys: String, CodingKey {
        case userText
        case threadContext
        case purpose
    }

    public init(
        userText: String,
        threadContext: ExchangeInterpreter.ThreadContext? = nil,
        purpose: ExchangeFastClassificationPurpose = .standardRequesterInterpretation
    ) {
        self.userText = userText
        self.threadContext = threadContext
        self.purpose = purpose
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userText = try c.decode(String.self, forKey: .userText)
        threadContext = try c.decodeIfPresent(ExchangeInterpreter.ThreadContext.self, forKey: .threadContext)
        purpose = try c.decodeIfPresent(ExchangeFastClassificationPurpose.self, forKey: .purpose)
            ?? .standardRequesterInterpretation
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userText, forKey: .userText)
        try c.encodeIfPresent(threadContext, forKey: .threadContext)
        try c.encode(purpose, forKey: .purpose)
    }
}

/// Fatal classification outcomes for `providerInboundAsk` (no template fallback posing as model output).
public struct ExchangeIntelligenceFastClassificationDecodeDetails: Sendable, Equatable {
    public let underlyingDescription: String
    public let rawCharacterCount: Int
    public let cleanedCharacterCount: Int

    public init(
        underlyingDescription: String,
        rawCharacterCount: Int,
        cleanedCharacterCount: Int
    ) {
        self.underlyingDescription = underlyingDescription
        self.rawCharacterCount = rawCharacterCount
        self.cleanedCharacterCount = cleanedCharacterCount
    }
}

public enum ExchangeIntelligenceFastClassificationFailure: Error, Sendable, Equatable {
    case decodeFailed(ExchangeIntelligenceFastClassificationDecodeDetails)
    case unusableLowConfidenceAfterDecode(
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference,
        confidence: Double
    )
}

public struct ExchangeIntelligenceFastClassificationResponse: Codable, Sendable, Hashable {
    public var queryIntentClass: ExchangeIntent.QueryIntentClass
    public var surfacePreference: ExchangeIntent.SurfacePreference
    public var mode: ExchangeMode
    public var kind: ExchangeIntent.Kind
    public var readiness: ExchangeIntent.Readiness

    public var confidence: Double
    public var needsFullLLMInterpretation: Bool

    public var semanticTags: [String]
    public var discoveryKeywords: [String]
    public var targetTags: [String]

    public var providerTerms: [String]
    public var capabilityTerms: [String]
    public var affinityTerms: [String]
    public var regionTerms: [String]

    public var explicitHardConstraints: [ExchangeIntent.Constraint]
    public var targetDescription: String?

    public var userSummary: String?
    public var userNextStep: String?

    public init(
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference,
        mode: ExchangeMode,
        kind: ExchangeIntent.Kind,
        readiness: ExchangeIntent.Readiness,
        confidence: Double,
        needsFullLLMInterpretation: Bool,
        semanticTags: [String] = [],
        discoveryKeywords: [String] = [],
        targetTags: [String] = [],
        providerTerms: [String] = [],
        capabilityTerms: [String] = [],
        affinityTerms: [String] = [],
        regionTerms: [String] = [],
        explicitHardConstraints: [ExchangeIntent.Constraint] = [],
        targetDescription: String? = nil,
        userSummary: String? = nil,
        userNextStep: String? = nil
    ) {
        self.queryIntentClass = queryIntentClass
        self.surfacePreference = surfacePreference
        self.mode = mode
        self.kind = kind
        self.readiness = readiness
        self.confidence = confidence
        self.needsFullLLMInterpretation = needsFullLLMInterpretation
        self.semanticTags = semanticTags
        self.discoveryKeywords = discoveryKeywords
        self.targetTags = targetTags
        self.providerTerms = providerTerms
        self.capabilityTerms = capabilityTerms
        self.affinityTerms = affinityTerms
        self.regionTerms = regionTerms
        self.explicitHardConstraints = explicitHardConstraints
        self.targetDescription = targetDescription
        self.userSummary = userSummary
        self.userNextStep = userNextStep
    }
}

// MARK: - Interpretation

public struct ExchangeIntelligenceInterpretationRequest: Codable, Sendable, Hashable {
    public var userText: String
    public var threadContext: ExchangeInterpreter.ThreadContext?

    public init(
        userText: String,
        threadContext: ExchangeInterpreter.ThreadContext? = nil
    ) {
        self.userText = userText
        self.threadContext = threadContext
    }
}

public struct ExchangeIntelligenceInterpretationResponse: Codable, Sendable, Hashable {
    public var queryIntentClass: ExchangeIntent.QueryIntentClass?
    public var surfacePreference: ExchangeIntent.SurfacePreference?

    public var mode: ExchangeMode
    public var kind: ExchangeIntent.Kind
    public var title: String
    public var objective: String
    public var targetDescription: String?
    public var constraints: [ExchangeIntent.Constraint]
    public var desiredOutcomes: [ExchangeIntent.DesiredOutcome]
    public var readiness: ExchangeIntent.Readiness
    public var interpretationNotes: String?
    public var confidence: Double
    public var clarificationQuestion: String?

    public var userSummary: String?
    public var userQuestion: String?
    public var userNextStep: String?

    public var inferredPosture: ExchangeIntelligencePostureResponse?

    public var needsClarification: Bool
    public var shouldDiscover: Bool
    public var shouldDraft: Bool

    public var semanticTags: [String]
    public var discoveryKeywords: [String]
    public var targetTags: [String]

    public init(
        queryIntentClass: ExchangeIntent.QueryIntentClass? = nil,
        surfacePreference: ExchangeIntent.SurfacePreference? = nil,
        mode: ExchangeMode,
        kind: ExchangeIntent.Kind,
        title: String,
        objective: String,
        targetDescription: String? = nil,
        constraints: [ExchangeIntent.Constraint] = [],
        desiredOutcomes: [ExchangeIntent.DesiredOutcome] = [],
        readiness: ExchangeIntent.Readiness,
        interpretationNotes: String? = nil,
        confidence: Double,
        clarificationQuestion: String? = nil,
        userSummary: String? = nil,
        userQuestion: String? = nil,
        userNextStep: String? = nil,
        inferredPosture: ExchangeIntelligencePostureResponse? = nil,
        needsClarification: Bool = false,
        shouldDiscover: Bool = true,
        shouldDraft: Bool = false,
        semanticTags: [String] = [],
        discoveryKeywords: [String] = [],
        targetTags: [String] = []
    ) {
        self.queryIntentClass = queryIntentClass
        self.surfacePreference = surfacePreference
        self.mode = mode
        self.kind = kind
        self.title = title
        self.objective = objective
        self.targetDescription = targetDescription
        self.constraints = constraints
        self.desiredOutcomes = desiredOutcomes
        self.readiness = readiness
        self.interpretationNotes = interpretationNotes
        self.confidence = confidence
        self.clarificationQuestion = clarificationQuestion
        self.userSummary = userSummary
        self.userQuestion = userQuestion
        self.userNextStep = userNextStep
        self.inferredPosture = inferredPosture
        self.needsClarification = needsClarification
        self.shouldDiscover = shouldDiscover
        self.shouldDraft = shouldDraft
        self.semanticTags = semanticTags
        self.discoveryKeywords = discoveryKeywords
        self.targetTags = targetTags
    }
}

// MARK: - Posture

public struct ExchangeIntelligencePostureRequest: Codable, Sendable, Hashable {
    public var userText: String
    public var intent: ExchangeIntent
    public var priorPosture: ExchangePosture?

    public init(
        userText: String,
        intent: ExchangeIntent,
        priorPosture: ExchangePosture? = nil
    ) {
        self.userText = userText
        self.intent = intent
        self.priorPosture = priorPosture
    }
}

public struct ExchangeIntelligencePostureResponse: Codable, Sendable, Hashable {
    public var urgency: ExchangePosture.Urgency
    public var warmth: ExchangePosture.Warmth
    public var directness: ExchangePosture.Directness
    public var openness: ExchangePosture.Openness
    public var commitment: ExchangePosture.Commitment
    public var privacy: ExchangePosture.Privacy
    public var priceSensitivity: ExchangePosture.PriceSensitivity
    public var flexibility: ExchangePosture.Flexibility
    public var notes: String?
    public var confidence: Double

    public init(
        urgency: ExchangePosture.Urgency,
        warmth: ExchangePosture.Warmth,
        directness: ExchangePosture.Directness,
        openness: ExchangePosture.Openness,
        commitment: ExchangePosture.Commitment,
        privacy: ExchangePosture.Privacy,
        priceSensitivity: ExchangePosture.PriceSensitivity,
        flexibility: ExchangePosture.Flexibility,
        notes: String? = nil,
        confidence: Double
    ) {
        self.urgency = urgency
        self.warmth = warmth
        self.directness = directness
        self.openness = openness
        self.commitment = commitment
        self.privacy = privacy
        self.priceSensitivity = priceSensitivity
        self.flexibility = flexibility
        self.notes = notes
        self.confidence = confidence
    }
}

// MARK: - Drafting

public struct ExchangeIntelligenceDraftRequest: Codable, Sendable, Hashable {
    public var thread: ExchangeThread
    public var counterparty: ExchangeCounterparty
    public var kind: ExchangeMessageDraft.Kind
    public var supersedingDraft: ExchangeMessageDraft?

    public init(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        kind: ExchangeMessageDraft.Kind,
        supersedingDraft: ExchangeMessageDraft? = nil
    ) {
        self.thread = thread
        self.counterparty = counterparty
        self.kind = kind
        self.supersedingDraft = supersedingDraft
    }
}

public struct ExchangeIntelligenceDraftResponse: Codable, Sendable, Hashable {
    public var subject: String?
    public var body: String
    public var strategyNote: String?
    public var confidence: Double

    public init(
        subject: String? = nil,
        body: String,
        strategyNote: String? = nil,
        confidence: Double
    ) {
        self.subject = subject
        self.body = body
        self.strategyNote = strategyNote
        self.confidence = confidence
    }
}

// MARK: - Provider-side inbound inquiry classification

public struct ExchangeIntelligenceInboundInquiryRequest: Codable, Sendable, Hashable {
    public var threadTitle: String
    public var visibleSummary: String?
    public var requesterAsk: String
    public var matchedOfferOrProfileAnchor: String?
    public var selectedCounterpartyName: String?
    public var knownFacts: [String]
    public var unresolvedIssues: [String]
    public var secretaryRepresentation: String?

    public init(
        threadTitle: String,
        visibleSummary: String? = nil,
        requesterAsk: String,
        matchedOfferOrProfileAnchor: String? = nil,
        selectedCounterpartyName: String? = nil,
        knownFacts: [String] = [],
        unresolvedIssues: [String] = [],
        secretaryRepresentation: String? = nil
    ) {
        self.threadTitle = threadTitle
        self.visibleSummary = visibleSummary
        self.requesterAsk = requesterAsk
        self.matchedOfferOrProfileAnchor = matchedOfferOrProfileAnchor
        self.selectedCounterpartyName = selectedCounterpartyName
        self.knownFacts = knownFacts
        self.unresolvedIssues = unresolvedIssues
        self.secretaryRepresentation = secretaryRepresentation
    }
}

public struct ExchangeIntelligenceInboundInquiryResponse: Codable, Sendable, Hashable {
    public var inquirySummary: String
    public var requesterAsk: String
    public var matchedOfferOrProfileAnchor: String?
    public var answerabilityStatus: ExchangeInboundInquiryAnswerability
    public var classification: ExchangeInboundInquiryClassification
    public var rationale: String?
    public var confidence: Double

    public init(
        inquirySummary: String,
        requesterAsk: String,
        matchedOfferOrProfileAnchor: String? = nil,
        answerabilityStatus: ExchangeInboundInquiryAnswerability,
        classification: ExchangeInboundInquiryClassification,
        rationale: String? = nil,
        confidence: Double
    ) {
        self.inquirySummary = inquirySummary
        self.requesterAsk = requesterAsk
        self.matchedOfferOrProfileAnchor = matchedOfferOrProfileAnchor
        self.answerabilityStatus = answerabilityStatus
        self.classification = classification
        self.rationale = rationale
        self.confidence = max(0.0, min(1.0, confidence))
    }

    public var asInboundInquiry: ExchangeInboundInquiry {
        ExchangeInboundInquiry(
            inquirySummary: inquirySummary,
            requesterAsk: requesterAsk,
            matchedOfferOrProfileAnchor: matchedOfferOrProfileAnchor,
            answerabilityStatus: answerabilityStatus,
            classification: classification
        )
    }
}

// MARK: - Conservative fallback provider

public struct ExchangeFallbackIntelligenceProvider: ExchangeIntelligenceProvider, Sendable {
    private let postureModeler = ExchangePostureModeler(
        intelligenceProvider: nil,
        useLegacyHeuristics: true
    )
    private let draftEngine = ExchangeDraftEngine.legacyTemplate

    public init() {}

    public func classifyIntentFast(
        _ request: ExchangeIntelligenceFastClassificationRequest
    ) async throws -> ExchangeIntelligenceFastClassificationResponse {
        let normalized = normalizeInput(request.userText)
        let lower = normalized.lowercased()

        let queryIntentClass = inferQueryIntentClass(
            from: lower,
            threadContext: request.threadContext,
            purpose: request.purpose
        )
        let surfacePreference = inferSurfacePreference(for: queryIntentClass)
        let mode = inferMode(from: lower, threadContext: request.threadContext)
        let kind = inferKind(
            from: lower,
            threadContext: request.threadContext,
            purpose: request.purpose
        )
        let readiness = inferReadiness(
            text: normalized,
            kind: kind,
            threadContext: request.threadContext,
            purpose: request.purpose
        )

        let providerTerms = inferProviderTerms(from: lower)
        let capabilityTerms = inferCapabilityTerms(from: lower)
        let affinityTerms = inferAffinityTerms(from: lower)
        let regionTerms = inferRegionTerms(from: lower)
        let semanticTags = normalizeTags(
            [kind.rawValue] + providerTerms + capabilityTerms + affinityTerms + regionTerms,
            maxCount: 12
        )
        let targetTags = inferTargetTags(
            queryIntentClass: queryIntentClass,
            providerTerms: providerTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: affinityTerms
        )
        let discoveryKeywords = normalizeTags(
            providerTerms + capabilityTerms + affinityTerms + regionTerms + targetTags,
            maxCount: 12
        )

        let needsFull = needsFullInterpretation(
            text: normalized,
            queryIntentClass: queryIntentClass,
            readiness: readiness,
            threadContext: request.threadContext,
            purpose: request.purpose
        )

        return ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference,
            mode: mode,
            kind: kind,
            readiness: readiness,
            confidence: needsFull ? 0.45 : 0.75,
            needsFullLLMInterpretation: needsFull,
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags,
            providerTerms: providerTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: affinityTerms,
            regionTerms: regionTerms,
            explicitHardConstraints: inferHardConstraints(from: lower),
            targetDescription: inferTargetDescription(from: normalized, kind: kind),
            userSummary: fallbackUserSummary(
                kind: kind,
                objective: normalized,
                targetDescription: inferTargetDescription(from: normalized, kind: kind),
                readiness: readiness
            ),
            userNextStep: fallbackUserNextStep(
                kind: kind,
                readiness: readiness
            )
        )
    }

    public func interpret(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse {
        let fast = try await classifyIntentFast(
            .init(
                userText: request.userText,
                threadContext: request.threadContext
            )
        )

        let normalized = normalizeInput(request.userText)

        let inferredPostureModel = await postureModeler.model(
            userText: request.userText,
            intent: ExchangeIntent(
                kind: fast.kind,
                mode: fast.mode,
                title: fallbackTitle(
                    for: fast.kind,
                    text: normalized,
                    threadContext: request.threadContext
                ),
                objective: normalized,
                targetDescription: fast.targetDescription,
                constraints: fast.explicitHardConstraints,
                desiredOutcomes: fallbackDesiredOutcomes(for: fast.kind),
                readiness: fast.readiness,
                interpretationNotes: "Fallback interpretation provider used."
            ),
            priorPosture: nil
        )

        let inferredPosture = ExchangeIntelligencePostureResponse(
            urgency: inferredPostureModel.urgency,
            warmth: inferredPostureModel.warmth,
            directness: inferredPostureModel.directness,
            openness: inferredPostureModel.openness,
            commitment: inferredPostureModel.commitment,
            privacy: inferredPostureModel.privacy,
            priceSensitivity: inferredPostureModel.priceSensitivity,
            flexibility: inferredPostureModel.flexibility,
            notes: inferredPostureModel.notes,
            confidence: 0.55
        )

        return ExchangeIntelligenceInterpretationResponse(
            queryIntentClass: fast.queryIntentClass,
            surfacePreference: fast.surfacePreference,
            mode: fast.mode,
            kind: fast.kind,
            title: fallbackTitle(
                for: fast.kind,
                text: normalized,
                threadContext: request.threadContext
            ),
            objective: normalized,
            targetDescription: fast.targetDescription,
            constraints: fast.explicitHardConstraints,
            desiredOutcomes: fallbackDesiredOutcomes(for: fast.kind),
            readiness: fast.readiness,
            interpretationNotes: "Fallback interpretation provider used.",
            confidence: fast.confidence,
            clarificationQuestion: fast.readiness == .ready
                ? nil
                : fallbackClarificationQuestion(for: fast.kind),
            userSummary: fast.userSummary,
            userQuestion: fast.readiness == .ready
                ? nil
                : fallbackClarificationQuestion(for: fast.kind),
            userNextStep: fast.userNextStep,
            inferredPosture: inferredPosture,
            needsClarification: fast.readiness != .ready,
            shouldDiscover: defaultShouldDiscover(for: fast.kind) && request.threadContext?.selectedCounterpartyID == nil,
            shouldDraft: defaultShouldDraft(for: fast.kind) && request.threadContext?.selectedCounterpartyID != nil,
            semanticTags: fast.semanticTags,
            discoveryKeywords: fast.discoveryKeywords,
            targetTags: fast.targetTags
        )
    }

    public func modelPosture(
        _ request: ExchangeIntelligencePostureRequest
    ) async throws -> ExchangeIntelligencePostureResponse {
        let posture = await postureModeler.model(
            userText: request.userText,
            intent: request.intent,
            priorPosture: request.priorPosture
        )

        return ExchangeIntelligencePostureResponse(
            urgency: posture.urgency,
            warmth: posture.warmth,
            directness: posture.directness,
            openness: posture.openness,
            commitment: posture.commitment,
            privacy: posture.privacy,
            priceSensitivity: posture.priceSensitivity,
            flexibility: posture.flexibility,
            notes: posture.notes,
            confidence: 0.55
        )
    }

    public func composeDraft(
        _ request: ExchangeIntelligenceDraftRequest
    ) async throws -> ExchangeIntelligenceDraftResponse {
        let draft = await draftEngine.createDraft(
            thread: request.thread,
            counterparty: request.counterparty,
            kind: request.kind,
            superseding: request.supersedingDraft?.id,
            now: request.supersedingDraft?.updatedAt ?? Date()
        )

        return ExchangeIntelligenceDraftResponse(
            subject: draft.subject,
            body: draft.body,
            strategyNote: draft.strategyNote,
            confidence: 0.50
        )
    }
    
    public func classifyInboundInquiry(
        _ request: ExchangeIntelligenceInboundInquiryRequest
    ) async throws -> ExchangeIntelligenceInboundInquiryResponse {
        let raw = [
            request.threadTitle,
            request.visibleSummary,
            request.requesterAsk,
            request.matchedOfferOrProfileAnchor,
            request.selectedCounterpartyName,
            request.knownFacts.joined(separator: " "),
            request.unresolvedIssues.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        let answerability: ExchangeInboundInquiryAnswerability
        if containsAny(raw, ["not a fit", "out of scope", "we don't do", "cannot help", "can't help"]) {
            answerability = .outOfScope
        } else if containsAny(raw, [
            "custom price", "custom pricing", "special rate", "discount",
            "contract", "agreement", "sign", "deposit", "payment",
            "schedule", "book", "reserve", "confirm time",
            "private", "confidential", "sensitive"
        ]) {
            answerability = .requiresUserInput
        } else if !request.knownFacts.isEmpty || request.matchedOfferOrProfileAnchor != nil {
            answerability = .answerableFromKnownFacts
        } else {
            answerability = .insufficientContext
        }

        let classification: ExchangeInboundInquiryClassification =
            answerability == .requiresUserInput ? .exceptional : .routine

        return ExchangeIntelligenceInboundInquiryResponse(
            inquirySummary: request.visibleSummary ?? String(request.requesterAsk.prefix(220)),
            requesterAsk: request.requesterAsk,
            matchedOfferOrProfileAnchor: request.matchedOfferOrProfileAnchor,
            answerabilityStatus: answerability,
            classification: classification,
            rationale: "Fallback inbound inquiry classifier used.",
            confidence: 0.50
        )
    }
}

private extension ExchangeFallbackIntelligenceProvider {
    func inferQueryIntentClass(
        from lower: String,
        threadContext: ExchangeInterpreter.ThreadContext?,
        purpose: ExchangeFastClassificationPurpose = .standardRequesterInterpretation
    ) -> ExchangeIntent.QueryIntentClass {
        if purpose != .providerInboundAsk,
           threadContext?.selectedCounterpartyID != nil {
            if containsAny(lower, ["status", "update", "where is this at", "what's the status"]) {
                return .statusCheck
            }
            if containsAny(lower, ["follow up", "follow-up", "check back"]) {
                return .followUp
            }
            return .directOutreach
        }

        if containsAny(lower, ["date", "dating", "single", "relationship"]) {
            return .relationshipSearch
        }
        if containsAny(lower, ["swim", "swimmer", "movie", "movies", "tennis", "hiking", "friend", "friends"]) {
            return .socialAffinitySearch
        }
        if containsAny(lower, ["collaborate", "collaboration", "partner", "work together", "cofounder", "co-founder"]) {
            return .collaborationSearch
        }
        if containsAny(lower, ["quote", "estimate", "roofer", "roofing", "hvac", "plumber", "electrician", "realtor", "contractor", "repair"]) {
            return .providerSearch
        }
        if containsAny(lower, ["offer", "service", "seller", "provider"]) {
            return .offerSearch
        }

        return .generalDiscovery
    }

    func inferSurfacePreference(
        for queryIntentClass: ExchangeIntent.QueryIntentClass
    ) -> ExchangeIntent.SurfacePreference {
        switch queryIntentClass {
        case .providerSearch, .offerSearch:
            return .offer
        case .capabilitySearch, .collaborationSearch:
            return .capability
        case .socialAffinitySearch, .relationshipSearch:
            return .affinity
        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return .mixed
        }
    }

    func inferMode(
        from lower: String,
        threadContext: ExchangeInterpreter.ThreadContext?
    ) -> ExchangeMode {
        if containsAny(lower, ["meet", "date", "relationship", "friend", "social", "introduce"]) {
            return .relational
        }
        if containsAny(lower, ["coordinate", "plan", "arrange", "schedule", "collaborate", "event", "partner"]) {
            return .cooperative
        }
        return threadContext?.modeHint ?? .transactional
    }

    func inferKind(
        from lower: String,
        threadContext: ExchangeInterpreter.ThreadContext?,
        purpose: ExchangeFastClassificationPurpose = .standardRequesterInterpretation
    ) -> ExchangeIntent.Kind {
        if containsAny(lower, ["quote", "pricing", "estimate", "bid"]) { return .requestQuote }
        if containsAny(lower, ["introduce", "intro", "connect me with"]) { return .introduce }
        if containsAny(lower, ["negotiate", "counteroffer", "terms"]) { return .negotiate }
        if containsAny(lower, ["phone call", "call"]) { return .arrangeCall }
        if containsAny(lower, ["meeting", "meet"]) { return .arrangeMeeting }
        if containsAny(lower, ["follow up", "follow-up", "check back"]) { return .followUp }
        if containsAny(lower, ["status", "update", "hear back"]) { return .checkStatus }
        if containsAny(lower, ["invite", "invitation"]) { return .invite }
        if containsAny(lower, ["source", "procure"]) { return .source }
        // "looking for …" does not contain the substring "look for" (the "ing" breaks it); keep in sync
        // with `ExchangeInterpreter.inferIntentKind`.
        if containsAny(lower, ["find", "look for", "looking for", "search for", "search"]) { return .find }
        if containsAny(lower, ["message", "contact", "send", "reach out"]) { return .message }
        if containsAny(lower, ["plan", "coordinate", "arrange", "schedule"]) { return .coordinate }

        if purpose != .providerInboundAsk,
           threadContext?.selectedCounterpartyID != nil {
            return .message
        }

        return .other
    }

    func inferReadiness(
        text: String,
        kind: ExchangeIntent.Kind,
        threadContext: ExchangeInterpreter.ThreadContext?,
        purpose: ExchangeFastClassificationPurpose = .standardRequesterInterpretation
    ) -> ExchangeIntent.Readiness {
        if purpose != .providerInboundAsk,
           threadContext?.selectedCounterpartyID != nil {
            return .ready
        }
        if text.count < 4 {
            return .underSpecified
        }
        switch kind {
        case .other:
            return .needsClarification
        default:
            return .ready
        }
    }

    func inferProviderTerms(from lower: String) -> [String] {
        var out: [String] = []
        if containsAny(lower, ["roofer", "roofing"]) { out.append("roofer") }
        if containsAny(lower, ["commercial roof", "commercial roofing"]) { out.append("commercial roofing") }
        if containsAny(lower, ["repair"]) { out.append("repair") }
        if containsAny(lower, ["hvac"]) { out.append("hvac") }
        if containsAny(lower, ["contractor"]) { out.append("contractor") }
        if containsAny(lower, ["realtor", "real estate"]) { out.append("realtor") }
        if containsAny(lower, ["battery recycler", "battery recycling"]) { out.append("battery recycler") }
        return normalizeTags(out, maxCount: 12)
    }

    func inferCapabilityTerms(from lower: String) -> [String] {
        var out: [String] = []
        if containsAny(lower, ["open to", "can help with", "come to you for"]) { out.append("open to") }
        if containsAny(lower, ["collaborate", "collaboration"]) { out.append("collaboration") }
        if containsAny(lower, ["ai"]) { out.append("ai") }
        return normalizeTags(out, maxCount: 12)
    }

    func inferAffinityTerms(from lower: String) -> [String] {
        var out: [String] = []
        if containsAny(lower, ["swim", "swimmer", "swimming"]) { out.append("swimming") }
        if containsAny(lower, ["movie", "movies"]) { out.append("movies") }
        if containsAny(lower, ["tennis"]) { out.append("tennis") }
        if containsAny(lower, ["date", "dating"]) { out.append("dating") }
        if containsAny(lower, ["friend", "friends"]) { out.append("friendship") }
        return normalizeTags(out, maxCount: 12)
    }

    func inferRegionTerms(from lower: String) -> [String] {
        var out: [String] = []
        if containsAny(lower, ["toronto"]) { out.append("toronto") }
        if containsAny(lower, ["aurora"]) { out.append("aurora") }
        if containsAny(lower, ["ontario"]) { out.append("ontario") }
        if containsAny(lower, ["canada"]) { out.append("canada") }
        return normalizeTags(out, maxCount: 8)
    }

    func inferTargetTags(
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        providerTerms: [String],
        capabilityTerms: [String],
        affinityTerms: [String]
    ) -> [String] {
        switch queryIntentClass {
        case .providerSearch, .offerSearch:
            return normalizeTags(providerTerms + ["service provider", "business"], maxCount: 10)
        case .capabilitySearch, .collaborationSearch:
            return normalizeTags(capabilityTerms + ["collaborator", "person"], maxCount: 10)
        case .socialAffinitySearch:
            return normalizeTags(affinityTerms + ["person"], maxCount: 10)
        case .relationshipSearch:
            return normalizeTags(affinityTerms + ["person"], maxCount: 10)
        case .directOutreach, .followUp, .statusCheck:
            return ["contact"]
        case .generalDiscovery:
            return ["person"]
        }
    }

    func inferHardConstraints(from lower: String) -> [ExchangeIntent.Constraint] {
        var out: [ExchangeIntent.Constraint] = []
        if containsAny(lower, ["urgent", "asap", "immediately", "today"]) {
            out.append(.init(key: "timing", value: "urgent", isHardConstraint: true))
        }
        if containsAny(lower, ["private", "discreet"]) {
            out.append(.init(key: "privacy", value: "guarded", isHardConstraint: true))
        }
        return out
    }

    func inferTargetDescription(
        from text: String,
        kind: ExchangeIntent.Kind
    ) -> String? {
        let cleaned = normalizeInput(text)
        let lower = cleaned.lowercased()

        func snippet(after prefixes: [String]) -> String? {
            for prefix in prefixes {
                guard let range = lower.range(of: prefix) else { continue }
                let suffix = cleaned[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                let clipped = String(suffix.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !clipped.isEmpty { return clipped }
            }
            return nil
        }

        switch kind {
        case .find:
            return snippet(after: ["find ", "look for ", "search for "])
        case .source:
            return snippet(after: ["source ", "procure "])
        case .introduce:
            return snippet(after: ["to ", "with "])
        case .requestQuote:
            return snippet(after: ["quote for ", "estimate for ", "pricing for ", "for "])
        default:
            return nil
        }
    }

    func needsFullInterpretation(
        text: String,
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        readiness: ExchangeIntent.Readiness,
        threadContext: ExchangeInterpreter.ThreadContext?,
        purpose: ExchangeFastClassificationPurpose = .standardRequesterInterpretation
    ) -> Bool {
        if purpose != .providerInboundAsk,
           threadContext?.selectedCounterpartyID != nil {
            return false
        }
        if readiness != .ready {
            return true
        }
        if text.count > 180 {
            return true
        }
        switch queryIntentClass {
        case .generalDiscovery, .collaborationSearch:
            return true
        case .providerSearch, .offerSearch, .socialAffinitySearch, .relationshipSearch, .directOutreach, .followUp, .statusCheck, .capabilitySearch:
            return false
        }
    }

    func defaultShouldDiscover(for kind: ExchangeIntent.Kind) -> Bool {
        switch kind {
        case .find, .source, .introduce, .requestQuote:
            return true
        default:
            return false
        }
    }

    func defaultShouldDraft(for kind: ExchangeIntent.Kind) -> Bool {
        switch kind {
        case .message, .followUp, .checkStatus, .arrangeCall, .arrangeMeeting, .invite, .coordinate, .plan, .negotiate:
            return true
        default:
            return false
        }
    }

    func fallbackUserSummary(
        kind: ExchangeIntent.Kind,
        objective: String,
        targetDescription: String?,
        readiness: ExchangeIntent.Readiness
    ) -> String {
        let subject = targetDescription?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .introduce:
            if let subject, !subject.isEmpty {
                return readiness == .ready
                    ? "I understood this as a request to help with an introduction to \(subject)."
                    : "I understood this as a request to help with an introduction to \(subject), but I still need a clearer target or filter."
            }
            return "I understood this as a request to help with an introduction."

        case .find:
            if let subject, !subject.isEmpty {
                return "I understood this as a request to find \(subject)."
            }
            return "I understood this as a request to find a relevant match."

        case .source:
            if let subject, !subject.isEmpty {
                return "I understood this as a request to source \(subject)."
            }
            return "I understood this as a sourcing request."

        case .message:
            return "I understood this as a request to prepare or advance a message."

        case .requestQuote:
            return "I understood this as a request to obtain a quote."

        case .arrangeCall:
            return "I understood this as a request to arrange a call."

        case .arrangeMeeting:
            return "I understood this as a request to arrange a meeting."

        case .followUp:
            return "I understood this as a request to follow up on an existing thread."

        case .checkStatus:
            return "I understood this as a request to check the status of an existing thread."

        case .invite:
            return "I understood this as a request to send an invitation."

        case .coordinate, .plan:
            return "I understood this as a coordination request."

        case .negotiate:
            return "I understood this as a negotiation-related request."

        case .other:
            return objective.isEmpty
                ? "I understood the general direction of the request."
                : "I understood the general direction of the request, but it may still need refinement."
        }
    }

    func fallbackUserNextStep(
        kind: ExchangeIntent.Kind,
        readiness: ExchangeIntent.Readiness
    ) -> String {
        switch readiness {
        case .ready:
            switch kind {
            case .introduce, .find, .source:
                return "I can use that understanding to search for viable paths or matches."
            case .message, .followUp, .checkStatus:
                return "I can use that understanding to prepare the next outbound step."
            case .requestQuote:
                return "I can use that understanding to look for suitable providers or prepare quote outreach."
            case .arrangeCall, .arrangeMeeting, .invite, .coordinate, .plan:
                return "I can use that understanding to prepare the next coordination step."
            case .negotiate:
                return "I can use that understanding to prepare the next negotiation move."
            case .other:
                return "I can use that understanding to determine the best next step."
            }

        case .needsClarification, .underSpecified:
            return "Once the missing detail is clarified, I can decide whether to search, draft, or advance the thread."
        }
    }

    func fallbackTitle(
        for kind: ExchangeIntent.Kind,
        text: String,
        threadContext: ExchangeInterpreter.ThreadContext?
    ) -> String {
        let clipped = String(text.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .requestQuote: return "Request Quote"
        case .introduce: return "Request Introduction"
        case .message: return threadContext?.selectedCounterpartyID != nil ? "Continue Message" : "Send Message"
        case .find: return "Find Match"
        case .source: return "Source Match"
        case .arrangeCall: return "Arrange Call"
        case .arrangeMeeting: return "Arrange Meeting"
        case .followUp: return "Follow Up"
        case .checkStatus: return "Check Status"
        case .invite: return "Invite"
        case .coordinate: return "Coordinate"
        case .plan: return "Plan"
        case .negotiate: return "Negotiate"
        case .other:
            return clipped.isEmpty ? (threadContext?.priorIntentTitle ?? "Exchange Request") : clipped
        }
    }

    func fallbackDesiredOutcomes(for kind: ExchangeIntent.Kind) -> [ExchangeIntent.DesiredOutcome] {
        switch kind {
        case .find, .source: return [.shortlist]
        case .introduce: return [.intro]
        case .requestQuote: return [.quote]
        case .arrangeCall, .arrangeMeeting: return [.meeting]
        case .message, .followUp, .checkStatus: return [.response]
        case .negotiate, .invite, .coordinate, .plan: return [.aligned]
        case .other: return [.resolved]
        }
    }

    func fallbackClarificationQuestion(for kind: ExchangeIntent.Kind) -> String {
        switch kind {
        case .requestQuote:
            return "What exactly do you want quoted, and what location or scope should I use?"
        case .introduce:
            return "Who do you want to be introduced to, or what kind of person should I look for?"
        case .message:
            return "Who should I contact, and what outcome do you want from the message?"
        case .arrangeCall, .arrangeMeeting:
            return "Who should I coordinate with, and what timing or purpose should I use?"
        case .find, .source:
            return "What kind of person or provider are you looking for, and what matters most in the match?"
        case .negotiate:
            return "What terms are you trying to move, and what outcome would count as acceptable?"
        case .followUp, .checkStatus:
            return "Which thread or contact should I follow up on?"
        case .invite:
            return "Who should be invited, and to what?"
        case .coordinate, .plan, .other:
            return "What is the specific coordination outcome you want me to help move forward?"
        }
    }

    func normalizeInput(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func normalizeTags(_ raw: [String], maxCount: Int) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for item in raw {
            let normalized = item
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !normalized.isEmpty else { continue }
            guard !seen.contains(normalized) else { continue }

            seen.insert(normalized)
            output.append(normalized)

            if output.count >= maxCount {
                break
            }
        }

        return output
    }

    func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
}
