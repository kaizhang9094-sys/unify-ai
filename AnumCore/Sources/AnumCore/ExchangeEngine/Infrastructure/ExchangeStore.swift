import Foundation

/// Persistence boundary for Exchange.
///
/// The store owns durable thread state and related domain records.
/// Keep this protocol stable and business-oriented. Do not leak SQL concerns here.
///
/// Canonical framing:
/// - thread = request-side coordination object
/// - counterparty = durable external entity / participant record
/// - public profile = seller-facing / outward-facing published surface
/// - offer = concrete published or draft offering attached to a public profile
///
/// Seller publication note:
/// publication state is now a first-class durable model.
/// It tracks:
/// - draft / pending publish / published / stale
/// - paused / pending unpublish / archived / failed
/// - whether the local surface is dirty
/// - when local mutation happened
/// - last successful remote projection identifiers
/// - optional last published fingerprint
public protocol ExchangeStore: Sendable {
    // MARK: - Threads

    func createThread(_ thread: ExchangeThread) async throws
    func updateThread(_ thread: ExchangeThread) async throws
    func fetchThread(id: ExchangeThread.ID) async throws -> ExchangeThread?
    /// Bounded lookup for canonical DM containers (uses `selected_counterparty_id` index, not global desk list).
    func listDirectMessageThreadCandidates(
        counterpartyNodeID: String,
        limit: Int
    ) async throws -> [ExchangeThread]
    func listThreads(filter: ExchangeThreadFilter) async throws -> [ExchangeThread]

    /// Hard-deletes all local Exchange rows scoped to one thread. Does not delete remote relay data.
    /// Returns `nil` when the thread id is not present (idempotent no-op).
    func hardDeleteThreadLocally(id: ExchangeThread.ID) async throws -> ExchangeThreadLocalDeleteReport?

    // MARK: - Turns

    func appendTurn(_ turn: ExchangeTurn) async throws
    func listTurns(
        threadID: ExchangeThread.ID,
        limit: Int?,
        ascending: Bool
    ) async throws -> [ExchangeTurn]

    // MARK: - Approvals

    func saveApproval(_ approval: ExchangeApproval) async throws
    func fetchApproval(id: ExchangeApproval.ID) async throws -> ExchangeApproval?
    func fetchLatestApproval(threadID: ExchangeThread.ID) async throws -> ExchangeApproval?
    /// Latest approval row per thread where status is pending (desk snapshot fast path).
    func listLatestPendingApprovals() async throws -> [ExchangeApproval]

    // MARK: - Drafts

    func saveDraft(_ draft: ExchangeMessageDraft) async throws
    func fetchDraft(id: ExchangeMessageDraft.ID) async throws -> ExchangeMessageDraft?
    func listDrafts(threadID: ExchangeThread.ID) async throws -> [ExchangeMessageDraft]

    // MARK: - Outcomes

    func saveOutcome(_ outcome: ExchangeOutcome) async throws
    func fetchLatestOutcome(threadID: ExchangeThread.ID) async throws -> ExchangeOutcome?

    // MARK: - Discovery / counterparties

    func upsertCounterparties(_ counterparties: [ExchangeCounterparty]) async throws
    func fetchCounterparty(id: ExchangeCounterparty.ID) async throws -> ExchangeCounterparty?
    func listCounterparties(filter: ExchangeCounterpartyFilter) async throws -> [ExchangeCounterparty]

    func saveMatches(_ matches: [ExchangeMatch]) async throws
    func listMatches(
        threadID: ExchangeThread.ID,
        status: ExchangeMatch.Status?
    ) async throws -> [ExchangeMatch]

    // MARK: - Seller public surfaces

    func savePublicProfile(_ profile: ExchangePublicNodeProfile) async throws
    func savePublicProfiles(_ profiles: [ExchangePublicNodeProfile]) async throws
    func fetchPublicProfile(id: ExchangePublicNodeProfile.ID) async throws -> ExchangePublicNodeProfile?
    func listPublicProfiles(filter: ExchangePublicProfileFilter) async throws -> [ExchangePublicNodeProfile]

    func savePublicationState(
        _ state: ExchangePublicationState,
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID
    ) async throws
    func fetchPublicationState(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID
    ) async throws -> ExchangePublicationState?

    // MARK: - Seller offers

    func saveOffer(_ offer: ExchangeOffer) async throws
    func saveOffers(_ offers: [ExchangeOffer]) async throws
    func fetchOffer(id: ExchangeOffer.ID) async throws -> ExchangeOffer?
    func listOffers(filter: ExchangeOfferFilter) async throws -> [ExchangeOffer]

