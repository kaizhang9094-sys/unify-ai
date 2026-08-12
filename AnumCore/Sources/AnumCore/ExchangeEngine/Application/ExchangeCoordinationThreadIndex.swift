import Foundation

/// In-memory index of umbrella ↔ child coordination threads for list/detail projection.
struct ExchangeCoordinationThreadIndex: Sendable {
    private var childrenByParentID: [ExchangeThread.ID: [ExchangeThread]]
    private var childrenByRootID: [ExchangeThread.ID: [ExchangeThread]]

    init(threads: [ExchangeThread]) {
        var byParent: [ExchangeThread.ID: [ExchangeThread]] = [:]
        var byRoot: [ExchangeThread.ID: [ExchangeThread]] = [:]
        byParent.reserveCapacity(8)
        byRoot.reserveCapacity(8)

        for thread in threads {
            let hasCoordinationMetadata = Self.hasCoordinationLookingMetadata(thread.metadata)
            #if DEBUG
            if hasCoordinationMetadata || thread.threadRole != .standalone {
                let rawRole = thread.metadata[ExchangeThreadRoleResolver.threadRoleMetadataKey] ?? "nil"
                let inclusion: String
                if thread.threadRole != .candidateCoordination {
                    inclusion = "excluded reason=not_candidateCoordination"
                } else if thread.isArchived {
                    inclusion = "excluded reason=archived"
                } else {
                    inclusion = "included"
                }
                if ExchangeDebugProjectionLogDedupe.shouldLogCoordinationThreadIndex(
                    threadID: thread.id.uuidString,
                    rawRole: rawRole,
                    parsedRole: thread.threadRole.rawValue,
                    parentThreadID: thread.parentThreadID?.uuidString,
                    rootThreadID: thread.rootThreadID?.uuidString,
                    archived: thread.isArchived,
                    inclusion: inclusion
                ) {
                    Swift.print(
                        "[ExchangeCoordinationThreadIndex] candidate " +
                        "threadID=\(thread.id.uuidString) " +
                        "rawRole=\(rawRole) " +
                        "parsedRole=\(thread.threadRole.rawValue) " +
                        "parentThreadID=\(thread.parentThreadID?.uuidString ?? "nil") " +
                        "rootThreadID=\(thread.rootThreadID?.uuidString ?? "nil") " +
                        "archived=\(thread.isArchived) " +
                        inclusion
                    )
                }
            }
            #endif

            guard thread.threadRole == .candidateCoordination, !thread.isArchived else {
                continue
            }
            if let parentThreadID = thread.parentThreadID {
                byParent[parentThreadID, default: []].append(thread)
            }
            if let rootThreadID = thread.rootThreadID {
                byRoot[rootThreadID, default: []].append(thread)
            }
        }

        for parentID in byParent.keys {
            byParent[parentID] = Self.sortedChildren(byParent[parentID] ?? [])
        }
        for rootID in byRoot.keys {
            byRoot[rootID] = Self.sortedChildren(byRoot[rootID] ?? [])
        }

        childrenByParentID = byParent
        childrenByRootID = byRoot
    }

    func childThreadIDs(
        forWorkbench workbenchID: ExchangeThread.ID,
        rootThreadID: ExchangeThread.ID? = nil
    ) -> [ExchangeThread.ID] {
        resolvedChildren(forWorkbench: workbenchID, rootThreadID: rootThreadID).map(\.id)
    }

    func childSummaries(
        forWorkbench workbenchID: ExchangeThread.ID,
        rootThreadID: ExchangeThread.ID? = nil
    ) -> [ExchangeModels.CoordinationChildThreadSummary] {
        resolvedChildren(forWorkbench: workbenchID, rootThreadID: rootThreadID).map(Self.summary(for:))
    }

    func childCount(
        forWorkbench workbenchID: ExchangeThread.ID,
        rootThreadID: ExchangeThread.ID? = nil
    ) -> Int {
        resolvedChildren(forWorkbench: workbenchID, rootThreadID: rootThreadID).count
    }

    func childThreadIDs(parentID: ExchangeThread.ID) -> [ExchangeThread.ID] {
        childThreadIDs(forWorkbench: parentID, rootThreadID: nil)
    }

    func childSummaries(parentID: ExchangeThread.ID) -> [ExchangeModels.CoordinationChildThreadSummary] {
        childSummaries(forWorkbench: parentID, rootThreadID: nil)
    }

    func activatedChild(
        parentID: ExchangeThread.ID,
        sourceMatchID: ExchangeMatch.ID?,
        counterpartyID: ExchangeCounterparty.ID
    ) -> ExchangeModels.CoordinationChildThreadSummary? {
        guard let thread = existingChildThread(
            parentID: parentID,
            sourceMatchID: sourceMatchID,
            counterpartyID: counterpartyID
        ) else {
            return nil
        }
        return Self.summary(for: thread)
    }

    func childCount(parentID: ExchangeThread.ID) -> Int {
        childCount(forWorkbench: parentID, rootThreadID: nil)
    }

    /// Best activated child: lowest `sourceRank`, then newest `updatedAt`.
    func bestChildThread(
        forWorkbench workbenchID: ExchangeThread.ID,
        rootThreadID: ExchangeThread.ID? = nil
    ) -> ExchangeThread? {
        resolvedChildren(forWorkbench: workbenchID, rootThreadID: rootThreadID).first
    }

    func coordinationChildThreads(
        forWorkbench workbenchID: ExchangeThread.ID,
        rootThreadID: ExchangeThread.ID? = nil
    ) -> [ExchangeThread] {
        resolvedChildren(forWorkbench: workbenchID, rootThreadID: rootThreadID)
    }

