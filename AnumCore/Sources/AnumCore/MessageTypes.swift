import Foundation

public struct ChatMessage: Identifiable, Sendable, Equatable {
    public enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    public let id: UUID
    public let role: Role
    public var text: String
    public let timestamp: Date

    public init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}
