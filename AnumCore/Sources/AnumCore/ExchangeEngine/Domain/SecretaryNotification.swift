import Foundation

/// User-facing Secretary attention item stored locally (not OS push).
public enum SecretaryNotificationKind: String, Codable, Sendable, CaseIterable, Hashable {
    case newReply
    case needsAnswer
    case needsApproval
    case sendFailed
    case matchReady
    case recoveryNeeded
    case trustedContactAdded
    case messageSent
    /// Discovery / For You surfaced new suggestions (SQLite-backed UI notification).
    case discoveryMatch
    /// Seller surface publishing or validation regression (SQLite-backed UI notification).
    case publicationIssue
    /// Inbox growth after sync — no stable per-thread envelope id yet (SQLite-backed summary).
    case inboundDigest
    /// Pending approval count rose (SQLite-backed digest; granular approval rows still come from hooks).
    case approvalDigest
}

extension SecretaryNotificationKind {
    /// Excluded from the global Updates sheet and bell unread projection (legacy rows may remain in SQLite).
    /// `.messageSent` is excluded because it is not actionable inbound-style work for the Updates bell.
    public static let globalBellAndFeedExcludedKinds: Set<SecretaryNotificationKind> = [.inboundDigest, .messageSent]

    /// Inbound tab badge and row messaging attention (incoming only).
    public static let inboundMessagingUnreadSurface: Set<SecretaryNotificationKind> = [
        .newReply,
        .needsAnswer
    ]

    /// Messaging kinds that must not contribute to Trusted contact-row unread.
    public static let trustedUnreadExcludedMessagingKinds: Set<SecretaryNotificationKind> = [
        .newReply,
        .messageSent,
        .needsAnswer,
        .inboundDigest
    ]
}

public enum SecretaryNotificationPriority: String, Codable, Sendable, Hashable {
    case normal
    case low
}

/// Stable dedupe identities for SQLite `ON CONFLICT(dedupe_key)`.
public enum SecretaryNotificationDedupeKey: Sendable {
    public static func newReply(threadID: ExchangeThread.ID, envelopeID: String) -> String {
        let e = envelopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.isEmpty {
            return "newReply:\(threadID.uuidString):unknown"
        }
        return "newReply:\(threadID.uuidString):\(e)"
    }

    /// Dedupes counterparty `replyReceived` attention when no stable envelope id is available yet.
    public static func newReplyTurn(threadID: ExchangeThread.ID, turnID: ExchangeTurn.ID) -> String {
        "newReply:\(threadID.uuidString):turn:\(turnID.uuidString)"
    }

    /// Last-resort dedupe for a thread when neither envelope id nor turn id is available to the caller.
    public static func newReplyTimeFallback(threadID: ExchangeThread.ID, millis: Int) -> String {
        "newReply:\(threadID.uuidString):ts:\(millis)"
    }

    /// Fallback when thread id is unknown but a counterparty node id is stable.
    public static func newReplyNode(nodeID: String, envelopeIDOrTimeKey: String) -> String {
        let n = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = envelopeIDOrTimeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeNode = n.isEmpty ? "unknown" : n
        let safeSuffix = s.isEmpty ? "unknown" : s
        return "newReplyNode:\(safeNode):\(safeSuffix)"
    }

    public static func needsAnswer(threadID: ExchangeThread.ID, clarificationTurnID: ExchangeTurn.ID) -> String {
        "needsAnswer:\(threadID.uuidString):\(clarificationTurnID.uuidString)"
    }

    public static func needsApproval(approvalID: ExchangeApproval.ID) -> String {
        "needsApproval:\(approvalID.uuidString)"
    }

    public static func sendFailed(threadID: ExchangeThread.ID, outboxItemID: ExchangeOutboxItem.ID) -> String {
        "sendFailed:\(threadID.uuidString):\(outboxItemID.uuidString)"
    }

    public static func recoveryNeeded(threadID: ExchangeThread.ID, failureID: ExchangeFailure.ID) -> String {
        "recoveryNeeded:\(threadID.uuidString):\(failureID.uuidString)"
    }

    public static func matchReady(threadID: ExchangeThread.ID) -> String {
        "matchReady:\(threadID.uuidString)"
    }

    public static func trustedContactAdded(nodeID: String) -> String {
        let trimmed = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        return "trustedContactAdded:\(trimmed)"
    }

    public static func messageSent(threadID: ExchangeThread.ID, turnID: ExchangeTurn.ID) -> String {
        "messageSent:\(threadID.uuidString):\(turnID.uuidString)"
    }

    /// Fingerprint of the surfaced For You set (IDs sorted and joined).
    public static func discoveryMatchFingerprint(_ fingerprint: String) -> String {
        let trimmed = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        return "discoveryMatch:\(trimmed)"
    }

    public static func publicationIssueFingerprint(_ fingerprint: String) -> String {
        let trimmed = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        return "publicationIssue:\(trimmed)"
    }

