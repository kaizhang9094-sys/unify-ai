import Foundation
import AnumCore

// MARK: - Recent activity projections (Threads tab — Recent mode)

enum SecretaryRecentSessionKind: String, Sendable, Hashable {
    case outboundSearch
    case inboundInquiry
    case noMatch
    case activeCoordination
    case unknown
}

enum SecretarySearchResultKind: String, Sendable, Hashable {
    case commercial
    case social
    case unknown
}

enum SecretarySearchResultCTA: String, Sendable, Hashable {
    case openPath
    /// Umbrella has coordination children but this card has no exact child match.
    case openPaths
    case openThread
    case viewDetails
    case compare
    case connect
}

/// How a Recent card opens a coordination child path (if at all).
enum SecretarySearchResultPathAccess: Sendable, Hashable {
    case none
    case exactChild(ExchangeThread.ID)
    case umbrellaPaths(umbrellaThreadID: ExchangeThread.ID)
}

struct SecretarySearchResultCardProjection: Identifiable, Sendable, Hashable {
    let id: String
    let displayName: String
    let headline: String?
    let subtitle: String?
    let primaryImageURL: String?
    let publicSupporterPresentation: ExchangeSupporterPresentation?
    let serviceAreaLine: String?
    let socialTagsLine: String?
    let matchReasonSummary: String?
    let knownFactLines: [String]
    let strengthBadge: String?
    let scoreText: String?
    let isPreferred: Bool
    let nodeID: String?
    let publicProfileID: String?
    let offerID: String?
    /// Thread opened by the card primary action (child when activated, else umbrella workbench).
    let linkedThreadID: ExchangeThread.ID
    /// Umbrella search workbench used for compare and full result sets.
    let umbrellaThreadID: ExchangeThread.ID
    /// True when this card is paired with a specific child thread.
    let isActivatedCoordinationPath: Bool
    let hasAnyCoordinationChildren: Bool
    let coordinationChildCount: Int
    let pathAccess: SecretarySearchResultPathAccess
    let primaryCTA: SecretarySearchResultCTA
    let showsCompareCTA: Bool
}

struct SecretaryRecentInquiryCardProjection: Sendable, Hashable {
    let senderTitle: String
    let summary: String
    let statusLabel: String
    let factLines: [String]
    let primaryImageURL: String?
    let ctaTitle: String
    let threadID: ExchangeThread.ID
}

struct SecretaryRecentActivityCardProjection: Sendable, Hashable {
    let title: String
    let summary: String
    let statusLabel: String?
    let ctaTitle: String
    let threadID: ExchangeThread.ID
}

struct SecretarySearchResultSessionProjection: Sendable, Hashable {
    let threadID: ExchangeThread.ID
    let sessionKind: SecretaryRecentSessionKind
    let searchTitle: String
    let updatedAt: Date
    let relativeTimeText: String
    let resultCount: Int
    let statusLine: String?
    let resultKind: SecretarySearchResultKind
    let cards: [SecretarySearchResultCardProjection]
    let inquiryCard: SecretaryRecentInquiryCardProjection?
    let activityCard: SecretaryRecentActivityCardProjection?
    let recoverySuggestions: [String]
    let showsNoMatchRecovery: Bool
    let showsCompareAllCTA: Bool
}

enum SecretarySearchResultProjection {
    #if DEBUG
    private static func logNoMatchProjectionPolicy(
        action: String,
        surface: String,
        threadID: ExchangeThread.ID? = nil
    ) {
        print(
            "[NoMatchProjectionPolicy] action=\(action) surface=\(surface) " +
            "threadID=\(threadID?.uuidString ?? "nil")"
        )
    }
    #else
    private static func logNoMatchProjectionPolicy(action: String, surface: String, threadID: ExchangeThread.ID? = nil) {}
    #endif

    /// Active search picker pool: eligible visible search rows (including terminal no-match receipts).
    private static func activeSearchPickerPool(
        from items: [ExchangeModels.InboxItem],
        pendingApprovalThreadIDs: Set<ExchangeThread.ID>,
        surface: String,
        allowRecoveryOnlyTerminal: Bool
    ) -> [ExchangeModels.InboxItem] {
        let eligible = items.filter {
            isRecentEligible($0, pendingApprovalThreadIDs: pendingApprovalThreadIDs)
        }
        if !eligible.isEmpty {
            return eligible
        }
        guard allowRecoveryOnlyTerminal else { return [] }
        let terminalOnly = items.filter { isTerminalNoMatchRecoveryEligible($0) }
        if let first = terminalOnly.max(by: { $0.updatedAt < $1.updatedAt }) {
            logNoMatchProjectionPolicy(action: "recoveryOnly", surface: surface, threadID: first.threadID)
        }
        return terminalOnly
    }

    private static func isTerminalNoMatchRecoveryEligible(_ item: ExchangeModels.InboxItem) -> Bool {
        if item.threadRole == .candidateCoordination { return false }
        guard SecretaryProjectionEngine.isTerminalNoMatchSearch(item) else { return false }
        return item.shouldDiscover || item.threadRole == .umbrellaSearch
    }

