import Foundation

#if DEBUG

public enum MultilingualSecretaryLiveSubsetFailureCategory: String, Sendable, Hashable, Codable, CaseIterable {
    case userIntentCarrierLoss
    case providerCarrierLoss
    case selectedOfferMismatch
    case noisyOutranking
    case forbiddenMissingFacts
    case uiPrimaryLanguageLeak
    case federationOverlayFallback
    case slowScenario
    case liveLLMOrEnricherFailure
    case unknown
}

public struct MultilingualSecretaryLiveSubsetClusteringConfig: Sendable, Hashable {
    public var slowScenarioThresholdMs: Int

    public init(slowScenarioThresholdMs: Int = 30_000) {
        self.slowScenarioThresholdMs = slowScenarioThresholdMs
    }

    public static let `default` = MultilingualSecretaryLiveSubsetClusteringConfig()
}

public enum MultilingualSecretaryLiveSubsetFailureClustering {
    public static func categorize(
        _ record: MultilingualSecretaryLiveSubsetAuditRecord,
        config: MultilingualSecretaryLiveSubsetClusteringConfig = .default
    ) -> [MultilingualSecretaryLiveSubsetFailureCategory] {
        var categories = Set<MultilingualSecretaryLiveSubsetFailureCategory>()
        let joinedFailures = record.failureReasons.joined(separator: " ").lowercased()
        let joinedWarnings = record.warnings.joined(separator: " ").lowercased()
        let joinedSignals = joinedFailures + " " + joinedWarnings

        if record.carrierLost
            || joinedSignals.contains("provider canonicalenglishretrievaltext missing")
            || joinedSignals.contains("canonicalenglishretrievaltext missing")
            || isProviderCarrierMissing(record.providerCanonicalEnglishRetrievalText) {
            categories.insert(.providerCarrierLoss)
        }

        if joinedSignals.contains("canonicalenglishsearchtext missing")
            || userIntentCarrierMissing(record: record) {
            categories.insert(.userIntentCarrierLoss)
        }

        if record.selectedOfferID != record.expectedOfferID
            || joinedSignals.contains("selected offer mismatch") {
            categories.insert(.selectedOfferMismatch)
        }

        if record.noisyOutrankingDetected
            || joinedSignals.contains("noisy profile/offer outranked exact object offer") {
            categories.insert(.noisyOutranking)
        }

        if !record.forbiddenMissingFactsTriggered.isEmpty
            || joinedSignals.contains("forbidden second-half missing facts") {
            categories.insert(.forbiddenMissingFacts)
        }

        if joinedSignals.contains("ui primary request uses normalized english")
            || joinedSignals.contains("ui displaysearchquery is not original")
            || joinedSignals.contains("ui request text does not preserve original")
            || uiPrimaryLanguageLeak(record: record) {
            categories.insert(.uiPrimaryLanguageLeak)
        }

        if record.overlayFallbackUsed
            || joinedSignals.contains("overlay fallback")
            || joinedSignals.contains("full facade used overlay fallback") {
            categories.insert(.federationOverlayFallback)
        }

        if record.timings.totalMs >= config.slowScenarioThresholdMs {
            categories.insert(.slowScenario)
        }

        if joinedSignals.contains("provider enricher did not produce english carrier")
            || joinedSignals.contains("unsafe non-english retrieval fallback")
            || joinedSignals.contains("enricher")
            || joinedSignals.contains("carrier token check failed") {
            categories.insert(.liveLLMOrEnricherFailure)
        }

        if !record.passed && categories.isEmpty {
            categories.insert(.unknown)
        }

        return categories.sorted { $0.rawValue < $1.rawValue }
    }

    public static func clusterSummary(
        from records: [MultilingualSecretaryLiveSubsetAuditRecord],
        config: MultilingualSecretaryLiveSubsetClusteringConfig = .default
    ) -> (
        categoryCounts: [String: Int],
        fixturesByCategory: [String: [String]],
        slowestByCategory: [String: String]
    ) {
        var categoryCounts: [String: Int] = [:]
        var fixturesByCategory: [String: [String]] = [:]
        var slowestByCategory: [String: (fixtureID: String, totalMs: Int)] = [:]

        for record in records {
            let categories = categorize(record, config: config)
            for category in categories {
                let key = category.rawValue
                categoryCounts[key, default: 0] += 1
                fixturesByCategory[key, default: []].append(record.fixtureID)
                let existing = slowestByCategory[key]
                if existing == nil || record.timings.totalMs > existing!.totalMs {
                    slowestByCategory[key] = (record.fixtureID, record.timings.totalMs)
                }
            }
        }

        for key in fixturesByCategory.keys {
            fixturesByCategory[key] = Array(Set(fixturesByCategory[key] ?? [])).sorted()
        }

        let slowestByCategoryIDs = slowestByCategory.mapValues(\.fixtureID)
        return (categoryCounts, fixturesByCategory, slowestByCategoryIDs)
    }

    public static func failureClusterLines(
        categoryCounts: [String: Int],
        fixturesByCategory: [String: [String]],
        warningOnlyCategories: Set<MultilingualSecretaryLiveSubsetFailureCategory> = [
            .federationOverlayFallback,
            .slowScenario,
            .liveLLMOrEnricherFailure
        ]
    ) -> [String] {
        MultilingualSecretaryLiveSubsetFailureCategory.allCases.compactMap { category in
            let count = categoryCounts[category.rawValue, default: 0]
            guard count > 0 else { return nil }
            let fixtures = fixturesByCategory[category.rawValue, default: []].joined(separator: ", ")
            let suffix = warningOnlyCategories.contains(category) ? " warnings" : ""
            if fixtures.isEmpty {
                return "- \(category.rawValue): \(count)\(suffix)"
            }
            return "- \(category.rawValue): \(count) fixture\(count == 1 ? "" : "s") — \(fixtures)\(suffix)"
        }
    }

    private static func isProviderCarrierMissing(_ carrier: String?) -> Bool {
        carrier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private static func userIntentCarrierMissing(record: MultilingualSecretaryLiveSubsetAuditRecord) -> Bool {
        guard MultilingualRetrievalE2EEvaluation.containsCJK(record.rawUserText) else { return false }
        let canonical = record.canonicalEnglishSearchText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return canonical.isEmpty && !record.passed
    }

    private static func uiPrimaryLanguageLeak(record: MultilingualSecretaryLiveSubsetAuditRecord) -> Bool {
        guard MultilingualRetrievalE2EEvaluation.containsCJK(record.rawUserText) else { return false }
        let raw = record.rawUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = record.displaySearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let captured = record.capturedRequestText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if display.isEmpty { return false }
        if display == record.canonicalEnglishSearchText { return true }
        return display != raw && captured != raw
    }
}

#endif
