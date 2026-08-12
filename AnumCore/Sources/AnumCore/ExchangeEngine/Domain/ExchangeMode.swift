import Foundation

/// The high-level coordination family for an exchange request.
///
/// Keep this intentionally small and durable.
/// It describes the social shape of coordination, not workflow state,
/// transport state, approval state, or UI presentation.
public enum ExchangeMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// Goal-oriented coordination with concrete deliverables or decisions.
    ///
    /// Examples:
    /// - request a quote
    /// - find a supplier
    /// - book a service
    case transactional

    /// Multi-party or mutual-progress coordination where alignment,
    /// planning, or shared execution matter.
    ///
    /// Examples:
    /// - coordinate a project conversation
    /// - arrange a collaboration
    /// - plan an event
    case cooperative

    /// Human connection or social coordination where tone, chemistry,
    /// trust, and pacing matter more than immediate execution.
    ///
    /// Examples:
    /// - request an introduction
    /// - start a social thread
    /// - coordinate a date or meetup
    case relational
}

public extension ExchangeMode {
    var title: String {
        switch self {
        case .transactional:
            return "Transactional"
        case .cooperative:
            return "Cooperative"
        case .relational:
            return "Relational"
        }
    }

    var summary: String {
        switch self {
        case .transactional:
            return "Concrete coordination toward a defined outcome."
        case .cooperative:
            return "Shared coordination where mutual alignment is central."
        case .relational:
            return "Connection-oriented coordination shaped by trust and tone."
        }
    }

    /// Whether this mode typically benefits from more tone sensitivity
    /// and slower pacing in drafting and reply handling.
    var isToneSensitive: Bool {
        switch self {
        case .transactional:
            return false
        case .cooperative, .relational:
            return true
        }
    }
}
