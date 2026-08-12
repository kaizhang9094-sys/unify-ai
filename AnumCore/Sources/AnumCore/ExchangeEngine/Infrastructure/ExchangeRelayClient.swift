import Foundation

/// Boundary for federated secretary-to-secretary transport.
///
/// Responsibilities:
/// - send outbound envelopes
/// - check delivery state when supported
/// - sync inbound relay receipts using a durable cursor
/// - acknowledge successfully persisted inbound receipts
///
/// The relay client must NOT own:
/// - thread mutation
/// - approval logic
/// - user-facing orchestration
/// - trust graph mutation
/// - inbox reconciliation
public protocol ExchangeRelayClient: Sendable {
    func send(
        _ envelope: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute?
    ) async throws -> ExchangeRelaySendResult

    func fetchDeliveryStatus(reference: String) async throws -> ExchangeRelayDeliveryStatus?

    func syncInbox(
        request: ExchangeRelayInboxSyncRequest
    ) async throws -> ExchangeRelayInboxSyncResponse

    func acknowledgeInboxItems(
        _ acknowledgements: [ExchangeRelayInboxAcknowledgement]
    ) async throws -> ExchangeRelayInboxAcknowledgeResponse
}

// MARK: - Outbound envelope

public struct ExchangeRelayEnvelope: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var createdAt: Date

    /// Protocol version for compatibility handling.
    public var protocolVersion: String

    /// Local thread that originated this envelope.
    public var threadID: ExchangeThread.ID

    /// Sender identity for the local node or user secretary.
    public var sender: Party

    /// Intended recipient routing information.
    public var recipient: Recipient

    /// Message payload.
    public var payload: Payload

    /// Optional detached or inline signature metadata.
    public var signature: Signature?

    /// Stable replay / ordering metadata.
    public var ordering: Ordering

    /// Small extensible metadata only.
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        createdAt: Date = Date(),
        protocolVersion: String = ExchangeProtocolVersion.current,
        threadID: ExchangeThread.ID,
        sender: Party,
        recipient: Recipient,
        payload: Payload,
        signature: Signature? = nil,
        ordering: Ordering = .init(),
        metadata: [String: String] = [:]
    ) {
        let cleanedProtocolVersion = protocolVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        self.id = id
        self.createdAt = createdAt
        self.protocolVersion = cleanedProtocolVersion.isEmpty ? ExchangeProtocolVersion.current : cleanedProtocolVersion
        self.threadID = threadID
        self.sender = sender
        self.recipient = recipient
        self.payload = payload
        self.signature = signature
        self.ordering = ordering
        self.metadata = metadata
    }
}

public extension ExchangeRelayEnvelope {
    struct Party: Codable, Sendable, Hashable {
        public var nodeID: String
        public var displayName: String?
        public var publicKeyID: String?

        public init(
            nodeID: String,
            displayName: String? = nil,
            publicKeyID: String? = nil
        ) {
            self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            self.displayName = displayName?.nilIfBlank
            self.publicKeyID = publicKeyID?.nilIfBlank
        }
    }

    struct Recipient: Codable, Sendable, Hashable {
        public var route: Route
        public var displayName: String?

        public init(
            route: Route,
            displayName: String? = nil
        ) {
            self.route = route
            self.displayName = displayName?.nilIfBlank
        }

        public enum Route: Codable, Sendable, Hashable {
            case node(id: String)
            case relayAddress(String)
            case email(String)
            case other(String)

            public var summaryLine: String {
                switch self {
                case .node(let id):
                    return "node:\(id)"
                case .relayAddress(let value):
                    return value
                case .email(let value):
                    return value
                case .other(let value):
                    return value
                }
            }
        }
    }

    struct Payload: Codable, Sendable, Hashable {
        public var kind: Kind
        public var subject: String?
        public var body: String
        public var disclosureLevel: DisclosureLevel
        public var threadContext: ThreadContext?
        /// Opaque E2EE payload. When nil, `body` carries legacy plaintext.
        public var encryption: ExchangeRelayPayloadEncryption?

