import Foundation

/// Durable audit trail for federation-visible actions.
///
/// This is not a debug log.
/// It is the user-facing truth substrate for questions like:
/// - what did you send on my behalf?
/// - when was it sent?
/// - did anything external actually happen?
/// - what failed and what did not happen?
public struct ExchangeAuditRecord: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var createdAt: Date
    public var threadID: ExchangeThread.ID?

    public var direction: Direction
    public var category: Category
    public var actor: Actor

    public var envelopeID: String?
    public var outboxItemID: ExchangeOutboxItem.ID?
    public var inboxItemID: ExchangeInboxItem.ID?

    public var summary: String
    public var detail: String?
    public var externalEffect: ExchangeFailure.ExternalEffect

    public var relatedNodeID: String?
    public var relatedDisplayName: String?
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        createdAt: Date = Date(),
        threadID: ExchangeThread.ID? = nil,
        direction: Direction,
        category: Category,
        actor: Actor,
        envelopeID: String? = nil,
        outboxItemID: ExchangeOutboxItem.ID? = nil,
        inboxItemID: ExchangeInboxItem.ID? = nil,
        summary: String,
        detail: String? = nil,
        externalEffect: ExchangeFailure.ExternalEffect = .none,
        relatedNodeID: String? = nil,
        relatedDisplayName: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.threadID = threadID
        self.direction = direction
        self.category = category
        self.actor = actor
        self.envelopeID = envelopeID?.exchangeNilIfBlank
        self.outboxItemID = outboxItemID
        self.inboxItemID = inboxItemID
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail?.exchangeNilIfBlank
        self.externalEffect = externalEffect
        self.relatedNodeID = relatedNodeID?.exchangeNilIfBlank
        self.relatedDisplayName = relatedDisplayName?.exchangeNilIfBlank
        self.metadata = metadata
    }
}

public extension ExchangeAuditRecord {
    enum Direction: String, Codable, Sendable, CaseIterable, Hashable {
        case outbound
        case inbound
        case localOnly
    }

    /// Keep categories user-legible and audit-oriented.
    enum Category: String, Codable, Sendable, CaseIterable, Hashable {
        case queued
        case sendStarted
        case sent
        case acknowledged
        case cancelled
        case failed
        case incompatible
        case received
        case reconciledIntoThread
        case duplicateIgnored
        case deferred
        case approvalRevoked
        case blockedByPolicy
    }

    enum Actor: String, Codable, Sendable, CaseIterable, Hashable {
        case user
        case secretary
        case relay
        case remoteNode
        case system
    }
}

public extension ExchangeAuditRecord {
    var userFacingLine: String {
        if let relatedDisplayName, !relatedDisplayName.isEmpty {
            return "\(summary) (\(relatedDisplayName))"
        }
        return summary
    }

    static func outboundQueued(
        threadID: ExchangeThread.ID,
        outboxItemID: ExchangeOutboxItem.ID,
        envelopeID: String,
        relatedNodeID: String,
        relatedDisplayName: String?,
        createdAt: Date = Date()
    ) -> ExchangeAuditRecord {
        ExchangeAuditRecord(
            createdAt: createdAt,
            threadID: threadID,
            direction: .outbound,
            category: .queued,
            actor: .secretary,
            envelopeID: envelopeID,
            outboxItemID: outboxItemID,
            summary: "Queued a message for delivery.",
            externalEffect: .none,
            relatedNodeID: relatedNodeID,
            relatedDisplayName: relatedDisplayName
        )
    }

    static func outboundSent(
        threadID: ExchangeThread.ID,
        outboxItemID: ExchangeOutboxItem.ID,
        envelopeID: String,
        relatedNodeID: String,
        relatedDisplayName: String?,
        externalEffect: ExchangeFailure.ExternalEffect = .attemptedButNotConfirmed,
        createdAt: Date = Date()
    ) -> ExchangeAuditRecord {
        ExchangeAuditRecord(
            createdAt: createdAt,
            threadID: threadID,
            direction: .outbound,
            category: .sent,
            actor: .secretary,
            envelopeID: envelopeID,
            outboxItemID: outboxItemID,
            summary: "Sent a message outward.",
            externalEffect: externalEffect,
            relatedNodeID: relatedNodeID,
            relatedDisplayName: relatedDisplayName
        )
    }

