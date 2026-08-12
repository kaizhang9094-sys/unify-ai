import Foundation

public struct DirectReplySelectedMove: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case acceptAndAskTime
        case answerStatusWithNextStep
        case reassure
        case choosePreference
        case acknowledgeAndContinue
        case closeWarmly
        case askClarifyingQuestion
        case redirect
        case hold
        case unknown
    }

    public var kind: Kind
    public var reason: String
    public var constraints: [String]
    public var requiresCaution: Bool

    public init(
        kind: Kind,
        reason: String,
        constraints: [String],
        requiresCaution: Bool = false
    ) {
        self.kind = kind
        self.reason = reason
        self.constraints = constraints
        self.requiresCaution = requiresCaution
    }
}
