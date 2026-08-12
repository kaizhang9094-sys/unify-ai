import Foundation

/// Prompt builder for open-ended requester search extraction.
enum ExchangeOpenEndedSearchIntentPromptBuilder {
    /// Flat string-only JSON summary (primary). Avoids nested DTO shapes small models confuse with top-level output.
    static func buildFlatSummaryPrompt(
        sourceText: String,
        intent: ExchangeIntent
    ) -> String {
        let example =
            #"{"raw":"Find me a roofer in Aurora for a roof estimate tomorrow at 2:30pm under $200.","englishSearch":"Find a roofer in Aurora for a roof estimate tomorrow at 2:30pm with budget under 200.","object":"roofer","need":"roof estimate","place":"Aurora","time":"tomorrow at 2:30pm","budget":"under 200","commercial":null,"mods":[],"hard":["Aurora","tomorrow at 2:30pm","under 200"],"soft":[],"gaps":[],"confidence":0.9,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.92,"routeRationale":"hire roofer for scheduled estimate"}"#

        return """
        Extract a compact JSON request summary for local discovery. Output JSON only: one object, `{` first, `}` last. No markdown, no fences, no extra text.

        Include every key exactly once, in this order (use null for unknown scalars; use [] for empty string arrays):
        {"raw":string,"englishSearch":string|null,"object":string|null,"need":string|null,"place":string|null,"time":string|null,"budget":string|null,"commercial":string|null,"mods":[string],"hard":[string],"soft":[string],"gaps":[string],"confidence":number,"routeClass":string|null,"surfacePreference":string|null,"targetKind":string|null,"mode":string|null,"routeConfidence":number|null,"routeRationale":string|null}

        Rules:
        - Arrays contain strings only. No nested objects.
        - `object`: the provider, item, person, group, or activity being searched for.
        - `need`: the specific task, problem, use case, project, or reason for the search.
        - Fill `need` when the user states what they need done, repaired, reviewed, practiced, joined, bought, compared, or scheduled.
        - Use null for `need` only when there is no specific task or use case beyond the object.
        - `englishSearch`: one normalized English sentence for retrieval embedding/BM25. Translate when the user request is not English. Use null when the request is already English-only.
        - `budget`: when the user states a budget cap, fill with a compact phrase such as "under 200" or "$200 max". Use null only when no budget limit is stated.
        - `hard`: only exact phrases explicitly present in the user request.
        - Do not stop after `raw`; fill object, need, place, time, and budget when clearly stated.
        - For on-site pricing or inspection requests, prefer `need` phrases with "estimate" (e.g. "roof estimate"); "appraisal" is acceptable when the user uses that word.

        Route fields classify HOW to discover (not what to extract):
        - `routeClass`: socialAffinitySearch | relationshipSearch | providerSearch | offerSearch | capabilitySearch | generalDiscovery
        - `surfacePreference`: affinity | offer | capability | mixed
        - `targetKind`: person | provider | offer | profile | counterparty | unknown
        - `mode`: relational | transactional | mixed
        - `routeConfidence`: 0..1 confidence in route fields only
        - `routeRationale`: one short debug phrase; never duplicate into object/need/tags

        Route contrasts:
        - Social/person/interest discovery without hiring, booking, buying, or scheduling a paid service:
          routeClass=socialAffinitySearch, surfacePreference=affinity, targetKind=person, mode=relational
        - Hire/book/find a professional or vendor to perform a task:
          routeClass=providerSearch, surfacePreference=offer, targetKind=provider, mode=transactional
        - Buy/rent/find a product or listing:
          routeClass=offerSearch, surfacePreference=offer, targetKind=provider, mode=transactional

        Examples:
        - "Find people interested in photography in Aurora" → socialAffinitySearch / affinity / person / relational
        - "Find photography enthusiasts in Aurora" → socialAffinitySearch / affinity / person / relational
        - "Find a photographer for product photos in Aurora" → providerSearch / offer / provider / transactional
        - "Find a roofer for a roof estimate tomorrow at 2pm under $200" → providerSearch / offer / provider / transactional

        Example (same key order; adapt to the real user request):
        \(example)

        Seed intent (hints only):
        {"queryIntentClass":"\(intent.queryIntentClass.rawValue)","surfacePreference":"\(intent.surfacePreference.rawValue)","mode":"\(intent.mode.rawValue)","kind":"\(intent.kind.rawValue)"}

        User request:
        \(sourceText)
        """
    }

    /// Backward-compatible entry: flat summary is the primary extraction contract.
    static func buildPrompt(
        sourceText: String,
        intent: ExchangeIntent
    ) -> String {
        buildFlatSummaryPrompt(sourceText: sourceText, intent: intent)
    }
}

/// Short model-facing JSON for `searchIntentExtraction` (fits small on-device output caps). Expanded to `SecretarySearchRequestSummaryDTO` before validation.
struct SecretaryCompactSearchSummaryDTO: Codable, Sendable, Hashable {
    var raw: String?
    var englishSearch: String?
    var object: String?
    var need: String?
    var place: String?
    var time: String?
    var budget: String?
    var commercial: String?
    var mods: [String]
    var hard: [String]
    var soft: [String]
    var gaps: [String]
    var confidence: Double?
    var routeClass: String?
    var surfacePreference: String?
    var targetKind: String?
    var mode: String?
    var routeConfidence: Double?
    var routeRationale: String?

    enum CodingKeys: String, CodingKey {
        case raw
        case englishSearch
        case object
        case need
        case place
        case time
        case budget
        case commercial
        case mods
        case hard
        case soft
        case gaps
        case confidence
        case routeClass
        case surfacePreference
        case targetKind
        case mode
        case routeConfidence
        case routeRationale
    }

    init(
        raw: String? = nil,
        englishSearch: String? = nil,
        object: String? = nil,
        need: String? = nil,
        place: String? = nil,
        time: String? = nil,
        budget: String? = nil,
        commercial: String? = nil,
        mods: [String] = [],
        hard: [String] = [],
        soft: [String] = [],
        gaps: [String] = [],
        confidence: Double? = nil,
        routeClass: String? = nil,
        surfacePreference: String? = nil,
        targetKind: String? = nil,
        mode: String? = nil,
        routeConfidence: Double? = nil,
        routeRationale: String? = nil
    ) {
        self.raw = raw
        self.englishSearch = englishSearch
        self.object = object
        self.need = need
        self.place = place
        self.time = time
        self.budget = budget
        self.commercial = commercial
        self.mods = mods
        self.hard = hard
        self.soft = soft
        self.gaps = gaps
        self.confidence = confidence
        self.routeClass = routeClass
        self.surfacePreference = surfacePreference
        self.targetKind = targetKind
        self.mode = mode
        self.routeConfidence = routeConfidence
        self.routeRationale = routeRationale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raw = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .raw))
        englishSearch = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .englishSearch))
        object = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .object))
        need = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .need))
        place = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .place))
        time = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .time))
        budget = SearchIntentSentinelFilter.nilIfSentinel(try Self.decodeFlexibleBudget(from: c))
        commercial = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .commercial))
        mods = SearchIntentSentinelFilter.filterSentinels(try c.decodeIfPresent([String].self, forKey: .mods) ?? [])
        hard = SearchIntentSentinelFilter.filterSentinels(try c.decodeIfPresent([String].self, forKey: .hard) ?? [])
        soft = SearchIntentSentinelFilter.filterSentinels(try c.decodeIfPresent([String].self, forKey: .soft) ?? [])
        gaps = SearchIntentSentinelFilter.filterSentinels(try c.decodeIfPresent([String].self, forKey: .gaps) ?? [])
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        routeClass = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .routeClass))
        surfacePreference = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .surfacePreference))
        targetKind = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .targetKind))
        mode = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .mode))
        routeConfidence = try c.decodeIfPresent(Double.self, forKey: .routeConfidence)
        routeRationale = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .routeRationale))
    }
}

/// Flat LLM output for Secretary search-intent extraction (no nested objects).
struct SecretarySearchRequestSummaryDTO: Codable, Sendable, Hashable {
    var rawNeedText: String?
    var canonicalEnglishSearchText: String?
    var objectText: String?
    var needText: String?
    var categoryHint: String?
    var transactionIntentHint: String?
    var surfacePreferenceHint: String?
    var placeText: String?
    var timeText: String?
    var budgetText: String?
    var commercialText: String?
    var availabilityText: String?
    var modifierTexts: [String]
    var hardTexts: [String]
    var softTexts: [String]
    var semanticTexts: [String]
    var broadRecallTokens: [String]
    var clarificationGaps: [String]
    var confidence: Double?
    var routeClassHint: String?
    var targetKindHint: String?
    var modeHint: String?
    var routeConfidence: Double?
    var routeRationale: String?

    enum CodingKeys: String, CodingKey {
        case rawNeedText
        case canonicalEnglishSearchText
        case objectText
        case needText
        case categoryHint
        case transactionIntentHint
        case surfacePreferenceHint
        case placeText
        case timeText
        case budgetText
        case commercialText
        case availabilityText
        case modifierTexts
        case hardTexts
        case softTexts
        case semanticTexts
        case broadRecallTokens
        case clarificationGaps
        case confidence
        case routeClassHint
        case targetKindHint
        case modeHint
        case routeConfidence
        case routeRationale
    }

    init(
        rawNeedText: String? = nil,
        canonicalEnglishSearchText: String? = nil,
        objectText: String? = nil,
        needText: String? = nil,
        categoryHint: String? = nil,
        transactionIntentHint: String? = nil,
        surfacePreferenceHint: String? = nil,
        placeText: String? = nil,
        timeText: String? = nil,
        budgetText: String? = nil,
        commercialText: String? = nil,
        availabilityText: String? = nil,
        modifierTexts: [String] = [],
        hardTexts: [String] = [],
        softTexts: [String] = [],
        semanticTexts: [String] = [],
        broadRecallTokens: [String] = [],
        clarificationGaps: [String] = [],
        confidence: Double? = nil,
        routeClassHint: String? = nil,
        targetKindHint: String? = nil,
        modeHint: String? = nil,
        routeConfidence: Double? = nil,
        routeRationale: String? = nil
    ) {
        self.rawNeedText = rawNeedText
        self.canonicalEnglishSearchText = canonicalEnglishSearchText
        self.objectText = objectText
        self.needText = needText
        self.categoryHint = categoryHint
        self.transactionIntentHint = transactionIntentHint
        self.surfacePreferenceHint = surfacePreferenceHint
        self.placeText = placeText
        self.timeText = timeText
        self.budgetText = budgetText
        self.commercialText = commercialText
        self.availabilityText = availabilityText
        self.modifierTexts = modifierTexts
        self.hardTexts = hardTexts
        self.softTexts = softTexts
        self.semanticTexts = semanticTexts
        self.broadRecallTokens = broadRecallTokens
        self.clarificationGaps = clarificationGaps
        self.confidence = confidence
        self.routeClassHint = routeClassHint
        self.targetKindHint = targetKindHint
        self.modeHint = modeHint
        self.routeConfidence = routeConfidence
        self.routeRationale = routeRationale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawNeedText = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .rawNeedText))
        canonicalEnglishSearchText = SearchIntentSentinelFilter.nilIfSentinel(
            try c.decodeIfPresent(String.self, forKey: .canonicalEnglishSearchText)
        )
        objectText = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .objectText))
        needText = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .needText))
        categoryHint = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .categoryHint))
        transactionIntentHint = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .transactionIntentHint))
        surfacePreferenceHint = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .surfacePreferenceHint))
        placeText = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .placeText))
        timeText = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .timeText))
        budgetText = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .budgetText))
        commercialText = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .commercialText))
        availabilityText = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .availabilityText))
        modifierTexts = SearchIntentSentinelFilter.filterSentinels(try c.decodeIfPresent([String].self, forKey: .modifierTexts) ?? [])
        hardTexts = SearchIntentSentinelFilter.filterSentinels(try c.decodeIfPresent([String].self, forKey: .hardTexts) ?? [])
        softTexts = SearchIntentSentinelFilter.filterSentinels(try c.decodeIfPresent([String].self, forKey: .softTexts) ?? [])
        semanticTexts = SearchIntentSentinelFilter.filterSentinels(try c.decodeIfPresent([String].self, forKey: .semanticTexts) ?? [])
        broadRecallTokens = SearchIntentSentinelFilter.filterSentinels(try c.decodeIfPresent([String].self, forKey: .broadRecallTokens) ?? [])
        clarificationGaps = SearchIntentSentinelFilter.filterSentinels(try c.decodeIfPresent([String].self, forKey: .clarificationGaps) ?? [])
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        routeClassHint = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .routeClassHint))
        targetKindHint = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .targetKindHint))
        modeHint = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .modeHint))
        routeConfidence = try c.decodeIfPresent(Double.self, forKey: .routeConfidence)
        routeRationale = SearchIntentSentinelFilter.nilIfSentinel(try c.decodeIfPresent(String.self, forKey: .routeRationale))
    }
}

