import Foundation
import AnumCore

#if DEBUG

enum AppSearchSmokeUIProjectionCapture {
    @MainActor
    static func capture(from detail: ExchangeModels.ThreadDetail) -> AppSearchSmokeUIProjectionSnapshot {
        let anchor = SecretarySearchResultProjection.resolveUIOfferAnchor(for: detail)
        let effectiveSelectedOfferID = anchor.offerID
        let cards = SecretarySearchResultProjection.cardProjections(from: detail)
        let preferredCard = effectiveSelectedOfferID.flatMap { offerID in
            cards.first(where: { $0.offerID == offerID })
        } ?? cards.first(where: { $0.isPreferred }) ?? cards.first
        let selectedMatch = detail.selectedMatch

        let sortedMatches = detail.matches.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }
        var matchedOffersByNode: [String: [String]] = [:]
        var seenNodes = Set<String>()
        for match in sortedMatches {
            let nodeID = match.counterpartyID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nodeID.isEmpty, !seenNodes.contains(nodeID) else { continue }
            seenNodes.insert(nodeID)
            matchedOffersByNode.merge(
                ExchangeProjectionDedup.aggregateProjectedOffersByNode(
                    nodeID: match.counterpartyID,
                    offerID: match.offerID,
                    matchedOfferIDs: match.matchedOfferIDs
                )
            ) { _, new in new }
        }

        let resolvedSelectedOfferID = effectiveSelectedOfferID
            ?? preferredCard?.offerID
            ?? selectedMatch?.offerID
        let uiCardOfferID = effectiveSelectedOfferID
            ?? preferredCard?.offerID
            ?? selectedMatch?.offerID

        let surfaceLead = ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: resolvedSelectedOfferID,
            selectedPublicProfileID: detail.selectedPublicProfileID ?? detail.thread.selectedPublicProfileID
        )

        let displaySearchQuery = ExchangeThreadSearchQueryDisplay.displaySearchQuery(
            for: detail.thread,
            turns: detail.turns
        )?.text
        let capturedRequestText = capturedRequestText(from: detail, displaySearchQuery: displaySearchQuery)
        let visibleSummary = detail.inboxItems.first?.visibleSummary
            ?? detail.timelineItems.first(where: { !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.summary
        let threadTitle = ExchangeThreadCardTitleProjection.inboxCardTitle(
            requestCapturedFromTurn: capturedRequestText,
            interpretationUserQuestion: detail.interpretationQuestion,
            threadStoredTitle: detail.thread.intent.title,
            draftedSubject: nil,
            hydratedOpportunityTitle: nil,
            prioritizeHydratedOpportunityTitle: false,
            threadID: detail.thread.id,
            surface: "multilingualE2ESmoke"
        ).title

        return AppSearchSmokeUIProjectionSnapshot(
            selectedOfferID: resolvedSelectedOfferID,
            matchedOffersByNode: matchedOffersByNode,
            preferredMatchCounterpartyID: selectedMatch?.counterpartyID ?? preferredCard?.nodeID,
            preferredMatchOfferID: selectedMatch?.offerID ?? preferredCard?.offerID ?? effectiveSelectedOfferID,
            cardOfferID: uiCardOfferID,
            visiblePublicProfileID: detail.selectedPublicProfileID ?? detail.thread.selectedPublicProfileID,
            surfaceLead: String(describing: surfaceLead),
            displaySearchQuery: displaySearchQuery,
            capturedRequestText: capturedRequestText,
            visibleSummary: visibleSummary,
            threadTitle: threadTitle
        )
    }

    private static func capturedRequestText(
        from detail: ExchangeModels.ThreadDetail,
        displaySearchQuery: String?
    ) -> String? {
        if let userTurn = detail.turns.first(where: { $0.kind == .requestCaptured && $0.actor == .user }),
           let text = turnDisplayText(from: userTurn) {
            return text
        }
        if let turn = detail.turns.first(where: { $0.kind == .requestCaptured }),
           let text = turnDisplayText(from: turn) {
            return text
        }
        if let stored = detail.thread.metadata[ExchangeThread.originalRequesterTextMetadataKey],
           let text = firstNonEmpty(stored) {
            return text
        }
        return firstNonEmpty(
            displaySearchQuery,
            detail.thread.intent.objective,
            detail.thread.intent.title,
            detail.summary
        )
    }

    private static func turnDisplayText(from turn: ExchangeTurn) -> String? {
        firstNonEmpty(turn.detail, turn.summary)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

#endif
