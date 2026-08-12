import Foundation

/// Policy boundary for Exchange.
///
/// This engine centralizes rules around:
/// - approval requirements
/// - sender-side disclosure limits
/// - recipient public-posture constraints
/// - retry permission
/// - follow-up permission
/// - whether a thread may advance externally
/// - whether federation execution is currently eligible
/// - cancellation and audit expectations
///
/// Important boundary:
/// - sender-side policy is not the same as recipient public posture
/// - recipient public posture is not the same as runtime transport state
/// - `deliveryState` here means canonical federation transport truth
///   (for example, from an outbox item), not thread summary state
public struct ExchangePolicyEngine: Sendable {
    public init() {}

    public func evaluate(
        thread: ExchangeThread,
        selectedCounterparty: ExchangeCounterparty? = nil,
        publicProfile: ExchangePublicNodeProfile? = nil,
        draft: ExchangeMessageDraft? = nil,
        deliveryState: ExchangeDeliveryState? = nil
    ) -> DecisionSet {
        let approval = approvalDecision(
            thread: thread,
            draft: draft
        )

        let senderPolicy = senderPolicyDecision(
            thread: thread
        )

        let recipientPosture = recipientPostureDecision(
            thread: thread,
            selectedCounterparty: selectedCounterparty,
            publicProfile: publicProfile,
            requestedDisclosureLevel: senderPolicy.proposedDisclosureLevel
        )

        let disclosure = disclosureDecision(
            senderPolicy: senderPolicy,
            recipientPosture: recipientPosture
        )

        let advancement = externalAdvancementDecision(
            thread: thread,
            draft: draft,
            approval: approval
        )

        let runtimeTransport = runtimeTransportDecision(
            draft: draft,
            deliveryState: deliveryState
        )

        let federationExecution = federationExecutionDecision(
            senderPolicy: senderPolicy,
            recipientPosture: recipientPosture,
            advancement: advancement,
            runtimeTransport: runtimeTransport
        )

        let cancellation = cancellationDecision(deliveryState: deliveryState)

        let audit = auditDecision(
            thread: thread,
            draft: draft,
            deliveryState: deliveryState
        )

        let retry = retryDecision(
            thread: thread,
            deliveryState: deliveryState
        )

        let followUp = followUpDecision(thread: thread)
        let closure = closureDecision(thread: thread)

        return DecisionSet(
            approval: approval,
            senderPolicy: senderPolicy,
            recipientPosture: recipientPosture,
            disclosure: disclosure,
            advancement: advancement,
            runtimeTransport: runtimeTransport,
            federationExecution: federationExecution,
            cancellation: cancellation,
            audit: audit,
            retry: retry,
            followUp: followUp,
            closure: closure
        )
    }
}

public extension ExchangePolicyEngine {
    struct DecisionSet: Sendable, Hashable {
        public var approval: ApprovalDecision
        public var senderPolicy: SenderPolicyDecision
        public var recipientPosture: RecipientPostureDecision
        public var disclosure: DisclosureDecision
        public var advancement: ExternalAdvancementDecision
        public var runtimeTransport: RuntimeTransportDecision
        public var federationExecution: FederationExecutionDecision
        public var cancellation: CancellationDecision
        public var audit: AuditDecision
        public var retry: RetryDecision
        public var followUp: FollowUpDecision
        public var closure: ClosureDecision

        public init(
            approval: ApprovalDecision,
            senderPolicy: SenderPolicyDecision,
            recipientPosture: RecipientPostureDecision,
            disclosure: DisclosureDecision,
            advancement: ExternalAdvancementDecision,
            runtimeTransport: RuntimeTransportDecision,
            federationExecution: FederationExecutionDecision,
            cancellation: CancellationDecision,
            audit: AuditDecision,
            retry: RetryDecision,
            followUp: FollowUpDecision,
            closure: ClosureDecision
        ) {
            self.approval = approval
            self.senderPolicy = senderPolicy
            self.recipientPosture = recipientPosture
            self.disclosure = disclosure
            self.advancement = advancement
            self.runtimeTransport = runtimeTransport
            self.federationExecution = federationExecution
            self.cancellation = cancellation
            self.audit = audit
            self.retry = retry
            self.followUp = followUp
            self.closure = closure
        }
    }

