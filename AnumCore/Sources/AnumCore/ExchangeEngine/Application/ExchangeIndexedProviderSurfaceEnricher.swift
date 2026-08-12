import Foundation

public protocol ExchangeIndexedProviderSurfaceEnricher: Sendable {
    func enrich(
        surface: ExchangeIndexedProviderSurface
    ) async -> ExchangeIndexedProviderSurface
}

public struct NoopIndexedProviderSurfaceEnricher: ExchangeIndexedProviderSurfaceEnricher, Sendable {
    public init() {}

    public func enrich(
        surface: ExchangeIndexedProviderSurface
    ) async -> ExchangeIndexedProviderSurface {
        surface
    }
}

public protocol AsyncProviderSurfaceEnrichmentJSONProvider: Sendable {
    func isReadyForImmediateExtraction() async -> Bool
    func enrichProviderSurfaceJSON(prompt: String) async throws -> String
}

public protocol ProviderSurfaceEnrichmentBusyError: Error {}
public protocol ProviderSurfaceEnrichmentUnavailableError: Error {}

public enum ProviderSurfaceEnrichmentSource: String, Sendable, Hashable {
    case deterministicOnly
    case deterministicStructuredEnglish
    case llmEnriched
    case llmRepairedJSON
    case fallbackOriginal
}

public enum ProviderSurfaceEnrichmentFailureReason: String, Sendable, Hashable {
    case providerUnavailable
    case modelBusy
    case timeout
    case cancelled
    case invalidJSON
    case repairFailed
    case unsafeDTO
    case thrownError
}

public struct ProviderSurfaceEnrichmentDiagnostics: Sendable, Hashable {
    public var attemptedLLM: Bool
    public var source: ProviderSurfaceEnrichmentSource
    public var failureReason: ProviderSurfaceEnrichmentFailureReason?
    public var repairAttempted: Bool
    public var addedSemanticConcepts: Int
    public var addedCommercialConstraints: Int
    public var addedTimeConstraints: Int
    public var addedBroadRecallTokens: Int
    public var timeoutSeconds: Double?
    public var elapsedMs: Int?
    public var decodeErrorSummary: String?

    public init(
        attemptedLLM: Bool,
        source: ProviderSurfaceEnrichmentSource,
        failureReason: ProviderSurfaceEnrichmentFailureReason? = nil,
        repairAttempted: Bool = false,
        addedSemanticConcepts: Int = 0,
        addedCommercialConstraints: Int = 0,
        addedTimeConstraints: Int = 0,
        addedBroadRecallTokens: Int = 0,
        timeoutSeconds: Double? = nil,
        elapsedMs: Int? = nil,
        decodeErrorSummary: String? = nil
    ) {
        self.attemptedLLM = attemptedLLM
        self.source = source
        self.failureReason = failureReason
        self.repairAttempted = repairAttempted
        self.addedSemanticConcepts = addedSemanticConcepts
        self.addedCommercialConstraints = addedCommercialConstraints
        self.addedTimeConstraints = addedTimeConstraints
        self.addedBroadRecallTokens = addedBroadRecallTokens
        self.timeoutSeconds = timeoutSeconds
        self.elapsedMs = elapsedMs
        self.decodeErrorSummary = decodeErrorSummary
    }
}

public actor ProviderSurfaceEnrichmentDiagnosticsStore {
    public private(set) var last: ProviderSurfaceEnrichmentDiagnostics?

    public init() {}

    public func record(_ value: ProviderSurfaceEnrichmentDiagnostics) {
        last = value
    }
}

public enum ProviderSurfaceEnrichmentTimeoutError: Error, Sendable, Hashable {
    case timedOut
}

struct ProviderSurfaceEnrichmentDTO: Codable, Sendable, Hashable {
    struct ConstraintDTO: Codable, Sendable, Hashable {
        var text: String
        var isHard: Bool?
    }

    struct OfferCanonicalEnglishDTO: Codable, Sendable, Hashable {
        var offerID: String
        var canonicalEnglishRetrievalText: String?
    }

    var canonicalEnglishRetrievalText: String?
    var offerCanonicalEnglish: [OfferCanonicalEnglishDTO]?
    var semanticConcepts: [String]?
    var softPreferences: [String]?
    var commercialConstraints: [ConstraintDTO]?
    var timeAvailabilityConstraints: [ConstraintDTO]?
    var broadRecallTokens: [String]?
    var sourceTextBlocks: [String]?
    var confidence: Double?
}

