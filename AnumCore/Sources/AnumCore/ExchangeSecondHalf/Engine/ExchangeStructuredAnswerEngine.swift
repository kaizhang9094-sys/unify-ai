import Foundation

/// Answers routine provider/requester questions from structured memory before generation.
///
/// This is intentionally conservative: it answers only when there is a clear
/// structured fact match. If not, it returns no answer and lets later layers
/// escalate or draft with more context.
public struct ExchangeStructuredAnswerEngine: Sendable {
    public init() {}

    public enum QueryKind: String, Codable, CaseIterable, Hashable, Sendable {
        case pricing
        case itemsServices
        case availability
        case serviceArea
        case locations
        case standardPolicy
        case requesterConstraint
        case general
    }

    public struct Query: Codable, Hashable, Sendable {
        public var rawText: String
        public var kind: QueryKind

        public init(
            rawText: String,
            kind: QueryKind = .general
        ) {
            self.rawText = rawText
            self.kind = kind
        }
    }

    public struct Answer: Codable, Hashable, Sendable {
        public var text: String
        public var sourcedFacts: [String]
        public var confidence: Double

        public init(
            text: String,
            sourcedFacts: [String],
            confidence: Double
        ) {
            self.text = text
            self.sourcedFacts = sourcedFacts
            self.confidence = confidence
        }
    }

    public func answer(
        query: Query,
        memory: ExchangeStructuredOperatingMemory
    ) -> Answer? {
        let normalized = normalize(query.rawText)

        switch query.kind {
        case .pricing:
            return answerPricing(query: normalized, memory: memory)
        case .itemsServices:
            return answerItemsServices(query: normalized, memory: memory)
        case .availability:
            return answerAvailability(query: normalized, memory: memory)
        case .serviceArea, .locations:
            return answerCoverage(query: normalized, memory: memory)
        case .standardPolicy:
            return answerPolicies(query: normalized, memory: memory)
        case .requesterConstraint:
            return answerRequesterConstraints(query: normalized, memory: memory)
        case .general:
            return answerGeneral(query: normalized, memory: memory)
        }
    }

    private func answerPricing(
        query: String,
        memory: ExchangeStructuredOperatingMemory
    ) -> Answer? {
        let matches = memory.pricingRules.filter {
            query.isEmpty || containsMatch(haystack: [$0.label, $0.amountDescription, $0.notes], query: query)
        }

        guard !matches.isEmpty else { return nil }

        let lines = matches.prefix(3).map { rule in
            if let notes = nonEmpty(rule.notes) {
                return "\(rule.label): \(rule.amountDescription). \(notes)"
            } else {
                return "\(rule.label): \(rule.amountDescription)."
            }
        }

        return Answer(
            text: lines.joined(separator: " "),
            sourcedFacts: matches.prefix(3).map { "\($0.label): \($0.amountDescription)" },
            confidence: 0.95
        )
    }

    private func answerItemsServices(
        query: String,
        memory: ExchangeStructuredOperatingMemory
    ) -> Answer? {
        let activeItems = memory.serviceItems.filter(\.isActive)
        let matches = activeItems.filter {
            query.isEmpty || containsMatch(haystack: [$0.name, $0.details], query: query)
        }

        guard !matches.isEmpty else { return nil }

        let lines = matches.prefix(5).map { item in
            if let details = nonEmpty(item.details) {
                return "\(item.name): \(details)"
            } else {
                return item.name
            }
        }

        return Answer(
            text: "Relevant services/items: " + lines.joined(separator: "; ") + ".",
            sourcedFacts: matches.prefix(5).map(\.name),
            confidence: 0.9
        )
    }

    private func answerAvailability(
        query: String,
        memory: ExchangeStructuredOperatingMemory
    ) -> Answer? {
        let availabilityMatches = memory.availabilityWindows.filter {
            query.isEmpty || containsMatch(haystack: [$0.label, $0.details], query: query)
        }

        let capacityMatches = memory.capacityRules.filter {
            query.isEmpty || containsMatch(haystack: [$0.label, $0.details], query: query)
        }

        guard !availabilityMatches.isEmpty || !capacityMatches.isEmpty else {
            return nil
        }

        var parts: [String] = []

        if !availabilityMatches.isEmpty {
            let availabilityText = availabilityMatches.prefix(3).map { window in
                if let details = nonEmpty(window.details) {
                    return "\(window.label): \(details)"
                } else {
                    return window.label
                }
            }.joined(separator: "; ")

            parts.append("Availability: \(availabilityText).")
        }

        if !capacityMatches.isEmpty {
            let capacityText = capacityMatches.prefix(3).map { cap in
                if let details = nonEmpty(cap.details) {
                    return "\(cap.label): \(details)"
                } else {
                    return cap.label
                }
            }.joined(separator: "; ")

            parts.append("Capacity: \(capacityText).")
        }

        return Answer(
            text: parts.joined(separator: " "),
            sourcedFacts: availabilityMatches.prefix(3).map(\.label) + capacityMatches.prefix(3).map(\.label),
            confidence: 0.9
        )
    }

    private func answerCoverage(
        query: String,
        memory: ExchangeStructuredOperatingMemory
    ) -> Answer? {
        let matches = memory.coverageAreas.filter {
            query.isEmpty || containsMatch(haystack: [$0.name, $0.details], query: query)
        }

        guard !matches.isEmpty else { return nil }

        let text = matches.prefix(5).map { area in
            if let details = nonEmpty(area.details) {
                return "\(area.name): \(details)"
            } else {
                return area.name
            }
        }.joined(separator: "; ")

        return Answer(
            text: "Coverage/service area: \(text).",
            sourcedFacts: matches.prefix(5).map(\.name),
            confidence: 0.92
        )
    }

    private func answerPolicies(
        query: String,
        memory: ExchangeStructuredOperatingMemory
    ) -> Answer? {
        let matches = memory.standardPolicies.filter {
            query.isEmpty || containsMatch(haystack: [$0.title, $0.details], query: query)
        }

        guard !matches.isEmpty else { return nil }

        let text = matches.prefix(4).map { "\($0.title): \($0.details)" }.joined(separator: " ")

        return Answer(
            text: text,
            sourcedFacts: matches.prefix(4).map(\.title),
            confidence: 0.9
        )
    }

    private func answerRequesterConstraints(
        query: String,
        memory: ExchangeStructuredOperatingMemory
    ) -> Answer? {
        let matches = memory.requesterConstraints.filter {
            query.isEmpty || containsMatch(haystack: [$0.key, $0.value], query: query)
        }

        guard !matches.isEmpty else { return nil }

        let text = matches.prefix(5).map { "\($0.key): \($0.value)" }.joined(separator: "; ")

        return Answer(
            text: "Known requester constraints: \(text).",
            sourcedFacts: matches.prefix(5).map { "\($0.key): \($0.value)" },
            confidence: 0.88
        )
    }

    private func answerGeneral(
        query: String,
        memory: ExchangeStructuredOperatingMemory
    ) -> Answer? {
        answerPricing(query: query, memory: memory)
        ?? answerItemsServices(query: query, memory: memory)
        ?? answerAvailability(query: query, memory: memory)
        ?? answerCoverage(query: query, memory: memory)
        ?? answerPolicies(query: query, memory: memory)
        ?? answerRequesterConstraints(query: query, memory: memory)
    }

    private func containsMatch(
        haystack: [String?],
        query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }

        return haystack
            .compactMap(nonEmpty)
            .map(normalize)
            .contains { $0.contains(query) || query.contains($0) }
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