    struct ApprovalDecision: Sendable, Hashable {
        public var required: Bool
        public var rationale: String

        public init(required: Bool, rationale: String) {
            self.required = required
            self.rationale = rationale
        }
    }

    /// Local sender-side policy only.
    ///
    /// This is about what the user's secretary is willing to do,
    /// before considering the recipient's posture.
    struct SenderPolicyDecision: Sendable, Hashable {
        public var allowsExternalAction: Bool
        public var proposedDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel
        public var rationale: String

        public init(
            allowsExternalAction: Bool,
            proposedDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
            rationale: String
        ) {
            self.allowsExternalAction = allowsExternalAction
            self.proposedDisclosureLevel = proposedDisclosureLevel
            self.rationale = rationale
        }
    }

    /// Recipient public posture only.
    ///
    /// This does not decide transport execution.
    /// It only expresses what the recipient publicly allows.
    struct RecipientPostureDecision: Sendable, Hashable {
        public enum Status: String, Sendable, Hashable {
            case unknown
            case allowedDirect
            case allowedIntroPreferred
            case allowedViaIntroduction
            case introRequired
            case trustTooLow
            case categoryMismatch
            case mutualFitRequired
            case modeNotAllowed
            case intentKindNotAllowed
            case audienceNotAllowed
            case closed
            case notAcceptingInbound
        }

        public var status: Status
        public var allowed: Bool
        public var disclosureCeiling: ExchangeRelayEnvelope.Payload.DisclosureLevel?
        public var effectiveDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel?
        public var rationale: String

        public init(
            status: Status,
            allowed: Bool,
            disclosureCeiling: ExchangeRelayEnvelope.Payload.DisclosureLevel?,
            effectiveDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel?,
            rationale: String
        ) {
            self.status = status
            self.allowed = allowed
            self.disclosureCeiling = disclosureCeiling
            self.effectiveDisclosureLevel = effectiveDisclosureLevel
            self.rationale = rationale
        }
    }

    struct DisclosureDecision: Sendable, Hashable {
        public var level: ExchangeRelayEnvelope.Payload.DisclosureLevel
        public var rationale: String

        public init(
            level: ExchangeRelayEnvelope.Payload.DisclosureLevel,
            rationale: String
        ) {
            self.level = level
            self.rationale = rationale
        }
    }

    struct ExternalAdvancementDecision: Sendable, Hashable {
        public var allowed: Bool
        public var rationale: String

        public init(allowed: Bool, rationale: String) {
            self.allowed = allowed
            self.rationale = rationale
        }
    }

    /// Runtime / transport execution constraints only.
    ///
    /// This is about whether execution can proceed given current draft and
    /// canonical delivery state. It should not encode recipient public posture.
    struct RuntimeTransportDecision: Sendable, Hashable {
        public var allowed: Bool
        public var rationale: String
        public var cancelOnApprovalRevocation: Bool

        public init(
            allowed: Bool,
            rationale: String,
            cancelOnApprovalRevocation: Bool
        ) {
            self.allowed = allowed
            self.rationale = rationale
            self.cancelOnApprovalRevocation = cancelOnApprovalRevocation
        }
    }

    struct FederationExecutionDecision: Sendable, Hashable {
        public var allowed: Bool
        public var rationale: String
        public var requiresAudit: Bool
        public var cancelOnApprovalRevocation: Bool

        public init(
            allowed: Bool,
            rationale: String,
            requiresAudit: Bool,
            cancelOnApprovalRevocation: Bool
        ) {
            self.allowed = allowed
            self.rationale = rationale
            self.requiresAudit = requiresAudit
            self.cancelOnApprovalRevocation = cancelOnApprovalRevocation
        }
    }

    struct CancellationDecision: Sendable, Hashable {
        public var allowed: Bool
        public var rationale: String
        public var mayAlreadyHaveExternalEffect: Bool

        public init(
            allowed: Bool,
            rationale: String,
            mayAlreadyHaveExternalEffect: Bool
        ) {
            self.allowed = allowed
            self.rationale = rationale
            self.mayAlreadyHaveExternalEffect = mayAlreadyHaveExternalEffect
        }
    }

