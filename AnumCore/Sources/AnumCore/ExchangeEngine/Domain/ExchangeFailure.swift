import Foundation

/// A first-class, user-legible representation of coordination failure.
///
/// Exchange failure is not a generic technical error bucket.
/// It must preserve trust by making failure visible and actionable.
///
/// Every failure should answer:
/// - what happened
/// - what did not happen
/// - whether anything changed externally
/// - what the next best move is
public struct ExchangeFailure: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var kind: Kind
    public var severity: Severity

    /// Human-readable explanation of the failure.
    ///
    /// Example:
    /// "I understood the request, but I could not find any strong local matches."
    public var summary: String

    /// A more specific description of what happened.
    public var whatHappened: String

    /// Explicit statement of what did NOT happen.
    ///
    /// Example:
    /// "No message was sent."
    public var whatDidNotHappen: String

    /// Whether anything changed outside the local app/system boundary.
    public var externalEffect: ExternalEffect

    /// Recommended next move after this failure.
    public var recommendedNextStep: NextStep

    /// Optional machine-friendly reason code for stable logic and analysis.
    public var reasonCode: String?

    /// Optional underlying system detail. This is not always shown to the user.
    public var technicalDetails: String?

    /// Time the failure was created.
    public var createdAt: Date

    /// Whether the failure may succeed later without changing the request.
    public var isRetryable: Bool

    public init(
        id: ID = UUID(),
        kind: Kind,
        severity: Severity = .normal,
        summary: String,
        whatHappened: String,
        whatDidNotHappen: String,
        externalEffect: ExternalEffect = .none,
        recommendedNextStep: NextStep,
        reasonCode: String? = nil,
        technicalDetails: String? = nil,
        createdAt: Date = Date(),
        isRetryable: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.summary = Self.normalizeRequired(summary, fallback: "An exchange failure occurred.")
        self.whatHappened = Self.normalizeRequired(
            whatHappened,
            fallback: "The request could not be completed as intended."
        )
        self.whatDidNotHappen = Self.normalizeNonAction(whatDidNotHappen)
        self.externalEffect = externalEffect
        self.recommendedNextStep = recommendedNextStep
        self.reasonCode = reasonCode?.nilIfBlank
        self.technicalDetails = technicalDetails?.nilIfBlank
        self.createdAt = createdAt
        self.isRetryable = isRetryable
    }

    /// Common failure families in the exchange doctrine.
    public enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
        case understandingFailure
        case discoveryFailure
        case fitFailure
        case deliveryFailure
        case negotiationFailure
        case systemFailure
    }

    public enum Severity: String, Codable, Sendable, CaseIterable, Hashable {
        case low
        case normal
        case high
        case critical
    }

    /// Explicit boundary statement for trust.
    public enum ExternalEffect: Codable, Sendable, Hashable {
        case none
        case attemptedButNotConfirmed
        case sent(messageID: String?)
        case partiallyChanged(description: String)
        case changed(description: String)

        public var changedAnythingExternally: Bool {
            switch self {
            case .none:
                return false
            case .attemptedButNotConfirmed, .sent, .partiallyChanged, .changed:
                return true
            }
        }

        public var summaryLine: String {
            switch self {
            case .none:
                return "No external change occurred."
            case .attemptedButNotConfirmed:
                return "An external action may have been attempted, but confirmation is unavailable."
            case .sent(let messageID):
                if let messageID, !messageID.isEmpty {
                    return "An outbound action was sent. Reference: \(messageID)."
                }
                return "An outbound action was sent."
            case .partiallyChanged(let description):
                let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "An external action partially changed state." : text
            case .changed(let description):
                let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "An external change occurred." : text
            }
        }
    }

    /// Recommended next move after a failure.
    ///
    /// Keep this focused on failure recovery and visible next steps.
    /// Do not let it turn into a parallel workflow state machine.
    public enum NextStep: Codable, Sendable, Hashable {
        case clarify(question: String)
        case refineSearch(suggestion: String)
        case widenSearch(suggestion: String)
        case waitAndRetry(after: RetryWindow?)
        case reviewDraft
        case reviewCandidates
        case reviewMismatch(reason: String)
        case retryDelivery
        case considerFollowUp
        case closeThread(reason: String)
        case seekRecovery
        case manualIntervention(note: String)
        case none

        public var userFacingTitle: String {
            switch self {
            case .clarify:
                return "Clarify"
            case .refineSearch:
                return "Refine Search"
            case .widenSearch:
                return "Widen Search"
            case .waitAndRetry:
                return "Wait and Retry"
            case .reviewDraft:
                return "Review Draft"
            case .reviewCandidates:
                return "Review Candidates"
            case .reviewMismatch:
                return "Review Mismatch"
            case .retryDelivery:
                return "Retry Delivery"
            case .considerFollowUp:
                return "Consider Follow-Up"
            case .closeThread:
                return "Close Thread"
            case .seekRecovery:
                return "Recover"
            case .manualIntervention:
                return "Manual Intervention"
            case .none:
                return "No Action"
            }
        }

        public var summaryLine: String {
            switch self {
            case .clarify(let question):
                let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Clarify the missing details." : text
            case .refineSearch(let suggestion):
                let text = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Refine the search criteria." : text
            case .widenSearch(let suggestion):
                let text = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Widen the search scope." : text
            case .waitAndRetry(let after):
                if let after {
                    return "Wait and retry \(after.description)."
                }
                return "Wait and retry later."
            case .reviewDraft:
                return "Review the current draft before proceeding."
            case .reviewCandidates:
                return "Review the current candidates."
            case .reviewMismatch(let reason):
                let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Review why the current matches are not strong enough." : text
            case .retryDelivery:
                return "Retry delivery."
            case .considerFollowUp:
                return "Consider sending a follow-up."
            case .closeThread(let reason):
                let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Close the thread." : text
            case .seekRecovery:
                return "A recovery step is needed before progress can continue."
            case .manualIntervention(let note):
                let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Manual intervention is needed." : text
            case .none:
                return "No further action recommended."
            }
        }
    }

    public enum RetryWindow: String, Codable, Sendable, CaseIterable, Hashable {
        case soon
        case laterToday
        case tomorrow
        case thisWeek

        public var description: String {
            switch self {
            case .soon:
                return "soon"
            case .laterToday:
                return "later today"
            case .tomorrow:
                return "tomorrow"
            case .thisWeek:
                return "this week"
            }
        }
    }
}

