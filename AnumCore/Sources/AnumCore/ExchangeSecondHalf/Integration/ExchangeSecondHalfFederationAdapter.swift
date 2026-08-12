import Foundation

#if DEBUG
@inline(__always)
private func exchSecondHalfFederationLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeSecondHalfFederationAdapter] \(message())")
}
#else
@inline(__always)
private func exchSecondHalfFederationLog(_ message: @autoclosure () -> String) {}
#endif

/// Adapter for second-half clarification/proposal messaging over federation.
///
/// This is intentionally thin and future-facing: it gives the second-half
/// subsystem a clean outbound/inbound contract without forcing transport
/// details into the coordinator.
public protocol ExchangeSecondHalfFederationAdapter: Sendable {
    func sendClarification(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        draft: ExchangeDraftComposer.Draft
    ) async throws

    func sendProposal(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        draft: ExchangeDraftComposer.Draft
    ) async throws

    func sendDecisionUpdate(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        action: ExchangeSecondHalfAction
    ) async throws
}

/// Default no-op adapter for local development.
///
/// It records a lightweight outbound audit trail so you can test the subsystem
/// without real federation transport.
public actor ExchangeDefaultSecondHalfFederationAdapter: ExchangeSecondHalfFederationAdapter {
    public struct SentEvent: Codable, Hashable, Sendable {
        public var id: UUID
        public var threadID: UUID
        public var role: ExchangeSecondHalfRole
        public var kind: Kind
        public var createdAt: Date
        public var subject: String?
        public var body: String?

        public enum Kind: String, Codable, Hashable, Sendable {
            case clarification
            case proposal
            case decisionUpdate
        }

        public init(
            id: UUID = UUID(),
            threadID: UUID,
            role: ExchangeSecondHalfRole,
            kind: Kind,
            createdAt: Date = Date(),
            subject: String? = nil,
            body: String? = nil
        ) {
            self.id = id
            self.threadID = threadID
            self.role = role
            self.kind = kind
            self.createdAt = createdAt
            self.subject = subject
            self.body = body
        }
    }

    private var sentEvents: [SentEvent] = []

    public init() {}

    public func sendClarification(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        draft: ExchangeDraftComposer.Draft
    ) async throws {
        exchSecondHalfFederationLog("sendClarification thread=\(threadID.uuidString)")
        sentEvents.append(
            SentEvent(
                threadID: threadID,
                role: role,
                kind: .clarification,
                subject: draft.subject,
                body: draft.body
            )
        )
    }

    public func sendProposal(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        draft: ExchangeDraftComposer.Draft
    ) async throws {
        exchSecondHalfFederationLog("sendProposal thread=\(threadID.uuidString)")
        sentEvents.append(
            SentEvent(
                threadID: threadID,
                role: role,
                kind: .proposal,
                subject: draft.subject,
                body: draft.body
            )
        )
    }

    public func sendDecisionUpdate(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        action: ExchangeSecondHalfAction
    ) async throws {
        exchSecondHalfFederationLog(
            "sendDecisionUpdate thread=\(threadID.uuidString) action=\(action.rawValue)"
        )
        sentEvents.append(
            SentEvent(
                threadID: threadID,
                role: role,
                kind: .decisionUpdate,
                subject: action.displayTitle,
                body: nil
            )
        )
    }

    public func allSentEvents() -> [SentEvent] {
        sentEvents
    }
}
