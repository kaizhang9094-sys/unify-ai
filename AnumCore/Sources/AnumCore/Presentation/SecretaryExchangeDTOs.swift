import Foundation

// MARK: - List row source (facade-assembled; not user-facing by itself)

/// Inputs for `SecretaryExchangeDTOBuilder.buildItem` assembled from the same data path as `ExchangeFacade.listThreads`.
public struct SecretaryExchangeListRowSource: Sendable {
    public let id: UUID
    public let updatedAt: Date
    public let titlePick: ExchangeThreadCardTitleProjection.TitlePick
    public let subtitle: String
    public let inboxPhaseTitle: String
    public let requestCaptured: String?
    public let threadStoredTitle: String
    public let interpretationUserQuestion: String?
    public let clarificationPrompt: String?
    public let nextStepText: String?
    public let latestDraft: ExchangeMessageDraft?
    public let display: ExchangeSecondHalfUIAdapter.DisplayModel?
    public let hydrationResolvedTitle: String?
    public let hydrationVisibleLine: String?
    public let hydrationMatchSummary: String?
    public let matchWhy: String?
    /// Owning durable thread snapshot (anchors outbound draft cards).
    public let thread: ExchangeThread

    public init(
        id: UUID,
        updatedAt: Date,
        titlePick: ExchangeThreadCardTitleProjection.TitlePick,
        subtitle: String,
        inboxPhaseTitle: String,
        requestCaptured: String?,
        threadStoredTitle: String,
        interpretationUserQuestion: String?,
        clarificationPrompt: String?,
        nextStepText: String?,
        latestDraft: ExchangeMessageDraft?,
        display: ExchangeSecondHalfUIAdapter.DisplayModel?,
        hydrationResolvedTitle: String?,
        hydrationVisibleLine: String?,
        hydrationMatchSummary: String?,
        matchWhy: String?,
        thread: ExchangeThread
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.titlePick = titlePick
        self.subtitle = subtitle
        self.inboxPhaseTitle = inboxPhaseTitle
        self.requestCaptured = requestCaptured
        self.threadStoredTitle = threadStoredTitle
        self.interpretationUserQuestion = interpretationUserQuestion
        self.clarificationPrompt = clarificationPrompt
        self.nextStepText = nextStepText
        self.latestDraft = latestDraft
        self.display = display
        self.hydrationResolvedTitle = hydrationResolvedTitle
        self.hydrationVisibleLine = hydrationVisibleLine
        self.hydrationMatchSummary = hydrationMatchSummary
        self.matchWhy = matchWhy
        self.thread = thread
    }
}

// MARK: - User-facing exchange DTOs

public struct SecretaryExchangeMessageCard: Sendable, Hashable {
    public var roleLabel: String
    public var timestamp: Date?
    public var subject: String?
    public var body: String
    public var footnote: String?

    public init(
        roleLabel: String,
        timestamp: Date? = nil,
        subject: String? = nil,
        body: String,
        footnote: String? = nil
    ) {
        self.roleLabel = roleLabel
        self.timestamp = timestamp
        self.subject = subject
        self.body = body
        self.footnote = footnote
    }
}

public struct SecretaryExchangeMatchCard: Sendable, Hashable {
    public var headline: String
    public var summary: String?
    public var whyItFits: String?

    public init(headline: String, summary: String? = nil, whyItFits: String? = nil) {
        self.headline = headline
        self.summary = summary
        self.whyItFits = whyItFits
    }
}

public struct SecretaryExchangeWorkStep: Sendable, Hashable {
    public var title: String
    public var detail: String?
    public var completed: Bool

    public init(title: String, detail: String? = nil, completed: Bool) {
        self.title = title
        self.detail = detail
        self.completed = completed
    }
}

public struct SecretaryExchangeNextAction: Sendable, Hashable {
    public var primaryLine: String
    public var detail: String?
    public var requiresUser: Bool

    public init(primaryLine: String, detail: String? = nil, requiresUser: Bool) {
        self.primaryLine = primaryLine
        self.detail = detail
        self.requiresUser = requiresUser
    }
}

public struct SecretaryExchangeItem: Sendable, Hashable {
    public var id: UUID
    public var updatedAt: Date
    public var headlineTitle: String
    public var subtitle: String?
    public var phaseLabel: String
    public var originalRequest: String?
    public var matchCard: SecretaryExchangeMatchCard?
    public var missingInformation: [String]
    public var outboundDraft: SecretaryExchangeMessageCard?
    public var latestInbound: SecretaryExchangeMessageCard?
    public var nextAction: SecretaryExchangeNextAction?

    public init(
        id: UUID,
        updatedAt: Date,
        headlineTitle: String,
        subtitle: String?,
        phaseLabel: String,
        originalRequest: String?,
        matchCard: SecretaryExchangeMatchCard?,
        missingInformation: [String],
        outboundDraft: SecretaryExchangeMessageCard?,
        latestInbound: SecretaryExchangeMessageCard?,
        nextAction: SecretaryExchangeNextAction?
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.headlineTitle = headlineTitle
        self.subtitle = subtitle
        self.phaseLabel = phaseLabel
        self.originalRequest = originalRequest
        self.matchCard = matchCard
        self.missingInformation = missingInformation
        self.outboundDraft = outboundDraft
        self.latestInbound = latestInbound
        self.nextAction = nextAction
    }
}

public struct SecretaryExchangeDetail: Sendable, Hashable {
    public var id: UUID
    public var updatedAt: Date
    public var headlineTitle: String
    public var subtitle: String?
    public var phaseLabel: String
    public var originalRequest: String?
    public var matchCard: SecretaryExchangeMatchCard?
    public var missingInformation: [String]
    public var outboundDraft: SecretaryExchangeMessageCard?
    public var latestInbound: SecretaryExchangeMessageCard?
    public var nextAction: SecretaryExchangeNextAction?
    public var workSteps: [SecretaryExchangeWorkStep]

    public init(
        id: UUID,
        updatedAt: Date,
        headlineTitle: String,
        subtitle: String?,
        phaseLabel: String,
        originalRequest: String?,
        matchCard: SecretaryExchangeMatchCard?,
        missingInformation: [String],
        outboundDraft: SecretaryExchangeMessageCard?,
        latestInbound: SecretaryExchangeMessageCard?,
        nextAction: SecretaryExchangeNextAction?,
        workSteps: [SecretaryExchangeWorkStep]
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.headlineTitle = headlineTitle
        self.subtitle = subtitle
        self.phaseLabel = phaseLabel
        self.originalRequest = originalRequest
        self.matchCard = matchCard
        self.missingInformation = missingInformation
        self.outboundDraft = outboundDraft
        self.latestInbound = latestInbound
        self.nextAction = nextAction
        self.workSteps = workSteps
    }
}
