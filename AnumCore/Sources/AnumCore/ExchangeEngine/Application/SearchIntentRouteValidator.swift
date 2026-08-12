import Foundation

/// Schema/confidence/hard-veto guardrail for LLM-provided discovery route fields.
/// When valid and confident, the extracted route is authoritative; legacy routing is fallback only.
enum SearchIntentRouteValidator {
    static let minRouteConfidence: Double = 0.65

    enum ResolutionSource: String, Sendable, Hashable {
        case llmRoute
        case legacy
    }

    enum RouteValidationRejection: String, Sendable, Hashable {
        case malformedRoute
        case lowConfidence
        case impossibleCombination
        case hardCommercialContradiction
    }

    struct ResolvedSearchRouting: Sendable, Hashable {
        var queryClass: ExchangeIntent.QueryIntentClass
        var surface: ExchangeIntent.SurfacePreference
        var targetKind: ExchangeIntentFacets.TargetKind
        var modeOverride: ExchangeMode?
        var source: ResolutionSource
        var rejectionReason: RouteValidationRejection?
    }

    // MARK: - Public resolution

    static func resolvedRouting(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        legacy: (
            queryClass: ExchangeIntent.QueryIntentClass,
            surface: ExchangeIntent.SurfacePreference,
            targetKind: ExchangeIntentFacets.TargetKind
        )
    ) -> ResolvedSearchRouting {
        resolve(from: canonical, legacy: legacy).routing
    }

