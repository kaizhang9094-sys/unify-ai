import Foundation

/// Evidence explaining why a trust edge exists or changed.
///
/// This keeps trust legible and auditable.
/// Trust should be explainable, not just numerically accumulated.
///
/// Important:
/// this is an evidence record, not the trust-scoring engine itself.
public struct ExchangeTrustEvidence: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var trustEdgeID: ExchangeTrustEdge.ID

    public var type: EvidenceType

    /// Relative evidence weight for downstream trust computation.
    /// Keep this bounded and interpretable.
    public var weight: Double

    public var threadID: ExchangeThread.ID?
    public var relatedCounterpartyID: ExchangeCounterparty.ID?
    public var summary: String?
    public var note: String?

    public var recordedAt: Date
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        trustEdgeID: ExchangeTrustEdge.ID,
        type: EvidenceType,
        weight: Double = 1.0,
        threadID: ExchangeThread.ID? = nil,
        relatedCounterpartyID: ExchangeCounterparty.ID? = nil,
        summary: String? = nil,
        note: String? = nil,
        recordedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.trustEdgeID = trustEdgeID
        self.type = type
        self.weight = Self.clamp(weight)
        self.threadID = threadID
        self.relatedCounterpartyID = relatedCounterpartyID?.exchangeNilIfBlank
        self.summary = summary?.exchangeNilIfBlank
        self.note = note?.exchangeNilIfBlank
        self.recordedAt = recordedAt
        self.metadata = metadata
    }
}

public extension ExchangeTrustEvidence {
    enum EvidenceType: String, Codable, Sendable, CaseIterable, Hashable {
        case manualAdd
        case manualUpgrade
        case importedContact
        case successfulThread
        case threadCompleted
        case repeatedSelection
        case repeatedApproval
        case userApprovedContact
        case userDeclinedContact
        case deliveryConfirmed
        case deliveryFailed
        case replyReceived
        case policyConcern
        case groundedPublicAnswer
        case userBlockedNode
        case mutualTrustObserved
        case verifiedIdentity
        case directIntroduction
        case systemObservation
        case revocation
    }
}

public extension ExchangeTrustEvidence {
    var isPositive: Bool {
        switch type {
        case .revocation,
             .userDeclinedContact,
             .deliveryFailed,
             .policyConcern,
             .userBlockedNode:
            return false
        case .manualAdd,
             .manualUpgrade,
             .importedContact,
             .successfulThread,
             .threadCompleted,
             .repeatedSelection,
             .repeatedApproval,
             .userApprovedContact,
             .deliveryConfirmed,
             .replyReceived,
             .groundedPublicAnswer,
             .mutualTrustObserved,
             .verifiedIdentity,
             .directIntroduction,
             .systemObservation:
            return true
        }
    }

    static func manualAdd(
        trustEdgeID: ExchangeTrustEdge.ID,
        note: String? = nil,
        recordedAt: Date = Date()
    ) -> ExchangeTrustEvidence {
        ExchangeTrustEvidence(
            trustEdgeID: trustEdgeID,
            type: .manualAdd,
            weight: 1.0,
            note: note,
            recordedAt: recordedAt
        )
    }

    static func successfulThread(
        trustEdgeID: ExchangeTrustEdge.ID,
        threadID: ExchangeThread.ID,
        summary: String? = nil,
        recordedAt: Date = Date()
    ) -> ExchangeTrustEvidence {
        ExchangeTrustEvidence(
            trustEdgeID: trustEdgeID,
            type: .successfulThread,
            weight: 1.2,
            threadID: threadID,
            summary: summary,
            recordedAt: recordedAt
        )
    }

    static func revocation(
        trustEdgeID: ExchangeTrustEdge.ID,
        note: String? = nil,
        recordedAt: Date = Date()
    ) -> ExchangeTrustEvidence {
        ExchangeTrustEvidence(
            trustEdgeID: trustEdgeID,
            type: .revocation,
            weight: 0.0,
            note: note,
            recordedAt: recordedAt
        )
    }
}

private extension ExchangeTrustEvidence {
    static func clamp(_ value: Double) -> Double {
        min(max(value, -5), 5)
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
