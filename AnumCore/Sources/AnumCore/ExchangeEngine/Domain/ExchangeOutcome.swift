import Foundation

/// Durable outcome record for a coordination thread.
///
/// This is richer than the lightweight thread snapshot.
/// It preserves what ultimately happened, what did not happen, whether anything
/// changed externally, and what the final recommendation or closure was.
///
/// Outcome is for durable legible closure, not live in-flight phase tracking.
public struct ExchangeOutcome: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var threadID: ExchangeThread.ID
    public var createdAt: Date

    public var status: Status
    public var category: Category

    /// Human-readable outcome summary.
    public var summary: String

    /// Explicit statement of what happened.
    public var whatHappened: String

    /// Explicit statement of what did not happen.
    public var whatDidNotHappen: String

    /// Whether anything changed externally.
    public var externalEffect: ExternalEffect

    /// Optional final recommendation or closure note.
    public var recommendedNextStep: String?

    /// Optional linked failure if the outcome was failure-shaped.
    public var failureID: ExchangeFailure.ID?

    /// Optional extensibility bag for non-canonical annotations.
    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        threadID: ExchangeThread.ID,
        createdAt: Date = Date(),
        status: Status,
        category: Category,
        summary: String,
        whatHappened: String,
        whatDidNotHappen: String,
        externalEffect: ExternalEffect = .none,
        recommendedNextStep: String? = nil,
        failureID: ExchangeFailure.ID? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.threadID = threadID
        self.createdAt = createdAt
        self.status = status
        self.category = category
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.whatHappened = whatHappened.trimmingCharacters(in: .whitespacesAndNewlines)
        self.whatDidNotHappen = Self.normalizeNonAction(whatDidNotHappen)
        self.externalEffect = externalEffect
        self.recommendedNextStep = recommendedNextStep?.nilIfBlank
        self.failureID = failureID
        self.metadata = metadata
    }
}

public extension ExchangeOutcome {
    /// Durable closure or legible end-shape for a thread.
    enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case noViableMatch
        case declined
        case stalled
        case resolved
        case failedLegibly
    }

    enum Category: String, Codable, Sendable, CaseIterable, Hashable {
        case success
        case failure
        case mixed
        case informational
    }

    enum ExternalEffect: Codable, Sendable, Hashable {
        case none
        case contactAttempted
        case messageSent(reference: String?)
        case coordinationOccurred
        case other(description: String)

        public var summaryLine: String {
            switch self {
            case .none:
                return "No external change occurred."
            case .contactAttempted:
                return "External contact may have been attempted."
            case .messageSent(let reference):
                if let reference, !reference.isEmpty {
                    return "A message was sent externally. Reference: \(reference)."
                }
                return "A message was sent externally."
            case .coordinationOccurred:
                return "External coordination occurred."
            case .other(let description):
                return description
            }
        }

        public var changedAnythingExternally: Bool {
            switch self {
            case .none:
                return false
            case .contactAttempted, .messageSent, .coordinationOccurred, .other:
                return true
            }
        }
    }
}

public extension ExchangeOutcome {
    var isTerminal: Bool {
        true
    }

    var isFailureShaped: Bool {
        switch category {
        case .failure:
            return true
        case .success, .mixed, .informational:
            return false
        }
    }

    var visibleExplanation: String {
        """
        \(summary)

        What happened: \(whatHappened)
        What did not happen: \(whatDidNotHappen)
        External status: \(externalEffect.summaryLine)
        \(recommendedNextStep.map { "Next step: \($0)" } ?? "Next step: None.")
        """
    }

    static func resolved(
        threadID: ExchangeThread.ID,
        summary: String,
        whatHappened: String,
        whatDidNotHappen: String,
        externalEffect: ExternalEffect = .coordinationOccurred,
        recommendedNextStep: String? = nil
    ) -> ExchangeOutcome {
        ExchangeOutcome(
            threadID: threadID,
            status: .resolved,
            category: .success,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: whatDidNotHappen,
            externalEffect: externalEffect,
            recommendedNextStep: recommendedNextStep
        )
    }

    static func noViableMatch(
        threadID: ExchangeThread.ID,
        summary: String,
        whatHappened: String,
        recommendedNextStep: String? = nil,
        failureID: ExchangeFailure.ID? = nil
    ) -> ExchangeOutcome {
        ExchangeOutcome(
            threadID: threadID,
            status: .noViableMatch,
            category: .failure,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: "No contact was made with a suitable counterparty.",
            externalEffect: .none,
            recommendedNextStep: recommendedNextStep,
            failureID: failureID
        )
    }

    static func declined(
        threadID: ExchangeThread.ID,
        summary: String,
        whatHappened: String,
        recommendedNextStep: String? = nil,
        failureID: ExchangeFailure.ID? = nil
    ) -> ExchangeOutcome {
        ExchangeOutcome(
            threadID: threadID,
            status: .declined,
            category: .failure,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: "The thread did not proceed to alignment.",
            externalEffect: .coordinationOccurred,
            recommendedNextStep: recommendedNextStep,
            failureID: failureID
        )
    }

    static func stalled(
        threadID: ExchangeThread.ID,
        summary: String,
        whatHappened: String,
        recommendedNextStep: String? = nil,
        failureID: ExchangeFailure.ID? = nil
    ) -> ExchangeOutcome {
        ExchangeOutcome(
            threadID: threadID,
            status: .stalled,
            category: .failure,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: "The thread did not progress to a meaningful next step.",
            externalEffect: .coordinationOccurred,
            recommendedNextStep: recommendedNextStep,
            failureID: failureID
        )
    }

    static func failedLegibly(
        threadID: ExchangeThread.ID,
        summary: String,
        whatHappened: String,
        whatDidNotHappen: String,
        externalEffect: ExternalEffect = .none,
        recommendedNextStep: String? = nil,
        failureID: ExchangeFailure.ID? = nil
    ) -> ExchangeOutcome {
        ExchangeOutcome(
            threadID: threadID,
            status: .failedLegibly,
            category: .failure,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: whatDidNotHappen,
            externalEffect: externalEffect,
            recommendedNextStep: recommendedNextStep,
            failureID: failureID
        )
    }

    private static func normalizeNonAction(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No further action was completed." : trimmed
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
