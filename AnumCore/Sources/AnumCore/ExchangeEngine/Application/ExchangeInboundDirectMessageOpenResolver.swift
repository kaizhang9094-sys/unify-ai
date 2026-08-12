import Foundation

/// Inbound DM open routing helpers (metadata-first; no full thread hydration required).
public enum ExchangeInboundDirectMessageOpenResolver: Sendable {

    /// Thread ids to inspect for routing, in hydration order. For `.directMessage` intent the canonical
    /// resolved id is consulted first and the row-linked exchange thread is omitted when already resolved.
    public static func routingCandidateThreadIDs(
        intent: ExchangeInboundConversationOpenIntent,
        rowLinkedThreadID: ExchangeThread.ID?,
        resolvedThreadID: ExchangeThread.ID?
    ) -> [ExchangeThread.ID] {
        switch intent {
        case .directMessage:
            if let resolvedThreadID {
                return [resolvedThreadID]
            }
            if let rowLinkedThreadID {
                return [rowLinkedThreadID]
            }
            return []

        case .providerInquiry, .auto:
            var candidates: [ExchangeThread.ID] = []
            if let rowLinkedThreadID {
                candidates.append(rowLinkedThreadID)
            }
            if let resolvedThreadID, !candidates.contains(resolvedThreadID) {
                candidates.append(resolvedThreadID)
            }
            return candidates
        }
    }

    public static func shouldSkipLinkedExchangeHydration(
        intent: ExchangeInboundConversationOpenIntent,
        rowLinkedThreadID: ExchangeThread.ID?,
        resolvedThreadID: ExchangeThread.ID?
    ) -> Bool {
        guard intent == .directMessage else { return false }
        guard let resolvedThreadID else { return false }
        guard let rowLinkedThreadID else { return false }
        return rowLinkedThreadID != resolvedThreadID
    }
}
