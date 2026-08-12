import Foundation

#if DEBUG

/// Semantic equivalence groups for multilingual E2E carrier token checks on `canonicalEnglishSearchText`.
public enum MultilingualEnglishCarrierTokenEquivalence {
    /// Expected scenario token → acceptable substrings in lowered English carrier text.
    public static let groups: [String: [String]] = [
        "estimate": ["estimate", "appraisal", "quote"]
    ]

    public static func isSatisfied(expectedToken: String, in loweredEnglish: String) -> Bool {
        let normalized = expectedToken.lowercased()
        if let equivalents = groups[normalized] {
            return equivalents.contains { loweredEnglish.contains($0) }
        }
        return loweredEnglish.contains(normalized)
    }
}

public enum MultilingualRetrievalE2EEvaluation {
    public struct Input: Sendable {
        public var scenario: ExchangeMultilingualRetrievalE2EScenario
        public var runMode: MultilingualRetrievalE2EMode
        public var searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
        public var thread: ExchangeThread
        public var sortedMatches: [ExchangeMatch]
        public var rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow]
        public var selectedOfferID: String?
        public var selectedCandidateID: String?
        public var objectLaneActive: Bool
        public var providerProjection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?
        public var providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot
        public var secondHalf: MultilingualE2ESecondHalfSnapshot
        public var ui: AppSearchSmokeUIProjectionSnapshot