    static func legacyQuerySurfaceTargetRouting(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> (
        queryClass: ExchangeIntent.QueryIntentClass,
        surface: ExchangeIntent.SurfacePreference,
        targetKind: ExchangeIntentFacets.TargetKind
    ) {
        switch canonical.domainCategory {
        case .homeService, .professionalService:
            return (.providerSearch, .offer, .provider)
        case .realEstate, .product:
            return (.offerSearch, .offer, .business)
        case .general:
            if let tx = canonical.transactionIntent {
                switch tx {
                case .hire, .book, .inquire:
                    return (.providerSearch, .offer, .provider)
                case .buy, .forSale, .rent:
                    return (.offerSearch, .offer, .provider)
                }
            }
            let trimmedObject = canonical.objectType?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedObject, !trimmedObject.isEmpty {
                return (.generalDiscovery, .mixed, .unknown)
            }
            return (.generalDiscovery, .mixed, .unknown)
        }
    }

    static func resolve(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        legacy: (
            queryClass: ExchangeIntent.QueryIntentClass,
            surface: ExchangeIntent.SurfacePreference,
            targetKind: ExchangeIntentFacets.TargetKind
        )
    ) -> (routing: ResolvedSearchRouting, rejectionReason: RouteValidationRejection?) {
        switch validate(extractedRoute: canonical.extractedRoute, canonical: canonical) {
        case .accepted(let validated):
            return (
                ResolvedSearchRouting(
                    queryClass: validated.queryClass,
                    surface: validated.surface,
                    targetKind: validated.targetKind,
                    modeOverride: validated.modeOverride,
                    source: .llmRoute,
                    rejectionReason: nil
                ),
                nil
            )
        case .rejected(let reason):
            return (
                ResolvedSearchRouting(
                    queryClass: legacy.queryClass,
                    surface: surfaceAfterRouteRejection(
                        reason: reason,
                        legacy: legacy,
                        canonical: canonical
                    ),
                    targetKind: legacy.targetKind,
                    modeOverride: nil,
                    source: .legacy,
                    rejectionReason: reason
                ),
                reason
            )
        }
    }

    // MARK: - Validation

    private struct ValidatedRoute {
        var queryClass: ExchangeIntent.QueryIntentClass
        var surface: ExchangeIntent.SurfacePreference
        var targetKind: ExchangeIntentFacets.TargetKind
        var modeOverride: ExchangeMode?
    }

    private enum ValidationOutcome {
        case accepted(ValidatedRoute)
        case rejected(RouteValidationRejection)
    }

    private static let structuredTransactionalLexicon: [String] = [
        "hire", "book", "buy", "rent", "quote", "estimate", "appraisal",
        "contractor", "provider", "company", "service", "paid", "pricing", "price",
    ]

    private static func validate(
        extractedRoute: ExchangeIntentFacets.ExtractedSearchRoute?,
        canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> ValidationOutcome {
        guard let route = extractedRoute,
              let routeClassRaw = SearchIntentSentinelFilter.nilIfSentinel(route.routeClassRaw),
              let surfaceRaw = SearchIntentSentinelFilter.nilIfSentinel(route.surfacePreferenceRaw),
              let targetKindRaw = SearchIntentSentinelFilter.nilIfSentinel(route.targetKindRaw)
        else {
            return .rejected(.malformedRoute)
        }

        guard let queryClass = ExchangeIntent.QueryIntentClass(rawValue: routeClassRaw),
              let surface = ExchangeIntent.SurfacePreference(rawValue: surfaceRaw),
              let targetKind = mapTargetKind(targetKindRaw)
        else {
            return .rejected(.malformedRoute)
        }

        let modeRaw = SearchIntentSentinelFilter.nilIfSentinel(route.modeRaw)
        let modeOverride = mapModeOverride(modeRaw)
        if let modeRaw, modeOverride == nil, modeRaw.lowercased() != "mixed" {
            return .rejected(.malformedRoute)
        }

        guard consistencyMatches(
            queryClass: queryClass,
            surface: surface,
            targetKind: targetKind,
            modeOverride: modeOverride
        ) else {
            return .rejected(.impossibleCombination)
        }

        guard let confidence = route.routeConfidence.map({ min(max($0, 0.0), 1.0) }),
              confidence >= minRouteConfidence
        else {
            return .rejected(.lowConfidence)
        }

        if isSocialRoute(queryClass),
           canonicalHasHardCommercialContradiction(canonical) {
            return .rejected(.hardCommercialContradiction)
        }

        if isSocialRoute(queryClass),
           shouldVetoSocialRouteForStructuredServiceIntent(canonical) {
            return .rejected(.hardCommercialContradiction)
        }

        return .accepted(
            ValidatedRoute(
                queryClass: queryClass,
                surface: surface,
                targetKind: targetKind,
                modeOverride: modeOverride
            )
        )
    }

    // MARK: - Consistency

    private static func consistencyMatches(
        queryClass: ExchangeIntent.QueryIntentClass,
        surface: ExchangeIntent.SurfacePreference,
        targetKind: ExchangeIntentFacets.TargetKind,
        modeOverride: ExchangeMode?
    ) -> Bool {
        switch queryClass {
        case .socialAffinitySearch, .relationshipSearch:
            guard surface == .affinity, targetKind == .person else { return false }
            if let modeOverride, modeOverride != .relational { return false }
            return true

        case .providerSearch, .offerSearch:
            guard surface == .offer || surface == .capability else { return false }
            guard targetKind == .provider else { return false }
            if let modeOverride, modeOverride == .relational { return false }
            return true

        case .capabilitySearch:
            guard surface == .capability || surface == .offer else { return false }
            guard targetKind == .provider else { return false }
            return true

        case .generalDiscovery:
            return true

        case .collaborationSearch, .directOutreach, .followUp, .statusCheck:
            return false
        }
    }

    private static func isSocialRoute(_ queryClass: ExchangeIntent.QueryIntentClass) -> Bool {
        queryClass == .socialAffinitySearch || queryClass == .relationshipSearch
    }

    private static func surfaceAfterRouteRejection(
        reason: RouteValidationRejection,
        legacy: (
            queryClass: ExchangeIntent.QueryIntentClass,
            surface: ExchangeIntent.SurfacePreference,
            targetKind: ExchangeIntentFacets.TargetKind
        ),
        canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> ExchangeIntent.SurfacePreference {
        switch reason {
        case .hardCommercialContradiction, .impossibleCombination:
            return legacy.surface
        case .malformedRoute, .lowConfidence:
            return canonical.extractedSurfacePreference ?? legacy.surface
        }
    }

    private static func shouldVetoSocialRouteForStructuredServiceIntent(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        guard canonicalHasTransactionalServiceIntent(canonical) else { return false }
        return hasStructuredServiceNeedPhrase(in: canonical)
    }

    private static func canonicalHasTransactionalServiceIntent(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        switch canonical.transactionIntent {
        case .hire, .book:
            return true
        case .buy, .forSale, .rent, .inquire, .none:
            return false
        }
    }

    private static func hasStructuredServiceNeedPhrase(
        in canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        if let need = inferredNeedText(from: canonical),
           needDistinctFromObjectType(need, objectType: canonical.objectType) {
            return true
        }
        for concept in canonical.semanticConcepts {
            if needDistinctFromObjectType(concept, objectType: canonical.objectType) {
                return true
            }
        }
        return false
    }

    private static func needDistinctFromObjectType(
        _ need: String,
        objectType: String?
    ) -> Bool {
        let needNorm = need.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needNorm.isEmpty else { return false }
        guard let object = objectType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !object.isEmpty
        else {
            return true
        }
        return needNorm != object
    }

    // MARK: - Hard commercial contradiction (structured evidence only)

    /// Vetoes a social LLM route only when explicit structured commercial fields contradict it.
    /// Does not reinterpret social vs commercial from schedule, place, activity nouns, or legacy routing.
    static func canonicalHasHardCommercialContradiction(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        if canonicalHasMeaningfulCommercialConstraints(canonical) {
            return true
        }

        if canonicalHasExplicitCommercialDomainCategory(canonical) {
            return true
        }

        if structuredCommercialFieldsContainTransactionalLexicon(canonical) {
            return true
        }

        return false
    }

    /// Backward-compatible alias for diagnostics.
    static func canonicalHasHardCommercialSignals(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        canonicalHasHardCommercialContradiction(canonical)
    }

    /// Backward-compatible alias for diagnostics.
    static func canonicalHasCommercialProtectionSignals(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        canonicalHasHardCommercialContradiction(canonical)
    }

    private static func canonicalHasMeaningfulCommercialConstraints(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        canonical.commercialConstraints.contains { constraint in
            let trimmed = constraint.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
        }
    }

    private static func canonicalHasExplicitCommercialDomainCategory(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        switch canonical.domainCategory {
        case .homeService, .professionalService, .product, .realEstate:
            return true
        case .general:
            return false
        }
    }

    private static func structuredCommercialFieldsContainTransactionalLexicon(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        let corpus = structuredCommercialFieldCorpus(canonical)
        guard !corpus.isEmpty else { return false }
        for term in structuredTransactionalLexicon {
            if containsWholeWord(term, in: corpus) {
                return true
            }
        }
        return false
    }

    /// Object, need, budget, and commercial structured fields only — not raw user text or recall tokens.
    private static func structuredCommercialFieldCorpus(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> String {
        var parts: [String] = []
        if let objectType = canonical.objectType {
            parts.append(objectType)
        }
        for constraint in canonical.commercialConstraints {
            parts.append(constraint.value)
        }
        if let needText = inferredNeedText(from: canonical) {
            parts.append(needText)
        }
        return parts.joined(separator: " ").lowercased()
    }

    /// Need is not stored separately on canonical; recover it from recall tokens when distinct from object.
    private static func inferredNeedText(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> String? {
        let objectNorm = canonical.objectType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        for token in canonical.broadRecallTokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let norm = trimmed.lowercased()
            if let objectNorm, norm == objectNorm { continue }
            return trimmed
        }
        return nil
    }

    private static func containsWholeWord(_ word: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    // MARK: - Mapping

    private static func mapTargetKind(_ raw: String) -> ExchangeIntentFacets.TargetKind? {
        switch raw.lowercased() {
        case "person", "profile", "counterparty":
            return .person
        case "provider", "offer":
            return .provider
        default:
            return nil
        }
    }

    private static func mapModeOverride(_ raw: String?) -> ExchangeMode? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "relational":
            return .relational
        case "transactional":
            return .transactional
        case "mixed":
            return nil
        default:
            return nil
        }
    }

    // MARK: - Deterministic route repair

    /// Repairs malformed or impossible LLM routes when compact extraction retained a confident atomic object.
    static func shouldDeterministicRouteRepair(
        canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        validAtomicObject: String
    ) -> Bool {
        guard !validAtomicObject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard isTransactionalModeForRouteRepair(canonical) else { return false }
        guard !isSocialAffinityExtractedRoute(canonical) else { return false }

        let semanticConfidence = canonical.extractionConfidence
            ?? canonical.extractedRoute?.routeConfidence
            ?? 0
        guard semanticConfidence >= minRouteConfidence else { return false }

        let legacy = legacyQuerySurfaceTargetRouting(from: canonical)
        let resolved = resolve(from: canonical, legacy: legacy)
        guard let rejection = resolved.rejectionReason else { return false }
        switch rejection {
        case .malformedRoute, .impossibleCombination:
            return true
        case .lowConfidence, .hardCommercialContradiction:
            return false
        }
    }

    static func canonicalWithDeterministicRouteRepair(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        let repaired = deterministicRepairedCommercialRoute(for: canonical)
        var copy = canonical
        let priorConfidence = copy.extractionConfidence
            ?? copy.extractedRoute?.routeConfidence
            ?? minRouteConfidence
        copy.extractedRoute = ExchangeIntentFacets.ExtractedSearchRoute(
            routeClassRaw: repaired.queryClass.rawValue,
            surfacePreferenceRaw: repaired.surface.rawValue,
            targetKindRaw: "provider",
            modeRaw: "transactional",
            routeConfidence: priorConfidence
        )
        copy.extractedSurfacePreference = repaired.surface
        return copy
    }

    static func canonicalHasServiceDiscoverySignals(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        switch canonical.domainCategory {
        case .homeService, .professionalService:
            return true
        default:
            break
        }
        if hasStructuredServiceNeedPhrase(in: canonical) {
            return true
        }
        guard canonicalHasTransactionalServiceIntent(canonical) else {
            return false
        }
        if !canonical.timeConstraints.isEmpty {
            return true
        }
        if canonicalHasMeaningfulCommercialConstraints(canonical) {
            return true
        }
        return false
    }

    private static func deterministicRepairedCommercialRoute(
        for canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> (
        queryClass: ExchangeIntent.QueryIntentClass,
        surface: ExchangeIntent.SurfacePreference,
        targetKind: ExchangeIntentFacets.TargetKind
    ) {
        if canonicalHasServiceDiscoverySignals(canonical) {
            return (.providerSearch, .offer, .provider)
        }

        switch canonical.domainCategory {
        case .homeService, .professionalService:
            return (.providerSearch, .offer, .provider)
        case .realEstate, .product:
            return (.offerSearch, .offer, .provider)
        case .general:
            break
        }

        switch canonical.transactionIntent {
        case .buy, .forSale, .rent:
            return (.offerSearch, .offer, .provider)
        case .hire, .book:
            return (.offerSearch, .offer, .provider)
        case .inquire, .none:
            return (.offerSearch, .offer, .provider)
        }
    }

    private static func isTransactionalModeForRouteRepair(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        if let modeRaw = canonical.extractedRoute?.modeRaw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           modeRaw == "relational" {
            return false
        }
        return !isSocialAffinityExtractedRoute(canonical)
    }

    private static func isSocialAffinityExtractedRoute(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        if canonical.extractedSurfacePreference == .affinity {
            return true
        }
        if let routeClassRaw = SearchIntentSentinelFilter.nilIfSentinel(
            canonical.extractedRoute?.routeClassRaw
        ),
           let queryClass = ExchangeIntent.QueryIntentClass(rawValue: routeClassRaw),
           isSocialRoute(queryClass) {
            return true
        }
        if canonical.extractedRoute?.modeRaw?.lowercased() == "relational",
           let routeClassRaw = canonical.extractedRoute?.routeClassRaw,
           let queryClass = ExchangeIntent.QueryIntentClass(rawValue: routeClassRaw),
           isSocialRoute(queryClass) {
            return true
        }
        return false
    }
}
