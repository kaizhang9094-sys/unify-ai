import Foundation

/// Durable outbound friend/contact request on the contact-signal lane (not `ExchangeThread` / exchange outbox).
public struct OutgoingContactRequest: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public enum Phase: String, Codable, Sendable, Hashable, CaseIterable {
        case queued
        case sending
        case sent
        case failed
        /// Requester received acceptance from the target; no longer shown as pending outgoing.
        case accepted
    }

    public var id: ID
    public var targetNodeID: String
    public var targetDisplayName: String?
    public var targetProfileID: String?
    public var envelopeID: String
    public var correlationID: UUID
    public var phase: Phase
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    public var sentAt: Date?
    public var lastError: String?
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        targetNodeID: String,
        targetDisplayName: String? = nil,
        targetProfileID: String? = nil,
        envelopeID: String,
        correlationID: UUID,
        phase: Phase,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sentAt: Date? = nil,
        lastError: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.targetNodeID = targetNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetDisplayName = targetDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.targetProfileID = targetProfileID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.envelopeID = envelopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.correlationID = correlationID
        self.phase = phase
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sentAt = sentAt
        self.lastError = lastError?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.metadata = metadata
    }
}

public struct OutgoingContactRequestFilter: Sendable, Hashable {
    public var targetNodeID: String?
    public var phases: Set<OutgoingContactRequest.Phase>?
    public var limit: Int?

    public init(
        targetNodeID: String? = nil,
        phases: Set<OutgoingContactRequest.Phase>? = nil,
        limit: Int? = nil
    ) {
        self.targetNodeID = targetNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.phases = phases
        self.limit = limit
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
