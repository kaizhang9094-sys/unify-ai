import Foundation

#if DEBUG
@inline(__always)
private func exchInterpLog(_ message: @autoclosure () -> String) {
    print("[ExchangeInterpreter] \(message())")
}
#else
@inline(__always)
private func exchInterpLog(_ message: @autoclosure () -> String) {}
#endif

/// Natural-language interpreter for Exchange.
///
/// Target architecture:
/// - Layer 0: structural gate only
/// - Layer 1: lightweight prior from literal signal + state
/// - Layer 2: canonical intent/facets proposal
/// - Layer 3+: real public-surface retrieval happens elsewhere
/// - Layer 4: narrow LLM escalation only when ambiguity is real
///
/// This layer:
/// - produces canonical intent
/// - produces retrieval-facing facets
/// - decides clarify / discover / draft
///
/// This layer does NOT:
/// - act like a ranking engine
/// - invent giant handcrafted provider/capability/affinity term families
/// - become the semantic choke point for open-ended search
public struct ExchangeInterpreter: Sendable {
    private let intelligenceProvider: any ExchangeIntelligenceProvider
    private let searchIntentExtractor: any OpenEndedSearchIntentExtractor
    private let asyncSearchIntentExtractor: (any AsyncOpenEndedSearchIntentExtractor)?
    private let flatSearchIntentMapper: LLMOpenEndedSearchIntentExtractor

    public init(
        intelligenceProvider: any ExchangeIntelligenceProvider,
        searchIntentExtractor: any OpenEndedSearchIntentExtractor = CanonicalSearchIntentHeuristicExtractor(),
        asyncSearchIntentExtractor: (any AsyncOpenEndedSearchIntentExtractor)? = nil,
        flatSearchIntentMapper: LLMOpenEndedSearchIntentExtractor = LLMOpenEndedSearchIntentExtractor()
    ) {
        self.intelligenceProvider = intelligenceProvider
        self.searchIntentExtractor = searchIntentExtractor
        self.asyncSearchIntentExtractor = asyncSearchIntentExtractor
        self.flatSearchIntentMapper = flatSearchIntentMapper
    }

    /// Atomic object retained from compact flat decode when route validation/actionability rejects early canonical.
    struct PreservedCompactSearchArtifact: Sendable, Hashable {
        var objectType: String
        var transactionIntent: ExchangeIntentFacets.TransactionIntent?
        var domainCategory: ExchangeIntentFacets.DomainCategory?
        var extractionSource: SearchIntentExtractionSource?
    }

    public func interpret(
        userText: String,
        threadContext: ThreadContext? = nil,
        entrySurface: InterpretationEntrySurface = .other
    ) async -> InterpretationResult {
        let normalized = normalizeInput(userText)

        exchInterpLog(
            "interpret enter " +
            "chars=\(normalized.count) " +
            "threadID=\(threadContext?.threadID?.uuidString ?? "nil") " +
            "modeHint=\(threadContext?.modeHint?.rawValue ?? "nil") " +
            "selectedCounterpartyID=\(threadContext?.selectedCounterpartyID ?? "nil") " +
            "entrySurface=\(entrySurface.rawValue)"
        )

        guard !normalized.isEmpty else {
            return .needsClarification(
                ExchangeFailure.understanding(
                    summary: "I do not yet have enough to act.",
                    whatHappened: "The request was empty or too incomplete to interpret.",
                    question: "What would you like me to help coordinate?"
                )
            )
        }

        let structural = buildStructuralGate(
            sourceText: normalized,
            threadContext: threadContext
        )

        var canonicalExtractorAlreadyAttempted = false
        var preservedCompactSearchArtifact: PreservedCompactSearchArtifact?
        if let canonicalFirst = await tryCanonicalSearchIntentFirst(
            sourceText: normalized,
            structural: structural,
            threadContext: threadContext,
            entrySurface: entrySurface,
            didAttemptExtraction: &canonicalExtractorAlreadyAttempted,
            preservedCompactSearchArtifact: &preservedCompactSearchArtifact
        ) {
            return canonicalFirst
        }

        if preservedCompactSearchArtifact == nil,
           let asyncSearchIntentExtractor,
           let extractionDiag = await asyncSearchIntentExtractor.lastExtractionDiagnostics(),
           let objectHint = extractionDiag.compactDecodedObjectHint {
            preservedCompactSearchArtifact = makePreservedCompactSearchArtifact(
                objectType: objectHint,
                sourceText: normalized
            )
            if let preserved = preservedCompactSearchArtifact {
                exchInterpLog(
                    "[CompactObjectHintPreserved] object=\(preserved.objectType) " +
                    "source=\(preserved.extractionSource?.rawValue ?? "compactDecode")"
                )
            }
        }

        if canonicalExtractorAlreadyAttempted,
           let asyncSearchIntentExtractor,
           let extractionDiag = await asyncSearchIntentExtractor.lastExtractionDiagnostics() {
            let unexpectedObject = preservedCompactSearchArtifact?.objectType
                ?? extractionDiag.compactDecodedObjectHint
            if let unexpectedObject {
                let confidenceLabel: String = {
                    guard let summary = extractionDiag.compactCanonicalSummary else { return "nil" }
                    for part in summary.split(separator: " ") {
                        if part.hasPrefix("confidence=") {
                            return String(part.dropFirst("confidence=".count))
                        }
                    }
                    return "nil"
                }()
                exchInterpLog(
                    "[UnexpectedProviderFallbackAfterExtractor] object=\(unexpectedObject) " +
                    "confidence=\(confidenceLabel) reason=priorEscalationAfterCompactDecode"
                )
            }
        }

        let prior = await buildInterpretationPrior(
            sourceText: normalized,
            structural: structural,
            threadContext: threadContext
        )

        exchInterpLog(
            "prior built " +
            "primaryClass=\(prior.primaryQueryIntentClass.rawValue) " +
            "primarySurface=\(prior.primarySurfacePreference.rawValue) " +
            "secondaryClass=\(prior.secondaryQueryIntentClass?.rawValue ?? "nil") " +
            "confidence=\(String(format: "%.2f", prior.confidence)) " +
            "ambiguity=\(prior.ambiguity.rawValue) " +
            "llm=\(prior.shouldEscalateToLLM)"
        )

        let escalation = escalationDecision(
            for: prior,
            sourceText: normalized,
            threadContext: threadContext
        )

        exchInterpLog(
            "escalation decision " +
            "action=\(escalation.action.rawValue) " +
            "reason=\(escalation.reason) " +
            "confidence=\(String(format: "%.2f", escalation.priorConfidence)) " +
            "ambiguity=\(escalation.priorAmbiguity.rawValue) " +
            "hits=\(escalation.exemplarHitCount)"
        )

        switch escalation.action {
        case .acceptPrior:
            return buildPriorOnlyInterpretationResult(
                sourceText: normalized,
                threadContext: threadContext,
                prior: prior
            )

        case .askClarification:
            let intent = buildIntentFromPrior(
                sourceText: normalized,
                threadContext: threadContext,
                prior: prior
            )

            let posture = fallbackPosture(
                from: normalized,
                mode: intent.mode
            )

            let semanticTags = buildSemanticTags(
                sourceText: normalized,
                prior: prior
            )
            let discoveryKeywords = buildDiscoveryKeywords(
                sourceText: normalized,
                prior: prior
            )
            let targetTags = buildTargetTags(
                sourceText: normalized,
                prior: prior
            )

            let facets = buildFacets(
                sourceText: normalized,
                intent: intent,
                posture: posture,
                threadContext: threadContext,
                prior: prior,
                semanticTags: semanticTags,
                discoveryKeywords: discoveryKeywords,
                targetTags: targetTags
            )
            let canonicalCompiled = compileCanonicalSearchArtifacts(
                sourceText: normalized,
                intent: intent,
                threadContext: threadContext,
                semanticTags: semanticTags,
                discoveryKeywords: discoveryKeywords,
                targetTags: targetTags,
                facets: facets
            )

            return .needsClarification(
                ExchangeFailure.understanding(
                    summary: buildPriorSummary(
                        sourceText: normalized,
                        prior: prior,
                        readiness: .needsClarification
                    ),
                    whatHappened: "The request is too ambiguous to route confidently.",
                    question: clarificationQuestion(for: intent),
                    reasonCode: "ambiguous_request"
                ),
                draftIntent: canonicalCompiled.intent,
                draftPosture: posture,
                draftFacets: canonicalCompiled.facets
            )

        case .surfaceAmbiguity:
            return buildPriorOnlyInterpretationResult(
                sourceText: normalized,
                threadContext: threadContext,
                prior: prior.withLLMEscalation(false)
            )

        case .llmNormalize:
            break
        }

        exchInterpLog("prior escalates to provider")

        let response: ExchangeIntelligenceInterpretationResponse
        do {
            response = try await loadInterpretationResponse(
                ExchangeIntelligenceInterpretationRequest(
                    userText: normalized,
                    threadContext: threadContext
                )
            )

            exchInterpLog(
                "provider interpret ok " +
                "mode=\(response.mode.rawValue) " +
                "kind=\(response.kind.rawValue) " +
                "confidence=\(String(format: "%.2f", response.confidence)) " +
                "needsClarification=\(response.needsClarification) " +
                "shouldDiscover=\(response.shouldDiscover) " +
                "shouldDraft=\(response.shouldDraft)"
            )
        } catch {
            exchInterpLog("provider interpret FAILED err=\(error)")
            return buildPriorOnlyInterpretationResult(
                sourceText: normalized,
                threadContext: threadContext,
                prior: prior
            )
        }

        guard let sanitized = sanitizeInterpretationResponse(response) else {
            exchInterpLog("sanitize rejected provider response -> fallback prior-only path")
            return buildPriorOnlyInterpretationResult(
                sourceText: normalized,
                threadContext: threadContext,
                prior: prior
            )
        }

        return await buildInterpretationResult(
            from: sanitized,
            sourceText: normalized,
            threadContext: threadContext,
            prior: prior,
            forceNoClarification: false,
            forceDiscover: false,
            forceDraftOff: false,
            skipCanonicalReExtract: canonicalExtractorAlreadyAttempted,
            entrySurface: entrySurface,
            preservedCompactSearchArtifact: preservedCompactSearchArtifact
        )
    }

