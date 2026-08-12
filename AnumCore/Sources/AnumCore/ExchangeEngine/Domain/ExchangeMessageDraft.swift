import Foundation

/// Outbound or proposed message artifact for a coordination thread.
///
/// Drafts are durable domain objects. They are not just temporary UI text.
/// A draft may be reviewed, approved, revised, superseded, sent, or abandoned.
///
/// Keep this focused on message intent and authorship state.
/// Do not let it become the source of truth for transport or delivery.
public struct ExchangeMessageDraft: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var threadID: ExchangeThread.ID
    public var createdAt: Date
    public var updatedAt: Date

    public var status: Status
    public var kind: Kind
    public var audience: Audience

    /// The actual message content intended for outbound coordination.
    public var subject: String?
    public var body: String

    /// Optional concise explanation of the draft's strategy.
    ///
    /// Example:
    /// "Direct and concise first-touch outreach with low-pressure CTA."
    public var strategyNote: String?

    /// The posture snapshot used when the draft was generated.
    public var posture: ExchangePosture

    /// Optional target counterparty for this draft.
    public var targetCounterpartyID: ExchangeCounterparty.ID?

    /// If this draft supersedes an older draft, preserve the lineage.
    public var supersedesDraftID: ID?

    /// Optional external reference once successfully handed off for send.
    /// This is a linkage field, not transport source-of-truth.
    public var sentExternalReference: String?

    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        threadID: ExchangeThread.ID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: Status = .draft,
        kind: Kind,
        audience: Audience,
        subject: String? = nil,
        body: String,
        strategyNote: String? = nil,
        posture: ExchangePosture,
        targetCounterpartyID: ExchangeCounterparty.ID? = nil,
        supersedesDraftID: ID? = nil,
        sentExternalReference: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.threadID = threadID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.kind = kind
        self.audience = audience
        self.subject = subject?.exchangeNilIfBlank
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.strategyNote = strategyNote?.exchangeNilIfBlank
        self.posture = posture
        self.targetCounterpartyID = targetCounterpartyID?.exchangeNilIfBlank
        self.supersedesDraftID = supersedesDraftID
        self.sentExternalReference = sentExternalReference?.exchangeNilIfBlank
        self.metadata = metadata
    }
}

public extension ExchangeMessageDraft {
    enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case draft
        case awaitingApproval
        case approved
        case rejected
        case sent
        case superseded
        case abandoned
    }

    enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
        case introduction
        case quoteRequest
        case inquiry
        case followUp
        case negotiation
        case scheduling
        case closure
        case other
    }

    enum Audience: String, Codable, Sendable, CaseIterable, Hashable {
        case externalCounterparty
        case relayNode
        case other
    }
}

public extension ExchangeMessageDraft {
    var isActionable: Bool {
        switch status {
        case .draft, .awaitingApproval, .approved:
            return true
        case .rejected, .sent, .superseded, .abandoned:
            return false
        }
    }
    
    /// Whether this draft is currently waiting on approval before it may proceed.
    ///
    /// Richer approval policy belongs in the approval engine.
    var requiresApprovalBeforeSend: Bool {
        status == .awaitingApproval
    }
    
