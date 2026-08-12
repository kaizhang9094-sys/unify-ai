import Foundation

/// Structured artifact produced during exchange coordination.
///
/// Artifacts are durable outputs of the secretary system, such as:
/// - candidate shortlists
/// - negotiation summaries
/// - quote request packages
/// - meeting proposals
/// - closure notes
///
/// They are not just UI blobs. They are reusable structured objects.
public struct ExchangeArtifact: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID
    public var threadID: ExchangeThread.ID
    public var createdAt: Date
    public var updatedAt: Date

    public var kind: Kind
    public var status: Status
    public var title: String
    public var summary: String?

    /// Main artifact payload, intentionally typed.
    public var payload: Payload

    /// Visibility markers for this artifact.
    public var visibility: ExchangeVisibility

    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        threadID: ExchangeThread.ID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        kind: Kind,
        status: Status = .active,
        title: String,
        summary: String? = nil,
        payload: Payload,
        visibility: ExchangeVisibility = .default,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.threadID = threadID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.kind = kind
        self.status = status
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary?.exchangeNilIfBlank
        self.payload = payload
        self.visibility = visibility
        self.metadata = metadata
    }
}

public extension ExchangeArtifact {
    enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
        case shortlist
        case quoteRequest
        case introductionPackage
        case negotiationSummary
        case schedulingProposal
        case threadSummary
        case closureNote
        case other
    }

    enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case active
        case superseded
        case archived
    }

    enum Payload: Codable, Sendable, Hashable {
        case shortlist(Shortlist)
        case quoteRequest(QuoteRequest)
        case introductionPackage(IntroductionPackage)
        case negotiationSummary(NegotiationSummary)
        case schedulingProposal(SchedulingProposal)
        case threadSummary(ThreadSummary)
        case closureNote(ClosureNote)
        case plainText(String)
    }

    struct Shortlist: Codable, Sendable, Hashable {
        public var matchIDs: [ExchangeMatch.ID]
        public var rationale: String?

        public init(
            matchIDs: [ExchangeMatch.ID],
            rationale: String? = nil
        ) {
            self.matchIDs = Array(Set(matchIDs)).sorted { $0.uuidString < $1.uuidString }
            self.rationale = rationale?.exchangeNilIfBlank
        }
    }

    struct QuoteRequest: Codable, Sendable, Hashable {
        public var scopeSummary: String
        public var constraints: [String]
        public var requestedDeliverables: [String]

        public init(
            scopeSummary: String,
            constraints: [String] = [],
            requestedDeliverables: [String] = []
        ) {
            self.scopeSummary = scopeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.constraints = ExchangeArtifact.normalizedLines(constraints)
            self.requestedDeliverables = ExchangeArtifact.normalizedLines(requestedDeliverables)
        }
    }

    struct IntroductionPackage: Codable, Sendable, Hashable {
        public var introSummary: String
        public var contextNotes: [String]

        public init(
            introSummary: String,
            contextNotes: [String] = []
        ) {
            self.introSummary = introSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.contextNotes = ExchangeArtifact.normalizedLines(contextNotes)
        }
    }

    struct NegotiationSummary: Codable, Sendable, Hashable {
        public var currentPosition: String
        public var openPoints: [String]
        public var nextMoveSuggestion: String?

        public init(
            currentPosition: String,
            openPoints: [String] = [],
            nextMoveSuggestion: String? = nil
        ) {
            self.currentPosition = currentPosition.trimmingCharacters(in: .whitespacesAndNewlines)
            self.openPoints = ExchangeArtifact.normalizedLines(openPoints)
            self.nextMoveSuggestion = nextMoveSuggestion?.exchangeNilIfBlank
        }
    }

    struct SchedulingProposal: Codable, Sendable, Hashable {
        public var proposedTimes: [String]
        public var formatNote: String?

        public init(
            proposedTimes: [String],
            formatNote: String? = nil
        ) {
            self.proposedTimes = ExchangeArtifact.normalizedLines(proposedTimes)
            self.formatNote = formatNote?.exchangeNilIfBlank
        }
    }

    struct ThreadSummary: Codable, Sendable, Hashable {
        public var whatHappened: String
        public var currentState: String
        public var nextStep: String?

        public init(
            whatHappened: String,
            currentState: String,
            nextStep: String? = nil
        ) {
            self.whatHappened = whatHappened.trimmingCharacters(in: .whitespacesAndNewlines)
            self.currentState = currentState.trimmingCharacters(in: .whitespacesAndNewlines)
            self.nextStep = nextStep?.exchangeNilIfBlank
        }
    }

    struct ClosureNote: Codable, Sendable, Hashable {
        public var summary: String
        public var didAnythingExternalChange: Bool
        public var recommendation: String?

        public init(
            summary: String,
            didAnythingExternalChange: Bool,
            recommendation: String? = nil
        ) {
            self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.didAnythingExternalChange = didAnythingExternalChange
            self.recommendation = recommendation?.exchangeNilIfBlank
        }
    }
}

public extension ExchangeArtifact {
    var previewLine: String {
        summary ?? title
    }

    func superseding(at date: Date = Date()) -> ExchangeArtifact {
        var copy = self
        copy.status = .superseded
        copy.updatedAt = date
        return copy
    }

    func archiving(at date: Date = Date()) -> ExchangeArtifact {
        var copy = self
        copy.status = .archived
        copy.updatedAt = date
        return copy
    }

    static func normalizedLines(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