    // MARK: - Artifacts

    func saveArtifact(_ artifact: ExchangeArtifact) async throws
    func listArtifacts(threadID: ExchangeThread.ID) async throws -> [ExchangeArtifact]

    // MARK: - Trust graph

    func saveTrustEdge(_ edge: ExchangeTrustEdge) async throws
    func fetchTrustEdge(id: ExchangeTrustEdge.ID) async throws -> ExchangeTrustEdge?
    func fetchTrustEdge(
        sourceNodeID: String,
        targetNodeID: String
    ) async throws -> ExchangeTrustEdge?
    func listTrustEdges(filter: ExchangeTrustEdgeFilter) async throws -> [ExchangeTrustEdge]

    func appendTrustEvidence(_ evidence: ExchangeTrustEvidence) async throws
    func listTrustEvidence(
        trustEdgeID: ExchangeTrustEdge.ID,
        limit: Int?,
        ascending: Bool
    ) async throws -> [ExchangeTrustEvidence]

    func fetchTrustedNodeProfile(
        nodeID: String,
        forSourceNodeID sourceNodeID: String?
    ) async throws -> ExchangeTrustedNodeProfile?

    // MARK: - Federation outbox

    func saveOutboxItem(_ item: ExchangeOutboxItem) async throws
    func fetchOutboxItem(id: ExchangeOutboxItem.ID) async throws -> ExchangeOutboxItem?
    func fetchOutboxItemByEnvelopeID(_ envelopeID: String) async throws -> ExchangeOutboxItem?
    func listOutboxItems(filter: ExchangeOutboxFilter) async throws -> [ExchangeOutboxItem]

    // MARK: - Federation inbox

    func saveInboxItem(_ item: ExchangeInboxItem) async throws
    func fetchInboxItem(id: ExchangeInboxItem.ID) async throws -> ExchangeInboxItem?
    func fetchInboxItemByEnvelopeID(_ envelopeID: String) async throws -> ExchangeInboxItem?
    func listInboxItems(filter: ExchangeInboxFilter) async throws -> [ExchangeInboxItem]

    // MARK: - Federation audit

    func appendAuditRecord(_ record: ExchangeAuditRecord) async throws
    func listAuditRecords(filter: ExchangeAuditFilter) async throws -> [ExchangeAuditRecord]

    // MARK: - Secretary notifications (local attention center)

    func upsertSecretaryNotification(_ notification: SecretaryNotification) async throws

    func listSecretaryNotifications(
        filter: ExchangeSecretaryNotificationFilter
    ) async throws -> [SecretaryNotification]

    func countUnreadSecretaryNotifications(
        excludingPriorityLow: Bool,
        excludedKinds: Set<SecretaryNotificationKind>?
    ) async throws -> Int

    func markSecretaryNotificationsRead(ids: Set<SecretaryNotification.ID>) async throws

    func markSecretaryNotificationsUnread(ids: Set<SecretaryNotification.ID>) async throws

    func markSecretaryNotificationsReadForThread(
        threadID: ExchangeThread.ID,
        kinds: Set<SecretaryNotificationKind>?
    ) async throws

    func markSecretaryNotificationsReadWhereApproval(
        approvalID: ExchangeApproval.ID
    ) async throws

    func markSecretaryNotificationsReadWhereFailure(
        failureID: ExchangeFailure.ID
    ) async throws

    func markSecretaryNotificationsReadWhereTrustedNode(
        nodeID: String
    ) async throws

    // MARK: - Contact signal outbound (friend request lane)

    func saveOutgoingContactRequest(_ request: OutgoingContactRequest) async throws
    func fetchOutgoingContactRequest(id: OutgoingContactRequest.ID) async throws -> OutgoingContactRequest?
    func fetchPendingOutgoingContactRequest(targetNodeID: String) async throws -> OutgoingContactRequest?
    func listOutgoingContactRequests(filter: OutgoingContactRequestFilter) async throws -> [OutgoingContactRequest]
    /// Marks all pending outgoing contact requests to `targetNodeID` as `.accepted`.
    func markOutgoingContactRequestsAcceptedForTarget(
        targetNodeID: String,
        now: Date
    ) async throws -> Int

    // MARK: - Transaction boundary

    func performTransaction<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T
}

