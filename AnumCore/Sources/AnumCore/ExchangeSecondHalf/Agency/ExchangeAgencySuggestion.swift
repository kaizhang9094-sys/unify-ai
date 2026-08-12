import Foundation

/// Planner output: read-only deterministic suggestions for agency UI (Pass 3).
///
/// Execution is **not** performed here — callers own approval/send paths.
public struct ExchangeAgencySuggestion: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case wait
        case askUserClarification
        case askCounterpartyClarification
        case draftRequesterOutreach
        case draftProviderReply
        case reviewApproval
        case sendIfSafe
        case recoverFailure
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var summary: String
    public var requiresUserApproval: Bool
    public var canRunAutonomously: Bool
    public var riskLevel: String
    public var reasons: [String]

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        title: String,
        summary: String,
        requiresUserApproval: Bool,
        canRunAutonomously: Bool,
        riskLevel: String,
        reasons: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.requiresUserApproval = requiresUserApproval
        self.canRunAutonomously = canRunAutonomously
        self.riskLevel = riskLevel
        self.reasons = reasons
    }
}
