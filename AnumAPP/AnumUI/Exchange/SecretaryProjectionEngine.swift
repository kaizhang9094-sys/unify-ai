import Foundation
import AnumCore

enum SecretaryProjectionEngine {
    /// Inline **Send** on ThreadView Draft ready card: same safe/routine gates as the approval sheet primary (no decision/commitment sheet).
    ///
    /// Intentionally **does not** block on ``SecretaryApprovalPanelDisplay/hasDecisionPacket`` or
    /// ``hasCommitmentBoundary``: harmless second-half framing (e.g. stale “waiting for provider” lines) must not
    /// force **Review** when the outbound path is executable and human approval is not required.
    static func threadViewDirectApproveAndSendEligible(for detail: ExchangeModels.ThreadDetail) -> Bool {
        guard hasActionableExternalOutboundDraft(in: detail) else {
            logDirectSendEligibleDeny(detail: detail, reason: "no_actionable_external_outbound_draft")
            return false
        }
        guard ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: detail.thread) else {
            logDirectSendEligibleDeny(detail: detail, reason: "no_recipient_surface")
            return false
        }

        if threadViewAutonomousRoutineSuppressesManualSend(for: detail) {
            logDirectSendEligibleDeny(detail: detail, reason: "autonomy_suppresses_manual_send")
            return false
        }

        // Thread autonomy allows auto-send, but Pass-3 is holding: use Review + hold copy — not a routine inline Send.
        if threadViewAutonomyGateDeniedExplanation(for: detail) != nil {
            logDirectSendEligibleDeny(detail: detail, reason: "autonomy_gate_denied")
            return false
        }

        let display = approvalDisplay(for: detail)

        if display.requiresHumanApproval {
            logDirectSendEligibleDeny(detail: detail, reason: "requires_human_approval", display: display)
            return false
        }

        let executable = display.prefersSecondHalfPreparedSend || display.approvalID != nil
        guard executable else {
            logDirectSendEligibleDeny(detail: detail, reason: "no_prepared_send_and_no_approval_id", display: display)
            return false
        }