public extension ExchangeFailure {
    var isUserCorrectable: Bool {
        switch kind {
        case .understandingFailure, .discoveryFailure, .fitFailure:
            return true
        case .deliveryFailure, .negotiationFailure, .systemFailure:
            return false
        }
    }

    var requiresExplicitUserVisibility: Bool {
        true
    }

    var visibleExplanation: String {
        """
        \(summary)

        What happened: \(whatHappened)
        What did not happen: \(whatDidNotHappen)
        External status: \(externalEffect.summaryLine)
        Next step: \(recommendedNextStep.summaryLine)
        """
    }

    static func understanding(
        summary: String,
        whatHappened: String,
        question: String,
        reasonCode: String? = nil
    ) -> ExchangeFailure {
        ExchangeFailure(
            kind: .understandingFailure,
            severity: .normal,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: "No external action was taken.",
            externalEffect: .none,
            recommendedNextStep: .clarify(question: question),
            reasonCode: reasonCode,
            isRetryable: true
        )
    }

    static func discovery(
        summary: String,
        whatHappened: String,
        whatDidNotHappen: String = "No strong matches were found.",
        nextStep: NextStep,
        reasonCode: String? = nil
    ) -> ExchangeFailure {
        ExchangeFailure(
            kind: .discoveryFailure,
            severity: .normal,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: whatDidNotHappen,
            externalEffect: .none,
            recommendedNextStep: nextStep,
            reasonCode: reasonCode,
            isRetryable: true
        )
    }

    static func fit(
        summary: String,
        whatHappened: String,
        mismatchReason: String,
        reasonCode: String? = nil
    ) -> ExchangeFailure {
        ExchangeFailure(
            kind: .fitFailure,
            severity: .normal,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: "No candidate was advanced because the fit was not strong enough.",
            externalEffect: .none,
            recommendedNextStep: .reviewMismatch(reason: mismatchReason),
            reasonCode: reasonCode,
            isRetryable: true
        )
    }

    static func delivery(
        summary: String,
        whatHappened: String,
        whatDidNotHappen: String,
        externalEffect: ExternalEffect,
        nextStep: NextStep,
        reasonCode: String? = nil,
        technicalDetails: String? = nil,
        isRetryable: Bool = true
    ) -> ExchangeFailure {
        ExchangeFailure(
            kind: .deliveryFailure,
            severity: .high,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: whatDidNotHappen,
            externalEffect: externalEffect,
            recommendedNextStep: nextStep,
            reasonCode: reasonCode,
            technicalDetails: technicalDetails,
            isRetryable: isRetryable
        )
    }

    static func negotiation(
        summary: String,
        whatHappened: String,
        nextStep: NextStep,
        reasonCode: String? = nil
    ) -> ExchangeFailure {
        ExchangeFailure(
            kind: .negotiationFailure,
            severity: .normal,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: "The thread did not reach alignment.",
            externalEffect: .changed(description: "Coordination occurred, but it did not end in agreement."),
            recommendedNextStep: nextStep,
            reasonCode: reasonCode,
            isRetryable: false
        )
    }

    static func system(
        summary: String,
        whatHappened: String,
        whatDidNotHappen: String,
        externalEffect: ExternalEffect = .none,
        nextStep: NextStep = .seekRecovery,
        reasonCode: String? = nil,
        technicalDetails: String? = nil
    ) -> ExchangeFailure {
        ExchangeFailure(
            kind: .systemFailure,
            severity: .critical,
            summary: summary,
            whatHappened: whatHappened,
            whatDidNotHappen: whatDidNotHappen,
            externalEffect: externalEffect,
            recommendedNextStep: nextStep,
            reasonCode: reasonCode,
            technicalDetails: technicalDetails,
            isRetryable: true
        )
    }
}

private extension ExchangeFailure {
    static func normalizeRequired(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func normalizeNonAction(_ text: String) -> String {
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