    static func outboundAcknowledged(
        threadID: ExchangeThread.ID,
        outboxItemID: ExchangeOutboxItem.ID,
        envelopeID: String,
        relatedNodeID: String,
        relatedDisplayName: String?,
        createdAt: Date = Date()
    ) -> ExchangeAuditRecord {
        ExchangeAuditRecord(
            createdAt: createdAt,
            threadID: threadID,
            direction: .outbound,
            category: .acknowledged,
            actor: .relay,
            envelopeID: envelopeID,
            outboxItemID: outboxItemID,
            summary: "Delivery was acknowledged.",
            externalEffect: .changed(description: "The remote side acknowledged receipt."),
            relatedNodeID: relatedNodeID,
            relatedDisplayName: relatedDisplayName
        )
    }

    static func outboundCancelled(
        threadID: ExchangeThread.ID,
        outboxItemID: ExchangeOutboxItem.ID,
        envelopeID: String?,
        relatedNodeID: String,
        relatedDisplayName: String?,
        detail: String?,
        externalEffect: ExchangeFailure.ExternalEffect,
        createdAt: Date = Date()
    ) -> ExchangeAuditRecord {
        ExchangeAuditRecord(
            createdAt: createdAt,
            threadID: threadID,
            direction: .outbound,
            category: .cancelled,
            actor: .user,
            envelopeID: envelopeID,
            outboxItemID: outboxItemID,
            summary: "Cancellation was applied.",
            detail: detail,
            externalEffect: externalEffect,
            relatedNodeID: relatedNodeID,
            relatedDisplayName: relatedDisplayName
        )
    }

    static func inboundReceived(
        inboxItemID: ExchangeInboxItem.ID,
        envelopeID: String,
        threadID: ExchangeThread.ID?,
        relatedNodeID: String?,
        relatedDisplayName: String?,
        summary: String,
        createdAt: Date = Date()
    ) -> ExchangeAuditRecord {
        ExchangeAuditRecord(
            createdAt: createdAt,
            threadID: threadID,
            direction: .inbound,
            category: .received,
            actor: .remoteNode,
            envelopeID: envelopeID,
            inboxItemID: inboxItemID,
            summary: summary,
            externalEffect: .changed(description: "An inbound message was received."),
            relatedNodeID: relatedNodeID,
            relatedDisplayName: relatedDisplayName
        )
    }

    static func failed(
        direction: Direction,
        category: Category = .failed,
        threadID: ExchangeThread.ID?,
        envelopeID: String?,
        outboxItemID: ExchangeOutboxItem.ID? = nil,
        inboxItemID: ExchangeInboxItem.ID? = nil,
        summary: String,
        detail: String?,
        externalEffect: ExchangeFailure.ExternalEffect,
        relatedNodeID: String?,
        relatedDisplayName: String?,
        createdAt: Date = Date()
    ) -> ExchangeAuditRecord {
        ExchangeAuditRecord(
            createdAt: createdAt,
            threadID: threadID,
            direction: direction,
            category: category,
            actor: .system,
            envelopeID: envelopeID,
            outboxItemID: outboxItemID,
            inboxItemID: inboxItemID,
            summary: summary,
            detail: detail,
            externalEffect: externalEffect,
            relatedNodeID: relatedNodeID,
            relatedDisplayName: relatedDisplayName
        )
    }

    /// Durable observability row for autonomous-send evaluation (not a policy block on its own).
    /// Uses `Category.blockedByPolicy` + `Direction.localOnly` only because the schema has no dedicated
    /// neutral "diagnostic" category; `metadata.trace_kind` distinguishes this from real policy blocks.
    static func autonomousSendAttemptTrace(
        attempt: AutonomousSendAttempt,
        createdAt: Date = Date()
    ) -> ExchangeAuditRecord {
        let summary: String
        if attempt.queued {
            summary = "Autonomous send trace — queued"
        } else if attempt.errorSummary != nil {
            summary = "Autonomous send trace — failed"
        } else {
            summary = "Autonomous send trace — skipped"
        }
        return ExchangeAuditRecord(
            createdAt: createdAt,
            threadID: attempt.threadID,
            direction: .localOnly,
            category: .blockedByPolicy,
            actor: .secretary,
            summary: summary,
            detail: attempt.compactDetailLine(),
            externalEffect: .none,
            relatedNodeID: nil,
            relatedDisplayName: nil,
            metadata: attempt.toMetadata()
        )
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
