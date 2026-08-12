import Foundation

enum ForYouPassFailureKind: String, Sendable {
    case needsMoreSpecificFocus
    case invalidRequest
    case networkOrServer
}

struct ForYouPassFailure: Equatable, Sendable {
    let kind: ForYouPassFailureKind
    let message: String
    let occurredAt: Date
}
