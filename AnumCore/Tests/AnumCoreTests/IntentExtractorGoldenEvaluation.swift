import Foundation
@testable import AnumCore

/// Shared expectation evaluation for intent extractor golden / raw I/O audit tests.
enum IntentExtractorGoldenEvaluation {
    static func mapAuditLanguage(_ fixtureLanguage: String) -> String {
        switch fixtureLanguage.lowercased() {
        case "english", "en": return "en"
        case "chinese", "zh": return "zh"
        case "mixed": return "mixed"
        default: return "unknown"
        }
    }

    static func extractIntentFacets(
        from result: ExchangeInterpreter.InterpretationResult
    ) -> (ExchangeIntent?, ExchangeIntentFacets?) {
        switch result {
        case .interpreted(let req):
            return (req.intent, req.facets)
        case .needsClarification(_, let draftIntent, _, let draftFacets):
            return (draftIntent, draftFacets)
        }
    }

    static func defaultSeedIntent(for text: String) -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "seed",
            objective: text
        )
    }

    static func buildHaystack(intent: ExchangeIntent?, facets: ExchangeIntentFacets?) -> String {
        var parts: [String] = []
        if let intent {
            parts.append(contentsOf: [
                intent.title,
                intent.objective,
                intent.targetDescription ?? "",
                intent.interpretationNotes ?? ""
            ])
            for c in intent.constraints {
                parts.append(c.key)
                parts.append(c.value)
            }
        }
        if let facets {
            parts.append(facets.targetRole ?? "")
            parts.append(facets.activity ?? "")
            parts.append(facets.serviceCategory ?? "")
            parts.append(facets.productCategory ?? "")
            parts.append(facets.locationText ?? "")
            parts.append(facets.placeName ?? "")
            parts.append(facets.timeText ?? "")
            parts.append(contentsOf: facets.providerTerms)
            parts.append(contentsOf: facets.capabilityTerms)
            parts.append(contentsOf: facets.affinityTerms)
            parts.append(contentsOf: facets.regionTerms)
            parts.append(contentsOf: facets.primaryKeywords)
            parts.append(contentsOf: facets.secondaryKeywords)
            if let si = facets.searchIntent {
                parts.append(si.rawUserText)
                parts.append(contentsOf: si.semanticConcepts)
                parts.append(contentsOf: si.broadRecallTokens)
                for p in si.places { parts.append(p.normalizedText) }
                for t in si.timeConstraints { parts.append(t.text) }
                for h in si.hardConstraints { parts.append(h.value) }
                for s in si.softPreferences { parts.append(s.value) }
            }
        }
        return parts.joined(separator: " ")
    }

    static func evaluateFlexible(
        fixture: IntentExtractorGoldenFixture,
        intent: ExchangeIntent?,
        facets: ExchangeIntentFacets?
    ) -> [String] {
        var failures: [String] = []
        guard let intent, let facets else {
            failures.append("missingIntentOrFacets")
            return failures
        }
        let hay = buildHaystack(intent: intent, facets: facets).lowercased()

        if !fixture.expectedAnyIntentKinds.isEmpty,
           !fixture.expectedAnyIntentKinds.contains(intent.kind.rawValue) {
            failures.append(
                "intentKind: wanted one of [\(fixture.expectedAnyIntentKinds.joined(separator: ","))] got \(intent.kind.rawValue)"
            )
        }
        if !fixture.expectedAnyQueryIntentClasses.isEmpty,
           !fixture.expectedAnyQueryIntentClasses.contains(intent.queryIntentClass.rawValue) {
            failures.append(
                "queryIntentClass: wanted one of [\(fixture.expectedAnyQueryIntentClasses.joined(separator: ","))] got \(intent.queryIntentClass.rawValue)"
            )
        }
        if !fixture.expectedAnySurfacePreferences.isEmpty,
           !fixture.expectedAnySurfacePreferences.contains(intent.surfacePreference.rawValue) {
            failures.append(
                "surfacePreference: wanted one of [\(fixture.expectedAnySurfacePreferences.joined(separator: ","))] got \(intent.surfacePreference.rawValue)"
            )
        }
        if !fixture.expectedReadiness.isEmpty,
           !fixture.expectedReadiness.contains(intent.readiness.rawValue) {
            failures.append(
                "readiness: wanted one of [\(fixture.expectedReadiness.joined(separator: ","))] got \(intent.readiness.rawValue)"
            )
        }
        if !fixture.expectedDomainCategories.isEmpty,
           let domain = facets.searchIntent?.domainCategory.rawValue,
           !fixture.expectedDomainCategories.contains(domain) {
            failures.append(
                "domainCategory: wanted one of [\(fixture.expectedDomainCategories.joined(separator: ","))] got \(domain)"
            )
        }
        for term in fixture.expectedHaystackSubstrings {
            if !hay.contains(term.lowercased()) {
                failures.append("haystackMissing:\(term)")
            }
        }
        return failures
    }

    static func evaluateStrict(
        fixture: IntentExtractorGoldenFixture,
        intent: ExchangeIntent?,
        facets: ExchangeIntentFacets?
    ) -> [String] {
        var failures = evaluateFlexible(fixture: fixture, intent: intent, facets: facets)
        guard let facets else { return failures }

        let vagueCategories: Set<String> = ["vague_needs_clarification"]
        if vagueCategories.contains(fixture.category) { return failures }

        guard let si = facets.searchIntent else {
            failures.append("strict:missingCanonicalSearchIntent")
            return failures
        }

        let hasStructure =
            si.objectType?.isEmpty == false ||
            !si.places.isEmpty ||
            !si.timeConstraints.isEmpty ||
            !si.semanticConcepts.isEmpty ||
            !si.broadRecallTokens.isEmpty ||
            !si.commercialConstraints.isEmpty

        if !hasStructure {
            failures.append("strict:canonicalSearchIntentStructurallyEmpty")
        }
        return failures
    }

    static func expectedFull(from fixture: IntentExtractorGoldenFixture) -> IntentExtractorExpectedFull {
        IntentExtractorExpectedFull(
            expectedSummaryLine: fixture.expectedSummaryLine,
            expectedAnyIntentKinds: fixture.expectedAnyIntentKinds,
            expectedAnyQueryIntentClasses: fixture.expectedAnyQueryIntentClasses,
            expectedAnySurfacePreferences: fixture.expectedAnySurfacePreferences,
            expectedReadiness: fixture.expectedReadiness,
            expectedDomainCategories: fixture.expectedDomainCategories,
            expectedHaystackSubstrings: fixture.expectedHaystackSubstrings,
            validationMode: fixture.validationMode.rawValue
        )
    }
    /// Strict expectations for production-routing audit (async flat-summary path with fixture JSON).
    static func evaluateProductionRoutingStrict(
        fixtureID: String,
        asyncFlatSummaryAttempted: Bool,
        rawLLMOutputExact: String?,
        facets: ExchangeIntentFacets?,
        extractionDiagnostics: SearchIntentExtractionDiagnostics?
    ) -> [String] {
        var failures: [String] = []
        guard IntentExtractorProductionRoutingFlatSummary.flatSummaryJSON(for: fixtureID) != nil else {
            failures.append("production:missingFixtureFlatJSON")
            return failures
        }

        if !asyncFlatSummaryAttempted {
            failures.append("production:asyncFlatSummaryNotAttempted")
        }
        if rawLLMOutputExact == nil {
            failures.append("production:rawLLMOutputNull")
        }

        let relaxed = IntentExtractorProductionRoutingFlatSummary.relaxedStrictLLMCanonical.contains(fixtureID)
        let contactOnly = IntentExtractorProductionRoutingFlatSummary.skipsProductionCanonicalSearchIntent.contains(fixtureID)
        if relaxed || contactOnly { return failures }

        guard let si = facets?.searchIntent else {
            failures.append("production:missingCanonicalSearchIntent")
            return failures
        }

        let llmSources: Set<SearchIntentExtractionSource> = [.llmFlatSummary, .llm, .llmRepairedJSON]
        let source = si.extractionSource ?? extractionDiagnostics?.source
        guard let source else {
            failures.append("production:missingExtractionSource")
            return failures
        }
        if !llmSources.contains(source) {
            failures.append("production:extractionSourceNotLLM:\(source.rawValue)")
        }
        if source == .heuristicFallback {
            failures.append("production:heuristicFallbackUsed")
        }
        return failures
    }

}

struct IntentExtractorExpectedFull: Codable, Sendable, Hashable {
    var expectedSummaryLine: String
    var expectedAnyIntentKinds: [String]
    var expectedAnyQueryIntentClasses: [String]
    var expectedAnySurfacePreferences: [String]
    var expectedReadiness: [String]
    var expectedDomainCategories: [String]
    var expectedHaystackSubstrings: [String]
    var validationMode: String

}
