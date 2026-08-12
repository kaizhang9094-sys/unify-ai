import Foundation

/// Canonical commercial-offer anchor resolution shared by audit, UI projection, and hydration paths.
///
/// `ExchangeDiscoveryService.selectBestMatch` / orchestrator `canonicalDiscoverySelection` owns final
/// selection. Downstream layers must read persisted canonical anchors — not recompute from raw object-lane
/// or first-match heuristics — unless no canonical anchor exists.
public enum ExchangeCanonicalSelectionResolution {
    public enum Source: String, Sendable, Hashable {
        case handoff
        case thread
        case canonicalBestMatch
        case childSelectedThread
        case selectedMatch
        case legacyObjectLane
        case legacyFirstMatch
        case none
    }

    public struct Result: Sendable, Hashable {
        public var selectedOfferID: String?
        public var source: Source

        public init(selectedOfferID: String?, source: Source) {
            self.selectedOfferID = selectedOfferID
            self.source = source
        }
    }

    public struct Anchors: Sendable, Hashable {
        public var handoffSelectedOfferID: String?
        public var threadSelectedOfferID: String?
        public var canonicalDiscoverySelectedOfferID: String?
        public var primaryCoordinationChildOfferID: String?
        /// When true, `primaryCoordinationChildOfferID` may be used (UI coordination cards).
        public var allowChildCoordinationAnchor: Bool

        public init(
            handoffSelectedOfferID: String? = nil,
            threadSelectedOfferID: String? = nil,
            canonicalDiscoverySelectedOfferID: String? = nil,
            primaryCoordinationChildOfferID: String? = nil,
            allowChildCoordinationAnchor: Bool = false
        ) {
            self.handoffSelectedOfferID = handoffSelectedOfferID
            self.threadSelectedOfferID = threadSelectedOfferID
            self.canonicalDiscoverySelectedOfferID = canonicalDiscoverySelectedOfferID
            self.primaryCoordinationChildOfferID = primaryCoordinationChildOfferID
            self.allowChildCoordinationAnchor = allowChildCoordinationAnchor
        }
    }

    public static func anchors(from response: ExchangeOrchestrator.Response) -> Anchors {
        Anchors(
            handoffSelectedOfferID: response.handoff.selectedOfferID,
            threadSelectedOfferID: response.thread.selectedOfferID,
            canonicalDiscoverySelectedOfferID: response.canonicalDiscoverySelection?.offerID,
            primaryCoordinationChildOfferID: response.canonicalDiscoverySelection?.primaryCoordinationChildOfferID,
            allowChildCoordinationAnchor: true
        )
    }

    public static func anchors(
        from detail: ExchangeModels.ThreadDetail,
        allowChildCoordinationAnchor: Bool = true
    ) -> Anchors {
        Anchors(
            handoffSelectedOfferID: nil,
            threadSelectedOfferID: detail.thread.selectedOfferID,
            canonicalDiscoverySelectedOfferID: detail.canonicalDiscoverySelectedOfferID,
            primaryCoordinationChildOfferID: detail.primaryCoordinationChildOfferID,
            allowChildCoordinationAnchor: allowChildCoordinationAnchor
        )
    }

    public static func anchors(
        from thread: ExchangeThread,
        allowChildCoordinationAnchor: Bool = false
    ) -> Anchors {
        Anchors(
            handoffSelectedOfferID: nil,
            threadSelectedOfferID: thread.selectedOfferID,
            canonicalDiscoverySelectedOfferID:
                ExchangeThreadCanonicalDiscoverySelectionMetadata.selectedOfferID(from: thread.metadata),
            primaryCoordinationChildOfferID:
                ExchangeThreadCanonicalDiscoverySelectionMetadata.primaryCoordinationChildOfferID(from: thread.metadata),
            allowChildCoordinationAnchor: allowChildCoordinationAnchor
        )
    }