enum ExchangeIndexedProviderSurfaceEnrichmentPromptBuilder {
    static func buildPrompt(surface: ExchangeIndexedProviderSurface) -> String {
        let profile = """
        {
          "displayName": \(json(surface.displayName)),
          "headline": \(json(surface.headline)),
          "summary": \(json(surface.summary)),
          "visibility": "\(surface.visibility)",
          "availability": "\(surface.availability)",
          "regions": \(jsonArray(surface.regions.regionTags + surface.regions.regionAliases + surface.regions.serviceAreaNotes)),
          "semanticConcepts": \(jsonArray(surface.semanticConcepts)),
          "sourceTextBlocks": \(jsonArray(surface.sourceTextBlocks))
        }
        """

        let offersPayload = surface.offers.map { offer in
            """
            {
              "offerID": \(json(offer.offerID)),
              "title": \(json(offer.title)),
              "summary": \(json(offer.summary)),
              "category": \(json(offer.freeTextCategory ?? offer.category)),
              "semanticConcepts": \(jsonArray(offer.semanticConcepts)),
              "commercialConstraints": \(jsonArray(offer.commercialConstraints.map(\.text))),
              "timeAvailabilityConstraints": \(jsonArray(offer.timeAvailabilityConstraints.map(\.text))),
              "sourceTextBlocks": \(jsonArray(offer.sourceTextBlocks)),
              "contactOrPolicyText": \(jsonArray(offer.contactOrPolicyText))
            }
            """
        }.joined(separator: ",\n")

        return """
        You are enriching a provider indexed search surface.

        Read the provider public profile and offers.
        Preserve unusual and open-ended provider claims verbatim.
        Extract searchable evidence that a requester may ask for naturally.
        Separate capabilities, service areas, commercial policies, availability/timing, ideal customers, exclusions, dealbreakers, fulfillment modes, and soft preferences.
        Do not infer hard constraints unless explicitly stated.
        Do not erase or rewrite the provider's original wording in sourceTextBlocks or other display fields.
        Keep raw/original-language text only in sourceTextBlocks; never put it in canonicalEnglishRetrievalText.

        canonicalEnglishRetrievalText and offerCanonicalEnglish[].canonicalEnglishRetrievalText:
        - Must be English when non-null. Never copy Arabic, Korean, Chinese, or any other non-English script or wording.
        - If source text is non-English, translate and normalize its meaning into concise English for retrieval.
        - If source text is already English, rewrite/normalize it into concise English for retrieval (do not paste verbatim unless already concise).
        - Do not transliterate except for proper nouns, brand names, place names, or product names.
        - Use null when there is not enough real user-provided meaning to produce English retrieval text.
        - Do not invent services, products, locations, credentials, pricing, or availability.
        - Do not use scaffold words like buyer, seller, coordination, discovery, inbound, or public surface unless the user explicitly provided that meaning.

        Return compact JSON only.
        No markdown.
        No prose.

        Output schema:
        {
          "canonicalEnglishRetrievalText": String|null,
          "offerCanonicalEnglish": [{"offerID": String, "canonicalEnglishRetrievalText": String|null}],
          "semanticConcepts": [String],
          "softPreferences": [String],
          "commercialConstraints": [{"text": String, "isHard": Bool}],
          "timeAvailabilityConstraints": [{"text": String, "isHard": Bool}],
          "broadRecallTokens": [String],
          "sourceTextBlocks": [String],
          "confidence": Number
        }

        Provider profile:
        \(profile)

        Offers:
        [
        \(offersPayload)
        ]
        """
    }