struct LLMSearchIntentExtractionDTO: Codable, Sendable, Hashable {
    var objectType: String?
    var domainHint: String?
    var transactionIntentHint: String?
    var places: [LLMPlaceDTO]
    var attributes: [LLMAttributeDTO]
    var preferences: [LLMPreferenceDTO]
    var timeConstraints: [LLMTimeConstraintDTO]
    var commercialConstraints: [LLMCommercialConstraintDTO]
    var hardConstraints: [String]
    var softPreferences: [String]
    var semanticConcepts: [String]
    var broadRecallTokens: [String]
    var clarificationGaps: [String]
    var confidence: Double?

    init(
        objectType: String? = nil,
        domainHint: String? = nil,
        transactionIntentHint: String? = nil,
        places: [LLMPlaceDTO] = [],
        attributes: [LLMAttributeDTO] = [],
        preferences: [LLMPreferenceDTO] = [],
        timeConstraints: [LLMTimeConstraintDTO] = [],
        commercialConstraints: [LLMCommercialConstraintDTO] = [],
        hardConstraints: [String] = [],
        softPreferences: [String] = [],
        semanticConcepts: [String] = [],
        broadRecallTokens: [String] = [],
        clarificationGaps: [String] = [],
        confidence: Double? = nil
    ) {
        self.objectType = objectType
        self.domainHint = domainHint
        self.transactionIntentHint = transactionIntentHint
        self.places = places
        self.attributes = attributes
        self.preferences = preferences
        self.timeConstraints = timeConstraints
        self.commercialConstraints = commercialConstraints
        self.hardConstraints = hardConstraints
        self.softPreferences = softPreferences
        self.semanticConcepts = semanticConcepts
        self.broadRecallTokens = broadRecallTokens
        self.clarificationGaps = clarificationGaps
        self.confidence = confidence
    }
}

struct LLMPlaceDTO: Codable, Sendable, Hashable {
    var text: String
    var aliases: [String]?
    var confidence: Double?
    var isHard: Bool?
}

struct LLMAttributeDTO: Codable, Sendable, Hashable {
    var key: String
    var value: String
    var numericValue: Double?
}

struct LLMPreferenceDTO: Codable, Sendable, Hashable {
    var key: String
    var value: String?
    var strength: String?
}

struct LLMTimeConstraintDTO: Codable, Sendable, Hashable {
    var kind: String?
    var text: String
    var isHard: Bool?
}

struct LLMCommercialConstraintDTO: Codable, Sendable, Hashable {
    var kind: String?
    var key: String?
    var value: String
    var isHard: Bool?
}

public protocol AsyncSearchIntentJSONProvider: Sendable {
    func isReadyForImmediateExtraction() async -> Bool
    func extractSearchIntentJSON(prompt: String) async throws -> String
}

public protocol SearchIntentProviderBusyError: Error {}
public protocol SearchIntentProviderUnavailableError: Error {}

/// LLM-backed canonical extractor boundary.
///
/// Runtime note:
/// - `OpenEndedSearchIntentExtractor` is currently synchronous.
/// - Async extraction relies on the runner’s `maxTokens` / output cap; cancellation propagates from the task hierarchy.
/// - Therefore this extractor is opt-in via injected `jsonProvider`; production default remains heuristic.
public struct LLMOpenEndedSearchIntentExtractor: OpenEndedSearchIntentExtractor {
    public struct Configuration: Sendable, Hashable {
        public var minConfidenceForEnumMapping: Double
        public var maxPlaces: Int
        public var maxAttributes: Int
        public var maxPreferences: Int
        public var maxTimeConstraints: Int
        public var maxCommercialConstraints: Int
        public var maxSemanticConcepts: Int
        public var maxBroadRecallTokens: Int
        public var maxHardConstraints: Int
        public var maxSoftPreferences: Int
        public var maxClarificationGaps: Int

        public init(
            minConfidenceForEnumMapping: Double = 0.70,
            maxPlaces: Int = 8,
            maxAttributes: Int = 12,
            maxPreferences: Int = 12,
            maxTimeConstraints: Int = 8,
            maxCommercialConstraints: Int = 10,
            maxSemanticConcepts: Int = 20,
            maxBroadRecallTokens: Int = 24,
            maxHardConstraints: Int = 10,
            maxSoftPreferences: Int = 16,
            maxClarificationGaps: Int = 10
        ) {
            self.minConfidenceForEnumMapping = minConfidenceForEnumMapping
            self.maxPlaces = maxPlaces
            self.maxAttributes = maxAttributes
            self.maxPreferences = maxPreferences
            self.maxTimeConstraints = maxTimeConstraints
            self.maxCommercialConstraints = maxCommercialConstraints
            self.maxSemanticConcepts = maxSemanticConcepts
            self.maxBroadRecallTokens = maxBroadRecallTokens
            self.maxHardConstraints = maxHardConstraints
            self.maxSoftPreferences = maxSoftPreferences
            self.maxClarificationGaps = maxClarificationGaps
        }
    }

    public protocol JSONProvider: Sendable {
        func extractSearchIntentJSON(
            prompt: String,
            sourceText: String,
            intent: ExchangeIntent
        ) throws -> String
    }

    private let jsonProvider: (any JSONProvider)?
    private let heuristicFallback: CanonicalSearchIntentHeuristicExtractor
    private let config: Configuration

    public init(
        jsonProvider: (any JSONProvider)? = nil,
        heuristicFallback: CanonicalSearchIntentHeuristicExtractor = CanonicalSearchIntentHeuristicExtractor(),
        config: Configuration = Configuration()
    ) {
        self.jsonProvider = jsonProvider
        self.heuristicFallback = heuristicFallback
        self.config = config
    }

    public func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        let normalized = normalizeInput(sourceText)
        guard !normalized.isEmpty else { return nil }

        guard let jsonProvider else {
            return heuristicFallback.extract(sourceText: sourceText, intent: intent)
        }

        let prompt = ExchangeOpenEndedSearchIntentPromptBuilder.buildPrompt(
            sourceText: normalized,
            intent: intent
        )

        let rawJSON: String
        do {
            rawJSON = try jsonProvider.extractSearchIntentJSON(
                prompt: prompt,
                sourceText: normalized,
                intent: intent
            )
        } catch {
            return heuristicFallback.extract(sourceText: sourceText, intent: intent)
        }

        let cleaned = cleanJSON(rawJSON)

        if let flatMapped = processSearchIntentFlatPipelineCanonical(
            cleaned: cleaned,
            userText: normalized,
            intent: intent
        ) {
            return exchangeCanonicalTagged(flatMapped, .llmFlatSummary)
        }

        guard let dto = decodeDTO(fromCleaned: cleaned) else {
            return heuristicFallback.extract(sourceText: sourceText, intent: intent)
        }

        guard let candidate = mapDTO(dto, sourceText: normalized, intent: intent) else {
            return heuristicFallback.extract(sourceText: sourceText, intent: intent)
        }

        guard isMateriallyActionable(candidate) else {
            return heuristicFallback.extract(sourceText: sourceText, intent: intent)
        }

        return exchangeCanonicalTagged(candidate, .llm)
    }
}

/// Runtime-safe async LLM-first extractor.
///
/// Attempts on-device JSON extraction first. Failures record `SearchIntentExtractionDiagnostics`
/// with `source: .heuristicFallback` and return `nil` (no heuristic canonical posing as LLM output).
public struct AsyncLLMOpenEndedSearchIntentExtractor: AsyncOpenEndedSearchIntentExtractor {
    /// Must match `LlamaExchangeModelRunner.resolveTaskPolicy` for `.searchIntentExtraction` `outputCharCap`.
    private static let searchIntentRunnerOutputCharCap: Int = 4000

    private let provider: (any AsyncSearchIntentJSONProvider)?
    private let fallbackExtractor: any OpenEndedSearchIntentExtractor
    private let mapper: LLMOpenEndedSearchIntentExtractor
    private let diagnosticsStore: SearchIntentExtractionDiagnosticsStore?

    public init(
        provider: (any AsyncSearchIntentJSONProvider)?,
        fallbackExtractor: any OpenEndedSearchIntentExtractor = CanonicalSearchIntentHeuristicExtractor(),
        mapper: LLMOpenEndedSearchIntentExtractor = LLMOpenEndedSearchIntentExtractor(),
        diagnosticsStore: SearchIntentExtractionDiagnosticsStore? = nil
    ) {
        self.provider = provider
        self.fallbackExtractor = fallbackExtractor
        self.mapper = mapper
        self.diagnosticsStore = diagnosticsStore
    }

    public func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        await diagnosticsStore?.reset()
        let normalized = mapper.normalizeInput(sourceText)
        guard !normalized.isEmpty else { return nil }

        guard let provider else {
            return await fallbackWith(
                sourceText: normalized,
                intent: intent,
                reason: .providerUnavailable,
                attemptedLLM: false
            )
        }

        guard await provider.isReadyForImmediateExtraction() else {
            return await fallbackWith(
                sourceText: normalized,
                intent: intent,
                reason: .modelBusy
            )
        }

        let prompt = ExchangeOpenEndedSearchIntentPromptBuilder.buildPrompt(
            sourceText: normalized,
            intent: intent
        )

        #if DEBUG
        await SearchIntentExtractionDebugTrace.shared.recordPrompt(prompt)
        #endif

        let start = CFAbsoluteTimeGetCurrent()
        let raw: String
        do {
            raw = try await provider.extractSearchIntentJSON(prompt: prompt)
            #if DEBUG
            await SearchIntentExtractionDebugTrace.shared.recordRaw(raw)
            #endif
        } catch is CancellationError {
            return await fallbackWith(
                sourceText: normalized,
                intent: intent,
                reason: .cancelled,
                elapsedMs: elapsedMs(from: start)
            )
        } catch is any SearchIntentProviderBusyError {
            return await fallbackWith(
                sourceText: normalized,
                intent: intent,
                reason: .modelBusy,
                elapsedMs: elapsedMs(from: start)
            )
        } catch is any SearchIntentProviderUnavailableError {
            return await fallbackWith(
                sourceText: normalized,
                intent: intent,
                reason: .providerUnavailable,
                elapsedMs: elapsedMs(from: start)
            )
        } catch {
            return await fallbackWith(
                sourceText: normalized,
                intent: intent,
                reason: .thrownError,
                elapsedMs: elapsedMs(from: start),
                decodeErrorSummary: String(describing: error)
            )
        }

        if raw.count >= Self.searchIntentRunnerOutputCharCap {
            return await fallbackWith(
                sourceText: normalized,
                intent: intent,
                reason: .invalidJSON,
                elapsedMs: elapsedMs(from: start),
                decodeErrorSummary: "outputCharCapReached(rawChars=\(raw.count))"
            )
        }

        #if DEBUG
        let rawShape = Self.classifyRawLLMJSONShape(raw)
        print("[SearchIntentExtractor] rawLLMJsonShape=\(rawShape.rawValue)")
        #endif

        let cleanedPrimary = mapper.cleanJSON(raw)
        let compactDecodedObjectHint = mapper.extractCompactDecodedObjectHint(
            cleaned: cleanedPrimary,
            userText: normalized
        )

        if let flatMapped = mapper.processSearchIntentFlatPipelineCanonical(
            cleaned: cleanedPrimary,
            userText: normalized,
            intent: intent
        ) {
            await diagnosticsStore?.record(
                .init(
                    attemptedLLM: true,
                    source: .llmFlatSummary,
                    compactCanonicalSummary: compactSummary(flatMapped)
                )
            )
            #if DEBUG
            print(
                "[SearchIntentExtractor] unwrapTextWrapperFallback=false " +
                "finalSource=llmFlatSummary summary=\(compactSummary(flatMapped))"
            )
            #endif
            return exchangeCanonicalTagged(flatMapped, .llmFlatSummary)
        }

