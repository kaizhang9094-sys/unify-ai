import Foundation

public struct TurnInput: Sendable {
    public let userText: String
    public let timestamp: Date

    public init(userText: String, timestamp: Date = Date()) {
        self.userText = userText
        self.timestamp = timestamp
    }
}

public struct TurnOutput: Sendable {
    public let assistantText: String
    public let traceId: String

    public init(assistantText: String, traceId: String) {
        self.assistantText = assistantText
        self.traceId = traceId
    }
}