    private static func json(_ value: String?) -> String {
        guard let value else { return "null" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func jsonArray(_ values: [String]) -> String {
        "[\(values.map { json($0) }.joined(separator: ", "))]"
    }
}

public struct LLMIndexedProviderSurfaceEnricher: ExchangeIndexedProviderSurfaceEnricher, Sendable {
    public struct Configuration: Sendable, Hashable {
        public var timeoutSeconds: Double
        public var minConfidenceForBroadRecallTokens: Double
        public var maxAddedItemsPerField: Int

        public init(
            timeoutSeconds: Double = 2.0,
            minConfidenceForBroadRecallTokens: Double = 0.70,
            maxAddedItemsPerField: Int = 24
        ) {
            self.timeoutSeconds = timeoutSeconds
            self.minConfidenceForBroadRecallTokens = minConfidenceForBroadRecallTokens
            self.maxAddedItemsPerField = maxAddedItemsPerField
        }
    }

    private let provider: (any AsyncProviderSurfaceEnrichmentJSONProvider)?
    private let config: Configuration
    private let diagnosticsStore: ProviderSurfaceEnrichmentDiagnosticsStore?

    public init(
        provider: (any AsyncProviderSurfaceEnrichmentJSONProvider)?,
        config: Configuration = .init(),
        diagnosticsStore: ProviderSurfaceEnrichmentDiagnosticsStore? = nil
    ) {
        self.provider = provider
        self.config = config
        self.diagnosticsStore = diagnosticsStore
    }

    public func enrich(
        surface: ExchangeIndexedProviderSurface
    ) async -> ExchangeIndexedProviderSurface {
        guard let provider else {
            return await finishAfterEnrichmentFailure(
                surface: surface,
                failureReason: .providerUnavailable,
                attemptedLLM: false,
                fallbackSourceIfNoCarrier: .deterministicOnly
            )
        }

        guard await provider.isReadyForImmediateExtraction() else {
            return await finishAfterEnrichmentFailure(
                surface: surface,
                failureReason: .modelBusy,
                attemptedLLM: true,
                fallbackSourceIfNoCarrier: .fallbackOriginal
            )
        }

        let prompt = ExchangeIndexedProviderSurfaceEnrichmentPromptBuilder.buildPrompt(surface: surface)
        let start = CFAbsoluteTimeGetCurrent()
        let raw: String
        do {
            raw = try await withTimeout(seconds: max(0.05, config.timeoutSeconds)) {
                try await provider.enrichProviderSurfaceJSON(prompt: prompt)
            }
        } catch is CancellationError {
            return await finishAfterEnrichmentFailure(
                surface: surface,
                failureReason: .cancelled,
                attemptedLLM: true,
                fallbackSourceIfNoCarrier: .fallbackOriginal,
                elapsedMs: elapsedMs(from: start)
            )
        } catch is ProviderSurfaceEnrichmentTimeoutError {
            return await finishAfterEnrichmentFailure(
                surface: surface,
                failureReason: .timeout,
                attemptedLLM: true,
                fallbackSourceIfNoCarrier: .fallbackOriginal,
                timeoutSeconds: config.timeoutSeconds,
                elapsedMs: elapsedMs(from: start)
            )
        } catch is any ProviderSurfaceEnrichmentBusyError {
            return await finishAfterEnrichmentFailure(
                surface: surface,
                failureReason: .modelBusy,
                attemptedLLM: true,
                fallbackSourceIfNoCarrier: .fallbackOriginal,
                elapsedMs: elapsedMs(from: start)
            )
        } catch is any ProviderSurfaceEnrichmentUnavailableError {
            return await finishAfterEnrichmentFailure(
                surface: surface,
                failureReason: .providerUnavailable,
                attemptedLLM: true,
                fallbackSourceIfNoCarrier: .fallbackOriginal,
                elapsedMs: elapsedMs(from: start)
            )
        } catch {
            return await finishAfterEnrichmentFailure(
                surface: surface,
                failureReason: .thrownError,
                attemptedLLM: true,
                fallbackSourceIfNoCarrier: .fallbackOriginal,
                elapsedMs: elapsedMs(from: start),
                decodeErrorSummary: String(describing: error)
            )
        }

        if let dto = decode(raw) {
            if let merged = await merge(
                surface: surface,
                dto: dto,
                source: .llmEnriched,
                repairAttempted: false
            ) {
                return merged
            }
        }

        let repaired = deterministicJSONRepair(raw)
        if let repaired,
           let dto = decode(repaired) {
            if let merged = await merge(
                surface: surface,
                dto: dto,
                source: .llmRepairedJSON,
                repairAttempted: true
            ) {
                return merged
            }
        }

        return await finishAfterEnrichmentFailure(
            surface: surface,
            failureReason: repaired == nil ? .invalidJSON : .repairFailed,
            attemptedLLM: true,
            fallbackSourceIfNoCarrier: .fallbackOriginal,
            repairAttempted: true,
            elapsedMs: elapsedMs(from: start)
        )
    }
}

private extension LLMIndexedProviderSurfaceEnricher {
    func finishAfterEnrichmentFailure(
        surface: ExchangeIndexedProviderSurface,
        failureReason: ProviderSurfaceEnrichmentFailureReason,
        attemptedLLM: Bool,
        fallbackSourceIfNoCarrier: ProviderSurfaceEnrichmentSource,
        repairAttempted: Bool = false,
        timeoutSeconds: Double? = nil,
        elapsedMs: Int? = nil,
        decodeErrorSummary: String? = nil
    ) async -> ExchangeIndexedProviderSurface {
        if ExchangeStructuredEnglishRetrievalCarrierBuilder.surfaceAppearsNonEnglish(surface),
           let enriched = ExchangeStructuredEnglishRetrievalCarrierBuilder.apply(to: surface),
           ExchangeStructuredEnglishRetrievalCarrierBuilder.hasAnyEnglishRetrievalCarrier(on: enriched) {
            await diagnosticsStore?.record(.init(
                attemptedLLM: attemptedLLM,
                source: .deterministicStructuredEnglish,
                failureReason: failureReason,
                repairAttempted: repairAttempted,
                timeoutSeconds: timeoutSeconds,
                elapsedMs: elapsedMs,
                decodeErrorSummary: decodeErrorSummary
            ))
            logProviderEnrichmentMissingEnglishCarrierIfNeeded(surface: enriched)
            return enriched
        }

        await diagnosticsStore?.record(.init(
            attemptedLLM: attemptedLLM,
            source: fallbackSourceIfNoCarrier,
            failureReason: failureReason,
            repairAttempted: repairAttempted,
            timeoutSeconds: timeoutSeconds,
            elapsedMs: elapsedMs,
            decodeErrorSummary: decodeErrorSummary
        ))
        logProviderEnrichmentUnsafeFallback(
            surface: surface,
            source: fallbackSourceIfNoCarrier,
            failureReason: failureReason
        )
        return surface
    }

    func merge(
        surface: ExchangeIndexedProviderSurface,
        dto: ProviderSurfaceEnrichmentDTO,
        source: ProviderSurfaceEnrichmentSource,
        repairAttempted: Bool
    ) async -> ExchangeIndexedProviderSurface? {
        let semanticAdds = sanitizeTextBlocks(dto.semanticConcepts ?? [], maxCount: config.maxAddedItemsPerField)
        let preferenceAdds = sanitizeTextBlocks(dto.softPreferences ?? [], maxCount: config.maxAddedItemsPerField)
        let sourceAdds = sanitizeTextBlocks(dto.sourceTextBlocks ?? [], maxCount: config.maxAddedItemsPerField)

        let commercialAdds = sanitizeConstraintAdds(dto.commercialConstraints ?? [], maxCount: config.maxAddedItemsPerField)
        let timeAdds = sanitizeConstraintAdds(dto.timeAvailabilityConstraints ?? [], maxCount: config.maxAddedItemsPerField)

        var broadAdds = sanitizeAtomicTokens(dto.broadRecallTokens ?? [], maxCount: config.maxAddedItemsPerField)
        if (dto.confidence ?? 0) < config.minConfidenceForBroadRecallTokens {
            let moved = broadAdds
            broadAdds = []
            let movedText = moved.map { String($0) }
            let semanticWithMoved = semanticAdds + movedText
            return await mergedSurface(
                surface: surface,
                dto: dto,
                semanticAdds: semanticWithMoved,
                preferenceAdds: preferenceAdds,
                sourceAdds: sourceAdds + movedText,
                commercialAdds: commercialAdds,
                timeAdds: timeAdds,
                broadAdds: [],
                source: source,
                repairAttempted: repairAttempted
            )
        }

        return await mergedSurface(
            surface: surface,
            dto: dto,
            semanticAdds: semanticAdds,
            preferenceAdds: preferenceAdds,
            sourceAdds: sourceAdds,
            commercialAdds: commercialAdds,
            timeAdds: timeAdds,
            broadAdds: broadAdds,
            source: source,
            repairAttempted: repairAttempted
        )
    }

    func mergedSurface(
        surface: ExchangeIndexedProviderSurface,
        dto: ProviderSurfaceEnrichmentDTO,
        semanticAdds: [String],
        preferenceAdds: [String],
        sourceAdds: [String],
        commercialAdds: [ProviderSurfaceEnrichmentDTO.ConstraintDTO],
        timeAdds: [ProviderSurfaceEnrichmentDTO.ConstraintDTO],
        broadAdds: [String],
        source: ProviderSurfaceEnrichmentSource,
        repairAttempted: Bool
    ) async -> ExchangeIndexedProviderSurface? {
        let hasEnglishCarrier =
            sanitizeTextBlocks([dto.canonicalEnglishRetrievalText].compactMap { $0 }, maxCount: 1).first != nil
            || (dto.offerCanonicalEnglish ?? []).contains {
                sanitizeTextBlocks([$0.canonicalEnglishRetrievalText].compactMap { $0 }, maxCount: 1).first != nil
            }

        if semanticAdds.isEmpty &&
            preferenceAdds.isEmpty &&
            sourceAdds.isEmpty &&
            commercialAdds.isEmpty &&
            timeAdds.isEmpty &&
            broadAdds.isEmpty &&
            !hasEnglishCarrier {
            await diagnosticsStore?.record(.init(
                attemptedLLM: true,
                source: .fallbackOriginal,
                failureReason: .unsafeDTO,
                repairAttempted: repairAttempted
            ))
            return nil
        }

        let mergedSemantic = dedupePreserve(surface.semanticConcepts + semanticAdds)
        let mergedPreferences = dedupePreserve(surface.softPreferences + preferenceAdds)
        let mergedSource = dedupePreserve(surface.sourceTextBlocks + sourceAdds)
        let mergedCommercial = dedupeCommercial(
            surface.commercialConstraints +
            commercialAdds.map { .init(text: $0.text, isHard: $0.isHard ?? false) }
        )
        let mergedTime = dedupeTime(
            surface.timeAvailabilityConstraints +
            timeAdds.map { .init(text: $0.text, isHard: $0.isHard ?? false) }
        )
        let mergedBroad = dedupePreserve(surface.broadRecallTokens + broadAdds)

        var copy = surface
        applyCanonicalEnglish(from: dto, to: &copy)
        copy.semanticConcepts = mergedSemantic
        copy.softPreferences = mergedPreferences
        copy.sourceTextBlocks = mergedSource
        copy.commercialConstraints = mergedCommercial
        copy.timeAvailabilityConstraints = mergedTime
        copy.broadRecallTokens = mergedBroad
        if var slices = copy.retrievalSlices {
            slices.capabilityBlocks = dedupePreserve(slices.capabilityBlocks + sourceAdds)
            copy.retrievalSlices = slices
        }

        await diagnosticsStore?.record(.init(
            attemptedLLM: true,
            source: source,
            repairAttempted: repairAttempted,
            addedSemanticConcepts: max(0, mergedSemantic.count - surface.semanticConcepts.count),
            addedCommercialConstraints: max(0, mergedCommercial.count - surface.commercialConstraints.count),
            addedTimeConstraints: max(0, mergedTime.count - surface.timeAvailabilityConstraints.count),
            addedBroadRecallTokens: max(0, mergedBroad.count - surface.broadRecallTokens.count)
        ))
        logProviderEnrichmentMissingEnglishCarrierIfNeeded(surface: copy)
        return copy
    }

    func applyCanonicalEnglish(
        from dto: ProviderSurfaceEnrichmentDTO,
        to surface: inout ExchangeIndexedProviderSurface
    ) {
        if let profileEnglish = sanitizeTextBlocks(
            [dto.canonicalEnglishRetrievalText].compactMap { $0 },
            maxCount: 1
        ).first {
            surface.canonicalEnglishRetrievalText = profileEnglish
        }
        guard let offerEnglish = dto.offerCanonicalEnglish, !offerEnglish.isEmpty else { return }
        for index in surface.offers.indices {
            let offerID = surface.offers[index].offerID
            guard let match = offerEnglish.first(where: { $0.offerID == offerID }),
                  let text = sanitizeTextBlocks(
                      [match.canonicalEnglishRetrievalText].compactMap { $0 },
                      maxCount: 1
                  ).first else { continue }
            surface.offers[index].canonicalEnglishRetrievalText = text
        }
    }

    func sanitizeTextBlocks(_ values: [String], maxCount: Int) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maxCount)
            .map { String($0) }
    }

