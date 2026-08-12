import Foundation

/// Creates and resolves approval boundaries for Exchange.
///
/// This engine does not send anything.
/// It only formalizes whether a human decision is required and records that boundary.
///
/// Important:
/// this engine should not duplicate policy. It should rely on `ExchangePolicyEngine`
/// for whether approval is required, then build the approval object consistently.
public struct ExchangeApprovalEngine: Sendable {
    private let policyEngine: ExchangePolicyEngine

    public init(
        policyEngine: ExchangePolicyEngine = .init()
    ) {
        self.policyEngine = policyEngine
    }

    public func approvalRequirement(
        for thread: ExchangeThread,
        draft: ExchangeMessageDraft?,
        deliveryState: ExchangeDeliveryState? = nil
    ) -> ApprovalRequirement {
        let decision = policyEngine.evaluate(
            thread: thread,
            selectedCounterparty: nil,
            draft: draft,
            deliveryState: deliveryState
        ).approval

        if decision.required {
            return .required(rationale: decision.rationale)
        }

        return .notRequired
    }

    public func createApproval(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft?,
        kind: ExchangeApproval.Kind = .outboundSend,
        expiresAt: Date? = nil,
        deliveryState: ExchangeDeliveryState? = nil,
        now: Date = Date()
    ) -> ExchangeApproval {
        let approvalRequirement = approvalRequirement(
            for: thread,
            draft: draft,
            deliveryState: deliveryState
        )

        let requestedAction = requestedAction(for: kind, draft: draft)
        let summary = summary(for: thread, draft: draft, requestedAction: requestedAction)

        let rationale: String? = {
            switch approvalRequirement {
            case .required(let rationale):
                return enrichedRationale(
                    baseRationale: rationale,
                    thread: thread,
                    kind: kind,
                    draft: draft
                )
            case .notRequired:
                return nil
            }
        }()

        return ExchangeApproval(
            threadID: thread.id,
            createdAt: now,
            updatedAt: now,
            status: .pending,
            kind: kind,
            requestedAction: requestedAction,
            draftID: draft?.id,
            summary: summary,
            rationale: rationale,
            expiresAt: expiresAt
        )
    }

    public func resolveApproval(
        _ approval: ExchangeApproval,
        decision: Decision,
        now: Date = Date(),
        note: String? = nil
    ) -> ExchangeApproval {
        switch decision {
        case .approve:
            return approval.approving(at: now, note: note)
        case .reject:
            return approval.rejecting(at: now, note: note)
        case .expire:
            return approval.expiring(at: now, note: note)
        case .cancel:
            return approval.cancelling(at: now, note: note)
        }
    }
}

public extension ExchangeApprovalEngine {
    enum ApprovalRequirement: Sendable, Hashable {
        case required(rationale: String)
        case notRequired

        public var requiresApproval: Bool {
            switch self {
            case .required:
                return true
            case .notRequired:
                return false
            }
        }
    }

    enum Decision: String, Sendable, Hashable {
        case approve
        case reject
        case expire
        case cancel
    }
}

private extension ExchangeApprovalEngine {
    func requestedAction(
        for kind: ExchangeApproval.Kind,
        draft: ExchangeMessageDraft?
    ) -> ExchangeApproval.RequestedAction {
        switch kind {
        case .outboundSend:
            return .sendMessage

        case .followUpSend:
            return .sendFollowUp

        case .discloseMoreContext:
            return .discloseContext(fields: disclosureFields(from: draft))

        case .negotiationStep:
            let label = draft?.strategyNote ?? "Approve the negotiation move."
            return .negotiate(summary: label)

        case .closeOrWithdraw:
            return .closeThread(reason: "Approve closing or withdrawing this thread.")

        case .other:
            return .other(label: "Approve this action.")
        }
    }

    func disclosureFields(from draft: ExchangeMessageDraft?) -> [String] {
        guard let draft else { return [] }

        var output: [String] = []

        if let subject = draft.subject, !subject.isEmpty {
            output.append("subject")
        }

        if draft.body.count > 80 {
            output.append("body details")
        }

        return output
    }

    func summary(
        for thread: ExchangeThread,
        draft: ExchangeMessageDraft?,
        requestedAction: ExchangeApproval.RequestedAction
    ) -> String {
        if let target = thread.intent.targetDescription, !target.isEmpty {
            return "Approve this action for \(target): \(requestedAction.summaryLine)"
        }

        if let preview = draft?.previewText, !preview.isEmpty {
            return "Approve this draft: \(preview)"
        }

        return requestedAction.summaryLine
    }

    func enrichedRationale(
        baseRationale: String,
        thread: ExchangeThread,
        kind: ExchangeApproval.Kind,
        draft: ExchangeMessageDraft?
    ) -> String {
        var parts: [String] = [baseRationale]

        if kind == .negotiationStep {
            parts.append("Negotiation can materially change the thread outcome.")
        }

        if draft?.kind == .followUp {
            parts.append("Follow-up timing can affect the tone of the thread.")
        }

        if thread.posture.privacy == .guarded &&
            !parts.contains(where: { $0.localizedCaseInsensitiveContains("privacy") }) {
            parts.append("The current posture is privacy-sensitive.")
        }

        return parts.joined(separator: " ")
    }
}
