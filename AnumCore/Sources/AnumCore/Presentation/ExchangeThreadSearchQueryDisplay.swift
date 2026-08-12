import Foundation

/// Read-path ownership for the durable search/request query on a thread.
///
/// Separates query text from display summaries (`visibleSummary`) and selection copy.
public enum ExchangeThreadSearchQueryDisplay: Sendable {

    public struct Resolution: Sendable, Hashable {
        public var text: String
        public var source: String

        public init(text: String, source: String) {
            self.text = text
            self.source = source
        }
    }

    /// Resolves the canonical user search/request query for display and debug read paths.
    public static func displaySearchQuery(
        for thread: ExchangeThread,
        turns: [ExchangeTurn]
    ) -> Resolution? {
        if let stored = trimmedNonEmpty(thread.metadata[ExchangeThread.originalRequesterTextMetadataKey]),
           !thread.looksLikeInternalSearchQuery(stored),
           !ExchangeChildCoordinationRequestText.isDiscoveryOrSelectionSummary(stored) {
            return Resolution(text: stored, source: "originalRequesterText")
        }

        if let queryTurn = firstQuerySemanticSearchStartedTurn(from: turns),
           let queryText = searchStartedQueryText(from: queryTurn),
           !thread.looksLikeInternalSearchQuery(queryText),
           !ExchangeChildCoordinationRequestText.isDiscoveryOrSelectionSummary(queryText) {
            return Resolution(text: queryText, source: "searchStartedTurn")
        }

        if let captured = ExchangeChildCoordinationRequestText.capturedRequesterText(from: turns),
           !captured.isEmpty,
           !thread.looksLikeInternalSearchQuery(captured),
           !ExchangeChildCoordinationRequestText.isDiscoveryOrSelectionSummary(captured) {
            return Resolution(text: captured, source: "requestCaptured")
        }

        let primary = thread.primarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty,
           !ExchangeChildCoordinationRequestText.isLikelyKeywordRail(
               primary,
               interpretation: thread.interpretation
           ),
           !ExchangeChildCoordinationRequestText.isDiscoveryOrSelectionSummary(primary) {
            return Resolution(text: primary, source: "primarySearchText")
        }

        return nil
    }

    // MARK: - Internals

    private static let searchStartedPlaceholders: Set<String> = [
        "search started.",
        "search refreshed."
    ]

    static func firstQuerySemanticSearchStartedTurn(from turns: [ExchangeTurn]) -> ExchangeTurn? {
        turns
            .filter { $0.kind == .searchStarted }
            .sorted { $0.createdAt < $1.createdAt }
            .first { turn in
                guard let text = searchStartedQueryText(from: turn) else { return false }
                return !searchStartedPlaceholders.contains(text.lowercased())
            }
    }

    static func searchStartedQueryText(from turn: ExchangeTurn) -> String? {
        let detail = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            return detail
        }
        let summary = turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private static func trimmedNonEmpty(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