    struct AuditDecision: Sendable, Hashable {
        public var required: Bool
        public var rationale: String

        public init(required: Bool, rationale: String) {
            self.required = required
            self.rationale = rationale
        }
    }

    struct RetryDecision: Sendable, Hashable {
        public var allowed: Bool
        public var rationale: String

        public init(allowed: Bool, rationale: String) {
            self.allowed = allowed
            self.rationale = rationale
        }
    }

    struct FollowUpDecision: Sendable, Hashable {
        public var allowed: Bool
        public var rationale: String

        public init(allowed: Bool, rationale: String) {
            self.allowed = allowed
            self.rationale = rationale
        }
    }

    struct ClosureDecision: Sendable, Hashable {
        public var allowed: Bool
        public var rationale: String

        public init(allowed: Bool, rationale: String) {
            self.allowed = allowed
            self.rationale = rationale
        }
    }

    /// Return-path reply on a thread that already recorded an **inbound federation envelope** for the same selected counterparty (continuation), not cold discovery initiation.
    static func isExistingInboundContinuationReplySend(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty
    ) -> Bool {
        let env = thread.lastInboundEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !env.isEmpty else { return false }
        let sel = thread.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sel.isEmpty, sel == counterparty.id else { return false }
        return true
    }
}

private extension ExchangePolicyEngine {
    func approvalDecision(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft?
    ) -> ApprovalDecision {
        if thread.posture.privacy == .guarded {
            return .init(
                required: true,
                rationale: "The current posture is privacy-sensitive."
            )
        }

        if let draft, draft.kind == .negotiation {
            return .init(
                required: true,
                rationale: "Negotiation moves require explicit approval."
            )
        }

        if thread.mode == .relational && thread.posture.commitment == .exploring {
            return .init(
                required: true,
                rationale: "Relational coordination with exploratory commitment should be explicitly approved before outbound action."
            )
        }

        return .init(
            required: false,
            rationale: "No explicit approval requirement was triggered."
        )
    }

    func senderPolicyDecision(
        thread: ExchangeThread
    ) -> SenderPolicyDecision {
        if thread.intent.requiresClarificationBeforeAction {
            return .init(
                allowsExternalAction: false,
                proposedDisclosureLevel: .minimal,
                rationale: "The request still requires clarification before external action."
            )
        }

        if thread.posture.privacy == .guarded {
            return .init(
                allowsExternalAction: true,
                proposedDisclosureLevel: .minimal,
                rationale: "The thread posture is guarded, so sender-side disclosure should stay minimal."
            )
        }

        if thread.posture.privacy == .disclosive {
            return .init(
                allowsExternalAction: true,
                proposedDisclosureLevel: .open,
                rationale: "The sender posture allows broader disclosure when useful."
            )
        }

        return .init(
            allowsExternalAction: true,
            proposedDisclosureLevel: .balanced,
            rationale: "Balanced disclosure is appropriate by default."
        )
    }