        public init(
            kind: Kind,
            subject: String? = nil,
            body: String,
            disclosureLevel: DisclosureLevel = .minimal,
            threadContext: ThreadContext? = nil,
            encryption: ExchangeRelayPayloadEncryption? = nil
        ) {
            self.kind = kind
            self.subject = subject?.nilIfBlank
            self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            self.disclosureLevel = disclosureLevel
            self.threadContext = threadContext
            self.encryption = encryption
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case subject
            case body
            case disclosureLevel
            case threadContext
            case encryption
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .other
            subject = try container.decodeIfPresent(String.self, forKey: .subject)?.nilIfBlank
            body = try container.decodeIfPresent(String.self, forKey: .body)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            disclosureLevel = try container.decodeIfPresent(DisclosureLevel.self, forKey: .disclosureLevel) ?? .minimal
            threadContext = try container.decodeIfPresent(ThreadContext.self, forKey: .threadContext)
            encryption = try container.decodeIfPresent(ExchangeRelayPayloadEncryption.self, forKey: .encryption)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(subject, forKey: .subject)
            try container.encode(body, forKey: .body)
            try container.encode(disclosureLevel, forKey: .disclosureLevel)
            try container.encodeIfPresent(threadContext, forKey: .threadContext)
            try container.encodeIfPresent(encryption, forKey: .encryption)
        }

        public enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
            case introduction
            /// User-initiated contact / friend request (contact-layer signal, not exchange desk work).
            case friendRequest = "friend_request"
            /// Acceptor notifies requester that a friend/contact request was accepted.
            case friendRequestAccepted = "friend_request_accepted"
            case inquiry
            case quoteRequest
            case followUp
            case negotiation
            case scheduling
            case closure
            case other
        }

        public enum DisclosureLevel: String, Codable, Sendable, CaseIterable, Hashable {
            case minimal
            case balanced
            case open
        }

        public struct ThreadContext: Codable, Sendable, Hashable {
            public var localThreadID: String
            public var mode: String
            public var intentTitle: String?

            public init(
                localThreadID: String,
                mode: String,
                intentTitle: String? = nil
            ) {
                self.localThreadID = localThreadID.trimmingCharacters(in: .whitespacesAndNewlines)
                self.mode = mode.trimmingCharacters(in: .whitespacesAndNewlines)
                self.intentTitle = intentTitle?.nilIfBlank
            }
        }
    }

    struct Signature: Codable, Sendable, Hashable {
        public var algorithm: ExchangeCryptoSignature.Algorithm
        public var value: String
        public var keyID: String?
        public var signatureVersion: String?

        public init(
            algorithm: ExchangeCryptoSignature.Algorithm,
            value: String,
            keyID: String? = nil,
            signatureVersion: String? = nil
        ) {
            self.algorithm = algorithm
            self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            self.keyID = keyID?.nilIfBlank
            self.signatureVersion = signatureVersion?.nilIfBlank
        }
    }

    struct Ordering: Codable, Sendable, Hashable {
        /// Sender-local per-thread sequence number.
        public var sequenceNumber: Int?
        public var parentEnvelopeID: String?
        public var idempotencyKey: String?

        public init(
            sequenceNumber: Int? = nil,
            parentEnvelopeID: String? = nil,
            idempotencyKey: String? = nil
        ) {
            self.sequenceNumber = sequenceNumber.map { max(0, $0) }
            self.parentEnvelopeID = parentEnvelopeID?.nilIfBlank
            self.idempotencyKey = idempotencyKey?.nilIfBlank
        }
    }

    var stableEnvelopeID: String {
        if let key = ordering.idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }
        return id.uuidString
    }
}

// MARK: - Outbound send result

public struct ExchangeRelaySendResult: Codable, Sendable, Hashable {
    public var status: Status
    public var externalReference: String?
    public var acceptedAt: Date?
    public var routeSummary: String?
    public var note: String?