    var previewText: String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let subject, !subject.isEmpty {
            return "\(subject) — \(String(trimmedBody.prefix(120)))"
        }
        return String(trimmedBody.prefix(140))
    }
    
    func updatingContent(
        subject: String?,
        body: String,
        strategyNote: String? = nil,
        at date: Date = Date()
    ) -> ExchangeMessageDraft {
        var copy = self
        copy.subject = subject?.exchangeNilIfBlank
        copy.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.strategyNote = strategyNote?.exchangeNilIfBlank
        copy.updatedAt = date
        return copy
    }
    
    func markingAwaitingApproval(at date: Date = Date()) -> ExchangeMessageDraft {
        var copy = self
        copy.status = .awaitingApproval
        copy.updatedAt = date
        return copy
    }
    
    func approving(at date: Date = Date()) -> ExchangeMessageDraft {
        var copy = self
        copy.status = .approved
        copy.updatedAt = date
        return copy
    }
    
    func rejecting(at date: Date = Date()) -> ExchangeMessageDraft {
        var copy = self
        copy.status = .rejected
        copy.updatedAt = date
        return copy
    }
    
    func markingSent(
        externalReference: String? = nil,
        at date: Date = Date()
    ) -> ExchangeMessageDraft {
        var copy = self
        copy.status = .sent
        copy.sentExternalReference = externalReference?.exchangeNilIfBlank
        copy.updatedAt = date
        return copy
    }
    
    func superseding(
        with newDraftID: ID,
        at date: Date = Date()
    ) -> ExchangeMessageDraft {
        var copy = self
        copy.status = .superseded
        copy.updatedAt = date
        copy.metadata["superseded_by_draft_id"] = newDraftID.uuidString
        return copy
    }
    
    func abandoning(at date: Date = Date()) -> ExchangeMessageDraft {
        var copy = self
        copy.status = .abandoned
        copy.updatedAt = date
        return copy
    }
    
    /// True when any draft is an unsent outbound message to the external counterparty with real body text.
    ///
    /// Mirrors list/detail “Draft ready” / actionable outbound gates: excludes internal/other audiences,
    /// empty bodies, and terminal send states (`.sent`, `.superseded`, `.abandoned`, `.rejected`).
    ///
    /// **Important:** `.approved` is excluded here. After the user approves, the draft is owned by the
    /// outbound/send pipeline; UI should show sending/sent/transcript rows, not a second “Draft ready” surface.
    /// Domain ``isActionable`` still treats `.approved` as actionable for orchestration until `.sent`.
    static func hasActionableExternalOutboundDraft(in drafts: [ExchangeMessageDraft]) -> Bool {
        drafts.contains { draft in
            guard draft.audience == .externalCounterparty else { return false }
            guard !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            switch draft.status {
            case .draft, .awaitingApproval:
                return true
            case .approved, .rejected, .sent, .superseded, .abandoned:
                return false
            }
        }
    }
    
    /// Persisted actionable external draft **and** durable recipient routing on the owning thread.
    ///
    /// Use this anywhere user-visible “Draft ready” / outbound review surfaces decide visibility.
    ///
    /// - Parameter turns: When provided, drafts older than the latest outbound send evidence (sent drafts,
    ///   ``ExchangeTurn.Kind/sendConfirmed``, thread delivery) are treated as stale and ignored so a newer
    ///   manual send does not leave an older second-half clarification draft actionable.
    static func hasUserFacingRenderableExternalOutboundDraft(
        in drafts: [ExchangeMessageDraft],
        thread: ExchangeThread,
        turns: [ExchangeTurn] = []
    ) -> Bool {
        !Self.userFacingRenderableExternalOutboundDrafts(in: drafts, thread: thread, turns: turns).isEmpty
    }
    
    /// Newest store-backed external outbound draft that should surface on Draft ready / review UI.
    static func newestUserFacingRenderableExternalOutboundDraft(
        in drafts: [ExchangeMessageDraft],
        thread: ExchangeThread,
        turns: [ExchangeTurn] = []
    ) -> ExchangeMessageDraft? {
        Self.userFacingRenderableExternalOutboundDrafts(in: drafts, thread: thread, turns: turns)
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
    }
    
    /// Canonical set of draft IDs that pass the same projection gates as ``hasUserFacingRenderableExternalOutboundDraft``
    /// / ``newestUserFacingRenderableExternalOutboundDraft`` (Conversation transcript, Draft ready card, etc.).
    static func userFacingRenderableExternalOutboundDraftIDs(
        in drafts: [ExchangeMessageDraft],
        thread: ExchangeThread,
        turns: [ExchangeTurn] = []
    ) -> Set<ID> {
        Set(Self.userFacingRenderableExternalOutboundDrafts(in: drafts, thread: thread, turns: turns).map(\.id))
    }
    
    // MARK: - User-facing outbound draft visibility (projection-only)
    
    private static func userFacingRenderableExternalOutboundDrafts(
        in drafts: [ExchangeMessageDraft],
        thread: ExchangeThread,
        turns: [ExchangeTurn]
    ) -> [ExchangeMessageDraft] {
        guard ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread) else {
#if DEBUG
            if Self.hasActionableExternalOutboundDraft(in: drafts) {
                Swift.print(
                    "[DraftAnchor] orphaned_actionable_external_draft_without_recipient_surface thread=\(thread.id.uuidString)"
                )
            }
#endif
            return []
        }
        
        let evidence = Self.latestOutboundSendEvidenceDate(drafts: drafts, turns: turns, thread: thread)
        var visible: [ExchangeMessageDraft] = []
        for draft in drafts {
            guard Self.hasActionableExternalOutboundDraft(in: [draft]) else { continue }
            let suppressed = Self.shouldSuppressDraftForUserFacingOutboundDisplay(
                draft: draft,
                evidenceDate: evidence,
                thread: thread
            )
#if DEBUG
            draftReadyProjectionDebugLog(
                threadID: thread.id,
                draft: draft,
                evidenceDate: evidence,
                visible: !suppressed
            )
#endif
            if !suppressed {
                visible.append(draft)
            }
        }
        return visible
    }
    
    /// Latest moment we have durable proof something outbound was already handed off / confirmed sent.
    ///
    /// Shared by user-facing draft gates and Conversation transcript diagnostics (same evidence timeline).
    internal static func latestOutboundSendEvidenceDate(
        drafts: [ExchangeMessageDraft],
        turns: [ExchangeTurn],
        thread: ExchangeThread
    ) -> Date? {
        var dates: [Date] = []
        for d in drafts where d.audience == .externalCounterparty && d.status == .sent {
            dates.append(d.updatedAt)
        }
        for t in turns where t.kind == .sendConfirmed {
            dates.append(t.createdAt)
        }
        if thread.delivery?.status == .sent {
            if let at = thread.delivery?.lastConfirmedSendAt ?? thread.delivery?.lastAttemptAt {
                dates.append(at)
            }
        }
        return dates.max()
    }
    
    private static func shouldSuppressDraftForUserFacingOutboundDisplay(
        draft: ExchangeMessageDraft,
        evidenceDate: Date?,
        thread: ExchangeThread
    ) -> Bool {
        if let ev = evidenceDate, draft.updatedAt < ev {
#if DEBUG
            Swift.print(
                "[StaleDraftSuppression] thread=\(thread.id.uuidString) draft=\(draft.id.uuidString) reason=newerOutboundSent latestEvidence=\(ev.timeIntervalSince1970)"
            )
#endif
            return true
        }
        
        if evidenceDate == nil { return false }
        
        if draft.metadata["second_half_generated"] == "true",
           Self.looksLikeSecondHalfInternalDecisionScaffoldBody(draft) {
#if DEBUG
            Swift.print(
                "[StaleDraftSuppression] thread=\(thread.id.uuidString) draft=\(draft.id.uuidString) reason=internalScaffold"
            )
#endif
            return true
        }
        
        return false
    }
    
    /// Heuristic: bodies produced by ``ExchangeDraftComposer`` / Pass-2 augment for generic “Find Match” clarifications.
    private static func looksLikeSecondHalfInternalDecisionScaffoldBody(_ draft: ExchangeMessageDraft) -> Bool {
        let b = draft.body.lowercased()
        if b.contains("public-surface-aligned questions") { return true }
        if b.contains("we're close to a decision") || b.contains("we’re close to a decision") { return true }
        if b.contains("find match") && b.contains("decision") { return true }
        if b.contains("capacity / throughput") || b.contains("cancellation/refund") { return true }
        if b.contains("shipping/delivery") { return true }
        if b.contains("hardened timeline") || b.contains("what hardened timeline") { return true }
        return false
    }
    
#if DEBUG
    private static func draftReadyProjectionDebugLog(
        threadID: ExchangeThread.ID,
        draft: ExchangeMessageDraft,
        evidenceDate: Date?,
        visible: Bool
    ) {
        let reason: String
        
        if visible {
            reason = "eligible"
        } else if let ev = evidenceDate, draft.updatedAt < ev {
            reason = "suppressed_newerOutboundSent"
        } else if evidenceDate != nil,
                  draft.metadata["second_half_generated"] == "true",
                  Self.looksLikeSecondHalfInternalDecisionScaffoldBody(draft) {
            reason = "suppressed_internalScaffold"
        } else {
            reason = "suppressed_other"
        }
        
        Swift.print(
            "[DraftReadyProjection] thread=\(threadID.uuidString) draft=\(draft.id.uuidString) status=\(draft.status.rawValue) audience=\(draft.audience.rawValue) updatedAt=\(draft.updatedAt.timeIntervalSince1970) latestSendEvidence=\(evidenceDate?.timeIntervalSince1970.description ?? "nil") visible=\(visible) reason=\(reason)"
        )
    }
#endif
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