    func recipientPostureDecision(
        thread: ExchangeThread,
        selectedCounterparty: ExchangeCounterparty?,
        publicProfile: ExchangePublicNodeProfile?,
        requestedDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel
    ) -> RecipientPostureDecision {
        guard let publicProfile else {
            if let cp = selectedCounterparty,
               ExchangePolicyEngine.isExistingInboundContinuationReplySend(thread: thread, counterparty: cp) {
                let ceiling = relayDisclosureLevel(from: .balanced)
                let effective = requestedDisclosureLevel.clamped(to: ceiling)
                return .init(
                    status: .allowedDirect,
                    allowed: true,
                    disclosureCeiling: ceiling,
                    effectiveDisclosureLevel: effective,
                    rationale: "Existing inbound continuation reply; cold-outreach public recipient posture is not required."
                )
            }
            return .init(
                status: .unknown,
                allowed: false,
                disclosureCeiling: nil,
                effectiveDisclosureLevel: nil,
                rationale: "No public recipient posture is available yet."
            )
        }

        let ceiling = relayDisclosureLevel(from: publicProfile.reachability.disclosureCeiling)
        let effectiveDisclosure = requestedDisclosureLevel.clamped(to: ceiling)

        guard publicProfile.reachability.acceptingInbound else {
            return .init(
                status: .notAcceptingInbound,
                allowed: false,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "The recipient is not currently accepting new inbound coordination."
            )
        }

        if let minimumTrust = publicProfile.reachability.minimumTrustLevel,
           let trust = trustLevel(for: selectedCounterparty),
           trustRank(trust) < trustRank(minimumTrust) {
            return .init(
                status: .trustTooLow,
                allowed: false,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "Trust is below the minimum level required by the recipient public posture."
            )
        }

        if !modeAllowed(thread.mode, publicProfile: publicProfile) {
            return .init(
                status: .modeNotAllowed,
                allowed: false,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "The recipient public posture does not allow this coordination mode."
            )
        }

        if !intentKindAllowed(thread.intent.kind, publicProfile: publicProfile) {
            return .init(
                status: .intentKindNotAllowed,
                allowed: false,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "The recipient public posture does not allow this kind of request."
            )
        }

        if !audienceAllowed(thread: thread, publicProfile: publicProfile) {
            return .init(
                status: .audienceNotAllowed,
                allowed: false,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "The recipient public posture does not allow this audience kind."
            )
        }

        if publicProfile.reachability.requiresCategoryMatch,
           !categoryMatchSatisfied(thread: thread, publicProfile: publicProfile) {
            return .init(
                status: .categoryMismatch,
                allowed: false,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "The request does not match the recipient's allowed public categories closely enough."
            )
        }

        if publicProfile.reachability.requiresMutualFit,
           !mutualFitSatisfied(thread: thread, selectedCounterparty: selectedCounterparty) {
            return .init(
                status: .mutualFitRequired,
                allowed: false,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "The recipient requires mutual or trusted fit before contact can advance."
            )
        }

        switch publicProfile.reachability.accessMode {
        case .closed:
            return .init(
                status: .closed,
                allowed: false,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "The recipient is currently closed to contact."
            )

        case .introRequired:
            guard threadHasTrustedIntroduction(thread) else {
                return .init(
                    status: .introRequired,
                    allowed: false,
                    disclosureCeiling: ceiling,
                    effectiveDisclosureLevel: effectiveDisclosure,
                    rationale: "The recipient allows contact only through an introduction or trusted path."
                )
            }

            return .init(
                status: .allowedViaIntroduction,
                allowed: true,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "Recipient posture allows contact through an introduction-qualified path."
            )

        case .introPreferred:
            return .init(
                status: .allowedIntroPreferred,
                allowed: true,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "Recipient posture allows direct contact, but introductions are preferred."
            )

        case .direct:
            return .init(
                status: .allowedDirect,
                allowed: true,
                disclosureCeiling: ceiling,
                effectiveDisclosureLevel: effectiveDisclosure,
                rationale: "Recipient posture allows direct contact."
            )
        }
    }

    func disclosureDecision(
        senderPolicy: SenderPolicyDecision,
        recipientPosture: RecipientPostureDecision
    ) -> DisclosureDecision {
        let level = recipientPosture.effectiveDisclosureLevel ?? senderPolicy.proposedDisclosureLevel

        if let ceiling = recipientPosture.disclosureCeiling,
           senderPolicy.proposedDisclosureLevel != level {
            return .init(
                level: level,
                rationale: "Disclosure was reduced from sender policy to the recipient posture ceiling of \(ceiling.rawValue)."
            )
        }

        return .init(
            level: level,
            rationale: recipientPosture.allowed
                ? "Disclosure level is compatible with both sender policy and recipient posture."
                : "Disclosure level reflects sender policy, but recipient posture is not yet satisfied."
        )
    }

