import Foundation

/// Filters synthesized/default fulfillment posture from Details fallback surfaces only.
public enum ExchangeProviderDetailsLegacyLineGate {

    public enum SuppressionCategory: String, Sendable {
        case fulfillmentPosture
        case faqAutoAnswer
        case synthesizedPricingMode
        case synthesizedCommitmentMode
        case onSiteLeaningDefault
        case remoteFriendlyDefault
    }

    /// Returns a suppression category when `line` must not appear in Details fallbacks.
    public static func suppressionCategory(for line: String) -> SuppressionCategory? {
        let normalized = normalize(line)
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("faq auto-answer")
            || normalized.contains("auto-answer allowed")
            || normalized.contains("auto answer allowed") {
            return .faqAutoAnswer
        }

        if normalized.contains("quote on request") || normalized.contains("quote required") {
            return .synthesizedPricingMode
        }

        if normalized.contains("exploratory commitment") || normalized == "exploratory" {
            return .synthesizedCommitmentMode
        }

        if normalized.contains("on-site leaning") || normalized.contains("onsite leaning") {
            return .onSiteLeaningDefault
        }

        if normalized == "remote-friendly" || normalized == "remote friendly" {
            return .remoteFriendlyDefault
        }

        if isFulfillmentPostureComposite(normalized) {
            return .fulfillmentPosture
        }

        if normalized.contains("fixed pricing")
            || normalized.contains("custom pricing")
            || normalized.contains("active commitment")
            || normalized.contains("approval required") {
            if normalized.contains("remote-friendly")
                || normalized.contains("on-site leaning")
                || normalized.contains("exploratory")
                || normalized.contains("quote on request") {
                return .fulfillmentPosture
            }
        }

        return nil
    }

    public static func allowsDetailsFallbackLine(_ line: String) -> Bool {
        suppressionCategory(for: line) == nil
    }

    public static func filterDetailsFallbackLines(
        _ lines: [String],
        source: String
    ) -> [String] {
        lines.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let category = suppressionCategory(for: trimmed) {
                logSuppression(source: source, category: category)
                return nil
            }
            return trimmed
        }
    }

    public static func filterCommercialSkimLines(
        _ lines: [String],
        source: String
    ) -> [String] {
        filterDetailsFallbackLines(lines, source: source)
    }

    // MARK: - Private

    private static func isFulfillmentPostureComposite(_ normalized: String) -> Bool {
        let hasPricing = normalized.contains("quote on request")
            || normalized.contains("fixed pricing")
            || normalized.contains("custom pricing")
        let hasCommitment = normalized.contains("exploratory")
            || normalized.contains("active commitment")
            || normalized.contains("approval required")
        let hasRemotePosture = normalized.contains("remote-friendly")
            || normalized.contains("on-site leaning")
        return (hasPricing && hasCommitment)
            || (hasPricing && hasRemotePosture)
            || (hasCommitment && hasRemotePosture)
    }

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static func logSuppression(source: String, category: SuppressionCategory) {
        #if DEBUG
        print(
            "[ProviderDetailsCard][legacyGate] source=\(source) " +
            "suppressed=\(category.rawValue) reason=synthesizedFulfillmentNotDetailsSafe"
        )
        #endif
    }
}