    func sanitizeConstraintAdds(
        _ values: [ProviderSurfaceEnrichmentDTO.ConstraintDTO],
        maxCount: Int
    ) -> [ProviderSurfaceEnrichmentDTO.ConstraintDTO] {
        values
            .map {
                .init(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isHard: $0.isHard
                )
            }
            .filter { !$0.text.isEmpty }
            .prefix(maxCount)
            .map { $0 }
    }

    func sanitizeAtomicTokens(_ values: [String], maxCount: Int) -> [String] {
        var out: [String] = []
        for raw in values {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty else { continue }
            guard token.count <= 120 else { continue }
            let words = token.split(whereSeparator: \.isWhitespace).count
            guard words <= 8 else { continue }
            guard !token.contains(",") else { continue }
            out.append(token)
            if out.count >= maxCount { break }
        }
        return dedupePreserve(out)
    }

    func dedupePreserve(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(value)
        }
        return out
    }

    func dedupeCommercial(
        _ values: [ExchangeIndexedProviderSurface.CommercialConstraint]
    ) -> [ExchangeIndexedProviderSurface.CommercialConstraint] {
        var seen = Set<String>()
        var out: [ExchangeIndexedProviderSurface.CommercialConstraint] = []
        for value in values {
            let key = value.text.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(value)
        }
        return out
    }

    func dedupeTime(
        _ values: [ExchangeIndexedProviderSurface.TimeAvailabilityConstraint]
    ) -> [ExchangeIndexedProviderSurface.TimeAvailabilityConstraint] {
        var seen = Set<String>()
        var out: [ExchangeIndexedProviderSurface.TimeAvailabilityConstraint] = []
        for value in values {
            let key = value.text.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(value)
        }
        return out
    }

    func decode(_ raw: String) -> ProviderSurfaceEnrichmentDTO? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProviderSurfaceEnrichmentDTO.self, from: data)
    }

    func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ProviderSurfaceEnrichmentTimeoutError.timedOut
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
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

    func elapsedMs(from start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    func logProviderEnrichmentUnsafeFallback(
        surface: ExchangeIndexedProviderSurface,
        source: ProviderSurfaceEnrichmentSource,
        failureReason: ProviderSurfaceEnrichmentFailureReason?
    ) {
        #if DEBUG
        guard providerSurfaceAppearsNonEnglish(surface) else { return }
        let affectedKinds = providerRetrievalDocKindsMissingEnglishCarrier(on: surface)
        print(
            "[ProviderSurfaceEnrichment][Multilingual] unsafeFallback=true source=\(source.rawValue) " +
            "failureReason=\(failureReason?.rawValue ?? "nil") " +
            "missingEnglishCarrier=true rawTextUnsafeForEnglishEmbedder=true " +
            "affectedDocKinds=\(affectedKinds.joined(separator: ","))"
        )
        #endif
    }

    func logProviderEnrichmentMissingEnglishCarrierIfNeeded(
        surface: ExchangeIndexedProviderSurface
    ) {
        #if DEBUG
        guard providerSurfaceAppearsNonEnglish(surface) else { return }
        let affectedKinds = providerRetrievalDocKindsMissingEnglishCarrier(on: surface)
        guard !affectedKinds.isEmpty else { return }
        print(
            "[ProviderSurfaceEnrichment][Multilingual] missingEnglishCarrierAfterEnrichment=true " +
            "affectedDocKinds=\(affectedKinds.joined(separator: ","))"
        )
        #endif
    }

    func providerSurfaceAppearsNonEnglish(_ surface: ExchangeIndexedProviderSurface) -> Bool {
        ExchangeStructuredEnglishRetrievalCarrierBuilder.surfaceAppearsNonEnglish(surface)
    }

    func providerRetrievalDocKindsMissingEnglishCarrier(
        on surface: ExchangeIndexedProviderSurface
    ) -> [String] {
        var kinds: [String] = []
        if ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(surface.canonicalEnglishRetrievalText) == nil {
            kinds.append("profile_intro,profile_seeking,profile_affinity,profile_about,profile_capability")
        }
        for offer in surface.offers {
            if ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(offer.canonicalEnglishRetrievalText) == nil {
                kinds.append("offer_detail,offer_object,offer_package,offer_faq(\(offer.offerID))")
            }
        }
        return kinds
    }
}