    func externalAdvancementDecision(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft?,
        approval: ApprovalDecision
    ) -> ExternalAdvancementDecision {
        if thread.intent.requiresClarificationBeforeAction {
            return .init(
                allowed: false,
                rationale: "The request still requires clarification."
            )
        }

        if case .matchFound = thread.state {
            if hasApprovedActionableSecondHalfOutwardDraft(
                thread: thread,
                draft: draft
            ) {
                return .init(
                    allowed: true,
                    rationale: "A second-half outward draft is prepared for this matched thread."
                )
            }
            if hasApprovedTrustedNodeManualOutwardDraft(
                thread: thread,
                draft: draft
            ) {
                return .init(
                    allowed: true,
                    rationale: "A user-authored trusted-node message is ready to send on this matched thread."
                )
            }
            if hasApprovedConversationCardManualOutwardDraft(
                thread: thread,
                draft: draft
            ) {
                return .init(
                    allowed: true,
                    rationale: "A user-authored conversation-card outbound draft is ready to send on this matched thread."
                )
            }
            return .init(
                allowed: false,
                rationale: "A match has been found, but no outward move is prepared yet."
            )
        }

        if approval.required {
            let isApproved = thread.approval?.status == .approved
            return .init(
                allowed: isApproved,
                rationale: isApproved
                    ? "Approval is required and has been granted."
                    : "Approval is required before external action."
            )
        }

        return .init(
            allowed: true,
            rationale: "No sender-side approval rule currently blocks external advancement."
        )
    }

    func hasApprovedActionableSecondHalfOutwardDraft(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft?
    ) -> Bool {
        guard let draft else { return false }
        guard draft.threadID == thread.id else { return false }
        guard draft.metadata["second_half_generated"] == "true" else { return false }
        guard draft.isActionable else { return false }
        guard draft.audience == .externalCounterparty else { return false }
        guard !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard draft.status == .approved else { return false }

        let selected = thread.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = draft.targetCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selected, !selected.isEmpty, let target, !target.isEmpty, selected != target {
            return false
        }

        return true
    }

    /// Human-authored message from Trust tab (not second-half / not secretary-generated).
    func hasApprovedTrustedNodeManualOutwardDraft(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft?
    ) -> Bool {
        guard let draft else { return false }
        guard draft.threadID == thread.id else { return false }
        guard draft.metadata["trusted_node_manual_message"] == "true" else { return false }
        guard draft.metadata["second_half_generated"] != "true" else { return false }
        guard draft.isActionable else { return false }
        guard draft.audience == .externalCounterparty else { return false }
        guard !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard draft.status == .approved else { return false }

        let selected = thread.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = draft.targetCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selected, !selected.isEmpty, let target, !target.isEmpty, selected != target {
            return false
        }

        return true
    }

    /// User-authored outbound from the thread Conversation card (exchange lane, not DM / not second-half).
    func hasApprovedConversationCardManualOutwardDraft(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft?
    ) -> Bool {
        guard let draft else { return false }
        guard draft.threadID == thread.id else { return false }
        guard draft.metadata["conversation_card_manual_outbound"] == "true" else { return false }
        guard draft.metadata["trusted_node_manual_message"] != "true" else { return false }
        guard draft.metadata["second_half_generated"] != "true" else { return false }
        guard draft.isActionable else { return false }
        guard draft.audience == .externalCounterparty else { return false }
        guard !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard draft.status == .approved else { return false }

        let selected = thread.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = draft.targetCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selected, !selected.isEmpty, let target, !target.isEmpty, selected != target {
            return false
        }

        return true
    }

    func runtimeTransportDecision(
        draft: ExchangeMessageDraft?,
        deliveryState: ExchangeDeliveryState?
    ) -> RuntimeTransportDecision {
        guard let draft else {
            return .init(
                allowed: false,
                rationale: "No outbound draft exists yet.",
                cancelOnApprovalRevocation: true
            )
        }

        if draft.status == .sent {
            return .init(
                allowed: false,
                rationale: "This draft is already marked as sent.",
                cancelOnApprovalRevocation: false
            )
        }

        if let deliveryState {
            switch deliveryState.phase {
            case .sending, .sent, .acknowledged, .tooLateToCancel:
                return .init(
                    allowed: false,
                    rationale: "Delivery has already started or completed.",
                    cancelOnApprovalRevocation: false
                )

            case .queued, .blockedByPrerequisite, .deferred:
                return .init(
                    allowed: false,
                    rationale: "A transport item already exists for this draft.",
                    cancelOnApprovalRevocation: true
                )

            case .cancelledBeforeSend, .failed, .incompatible:
                break
            }
        }

        return .init(
            allowed: true,
            rationale: "Runtime transport state allows execution.",
            cancelOnApprovalRevocation: true
        )
    }