        if let dto = mapper.decodeDTO(fromCleaned: cleanedPrimary),
           let mapped = mapper.mapDTO(dto, sourceText: normalized, intent: intent) {
            guard mapper.isMateriallyActionable(mapped) else {
                return await fallbackWith(
                    sourceText: normalized,
                    intent: intent,
                    reason: .nonActionableDTO,
                    elapsedMs: elapsedMs(from: start),
                    compactDecodedObjectHint: compactDecodedObjectHint
                )
            }
            await diagnosticsStore?.record(
                .init(
                    attemptedLLM: true,
                    source: .llm,
                    compactCanonicalSummary: compactSummary(mapped)
                )
            )
            #if DEBUG
            print(
                "[SearchIntentExtractor] unwrapTextWrapperFallback=false " +
                "finalSource=llm summary=\(compactSummary(mapped))"
            )
            #endif
            return exchangeCanonicalTagged(mapped, .llm)
        }

        if let innerText = Self.unwrapTextWrapperContent(from: raw) {
            let merged = Self.mergedUserTextAfterTextWrapperUnwrap(
                inner: innerText,
                normalizedUser: normalized
            )
            if let heuristic = fallbackExtractor.extract(sourceText: merged, intent: intent),
               mapper.isMateriallyActionable(heuristic) {
                let tagged = exchangeCanonicalTagged(heuristic, .heuristicFallback)
                await diagnosticsStore?.record(
                    .init(
                        attemptedLLM: true,
                        source: .heuristicFallback,
                        repairAttempted: true,
                        elapsedMs: elapsedMs(from: start),
                        decodeErrorSummary: "unwrapTextWrapperHeuristic",
                        compactCanonicalSummary: compactSummary(tagged)
                    )
                )
                #if DEBUG
                print(
                    "[SearchIntentExtractor] unwrapTextWrapperFallback=true " +
                    "finalSource=heuristicFallback summary=\(compactSummary(tagged))"
                )
                #endif
                return tagged
            }
            #if DEBUG
            print(
                "[SearchIntentExtractor] unwrapTextWrapperFallback=true " +
                "unwrapHeuristicMiss=true mergedChars=\(merged.count)"
            )
            #endif
        }

        let repaired = deterministicJSONRepair(raw)
        if let repaired {
            let cleanedRepair = mapper.cleanJSON(repaired)

            if let flatMapped = mapper.processSearchIntentFlatPipelineCanonical(
                cleaned: cleanedRepair,
                userText: normalized,
                intent: intent
            ) {
                await diagnosticsStore?.record(
                    .init(
                        attemptedLLM: true,
                        source: .llmFlatSummary,
                        repairAttempted: true,
                        elapsedMs: elapsedMs(from: start),
                        compactCanonicalSummary: compactSummary(flatMapped)
                    )
                )
                #if DEBUG
                print(
                    "[SearchIntentExtractor] repairAttempted=true " +
                    "finalSource=llmFlatSummary summary=\(compactSummary(flatMapped))"
                )
                #endif
                return exchangeCanonicalTagged(flatMapped, .llmFlatSummary)
            }

            if let dto = mapper.decodeDTO(fromCleaned: cleanedRepair),
               let mapped = mapper.mapDTO(dto, sourceText: normalized, intent: intent) {
                guard mapper.isMateriallyActionable(mapped) else {
                    return await fallbackWith(
                        sourceText: normalized,
                        intent: intent,
                        reason: .nonActionableDTO,
                        repairAttempted: true,
                        elapsedMs: elapsedMs(from: start)
                    )
                }
                await diagnosticsStore?.record(
                    .init(
                        attemptedLLM: true,
                        source: .llmRepairedJSON,
                        repairAttempted: true,
                        compactCanonicalSummary: compactSummary(mapped)
                    )
                )
                #if DEBUG
                print(
                    "[SearchIntentExtractor] unwrapTextWrapperFallback=false " +
                    "finalSource=llmRepairedJSON repairAttempted=true summary=\(compactSummary(mapped))"
                )
                #endif
                return exchangeCanonicalTagged(mapped, .llmRepairedJSON)
            }
        }

        let reason: SearchIntentExtractionFailureReason = repaired == nil ? .invalidJSON : .repairFailed
        return await fallbackWith(
            sourceText: normalized,
            intent: intent,
            reason: reason,
            repairAttempted: true,
            elapsedMs: elapsedMs(from: start),
            compactDecodedObjectHint: compactDecodedObjectHint
        )
    }

    public func lastExtractionDiagnostics() async -> SearchIntentExtractionDiagnostics? {
        await diagnosticsStore?.last
    }
}

private extension AsyncLLMOpenEndedSearchIntentExtractor {
    enum RawLLMJSONShape: String {
        case object
        case array
        case textWrapper
        case invalid
    }