public struct ExchangeSecretaryNotificationFilter: Sendable, Hashable {
    public var unreadOnly: Bool
    public var kinds: Set<SecretaryNotificationKind>?
    /// When non-empty, matching kinds are excluded from results (`AND kind NOT IN (...)`).
    public var excludedKinds: Set<SecretaryNotificationKind>?
    /// When true, rows with `.low` priority are excluded from results.
    public var excludingPriorityLow: Bool
    public var limit: Int?

    public init(
        unreadOnly: Bool = false,
        kinds: Set<SecretaryNotificationKind>? = nil,
        excludedKinds: Set<SecretaryNotificationKind>? = nil,
        excludingPriorityLow: Bool = false,
        limit: Int? = nil
    ) {
        self.unreadOnly = unreadOnly
        self.kinds = kinds
        self.excludedKinds = excludedKinds
        self.excludingPriorityLow = excludingPriorityLow
        self.limit = limit
    }
}

/// Controls how much work ``ExchangeFacade/getThread(threadID:hydrationMode:)`` performs.
public enum ExchangeThreadHydrationMode: String, Sendable, Equatable {
    /// Full exchange desk detail (second-half, coordination index, opportunity surface).
    case full
    /// Direct-message transcript surface only (no global thread index scan).
    case directMessage
}

public struct ExchangeThreadFilter: Sendable, Hashable {
    public var states: Set<ExchangeTransition.ExchangeStateKey>?
    public var requiresHumanDecisionOnly: Bool
    public var updatedAfter: Date?
    public var updatedBefore: Date?
    public var limit: Int?

    public init(
        states: Set<ExchangeTransition.ExchangeStateKey>? = nil,
        requiresHumanDecisionOnly: Bool = false,
        updatedAfter: Date? = nil,
        updatedBefore: Date? = nil,
        limit: Int? = nil
    ) {
        self.states = states
        self.requiresHumanDecisionOnly = requiresHumanDecisionOnly
        self.updatedAfter = updatedAfter
        self.updatedBefore = updatedBefore
        self.limit = limit
    }
}

public struct ExchangeCounterpartyFilter: Sendable, Hashable {
    public var tags: Set<String>
    public var status: Set<ExchangeCounterparty.Status>?
    public var trustLevels: Set<ExchangeCounterparty.TrustSnapshot.Level>?
    public var searchText: String?
    public var limit: Int?

    public init(
        tags: Set<String> = [],
        status: Set<ExchangeCounterparty.Status>? = nil,
        trustLevels: Set<ExchangeCounterparty.TrustSnapshot.Level>? = nil,
        searchText: String? = nil,
        limit: Int? = nil
    ) {
        self.tags = Set(
            tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        self.status = status
        self.trustLevels = trustLevels
        self.searchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.limit = limit
    }
}

public struct ExchangePublicProfileFilter: Sendable, Hashable {
    public var nodeID: String?
    public var counterpartyID: ExchangeCounterparty.ID?
    public var visibility: Set<ExchangePublicNodeProfile.Visibility>?
    public var availability: Set<ExchangePublicNodeProfile.Availability>?
    public var searchText: String?
    public var regionTags: Set<String>
    public var activityTags: Set<String>
    public var limit: Int?

