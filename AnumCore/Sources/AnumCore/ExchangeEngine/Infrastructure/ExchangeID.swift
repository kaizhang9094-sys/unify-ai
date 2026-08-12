import Foundation

/// Centralized ID generation for Exchange records.
///
/// Keep UUID-backed record creation consistent across the module.
/// String-based identifiers that come from external systems or federation
/// identity should generally not be minted here unless they become
/// explicitly runtime-owned IDs.
public protocol ExchangeIDGenerator: Sendable {
    func makeThreadID() -> ExchangeThread.ID
    func makeTurnID() -> ExchangeTurn.ID
    func makeApprovalID() -> ExchangeApproval.ID
    func makeDraftID() -> ExchangeMessageDraft.ID
    func makeOutcomeID() -> ExchangeOutcome.ID
    func makeArtifactID() -> ExchangeArtifact.ID
    func makeFailureID() -> ExchangeFailure.ID
    func makeMatchID() -> ExchangeMatch.ID

    func makeInboxItemID() -> ExchangeInboxItem.ID
    func makeOutboxItemID() -> ExchangeOutboxItem.ID
    func makeAuditRecordID() -> ExchangeAuditRecord.ID

    func makeTrustEdgeID() -> ExchangeTrustEdge.ID
    func makeTrustEvidenceID() -> ExchangeTrustEvidence.ID

    func makeEnvelopeID() -> ExchangeRelayEnvelope.ID
}

public struct DefaultExchangeIDGenerator: ExchangeIDGenerator {
    public init() {}

    public func makeThreadID() -> ExchangeThread.ID { UUID() }
    public func makeTurnID() -> ExchangeTurn.ID { UUID() }
    public func makeApprovalID() -> ExchangeApproval.ID { UUID() }
    public func makeDraftID() -> ExchangeMessageDraft.ID { UUID() }
    public func makeOutcomeID() -> ExchangeOutcome.ID { UUID() }
    public func makeArtifactID() -> ExchangeArtifact.ID { UUID() }
    public func makeFailureID() -> ExchangeFailure.ID { UUID() }
    public func makeMatchID() -> ExchangeMatch.ID { UUID() }

    public func makeInboxItemID() -> ExchangeInboxItem.ID { UUID() }
    public func makeOutboxItemID() -> ExchangeOutboxItem.ID { UUID() }
    public func makeAuditRecordID() -> ExchangeAuditRecord.ID { UUID() }

    public func makeTrustEdgeID() -> ExchangeTrustEdge.ID { UUID() }
    public func makeTrustEvidenceID() -> ExchangeTrustEvidence.ID { UUID() }

    public func makeEnvelopeID() -> ExchangeRelayEnvelope.ID { UUID() }
}