    func federationExecutionDecision(
        senderPolicy: SenderPolicyDecision,
        recipientPosture: RecipientPostureDecision,
        advancement: ExternalAdvancementDecision,
        runtimeTransport: RuntimeTransportDecision
    ) -> FederationExecutionDecision {
        guard senderPolicy.allowsExternalAction else {
            return .init(
                allowed: false,
                rationale: senderPolicy.rationale,
                requiresAudit: true,
                cancelOnApprovalRevocation: true
            )
        }

        guard advancement.allowed else {
            return .init(
                allowed: false,
                rationale: advancement.rationale,
                requiresAudit: true,
                cancelOnApprovalRevocation: true
            )
        }

        guard recipientPosture.allowed else {
            return .init(
                allowed: false,
                rationale: recipientPosture.rationale,
                requiresAudit: true,
                cancelOnApprovalRevocation: true
            )
        }

        guard runtimeTransport.allowed else {
            return .init(
                allowed: false,
                rationale: runtimeTransport.rationale,
                requiresAudit: true,
                cancelOnApprovalRevocation: runtimeTransport.cancelOnApprovalRevocation
            )
        }

        return .init(
            allowed: true,
            rationale: "Sender policy, recipient posture, and runtime transport all allow federation execution.",
            requiresAudit: true,
            cancelOnApprovalRevocation: runtimeTransport.cancelOnApprovalRevocation
        )
    }

    func cancellationDecision(
        deliveryState: ExchangeDeliveryState?
    ) -> CancellationDecision {
        guard let deliveryState else {
            return .init(
                allowed: true,
                rationale: "No delivery has started yet.",
                mayAlreadyHaveExternalEffect: false
            )
        }

        switch deliveryState.phase {
        case .queued, .blockedByPrerequisite, .deferred:
            return .init(
                allowed: true,
                rationale: "The item can still be cancelled before send.",
                mayAlreadyHaveExternalEffect: false
            )

        case .sending, .sent:
            return .init(
                allowed: false,
                rationale: "Delivery may already be underway or have left the device.",
                mayAlreadyHaveExternalEffect: true
            )

        case .acknowledged, .tooLateToCancel:
            return .init(
                allowed: false,
                rationale: "It is too late to guarantee cancellation.",
                mayAlreadyHaveExternalEffect: true
            )

        case .failed, .cancelledBeforeSend, .incompatible:
            return .init(
                allowed: false,
                rationale: "There is no active outbound send left to cancel.",
                mayAlreadyHaveExternalEffect: deliveryState.externalEffect.changedAnythingExternally
            )
        }
    }

    func auditDecision(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft?,
        deliveryState: ExchangeDeliveryState?
    ) -> AuditDecision {
        if draft != nil || deliveryState != nil || thread.selectedCounterpartyID != nil {
            return .init(
                required: true,
                rationale: "External coordination state should remain auditable."
            )
        }

        return .init(
            required: false,
            rationale: "No federation-visible action exists yet."
        )
    }

    func retryDecision(
        thread: ExchangeThread,
        deliveryState: ExchangeDeliveryState?
    ) -> RetryDecision {
        if let deliveryState {
            if deliveryState.mayRetry {
                return .init(
                    allowed: true,
                    rationale: "The current delivery state supports retry."
                )
            }

            if deliveryState.phase.isTerminal || deliveryState.phase == .sending || deliveryState.phase == .sent {
                return .init(
                    allowed: false,
                    rationale: "The current delivery state does not support retry."
                )
            }
        }

        if let failure = thread.latestFailure {
            if failure.isRetryable {
                return .init(
                    allowed: true,
                    rationale: "The latest failure is marked retryable."
                )
            }

            return .init(
                allowed: false,
                rationale: "The latest failure is not marked retryable."
            )
        }

        switch thread.state {
        case .blockedByDeliveryFailure,
             .stalled,
             .noViableMatch,
             .matchCandidatesWeak,
             .matchFound,
             .declined:
            return .init(
                allowed: true,
                rationale: "The current thread state supports another attempt or recovery path."
            )

        case .drafting,
             .draftReady,
             .needsClarification,
             .searching,
             .awaitingApproval,
             .sending,
             .awaitingResponse,
             .resolved,
             .blockedBySystemFailure:
            return .init(
                allowed: false,
                rationale: "Retry is not the right action for the current thread state."
            )
        }
    }

