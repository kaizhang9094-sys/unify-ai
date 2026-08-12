import Foundation

public enum ExchangeCommitmentBoundaryKind: String, Codable, CaseIterable, Hashable, Sendable {
    case safe
    case sensitiveDisclosure
    case obligationBearing
    case commitmentBearing
    case policyException
    case customPricing
    case scheduleCommitment
    case legalCommercialCommitment
}

/// Represents whether a move is safe or commitment-bearing.
///
/// This is the canonical classification object for escalation logic.
public struct ExchangeCommitmentBoundary: Codable, Hashable, Sendable {
    public var kind: ExchangeCommitmentBoundaryKind
    public var reason: String
    public var requiresHumanApproval: Bool
    public var allowsAutonomousDrafting: Bool
    public var allowsAutonomousSending: Bool

    public init(
        kind: ExchangeCommitmentBoundaryKind,
        reason: String,
        requiresHumanApproval: Bool,
        allowsAutonomousDrafting: Bool,
        allowsAutonomousSending: Bool
    ) {
        self.kind = kind
        self.reason = reason
        self.requiresHumanApproval = requiresHumanApproval
        self.allowsAutonomousDrafting = allowsAutonomousDrafting
        self.allowsAutonomousSending = allowsAutonomousSending
    }
}

public extension ExchangeCommitmentBoundary {
    static let safe = ExchangeCommitmentBoundary(
        kind: .safe,
        reason: "Routine non-binding coordination.",
        requiresHumanApproval: false,
        allowsAutonomousDrafting: true,
        allowsAutonomousSending: true
    )

    static func sensitiveDisclosure(reason: String) -> ExchangeCommitmentBoundary {
        ExchangeCommitmentBoundary(
            kind: .sensitiveDisclosure,
            reason: reason,
            requiresHumanApproval: true,
            allowsAutonomousDrafting: true,
            allowsAutonomousSending: false
        )
    }

    static func obligationBearing(reason: String) -> ExchangeCommitmentBoundary {
        ExchangeCommitmentBoundary(
            kind: .obligationBearing,
            reason: reason,
            requiresHumanApproval: true,
            allowsAutonomousDrafting: true,
            allowsAutonomousSending: false
        )
    }

    static func commitmentBearing(reason: String) -> ExchangeCommitmentBoundary {
        ExchangeCommitmentBoundary(
            kind: .commitmentBearing,
            reason: reason,
            requiresHumanApproval: true,
            allowsAutonomousDrafting: true,
            allowsAutonomousSending: false
        )
    }

    static func policyException(reason: String) -> ExchangeCommitmentBoundary {
        ExchangeCommitmentBoundary(
            kind: .policyException,
            reason: reason,
            requiresHumanApproval: true,
            allowsAutonomousDrafting: true,
            allowsAutonomousSending: false
        )
    }

    static func customPricing(reason: String) -> ExchangeCommitmentBoundary {
        ExchangeCommitmentBoundary(
            kind: .customPricing,
            reason: reason,
            requiresHumanApproval: true,
            allowsAutonomousDrafting: true,
            allowsAutonomousSending: false
        )
    }

    static func scheduleCommitment(reason: String) -> ExchangeCommitmentBoundary {
        ExchangeCommitmentBoundary(
            kind: .scheduleCommitment,
            reason: reason,
            requiresHumanApproval: true,
            allowsAutonomousDrafting: true,
            allowsAutonomousSending: false
        )
    }

    static func legalCommercialCommitment(reason: String) -> ExchangeCommitmentBoundary {
        ExchangeCommitmentBoundary(
            kind: .legalCommercialCommitment,
            reason: reason,
            requiresHumanApproval: true,
            allowsAutonomousDrafting: true,
            allowsAutonomousSending: false
        )
    }
}
