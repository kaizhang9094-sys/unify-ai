import Foundation

/// Canonical user-visible state for a coordination thread.
///
/// This enum describes the thread's legible coordination position.
/// It is not the source of truth for low-level transport mechanics,
/// relay receipts, or system diagnostics.
///
/// Failure is first-class and visible here, but detailed execution and
/// transport records should live in their own infrastructure models.
public enum ExchangeState: Codable, Sendable, Hashable {
    case drafting
    case needsClarification(ClarificationStatus)

    case searching(SearchStatus)

    /// A viable match/found path exists.
    ///
    /// Important:
    /// This is the clean handoff point between first-half discovery and
    /// second-half qualification / coordination.
    case matchFound(MatchFoundStatus)

    case matchCandidatesWeak(WeakMatchStatus)
    case noViableMatch(NoMatchStatus)

    case draftReady(DraftReadyStatus)
    case awaitingApproval(ApprovalStatus)
    case sending(SendingStatus)
    case blockedByDeliveryFailure(DeliveryFailureStatus)

    case awaitingResponse(ResponseWaitStatus)
    case declined(DeclineStatus)
    case stalled(StallStatus)
    case resolved(ResolutionStatus)

    case blockedBySystemFailure(SystemFailureStatus)
}

public extension ExchangeState {
    struct ClarificationStatus: Codable, Sendable, Hashable {
        public var question: String
        public var askedAt: Date
        public var attempts: Int

        public init(
            question: String,
            askedAt: Date = Date(),
            attempts: Int = 1
        ) {
            self.question = question.trimmingCharacters(in: .whitespacesAndNewlines)
            self.askedAt = askedAt
            self.attempts = max(1, attempts)
        }
    }

    struct SearchStatus: Codable, Sendable, Hashable {
        public var startedAt: Date
        public var scopeSummary: String?
        public var querySummary: String?
        public var candidateCount: Int

        public init(
            startedAt: Date = Date(),
            scopeSummary: String? = nil,
            querySummary: String? = nil,
            candidateCount: Int = 0
        ) {
            self.startedAt = startedAt
            self.scopeSummary = scopeSummary?.nilIfBlank
            self.querySummary = querySummary?.nilIfBlank
            self.candidateCount = max(0, candidateCount)
        }
    }

    /// User-visible state after discovery has selected a viable path.
    ///
    /// This should not be treated as "still searching".
    /// It means first-half discovery produced a usable candidate and the
    /// thread is now ready for second-half handling: qualification, review,
    /// draft preparation, clarification, or commitment-safe progression.
    struct MatchFoundStatus: Codable, Sendable, Hashable {
        public var foundAt: Date
        public var candidateCount: Int
        public var summary: String
        public var nextStep: String?
        public var selectedCounterpartyID: String?
        public var selectedPublicProfileID: String?
        public var selectedOfferID: String?

        public init(
            foundAt: Date = Date(),
            candidateCount: Int,
            summary: String,
            nextStep: String? = nil,
            selectedCounterpartyID: String? = nil,
            selectedPublicProfileID: String? = nil,
            selectedOfferID: String? = nil
        ) {
            self.foundAt = foundAt
            self.candidateCount = max(1, candidateCount)

            let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.summary = cleanSummary.isEmpty
                ? "Found a likely path."
                : cleanSummary

            self.nextStep = nextStep?.nilIfBlank
            self.selectedCounterpartyID = selectedCounterpartyID?.nilIfBlank
            self.selectedPublicProfileID = selectedPublicProfileID?.nilIfBlank
            self.selectedOfferID = selectedOfferID?.nilIfBlank
        }
    }

    struct WeakMatchStatus: Codable, Sendable, Hashable {
        public var candidateCount: Int
        public var explanation: String
        public var suggestedRefinement: String?

        public init(
            candidateCount: Int,
            explanation: String,
            suggestedRefinement: String? = nil
        ) {
            self.candidateCount = max(0, candidateCount)
            self.explanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            self.suggestedRefinement = suggestedRefinement?.nilIfBlank
        }
    }

    struct NoMatchStatus: Codable, Sendable, Hashable {
        public var searchedAt: Date
        public var explanation: String
        public var suggestedNextStep: String?

        public init(
            searchedAt: Date = Date(),
            explanation: String,
            suggestedNextStep: String? = nil
        ) {
            self.searchedAt = searchedAt
            self.explanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            self.suggestedNextStep = suggestedNextStep?.nilIfBlank
        }
    }

    struct DraftReadyStatus: Codable, Sendable, Hashable {
        public var preparedAt: Date
        public var summary: String
        public var draftID: UUID?

        public init(
            preparedAt: Date = Date(),
            summary: String,
            draftID: UUID? = nil
        ) {
            self.preparedAt = preparedAt
            self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.draftID = draftID
        }
    }

    struct ApprovalStatus: Codable, Sendable, Hashable {
        public var requestedAt: Date
        public var summary: String
        public var draftID: UUID?
        public var expiresAt: Date?

        public init(
            requestedAt: Date = Date(),
            summary: String,
            draftID: UUID? = nil,
            expiresAt: Date? = nil
        ) {
            self.requestedAt = requestedAt
            self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.draftID = draftID
            self.expiresAt = expiresAt
        }
    }

    struct SendingStatus: Codable, Sendable, Hashable {
        public var startedAt: Date
        public var attemptNumber: Int
        public var channelSummary: String?

        public init(
            startedAt: Date = Date(),
            attemptNumber: Int = 1,
            channelSummary: String? = nil
        ) {
            self.startedAt = startedAt
            self.attemptNumber = max(1, attemptNumber)
            self.channelSummary = channelSummary?.nilIfBlank
        }
    }