        return true
    }

    #if DEBUG
    private static func logDirectSendEligibleDeny(
        detail: ExchangeModels.ThreadDetail,
        reason: String,
        display: SecretaryApprovalPanelDisplay? = nil
    ) {
        let d = display ?? approvalDisplay(for: detail)
        Swift.print(
            "[DirectSendEligible] DENY reason=\(reason) thread=\(detail.thread.id.uuidString) " +
                "hasActionableDraft=\(hasActionableExternalOutboundDraft(in: detail)) " +
                "hasRecipientSurface=\(ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: detail.thread)) " +
                "autonomySuppressed=\(threadViewAutonomousRoutineSuppressesManualSend(for: detail)) " +
                "autonomyGateDenied=\(threadViewAutonomyGateDeniedExplanation(for: detail) != nil) " +
                "requiresHumanApproval=\(d.requiresHumanApproval) " +
                "hasDecisionPacket=\(d.hasDecisionPacket) " +
                "hasCommitmentBoundary=\(d.hasCommitmentBoundary) " +
                "prefersSecondHalfPreparedSend=\(d.prefersSecondHalfPreparedSend) " +
                "approvalIDNil=\(d.approvalID == nil) " +
                "canRunPrimaryAction=\(d.canRunPrimaryAction)"
        )
    }
    #else
    @inline(__always)
    private static func logDirectSendEligibleDeny(
        detail: ExchangeModels.ThreadDetail,
        reason: String,
        display: SecretaryApprovalPanelDisplay? = nil
    ) {
        _ = (detail, reason, display)
    }
    #endif

    /// When auto-reply/autonomy is on and the planner gate allows, hide manual **Send** (auto path owns the move).
    static func threadViewAutonomousRoutineSuppressesManualSend(for detail: ExchangeModels.ThreadDetail) -> Bool {
        guard ExchangeAutonomousSendPolicy.currentThreadAutonomyAuthority().allowsAutonomousSend else { return false }
        guard let sh = secondHalfDisplay(for: detail) else { return false }
        guard hasActionableExternalOutboundDraft(in: detail) else { return false }
        guard latestPendingApproval(for: detail) == nil else { return false }
        if secondHalfRequiresDedicatedApprovalSheet(sh) { return false }
        let gate = autonomousOutboundGate(for: sh)
        return gate.allowed
    }

    /// User-facing line when autonomy is enabled but the outbound gate vetoes automatic send.
    static func threadViewAutonomyGateDeniedExplanation(for detail: ExchangeModels.ThreadDetail) -> String? {
        guard ExchangeAutonomousSendPolicy.currentThreadAutonomyAuthority().allowsAutonomousSend else { return nil }
        guard let sh = secondHalfDisplay(for: detail) else { return nil }
        guard hasActionableExternalOutboundDraft(in: detail) else { return nil }
        if secondHalfRequiresDedicatedApprovalSheet(sh) { return nil }
        let gate = autonomousOutboundGate(for: sh)
        guard !gate.allowed else { return nil }
        return ExchangeAgencyPlanner.userFacingAutonomyHold(from: gate).line
    }

    /// When auto-reply owns the send, short pipeline copy for the draft card (evidence-backed; nil in manual mode).
    static func threadViewAutonomousOutboundPipelineExplanation(for detail: ExchangeModels.ThreadDetail) -> String? {
        guard threadViewAutonomousRoutineSuppressesManualSend(for: detail) else { return nil }
        if outboundSendEvidence(in: detail) {
            return "Sent."
        }
        guard let draft = latestPersistedActionableExternalOutboundDraft(for: detail) else {
            return "Will send automatically when a sendable draft is ready."
        }
        let obs = detail.outboxItems.filter { ob in
            ob.threadID == detail.thread.id && ob.draftID == draft.id && ob.isActive
        }
        if obs.contains(where: { $0.deliveryState.phase == .sending }) {
            return "Sending automatically now."
        }
        if obs.contains(where: {
            switch $0.deliveryState.phase {
            case .queued, .blockedByPrerequisite, .deferred:
                return true
            default:
                return false
            }
        }) {
            return "Queued — sending automatically."
        }
        if sendingOutboundIsTruthful(for: detail) {
            return "Sending automatically now."
        }
        return "Will send automatically when ready."
    }

    /// Conversation before offer/profile **surface** — disabled for consistent desk layout; inbound text lives in
    /// ``SecretaryThreadTranscriptView`` only (see ``ThreadTranscriptBuilder``).
    static func threadViewShouldPrioritizeConversationBeforeSurfaceHero(for detail: ExchangeModels.ThreadDetail) -> Bool {
        false
    }

    /// Routine inline Send path (no second approval sheet) — alias for tests and call sites.
    static func threadViewPrefersInlineSendOverApprovalSheet(for detail: ExchangeModels.ThreadDetail) -> Bool {
        threadViewDirectApproveAndSendEligible(for: detail)
    }

    struct CompactInboundMessageStrip: Equatable {
        public var eyebrow: String
        public var titleLine: String
        public var trustChip: String?
        public var bodyLine: String
    }

    enum ProviderInboundReplyBarIntent: Equatable {
        /// Routine provider inbound reply opens the manual compose sheet (inbound outbox queue on the open thread).
        case openInboundReplyComposer
        /// Thread is in structured clarification state (requester/missing-detail flow).
        case openStructuredClarification
    }

    /// Compact card placed **below** the surfaced offer/profile hero so inbound text stays visible without swapping section order.
    static func compactInboundMessageStrip(for detail: ExchangeModels.ThreadDetail) -> CompactInboundMessageStrip? {
        guard detail.thread.metadata["inbound_thread"] == "true" else { return nil }
        guard threadViewHasInboundReplyReceivedWithUsableText(detail) else { return nil }

        let replies = detail.turns.filter { $0.kind == .replyReceived }
        guard let latest = replies.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
        let rawBody = (latest.detail?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(\.nilIfBlank)
            ?? latest.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawBody.isEmpty else { return nil }

        let sender = inboundRemoteSenderPresentation(for: detail, latestInboundTurn: latest)
        return CompactInboundMessageStrip(
            eyebrow: "Latest message",
            titleLine: sender.titleLine,
            trustChip: sender.trustChip,
            bodyLine: String(rawBody.prefix(400))
        )
    }

    /// Prominent reply affordance for provider inbound threads (never replaces autonomous send safety gates).
    static func providerInboundReplyBarIntent(for detail: ExchangeModels.ThreadDetail) -> ProviderInboundReplyBarIntent? {
        guard detail.thread.metadata["inbound_thread"] == "true" else { return nil }
        guard threadViewHasInboundReplyReceivedWithUsableText(detail) else { return nil }

        let sh = secondHalfDisplay(for: detail)
        let providerSurface =
            sh.map { $0.status.role.caseInsensitiveCompare(ExchangeSecondHalfRole.provider.displayTitle) == .orderedSame } ?? true

        guard providerSurface else { return nil }

        if threadViewDirectApproveAndSendEligible(for: detail) {
            return nil
        }

        if case .needsClarification = detail.thread.state {
            return .openStructuredClarification
        }

        return .openInboundReplyComposer
    }

    /// Single primary label for the conversation footer action (no separate reply card).
    static func providerInboundConversationActionLabel(for detail: ExchangeModels.ThreadDetail) -> String {
        if case .needsClarification = detail.thread.state {
            return "Answer"
        }
        return "Reply"
    }

    /// Back-compat shim; use ``shouldSuppressProviderInboundApprovalCard(for:)``.
    static func shouldSuppressMisleadingApprovalCardForProviderInboundCoordination(
        for detail: ExchangeModels.ThreadDetail
    ) -> Bool {
        shouldSuppressProviderInboundApprovalCard(for: detail)
    }

    /// Detects provider-side inbound desks even when ``metadata["inbound_thread"]`` is missing from some paths.
    private static func threadDetailIsInboundProviderStyle(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        let meta = detail.thread.metadata
        if meta["inbound_thread"]?.trimmingCharacters(in: .whitespacesAndNewlines) == "true" {
            return true
        }
        let inboundSender = meta["inbound_sender_node"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !inboundSender.isEmpty { return true }

        let sh = secondHalfDisplay(for: detail)
        guard detailHasInboundReplyEvidence(detail, secondHalf: sh) else { return false }
        if let sh {
            return sh.status.role.caseInsensitiveCompare(ExchangeSecondHalfRole.provider.displayTitle) == .orderedSame
        }
        return true
    }

    private static func pendingApprovalLinksUserFacingRenderableDraft(for detail: ExchangeModels.ThreadDetail) -> Bool {
        guard let pending = latestPendingApproval(for: detail), let did = pending.draftID else { return false }
        guard let d = detail.drafts.first(where: { $0.id == did }) else { return false }
        return ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(
            in: [d],
            thread: detail.thread,
            turns: detail.turns
        )
    }

    /// Unified gate: hide coordination-only “approval” when there is nothing user-facing to approve on provider inbound threads.
    static func shouldSuppressProviderInboundApprovalCard(for detail: ExchangeModels.ThreadDetail) -> Bool {
        guard threadDetailIsInboundProviderStyle(detail) else { return false }
        guard !hasActionableExternalOutboundDraft(in: detail) else { return false }
        if outboundSendEvidence(in: detail) { return false }
        if detailHasActiveOutboundOutboxSendingWork(in: detail) { return false }

        let sh = secondHalfDisplay(for: detail)
        if let sh, sh.hasDecisionPacket { return false }
        if pendingApprovalLinksUserFacingRenderableDraft(for: detail) { return false }

        let pendingExists = latestPendingApproval(for: detail) != nil
        if pendingExists { return true }

        if let sh,
           sh.boundary.requiresHumanApproval,
           nonEmpty(sh.boundary.reason) != nil {
            return true
        }

        return false
    }

    private struct InboundSenderPresentation {
        var titleLine: String
        var trustChip: String?
    }

    private static func inboundRemoteSenderPresentation(
        for detail: ExchangeModels.ThreadDetail,
        latestInboundTurn: ExchangeTurn
    ) -> InboundSenderPresentation {
        let nodeKeys = [
            latestInboundTurn.metadata["source_sender_node_id"],
            latestInboundTurn.metadata["inbound_sender_node"],
            detail.thread.metadata["inbound_sender_node"]
        ]
        let nodeID = nodeKeys.compactMap { raw -> String? in
            let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }.first

        if let nodeID,
           let cp = detail.counterparties.first(where: { $0.id == nodeID }) {
            let base = counterpartyPublicSurfaceHeadline(cp) ?? cp.bestDisplayLine
            let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String = {
                if !trimmed.isEmpty,
                   !ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate(trimmed) {
                    return "Message from \(trimmed)"
                }
                return shortNodeIdentityLine(nodeID: nodeID)
            }()

            let chip = inboundTrustChip(for: cp)
            return InboundSenderPresentation(titleLine: title, trustChip: chip)
        }

        if let nodeID {
            return InboundSenderPresentation(
                titleLine: shortNodeIdentityLine(nodeID: nodeID),
                trustChip: "New contact"
            )
        }

        return InboundSenderPresentation(titleLine: "Inbound message", trustChip: nil)
    }

    private static func shortNodeIdentityLine(nodeID: String) -> String {
        let trimmed = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Inbound message" }
        if trimmed.lowercased().hasPrefix("node-") {
            let tail = trimmed.dropFirst("node-".count)
            let prefix = String(tail.prefix(8))
            return "Message from node \(prefix)…"
        }
        let prefix = String(trimmed.prefix(10))
        return "Message from \(prefix)…"
    }

    private static func inboundTrustChip(for counterparty: ExchangeCounterparty) -> String? {
        switch counterparty.trust.level {
        case .high, .moderate:
            return "Known contact"
        case .low, .unverified:
            return "New contact"
        }
    }

    private static func counterpartyPublicSurfaceHeadline(_ counterparty: ExchangeCounterparty) -> String? {
        if let headline = counterparty.publicProfile?.headline?.trimmingCharacters(in: .whitespacesAndNewlines),
           !headline.isEmpty {
            return headline
        }
        if let name = counterparty.publicProfile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return nil
    }

    /// When the surface card is shown first, surface a one-line post-approval clarification (conversation is below).
    static func threadViewOutstandingPostApprovalNoticeLine(for detail: ExchangeModels.ThreadDetail) -> String? {
        guard !threadViewShouldPrioritizeConversationBeforeSurfaceHero(for: detail) else { return nil }
        guard let grant = detail.turns
            .filter({ $0.kind == .approvalGranted })
            .max(by: { $0.createdAt < $1.createdAt })
        else {
            return nil
        }
        let pivot = grant.createdAt
        guard !threadDetailHasOutboundPipelineEvidence(after: pivot, detail: detail) else { return nil }

        if let sh = secondHalfDisplay(for: detail),
           secondHalfProviderInboundNeedsCoordinationInput(sh, detail: detail) {
            return "Needs your reply before Unify can send."
        }
        if !ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: detail.thread) {
            return "Approval recorded — nothing was sent yet because routing to the contact is not set up."
        }
        if !hasActionableExternalOutboundDraft(in: detail) {
            return "Approval recorded — nothing was sent yet because there isn’t a sendable outbound draft."
        }
        let reason = threadViewPostApprovalNoSendReason(detail)
        return "Approval recorded — \(reason)"
    }

    private static func threadViewHasInboundReplyReceivedWithUsableText(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        detail.turns.contains { turn in
            guard turn.kind == .replyReceived else { return false }
            let d = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let s = turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return !d.isEmpty || !s.isEmpty
        }
    }

    /// Mirrors ``ExchangeModels.ThreadTranscriptBuilder`` pipeline evidence (read-only; keeps list/detail honest).
    private static func threadDetailHasOutboundPipelineEvidence(
        after pivot: Date,
        detail: ExchangeModels.ThreadDetail
    ) -> Bool {
        let threadID = detail.thread.id
        if detail.drafts.contains(where: { draft in
            draft.audience == .externalCounterparty
                && draft.status == .sent
                && draft.updatedAt >= pivot
        }) {
            return true
        }
        if let delivery = detail.thread.delivery, delivery.status == .sent,
           let at = delivery.lastAttemptAt ?? delivery.lastConfirmedSendAt, at >= pivot {
            return true
        }
        return detail.outboxItems.contains { ob in
            guard ob.threadID == threadID else { return false }
            guard ob.updatedAt >= pivot else { return false }
            switch ob.deliveryState.phase {
            case .queued, .blockedByPrerequisite, .deferred, .sending, .sent:
                return true
            case .acknowledged, .failed, .cancelledBeforeSend, .tooLateToCancel, .incompatible:
                return false
            }
        }
    }

    private static func threadViewPostApprovalNoSendReason(_ detail: ExchangeModels.ThreadDetail) -> String {
        if let note = detail.thread.delivery?.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return note
        }
        if let step = detail.thread.workTrace?.steps.last(where: { $0.key == "coordination_input_needed_after_approval" }),
           let d = step.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !d.isEmpty {
            return d
        }
        if let headline = detail.thread.workTrace?.headline?.trimmingCharacters(in: .whitespacesAndNewlines),
           !headline.isEmpty {
            return headline
        }
        return "the message could not be queued yet"
    }

    private static func autonomousOutboundGate(
        for display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> ExchangeAgencyAutonomousOutboundGateResult {
        if display.status.role.caseInsensitiveCompare(ExchangeSecondHalfRole.provider.displayTitle) == .orderedSame {
            return ExchangeAgencyPlanner.evaluateAutonomousOutboundGate(display: display)
        }
        return ExchangeAgencyPlanner.evaluateRequesterAutonomousOutboundGate(display: display)
    }

    private static func secondHalfRequiresDedicatedApprovalSheet(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> Bool {
        if display.hasDecisionPacket { return true }
        if display.boundary.requiresHumanApproval { return true }
        if secondHalfBlocksPreparedSend(display) { return true }
        return false
    }

    /// Narrower than `secondHalfRequiresDedicatedApprovalSheet`.
    /// This decides whether an otherwise sendable prepared draft must stay behind Review.
    private static func secondHalfBlocksPreparedSend(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> Bool {
        if display.boundary.requiresHumanApproval {
            return true
        }

        let riskText = [
            nonEmpty(display.escalationReason),
            nonEmpty(display.boundary.reason),
            nonEmpty(display.boundary.externalEffectLine),
            nonEmpty(display.boundary.title)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        guard !riskText.isEmpty else {
            return false
        }

        let placeholderOrSafe =
            riskText.contains("no boundary reason recorded") ||
            riskText.contains("routine non-binding") ||
            riskText.contains("safe to continue") ||
            riskText.contains("normal checks") ||
            riskText.contains("no commitment") ||
            riskText.contains("not commitment-bearing") ||
            riskText.contains("non-binding")

        if placeholderOrSafe {
            return false
        }

        let approvalRisk =
            riskText.contains("approval") ||
            riskText.contains("commitment") ||
            riskText.contains("commit") ||
            riskText.contains("obligation") ||
            riskText.contains("private") ||
            riskText.contains("payment") ||
            riskText.contains("money") ||
            riskText.contains("price") ||
            riskText.contains("pricing") ||
            riskText.contains("legal") ||
            riskText.contains("contract") ||
            riskText.contains("exception")

        return approvalRisk
    }

    /// Waiting-state copy that should not appear in the approval **decision packet** when an outbound draft is ready.
    private static func isStaleWaitingForProviderDecisionCopy(_ raw: String) -> Bool {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        if n == "waiting for the provider's reply." { return true }
        if n == "waiting for the provider's reply" { return true }
        if n == "once they respond, unify will refresh this summary." { return true }
        if n == "once they respond, unify will refresh this summary" { return true }
        if n == "wait for reply" { return true }
        if n == "waiting for their reply" { return true }
        if n == "waiting for reply" { return true }
        if n.hasPrefix("waiting for the provider"), n.contains("reply") { return true }
        if n.contains("waiting"), n.contains("reply") { return true }
        if n.contains("once they respond") { return true }
        if n.contains("waiting on the other side") { return true }
        return false
    }

    /// Drops stale waiting copy from decision packet fields when a user-facing outbound draft is present.
    private static func approvalDisplayFilteredDecisionPacketLine(
        _ line: String?,
        suppressStaleWaitingWhenActionableDraft: Bool
    ) -> String? {
        guard let v = nonEmpty(line) else { return nil }
        guard suppressStaleWaitingWhenActionableDraft else { return v }
        guard isStaleWaitingForProviderDecisionCopy(v) else { return v }
        return nil
    }

    /// Human-readable boundary copy for the approval sheet; filters obvious coordination/debug vocabulary.
    static func passesApprovalSheetBoundaryPublicCopy(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isBlockedSystemArtifactText(trimmed) { return false }
        let lower = trimmed.lowercased()
        let extraBanned = ["route id", "route:", "raw log", "coordination path"]
        return !extraBanned.contains(where: { lower.contains($0) })
    }

    static func isBlockedSystemArtifactText(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        let blocked = [
            "coordination path",
            "system messages",
            "fit movement",
            "published seller surfaces",
            "not anchored",
            "snapshot",
            "capacity",
            "throughput",
            "exchange is strong enough",
            "new activity in this thread",
            "routine non-binding",
            "boundary",
            "schema",
            "deterministic",
            "pass 1",
            "pass 2",
            "pass 3",
            "outbound probe"
        ]
        return blocked.contains(where: { lower.contains($0) })
    }
    struct SecretaryMovementLine: Hashable {
        let title: String
        let detail: String
        let systemImage: String
    }
    
    // MARK: - Workspace classification
    
    enum Bucket: Hashable {
        case pending
        case searchResult
        case active
        case trusted
        case recovery
        case none
    }

    /// Terminal failed search — durable in SQLite; visible as a completed search receipt, not an operational desk row.
    static func isTerminalNoMatchSearch(_ item: ExchangeModels.InboxItem) -> Bool {
        if case .noViableMatch = item.state { return true }
        return false
    }

    /// Projection-only open policy: visibility and actionability are separate.
    enum SecretaryThreadInteractionPolicy: Sendable, Hashable {
        case operational
        case terminalSearchReceipt
    }

    static func interactionPolicy(for item: ExchangeModels.InboxItem) -> SecretaryThreadInteractionPolicy {
        isTerminalNoMatchSearch(item) ? .terminalSearchReceipt : .operational
    }

    static func isTerminalSearchReceipt(_ item: ExchangeModels.InboxItem) -> Bool {
        interactionPolicy(for: item) == .terminalSearchReceipt
    }

    static func isOperationalThreadOpenAllowed(_ item: ExchangeModels.InboxItem) -> Bool {
        interactionPolicy(for: item) == .operational
    }

    // MARK: - Unified visible thread status (list + detail)

    /// Canonical primary meaning for secretary thread surfaces — same priority for ``InboxItem`` and ``ThreadDetail``.
    enum ExchangeVisibleThreadStatusPrimary: Hashable, Sendable {
        case approvalNeeded
        case draftReady
        case sending
        case needsReviewArtifacts
        case replyReceived
        case waitingForReply
        case pulledOffer
        case pulledProfile
        case potentialMatch
        case noConfirmedMatch
        case needsYourInput
        case needsFix
        case completed
        case needsReview
        case openExchange
    }

    /// UI tone hint (maps to secretary chips / hero pill in SwiftUI callers).
    enum ExchangeVisibleThreadStatusTone: Hashable, Sendable {
        case neutral
        case warning
        case blocked
        case success
        case active
    }

    struct ExchangeVisibleThreadStatus: Hashable, Sendable {
        public var primary: ExchangeVisibleThreadStatusPrimary
        public var label: String
        public var subtitle: String?
        public var tone: ExchangeVisibleThreadStatusTone
        public var systemImage: String
    }

    /// Artifact-first visible status for thread **detail**.
    ///
    /// Priority: completed → structural failure → approval → actionable draft → sending → decision/requester-review
    /// artifact → inbound reply evidence → outbound wait → anchored offer/profile → weaker match states → clarification → open.
    static func visibleThreadStatus(for detail: ExchangeModels.ThreadDetail) -> ExchangeVisibleThreadStatus {
        renderVisibleThreadStatus(resolveVisibleThreadInputs(from: detail))
    }

    /// Same ordering as ``visibleThreadStatus(for:)`` using **only** inbox card fields (`bucket` informs recovery UI only).
    static func visibleThreadStatus(
        for item: ExchangeModels.InboxItem,
        bucket: Bucket,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = []
    ) -> ExchangeVisibleThreadStatus {
        renderVisibleThreadStatus(resolveVisibleThreadInputs(from: item, bucket: bucket, pendingApprovalThreadIDs: pendingApprovalThreadIDs))
    }

    /// Back-compat: list orb label (delegates to ``visibleThreadStatus(for:bucket:pendingApprovalThreadIDs:)``).
    static func exchangeListStatusLabel(
        for item: ExchangeModels.InboxItem,
        bucket: Bucket,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = []
    ) -> String {
        visibleThreadStatus(for: item, bucket: bucket, pendingApprovalThreadIDs: pendingApprovalThreadIDs).label
    }

    /// List/desk surfaces use factual card subtitles only; status-coach lines are ThreadView-only.
    private static func listSurfaceExcludesVisibleStatusCoach(_ surface: String) -> Bool {
        switch surface.lowercased() {
        case "exchange", "threads", "desksnapshot", "history", "dashboard":
            return true
        default:
            return false
        }
    }

    /// Prefer visible-status subtitle then fall back to legacy card subtitle synthesis.
    static func displayExchangeCardSubtitlePreferringVisibleStatus(
        for item: ExchangeModels.InboxItem,
        bucket: Bucket,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = [],
        surface: String = "exchange"
    ) -> String {
        let legacy = displayCardSubtitle(for: item, surface: surface)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !listSurfaceExcludesVisibleStatusCoach(surface) else {
            return legacy
        }

        let vs = visibleThreadStatus(for: item, bucket: bucket, pendingApprovalThreadIDs: pendingApprovalThreadIDs)

        if let subtitle = vs.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
            if legacy.isEmpty { return subtitle }
            if subtitle.caseInsensitiveCompare(legacy) == .orderedSame { return subtitle }
            if legacy.localizedCaseInsensitiveContains(subtitle) { return legacy }
            if subtitle.localizedCaseInsensitiveContains(legacy) { return subtitle }
            return subtitle
        }
        return legacy
    }

    // MARK: - ThreadView requester assessment

    /// How ``SecretaryThreadView`` presents the requester-side **Assessment** card so no-match threads do not surface internal second-half diagnostics.
    enum ThreadViewRequesterAssessmentMode: Equatable, Sendable {
        /// Omit the requester assessment card.
        case hidden
        /// Use fixed “no match found” copy instead of agency/qualifier lines (subject to ThreadView sparsity).
        case cleanNoMatch
        /// Show second-half-derived lines filtered by ``passesThreadViewAssessmentUXLinePolicy(_:)``.
        case rich
    }

    /// Picks assessment presentation using the same canonical status as ``visibleThreadStatus(for:)``.
    static func threadViewRequesterAssessmentMode(for detail: ExchangeModels.ThreadDetail) -> ThreadViewRequesterAssessmentMode {
        if latestPendingApproval(for: detail) != nil { return .rich }
        if hasActionableExternalOutboundDraft(in: detail) { return .rich }
        if let sh = secondHalfDisplay(for: detail), sh.hasProviderReception { return .rich }

        let vs = visibleThreadStatus(for: detail)
        let anchored = ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: detail.thread)

        switch vs.primary {
        case .noConfirmedMatch:
            return .cleanNoMatch
        case .potentialMatch:
            return anchored ? .rich : .hidden
        default:
            return .rich
        }
    }

    /// Filters assessment bullet lines that should never appear in normal ThreadView assessment surfaces.
    static func passesThreadViewAssessmentUXLinePolicy(_ raw: String) -> Bool {
        if isBlockedSystemArtifactText(raw) { return false }
        let lower = raw.lowercased()
        let banned = [
            "weak match so far",
            "has enough thread detail",
            "has enough exchange detail",
            "has enough public commercial",
            "thread detail to work with",
            "exchange detail to work with",
            "no viable match",
            "anchored yet",
            "not anchored",
            "no provider path is locked",
            "published seller surfaces",
            "surfaced candidate",
            "missing: no viable",
            "missing:no viable",
            "stance snapshot",
            "qualification tier"
        ]
        return !banned.contains(where: { lower.contains($0) })
    }

    // MARK: Resolvers (internals)

    private struct VisibleThreadInputs: Equatable {
        var completed: Bool
        var structuralFailure: Bool
        var approvalNeeded: Bool
        var actionableDraft: Bool
        var staleDraftReadyWithoutActionableDraft: Bool
        var sendingOutbound: Bool
        var artifactReviewSurface: Bool
        var inboundReplyEvidence: Bool
        var waitingAfterOutbound: Bool
        var anchoredOffer: Bool
        var anchoredProfileNoOffer: Bool
        var potentialMatch: Bool
        var noConfirmedMatch: Bool
        var clarification: Bool
        /// Provider inbound: second-half snapshot not written yet — card should acknowledge inbound immediately.
        var inboundAwaitingSecondHalfPreview: Bool
        /// Provider-side inbound second-half: needs facts / routing before any external reply; beats generic “reply received”.
        var providerInboundNeedsCoordinationInput: Bool
        var providerInboundCoordinationSubtitle: String?
        var discoveryProjectedGrade: ExchangeThreadDiscoveryGradeMetadata.ProjectedGrade?
    }

    private static func resolveVisibleThreadInputs(
        from detail: ExchangeModels.ThreadDetail
    ) -> VisibleThreadInputs {
        let delivery = detail.thread.delivery
        let sh = secondHalfDisplay(for: detail)

        let providerInboundCoordination = secondHalfProviderInboundNeedsCoordinationInput(sh, detail: detail)
        let providerInboundCoordinationSubtitle = providerInboundCoordinationSubtitleLines(sh)

        let approvalNeededRaw =
            latestPendingApproval(for: detail) != nil
            || {
                if case .awaitingApproval = detail.thread.state { return true }
                return false
            }()
            || delivery?.status == .pendingApproval
            || (sh?.placement == .needsApproval && sh?.boundary.requiresHumanApproval == true)

        /// When true, thread state still carries “approval” scaffolding but ThreadView should project reply/review, not an approval gate.
        let suppressInboundOnlyApprovalNoise = shouldSuppressProviderInboundApprovalCard(for: detail)

        let actionableDraft = hasActionableExternalOutboundDraft(in: detail)

        let approvalNeeded = approvalNeededRaw && !suppressInboundOnlyApprovalNoise

        let sendingOutbound = sendingOutboundIsTruthful(for: detail) && !providerInboundCoordination

        let inboundReplyEvidence =
            detailHasInboundReplyEvidence(detail, secondHalf: sh) && !providerInboundCoordination

        let hasOutboundEvidence = outboundSendEvidence(in: detail)
        let waitingAfterOutbound =
            isAwaitingResponse(detail) && !inboundReplyEvidence && hasOutboundEvidence && !providerInboundCoordination

        let artifactReviewSurface = {
            guard !approvalNeeded && !actionableDraft else { return false }
            guard let sh else { return false }
            let secondHalfWantsReview =
                sh.hasDecisionPacket
                || sh.hasRequesterReview
                || sh.placement == .decisionReady
                || sh.placement == .requesterReview
            guard secondHalfWantsReview else { return false }
            if sh.hasProviderReception { return true }
            return hasRecipientRoutingSurface(for: detail)
        }()

        let structuralFailure = structuralFailureEvidence(in: detail, secondHalf: sh)

        let offerAnchor = detail.selectedOfferID != nil
        let potentialRaw = potentialMatchEvidence(in: detail)
        let profileAnchor = profileOnlyAnchor(in: detail) && !offerAnchor && !potentialRaw

        let noConfirmedMatch =
            ({
                switch detail.thread.state {
                case .noViableMatch, .matchCandidatesWeak: return true
                default: return false
                }
            })() && !hasRecipientRoutingSurface(for: detail)

        let clarification = isClarification(detail)

        let completed = {
            switch detail.thread.state {
            case .resolved: return true
            default: return false
            }
        }()

        let staleDraftReadyWithoutActionableDraft = {
            if completed { return false }
            if case .draftReady = detail.thread.state {
                return !hasActionableExternalOutboundDraft(in: detail)
            }
            return false
        }()

        let inboundAwaitingSecondHalfPreview =
            detail.thread.metadata["inbound_thread"] == "true"
            && detailHasInboundReplyEvidence(detail, secondHalf: nil)
            && sh == nil

        let discoveryProjectedGrade: ExchangeThreadDiscoveryGradeMetadata.ProjectedGrade? = {
            guard case .matchCandidatesWeak = detail.thread.state else { return nil }
            return ExchangeUmbrellaDiscoveryGradeProjection.resolve(
                thread: detail.thread,
                context: .init(
                    activatedChildCount: detail.coordinationChildren.count,
                    strongestChildSourceRank: detail.coordinationChildren.first?.sourceRank
                )
            ).projectedGrade
        }()

        return VisibleThreadInputs(
            completed: completed,
            structuralFailure: structuralFailure && !completed,
            approvalNeeded: approvalNeeded && !completed,
            actionableDraft: actionableDraft && !completed,
            staleDraftReadyWithoutActionableDraft: staleDraftReadyWithoutActionableDraft,
            sendingOutbound: sendingOutbound && !completed,
            artifactReviewSurface: artifactReviewSurface && !completed,
            inboundReplyEvidence: inboundReplyEvidence && !completed,
            waitingAfterOutbound: waitingAfterOutbound && !completed && !approvalNeeded && !artifactReviewSurface && !actionableDraft,
            anchoredOffer: offerAnchor && !completed && !inboundReplyEvidence && !waitingAfterOutbound && !artifactReviewSurface && !actionableDraft && !approvalNeeded && !sendingOutbound,
            anchoredProfileNoOffer: profileAnchor && !completed && !inboundReplyEvidence && !waitingAfterOutbound && !artifactReviewSurface && !actionableDraft && !approvalNeeded && !sendingOutbound,
            potentialMatch: potentialRaw && !completed && !offerAnchor && !profileAnchor && !inboundReplyEvidence && !waitingAfterOutbound && !artifactReviewSurface && !actionableDraft && !approvalNeeded && !sendingOutbound,
            noConfirmedMatch: noConfirmedMatch && !completed && !potentialRaw && !offerAnchor && !profileAnchor,
            clarification: clarification && !completed && !structuralFailure,
            inboundAwaitingSecondHalfPreview: inboundAwaitingSecondHalfPreview && !completed,
            providerInboundNeedsCoordinationInput: providerInboundCoordination && !completed,
            providerInboundCoordinationSubtitle: providerInboundCoordination ? providerInboundCoordinationSubtitle : nil,
            discoveryProjectedGrade: discoveryProjectedGrade
        )
    }

    private static func resolveVisibleThreadInputs(
        from item: ExchangeModels.InboxItem,
        bucket: Bucket,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID>
    ) -> VisibleThreadInputs {
        let sh = secondHalfDisplay(for: item)

        let providerInboundCoordination = secondHalfProviderInboundNeedsCoordinationInput(sh, item: item)
        let providerInboundCoordinationSubtitle = providerInboundCoordinationSubtitleLines(sh)

        let approvalNeeded =
            item.hasPendingApproval
            || pendingApprovalThreadIDs.contains(item.threadID)
            || {
                if case .awaitingApproval = item.state { return true }
                return false
            }()
            || {
                if let sh, sh.placement == .needsApproval, sh.boundary.requiresHumanApproval { return true }
                return false
            }()

        let actionableDraft =
            item.hasActionableExternalOutboundDraft
            && ({
                switch item.state {
                case .sending: return false
                default: return true
                }
            })()

        let sendingOutbound = sendingOutboundIsTruthful(for: item) && !providerInboundCoordination

        let inboundReplyEvidence = inboxHasInboundReplyEvidence(item, secondHalf: sh) && !providerInboundCoordination

        let waitingRefined =
            ({
                switch item.state {
                case .awaitingResponse:
                    return !inboundReplyEvidence
                default:
                    return item.awaitingReply && !inboundReplyEvidence && hasOutboundEvidenceHeuristic(for: item)
                }
            })() && !providerInboundCoordination

        let artifactReviewSurface = {
            guard !approvalNeeded && !actionableDraft else { return false }
            guard let sh else { return false }
            let secondHalfWantsReview =
                sh.hasDecisionPacket
                || sh.hasRequesterReview
                || sh.placement == .decisionReady
                || sh.placement == .requesterReview
            guard secondHalfWantsReview else { return false }
            if sh.hasProviderReception { return true }
            return inboxHasDurableRoutingAnchor(for: item)
        }()

        let structuralFailure = inboxStructuralFailureEvidence(item)

        let offerAnchor = inboxAnchoredOfferEvidence(for: item)
        let potentialRaw = potentialMatchInboxEvidence(item)
        let profileAnchor = inboxProfileOnlyAnchor(item) && !offerAnchor && !potentialRaw

        let noConfirmedMatch: Bool = {
            switch item.state {
            case .noViableMatch:
                return true
            case .matchCandidatesWeak:
                return !inboxHasDurableRoutingAnchor(for: item)
            default:
                return false
            }
        }()

        let clarification = isClarification(item)

        let completed = {
            switch item.state {
            case .resolved: return true
            default: return false
            }
        }()

        let staleDraftReadyWithoutActionableDraft = {
            if completed { return false }
            if case .draftReady = item.state {
                return !item.hasActionableExternalOutboundDraft
            }
            return false
        }()

        let inboundAwaitingSecondHalfPreview =
            item.prefersInboundProviderCardTitleRewrite
            && nonEmpty(item.cardInboundRequesterPreview) != nil
            && sh == nil

        let discoveryProjectedGrade = item.discoveryProjectedGrade

        return VisibleThreadInputs(
            completed: completed,
            structuralFailure: structuralFailure && !completed,
            approvalNeeded: approvalNeeded && !completed,
            actionableDraft: actionableDraft && !completed && !approvalNeeded,
            staleDraftReadyWithoutActionableDraft: staleDraftReadyWithoutActionableDraft,
            sendingOutbound: sendingOutbound && !completed,
            artifactReviewSurface: artifactReviewSurface && !completed && !waitingRefined && !approvalNeeded && !actionableDraft,
            inboundReplyEvidence: inboundReplyEvidence && !completed,
            waitingAfterOutbound: waitingRefined && !completed && !approvalNeeded && !artifactReviewSurface && !actionableDraft,
            anchoredOffer: offerAnchor && !completed && !waitingRefined && !inboundReplyEvidence && !artifactReviewSurface && !actionableDraft && !approvalNeeded && !sendingOutbound,
            anchoredProfileNoOffer: profileAnchor && !completed && !waitingRefined && !inboundReplyEvidence && !artifactReviewSurface && !actionableDraft && !approvalNeeded && !sendingOutbound,
            potentialMatch: potentialRaw && !completed && !offerAnchor && !profileAnchor && !waitingRefined && !inboundReplyEvidence && !artifactReviewSurface && !actionableDraft && !approvalNeeded && !sendingOutbound,
            noConfirmedMatch: noConfirmedMatch && !completed && !potentialRaw && !offerAnchor && !profileAnchor,
            clarification: clarification && !completed && !structuralFailure,
            inboundAwaitingSecondHalfPreview: inboundAwaitingSecondHalfPreview && !completed,
            providerInboundNeedsCoordinationInput: providerInboundCoordination && !completed,
            providerInboundCoordinationSubtitle: providerInboundCoordination ? providerInboundCoordinationSubtitle : nil,
            discoveryProjectedGrade: discoveryProjectedGrade
        )
    }

    private static func outboundSendEvidence(in detail: ExchangeModels.ThreadDetail) -> Bool {
        if detail.thread.delivery?.status == .sent { return true }
        return detail.drafts.contains {
            $0.audience == .externalCounterparty && $0.status == .sent
        }
    }

    private static func hasOutboundEvidenceHeuristic(for item: ExchangeModels.InboxItem) -> Bool {
        switch item.state {
        case .awaitingResponse:
            return true
        default:
            break
        }
        let t = nonEmpty(item.deliveryStatusText)?.lowercased() ?? ""
        if t.contains("sent") && !t.contains("not sent") { return true }
        return item.awaitingReply && !({
            switch item.state {
            case .matchFound, .matchCandidatesWeak, .drafting:
                return true
            default:
                return false
            }
        }())
    }

    private static func structuralFailureEvidence(
        in detail: ExchangeModels.ThreadDetail,
        secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?
    ) -> Bool {
        if detail.thread.latestFailure != nil { return true }
        if ExchangeMessageDraft.hasActionableExternalOutboundDraft(in: detail.drafts),
           !ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: detail.thread) {
            #if DEBUG
            Swift.print(
                "[StructuralFailure] orphaned_actionable_external_draft_without_recipient_anchor thread=\(detail.thread.id.uuidString) (ignored for normal visible status; not a technical failure)"
            )
            #endif
        }
        if detail.thread.delivery?.status == .failed { return true }
        if let secondHalf, secondHalf.placement == .recovery || secondHalf.status.isBlocking {
            return true
        }

        switch detail.thread.state {
        case .blockedByDeliveryFailure, .blockedBySystemFailure:
            return true
        default:
            return false
        }
    }

    /// Inbox row: real coordination/delivery breakage only — **not** weak/no-match search outcomes.
    ///
    /// `ExchangeThread.hasFailure` / `InboxItem.hasFailure` treat `noViableMatch` and `matchCandidatesWeak` as
    /// “failure-shaped” for legacy cardography, but they are normal search states for visible status.
    private static func inboxStructuralFailureEvidence(
        _ item: ExchangeModels.InboxItem
    ) -> Bool {
        switch item.state {
        case .matchCandidatesWeak, .noViableMatch:
            return false
        default:
            break
        }

        if nonEmpty(item.latestFailureSummary) != nil { return true }
        if nonEmpty(item.failureWhatHappened) != nil { return true }

        if let sh = secondHalfDisplay(for: item),
           sh.placement == .recovery || sh.status.isBlocking {
            return true
        }

        switch item.state {
        case .blockedByDeliveryFailure, .blockedBySystemFailure:
            return true
        default:
            break
        }

        if let d = nonEmpty(item.deliveryStatusText)?.lowercased() {
            if d.contains("failed") { return true }
            if d.contains("couldn") && d.contains("send") { return true }
        }

        return false
    }

    private static func profileOnlyAnchor(in detail: ExchangeModels.ThreadDetail) -> Bool {
        if detail.selectedPublicProfileID != nil { return true }
        if detail.thread.selectedCounterpartyID != nil, detail.selectedOfferID == nil {
            return nonEmpty(selectedCounterpartyName(for: detail)) != nil
        }
        return false
    }

    private static func inboxProfileOnlyAnchor(_ item: ExchangeModels.InboxItem) -> Bool {
        if item.selectedPublicProfileID != nil { return true }
        if item.selectedOfferID != nil { return false }
        return nonEmpty(item.selectedCounterpartyName) != nil
    }

    private static func potentialMatchEvidence(in detail: ExchangeModels.ThreadDetail) -> Bool {
        if case .matchCandidatesWeak = detail.thread.state {
            let resolution = ExchangeUmbrellaDiscoveryGradeProjection.resolve(
                thread: detail.thread,
                context: .init(
                    activatedChildCount: detail.coordinationChildren.count,
                    strongestChildSourceRank: detail.coordinationChildren.first?.sourceRank
                )
            )
            if resolution.projectedGrade != .weak {
                return false
            }
        }

        switch detail.thread.state {
        case .matchCandidatesWeak:
            return true
        default:
            break
        }

        return hasMultipleComparePaths(for: detail)
    }

    private static func potentialMatchInboxEvidence(_ item: ExchangeModels.InboxItem) -> Bool {
        if let grade = item.discoveryProjectedGrade, grade != .weak {
            return false
        }
        switch item.state {
        case .matchCandidatesWeak:
            return true
        default:
            return item.candidateCount > 1
        }
    }

    private static func detailHasInboundReplyEvidence(
        _ detail: ExchangeModels.ThreadDetail,
        secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?
    ) -> Bool {
        if let secondHalf, secondHalf.hasProviderReception { return true }

        for turn in detail.turns where turn.kind == .replyReceived {
            let detailLine = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let raw: String = {
                if !detailLine.isEmpty { return detailLine }
                return turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            guard !raw.isEmpty else { continue }
            guard !isBlockedSystemArtifactText(raw) else { continue }
            return true
        }

        if detail.turns.contains(where: { $0.kind == .replyReceived }) {
            return false
        }

        let tid = detail.thread.id
        for inbox in detail.inboxItems where inbox.threadID == tid {
            switch inbox.processingState {
            case .reconciledIntoThread, .received, .deferred:
                break
            default:
                continue
            }

            let parts = [
                inbox.metadata["body_preview"],
                inbox.metadata["subject_preview"],
                inbox.visibleSummary
            ]

            var combined = ""
            for p in parts {
                let trimmed = (p ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                combined = String(trimmed.prefix(280))
                break
            }
            guard !combined.isEmpty else { continue }
            return true
        }

        return false
    }

    private static func inboxHasInboundReplyEvidence(
        _ item: ExchangeModels.InboxItem,
        secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?
    ) -> Bool {
        if let secondHalf, secondHalf.hasProviderReception { return true }
        return false
    }

    /// Durable routing/selection surface (matches ``ExchangeOutboundRecipientAnchor`` on thread rows).
    private static func hasRecipientRoutingSurface(for detail: ExchangeModels.ThreadDetail) -> Bool {
        ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: detail.thread)
    }

    /// List cards: offer/profile/counterparty id only (facade may echo a label without a durable id).
    private static func inboxHasDurableRoutingAnchor(for item: ExchangeModels.InboxItem) -> Bool {
        item.selectedOfferID != nil
            || item.selectedPublicProfileID != nil
            || item.selectedCounterpartyID != nil
    }

    /// Summary-row discovery result evidence (desk snapshot fields only; no thread hydration).
    static func hasSummaryDiscoveryResultEvidence(for item: ExchangeModels.InboxItem) -> Bool {
        if item.candidateCount > 0 { return true }
        if item.selectedCounterpartyID != nil { return true }
        return false
    }

    /// Offer anchor for visible status — selectedOfferID alone is not proof of a viable match.
    private static func inboxAnchoredOfferEvidence(for item: ExchangeModels.InboxItem) -> Bool {
        switch item.state {
        case .noViableMatch, .matchCandidatesWeak:
            return false
        case .matchFound:
            return item.selectedOfferID != nil && hasSummaryDiscoveryResultEvidence(for: item)
        default:
            return item.selectedOfferID != nil
        }
    }

    private static func discoveryProjectedVisibleStatus(
        _ grade: ExchangeThreadDiscoveryGradeMetadata.ProjectedGrade
    ) -> ExchangeVisibleThreadStatus? {
        guard let label = ExchangeUmbrellaDiscoveryGradeProjection.visibleStatusLabel(for: grade) else {
            return nil
        }
        let subtitle = ExchangeUmbrellaDiscoveryGradeProjection.visibleStatusSubtitle(for: grade)

        switch grade {
        case .strong:
            return ExchangeVisibleThreadStatus(
                primary: .pulledOffer,
                label: label,
                subtitle: subtitle,
                tone: .success,
                systemImage: "checkmark.seal"
            )
        case .moderate:
            return ExchangeVisibleThreadStatus(
                primary: .needsReview,
                label: label,
                subtitle: subtitle,
                tone: .warning,
                systemImage: "list.bullet.rectangle"
            )
        case .weak:
            return nil
        }
    }

    private static func renderVisibleThreadStatus(_ inputs: VisibleThreadInputs) -> ExchangeVisibleThreadStatus {
        func done(_ primary: ExchangeVisibleThreadStatusPrimary, _ label: String, _ subtitle: String?, _ tone: ExchangeVisibleThreadStatusTone, _ image: String)
            -> ExchangeVisibleThreadStatus {
            ExchangeVisibleThreadStatus(primary: primary, label: label, subtitle: subtitle, tone: tone, systemImage: image)
        }

        if inputs.completed {
            return done(.completed, "Completed", nil, .neutral, "checkmark.circle")
        }

        if inputs.structuralFailure {
            return done(.needsFix, "Blocked", "Something stopped this thread from moving forward.", .blocked, "exclamationmark.shield")
        }

        if inputs.inboundAwaitingSecondHalfPreview {
            return done(
                .replyReceived,
                "New message",
                "Unify is reviewing how you can respond.",
                .success,
                "tray.and.arrow.down"
            )
        }

        if inputs.providerInboundNeedsCoordinationInput && !inputs.actionableDraft {
            return done(
                .needsYourInput,
                "Needs your input",
                inputs.providerInboundCoordinationSubtitle
                    ?? "They asked something that needs your facts before Unify can reply.",
                .warning,
                "questionmark.circle"
            )
        }

        if inputs.approvalNeeded {
            return done(.approvalNeeded, "Needs your approval", "Review before anything goes out.", .warning, "checkmark.seal")
        }

        if inputs.actionableDraft {
            return done(.draftReady, "Draft ready", "You can edit or send once approved.", .warning, "doc.text")
        }

        if inputs.sendingOutbound {
            return done(.sending, "Sending…", "Your message is on its way.", .active, "paperplane.fill")
        }

        if inputs.inboundReplyEvidence {
            return done(.replyReceived, "Reply received", "Catch up with their latest message.", .success, "tray.and.arrow.down")
        }

        if inputs.waitingAfterOutbound {
            return done(.waitingForReply, "Waiting for reply", "Nothing from them yet.", .neutral, "clock")
        }

        if inputs.anchoredOffer {
            return done(.pulledOffer, "Match found", "Reviewing fit before anything goes out.", .success, "checkmark.seal")
        }

        if inputs.anchoredProfileNoOffer {
            // `subtitle` is ThreadView coaching only; list rows use `label` via `exchangeListStatusLabel`.
            return done(.pulledProfile, "Pulled profile", "Inspect the surfaced profile details next.", .success, "person.crop.square")
        }

        if let grade = inputs.discoveryProjectedGrade,
           let gradeStatus = discoveryProjectedVisibleStatus(grade) {
            return gradeStatus
        }

        if inputs.potentialMatch {
            return done(.potentialMatch, "Weak matches", "Review or refine before choosing.", .warning, "point.3.connected.trianglepath.dotted")
        }

        if inputs.noConfirmedMatch {
            return done(.noConfirmedMatch, "No match found", "Try refining the request.", .neutral, "circle.dashed")
        }

        if inputs.artifactReviewSurface {
            return done(.needsReviewArtifacts, "Needs your review", "There is a framed update to read before you decide.", .success, "text.book.closed")
        }

        if inputs.clarification {
            return done(.needsYourInput, "Needs your input", "Answer the missing prompt to continue.", .warning, "questionmark.circle")
        }

        if inputs.staleDraftReadyWithoutActionableDraft {
            return done(.needsReview, "Needs review", nil, .warning, "exclamationmark.circle")
        }

        return done(.openExchange, "Open", nil, .active, "arrow.right.circle")
    }

    static func bucket(
        for item: ExchangeModels.InboxItem,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = [],
        preferredThreadID: ExchangeThread.ID? = nil
    ) -> Bucket {
        if isTerminalNoMatchSearch(item) {
            #if DEBUG
            Swift.print(
                "[NoMatchProjectionPolicy] action=visibleNonOperational surface=bucket " +
                "threadID=\(item.threadID.uuidString)"
            )
            #endif
            return .searchResult
        }

        if let secondHalf = secondHalfDisplay(for: item) {
            switch secondHalf.placement {
            case .needsApproval, .needsInput:
                return .pending
                
            case .decisionReady, .requesterReview, .providerReception:
                return .searchResult
                
            case .activeCoordination, .currentFocus:
                return .active
                
            case .recovery:
                return .recovery
                
            case .completed, .none:
                break
            }
        }
        
        let hasPendingApproval = item.hasPendingApproval || pendingApprovalThreadIDs.contains(item.threadID)
        let needsClarification = item.needsClarification || {
            if case .needsClarification = item.state { return true }
            return false
        }()
        let hasMultipleCandidates = item.candidateCount > 1
        let hasFailure = item.hasFailure
        
        if item.threadID == preferredThreadID {
            switch item.state {
            case .drafting, .draftReady, .searching, .sending, .awaitingResponse:
                return .active
            case .needsClarification, .awaitingApproval:
                return .pending
            case .matchFound, .matchCandidatesWeak:
                return .searchResult
            case .blockedByDeliveryFailure, .declined, .stalled, .blockedBySystemFailure:
                return .recovery
            case .resolved:
                if ExchangeInboundOpenRouting.shouldKeepProviderDeskInThreadsHistory(
                    isInboundProviderDesk: item.isInboundProviderDesk,
                    hasFederatedInboundEnvelope: item.hasFederatedInboundEnvelope,
                    state: item.state,
                    hasFailure: item.hasFailure
                ) {
                    #if DEBUG
                    Swift.print(
                        "[ThreadsInboundVisibility] inbound_thread=true bucket=searchResult reason=provider_desk_resolved_preferred threadID=\(item.threadID.uuidString)"
                    )
                    #endif
                    return .searchResult
                }
                return .none
            case .noViableMatch:
                return .searchResult
            }
        }
        
        if hasPendingApproval || hasMultipleCandidates || needsClarification {
            return .pending
        }
        
        switch item.state {
        case .matchFound, .matchCandidatesWeak:
            return .searchResult

        case .noViableMatch:
            return .searchResult
            
        case .blockedByDeliveryFailure, .declined, .stalled, .blockedBySystemFailure:
            return .recovery
            
        case .drafting, .draftReady, .searching, .sending, .awaitingResponse:
            if hasFailure {
                return .recovery
            }

            let hasTrustSignal =
                !clean(item.selectedCounterpartyName).isEmpty ||
                !clean(item.trustPathSummary).isEmpty

            if hasTrustSignal {
                return .trusted
            }

            return .active
            
        case .needsClarification, .awaitingApproval:
            return .pending
            
        case .resolved:
            if ExchangeInboundOpenRouting.shouldKeepProviderDeskInThreadsHistory(
                isInboundProviderDesk: item.isInboundProviderDesk,
                hasFederatedInboundEnvelope: item.hasFederatedInboundEnvelope,
                state: item.state,
                hasFailure: hasFailure
            ) {
                #if DEBUG
                Swift.print(
                    "[ThreadsInboundVisibility] inbound_thread=true bucket=searchResult reason=provider_desk_resolved threadID=\(item.threadID.uuidString)"
                )
                #endif
                return .searchResult
            }
            return hasFailure ? .recovery : .none
        }
    }
    
    static func isPending(
        _ item: ExchangeModels.InboxItem,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = []
    ) -> Bool {
        if let secondHalf = secondHalfDisplay(for: item) {
            switch secondHalf.placement {
            case .needsInput, .needsApproval:
                return true
            default:
                break
            }
            
            if secondHalf.needsHumanAttention {
                return true
            }
        }
        
        if item.hasPendingApproval || pendingApprovalThreadIDs.contains(item.threadID) {
            return true
        }
        
        if item.candidateCount > 1 {
            return true
        }
        
        if item.needsClarification {
            return true
        }
        
        switch item.state {
        case .needsClarification, .awaitingApproval:
            return true
        default:
            return false
        }
    }
    
    static func isSearchResult(_ item: ExchangeModels.InboxItem) -> Bool {
        if let secondHalf = secondHalfDisplay(for: item) {
            switch secondHalf.placement {
            case .decisionReady, .requesterReview, .providerReception:
                return true
            default:
                break
            }
            
            if secondHalf.hasDecisionPacket || secondHalf.hasRequesterReview || secondHalf.hasProviderReception {
                return true
            }
        }
        
        switch item.state {
        case .matchFound, .matchCandidatesWeak:
            return true
        default:
            return false
        }
    }
    
    static func isRecovery(_ item: ExchangeModels.InboxItem) -> Bool {
        if let secondHalf = secondHalfDisplay(for: item) {
            if secondHalf.placement == .recovery {
                return true
            }
            
            if secondHalf.status.isBlocking && !secondHalf.needsHumanAttention {
                return true
            }
        }
        
        if item.needsClarification { return false }
        
        switch item.state {
        case .needsClarification,
                .matchFound,
                .matchCandidatesWeak,
                .noViableMatch:
            return false
            
        case .blockedByDeliveryFailure,
                .declined,
                .stalled,
                .blockedBySystemFailure:
            return true
            
        case .drafting,
                .draftReady,
                .searching,
                .awaitingApproval,
                .sending,
                .awaitingResponse,
                .resolved:
            return item.hasFailure
        }
    }
    
    static func isActive(
        _ item: ExchangeModels.InboxItem,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = []
    ) -> Bool {
        if let secondHalf = secondHalfDisplay(for: item) {
            switch secondHalf.placement {
            case .activeCoordination, .currentFocus:
                return true
            default:
                break
            }
            
            if secondHalf.canRunAutonomously && !secondHalf.needsHumanAttention {
                return true
            }
        }
        
        if item.hasFailure { return false }
        if item.hasPendingApproval || pendingApprovalThreadIDs.contains(item.threadID) { return false }
        if item.candidateCount > 1 { return false }
        if item.needsClarification { return false }
        
        switch item.state {
        case .drafting, .draftReady, .searching, .sending, .awaitingResponse:
            return true
        case .needsClarification,
                .matchFound,
                .matchCandidatesWeak,
                .noViableMatch,
                .awaitingApproval,
                .blockedByDeliveryFailure,
                .declined,
                .stalled,
                .resolved,
                .blockedBySystemFailure:
            return false
        }
    }
    
    static func isTrusted(
        _ item: ExchangeModels.InboxItem,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = []
    ) -> Bool {
        if let secondHalf = secondHalfDisplay(for: item) {
            if secondHalf.hasProviderReception || secondHalf.hasRequesterReview {
                return false
            }
        }
        
        if item.hasFailure { return false }
        if item.hasPendingApproval || pendingApprovalThreadIDs.contains(item.threadID) { return false }
        if item.candidateCount > 1 { return false }
        if item.needsClarification { return false }
        
        switch item.state {
        case .drafting, .draftReady, .searching, .sending, .awaitingResponse, .matchFound:
            let hasTrustSignal =
            !clean(item.selectedCounterpartyName).isEmpty ||
            !clean(item.trustPathSummary).isEmpty
            return hasTrustSignal
            
        case .needsClarification,
                .matchCandidatesWeak,
                .noViableMatch,
                .awaitingApproval,
                .blockedByDeliveryFailure,
                .declined,
                .stalled,
                .resolved,
                .blockedBySystemFailure:
            return false
        }
    }
    
    static func trustedPathPanelDisplay(
        from launch: SecretaryTrustView.TrustedPathLaunch,
        detail: ExchangeModels.ThreadDetail? = nil
    ) -> SecretaryTrustedPathPanelDisplay {
        let threadID = launch.linkedThreadID
        let nodeID = launch.trustedNodeID
        let nodeName = launch.trustedNodeDisplayName
        let sendable = detail.map { hasSendableSecondHalfGeneratedDraft(detail: $0) } ?? false
        if sendable, threadID != nil {
            return SecretaryTrustedPathPanelDisplay(
                title: launch.title,
                summary: launch.summary,
                relationshipLabel: "Known path",
                trustLabel: "Route context from thread history",
                activityLabel: "Active",
                examples: launch.examples,
                primaryTitle: "Send prepared message",
                secondaryTitle: "Open thread",
                threadID: threadID,
                sendPreparedDraftAvailable: true,
                trustedNodeID: nodeID,
                trustedNodeDisplayName: nodeName
            )
        }

        if threadID != nil {
            return SecretaryTrustedPathPanelDisplay(
                title: launch.title,
                summary: launch.summary,
                relationshipLabel: "Known path",
                trustLabel: "Route context from thread history",
                activityLabel: "Available",
                examples: launch.examples,
                primaryTitle: "Open thread",
                secondaryTitle: "Back to trust",
                threadID: threadID,
                sendPreparedDraftAvailable: false,
                trustedNodeID: nodeID,
                trustedNodeDisplayName: nodeName
            )
        }

        return SecretaryTrustedPathPanelDisplay(
            title: launch.title,
            summary: launch.summary,
            relationshipLabel: "Known path",
            trustLabel: "Trusted contact (no active thread yet)",
            activityLabel: "Available",
            examples: launch.examples,
            primaryTitle: "Ask Secretary",
            secondaryTitle: "Message",
            threadID: nil,
            sendPreparedDraftAvailable: false,
            trustComposerFallback: true,
            trustedNodeID: nodeID,
            trustedNodeDisplayName: nodeName
        )
    }

    /// True when a second-half generated draft exists, is actionable, has body text, and the thread has a selected counterparty.
    static func hasSendableSecondHalfGeneratedDraft(detail: ExchangeModels.ThreadDetail) -> Bool {
        guard detail.thread.selectedCounterpartyID != nil else { return false }
        return ExchangeFacade.pickSendableSecondHalfDraftForUserDirectedSend(
            drafts: detail.drafts,
            preferredDraftID: nil
        ) != nil
    }
    
    static func isClarification(_ item: ExchangeModels.InboxItem) -> Bool {
        if item.needsClarification { return true }
        if case .needsClarification = item.state { return true }
        return false
    }
    
    static func isWaiting(_ item: ExchangeModels.InboxItem) -> Bool {
        if case .awaitingResponse = item.state { return true }
        return item.awaitingReply
    }

    /// Unsent outbound counterparty drafts that still merit a “Draft ready” style surface (store-truth gate for UI).
    static func hasActionableExternalOutboundDraft(in detail: ExchangeModels.ThreadDetail) -> Bool {
        ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(
            in: detail.drafts,
            thread: detail.thread,
            turns: detail.turns
        )
    }

    /// List rows: façade-projected actionable outbound draft (aligned with ``hasActionableExternalOutboundDraft(in:)``).
    private static func userFacingPersistedOutboundDraft(for item: ExchangeModels.InboxItem) -> Bool {
        item.hasActionableExternalOutboundDraft
    }

    /// Detail screens: persisted actionable external outbound drafts only — never projection-only placeholders.
    private static func userFacingPersistedOutboundDraft(for detail: ExchangeModels.ThreadDetail) -> Bool {
        hasActionableExternalOutboundDraft(in: detail)
    }
    
    static func isAwaitingResponse(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        switch detail.thread.state {
        case .awaitingResponse:
            return true
        default:
            return false
        }
    }
    
    static func isJudgment(
        _ item: ExchangeModels.InboxItem,
        pendingApprovalThreadIDs: Set<ExchangeThread.ID> = []
    ) -> Bool {
        isPending(item, pendingApprovalThreadIDs: pendingApprovalThreadIDs)
    }
    
    // MARK: - Thread lane (social vs commercial)

    static func threadLane(for detail: ExchangeModels.ThreadDetail) -> ExchangeThreadLane {
        ExchangeThreadLaneResolver.lane(for: detail.thread)
    }

    static func isSocialConnectionThread(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        threadLane(for: detail) == .socialConnection
    }

    static func suppressesCommercialProviderPresentation(for detail: ExchangeModels.ThreadDetail) -> Bool {
        ExchangeThreadLaneResolver.skipsCommercialProviderSecondHalf(for: threadLane(for: detail))
    }

    static func socialConnectionSummary(for detail: ExchangeModels.ThreadDetail) -> String {
        if let name = selectedCounterpartyName(for: detail) {
            return "Profile connection with \(name)."
        }
        return "Social profile connection."
    }

    // MARK: - Second-half projection helpers
    
    static func secondHalfDisplay(
        for detail: ExchangeModels.ThreadDetail
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel? {
        guard let display = detail.secondHalfDisplay else { return nil }
        if suppressesCommercialProviderPresentation(for: detail),
           display.status.role.caseInsensitiveCompare(ExchangeSecondHalfRole.provider.displayTitle) == .orderedSame {
            return nil
        }
        return display
    }

    static func secondHalfDisplay(
        for item: ExchangeModels.InboxItem
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel? {
        item.secondHalfDisplay
    }

    private static func detailHasActiveOutboundOutboxSendingWork(in detail: ExchangeModels.ThreadDetail) -> Bool {
        detail.outboxItems.contains { ob in
            guard ob.threadID == detail.thread.id else { return false }
            guard ob.isActive else { return false }
            switch ob.deliveryState.phase {
            case .queued, .blockedByPrerequisite, .deferred, .sending:
                return true
            default:
                return false
            }
        }
    }

    /// Inbox rows lack outbox truth; veto provider coordination only on **strong** outbound signals.
    /// `deliveryStatusText == "Sending now"` mirrors ``ExchangeFacade.deliveryStatusText`` for `.sending`, but without
    /// a durable routing anchor or sendable draft it can be stale alongside provider needs-input — do not suppress.
    private static func inboxOutboundPipelineSuppressesProviderCoordination(_ item: ExchangeModels.InboxItem) -> Bool {
        let t = nonEmpty(item.deliveryStatusText)?.lowercased() ?? ""
        if t.contains("queued") { return true }
        if t.contains("sent"), !t.contains("not sent") { return true }
        if case .awaitingResponse = item.state, hasOutboundEvidenceHeuristic(for: item) {
            return true
        }
        if t.contains("sending now") {
            return item.hasActionableExternalOutboundDraft || inboxHasDurableRoutingAnchor(for: item)
        }
        return false
    }

    /// Provider-side inbound: second half says the local user must supply facts/routing before an external reply.
    private static func secondHalfProviderInboundNeedsCoordinationInput(
        _ sh: ExchangeSecondHalfUIAdapter.DisplayModel?,
        detail: ExchangeModels.ThreadDetail
    ) -> Bool {
        guard let sh else { return false }
        guard sh.status.role.caseInsensitiveCompare(ExchangeSecondHalfRole.provider.displayTitle) == .orderedSame else {
            return false
        }
        if outboundSendEvidence(in: detail) { return false }
        if detailHasActiveOutboundOutboxSendingWork(in: detail) { return false }

        let hasSendableOutbound = hasActionableExternalOutboundDraft(in: detail)

        if sh.placement == .needsInput { return true }
        if sh.agencyPhase == .needsUserInput { return true }
        if sh.nextMove?.needsUserInput == true { return true }
        if sh.nextMove?.actionRaw == ExchangeSecondHalfAction.requestUserInput.rawValue { return true }

        if sh.needsHumanAttention && !hasSendableOutbound { return true }
        return false
    }

    private static func secondHalfProviderInboundNeedsCoordinationInput(
        _ sh: ExchangeSecondHalfUIAdapter.DisplayModel?,
        item: ExchangeModels.InboxItem
    ) -> Bool {
        guard let sh else { return false }
        guard sh.status.role.caseInsensitiveCompare(ExchangeSecondHalfRole.provider.displayTitle) == .orderedSame else {
            return false
        }

        let hasSendableOutbound = item.hasActionableExternalOutboundDraft && inboxHasDurableRoutingAnchor(for: item)

        let needsCoordination =
            sh.placement == .needsInput
            || sh.agencyPhase == .needsUserInput
            || sh.nextMove?.needsUserInput == true
            || sh.nextMove?.actionRaw == ExchangeSecondHalfAction.requestUserInput.rawValue
            || (sh.needsHumanAttention && !hasSendableOutbound)

        guard needsCoordination else { return false }
        if inboxOutboundPipelineSuppressesProviderCoordination(item) { return false }
        return true
    }

    private static func providerInboundCoordinationSubtitleLines(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel?
    ) -> String? {
        guard let display else { return nil }
        let facts = cleanedList(display.operatingContext.userFacingMissingFacts)
        guard !facts.isEmpty else { return nil }
        let joined = facts.prefix(5).joined(separator: ", ")
        return "Needs \(joined)."
    }

    /// “Sending” must reflect a real send attempt (outbox / in-flight delivery / prior sent outbound), not a stuck `.sending` state.
    private static func sendingOutboundIsTruthful(for detail: ExchangeModels.ThreadDetail) -> Bool {
        let rawSending: Bool = {
            if case .sending = detail.thread.state { return true }
            return detail.thread.delivery?.status == .sending
        }()
        guard rawSending else { return false }
        if outboundSendEvidence(in: detail) { return true }
        return detailHasActiveOutboundOutboxSendingWork(in: detail)
    }

    /// Inbox list: infer send-in-flight only from card-facing delivery copy + `.sending` state (no outbox on `InboxItem`).
    private static func sendingOutboundIsTruthful(for item: ExchangeModels.InboxItem) -> Bool {
        guard case .sending = item.state else { return false }
        let t = nonEmpty(item.deliveryStatusText)?.lowercased() ?? ""
        if t.contains("ready to send") { return false }
        if t.contains("waiting for approval") { return false }
        if t.contains("no external action") { return false }
        if t.contains("prepared locally") && !t.contains("sending") { return false }
        return t.contains("sending") || t.contains("sent")
    }
    
    static func secondHalfHasPriority(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel?
    ) -> Bool {
        guard let display else { return false }
        
        switch display.placement {
        case .none:
            return false
            
        case .needsInput,
                .needsApproval,
                .providerReception,
                .requesterReview,
                .activeCoordination,
                .decisionReady,
                .recovery,
                .completed,
                .currentFocus:
            return true
        }
    }
    
    static func secondHalfPrimaryCTA(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel,
        fallback: String = "Open",
        persistedActionableExternalOutboundDraft: Bool = false
    ) -> String {
        if let explicit = nonEmpty(display.plain.primaryCTA), explicit.lowercased() != "open thread" {
            return explicit
        }
        if let primary = display.buttons.first(where: { $0.prominence == .primary }) {
            return primary.title
        }

        switch display.agencyPhase ?? .unknown {
        case .finalReviewReady,
             .providerAnswerReceived:
            return "Review"
        case .needsUserApproval:
            return "Approve"
        case .needsUserInput:
            return "Review"
        case .clarificationReady:
            return "Clarify"
        case .providerClarificationDraftReady:
            return "Review draft"
        case .clarificationSent,
             .awaitingProviderAnswer:
            return "Open thread"
        default:
            break
        }
        
        if display.hasDecisionPacket { return "Review" }
        if display.hasProviderReception { return "Review" }
        if display.hasRequesterReview { return "Review" }
        if persistedActionableExternalOutboundDraft { return "Review draft" }
        if display.needsHumanAttention { return "Review" }
        
        return fallback
    }
    
    static func secondHalfPrimaryIcon(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel,
        fallback: String = "arrow.right",
        persistedActionableExternalOutboundDraft: Bool = false
    ) -> String {
        if display.hasDecisionPacket { return "checkmark.seal" }
        if display.hasProviderReception { return "tray.and.arrow.down" }
        if display.hasRequesterReview { return "rectangle.and.text.magnifyingglass" }
        if persistedActionableExternalOutboundDraft { return "doc.text" }
        if display.needsHumanAttention { return "exclamationmark.circle" }
        if display.canRunAutonomously { return "sparkles" }
        if display.isTerminal { return "checkmark.circle" }
        
        return fallback
    }
    
    static func secondHalfBoundaryLine(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> String? {
        nonEmpty(display.boundary.externalEffectLine)
        ?? nonEmpty(display.boundary.reason)
    }
    
    static func secondHalfNextMoveLine(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> String? {
        if let plain = nonEmpty(display.plain.followUpReason) {
            return plain
        }
        let raw: String? = {
            if display.agencyPhase != .unknown {
                return nonEmpty(display.agencyPhaseDetail) ?? nonEmpty(display.agencyPhaseTitle)
            }
            return nonEmpty(display.nextMove?.title)
                ?? nonEmpty(display.actionTitle)
                ?? nonEmpty(display.recommendation)
                ?? nonEmpty(display.status.state)
        }()
        guard let raw else { return nil }
        return nonEmpty(
            ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                raw,
                field: .body,
                fallback: "Open thread"
            )
        )
    }
    
    static func secondHalfSummaryLine(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> String? {
        if let plain = nonEmpty(display.plain.plainOneLineSummary) {
            return plain
        }
        let raw: String? = {
            if display.agencyPhase != .unknown {
                return nonEmpty(display.agencyPhaseDetail) ?? nonEmpty(display.agencyPhaseTitle)
            }
            return nonEmpty(display.summary)
                ?? nonEmpty(display.hero.statusLine)
                ?? nonEmpty(display.subtitle)
                ?? nonEmpty(display.recommendation)
        }()
        guard let raw else { return nil }
        let cleaned = ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            raw,
            field: .body,
            fallback: ""
        )
        return nonEmpty(cleaned)
    }

    static func secretaryMovementLine(
        for display: ExchangeSecondHalfUIAdapter.DisplayModel,
        persistedActionableExternalOutboundDraft: Bool = false
    ) -> SecretaryMovementLine {
        if display.agencyPhase != .unknown {
            let title = nonEmpty(display.agencyPhaseTitle) ?? "Secretary movement"
            let detail = nonEmpty(display.agencyPhaseDetail)
                ?? nonEmpty(display.summary)
                ?? nonEmpty(display.hero.statusLine)
                ?? "The secretary is carrying this thread forward."
            return SecretaryMovementLine(
                title: title,
                detail: detail,
                systemImage: movementSystemImage(for: display.agencyPhase ?? .unknown)
            )
        }

        if display.boundary.requiresHumanApproval || display.needsHumanAttention {
            return SecretaryMovementLine(
                title: "Needs your approval before sending",
                detail: nonEmpty(display.boundary.reason)
                    ?? nonEmpty(display.nextMove?.rationale)
                    ?? "The secretary reached the approval boundary and paused.",
                systemImage: "checkmark.seal"
            )
        }

        if let boundary = secondHalfBoundaryLine(display), display.status.isBlocking {
            return SecretaryMovementLine(
                title: "Blocked",
                detail: boundary,
                systemImage: "exclamationmark.shield"
            )
        }

        if persistedActionableExternalOutboundDraft {
            return SecretaryMovementLine(
                title: "Draft is ready",
                detail: "A prepared draft is available for review.",
                systemImage: "square.and.pencil"
            )
        }

        return SecretaryMovementLine(
            title: "Secretary movement",
            detail: secondHalfSummaryLine(display)
                ?? "The secretary is tracking this path.",
            systemImage: display.canRunAutonomously ? "sparkles" : "clock"
        )
    }

    static func secretaryMovementLine(
        for item: ExchangeModels.InboxItem
    ) -> SecretaryMovementLine {
        if let secondHalf = secondHalfDisplay(for: item) {
            return secretaryMovementLine(
                for: secondHalf,
                persistedActionableExternalOutboundDraft: userFacingPersistedOutboundDraft(for: item)
            )
        }

        if item.hasPendingApproval {
            return SecretaryMovementLine(
                title: "Needs your approval before sending",
                detail: nonEmpty(item.requiresAttentionReason)
                    ?? nonEmpty(item.nextStepText)
                    ?? "A prepared move is waiting for your decision.",
                systemImage: "checkmark.seal"
            )
        }

        if item.hasFailure {
            return SecretaryMovementLine(
                title: "Blocked",
                detail: failureWhatHappened(for: item),
                systemImage: "exclamationmark.shield"
            )
        }

        if case .awaitingResponse = item.state {
            return SecretaryMovementLine(
                title: "Waiting for reply",
                detail: "The secretary is waiting for the counterparty response.",
                systemImage: "clock"
            )
        }

        return SecretaryMovementLine(
            title: "Secretary movement",
            detail: activityLatestMovement(for: item),
            systemImage: "sparkles"
        )
    }

    static func secretaryMovementLine(
        for detail: ExchangeModels.ThreadDetail,
        situation: ExchangeThreadSituation? = nil
    ) -> SecretaryMovementLine {
        if let situation {
            return secretaryMovementLine(for: situation)
        }

        if let secondHalf = secondHalfDisplay(for: detail) {
            return secretaryMovementLine(
                for: secondHalf,
                persistedActionableExternalOutboundDraft: userFacingPersistedOutboundDraft(for: detail)
            )
        }

        if let failure = detail.thread.latestFailure {
            return SecretaryMovementLine(
                title: "Blocked",
                detail: failure.whatHappened,
                systemImage: "exclamationmark.shield"
            )
        }

        if case .awaitingResponse = detail.thread.state {
            return SecretaryMovementLine(
                title: "Waiting for reply",
                detail: "The secretary is waiting for the counterparty response.",
                systemImage: "clock"
            )
        }

        return SecretaryMovementLine(
            title: "Secretary movement",
            detail: threadHeroSummary(detail),
            systemImage: "sparkles"
        )
    }

    static func secretaryMovementLine(
        for situation: ExchangeThreadSituation
    ) -> SecretaryMovementLine {
        if let hold = nonEmpty(situation.autonomyHoldLine) {
            return SecretaryMovementLine(
                title: "Blocked",
                detail: hold,
                systemImage: "lock.shield"
            )
        }

        if let phase = nonEmpty(situation.agencyPhaseTitle) {
            return SecretaryMovementLine(
                title: phase,
                detail: nonEmpty(situation.agencyPhaseDetail)
                    ?? nonEmpty(situation.stateSummary)
                    ?? "The secretary is tracking this thread.",
                systemImage: "sparkles"
            )
        }

        if situation.hasPendingApproval {
            return SecretaryMovementLine(
                title: "Needs your approval before sending",
                detail: "A prepared move is waiting for your decision.",
                systemImage: "checkmark.seal"
            )
        }

        return SecretaryMovementLine(
            title: "Secretary movement",
            detail: nonEmpty(situation.stateSummary) ?? "The secretary is tracking this thread.",
            systemImage: "sparkles"
        )
    }

    private static func movementSystemImage(
        for phase: ExchangeSecondHalfUIAdapter.AgencyPhase
    ) -> String {
        switch phase {
        case .evaluatingResult:
            return "scope"
        case .clarificationReady, .providerClarificationDraftReady:
            return "square.and.pencil"
        case .clarificationSent, .awaitingProviderAnswer:
            return "clock"
        case .providerAnswerReceived:
            return "tray.and.arrow.down"
        case .finalReviewReady:
            return "checkmark.seal"
        case .needsUserApproval:
            return "checkmark.seal"
        case .needsUserInput:
            return "questionmark.circle"
        case .blocked, .failed, .stalled:
            return "exclamationmark.shield"
        case .completed:
            return "checkmark.circle"
        case .activeCoordination, .unknown:
            return "sparkles"
        }
    }
    
    static func secondHalfDraftPreview(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> String? {
        guard let draft = display.draft else { return nil }
        
        if let subject = nonEmpty(draft.subject),
           let body = nonEmpty(draft.bodyPreview) {
            return "\(subject)\n\(body)"
        }
        
        return nonEmpty(draft.bodyPreview)
        ?? nonEmpty(draft.subject)
    }
    
    static func secondHalfExecutionDisplay(
        for display: ExchangeSecondHalfUIAdapter.DisplayModel,
        fallbackTitle: String,
        fallbackBoundary: String,
        persistedActionableExternalOutboundDraft: Bool = false,
        statusLabel: String
    ) -> SecretaryExecutionDisplay {
        let stages = display.activitySteps.map { step in
            SecretaryExecutionStageDisplay(
                title: step.title,
                subtitle: step.detail ?? "",
                status: executionStageStatus(from: step.status)
            )
        }
        
        return SecretaryExecutionDisplay(
            title: nonEmpty(display.hero.title) ?? nonEmpty(display.title) ?? fallbackTitle,
            summary: nonEmpty(display.hero.statusLine)
            ?? nonEmpty(display.summary)
            ?? nonEmpty(display.recommendation)
            ?? "The secretary is carrying this second-half coordination path.",
            badgeTitle: statusLabel,
            boundary: secondHalfBoundaryLine(display) ?? fallbackBoundary,
            nextMove: secondHalfNextMoveLine(display) ?? "Open the thread.",
            primaryActionTitle: secondHalfPrimaryCTA(
                display,
                persistedActionableExternalOutboundDraft: persistedActionableExternalOutboundDraft
            ),
            primarySystemImage: secondHalfPrimaryIcon(
                display,
                persistedActionableExternalOutboundDraft: persistedActionableExternalOutboundDraft
            ),
            secondaryActionTitle: "Details",
            secondarySystemImage: "list.bullet.rectangle",
            currentStageTitle: nonEmpty(display.agencyPhaseTitle)
            ?? nonEmpty(display.nextMove?.title)
            ?? nonEmpty(display.status.state)
            ?? nonEmpty(display.stateLabel)
            ?? "Second-half coordination",
            currentStageSubtitle: nonEmpty(display.agencyPhaseDetail)
            ?? nonEmpty(display.nextMove?.rationale)
            ?? nonEmpty(display.hero.statusLine)
            ?? nonEmpty(display.summary)
            ?? "The secretary is qualifying, framing, or moving the opportunity forward.",
            stages: stages.isEmpty
            ? [
                SecretaryExecutionStageDisplay(
                    title: nonEmpty(display.status.state) ?? "Second-half coordination",
                    subtitle: nonEmpty(display.summary) ?? "The secretary is holding this coordination path.",
                    status: display.isTerminal ? .complete : .active
                )
            ]
            : stages
        )
    }
    
    static func executionStageStatus(
        from status: ExchangeSecondHalfUIAdapter.ActivityStep.Status
    ) -> SecretaryExecutionStageDisplay.Status {
        switch status {
        case .pending:
            return .pending
        case .active:
            return .active
        case .completed:
            return .complete
        case .blocked:
            return .failed
        }
    }
    
    // MARK: - Common thread text
    
    /// Primary card title: user request / captured text (see `ExchangeThreadCardTitleProjection` + `listThreads`).
    static func userFacingPrimaryCardTitle(
        for item: ExchangeModels.InboxItem,
        surface: String = "threads"
    ) -> String {
        let pick = ExchangeThreadCardTitleProjection.displayTitleForInboxItem(item, surface: surface)
        return ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            pick.title,
            field: .title,
            fallback: "Thread"
        )
    }

    static func displayTitle(for item: ExchangeModels.InboxItem, surface: String = "threads") -> String {
        userFacingPrimaryCardTitle(for: item, surface: surface)
    }

    /// Card subtitle / status line under the title (state-first; does not echo machine interpretation as a title).
    static func displayCardSubtitle(for item: ExchangeModels.InboxItem, surface: String = "threads") -> String {
        let primary = userFacingPrimaryCardTitle(for: item, surface: surface)
        return ExchangeThreadCardTitleProjection.inboxCardSubtitle(
            for: item,
            primaryTitle: primary,
            surface: surface
        )
    }
    
    static func pendingReason(for item: ExchangeModels.InboxItem) -> String {
        let resolved: String = {
            if let secondHalf = secondHalfDisplay(for: item),
               secondHalf.needsHumanAttention || secondHalf.placement == .needsInput || secondHalf.placement == .needsApproval {
                return nonEmpty(secondHalf.nextMove?.rationale)
                    ?? nonEmpty(secondHalf.escalationReason)
                    ?? nonEmpty(secondHalf.summary)
                    ?? nonEmpty(secondHalf.recommendation)
                    ?? "Needs your reply."
            }

            if item.hasPendingApproval {
                if item.hasActionableExternalOutboundDraft {
                    return nonEmpty(item.draftedBodyPreview)
                        ?? "A draft is ready for your review before anything goes out."
                }
                return "Needs your approval before anything goes outward."
            }

            if item.candidateCount > 1 {
                return nonEmpty(item.requiresAttentionReason)
                    ?? "A few possible paths were found. Pick the one you want."
            }

            if let q = nonEmpty(item.clarificationPrompt) {
                return q
            }

            if let reason = nonEmpty(item.requiresAttentionReason) {
                return reason
            }

            if let next = nonEmpty(item.nextStepText) {
                return next
            }

            return "This thread is waiting on you."
        }()

        let bodySource: String = {
            if let secondHalf = secondHalfDisplay(for: item),
               secondHalf.needsHumanAttention || secondHalf.placement == .needsInput || secondHalf.placement == .needsApproval {
                if nonEmpty(secondHalf.nextMove?.rationale) != nil { return "secondHalfRationale" }
                if nonEmpty(secondHalf.escalationReason) != nil { return "escalation" }
                if nonEmpty(secondHalf.summary) != nil { return "summary" }
                return "recommendation"
            }
            if item.hasPendingApproval, item.hasActionableExternalOutboundDraft,
               nonEmpty(item.draftedBodyPreview) != nil { return "draftPreview" }
            return "fallback"
        }()

        let vsFallback = visibleThreadStatus(for: item, bucket: bucket(for: item))
        let cleaned = ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            resolved,
            field: .body,
            fallback: nonEmpty(vsFallback.subtitle) ?? vsFallback.label
        )
        #if DEBUG
        SecretaryDisplayCleanLog.log(
            surface: "dashboard",
            titleSource: "n/a",
            bodySource: bodySource,
            strippedInternal: cleaned != resolved
        )
        #endif
        return cleaned
    }
    
    static func approvalDecisionType(for item: ExchangeModels.InboxItem) -> String {
        if let secondHalf = secondHalfDisplay(for: item) {
            if secondHalf.hasDecisionPacket { return "Decision" }
            if secondHalf.hasProviderReception { return "New message" }
            if secondHalf.hasRequesterReview { return "Review" }
            if userFacingPersistedOutboundDraft(for: item) { return "Draft review" }
            if secondHalf.needsHumanAttention { return "Review" }
        }
        
        if item.hasPendingApproval { return "Review" }
        if item.candidateCount > 1 { return "Choose" }
        if isClarification(item) { return "Need Detail" }
        return "Pending"
    }
    
    static func pendingCTA(for item: ExchangeModels.InboxItem) -> String {
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.needsHumanAttention || secondHalf.placement == .needsInput || secondHalf.placement == .needsApproval {
            return secondHalfPrimaryCTA(
                secondHalf,
                fallback: "Review",
                persistedActionableExternalOutboundDraft: userFacingPersistedOutboundDraft(for: item)
            )
        }
        
        if item.hasPendingApproval { return "Review draft" }
        if item.candidateCount > 1 { return "Open thread" }
        if isClarification(item) { return "Answer" }
        return "Open"
    }
    
    static func pendingIcon(for item: ExchangeModels.InboxItem) -> String {
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.needsHumanAttention || secondHalf.placement == .needsInput || secondHalf.placement == .needsApproval {
            return secondHalfPrimaryIcon(
                secondHalf,
                fallback: "exclamationmark.circle",
                persistedActionableExternalOutboundDraft: userFacingPersistedOutboundDraft(for: item)
            )
        }
        
        if item.hasPendingApproval { return "checkmark.seal" }
        if item.candidateCount > 1 { return "arrow.right" }
        if isClarification(item) { return "questionmark.circle" }
        return "arrow.right"
    }
    
    static func searchResultBadge(for item: ExchangeModels.InboxItem) -> String {
        visibleThreadStatus(for: item, bucket: bucket(for: item)).label
    }
    
    static func searchResultPrimaryLine(for item: ExchangeModels.InboxItem) -> String {
        if let discoveryLine = discoveryCandidateReviewPrimaryLine(for: item) {
            return ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                discoveryLine,
                field: .body,
                fallback: discoveryLine
            )
        }

        let vs = visibleThreadStatus(for: item, bucket: bucket(for: item))
        if let secondHalf = secondHalfDisplay(for: item) {
            let raw = secondHalfSummaryLine(secondHalf)
                ?? nonEmpty(secondHalf.requesterReview?.subtitle)
                ?? nonEmpty(secondHalf.providerReception?.subtitle)
                ?? nonEmpty(secondHalf.decision?.summary)
            if let raw, !raw.isEmpty {
                return ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                    raw,
                    field: .body,
                    fallback: nonEmpty(vs.subtitle) ?? vs.label
                )
            }
        }

        let resolved = firstNonEmpty(
            item.visibleSummary,
            item.outcomeStatusText,
            item.selectedMatchSummary,
            vs.subtitle,
            fallback: ""
        )
        return ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            resolved,
            field: .body,
            fallback: nonEmpty(vs.subtitle) ?? vs.label
        )
    }
    
    static func searchResultBoundaryLine(for item: ExchangeModels.InboxItem) -> String {
        func s(_ raw: String) -> String {
            ExchangeUserFacingCopySanitizer.sanitizeOrFallback(raw, field: .subtitle, fallback: "Private.")
        }

        if let secondHalf = secondHalfDisplay(for: item),
           let boundary = secondHalfBoundaryLine(secondHalf) {
            return s(boundary)
        }

        switch item.state {
        case .matchFound:
            return s("Nothing sent. A found path is ready inside your boundary.")
        case .matchCandidatesWeak:
            return s("Nothing sent. Options are still inside your boundary.")
        case .noViableMatch:
            return s("Nothing sent. The current search did not produce a viable path.")
        default:
            return s("Nothing has been sent. This is still inside your boundary.")
        }
    }
    
    static func trustedBadge(for item: ExchangeModels.InboxItem) -> String {
        if let secondHalf = secondHalfDisplay(for: item),
           let trust = nonEmpty(secondHalf.operatingContext.trust) {
            return trust
        }
        return visibleThreadStatus(for: item, bucket: bucket(for: item)).label
    }

    static func trustedSecondaryLine(for item: ExchangeModels.InboxItem) -> String {
        let raw: String = {
            if let secondHalf = secondHalfDisplay(for: item) {
                return nonEmpty(secondHalf.operatingContext.postureSummary)
                    ?? nonEmpty(secondHalf.operatingContext.trust)
                    ?? nonEmpty(secondHalf.status.readiness)
                    ?? nonEmpty(secondHalf.summary)
                    ?? "A second-half relationship or trust context is visible on this thread."
            }

            return firstNonEmpty(
                item.selectedMatchWhy,
                item.trustPathSummary,
                item.subtitle,
                fallback: "A route context is visible on this thread."
            )
        }()
        return ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            raw,
            field: .body,
            fallback: ""
        )
    }
    
    static func trustedPrimaryLine(for item: ExchangeModels.InboxItem) -> String {
        firstNonEmpty(
            item.selectedCounterpartyName,
            item.title,
            fallback: "Untitled thread"
        )
    }
    
    static func recoveryBadge(for item: ExchangeModels.InboxItem) -> String {
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.placement == .recovery || secondHalf.status.isBlocking {
            return visibleThreadStatus(for: item, bucket: bucket(for: item)).label
        }

        switch item.state {
        case .blockedByDeliveryFailure:
            return "Delivery"
        case .declined:
            return "Declined"
        case .stalled:
            return "Stalled"
        case .blockedBySystemFailure:
            return "System"
        default:
            return "Recovery"
        }
    }
    
    static func failureWhatHappened(for item: ExchangeModels.InboxItem) -> String {
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.placement == .recovery || secondHalf.status.isBlocking {
            return nonEmpty(secondHalf.summary)
                ?? nonEmpty(secondHalf.hero.statusLine)
                ?? nonEmpty(secondHalf.escalationReason)
                ?? "The second-half coordination path is blocked or needs recovery."
        }

        return nonEmpty(item.failureWhatHappened)
            ?? nonEmpty(item.latestFailureSummary)
            ?? nonEmpty(item.requiresAttentionReason)
            ?? "The thread encountered a failure or stall that prevented normal progress."
    }

    static func failureWhatDidNotHappen(for item: ExchangeModels.InboxItem) -> String {
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.placement == .recovery || secondHalf.status.isBlocking {
            return nonEmpty(secondHalf.boundary.externalEffectLine)
                ?? nonEmpty(secondHalf.boundary.reason)
                ?? "The intended second-half move did not safely complete."
        }

        return nonEmpty(item.failureWhatDidNotHappen)
            ?? {
                if item.hasPendingApproval {
                    return "No external movement happened because the thread remained bounded at approval."
                }
                if let delivery = nonEmpty(item.deliveryStatusText),
                   delivery.lowercased().contains("failed") {
                    return "The intended outward movement did not complete successfully."
                }
                return "The thread did not complete the intended move."
            }()
    }

    static func failureExternalEffect(for item: ExchangeModels.InboxItem) -> String {
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.placement == .recovery || secondHalf.status.isBlocking {
            return secondHalfBoundaryLine(secondHalf)
                ?? "No safe external effect is confirmed from the second-half path."
        }

        return nonEmpty(item.deliveryStatusText) ?? "No clear external change is recorded."
    }

    static func failureNextMove(for item: ExchangeModels.InboxItem) -> String {
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.placement == .recovery || secondHalf.status.isBlocking {
            return secondHalfNextMoveLine(secondHalf)
                ?? nonEmpty(secondHalf.actionTitle)
                ?? "Open the thread and choose the recovery move."
        }

        return nonEmpty(item.failureNextMove)
            ?? nonEmpty(item.nextStepText)
            ?? "Open the thread, inspect the failure path, and choose the next recovery move."
    }
    
    static func recoveryBoundaryLine(for item: ExchangeModels.InboxItem) -> String {
        firstNonEmpty(
            item.failureWhatDidNotHappen,
            item.deliveryStatusText,
            fallback: "No external change is clearly recorded yet."
        )
    }
    
    static func boundaryLine(for item: ExchangeModels.InboxItem) -> String {
        func sanitizeBoundary(_ raw: String) -> String {
            ExchangeUserFacingCopySanitizer.sanitizeOrFallback(raw, field: .subtitle, fallback: "Private.")
        }

        if let secondHalf = secondHalfDisplay(for: item),
           let boundary = secondHalfBoundaryLine(secondHalf) {
            return sanitizeBoundary(boundary)
        }

        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.agencyPhase == .providerClarificationDraftReady {
            if item.hasActionableExternalOutboundDraft {
                return sanitizeBoundary(
                    "Draft ready. Review and send — nothing has reached the provider yet."
                )
            }
            return sanitizeBoundary(
                "Nothing has reached the provider yet. Finish review when your draft appears."
            )
        }

        // Waiting on a reply: never label as “nothing sent” unless transport actually moved.
        if isWaiting(item) {
            if let delivery = nonEmpty(item.deliveryStatusText) {
                let trimmed = delivery.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = trimmed.lowercased()
                if lower.hasPrefix("sent") {
                    return sanitizeBoundary("\(trimmed). Waiting on the other side.")
                }
                return sanitizeBoundary(trimmed)
            }
            return sanitizeBoundary("Sent. Waiting on the other side.")
        }

        if let delivery = nonEmpty(item.deliveryStatusText) {
            return sanitizeBoundary(delivery)
        }

        if item.hasPendingApproval {
            return sanitizeBoundary("Nothing has been sent yet.")
        }

        if isClarification(item) {
            return sanitizeBoundary("Nothing has been sent yet.")
        }

        if item.hasActionableExternalOutboundDraft {
            return sanitizeBoundary("Still local. Nothing has been sent yet.")
        }

        return sanitizeBoundary("Private.")
    }
    
    static func nextMove(for item: ExchangeModels.InboxItem) -> String {
        if let secondHalf = secondHalfDisplay(for: item),
           let next = secondHalfNextMoveLine(secondHalf) {
            return next
        }
        
        if item.hasPendingApproval {
            return item.hasActionableExternalOutboundDraft
                ? "Review the draft"
                : "Review before sending"
        }
        
        if let trace = item.workTrace,
           trace.status == .running,
           let active = trace.activeStep {
            return active.title
        }
        
        if let next = nonEmpty(item.nextStepText) {
            return next
        }
        
        if isClarification(item) {
            return "Answer the missing detail."
        }
        
        if isRecovery(item) {
            return "Open the recovery path."
        }
        
        if isSearchResult(item) {
            return "Review the search result."
        }
        
        return "Open the thread."
    }
    
    static func focusDisplay(
        for item: ExchangeModels.InboxItem?,
        execution: SecretaryExecutionDisplay? = nil
    ) -> SecretaryFocusDisplay {
        guard let item else {
            return SecretaryFocusDisplay(
                mode: .idle,
                isLive: false,
                headerEyebrow: "Workspace",
                headerSubeyebrow: "Main thing right now",
                badgeTitle: "Idle",
                title: "Nothing active yet",
                summary: "Start with a request below.",
                boundaryTitle: "Boundary",
                boundaryText: "Nothing moves outward until there is something clear to do.",
                primaryCTA: "Explore",
                primaryIcon: "arrow.right",
                secondaryCTA: "Threads",
                secondaryIcon: "waveform.path.ecg",
                clarificationQuestion: nil,
                clarificationWhy: nil,
                failureSummary: nil,
                failureReason: nil,
                failureNext: nil,
                foundHeading: nil,
                foundPrimary: nil,
                foundSecondary: nil,
                draftPreview: nil,
                foundNext: nil,
                nextTitle: "Next",
                nextText: "Start with a request below.",
                trace: nil,
                execution: nil
            )
        }
        
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalfHasPriority(secondHalf) {
            let outboundDraftTruth = userFacingPersistedOutboundDraft(for: item)
            let listStatus = visibleThreadStatus(for: item, bucket: bucket(for: item))
            let mode: SecretaryFocusDisplay.Mode = {
                if secondHalf.placement == .recovery || secondHalf.status.isBlocking {
                    return .failure
                }
                
                if secondHalf.placement == .needsInput {
                    return .clarification
                }
                
                if secondHalf.placement == .needsApproval ||
                    secondHalf.hasDecisionPacket ||
                    secondHalf.hasProviderReception ||
                    secondHalf.hasRequesterReview ||
                    outboundDraftTruth {
                    return .found
                }
                
                if item.awaitingReply {
                    return .waiting
                }
                
                return .active
            }()
            
            let secondHalfExecution = execution ?? secondHalfExecutionDisplay(
                for: secondHalf,
                fallbackTitle: displayTitle(for: item),
                fallbackBoundary: boundaryLine(for: item),
                persistedActionableExternalOutboundDraft: outboundDraftTruth,
                statusLabel: listStatus.label
            )
            
            return SecretaryFocusDisplay(
                mode: mode,
                isLive: secondHalf.canRunAutonomously || item.workTrace?.status == .running || execution != nil,
                headerEyebrow: secondHalf.canRunAutonomously ? "Live second half" : "Second half",
                headerSubeyebrow: nonEmpty(secondHalf.hero.eyebrow) ?? "Coordination layer",
                badgeTitle: listStatus.label,
                title: displayTitle(for: item),
                summary: secondHalfSummaryLine(secondHalf)
                ?? "The secretary is carrying the opportunity after the match.",
                boundaryTitle: nonEmpty(secondHalf.boundary.title) ?? "Boundary",
                boundaryText: secondHalfBoundaryLine(secondHalf) ?? boundaryLine(for: item),
                primaryCTA: secondHalfPrimaryCTA(
                    secondHalf,
                    fallback: item.hasPendingApproval ? "Review" : "Open",
                    persistedActionableExternalOutboundDraft: outboundDraftTruth
                ),
                primaryIcon: secondHalfPrimaryIcon(
                    secondHalf,
                    fallback: item.hasPendingApproval ? "checkmark.seal" : "arrow.right",
                    persistedActionableExternalOutboundDraft: outboundDraftTruth
                ),
                secondaryCTA: "Open thread",
                secondaryIcon: "text.document",
                clarificationQuestion: nonEmpty(secondHalf.nextMove?.requiredInputs.first)
                ?? nonEmpty(secondHalf.nextMove?.title),
                clarificationWhy: nonEmpty(secondHalf.nextMove?.rationale)
                ?? nonEmpty(secondHalf.summary),
                failureSummary: secondHalf.placement == .recovery || secondHalf.status.isBlocking
                ? (nonEmpty(secondHalf.summary) ?? failureWhatHappened(for: item))
                : nil,
                failureReason: secondHalf.placement == .recovery || secondHalf.status.isBlocking
                ? (nonEmpty(secondHalf.escalationReason) ?? nonEmpty(secondHalf.boundary.reason))
                : nil,
                failureNext: secondHalf.placement == .recovery || secondHalf.status.isBlocking
                ? (secondHalfNextMoveLine(secondHalf) ?? failureNextMove(for: item))
                : nil,
                foundHeading: secondHalf.hasDecisionPacket
                ? "Decision packet"
                : secondHalf.hasProviderReception
                ? "Provider reception"
                : secondHalf.hasRequesterReview
                ? "Opportunity review"
                : outboundDraftTruth
                ? "Prepared move"
                : "Second-half coordination",
                foundPrimary: nonEmpty(secondHalf.decision?.summary)
                ?? nonEmpty(secondHalf.providerReception?.inquirySummary)
                ?? nonEmpty(secondHalf.requesterReview?.subtitle)
                ?? nonEmpty(secondHalf.summary),
                foundSecondary: nonEmpty(secondHalf.recommendation)
                ?? nonEmpty(secondHalf.status.quality)
                ?? nonEmpty(secondHalf.status.readiness),
                draftPreview: outboundDraftTruth ? secondHalfDraftPreview(secondHalf) : nil,
                foundNext: secondHalfNextMoveLine(secondHalf),
                nextTitle: "Next",
                nextText: secondHalfNextMoveLine(secondHalf) ?? "Open the thread.",
                trace: item.workTrace,
                execution: secondHalfExecution
            )
        }
        
        let trace = item.workTrace
        let selectedMatchName = nonEmpty(item.selectedCounterpartyName) ?? ""
        let selectedMatchExists = item.selectedCounterpartyID != nil || !selectedMatchName.isEmpty
        let draftPreview: String? = {
            let body = clean(item.draftedBodyPreview)
            if !body.isEmpty {
                return body.count > 280
                ? String(body.prefix(280)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                : body
            }
            return nonEmpty(item.draftedSubject)
        }()
        
        let hasDraftPreview = item.hasActionableExternalOutboundDraft && draftPreview != nil
        let clarification = isClarification(item)
        let recovery = isRecovery(item)
        let explicitMatchFound: Bool = {
            if case .matchFound = item.state { return true }
            return false
        }()
        
        let found = !clarification && !recovery && (explicitMatchFound || selectedMatchExists || hasDraftPreview)
        let waiting = isWaiting(item)
        
        let mode: SecretaryFocusDisplay.Mode = {
            if clarification { return .clarification }
            if recovery { return .failure }
            if found { return .found }
            if waiting { return .waiting }
            return .active
        }()
        
        let isLive = trace?.status == .running || execution != nil
        
        let summary: String = {
            switch mode {
            case .clarification:
                return "One more detail is needed before this can move."
            case .failure:
                return "This thread needs recovery before it can move forward."
            case .found:
                if hasDraftPreview && selectedMatchExists {
                    return "A likely path is visible and a move is being prepared."
                }
                if hasDraftPreview {
                    return "A move is being prepared."
                }
                return "A likely path is visible."
            case .waiting:
                return "Waiting on the other side."
            case .active, .idle:
                if let headline = nonEmpty(trace?.headline) {
                    return headline
                }
                return activityMeaning(for: item)
            }
        }()
        
        let clarificationQuestion = nonEmpty(item.interpretationQuestion)
        ?? {
            if case .needsClarification(let status) = item.state {
                return nonEmpty(status.question)
            }
            return nil
        }()
        
        let clarificationWhy = nonEmpty(item.interpretationSummary)
        ?? nonEmpty(item.requiresAttentionReason)
        ?? nonEmpty(item.visibleSummary)
        
        let failureSummary = failureWhatHappened(for: item)
        let failureReason = nonEmpty(item.outcomeStatusText) ?? nonEmpty(item.requiresAttentionReason)
        let failureNext = failureNextMove(for: item)
        
        let foundHeading: String? = {
            if selectedMatchExists && hasDraftPreview { return "Best path and draft" }
            if selectedMatchExists { return "Best visible path" }
            if hasDraftPreview { return "Prepared move" }
            return nil
        }()
        
        let foundPrimary: String? = {
            if selectedMatchExists {
                return nonEmpty(item.visibleSummary)
                ?? nonEmpty(item.subtitle)
                ?? "This is the clearest visible path right now."
            }
            if hasDraftPreview {
                return "A draft is ready for review before anything moves outward."
            }
            return nonEmpty(item.visibleSummary) ?? nonEmpty(item.subtitle)
        }()
        
        let foundSecondary: String? = {
            if let trust = nonEmpty(item.trustPathSummary) { return trust }
            if let alternate = discoveryCandidateReviewAlternateLine(for: item) {
                return alternate
            }
            if selectedMatchExists && item.candidateCount > 1 {
                return "\(item.candidateCount) visible paths were considered. This one is currently selected."
            }
            return nonEmpty(item.outcomeStatusText)
        }()
        
        let foundNext: String? = {
            if let next = nonEmpty(item.nextStepText) { return next }
            if hasDraftPreview { return "Review the draft." }
            if selectedMatchExists { return "Inspect the selected path." }
            return "Open the thread."
        }()
        
        let nextText: String = {
            switch mode {
            case .clarification:
                return clarificationQuestion ?? "Answer the question."
            case .failure:
                return failureNext
            case .found:
                return foundNext ?? "Open the thread."
            case .waiting, .active, .idle:
                if let next = nonEmpty(item.nextStepText) { return next }
                if item.hasPendingApproval { return "Review it." }
                if waiting { return "Wait or follow up later." }
                return "Open the thread."
            }
        }()
        
        let badgeTitle: String = {
            switch mode {
            case .clarification: return "Need Detail"
            case .failure: return "Recovery"
            case .found:
                if selectedMatchExists && hasDraftPreview { return "Ready" }
                if selectedMatchExists { return "Found" }
                if hasDraftPreview { return "Draft" }
                return "Result"
            case .waiting: return "Waiting"
            case .active:
                if item.hasPendingApproval { return "Review" }
                return "Active"
            case .idle:
                return "Idle"
            }
        }()
        
        let primaryCTA: String = {
            switch mode {
            case .clarification: return "Answer"
            case .failure: return "Fix"
            case .found: return "Review"
            case .waiting, .active: return item.hasPendingApproval ? "Review" : "Open"
            case .idle: return "Explore"
            }
        }()
        
        let primaryIcon: String = {
            switch mode {
            case .clarification: return "questionmark.circle"
            case .failure: return "arrow.clockwise"
            case .found:
                if selectedMatchExists { return "person.crop.circle.badge.checkmark" }
                if hasDraftPreview { return "doc.text" }
                return "arrow.right"
            case .waiting, .active:
                return item.hasPendingApproval ? "checkmark.seal" : "arrow.right"
            case .idle:
                return "arrow.right"
            }
        }()
        
        return SecretaryFocusDisplay(
            mode: mode,
            isLive: isLive,
            headerEyebrow: isLive ? "Live workspace" : "Workspace",
            headerSubeyebrow: isLive ? "Live progress" : "Main thing right now",
            badgeTitle: badgeTitle,
            title: displayTitle(for: item),
            summary: summary,
            boundaryTitle: "Boundary",
            boundaryText: boundaryLine(for: item),
            primaryCTA: primaryCTA,
            primaryIcon: primaryIcon,
            secondaryCTA: (mode == .found || mode == .failure || mode == .clarification) ? "Open thread" : "Live view",
            secondaryIcon: (mode == .found || mode == .failure || mode == .clarification) ? "text.document" : "waveform.path.ecg",
            clarificationQuestion: clarificationQuestion,
            clarificationWhy: clarificationWhy,
            failureSummary: failureSummary,
            failureReason: failureReason,
            failureNext: failureNext,
            foundHeading: foundHeading,
            foundPrimary: foundPrimary,
            foundSecondary: foundSecondary,
            draftPreview: draftPreview,
            foundNext: foundNext,
            nextTitle: "Next",
            nextText: nextText,
            trace: trace,
            execution: execution
        )
    }
    
    static func activityLatestMovement(for item: ExchangeModels.InboxItem) -> String {
        
        if let secondHalf = secondHalfDisplay(for: item) {
            
            return nonEmpty(secondHalf.nextMove?.title)
            
            ?? nonEmpty(secondHalf.hero.statusLine)
            
            ?? nonEmpty(secondHalf.summary)
            
            ?? nonEmpty(secondHalf.recommendation)
            
            ?? "Second-half coordination is active."
            
        }
        
        if let trace = item.workTrace {
            
            if let active = trace.activeStep {
                
                return nonEmpty(active.detail) ?? active.title
                
            }
            
            if let latest = trace.latestStep {
                
                return nonEmpty(latest.detail) ?? latest.title
                
            }
            
            if let headline = nonEmpty(trace.headline) {
                
                return headline
                
            }
            
        }
        
        if let selected = nonEmpty(item.selectedMatchSummary) {
            
            return selected
            
        }
        
        switch item.state {
            
        case .draftReady:
            
            return nonEmpty(item.draftedBodyPreview) ?? "A local draft is ready."
            
        case .drafting:
            
            return "The secretary is shaping the next move."
            
        case .searching:
            
            return item.candidateCount > 1
            
            ? "Multiple visible paths are being compared."
            
            : "The secretary is searching for a viable path."
            
        case .awaitingResponse:
            
            return "Waiting on a reply after earlier activity."
            
        case .sending:
            
            return "The secretary is moving the prepared action outward."
            
        default:
            
            return nonEmpty(item.visibleSummary)
            
            ?? nonEmpty(item.subtitle)
            
            ?? "This thread is active and still progressing."
            
        }
        
    }
    
    static func isBlockedRecovery(_ item: ExchangeModels.InboxItem) -> Bool {
        switch item.state {
        case .blockedByDeliveryFailure, .blockedBySystemFailure:
            return true
        default:
            return false
        }
    }
    
    static func isDeclinedRecovery(_ item: ExchangeModels.InboxItem) -> Bool {
        if case .declined = item.state {
            return true
        }
        return false
    }
    
    static func isStalledRecovery(_ item: ExchangeModels.InboxItem) -> Bool {
        if case .stalled = item.state {
            return true
        }
        return false
    }
    
    static func isDirectTrust(_ item: ExchangeModels.InboxItem) -> Bool {
        nonEmpty(item.selectedCounterpartyName) != nil
    }
    
    static func isWarmTrust(_ item: ExchangeModels.InboxItem) -> Bool {
        let trust = clean(item.trustPathSummary).lowercased()
        return trust.contains("trust")
        || trust.contains("warm")
        || trust.contains("friend")
    }
    
    static func isActiveTrust(_ item: ExchangeModels.InboxItem) -> Bool {
        switch item.state {
        case .drafting, .draftReady, .searching, .sending, .awaitingResponse:
            return true
        default:
            return false
        }
    }
    
    
    
    static func activityMeaning(for item: ExchangeModels.InboxItem) -> String {
        
        if let secondHalf = secondHalfDisplay(for: item) {
            
            if secondHalf.hasDecisionPacket {
                
                return "Decision: \(secondHalf.decision?.recommendation ?? secondHalf.recommendation)"
                
            }
            
            if secondHalf.hasProviderReception {
                
                return "Reception: \(secondHalf.providerReception?.subtitle ?? secondHalf.summary)"
                
            }
            
            if secondHalf.hasRequesterReview {
                
                return "Review: \(secondHalf.requesterReview?.subtitle ?? secondHalf.summary)"
                
            }
            
            if let next = secondHalf.nextMove {
                
                return "Next: \(next.title)"
                
            }
            
            return secondHalf.summary
            
        }
        
        if let trace = item.workTrace {
            
            return "Trace: \(trace.completedStepCount)/\(trace.totalStepCount) steps"
            
        }
        
        if let next = nonEmpty(item.nextStepText) {
            
            return "Next: \(next)"
            
        }
        
        if let path = nonEmpty(item.selectedCounterpartyName) {
            
            return "Path: \(path)"
            
        }
        
        return "The thread is still active and evolving."
        
    }
    
    static func activityBadge(for item: ExchangeModels.InboxItem) -> String {
        if let trace = item.workTrace {
            switch trace.status {
            case .running: return "Working"
            case .completed: return "Work done"
            case .blocked: return "Work paused"
            case .idle: break
            }
        }
        return visibleThreadStatus(for: item, bucket: bucket(for: item)).label
    }
    
    static func trustLabel(for item: ExchangeModels.InboxItem) -> String {
        if let trust = nonEmpty(item.trustPathSummary) {
            return trust
        }
        if nonEmpty(item.selectedCounterpartyName) != nil {
            return "Direct visible path"
        }
        return "Warm / known route"
    }
    
    static func trustedActivityLabel(for item: ExchangeModels.InboxItem) -> String {
        if item.awaitingReply { return "Waiting" }
        if item.hasActionableExternalOutboundDraft { return "Draft Ready" }
        if isActive(item) { return "Active" }
        return "Visible"
    }
    
    static func trustedExamples(for item: ExchangeModels.InboxItem) -> [String] {
        var result: [String] = []
        
        if let counterparty = nonEmpty(item.selectedCounterpartyName) {
            result.append("Current visible party: \(counterparty)")
        }
        if let trust = nonEmpty(item.trustPathSummary) {
            result.append(trust)
        }
        if let delivery = nonEmpty(item.deliveryStatusText) {
            result.append(delivery)
        }
        if let next = nonEmpty(item.nextStepText) {
            result.append("Next: \(next)")
        }
        
        if result.isEmpty {
            result.append("A relationship-based path is visible here.")
        }
        
        return result
    }
    
    // MARK: - Execution projection
    
    static func executionDisplay(for item: ExchangeModels.InboxItem) -> SecretaryExecutionDisplay? {
        if let secondHalf = secondHalfDisplay(for: item) {
            let listStatus = visibleThreadStatus(for: item, bucket: bucket(for: item))
            return secondHalfExecutionDisplay(
                for: secondHalf,
                fallbackTitle: displayTitle(for: item),
                fallbackBoundary: boundaryLine(for: item),
                persistedActionableExternalOutboundDraft: userFacingPersistedOutboundDraft(for: item),
                statusLabel: listStatus.label
            )
        }
        
        if item.hasPendingApproval || item.candidateCount > 1 {
            let isSelection = !item.hasPendingApproval && item.candidateCount > 1
            
            return SecretaryExecutionDisplay(
                title: clean(
                    item.title,
                    fallback: isSelection ? "Selection in progress" : "Approval in progress"
                ),
                summary: isSelection
                ? "The secretary has surfaced multiple viable paths and is waiting for your judgment before collapsing to one."
                : "The secretary has finished preparing a bounded move and is waiting for your judgment.",
                badgeTitle: "Needs Judgment",
                boundary: clean(
                    item.deliveryStatusText,
                    fallback: "Nothing has been sent externally yet."
                ),
                nextMove: clean(
                    item.nextStepText,
                    fallback: isSelection
                    ? "Compare the visible paths and choose which one should move next."
                    : "Review the prepared draft and decide whether it should move."
                ),
                primaryActionTitle: isSelection ? "Compare" : "Review",
                primarySystemImage: isSelection ? "rectangle.split.3x1" : "checkmark.seal",
                secondaryActionTitle: "More",
                secondarySystemImage: "square.grid.2x2",
                currentStageTitle: isSelection ? "Waiting for path selection" : "Waiting for judgment",
                currentStageSubtitle: isSelection
                ? "The system has narrowed the field, but the final path still depends on your choice."
                : "The system has reached the human boundary and will not continue beyond it without approval.",
                stages: [
                    SecretaryExecutionStageDisplay(
                        title: "Understand request",
                        subtitle: "The secretary interpreted the user’s intent.",
                        status: .complete
                    ),
                    SecretaryExecutionStageDisplay(
                        title: "Shape path",
                        subtitle: routeSubtitle(for: item, fallback: "A viable next move was chosen."),
                        status: .complete
                    ),
                    SecretaryExecutionStageDisplay(
                        title: isSelection ? "Surface options" : "Prepare draft",
                        subtitle: isSelection
                        ? "Multiple viable paths are now visible."
                        : (userFacingPersistedOutboundDraft(for: item)
                            ? "A bounded outward move was prepared."
                            : "The thread is waiting at a human review gate."),
                        status: .complete
                    ),
                    SecretaryExecutionStageDisplay(
                        title: isSelection ? "Wait for selection" : "Wait for judgment",
                        subtitle: isSelection
                        ? "The thread is paused until the user chooses the path."
                        : "The thread is paused until the user decides.",
                        status: .active
                    )
                ]
            )
        }
        
        if item.hasFailure {
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Recovery in progress"),
                summary: "The secretary surfaced a visible failure and is holding the recovery path open.",
                badgeTitle: "Recovery",
                boundary: clean(item.deliveryStatusText, fallback: "External impact is limited or still unclear."),
                nextMove: clean(item.nextStepText, fallback: "Inspect the failure and choose the best recovery move."),
                primaryActionTitle: "Recover",
                primarySystemImage: "arrow.clockwise",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Recovery shaping",
                currentStageSubtitle: "The system is clarifying what happened, what did not happen, and what should happen next.",
                stages: [
                    SecretaryExecutionStageDisplay(
                        title: "Detect failure",
                        subtitle: "A failure or stall was surfaced on the thread.",
                        status: .complete
                    ),
                    SecretaryExecutionStageDisplay(
                        title: "Read external impact",
                        subtitle: clean(item.deliveryStatusText, fallback: "The system checked whether anything changed beyond the boundary."),
                        status: .complete
                    ),
                    SecretaryExecutionStageDisplay(
                        title: "Shape recovery",
                        subtitle: clean(item.nextStepText, fallback: "The best next move is being made visible."),
                        status: .active
                    )
                ]
            )
        }
        
        if item.awaitingReply {
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Awaiting reply"),
                summary: "The outward move has already happened, and the thread is waiting on the other side.",
                badgeTitle: "Awaiting Reply",
                boundary: clean(item.deliveryStatusText, fallback: "Something has already moved beyond your boundary."),
                nextMove: clean(item.nextStepText, fallback: "Wait for the reply window or prepare a bounded follow-up."),
                primaryActionTitle: "Open",
                primarySystemImage: "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Waiting on the other side",
                currentStageSubtitle: "The secretary is currently holding state while the thread waits for an external reply.",
                stages: [
                    SecretaryExecutionStageDisplay(
                        title: "Understand request",
                        subtitle: "The secretary interpreted the request and chose a path.",
                        status: .complete
                    ),
                    SecretaryExecutionStageDisplay(
                        title: "Prepare move",
                        subtitle: "The outward move was prepared.",
                        status: .complete
                    ),
                    SecretaryExecutionStageDisplay(
                        title: "Commit path",
                        subtitle: "The thread moved beyond the local boundary.",
                        status: .complete
                    ),
                    SecretaryExecutionStageDisplay(
                        title: "Await reply",
                        subtitle: "The thread is open and waiting on the response.",
                        status: .active
                    )
                ]
            )
        }
        
        switch item.state {
        case .drafting:
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Drafting"),
                summary: "The secretary is actively shaping an outward move.",
                badgeTitle: "Drafting",
                boundary: clean(item.deliveryStatusText, fallback: "Nothing has been sent externally yet."),
                nextMove: clean(item.nextStepText, fallback: "Review the draft path as it takes shape."),
                primaryActionTitle: "Open",
                primarySystemImage: "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Draft shaping",
                currentStageSubtitle: "The system is preparing the message or move that could happen next.",
                stages: [
                    .init(title: "Understand request", subtitle: "The request was interpreted.", status: .complete),
                    .init(title: "Choose path", subtitle: routeSubtitle(for: item, fallback: "A path or likely counterparty is being formed."), status: .complete),
                    .init(title: "Draft move", subtitle: "The outward move is being written or prepared.", status: .active),
                    .init(title: "Ready for review", subtitle: "The thread may soon pause for review.", status: .pending)
                ]
            )
            
        case .draftReady:
            let actionable = item.hasActionableExternalOutboundDraft
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: actionable ? "Draft Ready" : "Review"),
                summary: actionable
                    ? "The secretary has prepared a draft locally and is holding it inside the boundary."
                    : "This thread reached a draft-shaped phase, but there is nothing actionable to send outward yet.",
                badgeTitle: actionable ? "Draft Ready" : "Review",
                boundary: clean(
                    item.deliveryStatusText,
                    fallback: actionable
                        ? "Prepared locally. Nothing has been sent externally yet."
                        : "Nothing has moved outward yet."
                ),
                nextMove: clean(
                    item.nextStepText,
                    fallback: actionable
                        ? "Review the prepared draft."
                        : "Review what matters before deciding the next step."
                ),
                primaryActionTitle: "Open",
                primarySystemImage: "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: actionable ? "Draft ready" : "At review gate",
                currentStageSubtitle: actionable
                    ? "A persisted outbound draft is ready for review or onward movement."
                    : "No unsent actionable outward draft shows up locally yet.",
                stages: [
                    .init(title: "Understand request", subtitle: "The request was interpreted.", status: .complete),
                    .init(title: "Choose path", subtitle: routeSubtitle(for: item, fallback: "A likely path or counterparty has been identified."), status: .complete),
                    .init(
                        title: "Draft move",
                        subtitle: actionable
                            ? "A draft record is ready locally."
                            : "Draft bookkeeping may lag the visible outward move.",
                        status: actionable ? .complete : .active
                    ),
                    .init(
                        title: "Ready for review",
                        subtitle: actionable
                            ? "The thread holds a persisted outward draft worth reviewing."
                            : "Wait until a real outbound draft lands before committing to wording.",
                        status: actionable ? .active : .pending
                    )
                ]
            )
            
        case .searching:
            let hasManyCandidates = item.candidateCount > 1
            let hasAnyCandidates = item.candidateCount > 0
            
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Search in progress"),
                summary: hasManyCandidates
                ? "The secretary is comparing visible options before collapsing into a single next move."
                : "The secretary is actively searching for a viable path.",
                badgeTitle: "Searching",
                boundary: clean(item.deliveryStatusText, fallback: "Search work is still local and bounded."),
                nextMove: clean(
                    item.nextStepText,
                    fallback: hasManyCandidates
                    ? "Compare candidate quality or let the search continue."
                    : "Let the search continue or inspect the current path."
                ),
                primaryActionTitle: hasManyCandidates ? "Compare" : "Open",
                primarySystemImage: hasManyCandidates ? "rectangle.split.3x1" : "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: hasManyCandidates ? "Comparing options" : "Searching",
                currentStageSubtitle: hasManyCandidates
                ? "The system is evaluating counterparties, routes, or possible execution paths."
                : "The system is still looking for the right path to move this thread forward.",
                stages: [
                    .init(title: "Understand request", subtitle: "The request was interpreted.", status: .complete),
                    .init(title: "Search paths", subtitle: hasAnyCandidates ? "Possible counterparties or routes were surfaced." : "The system is still surfacing possible counterparties or routes.", status: hasAnyCandidates ? .complete : .active),
                    .init(title: "Compare fit", subtitle: hasManyCandidates ? "The system is weighing which visible option should move next." : "Fit comparison will happen once clearer options emerge.", status: hasManyCandidates ? .active : .pending),
                    .init(title: "Prepare next move", subtitle: "The path will be shaped once a clear direction emerges.", status: .pending)
                ]
            )
            
        case .needsClarification:
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Needs clarification"),
                summary: "The secretary cannot continue until the request is clarified.",
                badgeTitle: "Needs Clarification",
                boundary: clean(item.deliveryStatusText, fallback: "Nothing has moved externally."),
                nextMove: clean(item.nextStepText, fallback: "Clarify the request."),
                primaryActionTitle: "Open",
                primarySystemImage: "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Clarification needed",
                currentStageSubtitle: clean(item.requiresAttentionReason, fallback: "The thread needs more specificity before it can move."),
                stages: [
                    .init(title: "Understand request", subtitle: "The initial request was received.", status: .complete),
                    .init(title: "Clarify intent", subtitle: clean(item.requiresAttentionReason, fallback: "The system needs more clarity before it can proceed."), status: .active),
                    .init(title: "Resume pathing", subtitle: "Search or drafting will resume after clarification.", status: .pending)
                ]
            )
            
        case .matchFound:
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Found path"),
                summary: "A likely path was found and is ready for review.",
                badgeTitle: "Found",
                boundary: clean(item.deliveryStatusText, fallback: "Nothing has moved externally yet."),
                nextMove: clean(item.nextStepText, fallback: "Continue on this found path."),
                primaryActionTitle: "Review",
                primarySystemImage: "person.crop.circle.badge.checkmark",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Found path ready",
                currentStageSubtitle: "The secretary has selected the clearest current path, but nothing has moved outward yet.",
                stages: [
                    .init(title: "Understand request", subtitle: "The request was interpreted.", status: .complete),
                    .init(title: "Search paths", subtitle: "Candidate routes were surfaced.", status: .complete),
                    .init(title: "Select best path", subtitle: clean(item.selectedMatchSummary, fallback: "The strongest visible path was selected."), status: .complete),
                    .init(title: "Continue path", subtitle: clean(item.nextStepText, fallback: "The next step is ready to be shaped."), status: .active)
                ]
            )
            
        case .matchCandidatesWeak:
            if let grade = item.discoveryProjectedGrade, grade != .weak {
                let resolution = ExchangeUmbrellaDiscoveryGradeProjection.Resolution(
                    internalStateKey: ExchangeTransition.ExchangeStateKey.matchCandidatesWeak.rawValue,
                    classifyGrade: nil,
                    projectedGrade: grade,
                    gradeReason: "projection_execution_display",
                    usesMetadata: true
                )
                return SecretaryExecutionDisplay(
                    title: clean(
                        item.title,
                        fallback: ExchangeUmbrellaDiscoveryGradeProjection.executionTitle(for: resolution) ?? "Matches found"
                    ),
                    summary: ExchangeUmbrellaDiscoveryGradeProjection.executionSummary(for: resolution)
                        ?? "Matches were found and are ready for review.",
                    badgeTitle: ExchangeUmbrellaDiscoveryGradeProjection.executionBadgeTitle(for: resolution)
                        ?? "Matches Found",
                    boundary: clean(item.deliveryStatusText, fallback: "Nothing has moved externally yet."),
                    nextMove: clean(item.nextStepText, fallback: "Review surfaced matches before outreach."),
                    primaryActionTitle: "Open",
                    primarySystemImage: "arrow.right",
                    secondaryActionTitle: "Details",
                    secondarySystemImage: "list.bullet.rectangle",
                    currentStageTitle: grade == .strong ? "Strong matches ready" : "Matches need review",
                    currentStageSubtitle: grade == .strong
                        ? "Strong candidates were surfaced and are ready for your review."
                        : "Viable matches were found and need your review.",
                    stages: [
                        .init(title: "Understand request", subtitle: "The request was interpreted.", status: .complete),
                        .init(title: "Search paths", subtitle: "Candidate routes were surfaced.", status: .complete),
                        .init(title: "Review matches", subtitle: "Compare surfaced candidates before choosing.", status: .active),
                        .init(title: "Continue path", subtitle: "Select a path to move forward.", status: .pending)
                    ]
                )
            }
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Weak matches"),
                summary: "Some paths were found, but they are not strong enough yet.",
                badgeTitle: "Weak Paths",
                boundary: clean(item.deliveryStatusText, fallback: "Nothing has moved externally yet."),
                nextMove: clean(item.nextStepText, fallback: "Review weak paths or refine the request."),
                primaryActionTitle: "Open",
                primarySystemImage: "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Weak path review",
                currentStageSubtitle: "The system found options, but none are strong enough to commit yet.",
                stages: [
                    .init(title: "Understand request", subtitle: "The request was interpreted.", status: .complete),
                    .init(title: "Search paths", subtitle: "Candidate routes were surfaced.", status: .complete),
                    .init(title: "Evaluate fit", subtitle: "The current options are still weak.", status: .active),
                    .init(title: "Refine direction", subtitle: "The request may need refinement or expansion.", status: .pending)
                ]
            )
            
        case .noViableMatch:
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "No viable match"),
                summary: "The current request did not yield a viable path.",
                badgeTitle: "No Viable Match",
                boundary: clean(item.deliveryStatusText, fallback: "Nothing moved externally."),
                nextMove: clean(item.nextStepText, fallback: "Refine the request or broaden the route."),
                primaryActionTitle: "Open",
                primarySystemImage: "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "No viable path",
                currentStageSubtitle: "The current search space did not produce a strong enough result.",
                stages: [
                    .init(title: "Understand request", subtitle: "The request was interpreted.", status: .complete),
                    .init(title: "Search paths", subtitle: "The secretary searched for viable routes.", status: .complete),
                    .init(title: "No viable match", subtitle: "No path was strong enough to continue.", status: .active)
                ]
            )
            
        case .awaitingApproval:
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Awaiting approval"),
                summary: "The thread is paused at the approval boundary.",
                badgeTitle: "Needs Judgment",
                boundary: clean(item.deliveryStatusText, fallback: "Nothing has been sent externally yet."),
                nextMove: clean(item.nextStepText, fallback: "Review approval."),
                primaryActionTitle: "Review",
                primarySystemImage: "checkmark.seal",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Waiting for judgment",
                currentStageSubtitle: "The thread will not move further without your approval.",
                stages: [
                    .init(title: "Understand request", subtitle: "The request was interpreted.", status: .complete),
                    .init(title: "Prepare move", subtitle: "The move or draft was prepared.", status: .complete),
                    .init(title: "Await approval", subtitle: "The thread is paused at the human boundary.", status: .active)
                ]
            )
            
        case .sending:
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Sending"),
                summary: "The secretary is moving the prepared action outward.",
                badgeTitle: "Sending",
                boundary: clean(item.deliveryStatusText, fallback: "An outward move is currently in progress."),
                nextMove: clean(item.nextStepText, fallback: "Monitor the send."),
                primaryActionTitle: "Open",
                primarySystemImage: "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Sending",
                currentStageSubtitle: "The secretary is attempting to move the prepared action beyond the boundary.",
                stages: [
                    .init(title: "Understand request", subtitle: "The request was interpreted.", status: .complete),
                    .init(title: "Prepare move", subtitle: "The move was prepared.", status: .complete),
                    .init(title: "Send outward", subtitle: "The secretary is now transmitting the move.", status: .active)
                ]
            )
            
        case .blockedByDeliveryFailure:
            return nil
            
        case .awaitingResponse:
            return nil
            
        case .declined:
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Declined"),
                summary: "The thread was declined and is holding that outcome visibly.",
                badgeTitle: "Declined",
                boundary: clean(item.deliveryStatusText, fallback: "No further movement is happening."),
                nextMove: clean(item.nextStepText, fallback: "Review the decline and decide whether to reopen or close."),
                primaryActionTitle: "Open",
                primarySystemImage: "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Declined",
                currentStageSubtitle: "The current path did not proceed.",
                stages: [
                    .init(title: "Prepare move", subtitle: "A path was prepared.", status: .complete),
                    .init(title: "Decision reached", subtitle: "The thread was declined.", status: .active)
                ]
            )
            
        case .stalled:
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Stalled"),
                summary: "The thread is no longer progressing and needs a visible next move.",
                badgeTitle: "Stalled",
                boundary: clean(item.deliveryStatusText, fallback: "Progress is paused."),
                nextMove: clean(item.nextStepText, fallback: "Reassess the thread and choose whether to continue."),
                primaryActionTitle: "Open",
                primarySystemImage: "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Stalled",
                currentStageSubtitle: "The thread lost momentum and now needs intervention.",
                stages: [
                    .init(title: "Progress thread", subtitle: "The thread was previously moving.", status: .complete),
                    .init(title: "Detect stall", subtitle: "The thread is no longer progressing.", status: .active),
                    .init(title: "Choose recovery", subtitle: "A new next move must be chosen.", status: .pending)
                ]
            )
            
        case .resolved:
            return SecretaryExecutionDisplay(
                title: clean(item.title, fallback: "Resolved"),
                summary: "The thread reached a visible outcome.",
                badgeTitle: "Resolved",
                boundary: clean(item.deliveryStatusText, fallback: "The work is complete."),
                nextMove: clean(item.nextStepText, fallback: "Review the final outcome."),
                primaryActionTitle: "Open",
                primarySystemImage: "arrow.right",
                secondaryActionTitle: "Details",
                secondarySystemImage: "list.bullet.rectangle",
                currentStageTitle: "Resolved",
                currentStageSubtitle: "The coordination path has reached its conclusion.",
                stages: [
                    .init(title: "Move thread forward", subtitle: "The secretary progressed the thread.", status: .complete),
                    .init(title: "Reach outcome", subtitle: "A visible resolution was recorded.", status: .complete)
                ]
            )
            
        case .blockedBySystemFailure:
            return nil
        }
    }
    
    // MARK: - Inbox item DTO projection
    
    static func approvalDisplay(
        for item: ExchangeModels.InboxItem
    ) -> SecretaryApprovalPanelDisplay {
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.needsHumanAttention || secondHalf.hasDecisionPacket || item.hasPendingApproval
            || userFacingPersistedOutboundDraft(for: item) {
            let draftTruth = userFacingPersistedOutboundDraft(for: item)
            let providerCoordination = secondHalfProviderInboundNeedsCoordinationInput(secondHalf, item: item)
            let softenApprovalPrimary =
                providerCoordination || (item.hasPendingApproval && !draftTruth)
            let missingFactLines = cleanedList(secondHalf.operatingContext.userFacingMissingFacts)
            let suppressStaleWaitingInDecisionPacket = userFacingPersistedOutboundDraft(for: item)
            let preparedSendBlocked = secondHalfBlocksPreparedSend(secondHalf)
            let approvalSummary = approvalDisplayFilteredDecisionPacketLine(
                nonEmpty(secondHalf.decision?.summary)
                    ?? nonEmpty(secondHalf.summary)
                    ?? nonEmpty(secondHalf.recommendation),
                suppressStaleWaitingWhenActionableDraft: suppressStaleWaitingInDecisionPacket
            ) ?? pendingReason(for: item)
            let primaryApprovalTitle: String = {
                if item.prefersPreparedUserDirectedOutboundSend {
                    return "Send"
                }
                if softenApprovalPrimary {
                    return missingFactLines.isEmpty ? "Review request" : "Answer needed"
                }
                return "Approve"
            }()

            return SecretaryApprovalPanelDisplay(
                title: displayTitle(for: item),
                decisionType: approvalDecisionType(for: item),
                summary: approvalSummary,
                boundary: secondHalfBoundaryLine(secondHalf) ?? boundaryLine(for: item),
                draftSubject: draftTruth ? (nonEmpty(secondHalf.draft?.subject) ?? nonEmpty(item.draftedSubject)) : nil,
                draftBody: draftTruth
                    ? (nonEmpty(secondHalf.draft?.bodyPreview)
                        ?? nonEmpty(item.draftedBodyPreview)
                        ?? nonEmpty(item.visibleSummary)
                        ?? nonEmpty(item.subtitle))
                    : nil,
                rationale: nonEmpty(secondHalf.nextMove?.rationale)
                    ?? nonEmpty(secondHalf.escalationReason)
                    ?? nonEmpty(item.nextStepText),
                primaryTitle: primaryApprovalTitle,
                secondaryTitle: "Reject",
                threadID: item.threadID,
                approvalID: nil,
                prefersSecondHalfPreparedSend: item.prefersPreparedUserDirectedOutboundSend,
                decisionSummary: approvalDisplayFilteredDecisionPacketLine(
                    nonEmpty(secondHalf.decision?.summary),
                    suppressStaleWaitingWhenActionableDraft: suppressStaleWaitingInDecisionPacket
                ),
                recommendation: approvalDisplayFilteredDecisionPacketLine(
                    nonEmpty(secondHalf.decision?.recommendation) ?? nonEmpty(secondHalf.recommendation),
                    suppressStaleWaitingWhenActionableDraft: suppressStaleWaitingInDecisionPacket
                ),
                commitmentBoundaryTitle: nonEmpty(secondHalf.boundary.title),
                commitmentBoundaryReason: nonEmpty(secondHalf.boundary.reason)
                    ?? nonEmpty(secondHalf.boundary.externalEffectLine),
                requiresHumanApproval: secondHalf.boundary.requiresHumanApproval || preparedSendBlocked,
                clarifiedFacts: secondHalfClarifiedFacts(secondHalf),
                unresolvedIssues: secondHalfUnresolvedIssues(secondHalf),
                tradeoffs: secondHalfTradeoffs(secondHalf),
                whatChanged: secondHalfWhatChanged(secondHalf),
                approvalReasons: secondHalfApprovalReasons(secondHalf),
                extraSections: secondHalfExtraSections(secondHalf)
            )
        }

        let softenLegacy = item.hasPendingApproval && !userFacingPersistedOutboundDraft(for: item)

        return SecretaryApprovalPanelDisplay(
            title: displayTitle(for: item),
            decisionType: approvalDecisionType(for: item),
            summary: pendingReason(for: item),
            boundary: boundaryLine(for: item),
            draftSubject: userFacingPersistedOutboundDraft(for: item) ? nonEmpty(item.draftedSubject) : nil,
            draftBody: userFacingPersistedOutboundDraft(for: item)
                ? (nonEmpty(item.draftedBodyPreview) ?? nonEmpty(item.visibleSummary) ?? nonEmpty(item.subtitle))
                : nil,
            rationale: nonEmpty(item.nextStepText),
            primaryTitle: softenLegacy ? "Review request" : "Approve",
            secondaryTitle: "Reject",
            threadID: item.threadID,
            approvalID: nil
        )
    }
    
    static func recoveryDisplay(
        for item: ExchangeModels.InboxItem
    ) -> SecretaryRecoveryPanel.Display {
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.placement == .recovery || secondHalf.status.isBlocking {
            return SecretaryRecoveryPanel.Display(
                title: displayTitle(for: item),
                recoveryType: visibleThreadStatus(for: item, bucket: bucket(for: item)).label,
                whatHappened: nonEmpty(secondHalf.summary)
                    ?? nonEmpty(secondHalf.hero.statusLine)
                    ?? failureWhatHappened(for: item),
                whatDidNotHappen: nonEmpty(secondHalf.boundary.externalEffectLine)
                ?? failureWhatDidNotHappen(for: item),
                externalEffect: secondHalfBoundaryLine(secondHalf)
                ?? failureExternalEffect(for: item),
                bestNextMove: secondHalfNextMoveLine(secondHalf)
                ?? failureNextMove(for: item),
                primaryTitle: "Continue recovery",
                secondaryTitle: "Hold",
                threadID: item.threadID
            )
        }
        
        return SecretaryRecoveryPanel.Display(
            title: displayTitle(for: item),
            recoveryType: recoveryBadge(for: item),
            whatHappened: failureWhatHappened(for: item),
            whatDidNotHappen: failureWhatDidNotHappen(for: item),
            externalEffect: failureExternalEffect(for: item),
            bestNextMove: failureNextMove(for: item),
            primaryTitle: "Continue recovery",
            secondaryTitle: "Hold",
            threadID: item.threadID
        )
    }
    
    static func activityDisplay(
        for item: ExchangeModels.InboxItem
    ) -> SecretaryActivityPanelDisplay {
        let listVS = visibleThreadStatus(for: item, bucket: bucket(for: item))
        if let secondHalf = secondHalfDisplay(for: item) {
            let outboundTruth = userFacingPersistedOutboundDraft(for: item)
            return SecretaryActivityPanelDisplay(
                title: displayTitle(for: item),
                activityType: listVS.label,
                latestMovement: activityLatestMovement(for: item),
                meaning: activityMeaning(for: item),
                currentState: nonEmpty(listVS.subtitle) ?? listVS.label,
                boundary: secondHalfBoundaryLine(secondHalf) ?? boundaryLine(for: item),
                nextMove: secondHalfNextMoveLine(secondHalf) ?? nextMove(for: item),
                primaryTitle: secondHalfPrimaryCTA(
                    secondHalf,
                    fallback: "Open thread",
                    persistedActionableExternalOutboundDraft: outboundTruth
                ),
                secondaryTitle: "Close",
                execution: executionDisplay(for: item),
                threadID: item.threadID,
                whatChanged: secondHalfWhatChanged(secondHalf),
                operatingContext: secondHalfOperatingContextLines(secondHalf),
                stanceLines: secondHalfStanceLines(secondHalf),
                decisionLines: secondHalfDecisionLines(secondHalf),
                providerReceptionLines: secondHalfProviderReceptionLines(secondHalf),
                requesterReviewLines: secondHalfRequesterReviewLines(secondHalf),
                draftFactsUsed: secondHalfDraftFactsUsed(secondHalf),
                extraSections: secondHalfExtraSections(secondHalf)
            )
        }

        return SecretaryActivityPanelDisplay(
            title: displayTitle(for: item),
            activityType: listVS.label,
            latestMovement: activityLatestMovement(for: item),
            meaning: activityMeaning(for: item),
            currentState: nonEmpty(listVS.subtitle) ?? listVS.label,
            boundary: boundaryLine(for: item),
            nextMove: nextMove(for: item),
            primaryTitle: "Open thread",
            secondaryTitle: "Close",
            execution: executionDisplay(for: item),
            threadID: item.threadID
        )
    }
    
    static func compareDisplay(
        for detail: ExchangeModels.ThreadDetail
    ) -> SecretaryComparePanel.Display {
        let secondHalf = secondHalfDisplay(for: detail)
        let ranked = rankedComparableMatches(for: detail)

        if ranked.count >= 2 {
            let options = ranked.map { match in
                compareOptionForMatch(
                    match,
                    detail: detail,
                    secondHalf: secondHalf,
                    isPreferred: isPreferredCompareMatch(match, detail: detail, ranked: ranked)
                )
            }

            let exposureLine = secondHalf.flatMap { display in
                nonEmpty(display.boundary.externalEffectLine)
                ?? nonEmpty(display.boundary.reason)
            } ?? threadBoundaryLine(detail)

            return SecretaryComparePanel.Display(
                title: threadTitle(detail, surface: "compare"),
                summary: "These profiles were considered during discovery. The secretary is checking the top match first. Reviewing others does not contact them.",
                options: options,
                primaryTitle: "Open thread",
                secondaryTitle: "Close",
                threadID: detail.thread.id,
                panelKind: "Compare paths",
                recommendation: nil,
                exposureSummary: exposureLine,
                trustSummary: nil,
                readinessSummary: nil,
                missingFacts: [],
                strengthReasons: [],
                weaknessReasons: [],
                extraSections: []
            )
        }

        let selectedMatch = detail.selectedMatch ?? preferredVisibleMatch(for: detail)
        let selectedCounterparty = detail.selectedCounterparty

        let selectedTitle =
            matchOfferTitle(selectedMatch)
            ?? matchPublicProfileHeadline(selectedMatch)
            ?? matchPublicProfileName(selectedMatch)
            ?? compareOptionTitle(
                match: selectedMatch,
                counterparty: selectedCounterparty,
                detail: detail
            )

        #if DEBUG
        let anchor = detail.thread.intent.resolvedOpportunitySurfaceAnchor(
            selectedOfferID: detail.selectedOfferID,
            selectedPublicProfileID: detail.selectedPublicProfileID,
            selectedCounterpartyID: detail.thread.selectedCounterpartyID
        )
        let surfaceLabel: String = {
            switch anchor {
            case .offerSurface: return "offer"
            case .profileSurface: return "profile"
            case .counterpartyNode: return "fallback"
            }
        }()
        if ExchangeDebugProjectionLogDedupe.shouldLogOpportunityDisplay(
            threadID: detail.thread.id.uuidString,
            selectedOfferID: detail.selectedOfferID,
            resolvedSurface: surfaceLabel,
            title: selectedTitle
        ) {
            Swift.print(
                "[OpportunityDisplay] thread=\(detail.thread.id.uuidString) " +
                    "queryClass=\(detail.thread.intent.queryIntentClass.rawValue) " +
                    "surfacePref=\(detail.thread.intent.surfacePreference.rawValue) " +
                    "selectedCounterpartyID=\(detail.thread.selectedCounterpartyID ?? "nil") " +
                    "selectedProfileID=\(detail.selectedPublicProfileID ?? "nil") " +
                    "selectedOfferID=\(detail.selectedOfferID ?? "nil") " +
                    "resolvedSurface=\(surfaceLabel) " +
                    "title=\(selectedTitle)"
            )
        }
        let titleSourceForLog: String = {
            if matchOfferTitle(selectedMatch) != nil { return "offer" }
            if matchPublicProfileHeadline(selectedMatch) != nil || matchPublicProfileName(selectedMatch) != nil {
                return "profile"
            }
            if case .counterpartyNode = anchor { return "counterparty" }
            return "fallback"
        }()
        SecretaryDisplayCleanLog.log(
            surface: "currentOpportunity",
            titleSource: titleSourceForLog,
            bodySource: "summary",
            strippedInternal: false
        )
        #endif

        let option: SecretaryComparePanel.Option = {
            guard let match = selectedMatch else {
                return SecretaryComparePanel.Option(
                    candidateCounterpartyID: detail.thread.selectedCounterpartyID,
                    title: threadTitle(detail),
                    subtitle: "New activity in this thread",
                    trustLine: nonEmpty(secondHalf?.operatingContext.trust)
                        ?? "Trust is limited or not yet established.",
                    exposureLine: secondHalf.flatMap { display in
                        nonEmpty(display.boundary.externalEffectLine)
                        ?? nonEmpty(display.boundary.reason)
                    } ?? threadBoundaryLine(detail),
                    recommendationLine: threadNextMove(detail),
                    isPreferred: true,
                    isActionable: secondHalf?.needsHumanAttention == true || secondHalf?.hasDecisionPacket == true,
                    strengthReasons: [],
                    weaknessReasons: [],
                    missingFacts: compareMissingFacts(secondHalf: secondHalf, detail: detail),
                    readinessLine: nonEmpty(secondHalf?.status.readiness)
                        ?? nonEmpty(secondHalf?.operatingContext.readiness),
                    boundaryLine: nil,
                    nextMoveLine: threadNextMove(detail)
                )
            }

            return compareOptionForMatch(
                match,
                detail: detail,
                secondHalf: secondHalf,
                isPreferred: true
            )
        }()

        let exposureLine = option.exposureLine
        let recommendation = option.recommendationLine

        var extraSections: [SecretaryPanelSectionDisplay] = []

        if let secondHalf {
            extraSections.append(contentsOf: secondHalfExtraSections(secondHalf))
        }

        extraSections.append(contentsOf: compareMatchExtraSections(
            match: selectedMatch,
            detail: detail
        ))

        return SecretaryComparePanel.Display(
            title: threadTitle(detail, surface: "opportunity"),
            summary: nonEmpty(secondHalf?.decision?.summary)
                ?? nonEmpty(secondHalf?.requesterReview?.subtitle)
                ?? nonEmpty(detail.summary)
                ?? foundSummary(detail),
            options: [option],
            primaryTitle: "Add to trusted",
            secondaryTitle: "Keep searching",
            threadID: detail.thread.id,
            panelKind: secondHalf?.hasDecisionPacket == true ? "Decision Review" : "Thread review",
            recommendation: recommendation,
            exposureSummary: exposureLine,
            trustSummary: option.trustLine,
            readinessSummary: option.readinessLine,
            missingFacts: option.missingFacts,
            strengthReasons: option.strengthReasons,
            weaknessReasons: option.weaknessReasons,
            extraSections: extraSections
        )
    }
    
    static func compareDisplay(
        for item: ExchangeModels.InboxItem
    ) -> SecretaryComparePanel.Display {
        if let secondHalf = secondHalfDisplay(for: item),
           secondHalf.hasRequesterReview || secondHalf.hasDecisionPacket {
            let review = secondHalf.requesterReview
            let decision = secondHalf.decision

            return SecretaryComparePanel.Display(
                title: displayTitle(for: item),
                summary: nonEmpty(decision?.summary)
                    ?? nonEmpty(review?.subtitle)
                    ?? nonEmpty(secondHalf.summary)
                    ?? "The secretary has framed the current opportunity for review.",
                options: [
                    SecretaryComparePanel.Option(
                        title: nonEmpty(review?.title)
                            ?? nonEmpty(secondHalf.hero.title)
                            ?? "Open thread to review",
                        subtitle: nonEmpty(review?.recommendation)
                            ?? nonEmpty(decision?.recommendation)
                            ?? nonEmpty(secondHalf.recommendation)
                            ?? "Review details in the thread.",
                        trustLine: nonEmpty(secondHalf.operatingContext.trust)
                            ?? "Trust context is available in the second-half frame.",
                        exposureLine: secondHalfBoundaryLine(secondHalf)
                            ?? "Nothing commitment-bearing should leave without approval.",
                        recommendationLine: nonEmpty(decision?.recommendation)
                            ?? nonEmpty(review?.nextMoveTitle)
                            ?? secondHalfNextMoveLine(secondHalf)
                            ?? "Open the thread for full review.",
                        isPreferred: true,
                        isActionable: secondHalf.needsHumanAttention || secondHalf.hasDecisionPacket,
                        strengthReasons: cleanedList(review?.strengthReasons ?? []),
                        weaknessReasons: cleanedList(review?.weaknessReasons ?? []),
                        missingFacts: cleanedList(review?.missingFacts ?? secondHalf.operatingContext.userFacingMissingFacts),
                        readinessLine: nonEmpty(secondHalf.status.readiness)
                            ?? nonEmpty(secondHalf.operatingContext.readiness),
                        boundaryLine: secondHalfBoundaryLine(secondHalf),
                        nextMoveLine: secondHalfNextMoveLine(secondHalf)
                    )
                ],
                primaryTitle: "Add to trusted",
                secondaryTitle: "Keep searching",
                threadID: item.threadID,
                panelKind: secondHalf.hasDecisionPacket ? "Decision Review" : "Thread review",
                recommendation: nonEmpty(decision?.recommendation)
                    ?? nonEmpty(review?.recommendation)
                    ?? nonEmpty(secondHalf.recommendation),
                exposureSummary: secondHalfBoundaryLine(secondHalf),
                trustSummary: nonEmpty(secondHalf.operatingContext.trust),
                readinessSummary: nonEmpty(secondHalf.status.readiness)
                    ?? nonEmpty(secondHalf.operatingContext.readiness),
                missingFacts: cleanedList(review?.missingFacts ?? secondHalf.operatingContext.userFacingMissingFacts),
                strengthReasons: cleanedList(review?.strengthReasons ?? []),
                weaknessReasons: cleanedList(review?.weaknessReasons ?? []),
                extraSections: secondHalfExtraSections(secondHalf)
            )
        }

        let selectedTitle = nonEmpty(item.selectedCounterpartyName) ?? "Current visible path"
        let selectedSummary = nonEmpty(item.selectedMatchSummary)
            ?? "This is the currently surfaced path from the thread snapshot."
        let trustLine = nonEmpty(item.trustPathSummary)
            ?? "Trust visibility is limited from this snapshot."
        let exposureLine = nonEmpty(item.deliveryStatusText)
            ?? (isWaiting(item)
                ? "Waiting on the other side after your last outward move."
                : "Nothing sent yet.")
        let recommendation = nonEmpty(item.nextStepText)
            ?? "Open the full thread to inspect actual candidates before deciding."

        return SecretaryComparePanel.Display(
            title: displayTitle(for: item),
            summary: "Multiple candidates were considered. Open the compare view to review other profiles. Reviewing does not contact them.",
            options: [
                SecretaryComparePanel.Option(
                    title: selectedTitle,
                    subtitle: selectedSummary,
                    trustLine: trustLine,
                    exposureLine: exposureLine,
                    recommendationLine: recommendation,
                    isPreferred: true,
                    isActionable: false
                )
            ],
            primaryTitle: "Add to trusted",
            secondaryTitle: "Keep searching",
            threadID: item.threadID
        )
    }
    
    static func trustedPathDisplay(
        for item: ExchangeModels.InboxItem
    ) -> SecretaryTrustedPathPanel.Display {
        SecretaryTrustedPathPanel.Display(
            title: nonEmpty(item.selectedCounterpartyName) ?? displayTitle(for: item),
            summary: nonEmpty(item.trustPathSummary)
            ?? nonEmpty(item.selectedMatchWhy)
            ?? nonEmpty(item.subtitle)
            ?? "A trusted or relationship-based path is visible on this thread.",
            relationshipLabel: trustedBadge(for: item),
            trustLabel: trustLabel(for: item),
            activityLabel: trustedActivityLabel(for: item),
            examples: trustedExamples(for: item),
            primaryTitle: "Open thread",
            secondaryTitle: "Back",
            threadID: item.threadID
        )
    }
    
    // MARK: - Thread detail projection
    
    static func approvalDisplay(
        for detail: ExchangeModels.ThreadDetail
    ) -> SecretaryApprovalPanelDisplay {
        let actionableDraft = latestPersistedActionableExternalOutboundDraft(for: detail)
        let outboundTruth = userFacingPersistedOutboundDraft(for: detail)

        if let secondHalf = secondHalfDisplay(for: detail),
           secondHalf.needsHumanAttention || secondHalf.hasDecisionPacket
            || latestPendingApproval(for: detail) != nil || outboundTruth {
            let pendingApproval = latestPendingApproval(for: detail)
            let userDirectedPick = ExchangeFacade.pickUserDirectedOutboundDraftForPreparedSend(
                drafts: detail.drafts,
                preferredDraftID: nil,
                thread: detail.thread
            ) != nil
            let preparedSendBlocked = secondHalfBlocksPreparedSend(secondHalf)
            let prefersSecondHalfPreparedSend =
                pendingApproval == nil &&
                outboundTruth &&
                userDirectedPick &&
                !preparedSendBlocked

            let providerCoordination = secondHalfProviderInboundNeedsCoordinationInput(secondHalf, detail: detail)
            let softenApprovalPrimary =
                providerCoordination || (pendingApproval != nil && !outboundTruth)
            let missingFactLines = cleanedList(secondHalf.operatingContext.userFacingMissingFacts)
            let suppressStaleWaitingInDecisionPacket = hasActionableExternalOutboundDraft(in: detail)
            let approvalSummary = approvalDisplayFilteredDecisionPacketLine(
                nonEmpty(secondHalf.decision?.summary)
                    ?? nonEmpty(secondHalf.summary)
                    ?? nonEmpty(secondHalf.recommendation),
                suppressStaleWaitingWhenActionableDraft: suppressStaleWaitingInDecisionPacket
            ) ?? threadHeroSummary(detail)
            let primaryApprovalTitle: String = {
                if prefersSecondHalfPreparedSend {
                    if threadViewAutonomousRoutineSuppressesManualSend(for: detail) {
                        return "View draft"
                    }
                    if threadViewAutonomyGateDeniedExplanation(for: detail) != nil {
                        return softenApprovalPrimary
                            ? (missingFactLines.isEmpty ? "Review request" : "Answer needed")
                            : "Review"
                    }
                    return "Send"
                }
                if softenApprovalPrimary {
                    return missingFactLines.isEmpty ? "Review request" : "Answer needed"
                }
                return "Approve"
            }()

            return SecretaryApprovalPanelDisplay(
                title: threadTitle(detail),
                decisionType: secondHalf.hasDecisionPacket ? "Decision" : "Draft Approval",
                summary: approvalSummary,
                boundary: secondHalfBoundaryLine(secondHalf) ?? threadBoundaryLine(detail),
                draftSubject: outboundTruth
                    ? (nonEmpty(secondHalf.draft?.subject) ?? actionableDraft?.subject)
                    : nil,
                draftBody: outboundTruth
                    ? (nonEmpty(secondHalf.draft?.bodyPreview) ?? actionableDraft?.body)
                    : nil,
                rationale: nonEmpty(secondHalf.nextMove?.rationale)
                    ?? nonEmpty(secondHalf.escalationReason)
                    ?? pendingApproval?.rationale,
                primaryTitle: primaryApprovalTitle,
                secondaryTitle: "Reject",
                threadID: detail.thread.id,
                approvalID: pendingApproval?.id,
                prefersSecondHalfPreparedSend: prefersSecondHalfPreparedSend,
                decisionSummary: approvalDisplayFilteredDecisionPacketLine(
                    nonEmpty(secondHalf.decision?.summary),
                    suppressStaleWaitingWhenActionableDraft: suppressStaleWaitingInDecisionPacket
                ),
                recommendation: approvalDisplayFilteredDecisionPacketLine(
                    nonEmpty(secondHalf.decision?.recommendation) ?? nonEmpty(secondHalf.recommendation),
                    suppressStaleWaitingWhenActionableDraft: suppressStaleWaitingInDecisionPacket
                ),
                commitmentBoundaryTitle: nonEmpty(secondHalf.boundary.title),
                commitmentBoundaryReason: nonEmpty(secondHalf.boundary.reason)
                    ?? nonEmpty(secondHalf.boundary.externalEffectLine),
                requiresHumanApproval: secondHalf.boundary.requiresHumanApproval || preparedSendBlocked,
                clarifiedFacts: secondHalfClarifiedFacts(secondHalf),
                unresolvedIssues: secondHalfUnresolvedIssues(secondHalf),
                tradeoffs: secondHalfTradeoffs(secondHalf),
                whatChanged: secondHalfWhatChanged(secondHalf),
                approvalReasons: secondHalfApprovalReasons(secondHalf),
                extraSections: secondHalfExtraSections(secondHalf)
            )
        }

        let pendingApproval = latestPendingApproval(for: detail)
        let softenLegacy = pendingApproval != nil && !userFacingPersistedOutboundDraft(for: detail)

        return SecretaryApprovalPanelDisplay(
            title: threadTitle(detail),
            decisionType: "Draft Approval",
            summary: threadHeroSummary(detail),
            boundary: threadBoundaryLine(detail),
            draftSubject: actionableDraft?.subject,
            draftBody: actionableDraft?.body,
            rationale: pendingApproval?.rationale,
            primaryTitle: softenLegacy ? "Review request" : "Approve",
            secondaryTitle: "Reject",
            threadID: detail.thread.id,
            approvalID: pendingApproval?.id
        )
    }
    
    static func recoveryDisplay(
        for detail: ExchangeModels.ThreadDetail
    ) -> SecretaryRecoveryPanel.Display {
        if let secondHalf = secondHalfDisplay(for: detail),
           secondHalf.placement == .recovery || secondHalf.status.isBlocking {
            return SecretaryRecoveryPanel.Display(
                title: threadTitle(detail),
                recoveryType: visibleThreadStatus(for: detail).label,
                whatHappened: nonEmpty(secondHalf.summary)
                    ?? nonEmpty(secondHalf.hero.statusLine)
                    ?? detail.thread.latestFailure?.whatHappened
                ?? "The thread needs recovery attention.",
                whatDidNotHappen: nonEmpty(secondHalf.boundary.externalEffectLine)
                ?? detail.thread.latestFailure?.whatDidNotHappen
                ?? "The intended move did not complete.",
                externalEffect: secondHalfBoundaryLine(secondHalf)
                ?? detail.thread.latestFailure?.externalEffect.summaryLine
                ?? threadBoundaryLine(detail),
                bestNextMove: secondHalfNextMoveLine(secondHalf)
                ?? detail.thread.latestFailure?.recommendedNextStep.summaryLine
                ?? threadNextMove(detail),
                primaryTitle: "Continue recovery",
                secondaryTitle: "Hold",
                threadID: detail.thread.id
            )
        }
        
        let failure = detail.thread.latestFailure
        
        return SecretaryRecoveryPanel.Display(
            title: threadTitle(detail),
            recoveryType: recoveryBadge(for: detail),
            whatHappened: failure?.whatHappened ?? "The thread needs recovery attention.",
            whatDidNotHappen: failure?.whatDidNotHappen ?? "The intended move did not complete.",
            externalEffect: failure?.externalEffect.summaryLine ?? threadBoundaryLine(detail),
            bestNextMove: failure?.recommendedNextStep.summaryLine ?? threadNextMove(detail),
            primaryTitle: "Continue recovery",
            secondaryTitle: "Hold",
            threadID: detail.thread.id
        )
    }
    
    static func activityDisplay(
        for detail: ExchangeModels.ThreadDetail
    ) -> SecretaryActivityPanelDisplay {
        let detailVS = visibleThreadStatus(for: detail)
        if let secondHalf = secondHalfDisplay(for: detail) {
            let outboundTruth = userFacingPersistedOutboundDraft(for: detail)
            let execution = secondHalfExecutionDisplay(
                for: secondHalf,
                fallbackTitle: threadTitle(detail),
                fallbackBoundary: threadBoundaryLine(detail),
                persistedActionableExternalOutboundDraft: outboundTruth,
                statusLabel: detailVS.label
            )

            return SecretaryActivityPanelDisplay(
                title: threadTitle(detail),
                activityType: detailVS.label,
                latestMovement: nonEmpty(secondHalf.nextMove?.title)
                    ?? nonEmpty(secondHalf.hero.statusLine)
                    ?? nonEmpty(secondHalf.summary)
                    ?? threadHeroSummary(detail),
                meaning: nonEmpty(secondHalf.summary)
                    ?? nonEmpty(secondHalf.recommendation)
                    ?? "The secretary is carrying this second-half coordination path.",
                currentState: nonEmpty(detailVS.subtitle) ?? detailVS.label,
                boundary: secondHalfBoundaryLine(secondHalf) ?? threadBoundaryLine(detail),
                nextMove: secondHalfNextMoveLine(secondHalf) ?? threadNextMove(detail),
                primaryTitle: secondHalfPrimaryCTA(
                    secondHalf,
                    fallback: "Continue",
                    persistedActionableExternalOutboundDraft: outboundTruth
                ),
                secondaryTitle: "Back",
                execution: execution,
                threadID: detail.thread.id,
                whatChanged: secondHalfWhatChanged(secondHalf),
                operatingContext: secondHalfOperatingContextLines(secondHalf),
                stanceLines: secondHalfStanceLines(secondHalf),
                decisionLines: secondHalfDecisionLines(secondHalf),
                providerReceptionLines: secondHalfProviderReceptionLines(secondHalf),
                requesterReviewLines: secondHalfRequesterReviewLines(secondHalf),
                draftFactsUsed: secondHalfDraftFactsUsed(secondHalf),
                extraSections: secondHalfExtraSections(secondHalf)
            )
        }

        return SecretaryActivityPanelDisplay(
            title: threadTitle(detail),
            activityType: detailVS.label,
            latestMovement: threadHeroSummary(detail),
            meaning: nonEmpty(detail.summary) ?? "The thread is still active and evolving.",
            currentState: nonEmpty(detailVS.subtitle) ?? detailVS.label,
            boundary: threadBoundaryLine(detail),
            nextMove: threadNextMove(detail),
            primaryTitle: "Continue",
            secondaryTitle: "Back",
            execution: nil,
            threadID: detail.thread.id
        )
    }
    
    static func recoveryBadge(for detail: ExchangeModels.ThreadDetail) -> String {
        switch detail.thread.state {
        case .blockedByDeliveryFailure:
            return "Delivery"
        case .declined:
            return "Declined"
        case .stalled:
            return "Stalled"
        case .blockedBySystemFailure:
            return "System"
        default:
            return "Recovery"
        }
    }
    
    // MARK: - Thread helpers
    
    static func latestPendingApproval(
        for detail: ExchangeModels.ThreadDetail
    ) -> ExchangeApproval? {
        detail.approvals
            .filter { approval in
                approval.status == .pending &&
                    !isSuppressibleProviderInboundNeedsInputApproval(
                        approval: approval,
                        detail: detail
                    )
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
    }

    private static func isSuppressibleProviderInboundNeedsInputApproval(
        approval: ExchangeApproval,
        detail: ExchangeModels.ThreadDetail
    ) -> Bool {
        guard approval.status == .pending else { return false }
        guard approval.draftID == nil else { return false }
        guard threadDetailIsInboundProviderStyle(detail) else { return false }
        guard !hasActionableExternalOutboundDraft(in: detail) else { return false }
        guard !outboundSendEvidence(in: detail) else { return false }
        guard !detailHasActiveOutboundOutboxSendingWork(in: detail) else { return false }

        let sh = secondHalfDisplay(for: detail)
        if secondHalfProviderInboundNeedsCoordinationInput(sh, detail: detail) {
            return true
        }

        let nextAction = nonEmpty(detail.thread.metadata["second_half_next_action"])?.lowercased() ?? ""
        let command = nonEmpty(detail.thread.metadata["second_half_command"])?.lowercased() ?? ""
        return nextAction.contains("requestuserinput")
            || nextAction.contains("askprovideruser")
            || nextAction.contains("needsproviderinput")
            || command == "needsuserinput"
    }
    
    static func latestDraft(
        for detail: ExchangeModels.ThreadDetail
    ) -> ExchangeMessageDraft? {
        detail.drafts
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
    }

    /// Newest store-backed actionable external outbound draft (for user-facing surfaces).
    static func latestPersistedActionableExternalOutboundDraft(
        for detail: ExchangeModels.ThreadDetail
    ) -> ExchangeMessageDraft? {
        ExchangeMessageDraft.newestUserFacingRenderableExternalOutboundDraft(
            in: detail.drafts,
            thread: detail.thread,
            turns: detail.turns
        )
    }

    // MARK: - Safe auto-follow-ups settings nudge

    /// User-facing helper under “Draft ready” when autonomous follow-up is off.
    /// Projection-only; does not affect send queues, drafts, or policy gates.
    static func safeAutoFollowUpsEnableNudgeLineIfApplicable(
        for detail: ExchangeModels.ThreadDetail,
        defaults: UserDefaults = .standard
    ) -> String? {
        switch ExchangeAutonomousSendPolicy.currentThreadAutonomyAuthority(defaults: defaults) {
        case .routineAutoRespond, .fullWithinBoundaries:
            return nil
        case .manualOnly, .draftOnly, .missing, .invalid:
            break
        }

        guard hasActionableExternalOutboundDraft(in: detail) else { return nil }

        guard latestPendingApproval(for: detail) == nil else { return nil }

        if case .awaitingApproval = detail.thread.state { return nil }

        if let delivery = detail.thread.delivery, delivery.status == .pendingApproval {
            return nil
        }

        guard detail.thread.latestFailure == nil else { return nil }

        if let delivery = detail.thread.delivery, delivery.status == .failed {
            return nil
        }

        if case .blockedByDeliveryFailure = detail.thread.state { return nil }
        if case .blockedBySystemFailure = detail.thread.state { return nil }
        if case .noViableMatch = detail.thread.state { return nil }

        guard !isAwaitingResponse(detail) else { return nil }

        if detail.turns.contains(where: { $0.kind == .replyReceived }) {
            return nil
        }

        if let display = secondHalfDisplay(for: detail) {
            if display.placement == .needsApproval { return nil }
            if display.boundary.requiresHumanApproval { return nil }
            if display.status.role == ExchangeSecondHalfRole.provider.displayTitle { return nil }
            if display.placement == .recovery || display.status.isBlocking { return nil }
        }

        let specificCopy =
            "Auto-send is off. Turn on Safe auto-follow-ups to let Unify send low-risk clarification messages for you."
        let fallbackCopy =
            "Auto-send is off. You can enable Safe auto-follow-ups in Discovery settings."

        if let display = secondHalfDisplay(for: detail),
           display.status.role == ExchangeSecondHalfRole.requester.displayTitle,
           display.boundary.allowsAutonomousSending {
            return specificCopy
        }

        return fallbackCopy
    }
    
    static func selectedCounterpartyName(
        for detail: ExchangeModels.ThreadDetail
    ) -> String? {
        guard let selectedID = detail.thread.selectedCounterpartyID else { return nil }
        guard let selected = detail.counterparties.first(where: { $0.id == selectedID }) else { return nil }
        return nonEmpty(selected.bestDisplayLine)
    }
    
    static func threadTitle(
        _ detail: ExchangeModels.ThreadDetail,
        surface: String = "detail"
    ) -> String {
        let isProviderInbound = ExchangeThreadCardTitleProjection.isProviderInboundThread(
            metadata: detail.thread.metadata
        )

        let inboundRequesterAsk: String? = {
            guard isProviderInbound else { return nil }
            return ExchangeThreadCardTitleProjection.latestInboundRequesterAsk(from: detail.turns)
        }()

        let requestCapturedFromTurn: String? = {
            guard !isProviderInbound else { return nil }
            if detail.thread.threadRole == .candidateCoordination {
                return ExchangeThreadSearchQueryDisplay.displaySearchQuery(
                    for: detail.thread,
                    turns: detail.turns
                )?.text ?? ExchangeThreadCardTitleProjection.requestCapturedText(from: detail.turns)
            }
            return ExchangeThreadCardTitleProjection.requestCapturedText(from: detail.turns)
        }()

        let inquirySummary: String? = {
            guard isProviderInbound else { return nil }
            if let summary = nonEmptyJoinedLine(detail.secondHalfDisplay?.providerReception?.inquirySummary) {
                return summary
            }
            if let ask = nonEmptyJoinedLine(detail.secondHalfDisplay?.providerReception?.requesterAsk) {
                return ask
            }
            let objective = detail.thread.intent.objective.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !objective.isEmpty else { return nil }
            if ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate(objective) { return nil }
            let lower = objective.lowercased()
            if lower.hasPrefix("review and respond to the inbound") { return nil }
            return objective
        }()

        let inboundSenderDisplay: String? = {
            guard isProviderInbound else { return nil }

            if let selected = selectedCounterpartyName(for: detail) {
                return selected
            }

            return nonEmpty(detail.selectedCounterparty?.bestDisplayLine)
        }()

        let pick = ExchangeThreadCardTitleProjection.threadHeaderTitle(
            requestCapturedFromTurn: requestCapturedFromTurn,
            interpretationUserQuestion: isProviderInbound ? nil : detail.interpretationQuestion,
            threadStoredTitle: detail.thread.title,
            draftedSubject: {
                let s = latestPersistedActionableExternalOutboundDraft(for: detail)?
                    .subject?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return s.isEmpty ? nil : s
            }(),
            hydratedOpportunityTitle: offerOrProfileHeadlineFromDetail(detail),
            threadID: detail.thread.id,
            surface: surface,
            fallback: isProviderInbound ? "New inquiry" : "New request",
            isProviderInbound: isProviderInbound,
            inboundRequesterAsk: inboundRequesterAsk,
            inquirySummary: inquirySummary,
            inboundSenderDisplay: inboundSenderDisplay
        )
        return ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            pick.title,
            field: .title,
            fallback: isProviderInbound ? "New inquiry" : "Thread"
        )
    }

    private static func offerOrProfileHeadlineFromDetail(_ detail: ExchangeModels.ThreadDetail) -> String? {
        guard let match = detail.selectedMatch else { return nil }
        func meta(_ key: String) -> String? {
            let s = match.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return s.isEmpty ? nil : s
        }
        let lead = ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: detail.selectedOfferID,
            selectedPublicProfileID: detail.selectedPublicProfileID
        )
        switch lead {
        case .offerLed:
            return meta("selected_offer_title")
                ?? meta("public_profile_display_name")
                ?? meta("public_profile_headline")
        case .profileLed:
            return meta("public_profile_display_name")
                ?? meta("public_profile_headline")
                ?? meta("selected_offer_title")
        case .ambiguous:
            return meta("selected_offer_title")
                ?? meta("public_profile_display_name")
                ?? meta("public_profile_headline")
        }
    }
    
    static func threadHeroSummary(_ detail: ExchangeModels.ThreadDetail) -> String {
        if isSocialConnectionThread(detail) {
            return socialConnectionSummary(for: detail)
        }
        if let autoFollowUpLine = autoFollowUpOffLineIfApplicable(detail) {
            return autoFollowUpLine
        }
        if let secondHalf = secondHalfDisplay(for: detail),
           let summary = secondHalfSummaryLine(secondHalf) {
            return summary
        }
        
        if latestPendingApproval(for: detail) != nil {
            return "A concrete path is prepared and waiting for your review before anything external moves."
        }
        
        if isClarification(detail) {
            return "The thread is waiting for one missing detail before search can continue."
        }
        
        if detail.thread.latestFailure != nil {
            return "This thread is in recovery. The failure should stay visible and legible."
        }
        
        if showsFoundState(detail) {
            return foundSummary(detail)
        }
        
        if isAwaitingResponse(detail) {
            return "This thread is waiting on the other side after earlier movement."
        }
        
        let resolved = nonEmpty(detail.summary)
            ?? "The secretary is actively holding this coordination path."
        return ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            resolved,
            field: .body,
            fallback: "New activity in this thread"
        )
    }
    
    /// Returns a short annotation string when the thread was autonomously initiated by the
    /// For You pass, so the UI can show a visible "Autonomously contacted" label.
    static func autonomousContactNote(for detail: ExchangeModels.ThreadDetail) -> String? {
        let meta = detail.thread.metadata
        guard meta["autonomous_first_contact"] == "true" else { return nil }
        let mode = (meta["autonomy_mode"] ?? "").lowercased()
        switch mode {
        case "safeautosend":
            return "The secretary reached out from a For You opportunity."
        case "draftonly":
            return "The secretary prepared this from a For You opportunity."
        case "discoveronly", "":
            return "The secretary started this from a For You opportunity."
        default:
            if mode.contains("draft") {
                return "The secretary prepared this from a For You opportunity."
            }
            if mode.contains("send") {
                return "The secretary reached out from a For You opportunity."
            }
            return "The secretary started this from a For You opportunity."
        }
    }

    #if DEBUG
    /// Raw autonomy metadata for engineering review (not shown in release).
    static func autonomousContactNoteDebug(for detail: ExchangeModels.ThreadDetail) -> String? {
        let meta = detail.thread.metadata
        guard meta["autonomous_first_contact"] == "true" else { return nil }
        let source = meta["autonomy_source"] ?? "for_you"
        let mode = meta["autonomy_mode"] ?? "safeAutoSend"
        return "autonomy_source=\(source) · autonomy_mode=\(mode)"
    }
    #endif

    static func threadBoundaryLine(_ detail: ExchangeModels.ThreadDetail) -> String {
        func sanitize(_ raw: String) -> String {
            ExchangeUserFacingCopySanitizer.sanitizeOrFallback(raw, field: .subtitle, fallback: "Private.")
        }

        if let shCoord = secondHalfDisplay(for: detail),
           secondHalfProviderInboundNeedsCoordinationInput(shCoord, detail: detail) {
            let base = "Needs your reply before Unify can send."
            if let tail = providerInboundCoordinationSubtitleLines(shCoord), !tail.isEmpty {
                return sanitize("\(base) Missing: \(tail).")
            }
            return sanitize(base)
        }

        if let secondHalf = secondHalfDisplay(for: detail),
           let boundary = secondHalfBoundaryLine(secondHalf) {
            return sanitize(boundary)
        }

        if let delivery = detail.thread.delivery {
            switch delivery.status {
            case .notStarted:
                return sanitize("Not sent yet.")
            case .pendingApproval:
                return sanitize("Not sent yet — needs your approval.")
            case .readyToSend:
                if !hasActionableExternalOutboundDraft(in: detail) {
                    return sanitize("Not sent yet — routing or a sendable draft is still missing.")
                }
                return sanitize("Ready to send.")
            case .sending:
                if !sendingOutboundIsTruthful(for: detail) {
                    return sanitize("Not sent yet.")
                }
                return sanitize("Sending…")
            case .sent:
                return sanitize("Sent. Waiting on the other side.")
            case .failed:
                return sanitize("Couldn't send.")
            @unknown default:
                return sanitize("Still updating.")
            }
        }

        if isAwaitingResponse(detail) {
            return sanitize("Sent. Waiting on the other side.")
        }

        if latestPendingApproval(for: detail) != nil || hasActionableExternalOutboundDraft(in: detail) {
            return sanitize("Not sent yet.")
        }

        return sanitize("Private.")
    }
    
    static func threadNextMove(_ detail: ExchangeModels.ThreadDetail) -> String {
        if let autoFollowUpLine = autoFollowUpOffLineIfApplicable(detail) {
            return autoFollowUpLine
        }
        if let secondHalf = secondHalfDisplay(for: detail),
           let next = secondHalfNextMoveLine(secondHalf) {
            return next
        }
        
        if let approval = latestPendingApproval(for: detail) {
            return nonEmpty(approval.rationale)
            ?? "Review the prepared draft and decide whether it should move outward."
        }
        
        if isClarification(detail) {
            return clarificationQuestion(detail)
        }
        
        if let failure = detail.thread.latestFailure {
            return failure.recommendedNextStep.summaryLine
        }
        
        if isAwaitingResponse(detail) {
            return "Wait for the reply window or prepare a bounded follow-up."
        }
        
        if showsFoundState(detail) {
            if hasActionableExternalOutboundDraft(in: detail) {
                return "Review the prepared draft before deciding whether it should move."
            }
            if selectedCounterpartyName(for: detail) != nil {
                return "Inspect the selected path and decide whether to continue."
            }
        }
        
        if let next = nonEmpty(detail.interpretationNextStep) {
            return next
        }
        
        switch detail.thread.state {
        case .awaitingApproval:
            return hasActionableExternalOutboundDraft(in: detail)
                ? "Review the current draft and decide whether it should move."
                : "Review before anything moves outward."
        case .needsClarification:
            return "Clarify the request before the secretary continues."
        case .searching:
            return detail.thread.selectedCounterpartyID != nil
            ? "Inspect the selected path."
            : "Let the search continue or inspect candidate quality."
        case .matchFound:
            if hasActionableExternalOutboundDraft(in: detail) {
                return "Review the prepared draft before deciding whether it should move."
            }
            return "Continue on this found path."
        case .matchCandidatesWeak:
            return "Review the weak paths and decide whether to refine or broaden."
        case .noViableMatch:
            return "Adjust the request or broaden the route."
        case .drafting:
            return "Review the path as the draft takes shape."
        case .draftReady:
            return hasActionableExternalOutboundDraft(in: detail)
                ? "Review the prepared draft."
                : "Review what matters before deciding the next step."
        case .sending:
            return "Wait for delivery confirmation."
        case .blockedByDeliveryFailure:
            return "Inspect the failed move and choose the best recovery path."
        case .awaitingResponse:
            return "Wait for the reply window or prepare a bounded follow-up."
        case .declined:
            return "Review the decline and decide whether to reopen or close."
        case .stalled:
            return "Reassess the thread and choose whether to continue."
        case .resolved:
            return "Review the outcome."
        case .blockedBySystemFailure:
            return "Inspect the system failure and retry when the path is clear."
        }
    }

    private static func autoFollowUpOffLineIfApplicable(
        _ detail: ExchangeModels.ThreadDetail
    ) -> String? {
        let meta = detail.thread.metadata
        guard meta["autonomous_send_outcome"] == "disabledByUserSetting" else { return nil }
        let lane = meta["autonomous_send_lane"] ?? ""
        if lane == "requester_outbound" || lane == "provider_auto_response" {
            return "Auto-follow-ups are off. Review and send this message manually."
        }
        return nil
    }
    
    static func clarificationQuestion(_ detail: ExchangeModels.ThreadDetail) -> String {
        if let q = nonEmpty(detail.interpretationQuestion) {
            return q
        }
        
        if case .needsClarification(let status) = detail.thread.state,
           let q = nonEmpty(status.question) {
            return q
        }
        
        return "A bit more detail is needed before this can continue."
    }
    
    static func isClarification(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        if case .needsClarification = detail.thread.state { return true }
        if detail.thread.interpretation?.needsClarification == true { return true }
        return false
    }
    
    static func showsFoundState(_ detail: ExchangeModels.ThreadDetail) -> Bool {
        if let secondHalf = secondHalfDisplay(for: detail) {
            if secondHalf.hasDecisionPacket ||
                secondHalf.hasRequesterReview ||
                secondHalf.hasProviderReception ||
                hasActionableExternalOutboundDraft(in: detail) ||
                secondHalf.placement == .decisionReady ||
                secondHalf.placement == .requesterReview ||
                secondHalf.placement == .providerReception {
                return true
            }

            if secondHalf.placement == .recovery || secondHalf.status.isBlocking {
                return false
            }
        }

        if isClarification(detail) { return false }
        if detail.thread.latestFailure != nil { return false }

        if case .matchFound = detail.thread.state {
            return true
        }

        if latestPendingApproval(for: detail) != nil { return true }
        if hasActionableExternalOutboundDraft(in: detail) { return true }
        if selectedCounterpartyName(for: detail) != nil { return true }

        return false
    }

    static func foundSummary(_ detail: ExchangeModels.ThreadDetail) -> String {
        if isSocialConnectionThread(detail) {
            if let selected = selectedCounterpartyName(for: detail) {
                return "\(selected) is a profile connection to explore."
            }
            return "This is a profile-led social connection."
        }
        if let secondHalf = secondHalfDisplay(for: detail) {
            return nonEmpty(secondHalf.decision?.summary)
                ?? nonEmpty(secondHalf.requesterReview?.subtitle)
                ?? nonEmpty(secondHalf.providerReception?.inquirySummary)
                ?? nonEmpty(secondHalf.summary)
                ?? nonEmpty(secondHalf.recommendation)
                ?? "A second-half opportunity is ready to review."
        }

        if let selected = selectedCounterpartyName(for: detail) {
            if hasActionableExternalOutboundDraft(in: detail) {
                return "A path has been selected and a draft is now prepared around \(selected)."
            }
            return "\(selected) is currently the clearest path on this thread."
        }

        if hasActionableExternalOutboundDraft(in: detail) {
            return "A local draft is prepared and ready for review."
        }

        return nonEmpty(detail.summary) ?? "A viable result is ready to review."
    }
    
    // MARK: - Low-level helpers
    
    static func cleanUserFacingExchangeText(_ value: String?) -> String {
        guard let value else { return "" }
        let sanitized = ExchangeUserFacingCopySanitizer.cleanReceivedFederationBody(value).cleaned
        return ExchangeUserFacingCopySanitizer
            .sanitize(sanitized, field: .general)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func clean(_ value: String?) -> String {
        cleanUserFacingExchangeText(value)
    }
    
    static func clean(_ value: String?, fallback: String) -> String {
        let trimmed = clean(value)
        return trimmed.isEmpty ? fallback : trimmed
    }
    
    static func nonEmpty(_ value: String?) -> String? {
        let trimmed = clean(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonEmptyJoinedLine(_ value: String?) -> String? {
        nonEmpty(value)
    }

    private static func nonEmptyJoinedLine(_ values: [String]?) -> String? {
        values?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfBlank
    }
    
    static func firstNonEmpty(_ values: String?..., fallback: String) -> String {
        for value in values {
            let trimmed = clean(value)
            if !trimmed.isEmpty { return trimmed }
        }
        
        return fallback
    }
    
    static func firstNonEmpty(_ values: String?..., fallback: String? = nil) -> String? {
        for value in values {
            let trimmed = clean(value)
            if !trimmed.isEmpty { return trimmed }
        }
        
        guard let fallback else { return nil }
        return nonEmpty(fallback)
    }
    
    static func routeSubtitle(for item: ExchangeModels.InboxItem, fallback: String) -> String {
        let selected = clean(item.selectedCounterpartyName, fallback: "")
        if !selected.isEmpty {
            return "A likely path has formed around \(selected)."
        }
        return fallback
    }
    
    // MARK: - Rich second-half panel helpers
    
    private static func cleanedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            
            output.append(trimmed)
        }
        
        return output
    }
    
    private static func preferredVisibleMatch(
        for detail: ExchangeModels.ThreadDetail
    ) -> ExchangeMatch? {
        if let selected = detail.selectedMatch {
            return selected
        }

        if let selectedOfferID = detail.selectedOfferID,
           let match = detail.matches.first(where: { $0.offerID == selectedOfferID || $0.matchedOfferIDs.contains(selectedOfferID) }) {
            return match
        }

        if let selectedPublicProfileID = detail.selectedPublicProfileID,
           let match = detail.matches.first(where: { $0.publicProfileID == selectedPublicProfileID }) {
            return match
        }

        if let selectedCounterpartyID = detail.thread.selectedCounterpartyID,
           let match = detail.matches.first(where: { $0.counterpartyID == selectedCounterpartyID }) {
            return match
        }

        return detail.matches.sorted {
            if $0.status != $1.status {
                return $0.status == .selected
            }
            if $0.strength != $1.strength {
                return strengthRank($0.strength) > strengthRank($1.strength)
            }
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.createdAt > $1.createdAt
        }.first
    }

    /// Matches ranked for comparison UI (deduped by match id). Used only by secretary projection.
    private static func rankedComparableMatches(
        for detail: ExchangeModels.ThreadDetail
    ) -> [ExchangeMatch] {
        let sorted = detail.matches.sorted {
            if $0.status != $1.status {
                return $0.status == .selected
            }
            if $0.strength != $1.strength {
                return strengthRank($0.strength) > strengthRank($1.strength)
            }
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.createdAt > $1.createdAt
        }

        var seen = Set<ExchangeMatch.ID>()
        return sorted.filter { seen.insert($0.id).inserted }
    }

    /// True when the thread snapshot exposes two or more distinct match records to compare.
    static func hasMultipleComparePaths(for detail: ExchangeModels.ThreadDetail) -> Bool {
        rankedComparableMatches(for: detail).count >= 2
    }

    // MARK: - Discovery candidate review (visibility only; no outreach)

    static let discoveryCandidateReviewCTATitle = "View results"

    static func showsDiscoveryCandidateReviewCTA(for item: ExchangeModels.InboxItem) -> Bool {
        guard isOperationalThreadOpenAllowed(item) else { return false }
        guard item.candidateCount > 1 else { return false }
        switch item.state {
        case .matchFound, .matchCandidatesWeak:
            return true
        default:
            return false
        }
    }

    static func discoveryCandidateReviewSelectedName(for item: ExchangeModels.InboxItem) -> String {
        nonEmpty(item.selectedCounterpartyName) ?? "the top match"
    }

    static func discoveryCandidateReviewPrimaryLine(for item: ExchangeModels.InboxItem) -> String? {
        guard showsDiscoveryCandidateReviewCTA(for: item) else { return nil }
        let name = discoveryCandidateReviewSelectedName(for: item)
        return "Found \(item.candidateCount) possible matches. Checking \(name) first."
    }

    static func discoveryCandidateReviewAlternateLine(for item: ExchangeModels.InboxItem) -> String? {
        guard showsDiscoveryCandidateReviewCTA(for: item) else { return nil }
        let alts = item.alternateCandidateHeadlines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !alts.isEmpty else { return nil }
        return "Other matches: \(alts.joined(separator: ", "))."
    }

    static func discoveryCandidateReviewSummaryLines(for item: ExchangeModels.InboxItem) -> [String] {
        var lines: [String] = []
        if let primary = discoveryCandidateReviewPrimaryLine(for: item) {
            lines.append(primary)
        }
        if let alternate = discoveryCandidateReviewAlternateLine(for: item) {
            lines.append(alternate)
        }
        return lines
    }

    // MARK: - History umbrella / path rows

    /// Desk/discovery generic fallback (e.g. "Find Provider") — not user-facing History copy.
    static func isGenericProviderSearchFallbackCopy(_ raw: String?) -> Bool {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return false
        }
        if ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(text) {
            return true
        }
        return isHistoryUmbrellaLeadPlaceholderCopy(text)
    }

    /// Non-name path/lead placeholders (structural only; not a real counterparty).
    static func isHistoryUmbrellaLeadPlaceholderCopy(_ raw: String) -> Bool {
        let key = historyListNormalizedCopyKey(raw)
        let placeholders: Set<String> = [
            "provider path",
            "providerpath",
            "result path",
            "resultpath",
            "path",
            "the top match",
            "top match"
        ]
        return placeholders.contains(key)
    }

    private static func historyListNormalizedCopyKey(_ raw: String) -> String {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(\s)+"#, with: " ", options: .regularExpression)
            .lowercased()
        let alnumAndSpace = CharacterSet.alphanumerics.union(.whitespaces)
        let stripped = collapsed.unicodeScalars
            .filter { alnumAndSpace.contains($0) }
            .map { Character($0) }
        return String(stripped)
            .replacingOccurrences(of: #"(\s)+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `ExchangeVisibleThreadStatus.subtitle` coaching + engine next-step prompts — not History list facts.
    static func isExchangeVisibleStatusCoachCopy(_ raw: String?) -> Bool {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return false
        }
        if isHistoryInternalNextStepScaffoldCopy(text) { return true }

        let key = historyListNormalizedCopyKey(text)
        let compact = key.replacingOccurrences(of: " ", with: "")
        let exact: Set<String> = [
            "inspect the surfaced profile details next",
            "inspectthesurfacedprofiledetailsnext",
            "reviewing fit before anything goes out",
            "reviewingfitbeforeanythinggoesout",
            "catch up with their latest message",
            "catchupwiththeirlatestmessage",
            "unify is reviewing how you can respond",
            "unifyisreviewinghowyoucanrespond",
            "something stopped this thread from moving forward",
            "somethingstoppedthisthreadfrommovingforward",
            "review before anything goes out",
            "reviewbeforeanythinggoesout",
            "you can edit or send once approved",
            "youcaneditorisonceapproved",
            "your message is on its way",
            "yourmessageisonitsway",
            "nothing from them yet",
            "nothingfromthemyet",
            "review or refine before choosing",
            "revieworrefinebeforechoosing",
            "try refining the request",
            "tryrefiningtherequest",
            "answer the missing prompt to continue",
            "answerthemissingprompttocontinue",
            "there is a framed update to read before you decide",
            "thereisaframedupdatetoreadbeforeyoudecide"
        ]
        if exact.contains(key) || exact.contains(compact) { return true }

        let needles = [
            "inspect the surfaced",
            "inspect the selected path",
            "reviewing fit before",
            "catch up with their latest",
            "unify is reviewing how you can respond",
            "something stopped this thread",
            "review before anything goes out",
            "you can edit or send once approved",
            "your message is on its way",
            "nothing from them yet",
            "review or refine before choosing",
            "try refining the request",
            "answer the missing prompt",
            "framed update to read",
            "surfaced profile details",
            "surfaced path",
            "surfaced candidate",
            "weak match so far",
            "found strong matches",
            "found paths",
            "review matches before",
            "weak matches"
        ]
        return needles.contains { key.contains($0) }
    }

    /// Engine next-step scaffolding (e.g. compare/review prompts) — not History row copy.
    static func isHistoryInternalNextStepScaffoldCopy(_ raw: String?) -> Bool {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return false
        }
        let lower = text.lowercased()
        if lower.hasPrefix("next:") {
            text = String(text.dropFirst("next:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let key = historyListNormalizedCopyKey(text)
        let compact = key.replacingOccurrences(of: " ", with: "")
        let exact: Set<String> = [
            "review search results or compare providers",
            "reviewsearchresultsorcompareproviders",
            "review the search results or refresh the search",
            "reviewthesearchresultsorrefreshthesearch",
            "continue on this found path",
            "continueonthisfoundpath",
            "review the draft",
            "reviewthedraft"
        ]
        if exact.contains(key) || exact.contains(compact) { return true }
        let prefixes = [
            "review search results",
            "compare providers",
            "continue on this found path",
            "review the search results",
            "review the found path",
            "refresh the search"
        ]
        return prefixes.contains { key.hasPrefix($0) }
    }

    private static func historyListPresentableSegment(_ raw: String) -> String? {
        guard let line = nonEmpty(raw) else { return nil }
        guard !isGenericProviderSearchFallbackCopy(line) else { return nil }
        guard !isExchangeVisibleStatusCoachCopy(line) else { return nil }
        return line
    }

    /// Returns the line when it is safe to show on History list rows; drops generic provider-search fallbacks.
    static func historyListPresentableLine(_ raw: String?) -> String? {
        guard let line = nonEmpty(raw) else { return nil }
        if isGenericProviderSearchFallbackCopy(line) { return nil }
        if isExchangeVisibleStatusCoachCopy(line) { return nil }

        let separators = [" · ", " - ", " — ", ", ", "\n"]
        for separator in separators where line.contains(separator) {
            let parts = line
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap { historyListPresentableSegment($0) }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: " · ")
        }
        return line
    }

    /// Joins context fragments, omitting generic provider-search fallback segments.
    static func historyListPresentableJoinedContext(_ raw: String?) -> String? {
        guard let raw = nonEmpty(raw) else { return nil }
        let parts = raw
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { part -> String? in
                historyListPresentableLine(part)
            }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    static func historyDiscoveryReviewSubtitle(for item: ExchangeModels.InboxItem) -> String? {
        guard showsDiscoveryCandidateReviewCTA(for: item) else { return nil }
        let selectedName = discoveryCandidateReviewSelectedName(for: item)
        if isGenericProviderSearchFallbackCopy(selectedName) {
            let count = max(1, item.candidateCount)
            return count == 1 ? "Found 1 possible match." : "Found \(count) possible matches."
        }
        return historyListPresentableLine(discoveryCandidateReviewPrimaryLine(for: item))
    }

    static func historyPathDisplayTitle(for child: ExchangeModels.CoordinationChildThreadSummary) -> String {
        if let name = historyListPresentableLine(child.displayName) { return name }
        if let headline = historyListPresentableLine(child.headline) { return headline }
        if let summary = historyListPresentableLine(child.matchSummary) { return summary }
        return "Path"
    }

    static func historyPathStatusLabel(for child: ExchangeModels.CoordinationChildThreadSummary) -> String {
        if let title = nonEmpty(child.stateTitle) { return title }
        if let state = child.childState { return state.phaseTitle }
        return "Open"
    }

    static func historyPathSearchHaystack(for child: ExchangeModels.CoordinationChildThreadSummary) -> String {
        [
            "Result path",
            "Path",
            historyPathDisplayTitle(for: child),
            historyPathStatusLabel(for: child),
            child.matchSummary ?? "",
            child.headline ?? "",
        ]
        .joined(separator: " ")
    }

    static func historyUmbrellaPathsFootnote(for item: ExchangeModels.InboxItem) -> String? {
        let children = item.coordinationChildSummaries
        guard !children.isEmpty else { return nil }

        let count = children.count
        let pathWord = count == 1 ? "path" : "paths"
        var parts: [String] = ["\(count) result \(pathWord)"]

        if let lead = historyListLeadLabel(for: item) {
            parts.append("Lead: \(lead)")
        }

        return parts.joined(separator: " · ")
    }

    private static func historyListLeadLabel(for item: ExchangeModels.InboxItem) -> String? {
        if let lead = historyListPresentableLine(item.selectedCounterpartyName) {
            return lead
        }
        guard let first = item.coordinationChildSummaries.first else { return nil }
        return historyListPresentableLine(first.displayName)
            ?? historyListPresentableLine(first.headline)
            ?? historyListPresentableLine(first.matchSummary)
    }

    static func historyChildMatchesNeedsYouFilter(_ child: ExchangeModels.CoordinationChildThreadSummary) -> Bool {
        child.requiresHumanDecision || child.hasFailure || child.awaitingReply
    }

    static func historyChildMatchesJudgmentFilter(_ child: ExchangeModels.CoordinationChildThreadSummary) -> Bool {
        child.hasPendingApproval
    }

    private static func isPreferredCompareMatch(
        _ match: ExchangeMatch,
        detail: ExchangeModels.ThreadDetail,
        ranked: [ExchangeMatch]
    ) -> Bool {
        if let selected = detail.selectedMatch {
            return match.id == selected.id
        }
        guard let first = ranked.first else { return false }
        return match.id == first.id
    }

    private static func compareOptionForMatch(
        _ match: ExchangeMatch,
        detail: ExchangeModels.ThreadDetail,
        secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?,
        isPreferred: Bool
    ) -> SecretaryComparePanel.Option {
        let counterparty = detail.counterparties.first(where: { $0.id == match.counterpartyID })

        let rawTitle =
            matchOfferTitle(match)
            ?? matchPublicProfileHeadline(match)
            ?? matchPublicProfileName(match)
            ?? compareOptionTitle(
                match: match,
                counterparty: counterparty,
                detail: detail
            )

        let rawSubtitle =
            matchOfferSummary(match)
            ?? matchPublicProfileSummary(match)
            ?? compareOptionSubtitle(
                match: match,
                counterparty: counterparty,
                detail: detail
            )

        let cleanCompareTitle = ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            rawTitle,
            field: .title,
            fallback: threadTitle(detail)
        )
        let cleanCompareSubtitle = ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            rawSubtitle,
            field: .subtitle,
            fallback: "New activity in this thread"
        )

        let strengthReasons = compareStrengthReasons(
            match: match,
            secondHalf: secondHalf,
            detail: detail
        )

        let weaknessReasons = compareWeaknessReasons(
            match: match,
            secondHalf: secondHalf
        )

        let missingFacts = compareMissingFacts(
            secondHalf: secondHalf,
            detail: detail
        )

        let recommendation =
            nonEmpty(match.recommendation)
            ?? nonEmpty(secondHalf?.decision?.recommendation)
            ?? nonEmpty(secondHalf?.requesterReview?.recommendation)
            ?? nonEmpty(secondHalf?.recommendation)
            ?? threadNextMove(detail)

        let trustLine =
            match.fit.trustFit.map { "Trust fit: \(percentText($0))" }
            ?? nonEmpty(secondHalf?.operatingContext.trust)
            ?? "Trust is limited or not yet established."

        let exposureLine = secondHalf.flatMap { display in
            nonEmpty(display.boundary.externalEffectLine)
            ?? nonEmpty(display.boundary.reason)
        } ?? threadBoundaryLine(detail)

        let readinessLine =
            nonEmpty(secondHalf?.status.readiness)
            ?? nonEmpty(secondHalf?.operatingContext.readiness)

        let nextMoveLine: String = {
            if let secondHalf,
               let next = secondHalfNextMoveLine(secondHalf) {
                return next
            }

            return threadNextMove(detail)
        }()

        let actionable =
            secondHalf?.needsHumanAttention == true || secondHalf?.hasDecisionPacket == true

        return SecretaryComparePanel.Option(
            candidateCounterpartyID: match.counterpartyID,
            title: cleanCompareTitle,
            subtitle: cleanCompareSubtitle,
            trustLine: trustLine,
            exposureLine: exposureLine,
            recommendationLine: recommendation,
            isPreferred: isPreferred,
            isActionable: actionable,
            strengthReasons: strengthReasons,
            weaknessReasons: weaknessReasons,
            missingFacts: missingFacts,
            readinessLine: readinessLine,
            boundaryLine: exposureLine,
            nextMoveLine: nextMoveLine
        )
    }

    private static func strengthRank(_ strength: ExchangeMatch.Strength) -> Int {
        switch strength {
        case .weak: return 1
        case .moderate: return 2
        case .strong: return 3
        }
    }
    
    private static func matchOfferTitle(_ match: ExchangeMatch?) -> String? {
        match?.metadata["selected_offer_title"]?.nilIfBlank
        ?? match?.metadata["offer_title"]?.nilIfBlank
    }

    private static func matchOfferSummary(_ match: ExchangeMatch?) -> String? {
        match?.metadata["selected_offer_summary"]?.nilIfBlank
        ?? match?.metadata["offer_summary"]?.nilIfBlank
    }

    private static func matchOfferCategory(_ match: ExchangeMatch?) -> String? {
        match?.metadata["selected_offer_category"]?.nilIfBlank
        ?? match?.metadata["offer_category"]?.nilIfBlank
    }

    private static func matchOfferTags(_ match: ExchangeMatch?) -> String? {
        match?.metadata["selected_offer_tags"]?.nilIfBlank
        ?? match?.metadata["offer_tags"]?.nilIfBlank
    }

    private static func matchOfferRegions(_ match: ExchangeMatch?) -> String? {
        match?.metadata["selected_offer_regions"]?.nilIfBlank
        ?? match?.metadata["offer_regions"]?.nilIfBlank
    }

    private static func matchPublicProfileName(_ match: ExchangeMatch?) -> String? {
        match?.metadata["public_profile_display_name"]?.nilIfBlank
        ?? match?.metadata["public_profile_name"]?.nilIfBlank
    }

    private static func matchPublicProfileHeadline(_ match: ExchangeMatch?) -> String? {
        match?.metadata["public_profile_headline"]?.nilIfBlank
    }

    private static func matchPublicProfileSummary(_ match: ExchangeMatch?) -> String? {
        match?.metadata["public_profile_summary"]?.nilIfBlank
    }

    private static func compareOptionTitle(
        match: ExchangeMatch?,
        counterparty: ExchangeCounterparty?,
        detail: ExchangeModels.ThreadDetail
    ) -> String {
        let lead = ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: detail.selectedOfferID,
            selectedPublicProfileID: detail.selectedPublicProfileID
        )

        switch lead {
        case .offerLed:
            if let offerTitle = matchOfferTitle(match) {
                return offerTitle
            }
            if let profileName = matchPublicProfileName(match) {
                return profileName
            }
            if let profileHeadline = matchPublicProfileHeadline(match) {
                return profileHeadline
            }

        case .profileLed:
            if let profileName = matchPublicProfileName(match) {
                return profileName
            }
            if let profileHeadline = matchPublicProfileHeadline(match) {
                return profileHeadline
            }
            if let offerTitle = matchOfferTitle(match) {
                return offerTitle
            }

        case .ambiguous:
            if let offerTitle = matchOfferTitle(match) {
                return offerTitle
            }
            if let profileHeadline = matchPublicProfileHeadline(match) {
                return profileHeadline
            }
            if let profileName = matchPublicProfileName(match) {
                return profileName
            }
        }

        if let headline = nonEmpty(counterparty?.publicCoordinationHeadline) {
            return headline
        }

        if let counterpartyName = nonEmpty(counterparty?.bestDisplayLine) {
            return counterpartyName
        }

        if let selected = selectedCounterpartyName(for: detail) {
            return selected
        }

        if let offerID = nonEmpty(match?.offerID ?? detail.selectedOfferID) {
            return "Offer \(shortID(offerID))"
        }

        if let profileID = nonEmpty(match?.publicProfileID ?? detail.selectedPublicProfileID) {
            return "Public profile \(shortID(profileID))"
        }

        return "Candidate path"
    }

    private static func compareOptionSubtitle(
        match: ExchangeMatch?,
        counterparty: ExchangeCounterparty?,
        detail: ExchangeModels.ThreadDetail
    ) -> String {
        if let offerSummary = matchOfferSummary(match) {
            return offerSummary
        }

        if let profileSummary = matchPublicProfileSummary(match) {
            return profileSummary
        }

        if let recommendation = nonEmpty(match?.recommendation) {
            return recommendation
        }

        if let summary = nonEmpty(detail.summary) {
            return summary
        }

        if let counterparty {
            let line = nonEmpty(counterparty.publicCoordinationHeadline)
                ?? nonEmpty(counterparty.bestDisplayLine)
            if let line {
                return "Matched path through \(line)."
            }
        }

        return "This is the currently selected provider-side path."
    }

    private static func compareStrengthReasons(
        match: ExchangeMatch?,
        secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?,
        detail: ExchangeModels.ThreadDetail
    ) -> [String] {
        var values: [String] = []

        values.append(contentsOf: match?.reasons.map(\.summary) ?? [])
        values.append(contentsOf: secondHalf?.requesterReview?.strengthReasons ?? [])
        values.append(contentsOf: secondHalf?.operatingContext.strengthReasons ?? [])

        if let score = match?.score {
            values.append("Overall fit score: \(percentText(score))")
        }

        if let offerID = nonEmpty(match?.offerID ?? detail.selectedOfferID) {
            values.append("Matched offer ID: \(offerID)")
        }

        if let profileID = nonEmpty(match?.publicProfileID ?? detail.selectedPublicProfileID) {
            values.append("Matched public profile ID: \(profileID)")
        }

        return cleanedList(values)
    }

    private static func compareWeaknessReasons(
        match: ExchangeMatch?,
        secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?
    ) -> [String] {
        var values: [String] = []

        values.append(contentsOf: match?.cautions.map(\.summary) ?? [])
        values.append(contentsOf: secondHalf?.requesterReview?.weaknessReasons ?? [])

        if let trustFit = match?.fit.trustFit, trustFit < 0.5 {
            values.append("Trust signal is still limited.")
        }

        if let timingFit = match?.fit.timingFit, timingFit < 0.5 {
            values.append("Timing or availability may need confirmation.")
        }

        return cleanedList(values)
    }

    private static func compareMissingFacts(
        secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?,
        detail: ExchangeModels.ThreadDetail
    ) -> [String] {
        var values: [String] = []

        values.append(contentsOf: secondHalf?.requesterReview?.missingFacts ?? [])
        values.append(contentsOf: secondHalf?.operatingContext.userFacingMissingFacts ?? [])

        let anchor = detail.thread.intent.resolvedOpportunitySurfaceAnchor(
            selectedOfferID: detail.selectedOfferID,
            selectedPublicProfileID: detail.selectedPublicProfileID,
            selectedCounterpartyID: detail.thread.selectedCounterpartyID
        )

        switch anchor {
        case .offerSurface:
            if detail.selectedOfferID == nil {
                values.append("No selected offer ID is attached to this thread.")
            }
        case .profileSurface:
            if detail.selectedPublicProfileID == nil {
                values.append("No selected public profile ID is attached to this thread.")
            }
        case .counterpartyNode:
            break
        }

        return cleanedList(values)
    }

    private static func compareMatchExtraSections(
        match: ExchangeMatch?,
        detail: ExchangeModels.ThreadDetail
    ) -> [SecretaryPanelSectionDisplay] {
        guard let match else { return [] }

        var sections: [SecretaryPanelSectionDisplay] = []

        let publicSurfaceLines = compactLines([
            line("Offer", matchOfferTitle(match)),
            line("Offer Summary", matchOfferSummary(match)),
            line("Category", matchOfferCategory(match)),
            line("Tags", matchOfferTags(match)),
            line("Regions", matchOfferRegions(match)),
            line("Public Profile", matchPublicProfileName(match)),
            line("Profile Headline", matchPublicProfileHeadline(match)),
            line("Profile Summary", matchPublicProfileSummary(match)),
            line("Open To", match.metadata["public_profile_open_to"]),
            line("Profile Regions", match.metadata["public_profile_regions"])
        ])

        if !publicSurfaceLines.isEmpty {
            sections.append(
                SecretaryPanelSectionDisplay(
                    title: "Pulled Offer / Profile",
                    systemImage: "sparkles.rectangle.stack",
                    lines: publicSurfaceLines
                )
            )
        }

        let identityLines = compactLines([
            line("Counterparty ID", match.counterpartyID),
            line("Public Profile ID", match.publicProfileID),
            line("Offer ID", match.offerID),
            line("Scope", match.scope.rawValue),
            line("Strength", match.strength.rawValue),
            line("Score", percentText(match.score))
        ])

        if !identityLines.isEmpty {
            sections.append(
                SecretaryPanelSectionDisplay(
                    title: "Match Identity",
                    systemImage: "person.crop.square",
                    lines: identityLines
                )
            )
        }

        let fitLines = compactLines([
            match.fit.retrievalFit.map { line("Retrieval Fit", percentText($0)) } ?? nil,
            match.fit.offerFit.map { line("Offer Fit", percentText($0)) } ?? nil,
            match.fit.profileFit.map { line("Profile Fit", percentText($0)) } ?? nil,
            match.fit.constraintFit.map { line("Constraint Fit", percentText($0)) } ?? nil,
            match.fit.trustFit.map { line("Trust Fit", percentText($0)) } ?? nil,
            match.fit.postureFit.map { line("Posture Fit", percentText($0)) } ?? nil,
            match.fit.timingFit.map { line("Timing Fit", percentText($0)) } ?? nil
        ])

        if !fitLines.isEmpty {
            sections.append(
                SecretaryPanelSectionDisplay(
                    title: "Fit Breakdown",
                    systemImage: "chart.bar",
                    lines: fitLines
                )
            )
        }

        return sections.filter(\.isRenderable)
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int((max(0, min(1, value)) * 100).rounded()))%"
    }

    private static func shortID(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > 10 else { return clean }
        return String(clean.prefix(8))
    }
    
    private static func line(_ label: String, _ value: String?) -> SecretaryPanelInfoLineDisplay? {
        guard let value = nonEmpty(value) else { return nil }
        return SecretaryPanelInfoLineDisplay(label: label, value: value)
    }
    
    private static func compactLines(_ lines: [SecretaryPanelInfoLineDisplay?]) -> [SecretaryPanelInfoLineDisplay] {
        lines.compactMap { $0 }.filter(\.isRenderable)
    }
    
    private static func secondHalfOperatingContextLines(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [SecretaryPanelInfoLineDisplay] {
        compactLines([
            line("Trust", display.operatingContext.trust),
            line("Readiness", display.operatingContext.readiness),
            line("Urgency", display.operatingContext.urgency),
            line("Price Sensitivity", display.operatingContext.priceSensitivity),
            line("Flexibility", display.operatingContext.flexibility)
        ])
    }
    
    private static func secondHalfStanceLines(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [SecretaryPanelInfoLineDisplay] {
        compactLines([
            line("Role", display.roleLabel),
            line("State", display.status.state),
            line("Quality", display.status.quality),
            line("Readiness", display.status.readiness),
            line("Recommendation", display.recommendation)
        ])
    }
    
    private static func secondHalfDecisionLines(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [SecretaryPanelInfoLineDisplay] {
        guard let decision = display.decision else { return [] }

        return compactLines([
            line("Summary", decision.summary),
            line("Recommendation", decision.recommendation),
            line("Next Move", secondHalfNextMoveLine(display))
        ])
    }
    
    private static func secondHalfProviderReceptionLines(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [SecretaryPanelInfoLineDisplay] {
        guard let provider = display.providerReception else { return [] }
        
        return compactLines([
            line("Inbound Ask", provider.requesterAsk ?? provider.inquirySummary ?? provider.subtitle),
            line("Matched To", provider.matchedAnchor),
            line("Lead Strength", provider.leadStrength),
            line("Answerability", provider.answerabilityStatus),
            line("Escalation", provider.escalationReason)
        ])
    }
    
    private static func secondHalfRequesterReviewLines(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [SecretaryPanelInfoLineDisplay] {
        guard let review = display.requesterReview else { return [] }
        
        return compactLines([
            line("Review", review.subtitle),
            line("Strength", review.reviewStrength),
            line("Recommendation", review.recommendation),
            line("Next Move", review.nextMoveTitle)
        ])
    }
    
    private static func secondHalfWhatChanged(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [String] {
        cleanedList(
            display.decision?.whatChanged
            ?? display.summaryLines
        )
    }
    
    private static func secondHalfClarifiedFacts(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [String] {
        cleanedList(display.decision?.clarifiedFacts ?? [])
    }
    
    private static func secondHalfUnresolvedIssues(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [String] {
        cleanedList(
            display.decision?.unresolvedIssues
            ?? display.operatingContext.userFacingMissingFacts
        )
    }
    
    private static func secondHalfTradeoffs(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [String] {
        cleanedList(display.decision?.tradeoffs ?? [])
    }
    
    private static func secondHalfApprovalReasons(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [String] {
        cleanedList([
            display.nextMove?.rationale,
            display.escalationReason,
            display.boundary.reason,
            display.boundary.externalEffectLine
        ].compactMap { $0 })
    }
    
    private static func secondHalfDraftFactsUsed(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [String] {
        var values: [String] = []

        if let draft = display.draft {
            values.append(contentsOf: draft.usedStructuredFacts)
            values.append(contentsOf: draft.notes)
        }

        values.append(contentsOf: display.operatingContext.followUpHints)
        values.append(contentsOf: display.operatingContext.strengthReasons)

        if let decision = display.decision {
            values.append(contentsOf: decision.clarifiedFacts)
        }

        return cleanedList(values)
    }
    
    private static func secondHalfExtraSections(
        _ display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> [SecretaryPanelSectionDisplay] {
        var sections: [SecretaryPanelSectionDisplay] = []
        
        if !display.operatingContext.userFacingMissingFacts.isEmpty {
            sections.append(
                SecretaryPanelSectionDisplay(
                    title: "Missing Facts",
                    systemImage: "questionmark.circle",
                    lines: cleanedList(display.operatingContext.userFacingMissingFacts).map {
                        SecretaryPanelInfoLineDisplay(label: "Needed", value: $0)
                    }
                )
            )
        }

        if !display.operatingContext.diagnosticMissingFacts.isEmpty {
            sections.append(
                SecretaryPanelSectionDisplay(
                    title: "Coordination notes",
                    systemImage: "ellipsis.circle",
                    lines: cleanedList(display.operatingContext.diagnosticMissingFacts).map {
                        SecretaryPanelInfoLineDisplay(label: "Context", value: $0)
                    }
                )
            )
        }
        
        if !display.summaryLines.isEmpty {
            sections.append(
                SecretaryPanelSectionDisplay(
                    title: "Summary Lines",
                    systemImage: "text.alignleft",
                    lines: cleanedList(display.summaryLines).map {
                        SecretaryPanelInfoLineDisplay(label: "Signal", value: $0)
                    }
                )
            )
        }
        
        return sections.filter(\.isRenderable)
    }
}

// MARK: - Thread timeline presentation (Secretary Activity / UI-only)

extension SecretaryProjectionEngine {
    struct ThreadTimelinePresentedRow: Sendable {
        let title: String
        let summary: String?
        let secondary: String?
    }

    /// Rewrites façade timeline titles/summaries into short exchange language for secretary UI only.
    static func presentedThreadTimelineRow(
        item: ExchangeModels.ThreadTimelineItem
    ) -> ThreadTimelinePresentedRow {
        let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let mappedTitle = Self.mapTimelineRowTitle(
            trimmedTitle: trimmedTitle,
            tone: item.tone,
            summary: item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let displayTitleRaw = Self.sanitizedTimelinePresentationLine(mappedTitle)
        let displayTitle =
            displayTitleRaw.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? mappedTitle

        let summarized =
            Self.sanitizedTimelinePresentationParagraph(scrubInboundEnvelopePrefixes(item.summary))
        let secondaryized = item.secondary.flatMap { raw -> String in
            Self.sanitizedTimelinePresentationParagraph(
                scrubInboundEnvelopePrefixes(raw)
            )
        }

        return ThreadTimelinePresentedRow(
            title: displayTitle,
            summary: summarized.nilIfBlank,
            secondary: secondaryized?.nilIfBlank
        )
    }

    /// Package-private name for reuse from timeline SwiftUI previews/tests if needed.
    static func sanitizedTimelinePresentationParagraph(_ raw: String) -> String {
        let strippedUUIDs = Self.scrubTimelineUUIDs(raw)
        let strippedBad = Self.scrubTimelineForbiddenTokens(strippedUUIDs)
        return Self.collapseInsensitiveWhitespace(strippedBad)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Single-line headline (timeline title).
    private static func sanitizedTimelinePresentationLine(_ raw: String) -> String {
        let collapsed = Self.sanitizedTimelinePresentationParagraph(raw)
        return collapsed
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func scrubInboundEnvelopePrefixes(_ raw: String) -> String {
        var s = raw
        while let r = s.range(of: "Inbound envelope ", options: .caseInsensitive) {
            s.removeSubrange(r)
        }
        while let r = s.range(of: "Envelope ", options: .caseInsensitive) {
            s.removeSubrange(r)
        }
        return s
    }

    private static func scrubTimelineUUIDs(_ raw: String) -> String {
        let pattern =
            "\\b[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return raw
        }

        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return regex.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: "")
    }

    /// Multi-word phrases first, then whole-word removals.
    private static func scrubTimelineForbiddenTokens(_ raw: String) -> String {
        var result = raw

        let phrases: [String] = [
            "agency assessment",
            "autonomous decision",
            "execution stage",
            "state machine",
            "second half",
            "second_half",
        ]

        for phrase in phrases {
            result = result.replacingOccurrences(of: phrase, with: " ", options: [.caseInsensitive], range: nil)
        }

        let passScrubRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let afterPassTimeline = timelinePassLayerRegex?
            .stringByReplacingMatches(in: result, options: [], range: passScrubRange, withTemplate: " ")
            ?? result

        guard let regex = forbiddenTimelineWholeWordRegex else {
            return afterPassTimeline
        }

        let full = NSRange(afterPassTimeline.startIndex..<afterPassTimeline.endIndex, in: afterPassTimeline)
        let singlePass = regex.stringByReplacingMatches(in: afterPassTimeline, options: [], range: full, withTemplate: " ")

        if let inboundEnv = try? NSRegularExpression(pattern: "inbound\\s+envelope", options: [.caseInsensitive]) {
            let r2 = NSRange(singlePass.startIndex..<singlePass.endIndex, in: singlePass)
            return inboundEnv.stringByReplacingMatches(in: singlePass, options: [], range: r2, withTemplate: " ")
        }

        return singlePass
    }

    /// Removes only pass-layer phrasing (`pass 2`, `pass2`, …); standalone "pass" is kept (parking pass, pass by).
    private static let timelinePassLayerRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern:
        "(?:\\bpass\\s*-\\s*[23]\\b|\\bpass\\s+[23]\\b|\\bpass[23]\\b|\\bpass\\s+two\\b|\\bpass\\s+three\\b)",
        options: [.caseInsensitive]
    )

    private static let forbiddenTimelineWholeWordRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern:
        "\\b(trace|projection|pipeline|runtime|mutation|eligible|relay|facade|coordinator|handoff|" +
            "metadata|lifecycle|queue|outbox|internal|debug|execution|agency|autonomous|" +
            "envelope|envelopes)\\b",
        options: [.caseInsensitive]
    )

    private static func collapseInsensitiveWhitespace(_ raw: String) -> String {
        raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Maps façade-style titles to secretary exchange headings.
    private static func mapTimelineRowTitle(
        trimmedTitle: String,
        tone: ExchangeModels.ThreadTimelineItem.Tone,
        summary: String
    ) -> String {
        let lower = trimmedTitle.lowercased()
        let summarLower = summary.lowercased()

        if lower.hasPrefix("delivery state:") || lower.hasPrefix("delivery state ") {
            let suffix = trimmedTitle
                .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                .dropFirst()
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? ""

            switch suffix {
            case "sent":
                return "Sent"
            case "sending":
                return "Sending"
            case "failed":
                return "Couldn't send"
            case "not started":
                return "Not sent yet"
            case "pending approval":
                return "Needs approval"
            case "ready to send":
                return "Ready to send"
            default:
                if tone == .blocked { return "Couldn't send" }
                if summarLower.contains("failed") || summarLower.contains("fail") {
                    return "Couldn't send"
                }
                if summarLower.contains("going out") || summarLower.contains("in progress") {
                    return "Sending"
                }
                if summarLower.contains("successfully") || summarLower.contains("went out") {
                    return "Sent"
                }
                if summarLower.contains("nothing has gone") || summarLower.contains("not started") {
                    return "Not sent yet"
                }
                if summarLower.contains("approval") || summarLower.contains("waiting for approval") {
                    return "Needs approval"
                }
                let stripped = trimmedTitle.replacingOccurrences(
                    of: "Delivery state:",
                    with: "",
                    options: .caseInsensitive,
                    range: nil
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                return stripped.nilIfBlank ?? "Update"
            }
        }

        if lower == "work update" || lower.hasPrefix("work update ") {
            return "Update"
        }

        switch lower {
        case "thread opened":
            return "Started"

        case "search started", "searching":
            return "Looking"

        case "search completed":
            return "I found"

        case "weak matches":
            return "Few good matches"

        case "no matches", "no viable match":
            return "No match yet"

        case "match selected", "candidate selected":
            return "I found"

        case "candidate found", "candidates found":
            return "I found"

        case "negotiation started":
            return "I asked"

        case "provider contacted":
            return "I asked"

        case "message drafted":
            return "Draft update"

        case "message sent":
            return "Sent"

        case "waiting for reply", "waiting on provider":
            return "Waiting"

        case "waiting on you":
            return "Needs one detail"

        case "blocked":
            return "Needs attention"

        case "recovered":
            return "Back on track"

        case "inbound activity", "inbound message":
            return "They replied"

        case "request captured":
            return "You asked"

        case "draft prepared", "draft created", "draft updated":
            return "Draft update"

        case "approval requested":
            return "Needs approval"

        case "approval pending":
            return "Needs approval"

        case "match found":
            return "I found"

        case "selection basis", "path basis":
            return "I found"

        case "clarification needed", "clarification requested":
            return "Needs one detail"

        case "counterparty clarification":
            return "They replied"

        case "failure surfaced":
            return "Couldn't send"

        case "delivery failed":
            return "Couldn't send"

        case "reply received":
            return "They replied"

        case "send confirmed":
            return "Sent"

        case "send attempted":
            return "Sending"

        case "outbound activity":
            if tone == .success {
                return "Sent"
            }
            return "Not sent yet"

        case "system notice":
            return "Note"

        case "system error":
            return "Couldn't send"

        default:
            if lower.hasPrefix("approval ") {
                return mapApprovalPhraseTitle(trimmedTitle)
            }
        }

        return trimmedTitle
    }

    private static func mapApprovalPhraseTitle(_ trimmedTitle: String) -> String {
        let lowered = trimmedTitle.lowercased()
        if lowered.contains("pending") {
            return "Needs approval"
        }
        if lowered.contains("requested") || lowered.contains("requires") || lowered.contains("required") {
            return "Needs approval"
        }
        if lowered.contains("approved") || lowered.contains("granted") {
            return "Approved"
        }
        if lowered.contains("reject") || lowered.contains("stopped") || lowered.contains("denied") {
            return "Rejected"
        }
        if lowered.contains("expired") {
            return "Expired"
        }
        if lowered.contains("cancelled") || lowered.contains("canceled") {
            return "Cancelled"
        }

        return trimmedTitle
    }

    // MARK: - Direct message to trusted node (thread + Trust tab)

    /// Counterparty node id for `ExchangeFacade.sendManualMessageToTrustedNode` from thread detail.
    static func resolvedTrustedNodeIDForManualMessage(for detail: ExchangeModels.ThreadDetail) -> String? {
        if let id = detail.thread.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return id
        }
        if let id = detail.selectedMatch?.counterpartyID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return id
        }
        return nil
    }

    static func trustedCounterpartyForManualMessage(for detail: ExchangeModels.ThreadDetail) -> ExchangeCounterparty? {
        guard let id = resolvedTrustedNodeIDForManualMessage(for: detail) else { return nil }
        return detail.counterparties.first(where: { $0.id == id })
    }

    /// Whether the thread detail supports opening the direct-message compose sheet (local UI gate; send may still fail in engine).
    static func canShowDirectMessageToTrustedNode(for detail: ExchangeModels.ThreadDetail) -> Bool {
        guard trustedCounterpartyForManualMessage(for: detail)?.publicProfile != nil else { return false }
        guard detail.thread.metadata["archived"] != "true" else { return false }
        if detail.thread.state.isTerminal { return false }
        return true
    }

    static func directMessageRecipientDisplayName(for detail: ExchangeModels.ThreadDetail) -> String {
        if let name = selectedCounterpartyName(for: detail) { return name }
        if let cp = trustedCounterpartyForManualMessage(for: detail) {
            return nonEmpty(cp.bestDisplayLine) ?? cp.id
        }
        return "Contact"
    }

    /// Prefer a stronger “Message” treatment when the thread already reads as a direct, named path and is waiting on the other side.
    static func prefersProminentDirectMessageButton(for detail: ExchangeModels.ThreadDetail) -> Bool {
        guard canShowDirectMessageToTrustedNode(for: detail) else { return false }
        guard selectedCounterpartyName(for: detail) != nil else { return false }
        return isAwaitingResponse(detail)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
