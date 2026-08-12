import Foundation

/// A durable event within a coordination thread.
///
/// Turns are not generic chat messages. They are meaningful coordination events
/// that explain how a thread progressed, paused, failed, or resolved.
///
/// Keep turns append-only in normal operation. Corrections should generally be
/// represented by later turns, not by mutating old ones.
public struct ExchangeTurn: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var threadID: ExchangeThread.ID
    public var createdAt: Date
    public var actor: Actor
    public var kind: Kind

    /// Compact human-readable summary suitable for logs, inbox previews,
    /// and thread timelines.
    public var summary: String

    /// Optional detailed body for richer UI or debugging.
    public var detail: String?

    /// Visibility markers for this turn.
    public var visibility: ExchangeVisibility

    /// Optional external reference attached to the turn.
    /// Example: remote message id, envelope id, relay id.
    public var externalReference: String?

    /// Optional failure attached to this turn when the turn represents
    /// a legible failure event.
    public var failure: ExchangeFailure?

    /// Small future-safe metadata. Do not store large payloads here.
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        threadID: ExchangeThread.ID,
        createdAt: Date = Date(),
        actor: Actor,
        kind: Kind,
        summary: String,
        detail: String? = nil,
        visibility: ExchangeVisibility = .default,
        externalReference: String? = nil,
        failure: ExchangeFailure? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.threadID = threadID
        self.createdAt = createdAt
        self.actor = actor
        self.kind = kind
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail?.nilIfBlank
        self.visibility = visibility
        self.externalReference = externalReference?.nilIfBlank
        self.failure = failure
        self.metadata = metadata
    }
}

public extension ExchangeTurn {
    enum Actor: String, Codable, Sendable, CaseIterable, Hashable {
        case user
        case secretary
        case system
        case counterparty
        case relay
    }

    /// Keep kinds legible and product-meaningful.
    /// Avoid low-level transport noise and avoid near-duplicate event names.
    enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
        case requestCaptured
        case clarificationAsked
        case clarificationAnswered

        case searchStarted
        case searchCompleted
        case weakMatchesObserved
        case noViableMatchObserved
        case candidateSelected

        case draftPrepared

        case approvalRequested
        case approvalGranted
        case approvalRejected
        case approvalExpired

        case sendAttempted
        case sendConfirmed
        case deliveryFailed

        case replyReceived
        case followUpSuggested
        case threadStalled
        case threadDeclined
        case threadResolved

        case negotiationAdvanced
        case negotiationFailed

        case systemNotice
        case systemError
    }
}

public extension ExchangeTurn {
    var isFailureTurn: Bool {
        failure != nil || kind.isFailureLike
    }

    var isUserVisibleFailureTurn: Bool {
        isFailureTurn && visibility.isVisibleToUserByDefault
    }

    static func requestCaptured(
        threadID: ExchangeThread.ID,
        summary: String,
        detail: String? = nil,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .user,
            kind: .requestCaptured,
            summary: summary,
            detail: detail,
            visibility: .default
        )
    }

    static func clarificationAsked(
        threadID: ExchangeThread.ID,
        question: String,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .secretary,
            kind: .clarificationAsked,
            summary: question,
            visibility: .default
        )
    }

    static func weakMatchesObserved(
        threadID: ExchangeThread.ID,
        summary: String,
        detail: String? = nil,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .system,
            kind: .weakMatchesObserved,
            summary: summary,
            detail: detail,
            visibility: .default
        )
    }

    static func noViableMatchObserved(
        threadID: ExchangeThread.ID,
        summary: String,
        detail: String? = nil,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .system,
            kind: .noViableMatchObserved,
            summary: summary,
            detail: detail,
            visibility: .default
        )
    }

    static func candidateSelected(
        threadID: ExchangeThread.ID,
        summary: String,
        detail: String? = nil,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .system,
            kind: .candidateSelected,
            summary: summary,
            detail: detail,
            visibility: .userVisible
        )
    }

    static func draftPrepared(
        threadID: ExchangeThread.ID,
        summary: String = "Draft prepared.",
        detail: String? = nil,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .secretary,
            kind: .draftPrepared,
            summary: summary,
            detail: detail,
            visibility: .default
        )
    }

    static func approvalRequested(
        threadID: ExchangeThread.ID,
        summary: String,
        detail: String? = nil,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .secretary,
            kind: .approvalRequested,
            summary: summary,
            detail: detail,
            visibility: [.userVisible, .approvalRequired]
        )
    }

    static func sendConfirmed(
        threadID: ExchangeThread.ID,
        summary: String,
        externalReference: String? = nil,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .relay,
            kind: .sendConfirmed,
            summary: summary,
            visibility: [.userVisible, .externallyConfirmed],
            externalReference: externalReference
        )
    }

    static func deliveryFailed(
        threadID: ExchangeThread.ID,
        failure: ExchangeFailure,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .system,
            kind: .deliveryFailed,
            summary: failure.summary,
            detail: failure.visibleExplanation,
            visibility: [.userVisible, .failureVisible],
            failure: failure
        )
    }

    static func systemError(
        threadID: ExchangeThread.ID,
        failure: ExchangeFailure,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .system,
            kind: .systemError,
            summary: failure.summary,
            detail: failure.visibleExplanation,
            visibility: [.userVisible, .failureVisible],
            failure: failure
        )
    }
}

public extension ExchangeTurn.Kind {
    var isFailureLike: Bool {
        switch self {
        case .weakMatchesObserved,
             .noViableMatchObserved,
             .deliveryFailed,
             .threadStalled,
             .threadDeclined,
             .negotiationFailed,
             .systemError:
            return true

        case .requestCaptured,
             .clarificationAsked,
             .clarificationAnswered,
             .searchStarted,
             .searchCompleted,
             .candidateSelected,
             .draftPrepared,
             .approvalRequested,
             .approvalGranted,
             .approvalRejected,
             .approvalExpired,
             .sendAttempted,
             .sendConfirmed,
             .replyReceived,
             .followUpSuggested,
             .threadResolved,
             .negotiationAdvanced,
             .systemNotice:
            return false
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public extension ExchangeTurn {
    static func clarificationAnswered(
        threadID: ExchangeThread.ID,
        answer: String,
        createdAt: Date = Date()
    ) -> ExchangeTurn {
        ExchangeTurn(
            threadID: threadID,
            createdAt: createdAt,
            actor: .user,
            kind: .clarificationAnswered,
            summary: answer,
            visibility: .default
        )
    }
}