        public init(
            scenario: ExchangeMultilingualRetrievalE2EScenario,
            runMode: MultilingualRetrievalE2EMode,
            searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
            thread: ExchangeThread,
            sortedMatches: [ExchangeMatch],
            rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
            selectedOfferID: String?,
            selectedCandidateID: String?,
            objectLaneActive: Bool,
            providerProjection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?,
            providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
            secondHalf: MultilingualE2ESecondHalfSnapshot,
            ui: AppSearchSmokeUIProjectionSnapshot
        ) {
            self.scenario = scenario
            self.runMode = runMode
            self.searchIntent = searchIntent
            self.thread = thread
            self.sortedMatches = sortedMatches
            self.rankingTrace = rankingTrace
            self.selectedOfferID = selectedOfferID
            self.selectedCandidateID = selectedCandidateID
            self.objectLaneActive = objectLaneActive
            self.providerProjection = providerProjection
            self.providerIndexing = providerIndexing
            self.secondHalf = secondHalf
            self.ui = ui
        }
    }

    public struct Result: Sendable {
        public var failures: [String]
        public var warnings: [String]

        public var passed: Bool { failures.isEmpty }

        public init(failures: [String], warnings: [String]) {
            self.failures = failures
            self.warnings = warnings
        }
    }

    public static func evaluate(_ input: Input) -> Result {
        var failures: [String] = []
        var warnings: [String] = []
        let scenario = input.scenario
        let searchIntent = input.searchIntent

        failures.append(contentsOf: evaluateCanonicalIntent(scenario: scenario, searchIntent: searchIntent, thread: input.thread))
        failures.append(contentsOf: evaluateProviderProjection(scenario: scenario, projection: input.providerProjection))
        failures.append(contentsOf: evaluateDiscovery(
            scenario: scenario,
            sortedMatches: input.sortedMatches,
            rankingTrace: input.rankingTrace,
            selectedOfferID: input.selectedOfferID,
            selectedCandidateID: input.selectedCandidateID,
            objectLaneActive: input.objectLaneActive
        ))
        failures.append(contentsOf: evaluateSecondHalf(scenario: scenario, secondHalf: input.secondHalf))
        failures.append(contentsOf: evaluateUIProjection(scenario: scenario, searchIntent: searchIntent, ui: input.ui))

        if input.runMode == .livePublishEnricher {
            failures.append(contentsOf: evaluateLiveProviderIndexing(
                scenario: scenario,
                providerIndexing: input.providerIndexing,
                projection: input.providerProjection
            ))
            warnings.append(contentsOf: evaluateLiveWarnings(
                secondHalf: input.secondHalf,
                ui: input.ui
            ))
        }

        if input.runMode == .fullFacadePublishPath {
            failures.append(contentsOf: evaluateFullFacadeProviderIndexing(
                scenario: scenario,
                providerIndexing: input.providerIndexing,
                projection: input.providerProjection
            ))
            warnings.append(contentsOf: evaluateFullFacadeWarnings(
                providerIndexing: input.providerIndexing,
                secondHalf: input.secondHalf,
                ui: input.ui,
                baselineTimingMs: nil
            ))
        }

        return Result(
            failures: Array(Set(failures)).sorted(),
            warnings: Array(Set(warnings)).sorted()
        )
    }

    public static func evaluateLiveProviderIndexing(
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?
    ) -> [String] {
        var failures: [String] = []

        if providerIndexing.providerEnricherAttempted {
            let carrier = providerIndexing.providerCanonicalEnglishRetrievalText?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if carrier.isEmpty {
                failures.append("live enricher attempted but provider canonicalEnglishRetrievalText missing")
            }
        }

        if providerIndexing.providerUnsafeFallbackTriggered {
            failures.append("live enricher unsafe fallback without English carrier on non-English provider text")
        }

        if !(projection?.offerObjectUsesEnglishOnlyRetrievalProjection ?? false) {
            failures.append("live mode offer_object lacks English-only retrieval projection")
        }

        let serviceAreas = projection?.serviceAreas.map { $0.lowercased() } ?? []
        if !serviceAreas.contains("aurora") || !serviceAreas.contains("newmarket") {
            failures.append("live mode serviceAreas missing Aurora/Newmarket")
        }

        if projection?.offerID != scenario.expectedSelectedOfferID {
            failures.append("live mode provider projection offer mismatch")
        }

        return failures
    }

    public static func evaluateFullFacadeProviderIndexing(
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?
    ) -> [String] {
        var failures: [String] = []
        guard let publication = providerIndexing.fullFacadePublication else {
            failures.append("full facade publication snapshot missing")
            return failures
        }

        if publication.fullFacadeProfileSaveAttempted, !publication.fullFacadeProfileSaveSucceeded {
            failures.append("full facade savePublicProfile failed")
        }
        if publication.fullFacadeOfferSaveAttempted, !publication.fullFacadeOfferSaveSucceeded {
            failures.append("full facade saveOffer failed")
        }
        if publication.fullFacadePublishAttempted, !publication.fullFacadePublishSucceeded {
            failures.append("full facade publishSellerSurface failed")
        }
        if !publication.publishRetrievalDocumentsAttempted {
            failures.append("full facade publish path did not attempt retrieval document generation")
        }

        let carrierBefore = publication.canonicalEnglishCarrierBeforePublish?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let carrierAfter = publication.canonicalEnglishCarrierAfterPublish?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !carrierBefore.isEmpty && carrierAfter.isEmpty {
            failures.append("full facade carrier existed before publish but missing after publish")
        }

        if providerIndexing.providerEnricherAttempted, carrierAfter.isEmpty {
            failures.append("full facade enricher attempted but provider canonicalEnglishRetrievalText missing after publish")
        }

        if providerIndexing.providerUnsafeFallbackTriggered {
            failures.append("full facade unsafe fallback without English carrier on non-English provider text")
        }

        if !(projection?.offerObjectUsesEnglishOnlyRetrievalProjection ?? false) {
            failures.append("full facade offer_object lacks English-only retrieval projection after publish")
        }

        let serviceAreas = publication.serviceAreasAfterPublish.map { $0.lowercased() }
        if !serviceAreas.contains("aurora") || !serviceAreas.contains("newmarket") {
            failures.append("full facade serviceAreas missing Aurora/Newmarket after publish")
        }

        if !publication.originalChinesePreservedAfterPublish {
            failures.append("full facade original Chinese text not preserved after publish")
        }

        if projection?.offerID != scenario.expectedSelectedOfferID {
            failures.append("full facade provider projection offer mismatch")
        }

        return failures
    }

    public static func evaluateFullFacadeWarnings(
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        secondHalf: MultilingualE2ESecondHalfSnapshot,
        ui: AppSearchSmokeUIProjectionSnapshot,
        baselineTimingMs: Int?
    ) -> [String] {
        var warnings = evaluateLiveWarnings(secondHalf: secondHalf, ui: ui)
        guard let publication = providerIndexing.fullFacadePublication else { return warnings }

        if publication.federationRoundTripAttempted,
           !publication.federationRoundTripSucceeded,
           publication.usesOverlayFallbackForRoofer {
            warnings.append("federation round-trip failed but overlay fallback succeeded")
        }

        if let baselineTimingMs,
           let buildTimings = providerIndexing.providerBuildTimings,
           buildTimings.totalMs > baselineTimingMs {
            warnings.append("full facade mode slower than baseline by \(buildTimings.totalMs - baselineTimingMs)ms")
        }

        return warnings
    }

    public static func classifyFullFacadeModeFailureReasons(
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?
    ) -> [String] {
        var reasons = classifyLiveModeFailureReasons(
            providerIndexing: providerIndexing,
            projection: projection
        )
        guard let publication = providerIndexing.fullFacadePublication else {
            reasons.append("publication_snapshot_missing")
            return reasons
        }
        if publication.fullFacadeProfileSaveAttempted, !publication.fullFacadeProfileSaveSucceeded {
            reasons.append("profile_save_failed")
        }
        if publication.fullFacadeOfferSaveAttempted, !publication.fullFacadeOfferSaveSucceeded {
            reasons.append("offer_save_failed")
        }
        if publication.fullFacadePublishAttempted, !publication.fullFacadePublishSucceeded {
            reasons.append("publish_failed")
        }
        let carrierBefore = publication.canonicalEnglishCarrierBeforePublish?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let carrierAfter = publication.canonicalEnglishCarrierAfterPublish?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !carrierBefore.isEmpty && carrierAfter.isEmpty {
            reasons.append("carrier_lost_after_publish")
        }
        return Array(Set(reasons)).sorted()
    }

    public static func classifyFullFacadeModePass(
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?,
        selectedOfferID: String?,
        scenario: ExchangeMultilingualRetrievalE2EScenario
    ) -> Bool {
        guard let publication = providerIndexing.fullFacadePublication else { return false }
        guard publication.fullFacadeProfileSaveSucceeded,
              publication.fullFacadeOfferSaveSucceeded,
              publication.fullFacadePublishSucceeded,
              publication.publishRetrievalDocumentsAttempted else {
            return false
        }
        let serviceAreasOK = {
            let areas = publication.serviceAreasAfterPublish.map { $0.lowercased() }
            return areas.contains("aurora") && areas.contains("newmarket")
        }()
        return classifyLiveModePass(
            providerIndexing: providerIndexing,
            projection: projection,
            selectedOfferID: selectedOfferID,
            scenario: scenario
        ) && serviceAreasOK && publication.originalChinesePreservedAfterPublish
    }

    public static func evaluateLiveWarnings(
        secondHalf: MultilingualE2ESecondHalfSnapshot,
        ui: AppSearchSmokeUIProjectionSnapshot
    ) -> [String] {
        var warnings: [String] = []
        if let summary = ui.visibleSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty,
           !containsCJK(summary) {
            warnings.append("visibleSummary is English")
        }
        if let clarification = secondHalf.clarificationText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clarification.isEmpty,
           secondHalf.clarificationLanguage == "en" {
            warnings.append("clarification language is English")
        }
        return warnings
    }

    public static func classifyLiveModeFailureReasons(
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?
    ) -> [String] {
        var reasons: [String] = []
        if providerIndexing.providerEnricherAttempted,
           (providerIndexing.providerCanonicalEnglishRetrievalText?.isEmpty ?? true) {
            reasons.append("enricher_missing_carrier")
        }
        if providerIndexing.providerUnsafeFallbackTriggered {
            reasons.append("unsafe_fallback_without_carrier")
        }
        if !(projection?.offerObjectUsesEnglishOnlyRetrievalProjection ?? false) {
            reasons.append("offer_object_missing_english_projection")
        }
        return reasons
    }

    public static func classifyLiveModePass(
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?,
        selectedOfferID: String?,
        scenario: ExchangeMultilingualRetrievalE2EScenario
    ) -> Bool {
        let carrierPresent = !(providerIndexing.providerCanonicalEnglishRetrievalText?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let objectEnglish = projection?.offerObjectUsesEnglishOnlyRetrievalProjection ?? false
        let serviceAreasOK = {
            let areas = projection?.serviceAreas.map { $0.lowercased() } ?? []
            return areas.contains("aurora") && areas.contains("newmarket")
        }()
        let selectionOK = selectedOfferID == scenario.expectedSelectedOfferID
        return carrierPresent && objectEnglish && serviceAreasOK && selectionOK && !providerIndexing.providerUnsafeFallbackTriggered
    }

    public static func evaluateCanonicalIntent(
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        thread: ExchangeThread
    ) -> [String] {
        var failures: [String] = []
        guard let searchIntent else {
            failures.append("missing searchIntent")
            return failures
        }

        let english = searchIntent.canonicalEnglishSearchText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if english.isEmpty {
            failures.append("canonicalEnglishSearchText missing")
        } else {
            let lowered = english.lowercased()
            for token in scenario.expectedEnglishCarrierTokens
                where !MultilingualEnglishCarrierTokenEquivalence.isSatisfied(expectedToken: token, in: lowered) {
                failures.append("canonicalEnglishSearchText missing token=\(token)")
            }
        }

        let objectType = searchIntent.objectType?.lowercased() ?? ""
        if objectType.isEmpty {
            failures.append("objectType missing")
        } else if !scenario.expectedObjectTypeTokens.contains(where: { objectType.contains($0.lowercased()) }) {
            failures.append("objectType not roofer-like actual=\(objectType)")
        }

        let placeJoined = searchIntent.places.map(\.normalizedText).joined(separator: " ").lowercased()
        for place in scenario.expectedPlaceTokens where !placeJoined.contains(place.lowercased()) {
            failures.append("place missing token=\(place)")
        }

        let budgetMax = extractBudgetMax(from: searchIntent)
        if budgetMax != scenario.expectedBudgetMax {
            failures.append("budget max missing expected=\(scenario.expectedBudgetMax) actual=\(budgetMax.map(String.init) ?? "nil")")
        }

        let timeJoined = searchIntent.timeConstraints.map(\.text).joined(separator: " ").lowercased()
        if timeJoined.isEmpty {
            failures.append("time constraint missing")
        }

        let routeClass = (thread.facets?.queryIntentClass ?? thread.intent.queryIntentClass).rawValue
        if routeClass != scenario.expectedRouteClass {
            failures.append("routeClass mismatch expected=\(scenario.expectedRouteClass) actual=\(routeClass)")
        }

        let surfacePreference = (thread.facets?.surfacePreference ?? thread.intent.surfacePreference).rawValue
        if surfacePreference != scenario.expectedSurfacePreference {
            failures.append(
                "surfacePreference mismatch expected=\(scenario.expectedSurfacePreference) actual=\(surfacePreference)"
            )
        }

        let targetKind = thread.facets?.targetKind.rawValue ?? ExchangeIntentFacets.TargetKind.unknown.rawValue
        if targetKind != scenario.expectedTargetKind {
            failures.append("targetKind mismatch expected=\(scenario.expectedTargetKind) actual=\(targetKind)")
        }

        return failures
    }

    public static func evaluateProviderProjection(
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?
    ) -> [String] {
        var failures: [String] = []
        guard let projection else {
            failures.append("provider projection audit missing")
            return failures
        }

        let carrier = projection.canonicalEnglishRetrievalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if carrier.isEmpty {
            failures.append("provider canonicalEnglishRetrievalText missing")
        }

        if !projection.offerObjectUsesEnglishOnlyRetrievalProjection {
            failures.append("offer_object lacks English-only retrieval projection")
        }

        if !projection.offerDetailUsesEnglishOnlyRetrievalProjection {
            failures.append("offer_detail lacks English-only retrieval projection")
        }

        let serviceAreas = projection.serviceAreas.map { $0.lowercased() }
        if !serviceAreas.contains("aurora") || !serviceAreas.contains("newmarket") {
            failures.append("serviceAreas missing Aurora/Newmarket actual=\(projection.serviceAreas.joined(separator: ","))")
        }

        let objectText = projection.offerObjectSearchableText?.lowercased() ?? ""
        if !objectText.contains("roofer") && !objectText.contains("roof repair") {
            failures.append("offer_object missing roofer/roof repair carrier")
        }

        if !projection.preservedChineseInSourceBlocks {
            failures.append("original Chinese provider text not preserved in source blocks")
        }

        if projection.offerID != scenario.expectedSelectedOfferID {
            failures.append("provider projection offerID mismatch")
        }

        return failures
    }

    public static func evaluateDiscovery(
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        sortedMatches: [ExchangeMatch],
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        selectedOfferID: String?,
        selectedCandidateID: String?,
        objectLaneActive: Bool
    ) -> [String] {
        var failures: [String] = []

        if objectLaneActive != scenario.expectedObjectLaneActive {
            failures.append(
                "objectLaneActive mismatch expected=\(scenario.expectedObjectLaneActive) actual=\(objectLaneActive)"
            )
        }

        let selectedOffer = normalized(selectedOfferID)
        if selectedOffer != normalized(scenario.expectedSelectedOfferID) {
            failures.append(
                "selected offer mismatch expected=\(scenario.expectedSelectedOfferID) actual=\(selectedOfferID ?? "nil")"
            )
        }

        let selectedNode = normalized(selectedCandidateID)
        if selectedNode != normalized(scenario.expectedSelectedNodeID) {
            failures.append(
                "selected candidate mismatch expected=\(scenario.expectedSelectedNodeID) actual=\(selectedCandidateID ?? "nil")"
            )
        }

        if let noisyRank = rankOfNode(scenario.forbiddenNoisyNodeID, in: sortedMatches),
           let rooferRank = rankOfNode(scenario.expectedSelectedNodeID, in: sortedMatches),
           noisyRank < rooferRank {
            failures.append(
                "noisy profile outranks exact roofer offer noisyRank=\(noisyRank + 1) rooferRank=\(rooferRank + 1)"
            )
        }

        if let noisyTraceRank = rankOfNodeInTrace(scenario.forbiddenNoisyNodeID, trace: rankingTrace),
           let rooferTraceRank = rankOfNodeInTrace(scenario.expectedSelectedNodeID, trace: rankingTrace),
           noisyTraceRank < rooferTraceRank {
            failures.append(
                "noisy profile outranks roofer in retrieval trace noisyRank=\(noisyTraceRank + 1) rooferRank=\(rooferTraceRank + 1)"
            )
        }

        return failures
    }

    public static func evaluateSecondHalf(
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        secondHalf: MultilingualE2ESecondHalfSnapshot
    ) -> [String] {
        var failures: [String] = []
        if !secondHalf.forbiddenMissingFactsTriggered.isEmpty {
            failures.append(
                "forbidden second-half missing facts: \(secondHalf.forbiddenMissingFactsTriggered.joined(separator: ","))"
            )
        }
        return failures
    }

    public static func evaluateUIProjection(
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        ui: AppSearchSmokeUIProjectionSnapshot
    ) -> [String] {
        var failures: [String] = []
        let raw = scenario.rawUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = ui.displaySearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let captured = ui.capturedRequestText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if display.isEmpty {
            failures.append("UI displaySearchQuery missing")
        } else {
            if display == searchIntent?.canonicalEnglishSearchText {
                failures.append("UI primary request uses normalized English instead of original Chinese")
            }
            if !containsCJK(display) {
                failures.append("UI displaySearchQuery is not original Chinese request text")
            }
            if display != raw && captured != raw {
                failures.append("UI request text does not preserve original Chinese user request")
            }
        }

        if ui.selectedOfferID != scenario.expectedSelectedOfferID {
            failures.append(
                "UI selectedOfferID mismatch expected=\(scenario.expectedSelectedOfferID) actual=\(ui.selectedOfferID ?? "nil")"
            )
        }

        return failures
    }

    public static func classifyForbiddenMissingFacts(
        missingFacts: [String],
        forbiddenCategories: [String]
    ) -> [String] {
        var triggered: [String] = []
        for fact in missingFacts {
            let category = forbiddenMissingFactCategory(for: fact)
            if let category, forbiddenCategories.contains(category) {
                triggered.append(category)
            }
        }
        return Array(Set(triggered)).sorted()
    }

    public static func forbiddenMissingFactCategory(for fact: String) -> String? {
        let normalized = fact.lowercased()
        if matchesAny(normalized, ["location", "place", "where", "address", "service area", "area to serve"]) {
            return "location"
        }
        if matchesAny(normalized, ["budget", "price", "cost", "afford", "spend", "payment", "fee", "quote amount"]) {
            return "budget"
        }
        if matchesAny(normalized, ["time", "when", "schedule", "availability", "date", "hour", "deadline", "slot"]) {
            return "time"
        }
        return nil
    }

    public static func extractBudgetMax(from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent) -> Int? {
        ExchangeBudgetConstraintExtractor.extractBudgetMax(from: searchIntent)
    }

    public static func detectedRequestLanguage(for rawText: String) -> String? {
        containsCJK(rawText) ? "zh" : "en"
    }

    public static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00 ... 0x9FFF).contains(scalar.value)
                || (0x3400 ... 0x4DBF).contains(scalar.value)
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rankOfNode(_ nodeID: String, in matches: [ExchangeMatch]) -> Int? {
        for (index, match) in matches.enumerated() where match.counterpartyID == nodeID {
            return index
        }
        return nil
    }

    private static func rankOfNodeInTrace(
        _ nodeID: String,
        trace: [ExchangeRetrievalDebugTrace.RankingRow]
    ) -> Int? {
        for (index, row) in trace.enumerated() where row.counterpartyID == nodeID {
            return index
        }
        return nil
    }

    private static func matchesAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}

#endif