    static func classifyRawLLMJSONShape(_ raw: String) -> RawLLMJSONShape {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .invalid }
        if t.hasPrefix("{") {
            if Self.unwrapJSONObjectSingleTextOnly(from: t) != nil { return .textWrapper }
            return .object
        }
        if t.hasPrefix("[") {
            if Self.unwrapJSONArraySingleTextOnly(from: t) != nil { return .textWrapper }
            return .array
        }
        return .invalid
    }

    static func unwrapTextWrapperContent(from raw: String) -> String? {
        if let inner = unwrapJSONArraySingleTextOnly(from: raw) { return inner }
        return unwrapJSONObjectSingleTextOnly(from: raw)
    }

    static func unwrapJSONArraySingleTextOnly(from raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("[") else { return nil }
        guard let data = t.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [Any],
              top.count == 1,
              let obj = top[0] as? [String: Any]
        else {
            return nil
        }
        return singleTextOnlyPayload(from: obj)
    }

    static func unwrapJSONObjectSingleTextOnly(from raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{") else { return nil }
        guard let data = t.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return singleTextOnlyPayload(from: obj)
    }

    static func singleTextOnlyPayload(from obj: [String: Any]) -> String? {
        let loweredKeys = Set(obj.keys.map { $0.lowercased() })
        guard loweredKeys == ["text"] else { return nil }
        let textKey = obj.keys.first { $0.lowercased() == "text" }!
        guard let val = obj[textKey] as? String else { return nil }
        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func mergedUserTextAfterTextWrapperUnwrap(inner: String, normalizedUser: String) -> String {
        let innerNorm = inner.lowercased()
        let userNorm = normalizedUser.lowercased()
        if innerNorm.isEmpty { return normalizedUser }
        if userNorm.contains(innerNorm) { return normalizedUser }
        return (normalizedUser + " " + inner)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fallbackWith(
        sourceText: String,
        intent: ExchangeIntent,
        reason: SearchIntentExtractionFailureReason,
        attemptedLLM: Bool = true,
        repairAttempted: Bool = false,
        elapsedMs: Int? = nil,
        decodeErrorSummary: String? = nil,
        compactDecodedObjectHint: String? = nil
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        await diagnosticsStore?.record(
            .init(
                attemptedLLM: attemptedLLM,
                source: .heuristicFallback,
                fallbackReason: reason,
                repairAttempted: repairAttempted,
                timeoutSeconds: nil,
                elapsedMs: elapsedMs,
                decodeErrorSummary: decodeErrorSummary,
                compactCanonicalSummary: nil,
                compactDecodedObjectHint: compactDecodedObjectHint
            )
        )
        #if DEBUG
        print(
            "[SearchIntentExtractor] unwrapTextWrapperFallback=false " +
            "finalSource=heuristicFallback reason=\(reason.rawValue) attemptedLLM=\(attemptedLLM) " +
            "repairAttempted=\(repairAttempted) elapsedMs=\(elapsedMs.map(String.init) ?? "nil") " +
            "returningNil=true likelyNonEnglish=\(ExchangeRetrievalEnglishProjection.containsSignificantNonEnglish(sourceText))"
        )
        #endif
        return nil
    }

    func deterministicJSONRepair(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}") else {
            return nil
        }
        var candidate = String(text[first...last])
        if let balanced = extractFirstBalancedJSONObject(candidate) {
            candidate = balanced
        }
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractFirstBalancedJSONObject(_ value: String) -> String? {
        var depth = 0
        var start: String.Index?
        for idx in value.indices {
            let ch = value[idx]
            if ch == "{" {
                if start == nil { start = idx }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let start {
                    return String(value[start...idx])
                }
                if depth < 0 { return nil }
            }
        }
        return nil
    }

    func compactSummary(_ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent) -> String {
        "object=\(si.objectType ?? "nil") places=\(si.places.count) semantic=\(si.semanticConcepts.count) commercial=\(si.commercialConstraints.count)"
    }

    func elapsedMs(from start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

extension LLMOpenEndedSearchIntentExtractor {
    func decodeDTO(_ raw: String) -> LLMSearchIntentExtractionDTO? {
        decodeDTO(fromCleaned: cleanJSON(raw))
    }

    func decodeDTO(fromCleaned cleaned: String) -> LLMSearchIntentExtractionDTO? {
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMSearchIntentExtractionDTO.self, from: data)
    }

    func decodeCompactSearchSummaryDTO(_ cleaned: String) -> SecretaryCompactSearchSummaryDTO? {
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SecretaryCompactSearchSummaryDTO.self, from: data)
    }

    /// Retains a safe atomic object hint from compact flat JSON even when full canonical mapping fails.
    func extractCompactDecodedObjectHint(cleaned: String, userText: String) -> String? {
        guard let compact = decodeCompactSearchSummaryDTO(cleaned) else { return nil }
        return preservedFlatObjectText(compact.object)
    }

    /// Applies offer-search object lane defaults using the final live interpretation route.
    func applyOfferSearchObjectLaneDefaults(
        to canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        guard queryIntentClass == .offerSearch else { return canonical }
        guard surfacePreference == .offer else { return canonical }
        guard let object = canonical.objectType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !object.isEmpty else { return canonical }

        var copy = canonical
        switch copy.domainCategory {
        case .homeService, .professionalService, .realEstate:
            return copy
        case .product:
            break
        case .general:
            copy.domainCategory = .product
        }

        switch copy.transactionIntent {
        case .buy, .forSale:
            break
        case .rent, .hire, .book, .inquire, .none:
            copy.transactionIntent = .buy
        }

        return copy
    }

    func decodeFlatSummaryDTO(_ cleaned: String) -> SecretarySearchRequestSummaryDTO? {
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SecretarySearchRequestSummaryDTO.self, from: data)
    }

    /// Compact JSON → full summary DTO (deterministic hints + heuristic recall seeds).
    func expandCompactSearchSummaryToFull(
        _ compact: SecretaryCompactSearchSummaryDTO,
        userText: String,
        intent: ExchangeIntent
    ) -> SecretarySearchRequestSummaryDTO {
        let normalizedUser = normalizeInput(userText)
        let seedPieces = [
            compact.raw.map { normalizeInput($0) },
            compact.object.map { normalizeInput($0) },
            compact.need.map { normalizeInput($0) }
        ].compactMap { $0 }.filter { !$0.isEmpty }
        let heuristicSeed = normalizeInput(seedPieces.joined(separator: " "))
        let textForHeuristic = heuristicSeed.isEmpty ? normalizedUser : heuristicSeed

        var categoryHint: String?
        var transactionIntentHint: String?
        var surfacePreferenceHint: String?
        var semanticAcc: [String] = []
        var recallAcc: [String] = []

        if !textForHeuristic.isEmpty,
           let canon = heuristicFallback.extract(sourceText: textForHeuristic, intent: intent) {
            categoryHint = canon.domainCategory.rawValue
            transactionIntentHint = canon.transactionIntent?.rawValue
            semanticAcc = Array(canon.semanticConcepts.prefix(config.maxSemanticConcepts))
            recallAcc = Array(canon.broadRecallTokens.prefix(config.maxBroadRecallTokens))
            switch canon.domainCategory {
            case .homeService, .professionalService:
                surfacePreferenceHint = "offer"
            case .realEstate, .product:
                surfacePreferenceHint = "offer"
            case .general:
                surfacePreferenceHint = "mixed"
            }
        }

        if transactionIntentHint == nil {
            transactionIntentHint = inferCompactTransactionHint(userLower: normalizedUser.lowercased())
        }
        if categoryHint == nil {
            categoryHint = inferCategoryHintFromLexicon(
                object: compact.object,
                need: compact.need,
                userLower: normalizedUser.lowercased()
            )
        }
        if surfacePreferenceHint == nil {
            if compact.object.map({ !normalizeInput($0).isEmpty }) == true {
                surfacePreferenceHint = "offer"
            } else {
                surfacePreferenceHint = "mixed"
            }
        }

        applyOfferSearchLaneHintsToCompactExpansion(
            compact: compact,
            categoryHint: &categoryHint,
            transactionIntentHint: &transactionIntentHint,
            surfacePreferenceHint: &surfacePreferenceHint
        )

        let timeLane = compact.time.map { normalizeInput($0) }.flatMap { $0.isEmpty ? nil : $0 }
        let availabilityLane = timeLane

        var expanded = SecretarySearchRequestSummaryDTO(
            rawNeedText: compact.raw.map { String(normalizeInput($0).prefix(500)) }.flatMap { $0.isEmpty ? nil : $0 },
            canonicalEnglishSearchText: compact.englishSearch.map { String(normalizeInput($0).prefix(500)) }.flatMap { $0.isEmpty ? nil : $0 },
            objectText: compact.object.map { String(normalizeInput($0).prefix(140)) }.flatMap { $0.isEmpty ? nil : $0 },
            needText: SearchIntentSentinelFilter.nilIfSentinel(
                compact.need.map { String(normalizeInput($0).prefix(500)) }.flatMap { $0.isEmpty ? nil : $0 }
            ),
            categoryHint: categoryHint,
            transactionIntentHint: transactionIntentHint,
            surfacePreferenceHint: compact.surfacePreference ?? surfacePreferenceHint,
            placeText: compact.place.map { String(normalizeInput($0).prefix(140)) }.flatMap { $0.isEmpty ? nil : $0 },
            timeText: timeLane,
            budgetText: compact.budget.map { String(normalizeInput($0).prefix(120)) }.flatMap { $0.isEmpty ? nil : $0 },
            commercialText: compact.commercial.map { String(normalizeInput($0).prefix(200)) }.flatMap { $0.isEmpty ? nil : $0 },
            availabilityText: availabilityLane,
            modifierTexts: normalizeFlatStringList(compact.mods, maxCount: 24),
            hardTexts: normalizeFlatStringList(compact.hard, maxCount: config.maxHardConstraints),
            softTexts: normalizeFlatStringList(compact.soft, maxCount: config.maxSoftPreferences),
            semanticTexts: normalizeFlatStringList(semanticAcc, maxCount: config.maxSemanticConcepts),
            broadRecallTokens: normalizeFlatStringList(recallAcc, maxCount: config.maxBroadRecallTokens),
            clarificationGaps: normalizeFlatStringList(compact.gaps, maxCount: config.maxClarificationGaps),
            confidence: compact.confidence.map { clampConfidence($0) },
            routeClassHint: compact.routeClass,
            targetKindHint: compact.targetKind,
            modeHint: compact.mode,
            routeConfidence: compact.routeConfidence.map { clampConfidence($0) },
            routeRationale: compact.routeRationale
        )
        seedObjectDiscoveryAnchors(into: &expanded)
        return expanded
    }

    /// When compact expansion has a concrete object but no recall/semantic lanes, seed retrieval tokens deterministically.
    private func seedObjectDiscoveryAnchors(into summary: inout SecretarySearchRequestSummaryDTO) {
        guard let object = summary.objectText.map({ normalizeInput($0) }), !object.isEmpty else { return }
        if summary.broadRecallTokens.isEmpty {
            summary.broadRecallTokens = normalizeFlatStringList(
                [object],
                maxCount: config.maxBroadRecallTokens
            )
        }
        if summary.semanticTexts.isEmpty {
            summary.semanticTexts = normalizeFlatStringList(
                [object],
                maxCount: config.maxSemanticConcepts
            )
        }
    }

    func inferCompactTransactionHint(userLower: String) -> String {
        if containsAny(userLower, ["buy ", "purchase"]) { return "buy" }
        if containsAny(userLower, ["rent ", "lease"]) { return "rent" }
        if containsAny(userLower, ["book "]) { return "book" }
        if containsAny(userLower, ["find me ", "find a ", "need someone", "need a "]) { return "hire" }
        if containsAny(userLower, ["find "]) { return "inquire" }
        return "inquire"
    }

    func inferCategoryHintFromLexicon(object: String?, need: String?, userLower: String) -> String? {
        let blob = ([object, need].compactMap { $0?.lowercased() } + [userLower]).joined(separator: " ")
        if containsAny(blob, ["roofer", "roofing", "plumber", "electrician", "contractor", "hvac"]) {
            return ExchangeIntentFacets.DomainCategory.homeService.rawValue
        }
        if containsAny(blob, ["lawyer", "attorney", "accountant", "photographer", "designer"]) {
            return ExchangeIntentFacets.DomainCategory.professionalService.rawValue
        }
        if containsAny(blob, ["house", "condo", "bedroom", "property", "mortgage"]) {
            return ExchangeIntentFacets.DomainCategory.realEstate.rawValue
        }
        return nil
    }

    /// Decode compact summary first, then legacy full flat DTO; validate and map to canonical.
    func processSearchIntentFlatPipelineCanonical(
        cleaned: String,
        userText: String,
        intent: ExchangeIntent
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        if let compactRaw = decodeCompactSearchSummaryDTO(cleaned) {
            let compact = enrichCompactSearchSummary(compactRaw, userText: userText)
            #if DEBUG
            print(
                "[SearchIntentExtractor] compactSummaryDecoded=true " +
                "confidence=\(compact.confidence.map { String(format: "%.2f", $0) } ?? "nil") " +
                "object=\(compact.object ?? "nil") place=\(compact.place ?? "nil") time=\(compact.time ?? "nil")"
            )
            #endif
            var full = expandCompactSearchSummaryToFull(compact, userText: userText, intent: intent)
            full = applySocialAffinityHintsToExpandedSummary(full, compact: compact, userText: userText)
            full = normalizeFlatSummaryStruct(full)
            #if DEBUG
            print(
                "[SearchIntentExtractor] compactSummaryExpanded=true " +
                "semanticCount=\(full.semanticTexts.count) recallCount=\(full.broadRecallTokens.count)"
            )
            #endif
            full = enrichFlatSummaryIfSparse(full, userText: userText, intent: intent)
            seedObjectDiscoveryAnchors(into: &full)
            return acceptCompactFlatPipelineCanonical(
                full,
                userText: userText,
                intent: intent
            )
        }

        if let flatDecoded = decodeFlatSummaryDTO(cleaned) {
            var enriched = enrichFlatSummaryIfSparse(flatDecoded, userText: userText, intent: intent)
            seedObjectDiscoveryAnchors(into: &enriched)
            guard let mapped = acceptCompactFlatPipelineCanonical(
                enriched,
                userText: userText,
                intent: intent
            ) else { return nil }
            #if DEBUG
            print(
                "[SearchIntentExtractor] flatSummaryDecoded=true " +
                "confidence=\(mapped.extractionConfidence.map { String(format: "%.2f", $0) } ?? "nil") " +
                "object=\(mapped.objectType ?? "nil") routeClass=\(mapped.extractedRoute?.routeClassRaw ?? "nil")"
            )
            #endif
            return mapped
        }

        return nil
    }

    private func acceptCompactFlatPipelineCanonical(
        _ full: SecretarySearchRequestSummaryDTO,
        userText: String,
        intent: ExchangeIntent
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        guard let validated = validateFlatSummary(full, userText: userText) else {
            #if DEBUG
            logCompactFlatPipelineGuardFailure(
                stage: "compactValidated=false",
                summary: full,
                userText: userText
            )
            if sourceTextLikelyNonEnglish(userText) {
                print(
                    "[SearchIntentExtractor][Multilingual] stage=compactValidated=false " +
                    "llmCanonicalExtractionFailed=true reason=flatSummaryValidationRejected"
                )
            }
            #endif
            return nil
        }

        let mappedCandidate = mapFlatSummaryToCanonicalSearchIntent(
            validated,
            sourceText: userText,
            intent: intent
        ) ?? retryMapFlatSummaryAfterObjectPreservation(
            validated,
            sourceText: userText,
            intent: intent
        )

        guard var mappedCandidate else {
            #if DEBUG
            logCompactFlatPipelineGuardFailure(
                stage: "compactMapped=false",
                summary: validated,
                userText: userText
            )
            #endif
            return nil
        }

        mappedCandidate = patchCanonicalFlatObjectIfNeeded(
            mappedCandidate,
            summary: validated,
            sourceText: userText
        )

        let mapped = applyOfferSearchObjectLaneDefaults(to: mappedCandidate)
        guard isMateriallyActionable(mapped) else {
            #if DEBUG
            logCompactFlatPipelineGuardFailure(
                stage: "compactActionable=false",
                summary: validated,
                mapped: mapped,
                userText: userText
            )
            #endif
            return nil
        }
        return mapped
    }

    /// When compact decode retained `objectText` but first mapping failed, retry once with the raw object lane intact.
    private func retryMapFlatSummaryAfterObjectPreservation(
        _ summary: SecretarySearchRequestSummaryDTO,
        sourceText: String,
        intent: ExchangeIntent
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        guard let objectRaw = summary.objectText.map({ normalizeInput($0) }), !objectRaw.isEmpty else {
            return nil
        }
        var retrySummary = summary
        retrySummary.objectText = objectRaw
        return mapFlatSummaryToCanonicalSearchIntent(
            retrySummary,
            sourceText: sourceText,
            intent: intent
        )
    }

    #if DEBUG
    private func logCompactFlatPipelineGuardFailure(
        stage: String,
        summary: SecretarySearchRequestSummaryDTO,
        mapped: ExchangeIntentFacets.ExchangeCanonicalSearchIntent? = nil,
        userText: String? = nil
    ) {
        let objectText = summary.objectText ?? "nil"
        let objectAfterSanitize = summary.objectText.flatMap {
            sanitizeText($0, role: .objectText, sentenceFingerprint: userText.map { compactSentenceFingerprint($0) })
        } ?? "nil"
        let rawNeedText = summary.rawNeedText ?? "nil"
        let categoryHint = summary.categoryHint ?? "nil"
        let surfacePreferenceHint = summary.surfacePreferenceHint ?? "nil"
        var line =
            "[SearchIntentExtractor][CompactGuard] \(stage) " +
            "objectBeforeSanitize=\(objectText) objectAfterSanitize=\(objectAfterSanitize) " +
            "rawNeedText=\(rawNeedText) categoryHint=\(categoryHint) surfacePreferenceHint=\(surfacePreferenceHint) " +
            "semanticCount=\(summary.semanticTexts.count) recallCount=\(summary.broadRecallTokens.count)"
        if let mapped {
            line +=
                " mappedObject=\(mapped.objectType ?? "nil") " +
                "domain=\(mapped.domainCategory.rawValue) tx=\(mapped.transactionIntent?.rawValue ?? "nil") " +
                "mappedRecall=\(mapped.broadRecallTokens.count) " +
                "routeClass=\(mapped.extractedRoute?.routeClassRaw ?? "nil")"
        }
        print(line)
    }
    #endif

    func validateFlatSummary(
        _ dto: SecretarySearchRequestSummaryDTO,
        userText: String
    ) -> SecretarySearchRequestSummaryDTO? {
        var copy = normalizeFlatSummaryStruct(dto)
        var warnings: [String] = []
        let confBefore = copy.confidence.map { clampConfidence($0) }

        let structuredHardAnchors = flatSummaryStructuredHardAnchorTexts(copy)
        // Multilingual requests often normalize constraints into English during flat-summary extraction.
        // Substring checks against the source-language user text are still useful for rejecting suspicious
        // freeform hardTexts, but must not discard hardTexts that anchor structured canonical fields.
        let filteredHard = copy.hardTexts.filter { phrase in
            let p = normalizeInput(phrase)
            guard !p.isEmpty else { return false }
            if flatSummaryHardTextMatchesStructuredAnchor(p, anchors: structuredHardAnchors) {
                return true
            }
            return userText.range(of: p, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        if filteredHard.count < copy.hardTexts.count {
            warnings.append("hardTextsDroppedNotInUserText")
        }
        copy.hardTexts = filteredHard

        if let rawPlace = copy.placeText.map({ normalizeInput($0) }), !rawPlace.isEmpty {
            if flatSummaryPlaceHasTimeContamination(rawPlace) {
                warnings.append("placeTextTimeContamination")
                if let comma = rawPlace.firstIndex(of: ",") {
                    let first = String(rawPlace[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !first.isEmpty, !flatSummaryPlaceHasTimeContamination(first) {
                        copy.placeText = first
                        warnings.append("placeTextSplitOnComma")
                    } else {
                        if copy.timeText == nil {
                            copy.timeText = rawPlace
                        } else {
                            copy.clarificationGaps.append("ambiguous place/time phrase: \(rawPlace)")
                        }
                        copy.placeText = nil
                    }
                } else {
                    if copy.timeText == nil {
                        copy.timeText = rawPlace
                    }
                    copy.clarificationGaps.append("placeText resembled schedule language: \(rawPlace)")
                    copy.placeText = nil
                }
                let prev = copy.confidence ?? 0.7
                copy.confidence = clampConfidence(prev - 0.15)
            }
        }

        if let tt = copy.timeText.map({ normalizeInput($0) }), !tt.isEmpty {
            if !timeTextLooksLikeTimeOrDate(tt, userText: userText) {
                warnings.append("timeTextWeakSignal")
                copy.softTexts = normalizeFlatStringList(copy.softTexts + [tt], maxCount: config.maxSoftPreferences)
                copy.timeText = nil
            }
        }

        let hasObject = copy.objectText.map { !normalizeInput($0).isEmpty } ?? false
        let hasNeed = copy.needText.map { !normalizeInput($0).isEmpty } ?? false
        if !hasObject, hasNeed {
            warnings.append("needTextWithoutObjectCapsConfidence")
        }

        var conf = confBefore ?? inferDefaultFlatSummaryConfidence(copy)
        if !hasObject, hasNeed {
            conf = min(conf, 0.75)
        }
        copy.confidence = clampConfidence(conf)

        if isMostlyEmptyFlatSummary(copy) {
            #if DEBUG
            print(
                "[SearchIntentExtractor][FlatSummaryValidation] warnings=\(warnings.joined(separator: ";")) " +
                "confidenceBefore=\(confBefore.map { String(format: "%.2f", $0) } ?? "nil") " +
                "confidenceAfter=\(copy.confidence.map { String(format: "%.2f", $0) } ?? "nil") outcome=empty"
            )
            #endif
            return nil
        }

        #if DEBUG
        print(
            "[SearchIntentExtractor][FlatSummaryValidation] warnings=\(warnings.joined(separator: ";")) " +
            "confidenceBefore=\(confBefore.map { String(format: "%.2f", $0) } ?? "nil") " +
            "confidenceAfter=\(copy.confidence.map { String(format: "%.2f", $0) } ?? "nil")"
        )
        #endif

        return copy
    }

    func enrichFlatSummaryIfSparse(
        _ dto: SecretarySearchRequestSummaryDTO,
        userText: String,
        intent: ExchangeIntent
    ) -> SecretarySearchRequestSummaryDTO {
        guard isMostlyEmptyFlatSummary(dto) else { return dto }
        let normalizedUser = normalizeInput(userText)
        guard !normalizedUser.isEmpty else { return dto }
        guard let canonical = heuristicFallback.extract(sourceText: normalizedUser, intent: intent) else {
            return dto
        }

        var m = dto

        if m.rawNeedText.map({ normalizeInput($0).isEmpty }) != false {
            m.rawNeedText = dto.rawNeedText ?? normalizedUser
        }

        if m.objectText.map({ normalizeInput($0).isEmpty }) != false {
            m.objectText = canonical.objectType
        }

        if m.categoryHint.map({ normalizeInput($0).isEmpty }) != false {
            m.categoryHint = canonical.domainCategory.rawValue
        }

        if m.transactionIntentHint.map({ normalizeInput($0).isEmpty }) != false {
            m.transactionIntentHint = canonical.transactionIntent?.rawValue
        }

        if m.placeText.map({ normalizeInput($0).isEmpty }) != false,
           let firstPlace = canonical.places.first?.normalizedText,
           !firstPlace.isEmpty {
            m.placeText = firstPlace
        }

        if m.timeText.map({ normalizeInput($0).isEmpty }) != false {
            var timeParts = canonical.timeConstraints.map(\.text)
            if let loose = extractLooseScheduleSnippet(from: normalizedUser) {
                timeParts.append(loose)
            }
            let joined = normalizeInput(timeParts.joined(separator: " "))
            if !joined.isEmpty {
                m.timeText = joined
            }
        }

        if m.availabilityText.map({ normalizeInput($0).isEmpty }) != false,
           let tt = m.timeText.map({ normalizeInput($0) }),
           !tt.isEmpty {
            m.availabilityText = tt
        }

        if m.budgetText.map({ normalizeInput($0).isEmpty }) != false,
           let budget = canonical.commercialConstraints.first(where: { $0.kind == .budget }) {
            m.budgetText = budget.value
        }

        if m.commercialText.map({ normalizeInput($0).isEmpty }) != false,
           let other = canonical.commercialConstraints.first(where: { $0.kind != .budget }) {
            m.commercialText = other.value
        }

        if m.modifierTexts.isEmpty, !canonical.attributes.isEmpty {
            m.modifierTexts = canonical.attributes.map { "\($0.key): \($0.value)" }
        }

        if m.semanticTexts.isEmpty, !canonical.semanticConcepts.isEmpty {
            m.semanticTexts = canonical.semanticConcepts
        } else if !canonical.semanticConcepts.isEmpty {
            m.semanticTexts = normalizeFlatStringList(m.semanticTexts + canonical.semanticConcepts, maxCount: 32)
        }

        if m.broadRecallTokens.isEmpty, !canonical.broadRecallTokens.isEmpty {
            m.broadRecallTokens = canonical.broadRecallTokens
        } else if !canonical.broadRecallTokens.isEmpty {
            m.broadRecallTokens = normalizeFlatStringList(m.broadRecallTokens + canonical.broadRecallTokens, maxCount: 32)
        }

        if m.hardTexts.isEmpty {
            let fromCanonical = canonical.hardConstraints.filter(\.isHardConstraint).map(\.value)
            if !fromCanonical.isEmpty {
                m.hardTexts = normalizeFlatStringList(fromCanonical, maxCount: 24)
            }
        }

        if m.softTexts.isEmpty {
            let softVals = canonical.softPreferences.map(\.value)
            if !softVals.isEmpty {
                m.softTexts = normalizeFlatStringList(softVals, maxCount: 24)
            }
        }

        if m.clarificationGaps.isEmpty, !canonical.clarificationGaps.isEmpty {
            m.clarificationGaps = canonical.clarificationGaps
        }

        if m.confidence == nil {
            m.confidence = 0.72
        }

        let normalizedMerge = normalizeFlatSummaryStruct(m)
        #if DEBUG
        if isMostlyEmptyFlatSummary(dto) && !isMostlyEmptyFlatSummary(normalizedMerge) {
            print("[SearchIntentExtractor][FlatSummaryHeuristicInflate] applied=true")
        }
        #endif
        return normalizedMerge
    }

    func extractLooseScheduleSnippet(from user: String) -> String? {
        let patterns = [
            #"(?i)\b(tomorrow|today|tonight|this weekend|next week)[^.!?\n]{0,56}\d{1,2}:\d{2}\s*(?:am|pm)?"#,
            #"(?i)\b\d{1,2}:\d{2}\s*(?:am|pm)\b"#
        ]
        let ns = user as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            if let match = regex.firstMatch(in: user, options: [], range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty {
                    return raw
                }
            }
        }
        return nil
    }

    func mapFlatSummaryToCanonicalSearchIntent(
        _ summary: SecretarySearchRequestSummaryDTO,
        sourceText: String,
        intent: ExchangeIntent
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        let sentenceFingerprint = compactSentenceFingerprint(sourceText)
        let conf = summary.confidence.map { clampConfidence($0) }

        let categoryForDomain = normalizeCategoryHintForDomain(summary.categoryHint)
        let mappedDomain = mapDomainHint(categoryForDomain, confidence: conf)
        let mappedTx = mapTransactionHint(summary.transactionIntentHint, confidence: conf)

        let objectType = resolvedFlatObjectType(
            rawObjectText: summary.objectText,
            sentenceFingerprint: sentenceFingerprint
        )

        let rawNeed = summary.rawNeedText.map { normalizeInput($0) }.flatMap { $0.isEmpty ? nil : String($0.prefix(500)) }
            ?? sourceText

        var places: [ExchangeIntentFacets.StructuredPlace] = []
        let structuredHardAnchors = flatSummaryStructuredHardAnchorTexts(summary)
        if let pRaw = summary.placeText.flatMap({
            sanitizeText($0, role: .location, sentenceFingerprint: sentenceFingerprint)
        }) {
            let isHard = flatPhraseIsExplicitHard(
                pRaw,
                hardTexts: summary.hardTexts,
                userText: sourceText,
                structuredAnchors: structuredHardAnchors
            )
            places.append(
                .init(
                    normalizedText: pRaw.lowercased(),
                    aliases: [],
                    confidence: clampConfidence(conf ?? 0.78),
                    isHard: isHard
                )
            )
        }

        var timeConstraints: [ExchangeIntentFacets.StructuredTimeConstraint] = []
        var timePieces: [String] = []
        if let t = summary.timeText.flatMap({
            sanitizeText($0, role: .constraint, sentenceFingerprint: sentenceFingerprint)
        }) {
            timePieces.append(t)
        }
        if let a = summary.availabilityText.flatMap({
            sanitizeText($0, role: .constraint, sentenceFingerprint: sentenceFingerprint)
        }) {
            let tNorm = summary.timeText.map { normalizeInput($0).lowercased() } ?? ""
            if a.lowercased() != tNorm {
                timePieces.append(a)
            }
        }
        let combinedTime = normalizeInput(timePieces.joined(separator: " / "))
        if !combinedTime.isEmpty {
            timeConstraints.append(
                .init(
                    kind: mapTimeKind(nil),
                    text: combinedTime.lowercased()
                )
            )
        }

        var commercialConstraints: [ExchangeIntentFacets.StructuredCommercialConstraint] = []
        if let budget = summary.budgetText.flatMap({
            sanitizeText($0, role: .constraint, sentenceFingerprint: sentenceFingerprint)
        }),
           let validatedBudget = ExchangeBudgetConstraintExtractor.validatedBudgetConstraintValue(from: budget) {
            let isHard = flatPhraseIsExplicitHard(budget, hardTexts: summary.hardTexts, userText: sourceText, structuredAnchors: structuredHardAnchors)
            commercialConstraints.append(
                .init(kind: .budget, key: "budget", value: validatedBudget, isHard: isHard)
            )
        }
        if let commercial = summary.commercialText.flatMap({
            sanitizeText($0, role: .constraint, sentenceFingerprint: sentenceFingerprint)
        }) {
            let kind = mapCommercialKind(nil, value: commercial)
            let key = defaultCommercialKey(for: kind, value: commercial)
            let isHard = flatPhraseIsExplicitHard(commercial, hardTexts: summary.hardTexts, userText: sourceText, structuredAnchors: structuredHardAnchors)
            commercialConstraints.append(
                .init(kind: kind, key: key, value: commercial, isHard: isHard)
            )
        }

        var preferences: [ExchangeIntentFacets.StructuredPreference] = []
        for mod in summary.modifierTexts.prefix(config.maxPreferences) {
            guard let v = sanitizeText(mod, sentenceFingerprint: sentenceFingerprint) else { continue }
            preferences.append(.init(key: "modifier", value: v, strength: .preferred))
        }
        for soft in summary.softTexts.prefix(config.maxPreferences) {
            guard let v = sanitizeText(soft, sentenceFingerprint: sentenceFingerprint) else { continue }
            preferences.append(.init(key: "soft", value: v, strength: .preferred))
        }

        var semanticSeeds: [String] = []
        if mappedDomain == nil, let catHint = summary.categoryHint.map({ normalizeInput($0) }), !catHint.isEmpty {
            semanticSeeds.append(catHint)
        }
        semanticSeeds.append(contentsOf: summary.semanticTexts)
        let needText = summary.needText.flatMap {
            sanitizeText($0, role: .needText, sentenceFingerprint: sentenceFingerprint)
        }
        if let needText {
            semanticSeeds.append(needText)
        }
        let semanticConcepts = sanitizeAtomicList(
            semanticSeeds,
            maxCount: config.maxSemanticConcepts,
            sentenceFingerprint: sentenceFingerprint
        )
        var recallSeeds = summary.broadRecallTokens
        if let needText {
            recallSeeds.append(needText)
        }
        let broadRecallTokens = sanitizeAtomicList(
            recallSeeds,
            maxCount: config.maxBroadRecallTokens,
            sentenceFingerprint: sentenceFingerprint
        )
        let clarificationGaps = sanitizeAtomicList(
            summary.clarificationGaps,
            maxCount: config.maxClarificationGaps,
            sentenceFingerprint: sentenceFingerprint
        )

        let hardConstraintTerms = sanitizeAtomicList(
            summary.hardTexts,
            maxCount: config.maxHardConstraints,
            sentenceFingerprint: sentenceFingerprint
        )
        var hardConstraints = hardConstraintTerms.map {
            ExchangeIntent.Constraint(key: "flatHard", value: $0, isHardConstraint: true)
        }
        if !combinedTime.isEmpty,
           flatPhraseIsExplicitHard(combinedTime, hardTexts: summary.hardTexts, userText: sourceText, structuredAnchors: structuredHardAnchors) {
            hardConstraints.append(
                ExchangeIntent.Constraint(key: "flatTime", value: combinedTime, isHardConstraint: true)
            )
        }

        let domain = mappedDomain ?? .general
        let extractedSurface = mapSurfacePreferenceHint(summary.surfacePreferenceHint, confidence: conf)
        let extractedRoute = buildExtractedRoute(from: summary)

        let hasAnySignal =
            objectType != nil ||
            !places.isEmpty ||
            !preferences.isEmpty ||
            !timeConstraints.isEmpty ||
            !commercialConstraints.isEmpty ||
            !semanticConcepts.isEmpty ||
            !broadRecallTokens.isEmpty ||
            !hardConstraints.isEmpty ||
            !clarificationGaps.isEmpty ||
            hasConfidentDiscoveryRouteSignal(from: summary)

        guard hasAnySignal else { return nil }

        let canonicalEnglishSearchText = summary.canonicalEnglishSearchText
            .map { normalizeInput($0) }
            .flatMap { $0.isEmpty ? nil : String($0.prefix(500)) }

        logMultilingualCanonicalEnglishCarrierDiagnostics(
            sourceText: sourceText,
            canonicalEnglishSearchText: canonicalEnglishSearchText,
            stage: "mapFlatSummaryToCanonicalSearchIntent"
        )

        commercialConstraints = ExchangeBudgetConstraintExtractor.enrichCommercialConstraintsWithBudget(
            commercialConstraints: commercialConstraints,
            hardConstraints: hardConstraints,
            canonicalEnglishSearchText: canonicalEnglishSearchText
        )

        return applyOfferSearchObjectLaneDefaults(
            to: ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: domain,
            objectType: objectType,
            transactionIntent: mappedTx,
            places: places,
            attributes: [],
            preferences: preferences,
            timeConstraints: timeConstraints,
            commercialConstraints: commercialConstraints,
            broadRecallTokens: broadRecallTokens,
            semanticConcepts: semanticConcepts,
            hardConstraints: hardConstraints,
            softPreferences: [],
            clarificationGaps: clarificationGaps,
            rawUserText: rawNeed,
            extractionConfidence: conf,
            extractedSurfacePreference: extractedSurface,
            extractedRoute: extractedRoute,
            canonicalEnglishSearchText: canonicalEnglishSearchText
        )
        )
    }

    func buildExtractedRoute(
        from summary: SecretarySearchRequestSummaryDTO
    ) -> ExchangeIntentFacets.ExtractedSearchRoute? {
        let hasRoute =
            summary.routeClassHint != nil
            || summary.surfacePreferenceHint != nil
            || summary.targetKindHint != nil
            || summary.modeHint != nil
            || summary.routeConfidence != nil
        guard hasRoute else { return nil }
        return ExchangeIntentFacets.ExtractedSearchRoute(
            routeClassRaw: summary.routeClassHint,
            surfacePreferenceRaw: summary.surfacePreferenceHint,
            targetKindRaw: summary.targetKindHint,
            modeRaw: summary.modeHint,
            routeConfidence: summary.routeConfidence,
            routeRationale: summary.routeRationale
        )
    }

    func mapDTO(
        _ dto: LLMSearchIntentExtractionDTO,
        sourceText: String,
        intent: ExchangeIntent
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        let lower = sourceText.lowercased()
        let confidence = dto.confidence
        let sentenceFingerprint = compactSentenceFingerprint(sourceText)

        let mappedDomain = mapDomainHint(dto.domainHint, confidence: confidence)
        let mappedTx = mapTransactionHint(dto.transactionIntentHint, confidence: confidence)

        let objectType = resolvedFlatObjectType(
            rawObjectText: dto.objectType,
            sentenceFingerprint: sentenceFingerprint
        )

        let places = Array(dto.places.prefix(config.maxPlaces)).compactMap { place -> ExchangeIntentFacets.StructuredPlace? in
            guard let text = sanitizeText(
                place.text,
                role: .location,
                sentenceFingerprint: sentenceFingerprint
            ) else { return nil }
            let aliases = sanitizeAtomicList(
                place.aliases ?? [],
                maxCount: 8,
                sentenceFingerprint: sentenceFingerprint
            )
            return .init(
                normalizedText: text.lowercased(),
                aliases: aliases.map { $0.lowercased() },
                confidence: clampConfidence(place.confidence ?? 0.75),
                isHard: place.isHard ?? false
            )
        }

        let attributes = Array(dto.attributes.prefix(config.maxAttributes)).compactMap { attr -> ExchangeIntentFacets.StructuredAttribute? in
            guard let key = sanitizeText(attr.key, sentenceFingerprint: sentenceFingerprint),
                  let value = sanitizeText(attr.value, sentenceFingerprint: sentenceFingerprint)
            else { return nil }
            return .init(
                key: key.lowercased(),
                value: value,
                numericValue: attr.numericValue
            )
        }

        let preferences = Array(dto.preferences.prefix(config.maxPreferences)).compactMap { pref -> ExchangeIntentFacets.StructuredPreference? in
            guard let key = sanitizeText(pref.key, sentenceFingerprint: sentenceFingerprint) else { return nil }
            let value = sanitizeText(pref.value, sentenceFingerprint: sentenceFingerprint)
            let strength = mapPreferenceStrength(pref.strength)
            return .init(
                key: key.lowercased(),
                value: value,
                strength: strength
            )
        }

        let timeConstraints = Array(dto.timeConstraints.prefix(config.maxTimeConstraints)).compactMap { tc -> ExchangeIntentFacets.StructuredTimeConstraint? in
            guard let text = sanitizeText(tc.text, sentenceFingerprint: sentenceFingerprint) else { return nil }
            return .init(
                kind: mapTimeKind(tc.kind),
                text: text.lowercased()
            )
        }

        let hasHardLanguage = containsAny(
            lower,
            ["must ", "must have", "only ", "required", "exact ", "exactly ", "has to ", "need to "]
        )

        var commercialConstraints = Array(dto.commercialConstraints.prefix(config.maxCommercialConstraints)).compactMap { item -> ExchangeIntentFacets.StructuredCommercialConstraint? in
            guard let value = sanitizeText(item.value, sentenceFingerprint: sentenceFingerprint) else { return nil }
            let kind = mapCommercialKind(item.kind, value: value)
            let key = sanitizeText(item.key, sentenceFingerprint: sentenceFingerprint) ?? defaultCommercialKey(for: kind, value: value)
            let hardFromPhrase = hasHardLanguage && mentionsFinancing(value.lowercased())
            let hard = (item.isHard ?? false) || hardFromPhrase
            if kind == .budget {
                guard let validatedBudget = ExchangeBudgetConstraintExtractor.validatedBudgetConstraintValue(from: value) else {
                    return nil
                }
                return .init(
                    kind: .budget,
                    key: key,
                    value: validatedBudget,
                    isHard: hard
                )
            }
            return .init(
                kind: kind,
                key: key,
                value: value,
                isHard: hard
            )
        }

        let semanticConcepts = sanitizeAtomicList(
            dto.semanticConcepts + [dto.domainHint, dto.transactionIntentHint].compactMap { $0 },
            maxCount: config.maxSemanticConcepts,
            sentenceFingerprint: sentenceFingerprint
        )
        let broadRecallTokens = sanitizeAtomicList(
            dto.broadRecallTokens,
            maxCount: config.maxBroadRecallTokens,
            sentenceFingerprint: sentenceFingerprint
        )
        let clarificationGaps = sanitizeAtomicList(
            dto.clarificationGaps,
            maxCount: config.maxClarificationGaps,
            sentenceFingerprint: sentenceFingerprint
        )
        let hardConstraintTerms = sanitizeAtomicList(
            dto.hardConstraints,
            maxCount: config.maxHardConstraints,
            sentenceFingerprint: sentenceFingerprint
        )
        let softPreferenceTerms = sanitizeAtomicList(
            dto.softPreferences,
            maxCount: config.maxSoftPreferences,
            sentenceFingerprint: sentenceFingerprint
        )

        let hardConstraints = hardConstraintTerms.map {
            ExchangeIntent.Constraint(key: "llmHard", value: $0, isHardConstraint: true)
        }
        let softPreferences = softPreferenceTerms.map {
            ExchangeIntent.Constraint(key: "llmSoft", value: $0, isHardConstraint: false)
        }

        let domain = mappedDomain ?? .general
        let transaction = mappedTx

        // Empty / unsafe DTO should not suppress fallback.
        let hasAnySignal =
            objectType != nil ||
            !places.isEmpty ||
            !attributes.isEmpty ||
            !preferences.isEmpty ||
            !timeConstraints.isEmpty ||
            !commercialConstraints.isEmpty ||
            !semanticConcepts.isEmpty ||
            !broadRecallTokens.isEmpty ||
            !hardConstraints.isEmpty ||
            !softPreferences.isEmpty
        guard hasAnySignal else { return nil }

        commercialConstraints = ExchangeBudgetConstraintExtractor.enrichCommercialConstraintsWithBudget(
            commercialConstraints: commercialConstraints,
            hardConstraints: hardConstraints,
            canonicalEnglishSearchText: nil
        )

        return applyOfferSearchObjectLaneDefaults(
            to: ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: domain,
            objectType: objectType,
            transactionIntent: transaction,
            places: places,
            attributes: attributes,
            preferences: preferences,
            timeConstraints: timeConstraints,
            commercialConstraints: commercialConstraints,
            broadRecallTokens: broadRecallTokens,
            semanticConcepts: semanticConcepts,
            hardConstraints: hardConstraints,
            softPreferences: softPreferences,
            clarificationGaps: clarificationGaps,
            rawUserText: sourceText
        )
        )
    }

    func mapDomainHint(
        _ rawHint: String?,
        confidence: Double?
    ) -> ExchangeIntentFacets.DomainCategory? {
        guard let hint = rawHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !hint.isEmpty else { return nil }

        let meetsConfidence = (confidence ?? 0.0) >= config.minConfidenceForEnumMapping
        let exactOnly = confidence == nil
        guard meetsConfidence || exactOnly else { return nil }

        let exactMap: [String: ExchangeIntentFacets.DomainCategory] = [
            "real estate": .realEstate,
            "home service": .homeService,
            "homeservice": .homeService,
            "professional service": .professionalService,
            "professionalservice": .professionalService,
            "product": .product,
            "general": .general
        ]
        if let exact = exactMap[hint] { return exact }
        guard !exactOnly else { return nil }

        if hint.contains("real estate") || hint.contains("property") {
            return .realEstate
        }
        if hint.contains("home service") || hint.contains("homeservice") || hint.contains("contractor") || hint.contains("trades") {
            return .homeService
        }
        if hint.contains("professional service") || hint.contains("professionalservice") || hint.contains("expert") || hint.contains("advisor") {
            return .professionalService
        }
        if hint.contains("product") || hint.contains("goods") {
            return .product
        }
        return nil
    }

    func mapTransactionHint(
        _ rawHint: String?,
        confidence: Double?
    ) -> ExchangeIntentFacets.TransactionIntent? {
        guard let hint = rawHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !hint.isEmpty else { return nil }

        let meetsConfidence = (confidence ?? 0.0) >= config.minConfidenceForEnumMapping
        let exactOnly = confidence == nil
        guard meetsConfidence || exactOnly else { return nil }

        let exactMap: [String: ExchangeIntentFacets.TransactionIntent] = [
            "for sale": .forSale,
            "rent": .rent,
            "hire": .hire,
            "buy": .buy,
            "book": .book,
            "inquire": .inquire,
            "find": .inquire,
            "contact": .inquire
        ]
        if let exact = exactMap[hint] { return exact }
        guard !exactOnly else { return nil }

        if hint.contains("sale") { return .forSale }
        if hint.contains("rent") || hint.contains("lease") { return .rent }
        if hint.contains("hire") || hint.contains("contract") { return .hire }
        if hint.contains("buy") || hint.contains("purchase") { return .buy }
        if hint.contains("book") || hint.contains("schedule") { return .book }
        if hint.contains("inquire") || hint.contains("ask") || hint.contains("find") || hint.contains("contact") {
            return .inquire
        }
        return nil
    }

    func mapPreferenceStrength(_ raw: String?) -> ExchangeIntentFacets.StructuredPreference.Strength {
        let lower = raw?.lowercased() ?? ""
        if lower.contains("required") || lower.contains("must") || lower.contains("hard") {
            return .required
        }
        if lower.contains("optional") || lower.contains("nice") {
            return .optional
        }
        return .preferred
    }

    func mapTimeKind(_ raw: String?) -> ExchangeIntentFacets.StructuredTimeConstraint.Kind {
        let lower = raw?.lowercased() ?? ""
        if lower.contains("immediate") || lower.contains("urgent") { return .immediate }
        if lower.contains("range") || lower.contains("window") { return .range }
        if lower.contains("specific") || lower.contains("exact") { return .specific }
        if lower.contains("flex") { return .flexible }
        return .day
    }

    func mapCommercialKind(
        _ raw: String?,
        value: String
    ) -> ExchangeIntentFacets.StructuredCommercialConstraint.Kind {
        let lower = (raw ?? value).lowercased()
        if lower.contains("financ") || lower.contains("mortgage") || lower.contains("payment plan") {
            return .financing
        }
        if lower.contains("budget") || lower.contains("price") || lower.contains("cost") {
            return .budget
        }
        if lower.contains("payment") || lower.contains("term") || lower.contains("deposit") {
            return .paymentTerm
        }
        return .other
    }

    func defaultCommercialKey(
        for kind: ExchangeIntentFacets.StructuredCommercialConstraint.Kind,
        value: String
    ) -> String {
        switch kind {
        case .financing:
            return "financing"
        case .budget:
            return "budget"
        case .paymentTerm:
            return "paymentTerm"
        case .other:
            let sanitized = sanitizeText(value, sentenceFingerprint: nil)?
                .lowercased()
                .replacingOccurrences(of: " ", with: "_") ?? "commercial"
            return String(sanitized.prefix(40))
        }
    }

    func isMateriallyActionable(_ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent) -> Bool {
        let hasTargetAxis =
            (si.objectType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ||
            si.domainCategory != .general ||
            !si.semanticConcepts.isEmpty

        let hasDiscoveryAnchor =
            !si.places.isEmpty ||
            !si.commercialConstraints.isEmpty ||
            !si.attributes.isEmpty ||
            !si.preferences.isEmpty ||
            !si.timeConstraints.isEmpty ||
            !si.broadRecallTokens.isEmpty ||
            !si.softPreferences.isEmpty

        if hasTargetAxis && hasDiscoveryAnchor {
            return true
        }

        if hasTargetAxis, hasAuthoritativeProviderStyleRoute(si) {
            return true
        }

        if hasConfidentProviderCapabilityRouteOnly(si) {
            return true
        }

        if hasConfidentObjectOnlyTarget(si) {
            return true
        }

        return false
    }

    private func hasAuthoritativeProviderStyleRoute(
        _ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        guard let route = si.extractedRoute,
              let confidence = route.routeConfidence,
              confidence >= SearchIntentRouteValidator.minRouteConfidence,
              let routeClassRaw = SearchIntentSentinelFilter.nilIfSentinel(route.routeClassRaw),
              let queryClass = ExchangeIntent.QueryIntentClass(rawValue: routeClassRaw)
        else {
            return false
        }
        switch queryClass {
        case .providerSearch, .capabilitySearch:
            if let object = si.objectType?.trimmingCharacters(in: .whitespacesAndNewlines),
               !object.isEmpty {
                return true
            }
            return false
        case .offerSearch:
            return si.objectType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        default:
            return false
        }
    }

    private func hasConfidentProviderCapabilityRouteOnly(
        _ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        guard let route = si.extractedRoute,
              let confidence = route.routeConfidence,
              confidence >= SearchIntentRouteValidator.minRouteConfidence,
              let routeClassRaw = SearchIntentSentinelFilter.nilIfSentinel(route.routeClassRaw),
              let queryClass = ExchangeIntent.QueryIntentClass(rawValue: routeClassRaw)
        else {
            return false
        }
        switch queryClass {
        case .providerSearch, .capabilitySearch:
            return true
        default:
            return false
        }
    }

    private func isDeicticObjectPhrase(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "this", "that", "it", "these", "those":
            return true
        default:
            return false
        }
    }

    private func hasConfidentObjectOnlyTarget(
        _ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        guard let object = si.objectType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !object.isEmpty,
              object.count >= 3
        else {
            return false
        }
        let confidence = si.extractionConfidence ?? 0
        return confidence >= SearchIntentRouteValidator.minRouteConfidence
    }

    func sanitizeAtomicList(
        _ values: [String],
        maxCount: Int,
        sentenceFingerprint: String?
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for raw in values {
            guard let clean = sanitizeText(raw, sentenceFingerprint: sentenceFingerprint) else { continue }
            let low = clean.lowercased()
            guard !seen.contains(low) else { continue }
            seen.insert(low)
            out.append(clean)
            if out.count >= maxCount { break }
        }
        return out
    }

    func preservedFlatObjectText(_ rawObjectText: String?) -> String? {
        guard let collapsed = rawObjectText.map({ normalizeInput($0) }), !collapsed.isEmpty else {
            return nil
        }
        guard !SearchIntentSentinelFilter.isSentinel(collapsed) else { return nil }
        guard !isClauseFusedAtomic(collapsed) else { return nil }
        if isDeicticObjectPhrase(collapsed) {
            return String(collapsed.prefix(140))
        }
        guard isAtomicObjectPhrase(collapsed), !isObviousFullSentence(collapsed) else { return nil }
        return String(collapsed.prefix(140))
    }

    /// Atomic object suitable for deterministic route repair (excludes deictic/junk phrases).
    func validAtomicObjectForRouteRepair(_ rawObjectText: String?) -> String? {
        guard let collapsed = rawObjectText.map({ normalizeInput($0) }), !collapsed.isEmpty else {
            return nil
        }
        guard !isDeicticObjectPhrase(collapsed) else { return nil }
        return preservedFlatObjectText(rawObjectText)
    }

    func resolvedFlatObjectType(
        rawObjectText: String?,
        sentenceFingerprint: String
    ) -> String? {
        let rawLabel = rawObjectText ?? "nil"
        if let sanitized = sanitizeText(
            rawObjectText,
            role: .objectText,
            sentenceFingerprint: sentenceFingerprint
        ) {
            #if DEBUG
            if let rawObjectText,
               normalizeInput(rawObjectText) != sanitized {
                print(
                    "[SearchIntentObjectPreserve] rawObject=\(rawLabel) " +
                    "sanitizedObject=\(sanitized) preserved=\(sanitized) reason=sanitizeText"
                )
            }
            #endif
            return sanitized
        }
        guard let preserved = preservedFlatObjectText(rawObjectText) else {
            return nil
        }
        #if DEBUG
        print(
            "[SearchIntentObjectPreserve] rawObject=\(rawLabel) " +
            "sanitizedObject=nil preserved=\(preserved) reason=atomicFallback"
        )
        #endif
        return preserved
    }

    func hasConfidentDiscoveryRouteSignal(
        from summary: SecretarySearchRequestSummaryDTO
    ) -> Bool {
        guard let route = buildExtractedRoute(from: summary),
              let routeClassRaw = SearchIntentSentinelFilter.nilIfSentinel(route.routeClassRaw),
              let queryClass = ExchangeIntent.QueryIntentClass(rawValue: routeClassRaw),
              let confidence = route.routeConfidence.map({ min(max($0, 0.0), 1.0) }),
              confidence >= SearchIntentRouteValidator.minRouteConfidence
        else {
            return false
        }

        switch queryClass {
        case .providerSearch, .offerSearch, .capabilitySearch,
             .generalDiscovery, .socialAffinitySearch, .relationshipSearch:
            return true
        case .collaborationSearch, .directOutreach, .followUp, .statusCheck:
            return false
        }
    }

    func patchCanonicalFlatObjectIfNeeded(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        summary: SecretarySearchRequestSummaryDTO,
        sourceText: String
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        if let existing = canonical.objectType?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return canonical
        }
        let sentenceFingerprint = compactSentenceFingerprint(sourceText)
        guard let objectType = resolvedFlatObjectType(
            rawObjectText: summary.objectText,
            sentenceFingerprint: sentenceFingerprint
        ) else {
            return canonical
        }
        var copy = canonical
        copy.objectType = objectType
        return copy
    }

    enum SanitizedFieldRole: Sendable, Hashable {
        case objectText
        case needText
        case location
        case constraint
        case generic
    }

    func sanitizeText(
        _ value: String?,
        role: SanitizedFieldRole = .generic,
        sentenceFingerprint: String?
    ) -> String? {
        guard let value else { return nil }
        let collapsed = normalizeInput(value)
        guard !collapsed.isEmpty else { return nil }
        guard !SearchIntentSentinelFilter.isSentinel(collapsed) else { return nil }
        guard !isClauseFusedAtomic(collapsed) else { return nil }
        if role == .objectText, isAtomicObjectPhrase(collapsed), !isObviousFullSentence(collapsed) {
            return String(collapsed.prefix(140))
        }
        if let sentenceFingerprint, compactSentenceFingerprint(collapsed) == sentenceFingerprint {
            return nil
        }
        return String(collapsed.prefix(140))
    }

    func isAtomicObjectPhrase(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isObviousFullSentence(trimmed) else { return false }
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return tokens.count <= 3
    }

    func isObviousFullSentence(_ value: String) -> Bool {
        if value.contains("?") || value.contains("!") { return true }
        guard let last = value.last else { return false }
        if last == ".", value.filter({ $0 == "." }).count == 1, !value.contains("..") {
            let withoutTerminal = String(value.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            return withoutTerminal.split(whereSeparator: { $0.isWhitespace }).count >= 4
        }
        return false
    }

    func applyOfferSearchObjectLaneDefaults(
        to canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        var copy = canonical
        guard isOfferSearchOfferSurfaceRoute(copy) else { return copy }
        guard let object = copy.objectType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !object.isEmpty else { return copy }

        switch copy.domainCategory {
        case .homeService, .professionalService, .realEstate:
            return copy
        case .product:
            break
        case .general:
            copy.domainCategory = .product
        }

        switch copy.transactionIntent {
        case .buy, .forSale:
            break
        case .rent, .hire, .book, .inquire, .none:
            copy.transactionIntent = .buy
        }

        return copy
    }

    private func isOfferSearchOfferSurfaceRoute(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        guard let routeClass = canonical.extractedRoute?.routeClassRaw,
              routeClass == ExchangeIntent.QueryIntentClass.offerSearch.rawValue else {
            return false
        }

        let surfaceRaw = canonical.extractedRoute?.surfacePreferenceRaw
            ?? canonical.extractedSurfacePreference?.rawValue
        guard let surfaceRaw else { return true }
        return surfaceRaw == ExchangeIntent.SurfacePreference.offer.rawValue
    }

    private func applyOfferSearchLaneHintsToCompactExpansion(
        compact: SecretaryCompactSearchSummaryDTO,
        categoryHint: inout String?,
        transactionIntentHint: inout String?,
        surfacePreferenceHint: inout String?
    ) {
        guard compact.routeClass == ExchangeIntent.QueryIntentClass.offerSearch.rawValue else { return }
        guard compact.object.map({ !normalizeInput($0).isEmpty }) == true else { return }

        let surface = (compact.surfacePreference ?? surfacePreferenceHint)?.lowercased()
        guard surface == ExchangeIntent.SurfacePreference.offer.rawValue || surface == nil else { return }

        if isExplicitServiceOrSocialCategoryHint(categoryHint) {
            return
        }

        if categoryHint == nil || normalizeCategoryHintForDomain(categoryHint) == ExchangeIntentFacets.DomainCategory.general.rawValue {
            categoryHint = ExchangeIntentFacets.DomainCategory.product.rawValue
        }

        switch transactionIntentHint?.lowercased() {
        case "buy", "for sale", "forsale":
            break
        default:
            transactionIntentHint = ExchangeIntentFacets.TransactionIntent.buy.rawValue
        }

        if surfacePreferenceHint == nil {
            surfacePreferenceHint = ExchangeIntent.SurfacePreference.offer.rawValue
        }
    }

    private func isExplicitServiceOrSocialCategoryHint(_ raw: String?) -> Bool {
        guard let normalized = normalizeCategoryHintForDomain(raw) else { return false }
        switch normalized {
        case ExchangeIntentFacets.DomainCategory.homeService.rawValue,
             ExchangeIntentFacets.DomainCategory.professionalService.rawValue,
             ExchangeIntentFacets.DomainCategory.realEstate.rawValue:
            return true
        default:
            return false
        }
    }

    func sanitizeText(_ value: String?, sentenceFingerprint: String?) -> String? {
        sanitizeText(value, role: .generic, sentenceFingerprint: sentenceFingerprint)
    }

    func mentionsFinancing(_ value: String) -> Bool {
        containsAny(value, ["seller financing", "vendor take back", "vtb", "mortgage", "financing"])
    }

    func isClauseFusedAtomic(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains(", and ") || lower.contains("\n")
    }

    func cleanJSON(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let extracted: String
        if trimmed.hasPrefix("```"), let first = trimmed.range(of: "{"), let last = trimmed.range(of: "}", options: .backwards) {
            extracted = String(trimmed[first.lowerBound...last.upperBound])
        } else {
            extracted = trimmed
        }
        return SearchIntentExtractionFlatSummaryJSONRepair.repairEscapedKeyValueSeparators(extracted)
    }

    func normalizeFlatStringList(_ values: [String], maxCount: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in SearchIntentSentinelFilter.filterSentinels(values) {
            let t = normalizeInput(raw)
            guard !t.isEmpty else { continue }
            let low = t.lowercased()
            guard !seen.contains(low) else { continue }
            seen.insert(low)
            out.append(String(t.prefix(200)))
            if out.count >= maxCount { break }
        }
        return out
    }

    func normalizeFlatSummaryStruct(_ dto: SecretarySearchRequestSummaryDTO) -> SecretarySearchRequestSummaryDTO {
        SecretarySearchRequestSummaryDTO(
            rawNeedText: dto.rawNeedText.map { String(normalizeInput($0).prefix(500)) }.flatMap { $0.isEmpty ? nil : $0 },
            canonicalEnglishSearchText: dto.canonicalEnglishSearchText
                .map { String(normalizeInput($0).prefix(500)) }
                .flatMap { $0.isEmpty ? nil : $0 },
            objectText: dto.objectText.map { String(normalizeInput($0).prefix(140)) }.flatMap { $0.isEmpty ? nil : $0 },
            needText: SearchIntentSentinelFilter.nilIfSentinel(
                dto.needText.map { String(normalizeInput($0).prefix(500)) }.flatMap { $0.isEmpty ? nil : $0 }
            ),
            categoryHint: dto.categoryHint.map { String(normalizeInput($0).prefix(80)) }.flatMap { $0.isEmpty ? nil : $0 },
            transactionIntentHint: dto.transactionIntentHint.map { String(normalizeInput($0).prefix(80)) }.flatMap { $0.isEmpty ? nil : $0 },
            surfacePreferenceHint: dto.surfacePreferenceHint.map { String(normalizeInput($0).prefix(40)) }.flatMap { $0.isEmpty ? nil : $0 },
            placeText: dto.placeText.map { String(normalizeInput($0).prefix(140)) }.flatMap { $0.isEmpty ? nil : $0 },
            timeText: dto.timeText.map { String(normalizeInput($0).prefix(200)) }.flatMap { $0.isEmpty ? nil : $0 },
            budgetText: dto.budgetText.map { String(normalizeInput($0).prefix(120)) }.flatMap { $0.isEmpty ? nil : $0 },
            commercialText: dto.commercialText.map { String(normalizeInput($0).prefix(200)) }.flatMap { $0.isEmpty ? nil : $0 },
            availabilityText: dto.availabilityText.map { String(normalizeInput($0).prefix(200)) }.flatMap { $0.isEmpty ? nil : $0 },
            modifierTexts: normalizeFlatStringList(dto.modifierTexts, maxCount: 24),
            hardTexts: normalizeFlatStringList(dto.hardTexts, maxCount: 24),
            softTexts: normalizeFlatStringList(dto.softTexts, maxCount: 24),
            semanticTexts: normalizeFlatStringList(dto.semanticTexts, maxCount: 32),
            broadRecallTokens: normalizeFlatStringList(dto.broadRecallTokens, maxCount: 32),
            clarificationGaps: normalizeFlatStringList(dto.clarificationGaps, maxCount: 16),
            confidence: dto.confidence.map { clampConfidence($0) },
            routeClassHint: SearchIntentSentinelFilter.nilIfSentinel(dto.routeClassHint),
            targetKindHint: SearchIntentSentinelFilter.nilIfSentinel(dto.targetKindHint),
            modeHint: SearchIntentSentinelFilter.nilIfSentinel(dto.modeHint),
            routeConfidence: dto.routeConfidence.map { clampConfidence($0) },
            routeRationale: SearchIntentSentinelFilter.nilIfSentinel(dto.routeRationale)
        )
    }

    func flatSummaryPlaceHasTimeContamination(_ place: String) -> Bool {
        let s = place.lowercased()
        let markers = [
            "today", "tomorrow", "tonight", "weekend", "next week", "this week",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            " am", " pm", "morning", "afternoon", "evening", "noon", "midnight"
        ]
        if markers.contains(where: { s.contains($0) }) { return true }
        if s.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"\bat\s+\d"#, options: .regularExpression) != nil { return true }
        return false
    }

    func timeTextLooksLikeTimeOrDate(_ text: String, userText: String) -> Bool {
        let t = text.lowercased()
        if userText.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }
        let markers = [
            "today", "tomorrow", "tonight", "weekend", "week", "month",
            "am", "pm", ":", "morning", "afternoon", "evening",
            "before ", "after ", "by ", "until ", "next ", "this "
        ]
        return markers.contains { t.contains($0) }
    }

    func isMostlyEmptyFlatSummary(_ s: SecretarySearchRequestSummaryDTO) -> Bool {
        let hasObj = s.objectText.map { !normalizeInput($0).isEmpty } ?? false
        let hasNeed = s.needText.map { !normalizeInput($0).isEmpty } ?? false
        let hasPlace = s.placeText.map { !normalizeInput($0).isEmpty } ?? false
        let hasTime = (s.timeText.map { !normalizeInput($0).isEmpty } ?? false)
            || (s.availabilityText.map { !normalizeInput($0).isEmpty } ?? false)
        let hasSemantic = !s.semanticTexts.isEmpty || !s.broadRecallTokens.isEmpty
        let hasCommercial = (s.budgetText.map { !normalizeInput($0).isEmpty } ?? false)
            || (s.commercialText.map { !normalizeInput($0).isEmpty } ?? false)
        let hasConstraintLanes = !s.modifierTexts.isEmpty || !s.softTexts.isEmpty || !s.hardTexts.isEmpty
        return !hasObj && !hasNeed && !hasPlace && !hasTime && !hasSemantic && !hasCommercial && !hasConstraintLanes
    }

    func inferDefaultFlatSummaryConfidence(_ s: SecretarySearchRequestSummaryDTO) -> Double {
        let hasObject = s.objectText.map { !normalizeInput($0).isEmpty } ?? false
        let hasNeed = s.needText.map { !normalizeInput($0).isEmpty } ?? false
        let hasPlace = s.placeText.map { !normalizeInput($0).isEmpty } ?? false
        let hasTime = (s.timeText.map { !normalizeInput($0).isEmpty } ?? false)
            || (s.availabilityText.map { !normalizeInput($0).isEmpty } ?? false)
        if hasObject, hasPlace || hasTime { return 0.8 }
        if hasNeed, !hasObject { return 0.6 }
        return 0.35
    }

    func normalizeCategoryHintForDomain(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        var out = ""
        for ch in raw {
            if ch.isUppercase, !out.isEmpty, out.last != " " {
                out.append(" ")
            }
            out.append(ch)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func sourceTextLikelyNonEnglish(_ text: String) -> Bool {
        ExchangeRetrievalEnglishProjection.containsSignificantNonEnglish(text)
    }

    func logMultilingualCanonicalEnglishCarrierDiagnostics(
        sourceText: String,
        canonicalEnglishSearchText: String?,
        stage: String
    ) {
        #if DEBUG
        guard sourceTextLikelyNonEnglish(sourceText) else { return }
        let hasCarrier = canonicalEnglishSearchText.map {
            !normalizeInput($0).isEmpty
        } ?? false
        if !hasCarrier {
            print(
                "[SearchIntentExtractor][Multilingual] stage=\(stage) " +
                "missingCanonicalEnglishSearchText=true sourceLength=\(sourceText.count)"
            )
        }
        #endif
    }

    func flatSummaryStructuredHardAnchorTexts(_ summary: SecretarySearchRequestSummaryDTO) -> Set<String> {
        var anchors: Set<String> = []
        func add(_ raw: String?) {
            guard let normalized = raw.map({ normalizeInput($0) }), !normalized.isEmpty else { return }
            anchors.insert(normalized.lowercased())
        }
        add(summary.placeText)
        add(summary.timeText)
        add(summary.availabilityText)
        add(summary.budgetText)
        add(summary.commercialText)
        add(summary.objectText)
        add(summary.needText)
        return anchors
    }

    func flatSummaryHardTextMatchesStructuredAnchor(_ phrase: String, anchors: Set<String>) -> Bool {
        let normalized = normalizeInput(phrase).lowercased()
        guard !normalized.isEmpty else { return false }
        if anchors.contains(normalized) { return true }
        return anchors.contains { anchor in
            anchor.contains(normalized) || normalized.contains(anchor)
        }
    }

    func flatPhraseIsExplicitHard(
        _ phrase: String,
        hardTexts: [String],
        userText: String,
        structuredAnchors: Set<String> = []
    ) -> Bool {
        let trimmed = normalizeInput(phrase)
        guard !trimmed.isEmpty else { return false }
        if flatSummaryHardTextMatchesStructuredAnchor(trimmed, anchors: structuredAnchors) {
            return true
        }
        if userText.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }
        let pl = trimmed.lowercased()
        return hardTexts.contains { normalizeInput($0).lowercased() == pl }
    }

    func mapSurfacePreferenceHint(
        _ raw: String?,
        confidence: Double?
    ) -> ExchangeIntent.SurfacePreference? {
        guard let hint = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !hint.isEmpty else { return nil }
        if let c = confidence, c < 0.55 { return nil }
        switch hint {
        case "offer": return .offer
        case "capability": return .capability
        case "affinity": return .affinity
        case "profile": return .capability
        case "mixed": return .mixed
        default: return nil
        }
    }

    func normalizeInput(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func compactSentenceFingerprint(_ value: String) -> String {
        normalizeInput(value).lowercased().replacingOccurrences(of: " ", with: "")
    }

    func clampConfidence(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
}

fileprivate func exchangeCanonicalTagged(
    _ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
    _ source: SearchIntentExtractionSource
) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
    var copy = si
    copy.extractionSource = source
    return copy
}