    func followUpDecision(thread: ExchangeThread) -> FollowUpDecision {
        switch thread.state {
        case .awaitingResponse:
            return .init(
                allowed: true,
                rationale: "The thread is waiting on an external response."
            )

        case .stalled:
            return .init(
                allowed: true,
                rationale: "A stalled thread may benefit from a follow-up."
            )

        case .blockedByDeliveryFailure,
             .drafting,
             .draftReady,
             .needsClarification,
             .searching,
             .matchFound,
             .matchCandidatesWeak,
             .noViableMatch,
             .awaitingApproval,
             .sending,
             .declined,
             .resolved,
             .blockedBySystemFailure:
            return .init(
                allowed: false,
                rationale: "Follow-up is not appropriate for the current thread state."
            )
        }
    }

    func closureDecision(thread: ExchangeThread) -> ClosureDecision {
        switch thread.state {
        case .resolved, .declined, .stalled, .noViableMatch:
            return .init(
                allowed: true,
                rationale: "This thread can be closed cleanly."
            )

        case .drafting,
             .draftReady,
             .needsClarification,
             .searching,
             .matchFound,
             .matchCandidatesWeak,
             .awaitingApproval,
             .sending,
             .blockedByDeliveryFailure,
             .awaitingResponse,
             .blockedBySystemFailure:
            return .init(
                allowed: false,
                rationale: "Closing now would likely hide unfinished coordination state."
            )
        }
    }