    func bestNonEmpty(_ values: String?...) -> String? {
        values.first { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
    }

    func buildClarificationMergedUserText(
        originalThread: ExchangeThread,
        answer: String
    ) -> String {
        let base = [
            originalThread.intent.title,
            originalThread.intent.targetDescription,
            originalThread.intent.objective
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        guard !answer.isEmpty else { return base }

        if base.isEmpty {
            return answer
        }

        return """
        Original request:
        \(base)

        Clarification answer:
        \(answer)
        """
    }

    public func interpretClarificationAnswer(
        userText: String,
        originalThread: ExchangeThread,
        clarificationAnswer: String
    ) async -> InterpretedRequest {
        let normalized = normalizeInput(userText)
        let trimmedAnswer = normalizeInput(clarificationAnswer)

        exchInterpLog(
            "interpretClarificationAnswer enter " +
            "chars=\(normalized.count) " +
            "threadID=\(originalThread.id.uuidString) " +
            "answerChars=\(trimmedAnswer.count)"
        )

        let context = ThreadContext(
            threadID: originalThread.id,
            modeHint: originalThread.mode,
            priorIntentTitle: originalThread.intent.title,
            selectedCounterpartyID: originalThread.selectedCounterpartyID
        )

        let merged = buildClarificationMergedUserText(
            originalThread: originalThread,
            answer: trimmedAnswer.isEmpty ? normalized : trimmedAnswer
        )

        let structural = buildStructuralGate(
            sourceText: merged,
            threadContext: context
        )

        let prior = await buildInterpretationPrior(
            sourceText: merged,
            structural: structural,
            threadContext: context
        )

        exchInterpLog(
            "clarification prior built " +
            "primaryClass=\(prior.primaryQueryIntentClass.rawValue) " +
            "surface=\(prior.primarySurfacePreference.rawValue) " +
            "confidence=\(String(format: "%.2f", prior.confidence)) " +
            "ambiguity=\(prior.ambiguity.rawValue) " +
            "llm=\(prior.shouldEscalateToLLM)"
        )

        let clarificationEscalation = escalationDecision(
            for: prior,
            sourceText: merged,
            threadContext: context
        )

        exchInterpLog(
            "clarification escalation decision " +
            "action=\(clarificationEscalation.action.rawValue) " +
            "reason=\(clarificationEscalation.reason) " +
            "confidence=\(String(format: "%.2f", clarificationEscalation.priorConfidence)) " +
            "ambiguity=\(clarificationEscalation.priorAmbiguity.rawValue) " +
            "hits=\(clarificationEscalation.exemplarHitCount)"
        )

        if clarificationEscalation.action == .acceptPrior {
            exchInterpLog("clarification strong prior accepted")
            return forcedClarificationPriorRequest(
                sourceText: trimmedAnswer.isEmpty ? normalized : trimmedAnswer,
                originalThread: originalThread,
                prior: prior
            )
        }

        do {
            let response = try await loadInterpretationResponse(
                ExchangeIntelligenceInterpretationRequest(
                    userText: merged,
                    threadContext: context
                )
            )

            exchInterpLog(
                "provider interpret clarification-resume ok " +
                "mode=\(response.mode.rawValue) " +
                "kind=\(response.kind.rawValue) " +
                "confidence=\(String(format: "%.2f", response.confidence)) " +
                "needsClarification=\(response.needsClarification) " +
                "shouldDiscover=\(response.shouldDiscover) " +
                "shouldDraft=\(response.shouldDraft)"
            )

            if let sanitized = sanitizeInterpretationResponse(response) {
                switch await buildInterpretationResult(
                    from: sanitized,
                    sourceText: merged,
                    threadContext: context,
                    prior: prior,
                    forceNoClarification: true,
                    forceDiscover: true,
                    forceDraftOff: true
                ) {
                case .interpreted(let request):
                    return request
                case .needsClarification:
                    break
                }
            }

            exchInterpLog("clarification sanitize/build fell through -> prior fallback")
            return forcedClarificationPriorRequest(
                sourceText: trimmedAnswer.isEmpty ? normalized : trimmedAnswer,
                originalThread: originalThread,
                prior: prior
            )
        } catch {
            exchInterpLog("provider interpret clarification-resume FAILED err=\(error)")
            return forcedClarificationPriorRequest(
                sourceText: trimmedAnswer.isEmpty ? normalized : trimmedAnswer,
                originalThread: originalThread,
                prior: prior
            )
        }
    }
}

public extension ExchangeInterpreter {
    /// Where the interpreted text was entered (search composer vs thread continuation).
    enum InterpretationEntrySurface: String, Codable, Sendable, Hashable {
        case searchComposer
        case threadContinuation
        case other
    }

    struct ThreadContext: Codable, Sendable, Hashable {
        public var threadID: ExchangeThread.ID?
        public var modeHint: ExchangeMode?
        public var priorIntentTitle: String?
        public var selectedCounterpartyID: String?

        public init(
            threadID: ExchangeThread.ID? = nil,
            modeHint: ExchangeMode? = nil,
            priorIntentTitle: String? = nil,
            selectedCounterpartyID: String? = nil
        ) {
            self.threadID = threadID
            self.modeHint = modeHint
            self.priorIntentTitle = priorIntentTitle
            self.selectedCounterpartyID = selectedCounterpartyID
        }
    }

    struct InterpretedRequest: Sendable, Hashable {
        public var intent: ExchangeIntent
        public var posture: ExchangePosture
        public var facets: ExchangeIntentFacets

        public var userSummary: String?
        public var userQuestion: String?
        public var userNextStep: String?
        public var shouldDiscover: Bool
        public var shouldDraft: Bool

        public var semanticTags: [String]
        public var discoveryKeywords: [String]
        public var targetTags: [String]

        public var interpretationPrior: ExchangeInterpretationPrior?
        public var interpretationConfidence: Double
        public var needsFullLLMInterpretation: Bool

        public init(
            intent: ExchangeIntent,
            posture: ExchangePosture,
            facets: ExchangeIntentFacets,
            userSummary: String? = nil,
            userQuestion: String? = nil,
            userNextStep: String? = nil,
            shouldDiscover: Bool = true,
            shouldDraft: Bool = false,
            semanticTags: [String] = [],
            discoveryKeywords: [String] = [],
            targetTags: [String] = [],
            interpretationPrior: ExchangeInterpretationPrior? = nil,
            interpretationConfidence: Double = 0.0,
            needsFullLLMInterpretation: Bool = false
        ) {
            self.intent = intent
            self.posture = posture
            self.facets = facets
            self.userSummary = userSummary
            self.userQuestion = userQuestion
            self.userNextStep = userNextStep
            self.shouldDiscover = shouldDiscover
            self.shouldDraft = shouldDraft
            self.semanticTags = semanticTags
            self.discoveryKeywords = discoveryKeywords
            self.targetTags = targetTags
            self.interpretationPrior = interpretationPrior
            self.interpretationConfidence = interpretationConfidence
            self.needsFullLLMInterpretation = needsFullLLMInterpretation
        }
    }

    enum InterpretationResult: Sendable, Hashable {
        case interpreted(InterpretedRequest)
        case needsClarification(
            ExchangeFailure,
            draftIntent: ExchangeIntent? = nil,
            draftPosture: ExchangePosture? = nil,
            draftFacets: ExchangeIntentFacets? = nil
        )

        public var interpretedRequest: InterpretedRequest? {
            switch self {
            case .interpreted(let request):
                return request
            case .needsClarification:
                return nil
            }
        }
    }
}

private extension ExchangeInterpreter {

    struct InterpretationEscalationDecision: Sendable, Hashable {
        enum Action: String, Sendable, Hashable {
            case acceptPrior
            case llmNormalize
            case askClarification
            case surfaceAmbiguity
        }

        var action: Action
        var reason: String
        var priorConfidence: Double
        var priorAmbiguity: ExchangeInterpretationPrior.Ambiguity
        var exemplarHitCount: Int

        init(
            action: Action,
            reason: String,
            priorConfidence: Double,
            priorAmbiguity: ExchangeInterpretationPrior.Ambiguity,
            exemplarHitCount: Int
        ) {
            self.action = action
            self.reason = reason
            self.priorConfidence = priorConfidence
            self.priorAmbiguity = priorAmbiguity
            self.exemplarHitCount = exemplarHitCount
        }
    }

    // MARK: - Structural gate

    func buildStructuralGate(
        sourceText: String,
        threadContext: ThreadContext?
    ) -> ExchangeInterpretationPrior.StructuralGate {
        let lower = sourceText.lowercased()

        let urgencyBias: ExchangeInterpretationPrior.UrgencyBias? = {
            if containsAny(lower, ["asap", "urgent", "immediately", "today", "right now"]) {
                return .immediate
            }
            if containsAny(lower, ["soon", "quickly"]) {
                return .high
            }
            if containsAny(lower, ["whenever", "no rush"]) {
                return .low
            }
            return .normal
        }()

        let privacyBias: ExchangeInterpretationPrior.PrivacyBias? = {
            if containsAny(lower, ["private", "discreet", "confidential", "do not share too much"]) {
                return .guarded
            }
            if containsAny(lower, ["open", "public", "broadly"]) {
                return .open
            }
            return .balanced
        }()

        let gate = ExchangeInterpretationPrior.StructuralGate(
            selectedCounterpartyPresent: threadContext?.selectedCounterpartyID != nil,
            isResumingExistingThread: threadContext?.threadID != nil,
            literalConstraints: extractLiteralConstraints(from: sourceText),
            urgencyBias: urgencyBias,
            privacyBias: privacyBias
        )

        validateStructuralGate(gate)
        return gate
    }

    func validateStructuralGate(
        _ gate: ExchangeInterpretationPrior.StructuralGate
    ) {
        #if DEBUG
        for constraint in gate.literalConstraints {
            let key = constraint.key.lowercased()
            precondition(
                key.contains("location") ||
                key.contains("place") ||
                key.contains("fulfillment") ||
                key.contains("timing") ||
                key.contains("time") ||
                key.contains("privacy"),
                "Structural gate leaked semantic constraint: \(constraint.key)"
            )
        }
        #endif
    }

    // MARK: - Canonical search intent first (searchIntentExtraction)

    /// Runs `searchIntentExtraction` before prior/escalation/provider when the request is an open discovery/search/purchase shape.
    /// Returns a finished `InterpretationResult` on success; `nil` falls through to the legacy staged provider path.
    func tryCanonicalSearchIntentFirst(
        sourceText: String,
        structural: ExchangeInterpretationPrior.StructuralGate,
        threadContext: ThreadContext?,
        entrySurface: InterpretationEntrySurface,
        didAttemptExtraction: inout Bool,
        preservedCompactSearchArtifact: inout PreservedCompactSearchArtifact?
    ) async -> InterpretationResult? {
        guard asyncSearchIntentExtractor != nil else {
            exchInterpLog("canonicalSearchIntentFirst skipped reason=no_async_extractor")
            return nil
        }

        let gateDecision = canonicalSearchIntentGateDecision(
            sourceText: sourceText,
            threadContext: threadContext,
            entrySurface: entrySurface
        )
        guard gateDecision.shouldRun else {
            exchInterpLog("canonicalSearchIntentFirst skipped reason=\(gateDecision.skipReason)")
            return nil
        }

        didAttemptExtraction = true
        exchInterpLog("canonicalSearchIntentFirst start reason=\(gateDecision.startReason)")

        guard let asyncSearchIntentExtractor else { return nil }

        let seedIntent = seedIntentForCanonicalSearch(
            sourceText: sourceText,
            threadContext: threadContext
        )
        let canonicalCandidate = await asyncSearchIntentExtractor.extract(
            sourceText: sourceText,
            intent: seedIntent
        )
        let extractionDiag = await asyncSearchIntentExtractor.lastExtractionDiagnostics()

        guard let canonical = canonicalCandidate else {
            if let extractionDiag,
               extractionDiag.source == .heuristicFallback,
               isInfrastructureSearchIntentExtractorFailure(extractionDiag.fallbackReason) {
                let reason = extractionDiag.fallbackReason?.rawValue ?? "unknown"
                exchInterpLog(
                    "canonicalSearchIntentFirst extractor unavailable reason=\(reason)"
                )
                let technicalParts: [String] = [
                    "extractorFallbackReason=\(reason)",
                    extractionDiag.decodeErrorSummary.map { "decode=\($0)" },
                    extractionDiag.repairAttempted ? "repairAttempted=true" : nil,
                    extractionDiag.attemptedLLM ? "attemptedLLM=true" : "attemptedLLM=false"
                ].compactMap { $0 }
                let technicalDetails = technicalParts.joined(separator: " | ")
                return .needsClarification(
                    ExchangeFailure(
                        kind: .understandingFailure,
                        severity: .normal,
                        summary: "Semantic search isn’t ready yet.",
                        whatHappened: "On-device search understanding couldn’t run right now (\(reason)).",
                        whatDidNotHappen: "No external action was taken.",
                        externalEffect: .none,
                        recommendedNextStep: .clarify(
                            question: "Try again in a moment, or rephrase your search briefly."
                        ),
                        reasonCode: "search_intent_extractor_unavailable",
                        technicalDetails: technicalDetails.nilIfBlank,
                        isRetryable: true
                    )
                )
            }

            if let extractionDiag {
                let reason = extractionDiag.fallbackReason?.rawValue ?? extractionDiag.source.rawValue
                exchInterpLog(
                    "canonicalSearchIntentFirst fallthrough reason=\(reason) " +
                    "detail=extractor_nil_non_infrastructure"
                )
                if preservedCompactSearchArtifact == nil,
                   let objectHint = extractionDiag.compactDecodedObjectHint {
                    preservedCompactSearchArtifact = makePreservedCompactSearchArtifact(
                        objectType: objectHint,
                        sourceText: sourceText
                    )
                }
            } else {
                exchInterpLog("canonicalSearchIntentFirst fallback reason=invalidCanonical detail=extractor_nil")
            }
            return nil
        }

        var workingCanonical = canonical
        let materiallyActionable = isMateriallyActionableCanonicalSearchIntent(workingCanonical)
        let routeValidated = hasValidatedExtractedRoute(workingCanonical)
        var earlyReturnReason: String? = {
            if routeValidated { return "validated_route" }
            if materiallyActionable { return "materially_actionable" }
            return nil
        }()

        if routeValidated {
            let routeClass = workingCanonical.extractedRoute?.routeClassRaw ?? "nil"
            let routeConfidence = workingCanonical.extractedRoute?.routeConfidence
                .map { String(format: "%.2f", $0) } ?? "nil"
            exchInterpLog(
                "canonicalSearchIntentFirst routeValidated=true " +
                "routeClass=\(routeClass) " +
                "routeConfidence=\(routeConfidence)"
            )
        } else {
            let legacyRouting = querySurfaceTargetRouting(from: workingCanonical)
            logRouteValidationDiagnostics(canonical: workingCanonical, legacy: legacyRouting)
            exchInterpLog(
                "canonicalSearchIntentFirst routeValidated=false " +
                "reason=\(earlyReturnReason ?? "not_actionable_and_no_validated_route")"
            )
        }

        if earlyReturnReason == nil {
            if let atomicObject = flatSearchIntentMapper.validAtomicObjectForRouteRepair(
                workingCanonical.objectType
            ),
            SearchIntentRouteValidator.shouldDeterministicRouteRepair(
                canonical: workingCanonical,
                validAtomicObject: atomicObject
            ) {
                let beforeRoute = workingCanonical.extractedRoute?.routeClassRaw ?? "nil"
                let beforeSurface = workingCanonical.extractedRoute?.surfacePreferenceRaw ?? "nil"
                workingCanonical = SearchIntentRouteValidator.canonicalWithDeterministicRouteRepair(
                    workingCanonical
                )
                let legacyRouting = querySurfaceTargetRouting(from: workingCanonical)
                let routing = resolveSearchRouting(from: workingCanonical, legacy: legacyRouting)
                workingCanonical = flatSearchIntentMapper.applyOfferSearchObjectLaneDefaults(
                    to: workingCanonical,
                    queryIntentClass: routing.queryClass,
                    surfacePreference: routing.surface
                )
                workingCanonical = ExchangeOfferObjectLane.normalizeActorNounObjectForLiveInterpretation(
                    workingCanonical,
                    source: "deterministicRouteRepair"
                )
                workingCanonical = ExchangeOfferObjectLane.normalizeProductObjectTransactionForLiveInterpretation(
                    workingCanonical,
                    queryIntentClass: routing.queryClass,
                    surfacePreference: routing.surface,
                    source: "deterministicRouteRepair"
                )
                let afterRoute = workingCanonical.extractedRoute?.routeClassRaw ?? routing.queryClass.rawValue
                let afterSurface = workingCanonical.extractedRoute?.surfacePreferenceRaw ?? routing.surface.rawValue
                exchInterpLog(
                    "[CanonicalRouteRepair] source=llmSearchIntent reason=malformedRouteButSemanticObject " +
                    "object=\(atomicObject) beforeRoute=\(beforeRoute) beforeSurface=\(beforeSurface) " +
                    "afterRoute=\(afterRoute) afterSurface=\(afterSurface)"
                )
                exchInterpLog(
                    "[CanonicalFirstAccepted] source=routeRepaired " +
                    "searchIntentObject=\(workingCanonical.objectType ?? atomicObject)"
                )
                exchInterpLog(
                    "[CanonicalFirstBypassProviderFallback] reason=routeRepaired"
                )
                earlyReturnReason = "route_repaired"
            } else {
                preservedCompactSearchArtifact = makePreservedCompactSearchArtifact(
                    from: workingCanonical,
                    sourceText: sourceText
                )
                if let preserved = preservedCompactSearchArtifact {
                    exchInterpLog(
                        "[CompactObjectHintPreserved] object=\(preserved.objectType) " +
                        "source=\(preserved.extractionSource?.rawValue ?? "nil")"
                    )
                }
                exchInterpLog(
                    "canonicalSearchIntentFirst fallback reason=invalidCanonical detail=non_actionable " +
                    "preservedObject=\(preservedCompactSearchArtifact?.objectType ?? "nil")"
                )
                return nil
            }
        }

        guard let earlyReturnReason else { return nil }

        let legacyRouting = querySurfaceTargetRouting(from: workingCanonical)
        let routing = resolveSearchRouting(from: workingCanonical, legacy: legacyRouting)
        let sourceTag = workingCanonical.extractionSource.map(\.rawValue) ?? "legacy"
        let needLabel = workingCanonical.transactionIntent?.rawValue ?? "nil"

        exchInterpLog(
            "canonical search intent accepted " +
            "source=\(sourceTag) " +
            "earlyReturnReason=\(earlyReturnReason) " +
            "routeClass=\(workingCanonical.extractedRoute?.routeClassRaw ?? routing.queryClass.rawValue) " +
            "surfacePreference=\(workingCanonical.extractedRoute?.surfacePreferenceRaw ?? routing.surface.rawValue) " +
            "targetKind=\(workingCanonical.extractedRoute?.targetKindRaw ?? routing.targetKind.rawValue) " +
            "object=\(workingCanonical.objectType ?? "nil") " +
            "need=\(needLabel) " +
            "domain=\(workingCanonical.domainCategory.rawValue) " +
            "routeSource=\(routing.source.rawValue)"
        )

        let result = buildInterpretationResultFromCanonicalSearchIntent(
            canonical: workingCanonical,
            structural: structural,
            sourceText: sourceText,
            threadContext: threadContext
        )

        switch result {
        case .interpreted(let request):
            exchInterpLog(
                "canonicalSearchIntentFirst interpreted " +
                "queryClass=\(request.intent.queryIntentClass.rawValue) " +
                "surfacePreference=\(request.intent.surfacePreference.rawValue) " +
                "targetKind=\(request.facets.targetKind.rawValue) " +
                "needsFullLLMInterpretation=\(request.needsFullLLMInterpretation) " +
                "shouldDiscover=\(request.shouldDiscover)"
            )
        case .needsClarification:
            exchInterpLog(
                "canonicalSearchIntentFirst needsClarification " +
                "queryClass=\(routing.queryClass.rawValue)"
            )
        }

        return result
    }

    struct CanonicalSearchIntentGateDecision: Sendable {
        var shouldRun: Bool
        var startReason: String
        var skipReason: String
    }

    func canonicalSearchIntentGateDecision(
        sourceText: String,
        threadContext: ThreadContext?,
        entrySurface: InterpretationEntrySurface
    ) -> CanonicalSearchIntentGateDecision {
        if threadContext?.selectedCounterpartyID != nil {
            return .init(shouldRun: false, startReason: "counterparty", skipReason: "nonSearchCommand")
        }

        if isExplicitNonSearchCommand(sourceText) {
            return .init(shouldRun: false, startReason: "non_search", skipReason: "nonSearchCommand")
        }

        if entrySurface == .searchComposer {
            return .init(shouldRun: true, startReason: "searchMode", skipReason: "gate_false")
        }

        if matchesDiscoveryPhraseGate(sourceText) {
            return .init(shouldRun: true, startReason: "phraseGate", skipReason: "gate_false")
        }

        return .init(shouldRun: false, startReason: "phrase_gate", skipReason: "gate_false")
    }

    /// Category-agnostic structural gate for open discovery/search/purchase requests (no product vocabulary).
    func shouldUseCanonicalSearchIntentExtractorFirst(
        sourceText: String,
        threadContext: ThreadContext?,
        entrySurface: InterpretationEntrySurface = .other
    ) -> Bool {
        canonicalSearchIntentGateDecision(
            sourceText: sourceText,
            threadContext: threadContext,
            entrySurface: entrySurface
        ).shouldRun
    }

    func isExplicitNonSearchCommand(_ sourceText: String) -> Bool {
        let lower = sourceText.lowercased()

        if lower.hasPrefix("draft ") || lower.contains(" draft ") {
            return true
        }
        if lower.contains("reply to") || lower.contains("a reply") {
            return true
        }

        let nonDiscoveryPhrases = [
            "draft a reply",
            "draft reply",
            "reply to ",
            "reply saying",
            "send this",
            "send that",
            "send it",
            "send now",
            "approve",
            "reject",
            "text them",
            "email them",
            "tell them ",
            "ask them ",
            "follow up with",
            "follow-up with",
            "check status",
            "status of",
            "heard back",
            "hear back",
            "summarize",
            "summary of",
            "settings",
            "profile"
        ]
        return nonDiscoveryPhrases.contains(where: { lower.contains($0) })
    }

    func matchesDiscoveryPhraseGate(_ sourceText: String) -> Bool {
        let lower = sourceText.lowercased()

        let discoveryPhrases = [
            "find me ",
            "find a ",
            "find an ",
            "find someone",
            "find people",
            "find local",
            "find nearby",
            "look for a ",
            "look for an ",
            "looking for a ",
            "looking for an ",
            "looking for ",
            "search for ",
            "search ",
            "need a ",
            "need an ",
            "need someone",
            "need to find",
            "need to get",
            "need to buy",
            "help me find",
            "help me look",
            "show me a ",
            "show me an ",
            "show me ",
            "get me a ",
            "get me an ",
            "get a ",
            "get an ",
            "can you find",
            "could you find",
            "anyone know a ",
            "anyone know an ",
            "recommend a ",
            "recommend an ",
            "recommend someone",
            "suggest a ",
            "suggest an ",
            "locate a ",
            "locate an ",
            "locate ",
            "who does ",
            "want to buy",
            "want to get",
            "want to find",
            "looking to buy",
            "looking to get",
            "looking to hire",
            "shop for ",
            "purchase ",
            "buy a ",
            "buy an ",
            "buy "
        ]

        let actionPhrases = [
            "need ",
            "want ",
            "hire ",
            "book ",
            "source "
        ]

        let seekingPhrases = [
            "seller",
            "provider",
            "service",
            "services",
            "product",
            "products",
            "item",
            "offer",
            "vendor",
            "supplier"
        ]

        return discoveryPhrases.contains(where: { lower.contains($0) })
            || actionPhrases.contains(where: { lower.contains($0) })
            || seekingPhrases.contains(where: { lower.contains($0) })
            || lower.hasPrefix("find ")
            || lower.contains(" find ")
            || lower.hasPrefix("buy ")
            || lower.contains(" buy ")
            || lower.contains("shop for")
    }

    /// Neutral seed intent for async canonical extractors (no heuristic category commitment).
    func seedIntentForCanonicalSearch(
        sourceText: String,
        threadContext: ThreadContext?
    ) -> ExchangeIntent {
        let structural = buildStructuralGate(
            sourceText: sourceText,
            threadContext: threadContext
        )

        return ExchangeIntent(
            kind: .find,
            mode: threadContext?.modeHint ?? .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: String(sourceText.prefix(60)),
            objective: sourceText,
            targetDescription: nil,
            constraints: structural.literalConstraints,
            desiredOutcomes: [.shortlist],
            readiness: .ready,
            interpretationNotes: "canonical search intent seed",
            interpretationConfidence: 0.55,
            needsFullLLMInterpretation: true
        )
    }

    func buildInterpretationResultFromCanonicalSearchIntent(
        canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        structural: ExchangeInterpretationPrior.StructuralGate,
        sourceText: String,
        threadContext: ThreadContext?
    ) -> InterpretationResult {
        let legacyRouting = querySurfaceTargetRouting(from: canonical)
        let routing = resolveSearchRouting(from: canonical, legacy: legacyRouting)
        let extractionSourceTag = canonical.extractionSource.map(\.rawValue) ?? "legacy"
        let authorizesHardPlaceGate = canonical.extractionSource != .heuristicFallback

        let extractionConfidence = canonical.extractionConfidence.map { min(max($0, 0.0), 1.0) }
        let resolvedSurface = routing.surface

        exchInterpLog(
            "canonical search buildInterpretation source=\(extractionSourceTag) " +
            "domain=\(canonical.domainCategory.rawValue) " +
            "objectType=\(canonical.objectType ?? "nil") " +
            "places=\(canonical.places.map(\.normalizedText).joined(separator: "|")) " +
            "extractionConfidence=\(extractionConfidence.map { String(format: "%.2f", $0) } ?? "nil") " +
            "routeSource=\(routing.source.rawValue)"
        )

        let fulfillmentBias: ExchangeIntentFacets.FulfillmentMode? =
            canonical.places.isEmpty ? nil : .localPreferred

        let ecMidBand = extractionConfidence.map { $0 >= 0.55 && $0 < 0.80 } ?? false

        let priorNotes: String = {
            guard let src = canonical.extractionSource else {
                return "llm-first canonical search"
            }
            var line = "llm-first canonical search source=\(src.rawValue)"
            if let ec = extractionConfidence {
                line += " extractionConfidence=\(String(format: "%.2f", ec))"
            }
            if ecMidBand, !canonical.clarificationGaps.isEmpty {
                line += " | clarificationGaps=\(canonical.clarificationGaps.prefix(4).joined(separator: ";"))"
            }
            return line
        }()

        let priorConfidence = extractionConfidence ?? 0.9
        let priorAmbiguity: ExchangeInterpretationPrior.Ambiguity = {
            guard let ec = extractionConfidence else { return .low }
            if ec < 0.55 { return .high }
            if ec < 0.80 { return .medium }
            return .low
        }()

        let prior = ExchangeInterpretationPrior(
            structural: structural,
            primaryQueryIntentClass: routing.queryClass,
            primarySurfacePreference: resolvedSurface,
            secondaryQueryIntentClass: nil,
            secondarySurfacePreference: nil,
            targetKindBias: routing.targetKind,
            fulfillmentBias: fulfillmentBias,
            semanticHints: sanitizeRawPhraseList(
                canonical.semanticConcepts + canonical.broadRecallTokens,
                maxCount: 12
            ),
            exemplarHits: [],
            confidence: priorConfidence,
            ambiguity: priorAmbiguity,
            shouldEscalateToLLM: false,
            notes: priorNotes
        )

        var intent = buildIntentFromPrior(
            sourceText: sourceText,
            threadContext: threadContext,
            prior: prior
        )

        if let modeOverride = routing.modeOverride {
            intent.mode = modeOverride
        }

        intent.constraints = mergedConstraints(
            canonical.hardConstraints,
            structural.literalConstraints
        )
        intent.readiness = .ready
        if let ec = extractionConfidence {
            intent.interpretationConfidence = ec
        } else {
            intent.interpretationConfidence = max(intent.interpretationConfidence, 0.9)
        }
        intent.needsFullLLMInterpretation = false
        intent.interpretationNotes = priorNotes

        let posture = fallbackPosture(from: sourceText, mode: intent.mode)

        let semanticTags = buildSemanticTags(sourceText: sourceText, prior: prior)
        let discoveryKeywords = buildDiscoveryKeywords(sourceText: sourceText, prior: prior)
        let targetTags = buildTargetTags(sourceText: sourceText, prior: prior)

        var facets = buildFacets(
            sourceText: sourceText,
            intent: intent,
            posture: posture,
            threadContext: threadContext,
            prior: prior,
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags
        )

        if let mergedTime = mergeCanonicalTimeConstraintDisplayText(canonical) {
            facets.timeText = String(mergedTime.prefix(160))
        }

        let timeSoftConstraints: [ExchangeIntent.Constraint] = canonical.timeConstraints.map {
            ExchangeIntent.Constraint(
                key: "timeConstraint",
                value: $0.text,
                isHardConstraint: false
            )
        }
        let mergedTimeForSoft = mergeCanonicalTimeConstraintDisplayText(canonical)
        let timeSoftConstraintsWithRollup: [ExchangeIntent.Constraint] = {
            guard let mergedTimeForSoft else { return timeSoftConstraints }
            return timeSoftConstraints + [
                ExchangeIntent.Constraint(
                    key: "timeText",
                    value: mergedTimeForSoft,
                    isHardConstraint: false
                )
            ]
        }()

        let extraSoft = buildFacetSoftPreferences(
            from: canonical.softPreferences + timeSoftConstraintsWithRollup
        )
        facets.softPreferences = sanitizeFacetRequirements(
            facets.softPreferences + extraSoft,
            maxCount: 24
        )

        let compiledRails = compileLegacyRails(from: canonical, intent: intent)
        intent.targetDescription = compiledRails.targetDescription ?? intent.targetDescription

        let actorNormalized = ExchangeOfferObjectLane.normalizeActorNounObjectForLiveInterpretation(
            canonical,
            source: "liveInterpretation"
        )
        let normalizedCanonical = ExchangeOfferObjectLane.normalizeProductObjectTransactionForLiveInterpretation(
            actorNormalized,
            source: "liveInterpretation"
        )
        facets.searchIntent = normalizedCanonical
        facets.queryIntentClass = intent.queryIntentClass
        facets.surfacePreference = intent.surfacePreference
        facets.locationText = compiledRails.locationText
        facets.placeName = compiledRails.placeName
        facets.regionTerms = compiledRails.regionTerms
        facets.providerTerms = compiledRails.providerTerms
        facets.capabilityTerms = compiledRails.capabilityTerms
        facets.affinityTerms = compiledRails.affinityTerms

        let keywordRails = canonicalAtomicKeywordRails(from: canonical)
        facets.primaryKeywords = sanitizeRawPhraseList(keywordRails, maxCount: 12)
        facets.secondaryKeywords = sanitizeRawPhraseList(
            canonicalSecondaryKeywordRails(from: canonical),
            maxCount: 10
        )

        let anyHardPlace = canonical.places.contains(where: \.isHard)
        if let place = compiledRails.placeName {
            facets.explicitRegionRequired = anyHardPlace && authorizesHardPlaceGate
            facets.softLocationTerms = sanitizeRawPhraseList([place], maxCount: 8)
        } else if let locationText = compiledRails.locationText {
            facets.explicitRegionRequired = anyHardPlace && authorizesHardPlaceGate
            facets.softLocationTerms = sanitizeRawPhraseList([locationText], maxCount: 8)
        } else {
            facets.explicitRegionRequired = false
            facets.softLocationTerms = []
        }

        if let locationRequirement = ExchangeLocationRequirementBuilder.build(
            from: canonical,
            sourceText: sourceText,
            extractionSource: canonical.extractionSource?.rawValue ?? "canonical"
        ) {
            ExchangeLocationRequirementMapping.applyToFacets(locationRequirement, facets: &facets)
            if locationRequirement.strictness == .required {
                facets.explicitRegionRequired = true
                facets.hardRegionIDs = []
            }
        }

        applyNoPlaceLocalServiceDiscoveryDefaults(
            facets: &facets,
            canonical: canonical,
            intent: intent
        )

        let mergedSemanticTags = sanitizeRawPhraseList(
            semanticTags + compiledRails.semanticTags,
            maxCount: 12
        )
        let mergedDiscoveryKeywords = sanitizeRawPhraseList(keywordRails, maxCount: 16)
        let mergedTargetTags = sanitizeRawPhraseList(
            targetTags + compiledRails.targetTags,
            maxCount: 10
        )

        if let ec = extractionConfidence, ec < 0.55, !canonical.clarificationGaps.isEmpty {
            let gapsSnippet = canonical.clarificationGaps.prefix(3).joined(separator: "; ")
            return .needsClarification(
                ExchangeFailure.understanding(
                    summary: "I need one quick detail to search accurately.",
                    whatHappened: "Some specifics were not explicit enough to lock the search.",
                    question: "Can you clarify: \(gapsSnippet)?",
                    reasonCode: "under_specified_request"
                ),
                draftIntent: intent,
                draftPosture: posture,
                draftFacets: facets
            )
        }

        let needsClarification =
            intent.readiness != .ready ||
            shouldClarify(
                sourceText: sourceText,
                intent: intent,
                confidence: intent.interpretationConfidence,
                threadContext: threadContext,
                readiness: intent.readiness
            )

        let shouldDiscover =
            !needsClarification &&
            computeShouldDiscover(
                sourceText: sourceText,
                intent: intent,
                threadContext: threadContext
            )

        let shouldDraft = false

        if needsClarification {
            return .needsClarification(
                ExchangeFailure.understanding(
                    summary: buildPriorSummary(
                        sourceText: sourceText,
                        prior: prior,
                        readiness: intent.readiness
                    ),
                    whatHappened: "The canonical search parse still needs one more detail before proceeding.",
                    question: clarificationQuestion(for: intent),
                    reasonCode: "under_specified_request"
                ),
                draftIntent: intent,
                draftPosture: posture,
                draftFacets: facets
            )
        }

        return .interpreted(
            InterpretedRequest(
                intent: intent,
                posture: posture,
                facets: facets,
                userSummary: buildPriorSummary(
                    sourceText: sourceText,
                    prior: prior,
                    readiness: intent.readiness
                ),
                userQuestion: nil,
                userNextStep: buildPriorNextStep(
                    queryClass: intent.queryIntentClass,
                    hasSelectedCounterparty: prior.structural.selectedCounterpartyPresent
                ),
                shouldDiscover: shouldDiscover,
                shouldDraft: shouldDraft,
                semanticTags: mergedSemanticTags,
                discoveryKeywords: mergedDiscoveryKeywords,
                targetTags: mergedTargetTags,
                interpretationPrior: prior,
                interpretationConfidence: intent.interpretationConfidence,
                needsFullLLMInterpretation: false
            )
        )
    }

    func resolveSearchRouting(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        legacy: (
            queryClass: ExchangeIntent.QueryIntentClass,
            surface: ExchangeIntent.SurfacePreference,
            targetKind: ExchangeIntentFacets.TargetKind
        )
    ) -> SearchIntentRouteValidator.ResolvedSearchRouting {
        SearchIntentRouteValidator.resolve(from: canonical, legacy: legacy).routing
    }

    func hasValidatedExtractedRoute(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        let legacy = querySurfaceTargetRouting(from: canonical)
        return resolveSearchRouting(from: canonical, legacy: legacy).source == .llmRoute
    }

    func logRouteValidationDiagnostics(
        canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        legacy: (
            queryClass: ExchangeIntent.QueryIntentClass,
            surface: ExchangeIntent.SurfacePreference,
            targetKind: ExchangeIntentFacets.TargetKind
        )
    ) {
        let route = canonical.extractedRoute
        let resolved = SearchIntentRouteValidator.resolve(from: canonical, legacy: legacy)
        let extractedMode = route?.modeRaw ?? "nil"
        let routeConfidence = route?.routeConfidence.map { String(format: "%.2f", $0) } ?? "nil"
        let rejection = resolved.rejectionReason?.rawValue ?? "accepted"
        exchInterpLog(
            "routeValidationDiagnostics " +
            "extractedRouteClass=\(route?.routeClassRaw ?? "nil") " +
            "extractedSurface=\(route?.surfacePreferenceRaw ?? "nil") " +
            "extractedTargetKind=\(route?.targetKindRaw ?? "nil") " +
            "extractedMode=\(extractedMode) " +
            "routeConfidence=\(routeConfidence) " +
            "legacyQueryClass=\(legacy.queryClass.rawValue) " +
            "legacySurface=\(legacy.surface.rawValue) " +
            "legacyTargetKind=\(legacy.targetKind.rawValue) " +
            "resolvedSource=\(resolved.routing.source.rawValue) " +
            "resolvedQueryClass=\(resolved.routing.queryClass.rawValue) " +
            "resolvedTargetKind=\(resolved.routing.targetKind.rawValue) " +
            "rejectionCategory=\(rejection)"
        )
    }

    func querySurfaceTargetRouting(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> (
        queryClass: ExchangeIntent.QueryIntentClass,
        surface: ExchangeIntent.SurfacePreference,
        targetKind: ExchangeIntentFacets.TargetKind
    ) {
        SearchIntentRouteValidator.legacyQuerySurfaceTargetRouting(from: canonical)
    }

    func mergeCanonicalTimeConstraintDisplayText(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> String? {
        let parts = canonical.timeConstraints
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "; ").nilIfBlank
    }

    func sanitizeFacetRequirements(
        _ values: [ExchangeIntentFacets.Requirement],
        maxCount: Int
    ) -> [ExchangeIntentFacets.Requirement] {
        var seen = Set<String>()
        var out: [ExchangeIntentFacets.Requirement] = []
        for req in values {
            let key = "\(req.key.lowercased())|\(req.value.lowercased())"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(req)
            if out.count >= maxCount { break }
        }
        return out
    }

    func resolvedQueryIntentClass(
        from response: ExchangeIntelligenceInterpretationResponse,
        fallback prior: ExchangeInterpretationPrior
    ) -> ExchangeIntent.QueryIntentClass {
        response.queryIntentClass ?? prior.primaryQueryIntentClass
    }

    func resolvedSurfacePreference(
        from response: ExchangeIntelligenceInterpretationResponse,
        fallback prior: ExchangeInterpretationPrior
    ) -> ExchangeIntent.SurfacePreference {
        response.surfacePreference ?? prior.primarySurfacePreference
    }

    func escalationDecision(
        for prior: ExchangeInterpretationPrior,
        sourceText: String,
        threadContext: ThreadContext?
    ) -> InterpretationEscalationDecision {
        if prior.structural.selectedCounterpartyPresent {
            return .init(
                action: .acceptPrior,
                reason: "selected_counterparty_present",
                priorConfidence: prior.confidence,
                priorAmbiguity: prior.ambiguity,
                exemplarHitCount: 0
            )
        }

        if prior.hasStrongPrimary {
            return .init(
                action: .acceptPrior,
                reason: "strong_prior",
                priorConfidence: prior.confidence,
                priorAmbiguity: prior.ambiguity,
                exemplarHitCount: 0
            )
        }

        if prior.confidence < 0.40 {
            return .init(
                action: .llmNormalize,
                reason: "very_low_prior_confidence",
                priorConfidence: prior.confidence,
                priorAmbiguity: prior.ambiguity,
                exemplarHitCount: 0
            )
        }

        if prior.ambiguity == .high {
            return .init(
                action: .llmNormalize,
                reason: "high_ambiguity_needs_normalization",
                priorConfidence: prior.confidence,
                priorAmbiguity: prior.ambiguity,
                exemplarHitCount: 0
            )
        }

        if prior.confidence < 0.62 {
            return .init(
                action: .llmNormalize,
                reason: "medium_confidence_needs_normalization",
                priorConfidence: prior.confidence,
                priorAmbiguity: prior.ambiguity,
                exemplarHitCount: 0
            )
        }

        return .init(
            action: .surfaceAmbiguity,
            reason: "mixed_signal_without_safe_commitment",
            priorConfidence: prior.confidence,
            priorAmbiguity: prior.ambiguity,
            exemplarHitCount: 0
        )
    }

    func extractLiteralConstraints(
        from text: String
    ) -> [ExchangeIntent.Constraint] {
        let lower = text.lowercased()
        var output: [ExchangeIntent.Constraint] = []

        if containsAny(lower, ["must be local", "only local", "local only", "in person only", "onsite only", "on site only"]) {
            output.append(.init(key: "fulfillment", value: "local-only", isHardConstraint: true))
        }

        if containsAny(lower, ["remote only", "virtual only"]) {
            output.append(.init(key: "fulfillment", value: "remote-only", isHardConstraint: true))
        }

        if containsAny(lower, ["ship only", "shippable only"]) {
            output.append(.init(key: "fulfillment", value: "shippable", isHardConstraint: true))
        }

        if containsAny(lower, ["digital only", "download only", "online only"]) {
            output.append(.init(key: "fulfillment", value: "digital-delivery", isHardConstraint: true))
        }

        if containsAny(lower, ["asap", "urgent", "immediately", "today"]) {
            output.append(.init(key: "timing", value: "urgent", isHardConstraint: true))
        }

        if containsAny(lower, ["private", "discreet", "confidential", "do not share too much"]) {
            output.append(.init(key: "privacy", value: "guarded", isHardConstraint: true))
        }

        if let location = inferLocationText(from: text)?.nilIfBlank {
            output.append(.init(key: "locationText", value: location, isHardConstraint: false))
        }

        if let timeText = inferTimeText(from: text)?.nilIfBlank {
            output.append(.init(key: "timeText", value: timeText, isHardConstraint: false))
        }

        return sanitizeConstraints(output)
    }

    // MARK: - Interpretation prior

    func buildInterpretationPrior(
        sourceText: String,
        structural: ExchangeInterpretationPrior.StructuralGate,
        threadContext: ThreadContext?
    ) async -> ExchangeInterpretationPrior {
        if structural.selectedCounterpartyPresent {
            let lane = directLanePrior(
                sourceText: sourceText,
                structural: structural
            )

            exchInterpLog(
                "prior structural-direct " +
                "class=\(lane.primaryQueryIntentClass.rawValue) " +
                "surface=\(lane.primarySurfacePreference.rawValue)"
            )

            return lane
        }

        let fallback = fallbackPriorWithoutRetriever(
            sourceText: sourceText,
            structural: structural,
            threadContext: threadContext
        )

        exchInterpLog(
            "prior fallback-no-exemplars " +
            "class=\(fallback.primaryQueryIntentClass.rawValue) " +
            "surface=\(fallback.primarySurfacePreference.rawValue) " +
            "confidence=\(String(format: "%.2f", fallback.confidence)) " +
            "ambiguity=\(fallback.ambiguity.rawValue)"
        )

        return fallback
    }

    func directLanePrior(
        sourceText: String,
        structural: ExchangeInterpretationPrior.StructuralGate
    ) -> ExchangeInterpretationPrior {
        let lower = sourceText.lowercased()

        let queryClass: ExchangeIntent.QueryIntentClass = {
            if containsAny(lower, ["status", "update", "heard back", "hear back", "progress"]) {
                return .statusCheck
            }
            if containsAny(lower, ["follow up", "follow-up", "check back"]) {
                return .followUp
            }
            return .directOutreach
        }()

        return ExchangeInterpretationPrior(
            structural: structural,
            primaryQueryIntentClass: queryClass,
            primarySurfacePreference: .mixed,
            targetKindBias: .secretaryNode,
            fulfillmentBias: nil,
            semanticHints: [],
            exemplarHits: [],
            confidence: 0.96,
            ambiguity: .low,
            shouldEscalateToLLM: false,
            notes: "structural direct lane"
        )
    }

    func fallbackPriorWithoutRetriever(
        sourceText: String,
        structural: ExchangeInterpretationPrior.StructuralGate,
        threadContext: ThreadContext?
    ) -> ExchangeInterpretationPrior {
        let lower = sourceText.lowercased()

        let queryClass: ExchangeIntent.QueryIntentClass = {
            if containsAny(lower, ["quote", "estimate", "pricing", "bid"]) {
                return .providerSearch
            }

            if containsAny(lower, [
                "lesson", "lessons",
                "coach", "coaching",
                "teacher", "teachers",
                "tutor", "tutors",
                "instructor", "instructors",
                "class", "classes",
                "trainer", "trainers",
                "repair", "install", "installer", "installation",
                "contractor", "service", "services",
                "supplier", "provider"
            ]) {
                return .providerSearch
            }

            if containsAny(lower, ["dating", "date", "relationship", "single"]) {
                return .relationshipSearch
            }

            if containsAny(lower, ["friend", "friends", "buddy", "buddies"]) {
                return .socialAffinitySearch
            }

            if containsAny(lower, ["collaborate", "collaboration", "partner", "work together"]) {
                return .collaborationSearch
            }

            if containsAny(lower, ["introduce", "intro", "connect me with"]) {
                return .capabilitySearch
            }

            return .generalDiscovery
        }()

        let surfacePreference: ExchangeIntent.SurfacePreference = {
            switch queryClass {
            case .providerSearch, .offerSearch:
                return .offer
            case .capabilitySearch, .collaborationSearch:
                return .capability
            case .socialAffinitySearch, .relationshipSearch:
                return .affinity
            case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
                return .mixed
            }
        }()

        let confidence: Double = {
            switch queryClass {
            case .providerSearch:
                return 0.46
            case .capabilitySearch, .collaborationSearch, .socialAffinitySearch, .relationshipSearch:
                return 0.42
            case .generalDiscovery:
                return 0.24
            case .offerSearch, .directOutreach, .followUp, .statusCheck:
                return 0.34
            }
        }()

        let ambiguity: ExchangeInterpretationPrior.Ambiguity = {
            switch queryClass {
            case .providerSearch:
                return .medium
            case .capabilitySearch, .collaborationSearch, .socialAffinitySearch, .relationshipSearch:
                return .medium
            case .generalDiscovery:
                return .high
            case .offerSearch, .directOutreach, .followUp, .statusCheck:
                return .high
            }
        }()

        let targetKindBias: ExchangeIntentFacets.TargetKind? = {
            switch queryClass {
            case .providerSearch, .offerSearch:
                return .provider
            case .capabilitySearch, .collaborationSearch:
                return .business
            case .socialAffinitySearch, .relationshipSearch:
                return .person
            case .directOutreach, .followUp, .statusCheck:
                return structural.selectedCounterpartyPresent ? .secretaryNode : .person
            case .generalDiscovery:
                return structural.selectedCounterpartyPresent ? .secretaryNode : nil
            }
        }()

        let fulfillmentBias: ExchangeIntentFacets.FulfillmentMode? = {
            if containsAny(lower, ["must be local", "only local", "local only", "in person only", "onsite only", "on site only"]) {
                return .localOnly
            }
            if containsAny(lower, ["remote only", "virtual only", "zoom only"]) {
                return .remoteFriendly
            }
            if containsAny(lower, ["ship only", "shippable only"]) {
                return .shippable
            }
            if containsAny(lower, ["digital only", "download only", "online only"]) {
                return .digitalDelivery
            }
            if inferLocationText(from: sourceText) != nil || inferPlaceName(from: sourceText) != nil {
                return .localPreferred
            }
            return nil
        }()

        let semanticHints = buildFallbackSemanticHints(
            sourceText: sourceText,
            queryClass: queryClass
        )

        let notes = buildPriorNotes(
            sourceText: sourceText,
            threadContext: threadContext,
            confidence: confidence,
            ambiguity: ambiguity
        )

        return ExchangeInterpretationPrior(
            structural: structural,
            primaryQueryIntentClass: queryClass,
            primarySurfacePreference: surfacePreference,
            secondaryQueryIntentClass: nil,
            secondarySurfacePreference: nil,
            targetKindBias: targetKindBias,
            fulfillmentBias: fulfillmentBias,
            semanticHints: semanticHints,
            exemplarHits: [],
            confidence: confidence,
            ambiguity: ambiguity,
            shouldEscalateToLLM: true,
            notes: notes
        )
    }

    func buildFallbackSemanticHints(
        sourceText: String,
        queryClass: ExchangeIntent.QueryIntentClass
    ) -> [String] {
        let lower = sourceText.lowercased()
        var values: [String] = []

        switch queryClass {
        case .providerSearch, .offerSearch:
            if containsAny(lower, ["swim", "swimming"]) { values.append("swimming") }
            if containsAny(lower, ["teacher", "teachers"]) { values.append("teacher") }
            if containsAny(lower, ["coach", "coaches"]) { values.append("coach") }
            if containsAny(lower, ["tutor", "tutors"]) { values.append("tutor") }
            if containsAny(lower, ["instructor", "instructors"]) { values.append("instructor") }
            if containsAny(lower, ["lesson", "lessons"]) { values.append("lesson") }
            if containsAny(lower, ["class", "classes"]) { values.append("class") }
            if containsAny(lower, ["trainer", "trainers"]) { values.append("trainer") }
            if containsAny(lower, ["repair"]) { values.append("repair") }
            if containsAny(lower, ["contractor"]) { values.append("contractor") }

        case .capabilitySearch, .collaborationSearch:
            if containsAny(lower, ["ai"]) { values.append("ai") }
            if containsAny(lower, ["collaborate", "collaboration"]) { values.append("collaboration") }
            if containsAny(lower, ["partner"]) { values.append("partner") }

        case .socialAffinitySearch, .relationshipSearch:
            if containsAny(lower, ["swim", "swimming"]) { values.append("swimming") }
            if containsAny(lower, ["friend", "friends", "buddy", "buddies"]) { values.append("friendship") }
            if containsAny(lower, ["dating", "date"]) { values.append("dating") }

        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            break
        }

        if let locationText = inferLocationText(from: sourceText) {
            values.append(locationText)
        }

        if let placeName = inferPlaceName(from: sourceText) {
            values.append(placeName)
        }

        return sanitizeRawPhraseList(values, maxCount: 12)
    }

    func buildPriorNotes(
        sourceText: String,
        threadContext: ThreadContext?,
        confidence: Double,
        ambiguity: ExchangeInterpretationPrior.Ambiguity
    ) -> String {
        var parts: [String] = []
        parts.append("fallback prior")
        if let modeHint = threadContext?.modeHint?.rawValue {
            parts.append("modeHint=\(modeHint)")
        }
        parts.append("confidence=\(String(format: "%.2f", confidence))")
        parts.append("ambiguity=\(ambiguity.rawValue)")
        parts.append("source=\(String(sourceText.prefix(80)))")
        return parts.joined(separator: " | ")
    }

    // MARK: - Provider loading

    func loadInterpretationResponse(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse {
        try await intelligenceProvider.interpret(request)
    }

    // MARK: - Prior-only path

    func buildPriorOnlyInterpretationResult(
        sourceText: String,
        threadContext: ThreadContext?,
        prior: ExchangeInterpretationPrior
    ) -> InterpretationResult {
        var intent = buildIntentFromPrior(
            sourceText: sourceText,
            threadContext: threadContext,
            prior: prior
        )

        let posture = fallbackPosture(
            from: sourceText,
            mode: intent.mode
        )

        let semanticTags = buildSemanticTags(
            sourceText: sourceText,
            prior: prior
        )
        let discoveryKeywords = buildDiscoveryKeywords(
            sourceText: sourceText,
            prior: prior
        )
        let targetTags = buildTargetTags(
            sourceText: sourceText,
            prior: prior
        )

        let facets = buildFacets(
            sourceText: sourceText,
            intent: intent,
            posture: posture,
            threadContext: threadContext,
            prior: prior,
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags
        )
        let canonicalCompiled = compileCanonicalSearchArtifacts(
            sourceText: sourceText,
            intent: intent,
            threadContext: threadContext,
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags,
            facets: facets
        )
        intent = canonicalCompiled.intent

        let needsClarification =
            intent.readiness != .ready ||
            shouldClarify(
                sourceText: sourceText,
                intent: intent,
                confidence: intent.interpretationConfidence,
                threadContext: threadContext,
                readiness: intent.readiness
            )

        let shouldDiscover =
            !needsClarification &&
            computeShouldDiscover(
                sourceText: sourceText,
                intent: intent,
                threadContext: threadContext
            )

        let shouldDraft =
            !needsClarification &&
            computeShouldDraft(
                sourceText: sourceText,
                intent: intent,
                threadContext: threadContext
            )

        exchInterpLog(
            "prior-only decision " +
            "queryClass=\(intent.queryIntentClass.rawValue) " +
            "surface=\(intent.surfacePreference.rawValue) " +
            "confidence=\(String(format: "%.2f", intent.interpretationConfidence)) " +
            "needsClarification=\(needsClarification) " +
            "shouldDiscover=\(shouldDiscover) " +
            "shouldDraft=\(shouldDraft)"
        )

        if needsClarification {
            return .needsClarification(
                ExchangeFailure.understanding(
                    summary: buildPriorSummary(
                        sourceText: sourceText,
                        prior: prior,
                        readiness: intent.readiness
                    ),
                    whatHappened: "The request still needs one more detail before I can proceed safely.",
                    question: clarificationQuestion(for: intent),
                    reasonCode: "under_specified_request"
                ),
                draftIntent: intent,
                draftPosture: posture,
                draftFacets: canonicalCompiled.facets
            )
        }

        return .interpreted(
            InterpretedRequest(
                intent: intent,
                posture: posture,
                facets: canonicalCompiled.facets,
                userSummary: buildPriorSummary(
                    sourceText: sourceText,
                    prior: prior,
                    readiness: intent.readiness
                ),
                userQuestion: nil,
                userNextStep: buildPriorNextStep(
                    queryClass: intent.queryIntentClass,
                    hasSelectedCounterparty: prior.structural.selectedCounterpartyPresent
                ),
                shouldDiscover: shouldDiscover,
                shouldDraft: shouldDraft,
                semanticTags: canonicalCompiled.semanticTags,
                discoveryKeywords: canonicalCompiled.discoveryKeywords,
                targetTags: canonicalCompiled.targetTags,
                interpretationPrior: prior,
                interpretationConfidence: intent.interpretationConfidence,
                needsFullLLMInterpretation: intent.needsFullLLMInterpretation
            )
        )
    }

    func buildIntentFromPrior(
        sourceText: String,
        threadContext: ThreadContext?,
        prior: ExchangeInterpretationPrior
    ) -> ExchangeIntent {
        let kind = inferIntentKind(
            sourceText: sourceText,
            prior: prior
        )

        let mode = inferMode(
            sourceText: sourceText,
            prior: prior,
            threadContext: threadContext
        )

        let readiness = inferReadiness(
            sourceText: sourceText,
            prior: prior
        )

        return ExchangeIntent(
            kind: kind,
            mode: mode,
            queryIntentClass: prior.primaryQueryIntentClass,
            surfacePreference: prior.primarySurfacePreference,
            title: buildTitle(
                sourceText: sourceText,
                threadContext: threadContext,
                prior: prior
            ),
            objective: buildObjective(
                sourceText: sourceText,
                kind: kind,
                queryIntentClass: prior.primaryQueryIntentClass
            ),
            targetDescription: inferTargetDescription(
                sourceText: sourceText,
                prior: prior
            ),
            constraints: prior.structural.literalConstraints,
            desiredOutcomes: desiredOutcomes(for: kind),
            readiness: readiness,
            interpretationNotes: prior.notes,
            interpretationConfidence: prior.confidence,
            needsFullLLMInterpretation: prior.shouldEscalateToLLM
        )
    }

    func inferIntentKind(
        sourceText: String,
        prior: ExchangeInterpretationPrior
    ) -> ExchangeIntent.Kind {
        let lower = sourceText.lowercased()

        if prior.structural.selectedCounterpartyPresent {
            switch prior.primaryQueryIntentClass {
            case .followUp:
                return .followUp
            case .statusCheck:
                return .checkStatus
            default:
                return .message
            }
        }

        if containsAny(lower, ["quote", "estimate", "pricing", "bid"]) {
            return .requestQuote
        }
        if containsAny(lower, ["introduce", "intro", "connect me with"]) {
            return .introduce
        }
        if containsAny(lower, ["call", "phone call"]) {
            return .arrangeCall
        }
        if containsAny(lower, ["meeting", "meet"]) {
            return .arrangeMeeting
        }
        if containsAny(lower, ["invite", "invitation"]) {
            return .invite
        }
        if containsAny(lower, ["follow up", "follow-up", "check back"]) {
            return .followUp
        }
        if containsAny(lower, ["status", "update", "heard back", "hear back"]) {
            return .checkStatus
        }
        if containsAny(lower, ["message", "contact", "email", "reach out", "send"]) {
            return .message
        }
        if containsAny(lower, ["plan", "coordinate", "arrange", "schedule"]) {
            return .coordinate
        }
        if containsAny(lower, ["source", "procure"]) {
            return .source
        }
        if containsAny(lower, ["find", "look for", "search", "looking for", "need"]) {
            return .find
        }

        switch prior.primaryQueryIntentClass {
        case .providerSearch, .capabilitySearch, .socialAffinitySearch, .relationshipSearch, .generalDiscovery:
            return .find
        case .offerSearch:
            return .source
        case .collaborationSearch:
            return .coordinate
        case .directOutreach:
            return .message
        case .followUp:
            return .followUp
        case .statusCheck:
            return .checkStatus
        }
    }

    func inferMode(
        sourceText: String,
        prior: ExchangeInterpretationPrior,
        threadContext: ThreadContext?
    ) -> ExchangeMode {
        if let modeHint = threadContext?.modeHint {
            return modeHint
        }

        switch prior.primaryQueryIntentClass {
        case .socialAffinitySearch, .relationshipSearch:
            return .relational
        case .collaborationSearch:
            return .cooperative
        default:
            let lower = sourceText.lowercased()
            if containsAny(lower, ["dating", "date", "relationship", "friend", "social"]) {
                return .relational
            }
            if containsAny(lower, ["collaborate", "collaboration", "partner", "work together"]) {
                return .cooperative
            }
            return .transactional
        }
    }

    func inferReadiness(
        sourceText: String,
        prior: ExchangeInterpretationPrior
    ) -> ExchangeIntent.Readiness {
        if prior.structural.selectedCounterpartyPresent {
            return .ready
        }
        if sourceText.count < 3 {
            return .needsClarification
        }
        if prior.confidence < 0.24 {
            return .needsClarification
        }
        if prior.primaryQueryIntentClass == .generalDiscovery && prior.confidence < 0.58 {
            return .needsClarification
        }
        return .ready
    }

    func buildTitle(
        sourceText: String,
        threadContext: ThreadContext?,
        prior: ExchangeInterpretationPrior
    ) -> String {
        if prior.structural.selectedCounterpartyPresent {
            switch prior.primaryQueryIntentClass {
            case .followUp:
                return "Follow Up"
            case .statusCheck:
                return "Check Status"
            default:
                return "Continue Message"
            }
        }

        switch prior.primaryQueryIntentClass {
        case .providerSearch:
            return "Find Provider"
        case .offerSearch:
            return "Find Offer"
        case .capabilitySearch:
            return "Find Capability Match"
        case .collaborationSearch:
            return "Find Collaboration Match"
        case .socialAffinitySearch:
            return "Find Shared-Interest Match"
        case .relationshipSearch:
            return "Find Relationship Match"
        case .directOutreach:
            return "Send Message"
        case .followUp:
            return "Follow Up"
        case .statusCheck:
            return "Check Status"
        case .generalDiscovery:
            return String(sourceText.prefix(60)).nilIfBlank
                ?? threadContext?.priorIntentTitle
                ?? "Exchange Request"
        }
    }

    func buildObjective(
        sourceText: String,
        kind: ExchangeIntent.Kind,
        queryIntentClass: ExchangeIntent.QueryIntentClass
    ) -> String {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch queryIntentClass {
            case .providerSearch: return "Find a suitable provider."
            case .offerSearch: return "Find a suitable offer."
            case .capabilitySearch: return "Find a suitable capability match."
            case .collaborationSearch: return "Find a suitable collaborator."
            case .socialAffinitySearch: return "Find people with shared interests."
            case .relationshipSearch: return "Find a relationship-oriented match."
            case .directOutreach: return "Prepare the next direct outreach step."
            case .followUp: return "Follow up on the existing thread."
            case .statusCheck: return "Check the status of the existing thread."
            case .generalDiscovery: return "Interpret and coordinate the request."
            }
        }
        return trimmed
    }

    func inferTargetDescription(
        sourceText: String,
        prior: ExchangeInterpretationPrior
    ) -> String? {
        if let firstHint = prior.semanticHints.first, !firstHint.isEmpty {
            return firstHint
        }
        return inferLocationNeutralSnippet(from: sourceText)
    }

    func inferLocationNeutralSnippet(from text: String) -> String? {
        let cleaned = normalizeInput(text)
        guard cleaned.count > 4 else { return nil }
        return String(cleaned.prefix(140)).nilIfBlank
    }

    func desiredOutcomes(for kind: ExchangeIntent.Kind) -> [ExchangeIntent.DesiredOutcome] {
        switch kind {
        case .find, .source:
            return [.shortlist]
        case .introduce:
            return [.intro]
        case .requestQuote:
            return [.quote]
        case .arrangeCall, .arrangeMeeting:
            return [.meeting]
        case .message, .followUp, .checkStatus:
            return [.response]
        case .negotiate, .invite, .coordinate, .plan:
            return [.aligned]
        case .other:
            return [.resolved]
        }
    }

    func buildPriorSummary(
        sourceText: String,
        prior: ExchangeInterpretationPrior,
        readiness: ExchangeIntent.Readiness
    ) -> String {
        let label: String = {
            switch prior.primaryQueryIntentClass {
            case .providerSearch, .offerSearch:
                return "a provider-facing search"
            case .capabilitySearch, .collaborationSearch:
                return "a capability-oriented search"
            case .socialAffinitySearch:
                return "a shared-interest search"
            case .relationshipSearch:
                return "a relationship-oriented search"
            case .directOutreach:
                return "direct outreach"
            case .followUp:
                return "a follow-up request"
            case .statusCheck:
                return "a status check"
            case .generalDiscovery:
                return "general discovery"
            }
        }()

        if readiness == .ready {
            return "I understood this as \(label)."
        }
        return "I understood the general direction as \(label), but I still need one more detail."
    }

    func buildPriorNextStep(
        queryClass: ExchangeIntent.QueryIntentClass,
        hasSelectedCounterparty: Bool
    ) -> String {
        if hasSelectedCounterparty {
            return "I can use that understanding to prepare the next outbound step."
        }

        switch queryClass {
        case .providerSearch, .offerSearch:
            return "I can use that understanding to search public provider and offer surfaces."
        case .capabilitySearch, .collaborationSearch:
            return "I can use that understanding to search public capability surfaces."
        case .socialAffinitySearch, .relationshipSearch:
            return "I can use that understanding to search affinity-oriented public surfaces."
        case .directOutreach, .followUp, .statusCheck:
            return "I can use that understanding to prepare the next coordination step."
        case .generalDiscovery:
            return "I can use that understanding to search across multiple public surfaces."
        }
    }

    // MARK: - Provider path

    func buildInterpretationResult(
        from sanitized: ExchangeIntelligenceInterpretationResponse,
        sourceText: String,
        threadContext: ThreadContext?,
        prior: ExchangeInterpretationPrior,
        forceNoClarification: Bool,
        forceDiscover: Bool,
        forceDraftOff: Bool,
        skipCanonicalReExtract: Bool = false,
        entrySurface: InterpretationEntrySurface = .other,
        preservedCompactSearchArtifact: PreservedCompactSearchArtifact? = nil
    ) async -> InterpretationResult {
        let llmConfidence = clampConfidence(sanitized.confidence)
        let confidence = clampConfidence(max(llmConfidence, prior.confidence * 0.85))

        let canonicalQueryIntentClass = resolvedQueryIntentClass(
            from: sanitized,
            fallback: prior
        )

        let canonicalSurfacePreference = resolvedSurfacePreference(
            from: sanitized,
            fallback: prior
        )

        var intent = ExchangeIntent(
            kind: sanitized.kind,
            mode: sanitized.mode,
            queryIntentClass: canonicalQueryIntentClass,
            surfacePreference: canonicalSurfacePreference,
            title: sanitized.title,
            objective: sanitized.objective,
            targetDescription: sanitized.targetDescription ?? inferTargetDescription(sourceText: sourceText, prior: prior),
            constraints: mergedConstraints(
                sanitized.constraints,
                prior.structural.literalConstraints
            ),
            desiredOutcomes: sanitized.desiredOutcomes,
            readiness: sanitized.readiness,
            interpretationNotes: sanitized.interpretationNotes ?? prior.notes,
            interpretationConfidence: confidence,
            needsFullLLMInterpretation: prior.shouldEscalateToLLM
        )

        let posture = sanitized.inferredPosture.map {
            ExchangePosture(
                urgency: $0.urgency,
                warmth: $0.warmth,
                directness: $0.directness,
                openness: $0.openness,
                commitment: $0.commitment,
                privacy: $0.privacy,
                priceSensitivity: $0.priceSensitivity,
                flexibility: $0.flexibility,
                notes: $0.notes
            )
        } ?? fallbackPosture(from: sourceText, mode: sanitized.mode)

        let semanticTags = sanitizeRawPhraseList(
            sanitized.semanticTags + prior.allSemanticHints,
            maxCount: 12
        )
        let discoveryKeywords = sanitizeRawPhraseList(
            sanitized.discoveryKeywords + [sourceText],
            maxCount: 12
        )
        let targetTags = sanitizeRawPhraseList(
            sanitized.targetTags + prior.allSemanticHints,
            maxCount: 10
        )

        let facets = buildFacets(
            sourceText: sourceText,
            intent: intent,
            posture: posture,
            threadContext: threadContext,
            prior: prior,
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags
        )
        let canonicalCompiled = await compileCanonicalSearchArtifactsAsync(
            sourceText: sourceText,
            intent: intent,
            threadContext: threadContext,
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags,
            facets: facets,
            skipCanonicalReExtract: skipCanonicalReExtract,
            entrySurface: entrySurface
        )
        let mergedCompilation = mergePreservedCompactSearchArtifactIfNeeded(
            artifact: preservedCompactSearchArtifact,
            sourceText: sourceText,
            compilation: canonicalCompiled
        )
        intent = mergedCompilation.intent

        if let canonical = mergedCompilation.facets.searchIntent,
           hasValidatedExtractedRoute(canonical) {
            let legacyRouting = querySurfaceTargetRouting(from: canonical)
            let routing = resolveSearchRouting(from: canonical, legacy: legacyRouting)
            intent.queryIntentClass = routing.queryClass
            intent.surfacePreference = routing.surface
            exchInterpLog(
                "provider path preserved validated canonical route " +
                "queryClass=\(routing.queryClass.rawValue) " +
                "surface=\(routing.surface.rawValue)"
            )
        }

        // Use inclusive upper bound: fallback fast-path often emits exactly 0.45 when needsFull is true.
        if !forceNoClarification && llmConfidence <= 0.45 && prior.confidence < 0.55 {
            let actionable =
                mergedCompilation.facets.searchIntent.map(isMateriallyActionableCanonicalSearchIntent) ?? false
            if !actionable {
                exchInterpLog(
                    "provider low-confidence circuit breaker " +
                    "llmConfidence=\(String(format: "%.2f", llmConfidence)) " +
                    "priorConfidence=\(String(format: "%.2f", prior.confidence))"
                )

                return .needsClarification(
                    ExchangeFailure.understanding(
                        summary: "I can see a few possible directions, but I cannot safely collapse them into one interpretation yet.",
                        whatHappened: "Both the prior and the model response were too weak to justify a confident semantic route.",
                        question: clarificationQuestion(for: intent),
                        reasonCode: "low_confidence_after_escalation"
                    ),
                    draftIntent: intent,
                    draftPosture: posture,
                    draftFacets: mergedCompilation.facets
                )
            }

            exchInterpLog(
                "provider low-confidence bypass actionable canonical searchIntent " +
                "llmConfidence=\(String(format: "%.2f", llmConfidence)) " +
                "priorConfidence=\(String(format: "%.2f", prior.confidence))"
            )
        }

        let computedNeedsClarification =
            sanitized.needsClarification ||
            shouldClarify(
                sourceText: sourceText,
                intent: intent,
                confidence: confidence,
                threadContext: threadContext,
                readiness: sanitized.readiness
            )

        let needsClarification = forceNoClarification ? false : computedNeedsClarification

        let computedShouldDiscover =
            !needsClarification &&
            computeShouldDiscover(
                sourceText: sourceText,
                intent: intent,
                threadContext: threadContext
            )

        let shouldDiscover = forceDiscover ? true : computedShouldDiscover

        let computedShouldDraft =
            !needsClarification &&
            computeShouldDraft(
                sourceText: sourceText,
                intent: intent,
                threadContext: threadContext
            )

        let shouldDraft = forceDraftOff ? false : computedShouldDraft

        exchInterpLog(
            "provider decision " +
            "queryClass=\(intent.queryIntentClass.rawValue) " +
            "surface=\(intent.surfacePreference.rawValue) " +
            "confidence=\(String(format: "%.2f", confidence)) " +
            "needsClarification=\(needsClarification) " +
            "shouldDiscover=\(shouldDiscover) " +
            "shouldDraft=\(shouldDraft)"
        )

        if needsClarification {
            let question =
                sanitized.clarificationQuestion?.nilIfBlank ??
                sanitized.userQuestion?.nilIfBlank ??
                clarificationQuestion(for: intent)

            return .needsClarification(
                ExchangeFailure.understanding(
                    summary: sanitized.userSummary ?? buildPriorSummary(
                        sourceText: sourceText,
                        prior: prior,
                        readiness: intent.readiness
                    ),
                    whatHappened: "The request is still missing a key detail needed to proceed.",
                    question: question,
                    reasonCode: "under_specified_request"
                ),
                draftIntent: intent,
                draftPosture: posture,
                draftFacets: mergedCompilation.facets
            )
        }

        return .interpreted(
            InterpretedRequest(
                intent: intent,
                posture: posture,
                facets: mergedCompilation.facets,
                userSummary: sanitized.userSummary ?? buildPriorSummary(
                    sourceText: sourceText,
                    prior: prior,
                    readiness: intent.readiness
                ),
                userQuestion: forceNoClarification ? nil : sanitized.userQuestion,
                userNextStep: sanitized.userNextStep ?? buildPriorNextStep(
                    queryClass: intent.queryIntentClass,
                    hasSelectedCounterparty: prior.structural.selectedCounterpartyPresent
                ),
                shouldDiscover: shouldDiscover,
                shouldDraft: shouldDraft,
                semanticTags: mergedCompilation.semanticTags,
                discoveryKeywords: mergedCompilation.discoveryKeywords,
                targetTags: mergedCompilation.targetTags,
                interpretationPrior: prior,
                interpretationConfidence: confidence,
                needsFullLLMInterpretation: intent.needsFullLLMInterpretation
            )
        )
    }

    func forcedClarificationPriorRequest(
        sourceText: String,
        originalThread: ExchangeThread,
        prior: ExchangeInterpretationPrior
    ) -> InterpretedRequest {
        let normalized = normalizeInput(sourceText)

        let kind: ExchangeIntent.Kind =
            originalThread.intent.kind == .other
            ? inferIntentKind(sourceText: normalized, prior: prior)
            : originalThread.intent.kind

        var intent = ExchangeIntent(
            kind: kind,
            mode: originalThread.intent.mode,
            queryIntentClass: prior.primaryQueryIntentClass,
            surfacePreference: prior.primarySurfacePreference,
            title: originalThread.intent.title,
            objective: normalized.isEmpty ? originalThread.intent.objective : normalized,
            targetDescription: inferTargetDescription(sourceText: normalized, prior: prior) ?? originalThread.intent.targetDescription,
            constraints: mergedConstraints(
                originalThread.intent.constraints,
                prior.structural.literalConstraints
            ),
            desiredOutcomes: originalThread.intent.desiredOutcomes.isEmpty
                ? desiredOutcomes(for: kind)
                : originalThread.intent.desiredOutcomes,
            readiness: .ready,
            interpretationNotes: prior.notes,
            interpretationConfidence: prior.confidence,
            needsFullLLMInterpretation: prior.shouldEscalateToLLM
        )

        let posture = originalThread.posture

        let semanticTags = sanitizeRawPhraseList(
            (originalThread.interpretation?.semanticTags ?? []) + prior.allSemanticHints,
            maxCount: 12
        )

        let discoveryKeywords = sanitizeRawPhraseList(
            (originalThread.interpretation?.discoveryKeywords ?? []) + [normalized],
            maxCount: 12
        )

        let targetTags = sanitizeRawPhraseList(
            (originalThread.interpretation?.targetTags ?? []) + prior.allSemanticHints,
            maxCount: 10
        )

        let facets = buildFacets(
            sourceText: normalized.isEmpty ? originalThread.intent.objective : normalized,
            intent: intent,
            posture: posture,
            threadContext: .init(
                threadID: originalThread.id,
                modeHint: originalThread.mode,
                priorIntentTitle: originalThread.intent.title,
                selectedCounterpartyID: originalThread.selectedCounterpartyID
            ),
            prior: prior,
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags
        )
        let canonicalCompiled = compileCanonicalSearchArtifacts(
            sourceText: normalized.isEmpty ? originalThread.intent.objective : normalized,
            intent: intent,
            threadContext: .init(
                threadID: originalThread.id,
                modeHint: originalThread.mode,
                priorIntentTitle: originalThread.intent.title,
                selectedCounterpartyID: originalThread.selectedCounterpartyID
            ),
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags,
            facets: facets
        )
        intent = canonicalCompiled.intent

        return InterpretedRequest(
            intent: intent,
            posture: posture,
            facets: canonicalCompiled.facets,
            userSummary: "Clarification received. Continuing with search.",
            userQuestion: nil,
            userNextStep: "Continue with discovery.",
            shouldDiscover: true,
            shouldDraft: false,
            semanticTags: canonicalCompiled.semanticTags,
            discoveryKeywords: canonicalCompiled.discoveryKeywords,
            targetTags: canonicalCompiled.targetTags,
            interpretationPrior: prior,
            interpretationConfidence: prior.confidence,
            needsFullLLMInterpretation: prior.shouldEscalateToLLM
        )
    }

    // MARK: - Sanitizers

    func sanitizeInterpretationResponse(
        _ response: ExchangeIntelligenceInterpretationResponse
    ) -> ExchangeIntelligenceInterpretationResponse? {
        let title = response.title.nilIfBlank
        let objective = response.objective.nilIfBlank

        guard let title, let objective else {
            return nil
        }

        let targetDescription = response.targetDescription?.nilIfBlank
        let constraints = sanitizeConstraints(response.constraints)
        let desiredOutcomes = sanitizeDesiredOutcomes(
            response.desiredOutcomes,
            kind: response.kind
        )
        let semanticTags = sanitizeRawPhraseList(response.semanticTags, maxCount: 12)
        let discoveryKeywords = sanitizeRawPhraseList(response.discoveryKeywords, maxCount: 12)
        let targetTags = sanitizeRawPhraseList(response.targetTags, maxCount: 10)

        let inferredPosture = response.inferredPosture.map {
            ExchangeIntelligencePostureResponse(
                urgency: $0.urgency,
                warmth: $0.warmth,
                directness: $0.directness,
                openness: $0.openness,
                commitment: $0.commitment,
                privacy: $0.privacy,
                priceSensitivity: $0.priceSensitivity,
                flexibility: $0.flexibility,
                notes: trimmed($0.notes, limit: 240),
                confidence: clampConfidence($0.confidence)
            )
        }

        return ExchangeIntelligenceInterpretationResponse(
            queryIntentClass: response.queryIntentClass,
            surfacePreference: response.surfacePreference,
            mode: response.mode,
            kind: response.kind,
            title: String(title.prefix(80)),
            objective: String(objective.prefix(280)),
            targetDescription: targetDescription.map { String($0.prefix(180)) },
            constraints: constraints,
            desiredOutcomes: desiredOutcomes,
            readiness: response.readiness,
            interpretationNotes: trimmed(response.interpretationNotes, limit: 240),
            confidence: clampConfidence(response.confidence),
            clarificationQuestion: trimmed(response.clarificationQuestion, limit: 180),
            userSummary: trimmed(response.userSummary, limit: 220),
            userQuestion: trimmed(response.userQuestion, limit: 180),
            userNextStep: trimmed(response.userNextStep, limit: 220),
            inferredPosture: inferredPosture,
            needsClarification: response.needsClarification,
            shouldDiscover: response.shouldDiscover,
            shouldDraft: response.shouldDraft,
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags
        )
    }

    func sanitizeConstraints(
        _ constraints: [ExchangeIntent.Constraint]
    ) -> [ExchangeIntent.Constraint] {
        var seen = Set<String>()
        var output: [ExchangeIntent.Constraint] = []

        for item in constraints.prefix(8) {
            let key = item.key.nilIfBlank
            let value = item.value.nilIfBlank
            guard let key, let value else { continue }

            let dedupe = "\(key.lowercased())|||\(value.lowercased())|||\(item.isHardConstraint)"
            guard !seen.contains(dedupe) else { continue }

            seen.insert(dedupe)
            output.append(
                ExchangeIntent.Constraint(
                    id: item.id,
                    key: String(key.prefix(40)),
                    value: String(value.prefix(160)),
                    isHardConstraint: item.isHardConstraint
                )
            )
        }

        return output
    }

    func sanitizeDesiredOutcomes(
        _ outcomes: [ExchangeIntent.DesiredOutcome],
        kind: ExchangeIntent.Kind
    ) -> [ExchangeIntent.DesiredOutcome] {
        if outcomes.isEmpty {
            return desiredOutcomes(for: kind)
        }
        return Array(outcomes.prefix(5))
    }

    func sanitizeRawPhraseList(
        _ values: [String],
        maxCount: Int
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for raw in values {
            let cleaned = raw.nilIfBlank?
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

            guard let cleaned, !cleaned.isEmpty else { continue }

            let lowered = cleaned.lowercased()
            guard !seen.contains(lowered) else { continue }

            seen.insert(lowered)
            out.append(String(cleaned.prefix(120)))

            if out.count >= maxCount { break }
        }

        return out
    }

    func applyNoPlaceLocalServiceDiscoveryDefaults(
        facets: inout ExchangeIntentFacets,
        canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        intent: ExchangeIntent
    ) {
        guard canonical.places.isEmpty else { return }
        guard facets.allowsRemoteOrShipped == false else { return }
        switch intent.queryIntentClass {
        case .providerSearch, .offerSearch, .capabilitySearch:
            facets.prefersLocalFirst = true
            if facets.fulfillmentMode == .unknown {
                facets.fulfillmentMode = .localPreferred
            }
        default:
            break
        }
    }

    // MARK: - Facets

    func buildFacets(
        sourceText: String,
        intent: ExchangeIntent,
        posture: ExchangePosture,
        threadContext: ThreadContext?,
        prior: ExchangeInterpretationPrior,
        semanticTags: [String],
        discoveryKeywords: [String],
        targetTags: [String]
    ) -> ExchangeIntentFacets {
        let lower = sourceText.lowercased()

        let locationText = inferLocationText(from: sourceText)
        let placeName = inferPlaceName(from: sourceText)
        let timeText = inferTimeText(from: sourceText)
        let timePreference = inferTimePreference(from: lower)

        let prefersLocalFirst =
            locationText != nil ||
            placeName != nil ||
            containsAny(lower, ["near me", "nearby", "local", "in person", "onsite"])

        let fulfillmentMode: ExchangeIntentFacets.FulfillmentMode = {
            if let bias = prior.fulfillmentBias {
                return bias
            }
            if containsAny(lower, ["pickup only", "must be local", "on site", "onsite", "in person only"]) {
                return .localOnly
            }
            if containsAny(lower, ["remote", "virtual", "zoom", "phone", "call"]) {
                return .remoteFriendly
            }
            if containsAny(lower, ["ship", "shipping", "deliver", "delivery"]) {
                return .shippable
            }
            if containsAny(lower, ["digital", "download", "online only"]) {
                return .digitalDelivery
            }
            if prefersLocalFirst {
                return .localPreferred
            }
            return .unknown
        }()

        let targetKind: ExchangeIntentFacets.TargetKind = {
            if let bias = prior.targetKindBias {
                return bias
            }

            switch intent.queryIntentClass {
            case .providerSearch, .offerSearch:
                return .provider
            case .capabilitySearch, .collaborationSearch:
                return .business
            case .socialAffinitySearch, .relationshipSearch:
                return .person
            case .directOutreach, .followUp, .statusCheck:
                return threadContext?.selectedCounterpartyID != nil ? .secretaryNode : .person
            case .generalDiscovery:
                return threadContext?.selectedCounterpartyID != nil ? .secretaryNode : .unknown
            }
        }()

        let marketType: ExchangeIntentFacets.MarketType = {
            switch intent.queryIntentClass {
            case .providerSearch, .offerSearch:
                return .localService
            case .capabilitySearch, .collaborationSearch:
                return .digitalService
            case .socialAffinitySearch, .relationshipSearch:
                return .relationshipLed
            case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
                return prefersLocalFirst ? .localService : .unknown
            }
        }()

        let riskLevel: ExchangeIntentFacets.RiskLevel = {
            if intent.kind == .negotiate { return .high }
            if containsAny(lower, ["contract", "legal", "lawyer", "financing", "mortgage", "loan", "terms"]) {
                return .high
            }
            if intent.queryIntentClass == .relationshipSearch {
                return .moderate
            }
            return .moderate
        }()

        let primaryKeywords = sanitizeRawPhraseList(
            discoveryKeywords + [sourceText],
            maxCount: 12
        )

        let secondaryKeywords = sanitizeRawPhraseList(
            semanticTags + targetTags + prior.allSemanticHints,
            maxCount: 12
        )

        let targetRole = bestNonEmpty(
            targetTags.first,
            prior.semanticHints.first
        )

        let activity = bestNonEmpty(
            prior.semanticHints.first
        )

        let hardRequirements = buildFacetRequirements(
            from: mergedConstraints(intent.constraints, prior.structural.literalConstraints),
            isHard: true
        )

        let softPreferences = buildFacetSoftPreferences(
            from: mergedSoftPreferences(
                posture: posture,
                locationText: locationText,
                placeName: placeName,
                timeText: timeText,
                semanticHints: prior.allSemanticHints
            )
        )

        return ExchangeIntentFacets(
            targetKind: targetKind,
            marketType: marketType,
            fulfillmentMode: fulfillmentMode,
            riskLevel: riskLevel,
            prefersLocalFirst: prefersLocalFirst,
            allowsRemoteOrShipped: fulfillmentMode == .remoteFriendly || fulfillmentMode == .shippable || fulfillmentMode == .digitalDelivery,
            allowsAutonomousClarification: posture.privacy != .guarded && riskLevel != .high,
            queryIntentClass: intent.queryIntentClass,
            surfacePreference: intent.surfacePreference,
            targetRole: targetRole,
            activity: activity,
            serviceCategory: nil,
            productCategory: nil,
            locationText: locationText,
            placeName: placeName,
            timeText: timeText,
            timePreference: timePreference,
            providerTerms: [],
            capabilityTerms: [],
            affinityTerms: [],
            regionTerms: sanitizeRawPhraseList(
                [locationText, placeName].compactMap { $0 },
                maxCount: 8
            ),
            primaryKeywords: primaryKeywords,
            secondaryKeywords: secondaryKeywords,
            hardRequirements: hardRequirements,
            softPreferences: softPreferences,
            explicitRegionRequired: locationText != nil || placeName != nil,
            explicitProfessionalNeed: targetKind == .provider || targetKind == .business || targetKind == .organization,
            explicitAffinityNeed: targetKind == .person && (intent.queryIntentClass == .socialAffinitySearch || intent.queryIntentClass == .relationshipSearch),
            notes: prior.summaryLine
        )
    }

    // MARK: - Decisions

    func shouldClarify(
        sourceText: String,
        intent: ExchangeIntent,
        confidence: Double,
        threadContext: ThreadContext?,
        readiness: ExchangeIntent.Readiness
    ) -> Bool {
        if confidence < 0.22 { return true }
        if readiness == .underSpecified { return true }
        if readiness == .needsClarification { return true }

        if threadContext?.selectedCounterpartyID != nil {
            return false
        }

        if intent.kind == .other {
            return true
        }

        return false
    }

    func computeShouldDiscover(
        sourceText: String,
        intent: ExchangeIntent,
        threadContext: ThreadContext?
    ) -> Bool {
        if threadContext?.selectedCounterpartyID != nil {
            return false
        }

        switch intent.queryIntentClass {
        case .providerSearch,
             .offerSearch,
             .capabilitySearch,
             .collaborationSearch,
             .socialAffinitySearch,
             .relationshipSearch,
             .generalDiscovery:
            return true

        case .directOutreach,
             .followUp,
             .statusCheck:
            return false
        }
    }

    func computeShouldDraft(
        sourceText: String,
        intent: ExchangeIntent,
        threadContext: ThreadContext?
    ) -> Bool {
        let lower = sourceText.lowercased()

        if threadContext?.selectedCounterpartyID != nil {
            return true
        }

        switch intent.queryIntentClass {
        case .directOutreach, .followUp, .statusCheck:
            return true
        case .providerSearch,
             .offerSearch,
             .capabilitySearch,
             .collaborationSearch,
             .socialAffinitySearch,
             .relationshipSearch,
             .generalDiscovery:
            return containsAny(lower, [
                "draft",
                "write a message",
                "write an email",
                "send a message",
                "send an email",
                "reach out",
                "contact"
            ])
        }
    }

    // MARK: - Builders / posture

    func fallbackPosture(from text: String, mode: ExchangeMode) -> ExchangePosture {
        let lower = text.lowercased()

        let urgency: ExchangePosture.Urgency = {
            if containsAny(lower, ["asap", "urgent", "immediately", "today"]) { return .immediate }
            if containsAny(lower, ["soon", "quickly"]) { return .high }
            if containsAny(lower, ["whenever", "no rush"]) { return .low }
            return .normal
        }()

        let warmth: ExchangePosture.Warmth = {
            if containsAny(lower, ["warm", "friendly", "nice", "gentle"]) { return .warm }
            if containsAny(lower, ["direct", "formal", "professional"]) { return .reserved }
            switch mode {
            case .relational: return .warm
            case .cooperative, .transactional: return .neutral
            }
        }()

        let directness: ExchangePosture.Directness = {
            if containsAny(lower, ["firm", "direct", "straight to the point"]) { return .firm }
            if containsAny(lower, ["soft", "gentle", "casual"]) { return .soft }
            return .balanced
        }()

        let openness: ExchangePosture.Openness = {
            if containsAny(lower, ["be selective", "selective", "high fit only"]) { return .selective }
            return .exploratory
        }()

        let commitment: ExchangePosture.Commitment = {
            if containsAny(lower, ["definitely", "committed"]) { return .committed }
            if containsAny(lower, ["ready to move", "serious"]) { return .serious }
            return .exploring
        }()

        let privacy: ExchangePosture.Privacy = {
            if containsAny(lower, ["private", "discreet", "do not share too much", "confidential"]) { return .guarded }
            return .balanced
        }()

        let priceSensitivity: ExchangePosture.PriceSensitivity = {
            if containsAny(lower, ["cheapest", "lowest price"]) { return .high }
            if containsAny(lower, ["budget", "affordable"]) { return .moderate }
            return .notSpecified
        }()

        let flexibility: ExchangePosture.Flexibility = {
            if containsAny(lower, ["must", "only", "strictly"]) { return .rigid }
            if containsAny(lower, ["flexible", "open"]) { return .flexible }
            return .moderate
        }()

        return ExchangePosture(
            urgency: urgency,
            warmth: warmth,
            directness: directness,
            openness: openness,
            commitment: commitment,
            privacy: privacy,
            priceSensitivity: priceSensitivity,
            flexibility: flexibility,
            notes: nil
        )
    }

    func buildSemanticTags(
        sourceText: String,
        prior: ExchangeInterpretationPrior
    ) -> [String] {
        sanitizeRawPhraseList(
            [prior.primaryQueryIntentClass.rawValue] +
            prior.allSemanticHints,
            maxCount: 12
        )
    }

    func buildDiscoveryKeywords(
        sourceText: String,
        prior: ExchangeInterpretationPrior
    ) -> [String] {
        sanitizeRawPhraseList(
            [normalizeInput(sourceText)] + prior.allSemanticHints,
            maxCount: 12
        )
    }

    func buildTargetTags(
        sourceText: String,
        prior: ExchangeInterpretationPrior
    ) -> [String] {
        var values: [String] = []

        switch prior.primaryQueryIntentClass {
        case .providerSearch, .offerSearch:
            values.append("provider")
        case .capabilitySearch, .collaborationSearch:
            values.append("capability")
        case .socialAffinitySearch:
            values.append("affinity")
        case .relationshipSearch:
            values.append("relationship")
        case .directOutreach, .followUp, .statusCheck:
            values.append("contact")
        case .generalDiscovery:
            break
        }

        values.append(contentsOf: prior.allSemanticHints)
        return sanitizeRawPhraseList(values, maxCount: 10)
    }

    struct CanonicalSearchCompilation: Sendable {
        var intent: ExchangeIntent
        var semanticTags: [String]
        var discoveryKeywords: [String]
        var targetTags: [String]
        var facets: ExchangeIntentFacets
    }

    func mergePreservedCompactSearchArtifactIfNeeded(
        artifact: PreservedCompactSearchArtifact?,
        sourceText: String,
        compilation: CanonicalSearchCompilation
    ) -> CanonicalSearchCompilation {
        guard compilation.facets.searchIntent?.objectType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            return compilation
        }
        guard let artifact else { return compilation }
        guard isCompactObjectHintCompatibleRoute(
            compilation.intent.queryIntentClass,
            compilation.intent.surfacePreference
        ) else {
            exchInterpLog(
                "[CompactObjectHintMergeSkipped] object=\(artifact.objectType) " +
                "reason=incompatibleRoute routeClass=\(compilation.intent.queryIntentClass.rawValue) " +
                "surface=\(compilation.intent.surfacePreference.rawValue)"
            )
            return compilation
        }

        var canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: artifact.domainCategory ?? .general,
            objectType: artifact.objectType,
            transactionIntent: artifact.transactionIntent,
            broadRecallTokens: [artifact.objectType],
            semanticConcepts: [artifact.objectType],
            rawUserText: sourceText,
            extractionSource: artifact.extractionSource ?? .llmFlatSummary
        )

        canonical = flatSearchIntentMapper.applyOfferSearchObjectLaneDefaults(
            to: canonical,
            queryIntentClass: compilation.intent.queryIntentClass,
            surfacePreference: compilation.intent.surfacePreference
        )
        canonical = ExchangeOfferObjectLane.normalizeActorNounObjectForLiveInterpretation(
            canonical,
            source: "compactObjectHintMerge"
        )
        canonical = ExchangeOfferObjectLane.normalizeProductObjectTransactionForLiveInterpretation(
            canonical,
            queryIntentClass: compilation.intent.queryIntentClass,
            surfacePreference: compilation.intent.surfacePreference,
            source: "compactObjectHintMerge"
        )

        var updatedFacets = compilation.facets
        updatedFacets.searchIntent = canonical
        updatedFacets.queryIntentClass = compilation.intent.queryIntentClass
        updatedFacets.surfacePreference = compilation.intent.surfacePreference

        let keywordRails = canonicalAtomicKeywordRails(from: canonical)
        updatedFacets.primaryKeywords = sanitizeRawPhraseList(keywordRails, maxCount: 12)
        updatedFacets.secondaryKeywords = sanitizeRawPhraseList(
            canonicalSecondaryKeywordRails(from: canonical),
            maxCount: 10
        )

        exchInterpLog(
            "[CompactObjectHintMerge] object=\(canonical.objectType ?? "nil") " +
            "domain=\(canonical.domainCategory.rawValue) " +
            "transaction=\(canonical.transactionIntent?.rawValue ?? "nil") " +
            "routeClass=\(compilation.intent.queryIntentClass.rawValue) " +
            "surface=\(compilation.intent.surfacePreference.rawValue)"
        )

        return .init(
            intent: compilation.intent,
            semanticTags: compilation.semanticTags,
            discoveryKeywords: compilation.discoveryKeywords,
            targetTags: compilation.targetTags,
            facets: updatedFacets
        )
    }

    func isCompactObjectHintCompatibleRoute(
        _ queryClass: ExchangeIntent.QueryIntentClass,
        _ surface: ExchangeIntent.SurfacePreference
    ) -> Bool {
        switch queryClass {
        case .offerSearch:
            return surface == .offer || surface == .mixed
        case .providerSearch:
            return surface == .offer || surface == .mixed || surface == .capability
        default:
            return false
        }
    }

    func makePreservedCompactSearchArtifact(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        sourceText: String
    ) -> PreservedCompactSearchArtifact? {
        guard let rawObject = canonical.objectType?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawObject.isEmpty
        else {
            return nil
        }
        guard let objectType = flatSearchIntentMapper.preservedFlatObjectText(rawObject) else {
            return nil
        }
        return PreservedCompactSearchArtifact(
            objectType: objectType,
            transactionIntent: canonical.transactionIntent,
            domainCategory: canonical.domainCategory,
            extractionSource: canonical.extractionSource
        )
    }

    func makePreservedCompactSearchArtifact(
        objectType rawObject: String,
        sourceText: String
    ) -> PreservedCompactSearchArtifact? {
        guard let objectType = flatSearchIntentMapper.preservedFlatObjectText(rawObject) else {
            return nil
        }
        return PreservedCompactSearchArtifact(
            objectType: objectType,
            transactionIntent: nil,
            domainCategory: nil,
            extractionSource: .llmFlatSummary
        )
    }

    func compileCanonicalSearchArtifacts(
        sourceText: String,
        intent: ExchangeIntent,
        threadContext: ThreadContext?,
        semanticTags: [String],
        discoveryKeywords: [String],
        targetTags: [String],
        facets: ExchangeIntentFacets,
        entrySurface: InterpretationEntrySurface = .other
    ) -> CanonicalSearchCompilation {
        guard shouldCompileCanonicalSearchArtifacts(
            sourceText: sourceText,
            intent: intent,
            threadContext: threadContext,
            entrySurface: entrySurface
        ) else {
            return .init(
                intent: intent,
                semanticTags: semanticTags,
                discoveryKeywords: discoveryKeywords,
                targetTags: targetTags,
                facets: facets
            )
        }

        guard let canonical = searchIntentExtractor.extract(
            sourceText: sourceText,
            intent: intent
        ) else {
            return .init(
                intent: intent,
                semanticTags: semanticTags,
                discoveryKeywords: discoveryKeywords,
                targetTags: targetTags,
                facets: facets
            )
        }

        let compiled = compileLegacyRails(from: canonical, intent: intent)

        var updatedIntent = intent
        updatedIntent.targetDescription = compiled.targetDescription ?? intent.targetDescription

        var updatedFacets = facets
        let route = ExchangeOfferObjectLane.resolvedLiveInterpretationRoute(from: canonical)
        let actorNormalized = ExchangeOfferObjectLane.normalizeActorNounObjectForLiveInterpretation(
            canonical,
            source: "liveInterpretation"
        )
        let normalizedCanonical = ExchangeOfferObjectLane.normalizeProductObjectTransactionForLiveInterpretation(
            actorNormalized,
            queryIntentClass: route.queryIntentClass,
            surfacePreference: route.surfacePreference,
            source: "liveInterpretation"
        )
        updatedIntent.queryIntentClass = route.queryIntentClass
        updatedIntent.surfacePreference = route.surfacePreference
        updatedFacets.searchIntent = normalizedCanonical
        updatedFacets.queryIntentClass = route.queryIntentClass
        updatedFacets.surfacePreference = route.surfacePreference
        updatedFacets.locationText = compiled.locationText
        updatedFacets.placeName = compiled.placeName
        updatedFacets.regionTerms = compiled.regionTerms
        updatedFacets.providerTerms = compiled.providerTerms
        updatedFacets.capabilityTerms = compiled.capabilityTerms

        let keywordRails = canonicalAtomicKeywordRails(from: canonical)
        updatedFacets.primaryKeywords = sanitizeRawPhraseList(keywordRails, maxCount: 12)
        updatedFacets.secondaryKeywords = sanitizeRawPhraseList(
            canonicalSecondaryKeywordRails(from: canonical),
            maxCount: 10
        )

        let anyHardPlace = canonical.places.contains(where: \.isHard)
        if let place = compiled.placeName {
            updatedFacets.explicitRegionRequired = anyHardPlace
            updatedFacets.softLocationTerms = sanitizeRawPhraseList([place], maxCount: 8)
        } else if let locationText = compiled.locationText {
            updatedFacets.explicitRegionRequired = anyHardPlace
            updatedFacets.softLocationTerms = sanitizeRawPhraseList([locationText], maxCount: 8)
        } else {
            updatedFacets.explicitRegionRequired = false
            updatedFacets.softLocationTerms = []
        }

        let canonicalDiscoveryKeywords = sanitizeRawPhraseList(keywordRails, maxCount: 16)

        return .init(
            intent: updatedIntent,
            semanticTags: compiled.semanticTags,
            discoveryKeywords: canonicalDiscoveryKeywords,
            targetTags: compiled.targetTags,
            facets: updatedFacets
        )
    }

    func compileCanonicalSearchArtifactsAsync(
        sourceText: String,
        intent: ExchangeIntent,
        threadContext: ThreadContext?,
        semanticTags: [String],
        discoveryKeywords: [String],
        targetTags: [String],
        facets: ExchangeIntentFacets,
        skipCanonicalReExtract: Bool = false,
        entrySurface: InterpretationEntrySurface = .other
    ) async -> CanonicalSearchCompilation {
        guard shouldCompileCanonicalSearchArtifacts(
            sourceText: sourceText,
            intent: intent,
            threadContext: threadContext,
            entrySurface: entrySurface
        ) else {
            return .init(
                intent: intent,
                semanticTags: semanticTags,
                discoveryKeywords: discoveryKeywords,
                targetTags: targetTags,
                facets: facets
            )
        }

        if skipCanonicalReExtract, facets.searchIntent == nil {
            exchInterpLog("canonicalArtifacts skipReExtract reason=already_attempted_in_interpret")
            return .init(
                intent: intent,
                semanticTags: semanticTags,
                discoveryKeywords: discoveryKeywords,
                targetTags: targetTags,
                facets: facets
            )
        }

        if let existing = facets.searchIntent {
            exchInterpLog("canonicalArtifacts reuse=true source=canonicalSearchIntentFirst")
            return finalizeCanonicalSearchCompilation(
                canonical: existing,
                intent: intent,
                semanticTags: semanticTags,
                discoveryKeywords: discoveryKeywords,
                targetTags: targetTags,
                facets: facets
            )
        }

        let canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
        if let asyncSearchIntentExtractor {
            canonical = await asyncSearchIntentExtractor.extract(
                sourceText: sourceText,
                intent: intent
            )
        } else {
            canonical = searchIntentExtractor.extract(
                sourceText: sourceText,
                intent: intent
            )
        }

        guard let canonical else {
            return .init(
                intent: intent,
                semanticTags: semanticTags,
                discoveryKeywords: discoveryKeywords,
                targetTags: targetTags,
                facets: facets
            )
        }

        return finalizeCanonicalSearchCompilation(
            canonical: canonical,
            intent: intent,
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags,
            facets: facets
        )
    }

    func finalizeCanonicalSearchCompilation(
        canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        intent: ExchangeIntent,
        semanticTags: [String],
        discoveryKeywords: [String],
        targetTags: [String],
        facets: ExchangeIntentFacets
    ) -> CanonicalSearchCompilation {
        let compiled = compileLegacyRails(from: canonical, intent: intent)

        var updatedIntent = intent
        updatedIntent.targetDescription = compiled.targetDescription ?? intent.targetDescription

        var updatedFacets = facets
        let route = ExchangeOfferObjectLane.resolvedLiveInterpretationRoute(from: canonical)
        let actorNormalized = ExchangeOfferObjectLane.normalizeActorNounObjectForLiveInterpretation(
            canonical,
            source: "liveInterpretation"
        )
        let normalizedCanonical = ExchangeOfferObjectLane.normalizeProductObjectTransactionForLiveInterpretation(
            actorNormalized,
            queryIntentClass: route.queryIntentClass,
            surfacePreference: route.surfacePreference,
            source: "liveInterpretation"
        )
        updatedIntent.queryIntentClass = route.queryIntentClass
        updatedIntent.surfacePreference = route.surfacePreference
        updatedFacets.searchIntent = normalizedCanonical
        updatedFacets.queryIntentClass = route.queryIntentClass
        updatedFacets.surfacePreference = route.surfacePreference
        updatedFacets.locationText = compiled.locationText
        updatedFacets.placeName = compiled.placeName
        updatedFacets.regionTerms = compiled.regionTerms
        updatedFacets.providerTerms = compiled.providerTerms
        updatedFacets.capabilityTerms = compiled.capabilityTerms
        updatedFacets.affinityTerms = compiled.affinityTerms

        let keywordRails = canonicalAtomicKeywordRails(from: canonical)
        updatedFacets.primaryKeywords = sanitizeRawPhraseList(keywordRails, maxCount: 12)
        updatedFacets.secondaryKeywords = sanitizeRawPhraseList(
            canonicalSecondaryKeywordRails(from: canonical),
            maxCount: 10
        )

        let anyHardPlace = canonical.places.contains(where: \.isHard)
        if let place = compiled.placeName {
            updatedFacets.explicitRegionRequired = anyHardPlace
            updatedFacets.softLocationTerms = sanitizeRawPhraseList([place], maxCount: 8)
        } else if let locationText = compiled.locationText {
            updatedFacets.explicitRegionRequired = anyHardPlace
            updatedFacets.softLocationTerms = sanitizeRawPhraseList([locationText], maxCount: 8)
        } else {
            updatedFacets.explicitRegionRequired = false
            updatedFacets.softLocationTerms = []
        }

        let canonicalDiscoveryKeywords = sanitizeRawPhraseList(keywordRails, maxCount: 16)

        return .init(
            intent: updatedIntent,
            semanticTags: compiled.semanticTags,
            discoveryKeywords: canonicalDiscoveryKeywords,
            targetTags: compiled.targetTags,
            facets: updatedFacets
        )
    }

    /// Atomic recall chips for facet keyword rails (no raw user paragraph or fused clauses).
    func canonicalAtomicKeywordRails(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> [String] {
        var seeds: [String] = []
        seeds.append(contentsOf: canonical.broadRecallTokens)
        seeds.append(contentsOf: canonical.semanticConcepts)
        seeds.append(canonical.domainCategory.rawValue)
        if let tx = canonical.transactionIntent {
            seeds.append(tx.rawValue)
        }
        if let ot = canonical.objectType {
            seeds.append(ot)
        }
        for p in canonical.places {
            seeds.append(p.normalizedText)
            seeds.append(contentsOf: p.aliases)
        }
        for cc in canonical.commercialConstraints {
            seeds.append(cc.key)
            seeds.append(cc.value)
        }
        for a in canonical.attributes {
            seeds.append(a.key)
            seeds.append(a.value)
        }
        for tc in canonical.timeConstraints {
            seeds.append(tc.text)
        }
        return sanitizeAtomicLegacyTerms(seeds, maxCount: 24)
    }

    /// Narrow secondary rails: domain/transaction classifiers only (atomic).
    func canonicalSecondaryKeywordRails(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> [String] {
        var seeds: [String] = [canonical.domainCategory.rawValue]
        if let tx = canonical.transactionIntent {
            seeds.append(tx.rawValue)
        }
        return sanitizeAtomicLegacyTerms(seeds, maxCount: 10)
    }

    /// True only for runtime/infrastructure extractor failures — not parse or actionability misses.
    private func isInfrastructureSearchIntentExtractorFailure(
        _ reason: SearchIntentExtractionFailureReason?
    ) -> Bool {
        switch reason {
        case .providerUnavailable, .modelBusy, .timeout, .cancelled, .thrownError:
            return true
        case .invalidJSON, .repairFailed, .emptyDTO, .unsafeDTO, .nonActionableDTO, .none:
            return false
        }
    }

    /// True when compiled canonical search intent has enough structure to justify continuing past the
    /// low-confidence clarification breaker (target axis + a discovery anchor).
    ///
    /// `broadRecallTokens` alone must not bypass when there is only a single chip (e.g. object type
    /// `"someone"` duplicates one recall token); require either structured anchors or ≥2 recall chips.
    private func isMateriallyActionableCanonicalSearchIntent(
        _ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        let trimmedObject = si.objectType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let objectNonEmpty = !(trimmedObject?.isEmpty ?? true)
        if si.domainCategory != .general, objectNonEmpty {
            return true
        }

        let hasTargetAxis =
            objectNonEmpty ||
            si.domainCategory != .general ||
            !si.semanticConcepts.isEmpty

        let hasDiscoveryAnchor =
            !si.places.isEmpty ||
            !si.commercialConstraints.isEmpty ||
            !si.attributes.isEmpty ||
            !si.preferences.isEmpty ||
            !si.timeConstraints.isEmpty ||
            si.broadRecallTokens.count >= 2

        return hasTargetAxis && hasDiscoveryAnchor
    }

    func shouldBuildCanonicalSearchIntent(
        intent: ExchangeIntent,
        threadContext: ThreadContext?
    ) -> Bool {
        guard threadContext?.selectedCounterpartyID == nil else { return false }
        switch intent.queryIntentClass {
        case .providerSearch,
             .offerSearch,
             .capabilitySearch,
             .collaborationSearch,
             .socialAffinitySearch,
             .relationshipSearch,
             .generalDiscovery:
            return true
        case .directOutreach, .followUp, .statusCheck:
            return false
        }
    }

    /// Late compile/extract only for open discovery shapes that use the canonical-first path.
    func shouldCompileCanonicalSearchArtifacts(
        sourceText: String,
        intent: ExchangeIntent,
        threadContext: ThreadContext?,
        entrySurface: InterpretationEntrySurface = .other
    ) -> Bool {
        shouldBuildCanonicalSearchIntent(intent: intent, threadContext: threadContext)
            && shouldUseCanonicalSearchIntentExtractorFirst(
                sourceText: sourceText,
                threadContext: threadContext,
                entrySurface: entrySurface
            )
    }

    struct CompiledLegacyRails: Sendable {
        var semanticTags: [String]
        var targetTags: [String]
        var targetDescription: String?
        var locationText: String?
        var placeName: String?
        var regionTerms: [String]
        var providerTerms: [String]
        var capabilityTerms: [String]
        var affinityTerms: [String]
    }

    func compileLegacyRails(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        intent: ExchangeIntent
    ) -> CompiledLegacyRails {
        let place = canonical.places.first?.normalizedText
        let locationText = place
        let regionTerms = sanitizeAtomicLegacyTerms(canonical.places.map(\.normalizedText), maxCount: 8)

        let semanticTags = sanitizeAtomicLegacyTerms(
            canonical.semanticConcepts +
            canonical.broadRecallTokens +
            [canonical.domainCategory.rawValue],
            maxCount: 14
        )

        var targetSeed: [String] = []
        if let objectType = canonical.objectType {
            targetSeed.append(objectType)
        }
        switch intent.queryIntentClass {
        case .providerSearch, .offerSearch:
            targetSeed.append("provider")
        case .capabilitySearch, .collaborationSearch:
            targetSeed.append("capability")
        case .socialAffinitySearch:
            targetSeed.append("affinity")
        case .relationshipSearch:
            targetSeed.append("relationship")
        case .generalDiscovery, .directOutreach, .followUp, .statusCheck:
            break
        }
        targetSeed.append(contentsOf: canonical.semanticConcepts)
        let targetTags = sanitizeAtomicLegacyTerms(targetSeed, maxCount: 10)

        let providerTerms: [String] = {
            switch intent.queryIntentClass {
            case .providerSearch, .offerSearch:
                return sanitizeAtomicLegacyTerms([canonical.objectType] + canonical.semanticConcepts, maxCount: 12)
            default:
                return []
            }
        }()

        let capabilityTerms: [String] = {
            switch intent.queryIntentClass {
            case .capabilitySearch, .collaborationSearch:
                return sanitizeAtomicLegacyTerms(canonical.semanticConcepts + [canonical.objectType], maxCount: 12)
            default:
                return []
            }
        }()

        let affinityTerms: [String] = {
            switch intent.queryIntentClass {
            case .socialAffinitySearch, .relationshipSearch:
                return sanitizeAtomicLegacyTerms(
                    [canonical.objectType] + canonical.semanticConcepts + canonical.broadRecallTokens,
                    maxCount: 12
                )
            default:
                return []
            }
        }()

        let targetDescription: String? = {
            var parts: [String] = []
            if let objectType = canonical.objectType {
                parts.append(objectType)
            }
            if let place {
                parts.append("in \(place)")
            }
            if let financing = canonical.commercialConstraints.first(where: { $0.kind == .financing }) {
                parts.append(financing.value)
            }
            let text = parts.joined(separator: " ")
            return text.nilIfBlank
        }()

        return .init(
            semanticTags: semanticTags,
            targetTags: targetTags,
            targetDescription: targetDescription,
            locationText: locationText,
            placeName: place,
            regionTerms: regionTerms,
            providerTerms: providerTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: affinityTerms
        )
    }

    func sanitizeAtomicLegacyTerms(
        _ values: [String],
        maxCount: Int
    ) -> [String] {
        let filtered = values.filter { value in
            let lower = value.lowercased()
            return !lower.contains(", and ") &&
                !lower.contains(" and ") &&
                !lower.contains(" who ") &&
                !lower.contains(" with ")
        }
        return sanitizeRawPhraseList(filtered, maxCount: maxCount)
    }

    func sanitizeAtomicLegacyTerms(
        _ values: [String?],
        maxCount: Int
    ) -> [String] {
        sanitizeAtomicLegacyTerms(values.compactMap { $0 }, maxCount: maxCount)
    }

    func mergedConstraints(
        _ lhs: [ExchangeIntent.Constraint],
        _ rhs: [ExchangeIntent.Constraint]
    ) -> [ExchangeIntent.Constraint] {
        sanitizeConstraints(lhs + rhs)
    }

    func mergedSoftPreferences(
        posture: ExchangePosture,
        locationText: String?,
        placeName: String?,
        timeText: String?,
        semanticHints: [String]
    ) -> [ExchangeIntent.Constraint] {
        var out: [ExchangeIntent.Constraint] = []

        if posture.priceSensitivity == .high {
            out.append(.init(key: "price", value: "budget-sensitive", isHardConstraint: false))
        }

        if posture.flexibility == .flexible {
            out.append(.init(key: "flexibility", value: "flexible", isHardConstraint: false))
        }

        if let locationText {
            out.append(.init(key: "location", value: locationText, isHardConstraint: false))
        }

        if let placeName {
            out.append(.init(key: "place", value: placeName, isHardConstraint: false))
        }

        if let timeText {
            out.append(.init(key: "time", value: timeText, isHardConstraint: false))
        }

        if let firstHint = semanticHints.first {
            out.append(.init(key: "semanticHint", value: firstHint, isHardConstraint: false))
        }

        return sanitizeConstraints(out)
    }

    // MARK: - Helpers

    func inferLocationText(from text: String) -> String? {
        let snippets = [
            snippet(afterAnyOf: ["near ", "in "], in: text),
            phraseMatch(in: text, phrases: ["near me"])
        ].compactMap { $0 }

        return snippets
            .map { String($0.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    func inferPlaceName(from text: String) -> String? {
        if let afterAt = snippet(afterAnyOf: ["at "], in: text) {
            let place = afterAt
                .split(separator: ",")
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return place?.nilIfBlank.map { String($0.prefix(80)) }
        }
        return nil
    }

    func inferTimeText(from text: String) -> String? {
        let lower = text.lowercased()
        let phrases = [
            "right now", "today", "tonight", "tomorrow",
            "this week", "this weekend", "next weekend", "next week",
            "after work", "evening", "weekend"
        ]

        for phrase in phrases where lower.contains(phrase) {
            return phrase
        }
        return nil
    }

    func inferTimePreference(from lower: String) -> ExchangeIntentFacets.TimePreference? {
        if containsAny(lower, ["asap", "urgent", "immediately", "right now"]) { return .immediate }
        if containsAny(lower, ["today", "this afternoon"]) { return .today }
        if containsAny(lower, ["tonight", "this evening"]) { return .tonight }
        if containsAny(lower, ["this week"]) { return .thisWeek }
        if containsAny(lower, ["weekend", "this weekend", "next weekend"]) { return .weekend }
        if containsAny(lower, ["next week"]) { return .nextWeek }
        if containsAny(lower, ["flexible", "whenever", "no rush"]) { return .flexible }
        return nil
    }

    func buildFacetRequirements(
        from constraints: [ExchangeIntent.Constraint],
        isHard: Bool
    ) -> [ExchangeIntentFacets.Requirement] {
        constraints.map {
            ExchangeIntentFacets.Requirement(
                key: $0.key,
                value: $0.value,
                isHard: isHard && $0.isHardConstraint
            )
        }
    }

    func buildFacetSoftPreferences(
        from constraints: [ExchangeIntent.Constraint]
    ) -> [ExchangeIntentFacets.Requirement] {
        constraints
            .filter { !$0.isHardConstraint }
            .map {
                ExchangeIntentFacets.Requirement(
                    key: $0.key,
                    value: $0.value,
                    isHard: false
                )
            }
    }

    func phraseMatch(in text: String, phrases: [String]) -> String? {
        let lower = text.lowercased()
        for phrase in phrases {
            if let range = lower.range(of: phrase) {
                let suffix = text[range.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                let clipped = String(suffix.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !clipped.isEmpty { return clipped }
            }
        }
        return nil
    }

    func clarificationQuestion(for intent: ExchangeIntent) -> String {
        switch intent.kind {
        case .requestQuote:
            return "What exactly do you want quoted, and what location or scope should I use?"
        case .introduce:
            return "Who do you want to be introduced to?"
        case .message:
            return "Who should I contact, and what outcome do you want from the message?"
        case .arrangeCall, .arrangeMeeting:
            return "Who should I coordinate with, and what timing or purpose should I use?"
        case .find, .source:
            return "What kind of match are you looking for, and what matters most?"
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

    func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    func snippet(afterAnyOf prefixes: [String], in text: String) -> String? {
        let lower = text.lowercased()

        for prefix in prefixes {
            guard let range = lower.range(of: prefix) else { continue }
            let suffix = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !suffix.isEmpty else { continue }
            let clipped = String(suffix.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            return clipped.isEmpty ? nil : clipped
        }

        return nil
    }

    func trimmed(_ value: String?, limit: Int) -> String? {
        guard let value = value?.nilIfBlank else { return nil }
        return String(value.prefix(limit))
    }

    func normalizeInput(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func clampConfidence(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
