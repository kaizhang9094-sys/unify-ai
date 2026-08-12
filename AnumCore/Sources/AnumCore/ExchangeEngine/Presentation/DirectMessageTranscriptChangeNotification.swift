import Foundation

public enum DirectMessageTranscriptChangeSource: String, Sendable {
    case apnsSync
    case pollSync
    case localSend
    case inboundReconcile

    public init(syncTrigger: ExchangeSyncEngine.Trigger) {
        switch syncTrigger {
        case .silentPush:
            self = .apnsSync
        case .foregroundInboxPoll, .appBecameActive, .appLaunch, .manualRefresh:
            self = .pollSync
        default:
            self = .inboundReconcile
        }
    }
}

public struct DirectMessageTranscriptChangeEvent: Sendable, Equatable {
    public static let threadIDKey = "threadID"
    public static let counterpartyNodeIDKey = "counterpartyNodeID"
    public static let messageIDKey = "messageID"
    public static let directionKey = "direction"
    public static let sourceKey = "source"

    public let threadID: ExchangeThread.ID
    public let counterpartyNodeID: String
    public let messageID: String
    public let direction: String
    public let source: DirectMessageTranscriptChangeSource

    public var conversationKey: String { counterpartyNodeID }

    public init(
        threadID: ExchangeThread.ID,
        counterpartyNodeID: String,
        messageID: String,
        direction: String,
        source: DirectMessageTranscriptChangeSource
    ) {
        self.threadID = threadID
        self.counterpartyNodeID = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.messageID = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.direction = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
    }

    public init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo else { return nil }
        guard let threadRaw = userInfo[Self.threadIDKey] as? String,
              let threadID = UUID(uuidString: threadRaw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }

        let counterpartyNodeID = (userInfo[Self.counterpartyNodeIDKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let messageID = (userInfo[Self.messageIDKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let direction = (userInfo[Self.directionKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sourceRaw = (userInfo[Self.sourceKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = DirectMessageTranscriptChangeSource(rawValue: sourceRaw) ?? .inboundReconcile

        guard !counterpartyNodeID.isEmpty, !messageID.isEmpty else { return nil }

        self.init(
            threadID: threadID,
            counterpartyNodeID: counterpartyNodeID,
            messageID: messageID,
            direction: direction,
            source: source
        )
    }

    public var userInfo: [String: String] {
        [
            Self.threadIDKey: threadID.uuidString,
            Self.counterpartyNodeIDKey: counterpartyNodeID,
            Self.messageIDKey: messageID,
            Self.directionKey: direction,
            Self.sourceKey: source.rawValue
        ]
    }
}

public extension Notification.Name {
    static let directMessageTranscriptDidChange = Notification.Name("directMessageTranscriptDidChange")
}

public enum DirectMessageTranscriptChangeNotification {
    @MainActor
    public static func post(_ event: DirectMessageTranscriptChangeEvent) {
        print(
            "[DMTranscript][changeEvent] conversationKey=\(event.conversationKey) " +
            "messageID=\(event.messageID) source=\(event.source.rawValue)"
        )
        NotificationCenter.default.post(
            name: .directMessageTranscriptDidChange,
            object: nil,
            userInfo: event.userInfo
        )
    }

    public static func logStoreWrite(_ event: DirectMessageTranscriptChangeEvent) {
        print(
            "[DMTranscript][storeWrite] conversationKey=\(event.conversationKey) " +
            "messageID=\(event.messageID) direction=\(event.direction) source=\(event.source.rawValue)"
        )
    }
}