    public init(
        status: Status,
        externalReference: String? = nil,
        acceptedAt: Date? = nil,
        routeSummary: String? = nil,
        note: String? = nil
    ) {
        self.status = status
        self.externalReference = externalReference?.nilIfBlank
        self.acceptedAt = acceptedAt
        self.routeSummary = routeSummary?.nilIfBlank
        self.note = note?.nilIfBlank
    }

    public enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case accepted
        case queued
        case rejected
        case incompatible
        case unknown
    }

    public var indicatesOutboundProgress: Bool {
        switch status {
        case .accepted, .queued:
            return true
        case .rejected, .incompatible, .unknown:
            return false
        }
    }
}

// MARK: - Outbound delivery status

public struct ExchangeRelayDeliveryStatus: Codable, Sendable, Hashable {
    public var reference: String
    public var status: Status
    public var checkedAt: Date
    public var note: String?

    public init(
        reference: String,
        status: Status,
        checkedAt: Date = Date(),
        note: String? = nil
    ) {
        self.reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        self.status = status
        self.checkedAt = checkedAt
        self.note = note?.nilIfBlank
    }

    public enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case accepted
        case delivered
        case failed
        case unknown
    }
}

// MARK: - Delivery status (server JSON / URL helpers)

/// Maps federation `GET /v1/relay/status/:reference` payloads and related strings to client models.
public enum ExchangeRelayDeliveryStatusMapping {
    /// RFC 3986 unreserved set for a single path segment (reference is the last segment).
    private static let pathSegmentAllowed: CharacterSet = {
        var c = CharacterSet()
        c.formUnion(CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))
        return c
    }()

    public static func percentEncodedPathSegmentForStatusReference(_ reference: String) -> String {
        reference.addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowed) ?? ""
    }

    public static func mapServerStatus(_ raw: String) -> ExchangeRelayDeliveryStatus.Status {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch s {
        case "accepted", "queued":
            return .accepted
        case "delivered":
            return .delivered
        case "rejected", "failed":
            return .failed
        default:
            return .unknown
        }
    }

    /// Parses ISO8601 timestamps from relay/inbox JSON (with optional fractional seconds).
    public static func parseServerISO8601Date(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: trimmed) {
            return date
        }

        let formatterBasic = ISO8601DateFormatter()
        formatterBasic.formatOptions = [.withInternetDateTime]
        return formatterBasic.date(from: trimmed)
    }

    public static func parseCheckedAt(_ raw: String?) -> Date {
        guard let raw else { return Date() }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Date() }
        return parseServerISO8601Date(trimmed) ?? Date()
    }
}

// MARK: - Inbound sync request / response

public struct ExchangeRelayInboxSyncRequest: Codable, Sendable, Hashable {
    /// Durable relay-provided cursor.
    /// Nil means "start from current server defaults / first page".
    public var cursor: String?

    /// Optional client hint for bounded fetch.
    /// Relay may ignore or clamp this.
    public var limit: Int?

    /// Optional client node id for explicit mailbox targeting when needed.
    public var nodeID: String?

    public init(
        cursor: String? = nil,
        limit: Int? = nil,
        nodeID: String? = nil
    ) {
        self.cursor = cursor?.nilIfBlank
        self.limit = limit.map { max(1, $0) }
        self.nodeID = nodeID?.nilIfBlank
    }
}

public struct ExchangeRelayInboxSyncResponse: Codable, Sendable, Hashable {
    /// Receipts fetched in this pass.
    public var receipts: [ExchangeRelayInboundReceipt]

    /// Cursor to persist for the next sync request.
    /// Nil means "no cursor advancement available".
    public var nextCursor: String?

    /// Whether more pages likely exist immediately after this one.
    public var hasMore: Bool

    /// Server timestamp for observability / debugging.
    public var syncedAt: Date?

    /// Optional server note.
    public var note: String?