    func threadHasTrustedIntroduction(
        _ thread: ExchangeThread
    ) -> Bool {
        if let selectedPath = thread.selectedPath,
           selectedPath.accessMode == .introOnly && selectedPath.status == .selected {
            return true
        }

        if let mode = thread.metadata["contact_mode"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           mode == "introduced" || mode == "trusted_path" {
            return true
        }

        if let trustedPathID = thread.metadata["trusted_path_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !trustedPathID.isEmpty {
            return true
        }

        return false
    }

    func trustLevel(
        for counterparty: ExchangeCounterparty?
    ) -> ExchangeCounterparty.TrustSnapshot.Level? {
        counterparty?.trust.level
    }

    func trustRank(
        _ level: ExchangeCounterparty.TrustSnapshot.Level
    ) -> Int {
        switch level {
        case .unverified: return 0
        case .low: return 1
        case .moderate: return 2
        case .high: return 3
        }
    }

    func relayDisclosureLevel(
        from ceiling: ExchangePublicNodeProfile.ReachabilityPolicy.DisclosureCeiling
    ) -> ExchangeRelayEnvelope.Payload.DisclosureLevel {
        switch ceiling {
        case .minimal:
            return .minimal
        case .balanced:
            return .balanced
        case .open:
            return .open
        }
    }

    func modeAllowed(
        _ mode: ExchangeMode,
        publicProfile: ExchangePublicNodeProfile
    ) -> Bool {
        let allowed = publicProfile.reachability.allowedModes
        guard !allowed.isEmpty else { return true }
        return allowed.contains(mode.rawValue.lowercased())
    }

    func intentKindAllowed(
        _ kind: ExchangeIntent.Kind,
        publicProfile: ExchangePublicNodeProfile
    ) -> Bool {
        let allowed = publicProfile.reachability.allowedIntentKinds
        guard !allowed.isEmpty else { return true }
        return allowed.contains(kind.rawValue.lowercased())
    }

    func audienceAllowed(
        thread: ExchangeThread,
        publicProfile: ExchangePublicNodeProfile
    ) -> Bool {
        let allowed = publicProfile.reachability.allowedAudienceKinds
        guard !allowed.isEmpty else { return true }

        let requestedAudience = inferredAudienceKind(for: thread)
        guard let requestedAudience else { return true }
        return allowed.contains(requestedAudience)
    }

    func inferredAudienceKind(
        for thread: ExchangeThread
    ) -> ExchangePublicNodeProfile.SemanticSurface.AudienceKind? {
        if let targetKind = thread.facets?.targetKind {
            switch targetKind {
            case .person:
                return .person
            case .provider:
                return .provider
            case .business:
                return .business
            case .organization:
                return .organization
            case .group:
                return .group
            case .secretaryNode:
                return .secretaryNode
            case .unknown:
                break
            }
        }

        switch thread.intent.queryIntentClass {
        case .providerSearch, .offerSearch:
            return .provider
        case .capabilitySearch, .collaborationSearch:
            return .business
        case .socialAffinitySearch, .relationshipSearch:
            return .person
        case .directOutreach, .followUp, .statusCheck:
            if thread.selectedCounterpartyID != nil {
                return .secretaryNode
            }
            return nil
        case .generalDiscovery:
            return nil
        }
    }

    func categoryMatchSatisfied(
        thread: ExchangeThread,
        publicProfile: ExchangePublicNodeProfile
    ) -> Bool {
        let policy = publicProfile.reachability.intentCategoryPolicy

        let baseText: [String] = [
            thread.intent.title,
            thread.intent.targetDescription,
            thread.intent.objective,
            thread.facets?.searchableText,
            thread.interpretation?.userSummary,
            thread.interpretation?.userQuestion
        ].compactMap { $0 }

        let interpretationSemanticTags = thread.interpretation?.semanticTags ?? []
        let interpretationTargetTags = thread.interpretation?.targetTags ?? []
        let interpretationDiscoveryKeywords = thread.interpretation?.discoveryKeywords ?? []

        let laneTokens = [
            thread.intent.queryIntentClass.rawValue,
            thread.intent.surfacePreference.rawValue
        ]

        let requestedInput =
            baseText +
            interpretationSemanticTags +
            interpretationTargetTags +
            interpretationDiscoveryKeywords +
            laneTokens

        let requestedTokens = Set(normalizedTerms(requestedInput))

        let offerTokens = Set(normalizedTerms(publicProfile.offers))
        let openToTokens = Set(normalizedTerms(publicProfile.openTo))
        let semanticTokens = Set(normalizedTerms(publicProfile.semantic.searchableTerms))
        let activityTokens = Set(normalizedTerms(publicProfile.activityTags))
        let interestTokens = Set(normalizedTerms(publicProfile.interests))
        let regionTokens = Set(normalizedTerms(publicProfile.regionTags))

        let allProfileTokens =
            offerTokens
            .union(openToTokens)
            .union(semanticTokens)
            .union(activityTokens)
            .union(interestTokens)
            .union(regionTokens)

        switch policy {
        case .broad:
            return true

        case .permissive:
            // Remote/default compatibility mode.
            // Allow when there is no useful request/category signal yet,
            // otherwise prefer at least some lightweight public-surface overlap.
            if requestedTokens.isEmpty { return true }
            if allProfileTokens.isEmpty { return true }
            return !requestedTokens.intersection(allProfileTokens).isEmpty

        case .matchedCategoriesOnly:
            if requestedTokens.isEmpty {
                return false
            }
            return !requestedTokens.intersection(allProfileTokens).isEmpty

        case .listedCategoriesOnly:
            if requestedTokens.isEmpty {
                return false
            }

            let listed = offerTokens.union(openToTokens)
            guard !listed.isEmpty else { return false }

            return !requestedTokens.intersection(listed).isEmpty
        }
    }

    func mutualFitSatisfied(
        thread: ExchangeThread,
        selectedCounterparty: ExchangeCounterparty?
    ) -> Bool {
        if threadHasTrustedIntroduction(thread) {
            return true
        }

        guard let selectedCounterparty else { return false }
        return trustRank(selectedCounterparty.trust.level) >= trustRank(.moderate)
    }

    func normalizedTerms(
        _ values: [String]
    ) -> [String] {
        Array(
            Set(
                values
                    .flatMap {
                        $0.lowercased()
                            .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
    }
}

private extension ExchangeRelayEnvelope.Payload.DisclosureLevel {
    func clamped(to ceiling: Self) -> Self {
        switch (self, ceiling) {
        case (_, .minimal):
            return .minimal
        case (.open, .balanced):
            return .balanced
        default:
            return self
        }
    }
}
