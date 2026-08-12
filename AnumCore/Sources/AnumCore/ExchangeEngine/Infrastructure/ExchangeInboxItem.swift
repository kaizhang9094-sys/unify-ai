import Foundation

/// Durable inbound federation item before reconciliation into thread state.
///
/// This allows:
/// - version handling
/// - deduplication
/// - out-of-order receive handling
/// - user-auditable inbound history
/// - safe replay/reconciliation after app restarts
public struct ExchangeInboxItem: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var receivedAt: Date
    public var updatedAt: Date

    public var envelopeID: String
    public var threadID: ExchangeThread.ID?
    public var senderNodeID: String?
    public var senderDisplayName: String?

    public var ordering: Ordering
    public var compatibility: Compatibility
    public var processingState: ProcessingState

    public var visibleSummary: String
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        receivedAt: Date = Date(),
        updatedAt: Date = Date(),
        envelopeID: String,
        threadID: ExchangeThread.ID? = nil,
        senderNodeID: String? = nil,
        senderDisplayName: String? = nil,
        ordering: Ordering = .init(),
        compatibility: Compatibility = .supported,
        processingState: ProcessingState = .received,
        visibleSummary: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.updatedAt = updatedAt
        self.envelopeID = envelopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.threadID = threadID
        self.senderNodeID = senderNodeID?.exchangeNilIfBlank
        self.senderDisplayName = senderDisplayName?.exchangeNilIfBlank
        self.ordering = ordering
        self.compatibility = compatibility
        self.processingState = processingState
        self.visibleSummary = visibleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.metadata = metadata
    }
}

public extension ExchangeInboxItem {
    struct Ordering: Codable, Sendable, Hashable {
        /// Sender-local per-thread sequence, if available.
        public var sequenceNumber: Int?
        public var parentEnvelopeID: String?
        public var senderTimestamp: Date?

        public init(
            sequenceNumber: Int? = nil,
            parentEnvelopeID: String? = nil,
            senderTimestamp: Date? = nil
        ) {
            self.sequenceNumber = sequenceNumber.map { max(0, $0) }
            self.parentEnvelopeID = parentEnvelopeID?.exchangeNilIfBlank
            self.senderTimestamp = senderTimestamp
        }
    }

    enum Compatibility: Codable, Sendable, Hashable {
        case supported
        case unsupportedVersion(version: String?)
        case unsupportedPayload(kind: String?)
        case invalidSignature
        case malformed(reason: String)

        /// Whether the item is safe to reconcile automatically into thread state.
        public var isProcessable: Bool {
            switch self {
            case .supported:
                return true
            case .unsupportedVersion, .unsupportedPayload, .invalidSignature, .malformed:
                return false
            }
        }
    }

    enum ProcessingState: String, Codable, Sendable, CaseIterable, Hashable {
        case received
        case deferred
        case duplicateIgnored
        case awaitingOrderingGapResolution
        case reconciledIntoThread
        case rejected
        case archived
    }
}

public extension ExchangeInboxItem {
    var isTerminal: Bool {
        switch processingState {
        case .reconciledIntoThread, .rejected, .archived, .duplicateIgnored:
            return true
        case .received, .deferred, .awaitingOrderingGapResolution:
            return false
        }
    }

    var shouldBlockAutomaticReconciliation: Bool {
        if !compatibility.isProcessable {
            return true
        }

        switch processingState {
        case .awaitingOrderingGapResolution:
            return true
        case .received, .deferred, .duplicateIgnored, .reconciledIntoThread, .rejected, .archived:
            return false
        }
    }

    func markingDeferred(
        at date: Date = Date()
    ) -> ExchangeInboxItem {
        var copy = self
        copy.processingState = .deferred
        copy.updatedAt = date
        return copy
    }

    func markingDuplicateIgnored(
        at date: Date = Date()
    ) -> ExchangeInboxItem {
        var copy = self
        copy.processingState = .duplicateIgnored
        copy.updatedAt = date
        return copy
    }

    func markingAwaitingOrderingGapResolution(
        at date: Date = Date()
    ) -> ExchangeInboxItem {
        var copy = self
        copy.processingState = .awaitingOrderingGapResolution
        copy.updatedAt = date
        return copy
    }

    func reconcilingIntoThread(
        at date: Date = Date()
    ) -> ExchangeInboxItem {
        var copy = self
        copy.processingState = .reconciledIntoThread
        copy.updatedAt = date
        return copy
    }

    func rejecting(
        at date: Date = Date()
    ) -> ExchangeInboxItem {
        var copy = self
        copy.processingState = .rejected
        copy.updatedAt = date
        return copy
    }

    func archiving(
        at date: Date = Date()
    ) -> ExchangeInboxItem {
        var copy = self
        copy.processingState = .archived
        copy.updatedAt = date
        return copy
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