    public init(
        nodeID: String? = nil,
        counterpartyID: ExchangeCounterparty.ID? = nil,
        visibility: Set<ExchangePublicNodeProfile.Visibility>? = nil,
        availability: Set<ExchangePublicNodeProfile.Availability>? = nil,
        searchText: String? = nil,
        regionTags: Set<String> = [],
        activityTags: Set<String> = [],
        limit: Int? = nil
    ) {
        self.nodeID = nodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.counterpartyID = counterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.visibility = visibility
        self.availability = availability
        self.searchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.regionTags = Set(
            regionTags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        self.activityTags = Set(
            activityTags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        self.limit = limit
    }
}

public struct ExchangeOfferFilter: Sendable, Hashable {
    public var nodeID: String?
    public var publicProfileID: String?
    public var statuses: Set<ExchangeOffer.Status>?
    public var visibility: Set<ExchangeOffer.Visibility>?
    public var categories: Set<String>
    public var fulfillmentModes: Set<ExchangeOffer.SemanticSurface.FulfillmentMode>?
    public var searchText: String?
    public var updatedAfter: Date?
    public var updatedBefore: Date?
    public var limit: Int?

    public init(
        nodeID: String? = nil,
        publicProfileID: String? = nil,
        statuses: Set<ExchangeOffer.Status>? = nil,
        visibility: Set<ExchangeOffer.Visibility>? = nil,
        categories: Set<String> = [],
        fulfillmentModes: Set<ExchangeOffer.SemanticSurface.FulfillmentMode>? = nil,
        searchText: String? = nil,
        updatedAfter: Date? = nil,
        updatedBefore: Date? = nil,
        limit: Int? = nil
    ) {
        self.nodeID = nodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.publicProfileID = publicProfileID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.statuses = statuses
        self.visibility = visibility
        self.categories = Set(
            categories
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        self.fulfillmentModes = fulfillmentModes
        self.searchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.updatedAfter = updatedAfter
        self.updatedBefore = updatedBefore
        self.limit = limit
    }
}

public struct ExchangeTrustEdgeFilter: Sendable, Hashable {
    public var sourceNodeID: String?
    public var targetNodeID: String?
    public var relationshipTypes: Set<ExchangeTrustEdge.RelationshipType>?
    public var trustLevels: Set<ExchangeTrustEdge.TrustLevel>?
    public var scopes: Set<ExchangeTrustEdge.TrustScope>?
    public var propagations: Set<ExchangeTrustEdge.Propagation>?
    public var sourceKinds: Set<ExchangeTrustEdge.SourceKind>?
    public var activeOnly: Bool
    public var limit: Int?

    public init(
        sourceNodeID: String? = nil,
        targetNodeID: String? = nil,
        relationshipTypes: Set<ExchangeTrustEdge.RelationshipType>? = nil,
        trustLevels: Set<ExchangeTrustEdge.TrustLevel>? = nil,
        scopes: Set<ExchangeTrustEdge.TrustScope>? = nil,
        propagations: Set<ExchangeTrustEdge.Propagation>? = nil,
        sourceKinds: Set<ExchangeTrustEdge.SourceKind>? = nil,
        activeOnly: Bool = true,
        limit: Int? = nil
    ) {
        self.sourceNodeID = sourceNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.targetNodeID = targetNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.relationshipTypes = relationshipTypes
        self.trustLevels = trustLevels
        self.scopes = scopes
        self.propagations = propagations
        self.sourceKinds = sourceKinds
        self.activeOnly = activeOnly
        self.limit = limit
    }
}

public struct ExchangeOutboxFilter: Sendable, Hashable {
    public var threadID: ExchangeThread.ID?
    public var draftID: ExchangeMessageDraft.ID?
    public var approvalID: ExchangeApproval.ID?
    public var targetNodeID: String?
    public var phases: Set<ExchangeDeliveryState.Phase>?
    public var activeOnly: Bool
    public var createdAfter: Date?
    public var createdBefore: Date?
    public var limit: Int?

    public init(
        threadID: ExchangeThread.ID? = nil,
        draftID: ExchangeMessageDraft.ID? = nil,
        approvalID: ExchangeApproval.ID? = nil,
        targetNodeID: String? = nil,
        phases: Set<ExchangeDeliveryState.Phase>? = nil,
        activeOnly: Bool = false,
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        limit: Int? = nil
    ) {
        self.threadID = threadID
        self.draftID = draftID
        self.approvalID = approvalID
        self.targetNodeID = targetNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.phases = phases
        self.activeOnly = activeOnly
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.limit = limit
    }
}

public struct ExchangeInboxFilter: Sendable, Hashable {
    public var threadID: ExchangeThread.ID?
    public var senderNodeID: String?
    public var processingStates: Set<ExchangeInboxItem.ProcessingState>?
    public var processableOnly: Bool
    public var receivedAfter: Date?
    public var receivedBefore: Date?
    public var limit: Int?
    /// When true, Inbound-style surfaces may include inbox rows reconciled into a thread. Default false for other callers.
    public var includeReconciledLinkedToThread: Bool

    public init(
        threadID: ExchangeThread.ID? = nil,
        senderNodeID: String? = nil,
        processingStates: Set<ExchangeInboxItem.ProcessingState>? = nil,
        processableOnly: Bool = false,
        receivedAfter: Date? = nil,
        receivedBefore: Date? = nil,
        limit: Int? = nil,
        includeReconciledLinkedToThread: Bool = false
    ) {
        self.threadID = threadID
        self.senderNodeID = senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.processingStates = processingStates
        self.processableOnly = processableOnly
        self.receivedAfter = receivedAfter
        self.receivedBefore = receivedBefore
        self.limit = limit
        self.includeReconciledLinkedToThread = includeReconciledLinkedToThread
    }
}

public struct ExchangeAuditFilter: Sendable, Hashable {
    public var threadID: ExchangeThread.ID?
    public var direction: ExchangeAuditRecord.Direction?
    public var categories: Set<ExchangeAuditRecord.Category>?
    public var envelopeID: String?
    public var relatedNodeID: String?
    public var createdAfter: Date?
    public var createdBefore: Date?
    public var limit: Int?

    public init(
        threadID: ExchangeThread.ID? = nil,
        direction: ExchangeAuditRecord.Direction? = nil,
        categories: Set<ExchangeAuditRecord.Category>? = nil,
        envelopeID: String? = nil,
        relatedNodeID: String? = nil,
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        limit: Int? = nil
    ) {
        self.threadID = threadID
        self.direction = direction
        self.categories = categories
        self.envelopeID = envelopeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.relatedNodeID = relatedNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.limit = limit
    }
}

public enum ExchangeStoreError: Error, Sendable, Hashable {
    case threadNotFound(ExchangeThread.ID)
    case draftNotFound(ExchangeMessageDraft.ID)
    case approvalNotFound(ExchangeApproval.ID)
    case counterpartyNotFound(ExchangeCounterparty.ID)
    case publicProfileNotFound(ExchangePublicNodeProfile.ID)
    case offerNotFound(ExchangeOffer.ID)
    case trustEdgeNotFound(ExchangeTrustEdge.ID)
    case trustedNodeProfileNotFound(String)
    case outboxItemNotFound(ExchangeOutboxItem.ID)
    case inboxItemNotFound(ExchangeInboxItem.ID)
    case invalidLimit
    case conflict(reason: String)
    case storageFailure(reason: String)
}

public extension ExchangeStore {
    func requireThread(id: ExchangeThread.ID) async throws -> ExchangeThread {
        guard let thread = try await fetchThread(id: id) else {
            throw ExchangeStoreError.threadNotFound(id)
        }
        return thread
    }

    func requireDraft(id: ExchangeMessageDraft.ID) async throws -> ExchangeMessageDraft {
        guard let draft = try await fetchDraft(id: id) else {
            throw ExchangeStoreError.draftNotFound(id)
        }
        return draft
    }

    func requireApproval(id: ExchangeApproval.ID) async throws -> ExchangeApproval {
        guard let approval = try await fetchApproval(id: id) else {
            throw ExchangeStoreError.approvalNotFound(id)
        }
        return approval
    }

    func requireCounterparty(id: ExchangeCounterparty.ID) async throws -> ExchangeCounterparty {
        guard let counterparty = try await fetchCounterparty(id: id) else {
            throw ExchangeStoreError.counterpartyNotFound(id)
        }
        return counterparty
    }

    func requirePublicProfile(id: ExchangePublicNodeProfile.ID) async throws -> ExchangePublicNodeProfile {
        guard let profile = try await fetchPublicProfile(id: id) else {
            throw ExchangeStoreError.publicProfileNotFound(id)
        }
        return profile
    }

    func requireOffer(id: ExchangeOffer.ID) async throws -> ExchangeOffer {
        guard let offer = try await fetchOffer(id: id) else {
            throw ExchangeStoreError.offerNotFound(id)
        }
        return offer
    }

    func requireTrustEdge(id: ExchangeTrustEdge.ID) async throws -> ExchangeTrustEdge {
        guard let edge = try await fetchTrustEdge(id: id) else {
            throw ExchangeStoreError.trustEdgeNotFound(id)
        }
        return edge
    }

    func requireTrustedNodeProfile(
        nodeID: String,
        forSourceNodeID sourceNodeID: String?
    ) async throws -> ExchangeTrustedNodeProfile {
        guard let profile = try await fetchTrustedNodeProfile(
            nodeID: nodeID,
            forSourceNodeID: sourceNodeID
        ) else {
            throw ExchangeStoreError.trustedNodeProfileNotFound(nodeID)
        }
        return profile
    }

    func requireOutboxItem(id: ExchangeOutboxItem.ID) async throws -> ExchangeOutboxItem {
        guard let item = try await fetchOutboxItem(id: id) else {
            throw ExchangeStoreError.outboxItemNotFound(id)
        }
        return item
    }

    func requireInboxItem(id: ExchangeInboxItem.ID) async throws -> ExchangeInboxItem {
        guard let item = try await fetchInboxItem(id: id) else {
            throw ExchangeStoreError.inboxItemNotFound(id)
        }
        return item
    }

    func requirePublicationState(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID
    ) async throws -> ExchangePublicationState {
        guard let state = try await fetchPublicationState(forPublicProfileID: publicProfileID) else {
            throw ExchangeStoreError.storageFailure(
                reason: "Publication state not found for public profile \(publicProfileID)."
            )
        }
        return state
    }
}

// MARK: - Seller publication helpers

public extension ExchangeStore {
    /// Ensures a publication state exists for the profile.
    func ensurePublicationState(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID,
        now: Date = Date()
    ) async throws -> ExchangePublicationState {
        if let existing = try await fetchPublicationState(forPublicProfileID: publicProfileID) {
            return existing
        }

        let initial = ExchangePublicationState(
            status: .draft,
            isDirty: true,
            publishedAt: nil,
            lastAttemptAt: nil,
            lastSuccessAt: nil,
            lastLocalMutationAt: now,
            lastFailureSummary: nil,
            lastRemoteProfileID: nil,
            lastRemoteOfferIDs: [],
            lastPublishedFingerprint: nil,
            metadata: [:]
        )

        try await savePublicationState(initial, forPublicProfileID: publicProfileID)
        return initial
    }

    /// Saves a public profile and marks its seller publication state dirty.
    func savePublicProfileMarkingPublicationDirty(
        _ profile: ExchangePublicNodeProfile,
        now: Date = Date()
    ) async throws {
        try await savePublicProfile(profile)
        try await markPublicationDirty(forPublicProfileID: profile.id, now: now)
    }

    /// Saves an offer and marks its linked publication state dirty.
    func saveOfferMarkingPublicationDirty(
        _ offer: ExchangeOffer,
        now: Date = Date()
    ) async throws {
        try await saveOffer(offer)

        guard let publicProfileID = offer.publicProfileID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !publicProfileID.isEmpty else {
            return
        }

        try await markPublicationDirty(forPublicProfileID: publicProfileID, now: now)
    }

    /// Marks the local seller surface as changed since the last successful remote publish.
    func markPublicationDirty(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID,
        now: Date = Date()
    ) async throws {
        let current = try await ensurePublicationState(
            forPublicProfileID: publicProfileID,
            now: now
        )

        let next = current.markingLocalMutation(at: now)
        try await savePublicationState(next, forPublicProfileID: publicProfileID)
    }

    /// Records that a publish attempt started.
    func markPublicationAttempted(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID,
        now: Date = Date()
    ) async throws {
        let current = try await ensurePublicationState(
            forPublicProfileID: publicProfileID,
            now: now
        )

        let next = current.markingPublishStarted(at: now)
        try await savePublicationState(next, forPublicProfileID: publicProfileID)
    }

    /// Records a successful publish and clears dirty state.
    func markPublicationSucceeded(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID,
        remoteProfileID: String,
        remoteOfferIDs: [String],
        fingerprint: String?,
        now: Date = Date()
    ) async throws {
        let current = try await ensurePublicationState(
            forPublicProfileID: publicProfileID,
            now: now
        )

        let next = current.markingPublished(
            remoteProfileID: remoteProfileID,
            remoteOfferIDs: remoteOfferIDs,
            fingerprint: fingerprint,
            at: now
        )

        try await savePublicationState(next, forPublicProfileID: publicProfileID)
    }

    /// Records a failed publish attempt.
    func markPublicationFailed(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID,
        summary: String,
        now: Date = Date()
    ) async throws {
        let current = try await ensurePublicationState(
            forPublicProfileID: publicProfileID,
            now: now
        )

        let next = current.markingPublishFailed(
            summary: summary,
            at: now
        )

        try await savePublicationState(next, forPublicProfileID: publicProfileID)
    }

    func markPublicationPaused(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID,
        now: Date = Date()
    ) async throws {
        let current = try await ensurePublicationState(
            forPublicProfileID: publicProfileID,
            now: now
        )

        let next = current.markingPaused(at: now)
        try await savePublicationState(next, forPublicProfileID: publicProfileID)
    }

    func markPublicationPendingUnpublish(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID,
        now: Date = Date()
    ) async throws {
        let current = try await ensurePublicationState(
            forPublicProfileID: publicProfileID,
            now: now
        )

        let next = current.markingPendingUnpublish(at: now)
        try await savePublicationState(next, forPublicProfileID: publicProfileID)
    }

    func markPublicationArchived(
        forPublicProfileID publicProfileID: ExchangePublicNodeProfile.ID,
        now: Date = Date()
    ) async throws {
        let current = try await ensurePublicationState(
            forPublicProfileID: publicProfileID,
            now: now
        )

        let next = current.markingArchived(at: now)
        try await savePublicationState(next, forPublicProfileID: publicProfileID)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