    /// Priority / current-work row: state urgency first, then preferred, then `updatedAt`.
    static func pickCurrentSearchResultItem(
        from items: [ExchangeModels.InboxItem],
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = [],
        preferredThreadID: ExchangeThread.ID? = nil
    ) -> ExchangeModels.InboxItem? {
        let eligible = activeSearchPickerPool(
            from: items,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs,
            surface: "pickCurrent",
            allowRecoveryOnlyTerminal: false
        )
        guard !eligible.isEmpty else { return nil }

        #if DEBUG
        for item in eligible {
            let rank = recentEndStateRank(item, pendingApprovalThreadIDs: pendingApprovalThreadIDs)
            print(
                "[RecentPicker] candidate thread=\(item.threadID.uuidString) " +
                "state=\(item.state) updatedAt=\(item.updatedAt) rank=\(rank) " +
                "eligible=true selectedOffer=\(item.selectedOfferID != nil) " +
                "selectedCounterparty=\(item.selectedCounterpartyID != nil) " +
                "candidateCount=\(item.candidateCount) " +
                "reason=\(recentEndStateRankReason(item, pendingApprovalThreadIDs: pendingApprovalThreadIDs))"
            )
        }
        #endif

        let selected = eligible.sorted { lhs, rhs in
            let lhsRank = recentEndStateRank(lhs, pendingApprovalThreadIDs: pendingApprovalThreadIDs)
            let rhsRank = recentEndStateRank(rhs, pendingApprovalThreadIDs: pendingApprovalThreadIDs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            if let preferredThreadID {
                if lhs.threadID == preferredThreadID && rhs.threadID != preferredThreadID { return true }
                if rhs.threadID == preferredThreadID && lhs.threadID != preferredThreadID { return false }
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.threadID.uuidString < rhs.threadID.uuidString
        }.first

        #if DEBUG
        if let selected {
            let rank = recentEndStateRank(selected, pendingApprovalThreadIDs: pendingApprovalThreadIDs)
            print(
                "[RecentPicker] selected thread=\(selected.threadID.uuidString) " +
                "state=\(selected.state) rank=\(rank) " +
                "reason=\(recentEndStateRankReason(selected, pendingApprovalThreadIDs: pendingApprovalThreadIDs))"
            )
        }
        #endif

        return selected
    }

    /// Latest submitted search for Dashboard discovery strip and Threads → Recent (`updatedAt` first).
    static func pickLatestSearchResultItem(
        from items: [ExchangeModels.InboxItem],
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = [],
        preferredThreadID: ExchangeThread.ID? = nil,
        surface: String = "threadsRecent",
        preferPreferredWhenEligible: Bool = false
    ) -> ExchangeModels.InboxItem? {
        let eligible = activeSearchPickerPool(
            from: items,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs,
            surface: surface,
            allowRecoveryOnlyTerminal: true
        )
        guard !eligible.isEmpty else { return nil }

        let preferredInEligible = preferredThreadID.flatMap { id in
            eligible.first(where: { $0.threadID == id })
        }

        let preferPreferred = preferPreferredWhenEligible && preferredInEligible != nil

        let selected = eligible.sorted { lhs, rhs in
            if preferPreferred, let preferredThreadID {
                let lhsPreferred = lhs.threadID == preferredThreadID
                let rhsPreferred = rhs.threadID == preferredThreadID
                if lhsPreferred != rhsPreferred {
                    return lhsPreferred
                }
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            if let preferredThreadID {
                if lhs.threadID == preferredThreadID && rhs.threadID != preferredThreadID { return true }
                if rhs.threadID == preferredThreadID && lhs.threadID != preferredThreadID { return false }
            }

            let lhsRank = recentEndStateRank(lhs, pendingApprovalThreadIDs: pendingApprovalThreadIDs)
            let rhsRank = recentEndStateRank(rhs, pendingApprovalThreadIDs: pendingApprovalThreadIDs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.threadID.uuidString < rhs.threadID.uuidString
        }.first

        #if DEBUG
        if let selected {
            let rank = recentEndStateRank(selected, pendingApprovalThreadIDs: pendingApprovalThreadIDs)
            let title = cleaned(selected.capturedRequestText) ?? selected.title
            print(
                "[RecentSearchTrace][picker] surface=\(surface) mode=latestSearch " +
                "candidateCount=\(eligible.count) selectedThreadID=\(selected.threadID.uuidString) " +
                "selectedTitle=\(title) selectedUpdatedAt=\(selected.updatedAt) " +
                "preferredThreadID=\(preferredThreadID?.uuidString ?? "nil") stateRank=\(rank) " +
                "preferredEligible=\(preferredInEligible != nil)"
            )
        } else {
            print(
                "[RecentSearchTrace][picker] surface=\(surface) mode=latestSearch " +
                "candidateCount=0 selectedThreadID=nil preferredThreadID=\(preferredThreadID?.uuidString ?? "nil")"
            )
        }
        #endif

        return selected
    }

    /// Latest meaningful secretary thread for Recent mode (latest search, not priority work queue).
    static func pickLatestRecentInboxItem(
        from items: [ExchangeModels.InboxItem],
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = [],
        preferredThreadID: ExchangeThread.ID? = nil
    ) -> ExchangeModels.InboxItem? {
        pickLatestSearchResultItem(
            from: items,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs,
            preferredThreadID: preferredThreadID,
            surface: "threadsRecent"
        )
    }

    /// Lower rank = higher priority for priority picker tie-breaks. `updatedAt` is primary in `pickLatestSearchResultItem`.
    static func recentEndStateRank(
        _ item: ExchangeModels.InboxItem,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID>
    ) -> Int {
        if item.hasPendingApproval || pendingApprovalThreadIDs.contains(item.threadID) {
            return 0
        }
        if item.needsClarification {
            return 0
        }
        switch item.state {
        case .needsClarification, .awaitingApproval:
            return 0
        case .searching:
            return 1
        case .drafting, .draftReady:
            return item.shouldDiscover ? 1 : 6
        case .matchCandidatesWeak:
            return 2
        case .noViableMatch:
            return 7
        case .matchFound:
            return SecretaryProjectionEngine.hasSummaryDiscoveryResultEvidence(for: item) ? 4 : 5
        default:
            return 6
        }
    }

    static func recentEndStateRankReason(
        _ item: ExchangeModels.InboxItem,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID>
    ) -> String {
        if item.hasPendingApproval || pendingApprovalThreadIDs.contains(item.threadID) {
            return "pendingApproval"
        }
        if item.needsClarification {
            return "needsClarificationFlag"
        }
        switch item.state {
        case .needsClarification:
            return "needsClarification"
        case .awaitingApproval:
            return "awaitingApproval"
        case .searching:
            return "searching"
        case .drafting, .draftReady:
            return item.shouldDiscover ? "activeSearchDraft" : "otherEligible"
        case .noViableMatch:
            return "noViableMatch"
        case .matchCandidatesWeak:
            return "matchCandidatesWeak"
        case .matchFound:
            return SecretaryProjectionEngine.hasSummaryDiscoveryResultEvidence(for: item)
                ? "verifiedMatchFound"
                : "unverifiedMatchFound"
        default:
            return "otherEligible"
        }
    }

    static func buildSession(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail,
        supplementalProfileImageURLsByNodeID: [String: String] = [:],
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = []
    ) -> SecretarySearchResultSessionProjection {
        let ranked = rankedMatches(for: detail)
        let sessionKind = classifyRecentSessionKind(
            inboxItem: inboxItem,
            detail: detail,
            rankedMatches: ranked,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs
        )

        let title = primaryTitle(
            inboxItem: inboxItem,
            detail: detail,
            sessionKind: sessionKind
        )
        let relativeTime = SecretaryRelativeTime.string(from: inboxItem.updatedAt)

        switch sessionKind {
        case .inboundInquiry:
            let inquiry = buildInquiryCard(
                inboxItem: inboxItem,
                detail: detail,
                supplementalProfileImageURLsByNodeID: supplementalProfileImageURLsByNodeID
            )
            return SecretarySearchResultSessionProjection(
                threadID: detail.thread.id,
                sessionKind: .inboundInquiry,
                searchTitle: title,
                updatedAt: inboxItem.updatedAt,
                relativeTimeText: relativeTime,
                resultCount: 0,
                statusLine: nil,
                resultKind: resultKind(for: detail),
                cards: [],
                inquiryCard: inquiry,
                activityCard: nil,
                recoverySuggestions: [],
                showsNoMatchRecovery: false,
                showsCompareAllCTA: false
            )

        case .noMatch:
            return SecretarySearchResultSessionProjection(
                threadID: detail.thread.id,
                sessionKind: .noMatch,
                searchTitle: title,
                updatedAt: inboxItem.updatedAt,
                relativeTimeText: relativeTime,
                resultCount: 0,
                statusLine: statusLine(inboxItem: inboxItem, detail: detail, resultCount: 0),
                resultKind: resultKind(for: detail),
                cards: [],
                inquiryCard: nil,
                activityCard: nil,
                recoverySuggestions: recoverySuggestions(for: detail, inboxItem: inboxItem),
                showsNoMatchRecovery: true,
                showsCompareAllCTA: false
            )

        case .outboundSearch:
            let cards = ranked.enumerated().map { index, match in
                card(
                    for: match,
                    detail: detail,
                    inboxItem: inboxItem,
                    rankIndex: index,
                    ranked: ranked,
                    supplementalProfileImageURLsByNodeID: supplementalProfileImageURLsByNodeID
                )
            }
            let count = cards.count
            let showsCompareAll = SecretaryProjectionEngine.hasMultipleComparePaths(for: detail)
            return SecretarySearchResultSessionProjection(
                threadID: detail.thread.id,
                sessionKind: .outboundSearch,
                searchTitle: title,
                updatedAt: inboxItem.updatedAt,
                relativeTimeText: relativeTime,
                resultCount: count,
                statusLine: statusLine(inboxItem: inboxItem, detail: detail, resultCount: count),
                resultKind: resultKind(for: detail),
                cards: cards,
                inquiryCard: nil,
                activityCard: nil,
                recoverySuggestions: recoverySuggestions(for: detail, inboxItem: inboxItem),
                showsNoMatchRecovery: false,
                showsCompareAllCTA: showsCompareAll
            )

        case .activeCoordination, .unknown:
            let activity = buildActivityCard(
                inboxItem: inboxItem,
                detail: detail,
                sessionKind: sessionKind
            )
            return SecretarySearchResultSessionProjection(
                threadID: detail.thread.id,
                sessionKind: sessionKind,
                searchTitle: title,
                updatedAt: inboxItem.updatedAt,
                relativeTimeText: relativeTime,
                resultCount: 0,
                statusLine: activity.statusLabel,
                resultKind: resultKind(for: detail),
                cards: [],
                inquiryCard: nil,
                activityCard: activity,
                recoverySuggestions: [],
                showsNoMatchRecovery: false,
                showsCompareAllCTA: false
            )
        }
    }

    // MARK: - Immediate submit strip (local override before desk snapshot)

    /// Lightweight inbox row for dashboard strip immediately after local submit (no `listDeskThreads`).
    static func buildImmediateStripInboxItem(
        detail: ExchangeModels.ThreadDetail,
        capturedRequestText: String
    ) -> ExchangeModels.InboxItem {
        let thread = detail.thread
        let interpretation = thread.interpretation
        let trimmedRequest = cleaned(capturedRequestText)
            ?? cleaned(interpretation?.userQuestion)
            ?? cleaned(thread.title)
            ?? "Search request"

        let interpretationNextStep = cleaned(interpretation?.userNextStep)
            ?? noMatchSuggestedNextStep(from: thread.state)
            ?? cleaned(detail.summary)

        let hasPendingApproval: Bool = {
            if thread.approval?.status == .pending { return true }
            if case .awaitingApproval = thread.state { return true }
            return false
        }()

        let candidateCount = max(detail.matches.count, thread.candidateCounterpartyIDs.count)

        return ExchangeModels.InboxItem(
            threadID: thread.id,
            title: trimmedRequest,
            capturedRequestText: trimmedRequest,
            subtitle: detail.summary,
            state: thread.state,
            stateTitle: thread.state.phaseTitle,
            updatedAt: thread.updatedAt,
            requiresHumanDecision: thread.requiresHumanDecision || hasPendingApproval,
            hasFailure: thread.hasFailure,
            visibleSummary: cleaned(detail.summary),
            candidateCount: candidateCount,
            hasPendingApproval: hasPendingApproval,
            interpretationSummary: cleaned(interpretation?.userSummary),
            interpretationQuestion: cleaned(interpretation?.userQuestion),
            interpretationNextStep: interpretationNextStep,
            needsClarification: interpretation?.needsClarification ?? false,
            shouldDiscover: interpretation?.shouldDiscover ?? true,
            shouldDraft: interpretation?.shouldDraft ?? false,
            shouldFederate: interpretation?.shouldFederate ?? false,
            threadRole: thread.threadRole
        )
    }

    /// True when desk snapshot includes the override thread with a reconcilable search outcome state.
    static func shouldClearLocalStripOverride(
        overrideItem: ExchangeModels.InboxItem,
        snapshotThreads: [ExchangeModels.InboxItem]
    ) -> Bool {
        guard let snapshotItem = snapshotThreads.first(where: { $0.threadID == overrideItem.threadID }) else {
            return false
        }
        return stripSearchStatesReconcilable(overrideItem.state, snapshotItem.state)
    }

    private static func stripSearchStatesReconcilable(_ lhs: ExchangeState, _ rhs: ExchangeState) -> Bool {
        switch (lhs, rhs) {
        case (.noViableMatch, .noViableMatch),
             (.matchCandidatesWeak, .matchCandidatesWeak),
             (.matchFound, .matchFound),
             (.searching, .searching):
            return true
        default:
            return lhs == rhs
        }
    }

    private static func noMatchSuggestedNextStep(from state: ExchangeState) -> String? {
        if case .noViableMatch(let status) = state {
            return cleaned(status.suggestedNextStep) ?? cleaned(status.explanation)
        }
        return nil
    }

    // MARK: - Recent eligibility & classification

    private static func isRecentEligible(
        _ item: ExchangeModels.InboxItem,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID>
    ) -> Bool {
        if item.threadRole == .candidateCoordination {
            return false
        }
        let bucket = SecretaryProjectionEngine.bucket(
            for: item,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs
        )
        return bucket != .none
    }

    static func classifyRecentSessionKind(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail,
        rankedMatches: [ExchangeMatch],
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = []
    ) -> SecretaryRecentSessionKind {
        if isInboundInquiry(inboxItem: inboxItem, detail: detail) {
            return .inboundInquiry
        }

        if isOutboundSearchSession(inboxItem: inboxItem, detail: detail) {
            if isSearchInProgress(inboxItem) {
                return .activeCoordination
            }
            if isNoMatchState(inboxItem.state) {
                return .noMatch
            }
            if case .matchCandidatesWeak = inboxItem.state {
                if rankedMatches.isEmpty {
                    return .noMatch
                }
                return .outboundSearch
            }
            if case .matchFound = inboxItem.state {
                if !SecretaryProjectionEngine.hasSummaryDiscoveryResultEvidence(for: inboxItem)
                    || rankedMatches.isEmpty {
                    return .noMatch
                }
                return .outboundSearch
            }
            if rankedMatches.isEmpty {
                return .noMatch
            }
            return .outboundSearch
        }

        if isActiveCoordinationSession(
            inboxItem: inboxItem,
            detail: detail,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs
        ) {
            return .activeCoordination
        }

        return .unknown
    }

    private static func isInboundInquiry(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail
    ) -> Bool {
        if detail.thread.metadata["inbound_thread"]?.trimmingCharacters(in: .whitespacesAndNewlines) == "true" {
            return true
        }
        if inboxItem.prefersInboundProviderCardTitleRewrite {
            return true
        }
        if let preview = cleaned(inboxItem.cardInboundRequesterPreview), !preview.isEmpty {
            if cleaned(inboxItem.cardInboundSenderLabel) != nil || inboxItem.selectedCounterpartyID != nil {
                return true
            }
        }
        if let secondHalf = SecretaryProjectionEngine.secondHalfDisplay(for: inboxItem) {
            if secondHalf.placement == .providerReception || secondHalf.hasProviderReception {
                return true
            }
        }
        return false
    }

    private static func isOutboundSearchSession(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail
    ) -> Bool {
        guard !isInboundInquiry(inboxItem: inboxItem, detail: detail) else { return false }

        if inboxItem.shouldDiscover {
            return true
        }

        switch inboxItem.state {
        case .matchFound, .matchCandidatesWeak, .noViableMatch:
            return true
        default:
            break
        }

        if let secondHalf = SecretaryProjectionEngine.secondHalfDisplay(for: inboxItem) {
            switch secondHalf.placement {
            case .decisionReady, .requesterReview:
                return true
            case .providerReception:
                return false
            default:
                break
            }
            if secondHalf.hasRequesterReview || secondHalf.hasDecisionPacket {
                return true
            }
        }

        return false
    }

    private static func isActiveCoordinationSession(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID>
    ) -> Bool {
        if inboxItem.hasPendingApproval || pendingApprovalThreadIDs.contains(inboxItem.threadID) {
            return true
        }
        if inboxItem.requiresHumanDecision || inboxItem.needsClarification {
            return true
        }
        if SecretaryProjectionEngine.isActive(
            inboxItem,
            pendingApprovalThreadIDs: pendingApprovalThreadIDs
        ) {
            return true
        }
        if let secondHalf = SecretaryProjectionEngine.secondHalfDisplay(for: inboxItem) {
            switch secondHalf.placement {
            case .activeCoordination, .currentFocus, .needsApproval, .needsInput:
                return true
            default:
                break
            }
        }
        _ = detail
        return false
    }

    // MARK: - Card builders (inbound / activity)

    private static func buildInquiryCard(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail,
        supplementalProfileImageURLsByNodeID: [String: String]
    ) -> SecretaryRecentInquiryCardProjection {
        let secondHalf = SecretaryProjectionEngine.secondHalfDisplay(for: inboxItem)
        let reception = secondHalf?.providerReception

        let senderTitle =
            cleaned(inboxItem.cardInboundSenderLabel)
            ?? cleaned(inboxItem.selectedCounterpartyName)
            ?? cleaned(inboxItem.title)
            ?? "New inquiry"

        let summary =
            cleaned(inboxItem.cardInboundRequesterPreview)
            ?? cleaned(reception?.requesterAsk)
            ?? cleaned(reception?.inquirySummary)
            ?? cleaned(reception?.subtitle)
            ?? cleaned(detail.thread.intent.objective)
            ?? "Review the inquiry and decide how to respond."

        let statusLabel = inquiryStatusLabel(inboxItem: inboxItem, secondHalf: secondHalf)
        let factLines = inquiryFactLines(inboxItem: inboxItem, detail: detail)
        let imageURL = inquiryPrimaryImageURL(
            inboxItem: inboxItem,
            detail: detail,
            supplementalProfileImageURLsByNodeID: supplementalProfileImageURLsByNodeID
        )

        let ctaTitle: String
        if secondHalf?.hasProviderReception == true || reception != nil {
            ctaTitle = "Review inquiry"
        } else {
            ctaTitle = "Open thread"
        }

        return SecretaryRecentInquiryCardProjection(
            senderTitle: senderTitle,
            summary: summary,
            statusLabel: statusLabel,
            factLines: factLines,
            primaryImageURL: imageURL,
            ctaTitle: ctaTitle,
            threadID: detail.thread.id
        )
    }

    private static func buildActivityCard(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail,
        sessionKind: SecretaryRecentSessionKind
    ) -> SecretaryRecentActivityCardProjection {
        let secondHalf = SecretaryProjectionEngine.secondHalfDisplay(for: inboxItem)
        let title = cleaned(inboxItem.capturedRequestText)
            ?? cleaned(detail.thread.intent.title)
            ?? SecretaryProjectionEngine.displayTitle(for: inboxItem, surface: "exchange")

        let summary =
            cleaned(inboxItem.visibleSummary)
            ?? cleaned(inboxItem.nextStepText)
            ?? cleaned(secondHalf?.summary)
            ?? cleaned(detail.summary)
            ?? "Open to see the latest coordination on this thread."

        let status: String?
        if inboxItem.hasPendingApproval {
            status = "Needs approval"
        } else if inboxItem.needsClarification {
            status = "Needs your input"
        } else if let secondHalf, secondHalf.canRunAutonomously, !secondHalf.needsHumanAttention {
            status = "In progress"
        } else if SecretaryProjectionEngine.isWaiting(inboxItem) {
            status = "Waiting"
        } else if isSearchInProgress(inboxItem) {
            status = "Searching"
        } else if sessionKind == .activeCoordination {
            status = "Active"
        } else {
            status = cleaned(inboxItem.stateTitle)
        }

        return SecretaryRecentActivityCardProjection(
            title: title,
            summary: summary,
            statusLabel: status,
            ctaTitle: "Open thread",
            threadID: detail.thread.id
        )
    }

    private static func inquiryStatusLabel(
        inboxItem: ExchangeModels.InboxItem,
        secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?
    ) -> String {
        if inboxItem.hasPendingApproval {
            return "Needs review"
        }
        if let secondHalf {
            if secondHalf.hasProviderReception || secondHalf.placement == .providerReception {
                if secondHalf.canRunAutonomously, !secondHalf.needsHumanAttention {
                    return "AI can answer"
                }
                return "Reception"
            }
            if secondHalf.needsHumanAttention {
                return "Needs review"
            }
        }
        if SecretaryProjectionEngine.isWaiting(inboxItem) {
            return "Waiting"
        }
        return "New inquiry"
    }

    private static func inquiryFactLines(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail
    ) -> [String] {
        var lines: [String] = []

        if let offerID = cleaned(inboxItem.selectedOfferID) {
            lines.append("Linked offer")
            _ = offerID
        }
        if let profileID = cleaned(inboxItem.selectedPublicProfileID) {
            lines.append("Linked profile")
            _ = profileID
        }
        if let name = cleaned(inboxItem.selectedCounterpartyName) {
            lines.append("From \(name)")
        }
        if let trust = cleaned(inboxItem.trustPathSummary) {
            lines.append(trust)
        }

        if lines.isEmpty, let match = detail.selectedMatch ?? detail.matches.first {
            if let headline = cleaned(match.recommendation) {
                lines.append(headline)
            }
        }

        return dedupedLines(lines, limit: 3)
    }

    private static func inquiryPrimaryImageURL(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail,
        supplementalProfileImageURLsByNodeID: [String: String]
    ) -> String? {
        if let url = inboxItem.surfaceListImageURLCandidates.compactMap({ cleaned($0) }).first {
            return url
        }
        if let nodeID = cleaned(inboxItem.selectedCounterpartyID) {
            let lowered = nodeID.lowercased()
            if let url = cleaned(supplementalProfileImageURLsByNodeID[nodeID])
                ?? cleaned(supplementalProfileImageURLsByNodeID[lowered]) {
                return url
            }
        }
        if let cp = detail.counterparties.first(where: { $0.id == inboxItem.selectedCounterpartyID }) {
            return cleaned(cp.publicProfile?.primaryImageURL)
        }
        return nil
    }

    private static func primaryTitle(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail,
        sessionKind: SecretaryRecentSessionKind
    ) -> String {
        switch sessionKind {
        case .inboundInquiry:
            return cleaned(inboxItem.cardInboundSenderLabel)
                ?? cleaned(inboxItem.selectedCounterpartyName)
                ?? "New inquiry"
        case .outboundSearch, .noMatch:
            return searchTitle(inboxItem: inboxItem, detail: detail)
        case .activeCoordination, .unknown:
            return cleaned(inboxItem.capturedRequestText)
                ?? cleaned(detail.thread.intent.title)
                ?? SecretaryProjectionEngine.displayTitle(for: inboxItem, surface: "exchange")
        }
    }

    /// Resolved commercial offer anchor for umbrella card preference (canonical anchors before legacy fallback).
    static func effectiveSelectedOfferID(
        for detail: ExchangeModels.ThreadDetail
    ) -> String? {
        resolveUIOfferAnchor(for: detail).offerID
    }

    /// Canonical UI-card offer anchor with diagnostic source (audit / smoke).
    static func resolveUIOfferAnchor(
        for detail: ExchangeModels.ThreadDetail
    ) -> (offerID: String?, source: String) {
        var anchors = ExchangeCanonicalSelectionResolution.anchors(
            from: detail,
            allowChildCoordinationAnchor: true
        )
        anchors.threadSelectedOfferID = detail.selectedOfferID ?? detail.thread.selectedOfferID
        let resolved = ExchangeCanonicalSelectionResolution.resolve(
            anchors: anchors,
            thread: detail.thread,
            matches: detail.matches,
            location: "SecretarySearchResultProjection"
        )
        return (resolved.selectedOfferID, resolved.source.rawValue)
    }

    /// Card projections for hydrated umbrella coordination children (thread detail Results section).
    static func cardProjections(
        from detail: ExchangeModels.ThreadDetail
    ) -> [SecretarySearchResultCardProjection] {
        let preferredOfferID = effectiveSelectedOfferID(for: detail)
        let childCount = detail.coordinationChildren.count
        var cards = detail.coordinationChildren.enumerated().map { index, child in
            cardProjection(
                from: child,
                umbrellaThreadID: detail.compareWorkbenchThreadID,
                rankIndex: index,
                childCount: childCount,
                preferredOfferID: preferredOfferID
            )
        }
        if let preferredOfferID,
           let preferredIndex = cards.firstIndex(where: { $0.offerID == preferredOfferID }),
           preferredIndex > 0 {
            let preferredCard = cards[preferredIndex]
            cards.remove(at: preferredIndex)
            cards.insert(preferredCard, at: 0)
        }
        return cards
    }

    static func cardProjection(
        from child: ExchangeModels.CoordinationChildThreadSummary,
        umbrellaThreadID: ExchangeThread.ID,
        rankIndex: Int,
        childCount: Int,
        preferredOfferID: String? = nil
    ) -> SecretarySearchResultCardProjection {
        let displayName = cleaned(child.displayName) ?? "Result"
        let childOfferID = cleaned(child.offerID)
        let isPreferred: Bool
        if let preferredOfferID, let childOfferID {
            isPreferred = childOfferID == preferredOfferID
        } else {
            isPreferred = rankIndex == 0
        }
        return SecretarySearchResultCardProjection(
            id: child.childThreadID.uuidString,
            displayName: displayName,
            headline: cleaned(child.headline),
            subtitle: cleaned(child.matchSummary),
            primaryImageURL: cleaned(child.primaryImageURL),
            publicSupporterPresentation: nil,
            serviceAreaLine: nil,
            socialTagsLine: nil,
            matchReasonSummary: cleaned(child.matchSummary),
            knownFactLines: [],
            strengthBadge: isPreferred ? "Top match" : nil,
            scoreText: nil,
            isPreferred: isPreferred,
            nodeID: cleaned(child.counterpartyID),
            publicProfileID: cleaned(child.publicProfileID),
            offerID: cleaned(child.offerID),
            linkedThreadID: child.childThreadID,
            umbrellaThreadID: umbrellaThreadID,
            isActivatedCoordinationPath: true,
            hasAnyCoordinationChildren: childCount > 0,
            coordinationChildCount: childCount,
            pathAccess: .exactChild(child.childThreadID),
            primaryCTA: .openPath,
            showsCompareCTA: childCount > 1
        )
    }

    // MARK: - Ranking

    private static func resolveSelectedOfferIDFromMatches(
        detail: ExchangeModels.ThreadDetail
    ) -> String? {
        let sortedMatches = detail.matches.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }
        guard !sortedMatches.isEmpty else { return nil }

        if ExchangeOfferObjectLane.isObjectLaneActive(thread: detail.thread) {
            for match in sortedMatches {
                if let resolved = ExchangeOfferObjectLane.resolveSelectedOfferID(
                    provenObjectOfferIDs: Set(match.provenObjectOfferIDs),
                    objectEvidenceScoreByOfferID: match.objectEvidenceScoreByOfferID
                ) {
                    return resolved
                }
            }
            return nil
        }

        if let primary = cleaned(sortedMatches.first?.offerID) {
            return primary
        }
        return cleaned(sortedMatches.first?.matchedOfferIDs.first)
    }

    private static func rankedMatches(for detail: ExchangeModels.ThreadDetail) -> [ExchangeMatch] {
        let sorted = detail.matches.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .selected
            }
            if lhs.strength != rhs.strength {
                return strengthRank(lhs.strength) > strengthRank(rhs.strength)
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.createdAt > rhs.createdAt
        }

        var seen = Set<ExchangeMatch.ID>()
        return sorted.filter { seen.insert($0.id).inserted }
    }

    private static func strengthRank(_ strength: ExchangeMatch.Strength) -> Int {
        switch strength {
        case .weak: return 1
        case .moderate: return 2
        case .strong: return 3
        }
    }

    private static func isPreferredMatch(
        _ match: ExchangeMatch,
        detail: ExchangeModels.ThreadDetail,
        ranked: [ExchangeMatch]
    ) -> Bool {
        if let anchorOfferID = effectiveSelectedOfferID(for: detail),
           let matchOfferID = cleaned(match.offerID) ?? cleaned(match.matchedOfferIDs.first) {
            if matchOfferID == anchorOfferID { return true }
            if match.matchedOfferIDs.contains(anchorOfferID) { return true }
        }
        if let selected = detail.selectedMatch {
            return match.id == selected.id
        }
        return ranked.first?.id == match.id
    }

    // MARK: - Search result card building

    private static func card(
        for match: ExchangeMatch,
        detail: ExchangeModels.ThreadDetail,
        inboxItem: ExchangeModels.InboxItem,
        rankIndex: Int,
        ranked: [ExchangeMatch],
        supplementalProfileImageURLsByNodeID: [String: String]
    ) -> SecretarySearchResultCardProjection {
        let counterparty = detail.counterparties.first(where: { $0.id == match.counterpartyID })
        let preferred = isPreferredMatch(match, detail: detail, ranked: ranked)

        let displayName = cleaned(
            meta(match, "public_profile_display_name")
                ?? meta(match, "counterparty_name")
                ?? counterparty?.displayName
        ) ?? "Result"

        let headline = cleaned(
            meta(match, "selected_offer_title")
                ?? meta(match, "public_profile_headline")
        )

        let subtitle = cleaned(
            meta(match, "selected_offer_summary")
                ?? meta(match, "public_profile_summary")
                ?? meta(match, "selected_offer_category")
        )

        let imageURL = resolvePrimaryImageURL(
            match: match,
            counterparty: counterparty,
            supplementalProfileImageURLsByNodeID: supplementalProfileImageURLsByNodeID
        )

        let regionLine = cleaned(meta(match, "selected_offer_regions") ?? meta(match, "public_profile_regions"))
        let tagsLine = cleaned(
            meta(match, "selected_offer_tags")
                ?? meta(match, "public_profile_activity_tags")
        )

        let kind = resultKind(for: detail)
        let serviceAreaLine = kind == .commercial ? regionLine : nil
        let socialTagsLine = kind == .social ? tagsLine : nil

        let matchReason = cardSafeMatchReasonSummary(
            for: match,
            kind: kind,
            headline: headline,
            subtitle: subtitle,
            serviceAreaLine: serviceAreaLine,
            socialTagsLine: socialTagsLine
        )

        let facts = knownFactLines(
            for: match,
            kind: kind,
            excludingSubtitle: subtitle
        )

        let childCount = coordinationChildCount(detail: detail, inboxItem: inboxItem)
        let hasAnyChildren = childCount > 0
        let pathAccess = resolvePathAccess(
            for: match,
            detail: detail,
            inboxItem: inboxItem,
            rankIndex: rankIndex
        )
        let isActivated: Bool = {
            if case .exactChild = pathAccess { return true }
            return false
        }()

        let badge = strengthBadge(
            match: match,
            preferred: preferred,
            isActivated: isActivated,
            hasAnyChildren: hasAnyChildren,
            rankIndex: rankIndex
        )

        let fitScoreLabel = String(format: "%.0f%% fit", min(100, max(0, match.score * 100)))
        let scoreText: String? = {
            if isActivated { return nil }
            return shouldShowFitScore(for: match) ? fitScoreLabel : nil
        }()

        let umbrellaThreadID = detail.compareWorkbenchThreadID
        let linkedThreadID: ExchangeThread.ID = {
            switch pathAccess {
            case .exactChild(let childThreadID):
                return childThreadID
            case .umbrellaPaths, .none:
                return umbrellaThreadID
            }
        }()

        let primaryCTA: SecretarySearchResultCTA = {
            switch pathAccess {
            case .exactChild:
                return kind == .social ? .connect : .openPath
            case .umbrellaPaths:
                return kind == .social ? .connect : .openPaths
            case .none:
                return kind == .social ? .connect : .openThread
            }
        }()

        #if DEBUG
        switch pathAccess {
        case .exactChild(let childThreadID):
            Swift.print(
                "[RecentSearchCard] path=exact displayName=\(displayName) " +
                "childThreadID=\(childThreadID.uuidString) umbrellaThreadID=\(umbrellaThreadID.uuidString)"
            )
        case .umbrellaPaths:
            Swift.print(
                "[RecentSearchCard] path=umbrella-fallback displayName=\(displayName) " +
                "childCount=\(childCount) umbrellaThreadID=\(umbrellaThreadID.uuidString)"
            )
        case .none:
            break
        }
        #endif

        return SecretarySearchResultCardProjection(
            id: match.id.uuidString,
            displayName: displayName,
            headline: headline,
            subtitle: subtitle,
            primaryImageURL: imageURL,
            publicSupporterPresentation: counterparty?.publicProfile?.publicSupporterPresentation,
            serviceAreaLine: serviceAreaLine,
            socialTagsLine: socialTagsLine,
            matchReasonSummary: matchReason,
            knownFactLines: facts,
            strengthBadge: badge,
            scoreText: scoreText,
            isPreferred: preferred || isActivated,
            nodeID: match.counterpartyID,
            publicProfileID: match.publicProfileID,
            offerID: match.offerID,
            linkedThreadID: linkedThreadID,
            umbrellaThreadID: umbrellaThreadID,
            isActivatedCoordinationPath: isActivated,
            hasAnyCoordinationChildren: hasAnyChildren,
            coordinationChildCount: childCount,
            pathAccess: pathAccess,
            primaryCTA: primaryCTA,
            showsCompareCTA: ranked.count > 1
        )
    }

    private static func coordinationChildCount(
        detail: ExchangeModels.ThreadDetail,
        inboxItem: ExchangeModels.InboxItem
    ) -> Int {
        max(detail.coordinationChildren.count, inboxItem.coordinationChildThreadIDs.count)
    }

    private static func resolvePathAccess(
        for match: ExchangeMatch,
        detail: ExchangeModels.ThreadDetail,
        inboxItem: ExchangeModels.InboxItem,
        rankIndex: Int
    ) -> SecretarySearchResultPathAccess {
        let umbrellaThreadID = detail.compareWorkbenchThreadID
        if let child = activatedCoordinationChild(
            for: match,
            detail: detail,
            rankIndex: rankIndex,
            displayName: cardDisplayName(for: match, detail: detail)
        ) {
            return .exactChild(child.childThreadID)
        }
        if coordinationChildCount(detail: detail, inboxItem: inboxItem) > 0 {
            return .umbrellaPaths(umbrellaThreadID: umbrellaThreadID)
        }
        return .none
    }

    private static func cardDisplayName(
        for match: ExchangeMatch,
        detail: ExchangeModels.ThreadDetail
    ) -> String {
        let counterparty = detail.counterparties.first(where: { $0.id == match.counterpartyID })
        return cleaned(
            meta(match, "public_profile_display_name")
                ?? meta(match, "counterparty_name")
                ?? counterparty?.displayName
        ) ?? "Result"
    }

    private static func activatedCoordinationChild(
        for match: ExchangeMatch,
        detail: ExchangeModels.ThreadDetail,
        rankIndex: Int,
        displayName: String
    ) -> ExchangeModels.CoordinationChildThreadSummary? {
        let children = detail.coordinationChildren
        guard !children.isEmpty else { return nil }

        if let child = children.first(where: { $0.sourceMatchID == match.id }) {
            return child
        }

        let counterpartyMatches = children.filter {
            childMatchesCounterparty($0, counterpartyID: match.counterpartyID)
        }
        if counterpartyMatches.count == 1 {
            return counterpartyMatches[0]
        }

        let profileID = match.publicProfileID ?? meta(match, "public_profile_id")
        let profileMatches = children.filter {
            childMatchesProfile($0, profileID: profileID)
        }
        if profileMatches.count == 1 {
            return profileMatches[0]
        }

        let offerID = match.offerID ?? meta(match, "selected_offer_id")
        let offerMatches = children.filter {
            childMatchesOffer($0, offerID: offerID)
        }
        if offerMatches.count == 1 {
            return offerMatches[0]
        }

        let metaCounterpartyID = meta(match, "counterparty_id")
        if let metaCounterpartyID {
            let metaCounterpartyMatches = children.filter {
                childMatchesCounterparty($0, counterpartyID: metaCounterpartyID)
            }
            if metaCounterpartyMatches.count == 1 {
                return metaCounterpartyMatches[0]
            }
        }

        let expectedRank = rankIndex + 1
        let rankMatches = children.filter { $0.sourceRank == expectedRank }
        if rankMatches.count == 1 {
            return rankMatches[0]
        }

        if let displayToken = normalizedToken(displayName), displayToken != "result" {
            let nameMatches = children.filter { child in
                guard let childName = childDisplayName(child, detail: detail) else { return false }
                return normalizedToken(childName) == displayToken
            }
            if nameMatches.count == 1 {
                return nameMatches[0]
            }
        }

        if children.count == 1, rankIndex == 0 {
            return children[0]
        }

        return nil
    }

    private static func childDisplayName(
        _ child: ExchangeModels.CoordinationChildThreadSummary,
        detail: ExchangeModels.ThreadDetail
    ) -> String? {
        detail.counterparties.first(where: { $0.id == child.counterpartyID })?.displayName
    }

    private static func normalizedToken(_ raw: String?) -> String? {
        cleaned(raw)?.lowercased()
    }

    private static func childMatchesCounterparty(
        _ child: ExchangeModels.CoordinationChildThreadSummary,
        counterpartyID: String?
    ) -> Bool {
        guard let token = normalizedToken(counterpartyID), !token.isEmpty else { return false }
        return normalizedToken(child.counterpartyID) == token
    }

    private static func childMatchesProfile(
        _ child: ExchangeModels.CoordinationChildThreadSummary,
        profileID: String?
    ) -> Bool {
        guard let token = normalizedToken(profileID), !token.isEmpty else { return false }
        return normalizedToken(child.publicProfileID) == token
    }

    private static func childMatchesOffer(
        _ child: ExchangeModels.CoordinationChildThreadSummary,
        offerID: String?
    ) -> Bool {
        guard let token = normalizedToken(offerID), !token.isEmpty else { return false }
        return normalizedToken(child.offerID) == token
    }

    /// Recent cards only: neutral copy from public profile/offer metadata — never fit-engine recommendation or reasons.
    private static func cardSafeMatchReasonSummary(
        for match: ExchangeMatch,
        kind: SecretarySearchResultKind,
        headline: String?,
        subtitle: String?,
        serviceAreaLine: String?,
        socialTagsLine: String?
    ) -> String? {
        let hasOfferEvidence =
            cleaned(meta(match, "selected_offer_title")) != nil
            || cleaned(meta(match, "selected_offer_summary")) != nil
            || cleaned(meta(match, "selected_offer_category")) != nil
        let hasProfileText =
            cleaned(meta(match, "public_profile_summary")) != nil
            || cleaned(meta(match, "public_profile_headline")) != nil
            || headline != nil
            || subtitle != nil
        let hasProfileFacts =
            cleaned(meta(match, "public_profile_open_to")) != nil
            || cleaned(meta(match, "public_profile_interests")) != nil
            || cleaned(meta(match, "public_profile_regions")) != nil
            || serviceAreaLine != nil
            || socialTagsLine != nil

        let hasSubstantiveEvidence = hasOfferEvidence || hasProfileText || hasProfileFacts

        if match.strength == .weak || match.score < 0.65 {
            return nil
        }

        if !hasSubstantiveEvidence {
            return "Matched your search request."
        }

        if hasOfferEvidence && (hasProfileText || hasProfileFacts) {
            return "Profile and offer details matched your request."
        }
        if hasOfferEvidence {
            return "Matched your search request."
        }
        _ = kind
        return "This result matched available public information."
    }

    private static func shouldShowFitScore(for match: ExchangeMatch) -> Bool {
        match.strength == .strong || match.score >= 0.65
    }

    private static func knownFactLines(
        for match: ExchangeMatch,
        kind: SecretarySearchResultKind,
        excludingSubtitle: String?
    ) -> [String] {
        var lines: [String] = []

        if let summary = cleaned(meta(match, "selected_offer_summary") ?? meta(match, "public_profile_summary")),
           !linesEquivalent(summary, excludingSubtitle) {
            lines.append(summary)
        }

        if kind == .commercial, let regions = cleaned(meta(match, "selected_offer_regions")) {
            lines.append("Area: \(regions)")
        }

        if kind == .social {
            if let openTo = cleaned(meta(match, "public_profile_open_to")) {
                lines.append("Open to: \(openTo)")
            }
            if let interests = cleaned(meta(match, "public_profile_interests")) {
                lines.append("Interests: \(interests)")
            }
        }

        return dedupedLines(lines, limit: 4)
    }

    private static func linesEquivalent(_ lhs: String, _ rhs: String?) -> Bool {
        guard let rhs = cleaned(rhs) else { return false }
        return lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func strengthBadge(
        match: ExchangeMatch,
        preferred: Bool,
        isActivated: Bool,
        hasAnyChildren: Bool,
        rankIndex: Int
    ) -> String? {
        if isActivated {
            return String(format: "%.0f%% fit", min(100, max(0, match.score * 100)))
        }
        if hasAnyChildren { return "Paths available" }
        if preferred { return "Best match" }
        switch match.strength {
        case .strong:
            return "Strong match"
        case .moderate:
            return rankIndex == 0 ? "Top match" : "Good match"
        case .weak:
            return "Possible match"
        }
    }

    private static func resolvePrimaryImageURL(
        match: ExchangeMatch,
        counterparty: ExchangeCounterparty?,
        supplementalProfileImageURLsByNodeID: [String: String]
    ) -> String? {
        if let profileURL = cleaned(counterparty?.publicProfile?.primaryImageURL) {
            return profileURL
        }

        guard let nodeID = cleaned(match.counterpartyID) else { return nil }
        let lowered = nodeID.lowercased()
        if let url = cleaned(supplementalProfileImageURLsByNodeID[nodeID]) {
            return url
        }
        if let url = cleaned(supplementalProfileImageURLsByNodeID[lowered]) {
            return url
        }
        return nil
    }

    // MARK: - Session copy

    private static func searchTitle(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail
    ) -> String {
        if let captured = cleaned(inboxItem.capturedRequestText) {
            return captured
        }
        if let objective = cleaned(detail.thread.intent.objective) {
            return objective
        }
        return SecretaryProjectionEngine.displayTitle(for: inboxItem, surface: "exchange")
    }

    private static func statusLine(
        inboxItem: ExchangeModels.InboxItem,
        detail: ExchangeModels.ThreadDetail,
        resultCount: Int
    ) -> String? {
        if isNoMatchState(inboxItem.state) {
            return "No strong matches from the last search."
        }
        if case .matchCandidatesWeak = inboxItem.state {
            if resultCount == 0 {
                return "Matches are tentative — review before outreach."
            }
            if let grade = inboxItem.discoveryProjectedGrade, grade != .weak {
                let resolution = ExchangeUmbrellaDiscoveryGradeProjection.resolve(thread: detail.thread)
                return ExchangeUmbrellaDiscoveryGradeProjection.searchResultBoundaryLine(for: resolution)
                    ?? "Matches are tentative — review before outreach."
            }
            return "Matches are tentative — review before outreach."
        }
        if case .matchFound = inboxItem.state {
            if !SecretaryProjectionEngine.hasSummaryDiscoveryResultEvidence(for: inboxItem) || resultCount == 0 {
                return "No strong matches from the last search."
            }
        }
        if resultCount == 0 {
            return nil
        }
        if let summary = cleaned(detail.summary),
           !summary.isEmpty,
           !isDiscoverySystemSummary(summary) {
            return summary
        }
        switch inboxItem.state {
        case .matchFound:
            return "Matches ranked from your latest search."
        default:
            return nil
        }
    }

    private static func isDiscoverySystemSummary(_ raw: String) -> Bool {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if lower.contains("provider-facing") { return true }
        if lower.hasPrefix("i found") && lower.contains("public surfaces") { return true }
        if lower.contains("public surfaces with") { return true }
        if lower.contains("capability-oriented public surfaces") { return true }
        if lower.contains("affinity-oriented public surfaces") { return true }
        return false
    }

    /// In-flight discover/search — empty matches must not surface as completed no-match recovery.
    static func isSearchInProgress(_ item: ExchangeModels.InboxItem) -> Bool {
        switch item.state {
        case .searching:
            return true
        case .drafting, .draftReady:
            return item.shouldDiscover
        default:
            return false
        }
    }

    private static func isNoMatchState(_ state: ExchangeState) -> Bool {
        if case .noViableMatch = state { return true }
        return false
    }

    private static func resultKind(for detail: ExchangeModels.ThreadDetail) -> SecretarySearchResultKind {
        if SecretaryProjectionEngine.isSocialConnectionThread(detail) {
            return .social
        }
        switch detail.thread.intent.queryIntentClass {
        case .socialAffinitySearch, .relationshipSearch:
            return .social
        case .providerSearch, .offerSearch:
            return .commercial
        default:
            let lane = ExchangeThreadLaneResolver.lane(for: detail.thread)
            switch lane {
            case .socialConnection:
                return .social
            case .commercialInquiry:
                return .commercial
            default:
                return .unknown
            }
        }
    }

    private static func recoverySuggestions(
        for detail: ExchangeModels.ThreadDetail,
        inboxItem: ExchangeModels.InboxItem
    ) -> [String] {
        var suggestions: [String] = [
            "Widen the area or relax locality requirements.",
            "Refine search terms to be more specific.",
            "Try again later as more public surfaces publish."
        ]

        if !detail.semanticTags.isEmpty {
            suggestions.append("Adjust tags: \(detail.semanticTags.prefix(4).joined(separator: ", ")).")
        }

        if inboxItem.candidateCount > 0 {
            suggestions.insert("Review alternate headlines that were considered.", at: 1)
        }

        return suggestions
    }

    // MARK: - Metadata helpers

    private static func meta(_ match: ExchangeMatch, _ key: String) -> String? {
        cleaned(match.metadata[key])
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func dedupedLines(_ lines: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for line in lines {
            let key = line.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(line)
            if output.count >= limit { break }
        }
        return output
    }
}
