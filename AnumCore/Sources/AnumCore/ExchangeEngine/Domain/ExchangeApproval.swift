import Foundation

/// Human approval boundary for external coordination.
///
/// Approval is first-class in Exchange. Anything that may create or change an
/// external state should pass through a clear approval object unless policy
/// explicitly says otherwise.
public struct ExchangeApproval: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var threadID: ExchangeThread.ID
    public var createdAt: Date
    public var updatedAt: Date

    public var status: Status
    public var kind: Kind
    public var requestedAction: RequestedAction

    /// Optional draft tied to this approval request.
    public var draftID: ExchangeMessageDraft.ID?

    /// What the user is being asked to approve, in plain language.
    public var summary: String

    /// Optional explanation of why approval is required.
    public var rationale: String?

    /// Optional expiration boundary for stale approvals.
    public var expiresAt: Date?

    /// Decision metadata.
    public var decidedAt: Date?
    public var decisionNote: String?

    /// Small future-safe metadata only.
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        threadID: ExchangeThread.ID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: Status = .pending,
        kind: Kind,
        requestedAction: RequestedAction,
        draftID: ExchangeMessageDraft.ID? = nil,
        summary: String,
        rationale: String? = nil,
        expiresAt: Date? = nil,
        decidedAt: Date? = nil,
        decisionNote: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.threadID = threadID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.kind = kind
        self.requestedAction = requestedAction
        self.draftID = draftID
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rationale = rationale?.nilIfBlank
        self.expiresAt = expiresAt
        self.decidedAt = decidedAt
        self.decisionNote = decisionNote?.nilIfBlank
        self.metadata = metadata
    }
}

public extension ExchangeApproval {
    enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case pending
        case approved
        case rejected
        case expired
        case cancelled
    }

    /// Broad approval families.
    ///
    /// Keep this compact. Detailed payload belongs in RequestedAction.
    enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
        /// Approve the first outbound contact.
        case outboundSend

        /// Approve a follow-up after silence or stall.
        case followUpSend

        /// Approve disclosure of extra context.
        case discloseMoreContext

        /// Approve a negotiation move.
        case negotiationStep

        /// Approve a closure, decline, or withdrawal action.
        case closeOrWithdraw

        /// Reserved fallback.
        case other
    }

    /// The concrete user-facing action awaiting approval.
    enum RequestedAction: Codable, Sendable, Hashable {
        case sendMessage
        case sendFollowUp
        case discloseContext(fields: [String])
        case negotiate(summary: String)
        case closeThread(reason: String)
        case other(label: String)

        public var summaryLine: String {
            switch self {
            case .sendMessage:
                return "Send the prepared message."
            case .sendFollowUp:
                return "Send a follow-up."
            case .discloseContext(let fields):
                if fields.isEmpty {
                    return "Disclose additional context."
                }
                return "Disclose additional context: \(fields.joined(separator: ", "))"
            case .negotiate(let summary):
                let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Proceed with the negotiation step." : text
            case .closeThread(let reason):
                let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Close the thread." : "Close the thread: \(text)"
            case .other(let label):
                let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Approve the requested action." : text
            }
        }
    }
}

public extension ExchangeApproval {
    var isPending: Bool {
        status == .pending
    }

    var isDecided: Bool {
        switch status {
        case .approved, .rejected, .expired, .cancelled:
            return true
        case .pending:
            return false
        }
    }

    /// Whether the approval is stale by explicit state or wall-clock expiry.
    ///
    /// Note: this does not mutate the object. Persisted normalization should be
    /// handled by the approval engine or store.
    var isExpired: Bool {
        if status == .expired {
            return true
        }
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    var canStillBeActedOn: Bool {
        status == .pending && !isExpired
    }

    func approving(
        at date: Date = Date(),
        note: String? = nil
    ) -> ExchangeApproval {
        var copy = self
        copy.status = .approved
        copy.updatedAt = date
        copy.decidedAt = date
        copy.decisionNote = note?.nilIfBlank
        return copy
    }

    func rejecting(
        at date: Date = Date(),
        note: String? = nil
    ) -> ExchangeApproval {
        var copy = self
        copy.status = .rejected
        copy.updatedAt = date
        copy.decidedAt = date
        copy.decisionNote = note?.nilIfBlank
        return copy
    }

    func expiring(
        at date: Date = Date(),
        note: String? = nil
    ) -> ExchangeApproval {
        var copy = self
        copy.status = .expired
        copy.updatedAt = date
        copy.decidedAt = date
        copy.decisionNote = note?.nilIfBlank
        return copy
    }

    func cancelling(
        at date: Date = Date(),
        note: String? = nil
    ) -> ExchangeApproval {
        var copy = self
        copy.status = .cancelled
        copy.updatedAt = date
        copy.decidedAt = date
        copy.decisionNote = note?.nilIfBlank
        return copy
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