    public static func resolve(
        anchors: Anchors,
        thread: ExchangeThread,
        matches: [ExchangeMatch],
        location: String,
        logResolution: Bool = true
    ) -> Result {
        let handoff = normalized(anchors.handoffSelectedOfferID)
        let threadSelected = normalized(anchors.threadSelectedOfferID)
        let canonical = normalized(anchors.canonicalDiscoverySelectedOfferID)
        let child = normalized(anchors.primaryCoordinationChildOfferID)

        let result: Result
        if let handoff {
            result = Result(selectedOfferID: handoff, source: .handoff)
        } else if let threadSelected {
            result = Result(selectedOfferID: threadSelected, source: .thread)
        } else if let canonical {
            result = Result(selectedOfferID: canonical, source: .canonicalBestMatch)
        } else if anchors.allowChildCoordinationAnchor, let child {
            result = Result(selectedOfferID: child, source: .childSelectedThread)
        } else if let selectedMatchOffer = selectedOfferIDFromSelectedStatus(in: matches) {
            result = Result(selectedOfferID: selectedMatchOffer, source: .selectedMatch)
        } else if let legacyObjectLane = legacyObjectLaneOfferID(thread: thread, matches: matches) {
            result = Result(selectedOfferID: legacyObjectLane, source: .legacyObjectLane)
        } else if let legacyFirst = legacyFirstMatchOfferID(in: matches) {
            result = Result(selectedOfferID: legacyFirst, source: .legacyFirstMatch)
        } else {
            result = Result(selectedOfferID: nil, source: .none)
        }

        if logResolution {
            log(
                location: location,
                source: result.source,
                selectedOfferID: result.selectedOfferID,
                canonicalSelectedOfferID: canonical,
                threadSelectedOfferID: threadSelected
            )
        }

        return result
    }

    public static func resolveOfferID(
        anchors: Anchors,
        thread: ExchangeThread,
        matches: [ExchangeMatch] = [],
        location: String,
        logResolution: Bool = false
    ) -> String? {
        resolve(
            anchors: anchors,
            thread: thread,
            matches: matches,
            location: location,
            logResolution: logResolution
        ).selectedOfferID
    }

    // MARK: - Legacy fallbacks (only when no canonical anchor exists)

    private static func selectedOfferIDFromSelectedStatus(in matches: [ExchangeMatch]) -> String? {
        guard let selectedMatch = matches.first(where: { $0.status == .selected }) else {
            return nil
        }
        return normalized(selectedMatch.offerID)
            ?? normalized(selectedMatch.matchedOfferIDs.first)
    }

    private static func legacyObjectLaneOfferID(
        thread: ExchangeThread,
        matches: [ExchangeMatch]
    ) -> String? {
        guard ExchangeOfferObjectLane.isObjectLaneActive(thread: thread) else { return nil }
        for match in sortedMatches(matches) {
            if let resolved = ExchangeOfferObjectLane.resolveSelectedOfferID(
                provenObjectOfferIDs: Set(match.provenObjectOfferIDs),
                objectEvidenceScoreByOfferID: match.objectEvidenceScoreByOfferID
            ) {
                return normalized(resolved)
            }
        }
        return nil
    }

    private static func legacyFirstMatchOfferID(in matches: [ExchangeMatch]) -> String? {
        let sorted = sortedMatches(matches)
        return normalized(sorted.first?.offerID)
            ?? normalized(sorted.first?.matchedOfferIDs.first)
    }

    private static func sortedMatches(_ matches: [ExchangeMatch]) -> [ExchangeMatch] {
        matches.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func log(
        location: String,
        source: Source,
        selectedOfferID: String?,
        canonicalSelectedOfferID: String?,
        threadSelectedOfferID: String?
    ) {
        #if DEBUG
        Swift.print(
            "[CanonicalSelectionResolution] " +
            "location=\(location) " +
            "source=\(source.rawValue) " +
            "selectedOfferID=\(selectedOfferID ?? "nil") " +
            "canonicalSelectedOfferID=\(canonicalSelectedOfferID ?? "nil") " +
            "threadSelectedOfferID=\(threadSelectedOfferID ?? "nil")"
        )
        #endif
    }
}

public extension ExchangeThread {
    /// Thread-selected or metadata-persisted discovery best-match offer anchor (no legacy recompute).
    var canonicalCommercialOfferAnchor: String? {
        let threadOffer = selectedOfferID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let threadOffer, !threadOffer.isEmpty {
            return threadOffer
        }
        return ExchangeThreadCanonicalDiscoverySelectionMetadata.selectedOfferID(from: metadata)
    }
}