    struct DeliveryFailureStatus: Codable, Sendable, Hashable {
        public var failedAt: Date
        public var failureID: UUID
        public var deliveryWasAttempted: Bool

        public init(
            failedAt: Date = Date(),
            failureID: UUID,
            deliveryWasAttempted: Bool
        ) {
            self.failedAt = failedAt
            self.failureID = failureID
            self.deliveryWasAttempted = deliveryWasAttempted
        }
    }

    struct ResponseWaitStatus: Codable, Sendable, Hashable {
        public var since: Date
        public var lastOutboundAt: Date?
        public var followUpSuggestedAt: Date?

        public init(
            since: Date = Date(),
            lastOutboundAt: Date? = nil,
            followUpSuggestedAt: Date? = nil
        ) {
            self.since = since
            self.lastOutboundAt = lastOutboundAt
            self.followUpSuggestedAt = followUpSuggestedAt
        }
    }

    struct DeclineStatus: Codable, Sendable, Hashable {
        public var declinedAt: Date
        public var reasonSummary: String?

        public init(
            declinedAt: Date = Date(),
            reasonSummary: String? = nil
        ) {
            self.declinedAt = declinedAt
            self.reasonSummary = reasonSummary?.nilIfBlank
        }
    }

    struct StallStatus: Codable, Sendable, Hashable {
        public var stalledAt: Date
        public var reasonSummary: String
        public var lastMeaningfulActivityAt: Date?

        public init(
            stalledAt: Date = Date(),
            reasonSummary: String,
            lastMeaningfulActivityAt: Date? = nil
        ) {
            self.stalledAt = stalledAt
            self.reasonSummary = reasonSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastMeaningfulActivityAt = lastMeaningfulActivityAt
        }
    }

    struct ResolutionStatus: Codable, Sendable, Hashable {
        public var resolvedAt: Date
        public var summary: String

        public init(
            resolvedAt: Date = Date(),
            summary: String
        ) {
            self.resolvedAt = resolvedAt
            self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    struct SystemFailureStatus: Codable, Sendable, Hashable {
        public var failedAt: Date
        public var failureID: UUID

        public init(
            failedAt: Date = Date(),
            failureID: UUID
        ) {
            self.failedAt = failedAt
            self.failureID = failureID
        }
    }
}

public extension ExchangeState {
    var phaseTitle: String {
        switch self {
        case .drafting:
            return "Drafting"

        case .needsClarification:
            return "Needs Clarification"

        case .searching:
            return "Searching"

        case .matchFound:
            return "Match Found"

        case .matchCandidatesWeak:
            return "Weak Matches"

        case .noViableMatch:
            return "No Viable Match"

        case .draftReady:
            return "Draft Ready"

        case .awaitingApproval:
            return "Awaiting Approval"

        case .sending:
            return "Sending"

        case .blockedByDeliveryFailure:
            return "Delivery Failed"

        case .awaitingResponse:
            return "Awaiting Response"

        case .declined:
            return "Declined"

        case .stalled:
            return "Stalled"

        case .resolved:
            return "Resolved"

        case .blockedBySystemFailure:
            return "System Error"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .resolved,
             .declined:
            return true

        case .drafting,
             .needsClarification,
             .searching,
             .matchFound,
             .matchCandidatesWeak,
             .noViableMatch,
             .draftReady,
             .awaitingApproval,
             .sending,
             .blockedByDeliveryFailure,
             .awaitingResponse,
             .stalled,
             .blockedBySystemFailure:
            return false
        }
    }

    /// Whether the thread currently needs a meaningful user decision,
    /// response, or review to progress.
    var requiresUserAttention: Bool {
        switch self {
        case .needsClarification,
             .matchFound,
             .matchCandidatesWeak,
             .noViableMatch,
             .draftReady,
             .awaitingApproval,
             .blockedByDeliveryFailure,
             .declined,
             .stalled,
             .blockedBySystemFailure:
            return true

        case .drafting,
             .searching,
             .sending,
             .awaitingResponse,
             .resolved:
            return false
        }
    }

    /// Whether the thread is visibly impeded by a negative condition.
    ///
    /// `matchFound` is not a failure state. It is a positive checkpoint
    /// waiting for review, qualification, or next-step progression.
    var isFailureState: Bool {
        switch self {
        case .matchCandidatesWeak,
             .noViableMatch,
             .blockedByDeliveryFailure,
             .declined,
             .stalled,
             .blockedBySystemFailure:
            return true

        case .drafting,
             .needsClarification,
             .searching,
             .matchFound,
             .draftReady,
             .awaitingApproval,
             .sending,
             .awaitingResponse,
             .resolved:
            return false
        }
    }

    var summaryLine: String {
        switch self {
        case .drafting:
            return "The request is being prepared."

        case .needsClarification(let status):
            return status.question

        case .searching(let status):
            if let query = status.querySummary {
                return "Searching: \(query)"
            }
            return "Searching for candidates."

        case .matchFound(let status):
            return status.summary

        case .matchCandidatesWeak(let status):
            return status.explanation

        case .noViableMatch(let status):
            return status.explanation

        case .draftReady(let status):
            return status.summary

        case .awaitingApproval(let status):
            return status.summary

        case .sending(let status):
            return "Sending attempt \(status.attemptNumber)."

        case .blockedByDeliveryFailure:
            return "Delivery did not complete successfully."

        case .awaitingResponse:
            return "Waiting for a response."

        case .declined(let status):
            return status.reasonSummary ?? "The request was declined."

        case .stalled(let status):
            return status.reasonSummary

        case .resolved(let status):
            return status.summary

        case .blockedBySystemFailure:
            return "A system failure interrupted progress."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