    private func resolvedChildren(
        forWorkbench workbenchID: ExchangeThread.ID,
        rootThreadID: ExchangeThread.ID?
    ) -> [ExchangeThread] {
        let byParent = childrenByParentID[workbenchID] ?? []
        if !byParent.isEmpty {
            return byParent
        }
        let rootID = rootThreadID ?? workbenchID
        return childrenByRootID[rootID] ?? []
    }

    /// Resolves an existing candidate-coordination child under `parentID`.
    /// Prefers `sourceMatchID`, then falls back to `counterpartyID`.
    func existingChildThread(
        parentID: ExchangeThread.ID,
        sourceMatchID: ExchangeMatch.ID?,
        counterpartyID: ExchangeCounterparty.ID
    ) -> ExchangeThread? {
        let children = childrenByParentID[parentID] ?? []
        if let sourceMatchID,
           let match = children.first(where: { $0.sourceMatchID == sourceMatchID }) {
            return match
        }
        let trimmedCounterpartyID = counterpartyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCounterpartyID.isEmpty else { return nil }
        return children.first {
            ($0.selectedCounterpartyID ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines) == trimmedCounterpartyID
        }
    }

    private static func sortedChildren(_ children: [ExchangeThread]) -> [ExchangeThread] {
        children.sorted { lhs, rhs in
            let leftRank = lhs.sourceRank ?? Int.max
            let rightRank = rhs.sourceRank ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static func hasCoordinationLookingMetadata(_ metadata: [String: String]) -> Bool {
        let keys = [
            ExchangeThreadRoleResolver.threadRoleMetadataKey,
            ExchangeThreadRoleResolver.parentThreadIDMetadataKey,
            ExchangeThreadRoleResolver.rootThreadIDMetadataKey,
            ExchangeThreadRoleResolver.sourceMatchIDMetadataKey,
            ExchangeThreadRoleResolver.sourceRankMetadataKey,
        ]
        return keys.contains { metadata[$0]?.isEmpty == false }
    }

    private static func summary(
        for thread: ExchangeThread
    ) -> ExchangeModels.CoordinationChildThreadSummary {
        structuralSummary(for: thread)
    }

    static func structuralSummary(
        for thread: ExchangeThread
    ) -> ExchangeModels.CoordinationChildThreadSummary {
        deskListSummary(for: thread)
    }

    /// Structural path row for desk snapshot / History list (thread store fields only).
    static func deskListSummary(for thread: ExchangeThread) -> ExchangeModels.CoordinationChildThreadSummary {
        let titleRaw = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = titleRaw.isEmpty ? nil : titleRaw
        let hasPendingApproval = thread.approval?.status == .pending
            || {
                if case .awaitingApproval = thread.state { return true }
                return false
            }()

        return ExchangeModels.CoordinationChildThreadSummary(
            childThreadID: thread.id,
            parentThreadID: thread.parentThreadID ?? thread.id,
            rootThreadID: thread.rootThreadID ?? thread.parentThreadID ?? thread.id,
            sourceMatchID: thread.sourceMatchID,
            sourceRank: thread.sourceRank,
            counterpartyID: thread.selectedCounterpartyID ?? "",
            publicProfileID: thread.selectedPublicProfileID,
            offerID: thread.selectedOfferID,
            displayName: title,
            childState: thread.state,
            stateTitle: thread.state.phaseTitle,
            updatedAt: thread.updatedAt,
            requiresHumanDecision: thread.requiresHumanDecision || hasPendingApproval,
            hasPendingApproval: hasPendingApproval,
            hasFailure: thread.hasFailure,
            awaitingReply: {
                if case .awaitingResponse = thread.state { return true }
                return false
            }()
        )
    }
}

enum ExchangeCoordinationProjection {
    static func applyListFields(
        to inboxItem: inout ExchangeModels.InboxItem,
        thread: ExchangeThread,
        index: ExchangeCoordinationThreadIndex
    ) {
        inboxItem.threadRole = thread.threadRole
        inboxItem.parentThreadID = thread.parentThreadID
        inboxItem.rootThreadID = thread.rootThreadID
        inboxItem.sourceMatchID = thread.sourceMatchID
        inboxItem.sourceRank = thread.sourceRank

        if thread.threadRole == .candidateCoordination {
            inboxItem.coordinationChildThreadIDs = []
        } else {
            inboxItem.coordinationChildThreadIDs = index.childThreadIDs(
                forWorkbench: thread.id,
                rootThreadID: thread.rootThreadID ?? thread.id
            )
        }

        #if DEBUG
        let gradeSnapshot = ExchangeThreadDiscoveryGradeMetadata.snapshot(from: thread.metadata)
        Swift.print(
            "[ExchangeCoordinationProjection] applyListFields " +
            "threadID=\(thread.id.uuidString) " +
            "rawRole=\(thread.metadata[ExchangeThreadRoleResolver.threadRoleMetadataKey] ?? "nil") " +
            "resolvedRole=\(thread.threadRole.rawValue) " +
            "rawParentID=\(thread.metadata[ExchangeThreadRoleResolver.parentThreadIDMetadataKey] ?? "nil") " +
            "rawRootID=\(thread.metadata[ExchangeThreadRoleResolver.rootThreadIDMetadataKey] ?? "nil") " +
            "coordinationChildThreadIDs.count=\(inboxItem.coordinationChildThreadIDs.count) " +
            "discovery_projected_grade=\(gradeSnapshot.projectedGrade?.rawValue ?? "nil") " +
            "discovery_classify_grade=\(gradeSnapshot.classifyGrade?.rawValue ?? "nil")"
        )
        #endif
    }
}