    public init(
        receipts: [ExchangeRelayInboundReceipt],
        nextCursor: String? = nil,
        hasMore: Bool = false,
        syncedAt: Date? = nil,
        note: String? = nil
    ) {
        self.receipts = receipts
        self.nextCursor = nextCursor?.nilIfBlank
        self.hasMore = hasMore
        self.syncedAt = syncedAt
        self.note = note?.nilIfBlank
    }

    public var isEmpty: Bool {
        receipts.isEmpty
    }
}

// MARK: - Inbound relay receipt

/// A relay receipt is the durable server-side delivery wrapper around an envelope.
/// This is what the sync engine fetches and later acknowledges.
public struct ExchangeRelayInboundReceipt: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var receiptID: String
    public var mailboxNodeID: String?
    public var receivedAt: Date
    public var envelope: ExchangeRelayEnvelope
    public var route: ExchangeRelayRoute?
    public var externalReference: String?
    public var status: Status
    public var compatibility: Compatibility
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        receiptID: String,
        mailboxNodeID: String? = nil,
        receivedAt: Date = Date(),
        envelope: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute? = nil,
        externalReference: String? = nil,
        status: Status = .new,
        compatibility: Compatibility = .supported,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.receiptID = receiptID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mailboxNodeID = mailboxNodeID?.nilIfBlank
        self.receivedAt = receivedAt
        self.envelope = envelope
        self.route = route
        self.externalReference = externalReference?.nilIfBlank
        self.status = status
        self.compatibility = compatibility
        self.metadata = metadata
    }

    public enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case new
        case redelivered
        case acknowledged
        case ignored
    }

    public enum Compatibility: Codable, Sendable, Hashable {
        case supported
        case unsupportedVersion(String?)
        case unsupportedPayload(String?)
        case malformed(String)

        public var isProcessable: Bool {
            if case .supported = self {
                return true
            }
            return false
        }
    }
}

// MARK: - Backward compatibility alias

/// Temporary alias so older call sites that still mention `ExchangeRelayInboundItem`
/// can be migrated cleanly without an all-at-once rename.
public typealias ExchangeRelayInboundItem = ExchangeRelayInboundReceipt

// MARK: - Acknowledgements

public struct ExchangeRelayInboxAcknowledgement: Codable, Sendable, Hashable {
    public var receiptID: String
    public var envelopeID: String?
    public var acknowledgedAt: Date
    public var result: Result
    public var note: String?

    public init(
        receiptID: String,
        envelopeID: String? = nil,
        acknowledgedAt: Date = Date(),
        result: Result = .processed,
        note: String? = nil
    ) {
        self.receiptID = receiptID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.envelopeID = envelopeID?.nilIfBlank
        self.acknowledgedAt = acknowledgedAt
        self.result = result
        self.note = note?.nilIfBlank
    }

    public enum Result: String, Codable, Sendable, CaseIterable, Hashable {
        case processed
        case ignored
        case incompatible
        case failedPermanently
    }
}

public struct ExchangeRelayInboxAcknowledgeResponse: Codable, Sendable, Hashable {
    public var acknowledgedReceiptIDs: [String]
    public var rejectedReceiptIDs: [String]
    public var updatedCount: Int
    public var note: String?

    public init(
        acknowledgedReceiptIDs: [String],
        rejectedReceiptIDs: [String] = [],
        updatedCount: Int,
        note: String? = nil
    ) {
        self.acknowledgedReceiptIDs = acknowledgedReceiptIDs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        self.rejectedReceiptIDs = rejectedReceiptIDs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        self.updatedCount = max(0, updatedCount)
        self.note = note?.nilIfBlank
    }
}

// MARK: - Errors

public enum ExchangeRelayClientError: Error, Sendable, Hashable {
    case unavailable(reason: String)
    case unauthorized(reason: String)
    case invalidEnvelope(reason: String)
    case invalidSyncRequest(reason: String)
    case rejected(reason: String)
    case incompatibleVersion(version: String?)
    case transportFailure(reason: String)
    case rateLimited(reason: String, retryAfterSeconds: Int?)
}

// MARK: - Helpers

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
