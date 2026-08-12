import Foundation

/// Produces cheap, high-value "what changed" summaries.
///
/// This is intentionally lightweight and deterministic. It should help the UI
/// and decision framing layer explain movement without replaying the thread log.
public struct ExchangeChangeSummaryBuilder: Sendable {
    public init() {}

    public func build(
        from delta: ExchangeThreadDelta?
    ) -> [String] {
        guard let delta, delta.hasMeaningfulChange else {
            return []
        }

        var items: [String] = []

        items.append(contentsOf: cleaned(delta.newFactsLearned))

        switch delta.riskChange {
        case .increased:
            items.append("Risk increased.")
        case .decreased:
            items.append("Risk decreased.")
        case .unchanged:
            break
        }

        switch delta.readinessShift {
        case .increased:
            items.append("The thread moved closer to decision.")
        case .decreased:
            items.append("The thread became less decision-ready.")
        case .unchanged:
            break
        }

        if delta.recommendationChanged {
            items.append("The recommendation changed.")
        }

        if delta.nextStepChanged {
            items.append("The recommended next step changed.")
        }

        if let significance = nonEmpty(delta.significanceExplanation) {
            items.append(significance)
        }

        return cleaned(items)
    }

    public func buildShortSummary(
        from delta: ExchangeThreadDelta?
    ) -> String? {
        let items = build(from: delta)
        guard !items.isEmpty else { return nil }
        return items.joined(separator: " ")
    }

    private func cleaned(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                output.append(trimmed)
            }
        }

        return output
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