    /// Stable per-node identity for seller / public-surface validation attention (issue payload lives in metadata).
    public static func publicationIssueSellerSurface(nodeID: String) -> String {
        let trimmed = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        return "publicationIssue:sellerSurface:\(trimmed)"
    }

    /// Coarse time bucket (~10 minutes) for digest dedupe windows.
    public static func inboundDigestBucket(_ epochSeconds: TimeInterval) -> String {
        let bucket = Int(floor(epochSeconds / 600.0))
        return "inboundDigestBucket:\(bucket)"
    }

    public static func approvalDigestSnapshot(count: Int) -> String {
        "approvalDigestSnapshot:\(count)"
    }
}

public struct SecretaryNotification: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var createdAt: Date
    public var updatedAt: Date

    public var kind: SecretaryNotificationKind
    /// Unique across rows; UPSERT merges on conflict.
    public var dedupeKey: String

    public var isRead: Bool
    public var priority: SecretaryNotificationPriority

    public var title: String
    public var body: String

    public var threadID: ExchangeThread.ID?
    public var approvalID: ExchangeApproval.ID?
    public var failureID: ExchangeFailure.ID?
    public var turnID: ExchangeTurn.ID?
    public var trustedNodeID: String?

    /// Routing / telemetry only — never displayed verbatim in UI.
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        kind: SecretaryNotificationKind,
        dedupeKey: String,
        isRead: Bool = false,
        priority: SecretaryNotificationPriority = .normal,
        title: String,
        body: String,
        threadID: ExchangeThread.ID? = nil,
        approvalID: ExchangeApproval.ID? = nil,
        failureID: ExchangeFailure.ID? = nil,
        turnID: ExchangeTurn.ID? = nil,
        trustedNodeID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.kind = kind
        self.dedupeKey = dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isRead = isRead
        self.priority = priority
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.threadID = threadID
        self.approvalID = approvalID
        self.failureID = failureID
        self.turnID = turnID
        self.trustedNodeID = trustedNodeID
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        self.metadata = metadata
    }
}

extension SecretaryNotification {
    /// Stable identity for deduping inbound messaging attention (.newReply, .needsAnswer) across UI surfaces.
    public var inboundMessagingAttentionKey: String {
        if let tid = threadID {
            return "thread:\(tid.uuidString.lowercased())"
        }
        if let nid = trustedNodeID, !nid.isEmpty {
            return "node:\(nid.lowercased())"
        }
        return "dedupe:\(dedupeKey)"
    }

    /// Stable key for collapsing duplicate unread attention rows in the global Updates / bell projection.
    public static func globalUnreadBellDistinctKey(for notification: SecretaryNotification) -> String {
        switch notification.kind {
        case .newReply, .needsAnswer:
            return "\(notification.kind.rawValue):\(notification.inboundMessagingAttentionKey)"
        case .matchReady:
            return "matchReady:\(notification.dedupeKey)"
        case .publicationIssue:
            return "publicationIssue:\(notification.dedupeKey)"
        default:
            return "\(notification.kind.rawValue):\(notification.dedupeKey)"
        }
    }

    /// One visible row per distinct attention surface (new reply / needs answer / match / publication), newest first.
    public static func collapseGlobalUnreadForDistinctAttention(
        _ rows: [SecretaryNotification]
    ) -> [SecretaryNotification] {
        let sorted = rows.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var seen = Set<String>()
        var out: [SecretaryNotification] = []
        for n in sorted {
            let collapsible: Bool = {
                switch n.kind {
                case .newReply, .needsAnswer, .matchReady, .publicationIssue:
                    return true
                default:
                    return false
                }
            }()
            if collapsible {
                let key = globalUnreadBellDistinctKey(for: n)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
            }
            out.append(n)
        }
        return out
    }
}

/// User-facing scrub for secretary notification titles/bodies/peek lines (not full transcripts).
public enum SecretaryNotificationCopySanitizer: Sendable {
    /// Returned when internal/system vocabulary is stripped.
    public static let neutralFallback = "Something needs your attention."

    /// Short, single-line-ish copy suitable for badges and sheets.
    public static func sanitizeSentence(_ raw: String, maxLength: Int = 200) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return neutralFallback }

        guard !shouldNeutralize(collapsed) else { return neutralFallback }

        guard collapsed.count <= maxLength else {
            let end = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
            return String(collapsed[..<end]) + "…"
        }

        return collapsed
    }

    private static func shouldNeutralize(_ text: String) -> Bool {
        if text.range(
            of: #"second(?:[\s_-]+half|_half)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        // Whole-word match avoids scrubbing benign substrings (e.g. “permutation”) for `mutation`.
        if text.range(
            of: #"\b(?:relay|execution|trace|agency|mutation|pipeline|outbox|metadata|envelope|envelopes|autonomous)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        return false
    }
}
