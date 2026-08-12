import Foundation

/// Read-only consolidated view of Exchange thread posture for secretary agency / UI.
///
/// Built from canonical `ExchangeModels.ThreadDetail` plus optionally resolved seller-surface rows.
/// No transport, persistence, or LLM work — strictly projection.
public struct ExchangeThreadSituation: Sendable, Hashable, Identifiable {
    public var id: ExchangeThread.ID { threadID }

    public var threadID: ExchangeThread.ID
    public var title: String
    public var phaseLabel: String
    public var agencyPhaseTitle: String?
    public var agencyPhaseDetail: String?
    public var stateSummary: String

    public var roleLabel: String?
    public var counterpartyName: String?

    /// Raw IDs for debugging / deep links — display titles live in sibling fields when resolved.
    public var selectedPublicProfileID: ExchangePublicNodeProfile.ID?
    public var selectedOfferID: ExchangeOffer.ID?

    public var selectedPublicProfileTitle: String?
    public var selectedOfferTitle: String?
    public var selectedOfferSummary: String?

    public var primaryImageURL: String?

    /// Resolved selected-offer public image URLs (hero first, max five). Empty when no offer images.
    public var selectedOfferImageURLs: [String]

    public var latestUserIntent: String?
    public var latestInboundLine: String?
    public var latestOutboundLine: String?

    public var pendingDraftSubject: String?
    public var pendingDraftPreview: String?

    /// True when a concrete approval packet is awaiting user decision on this snapshot.
    public var hasPendingApproval: Bool

    public var deliveryLine: String
    public var boundaryLine: String
    public var nextMoveLine: String

    public var trustLine: String?
    public var reachabilityLine: String?

    public var missingFacts: [String]
    public var whatChanged: [String]
    public var strengthReasons: [String]
    public var weaknessReasons: [String]

    /// Stable labels suitable for surfaced affordances — not commands.
    public var safeActionLabels: [String]

    public var requiresUserJudgment: Bool
    public var canRunAutonomously: Bool

    /// Pass 2: compact public/offered fact lines surfaced for grounding (read-only).
    public var groundedFactLines: [String]

    /// Pass 2: single-line provider-side answerability summary when available.
    public var answerabilityLine: String?

    /// Pass 2: concise buyer/agency readiness lines derived from surfaced gaps.
    public var decisionNeedLines: [String]

    /// Pass 3: read-only deterministic planner hints (mirror of `ExchangeAgencyAssessment.agencySuggestions`).
    public var agencySuggestions: [ExchangeAgencySuggestion]

    /// Short lines from the selected offer’s v1.5 commercial surface (when resolved).
    public var commercialSurfaceFactLines: [String]

    /// User-facing fulfillment summary for thread Details (lead time, capacity, posture).
    public var offerFulfillmentLine: String?

    /// Published offer contact summary for thread Details (email/phone/website only).
    public var offerContactSummary: String?

    /// Seller-required buyer inputs from resolved offer commercial facts.
    public var requiredBuyerInputLines: [String]

    /// FAQ lines formatted for display (`question — answer`).
    public var faqDisplayLines: [String]

    /// Package lines for thread Details (title + optional price).
    public var packageDisplayLines: [String]

    /// Short human-readable lines for skim / narration.
    public var explanationLines: [String]

    /// When autonomous outbound queueing was withheld (Pass 3 gate); user-safe copy only — no raw enums or payloads.
    public var autonomyHoldLine: String?
    public var autonomyHoldReason: String?

    public var trustPostureTitle: String?
    public var trustPostureSummary: String?
    public var trustEvidenceLines: [String]
    public var trustCautionLines: [String]
    public var trustRouteLabel: String?
    public var trustIsLedgerBacked: Bool

    public init(
        threadID: ExchangeThread.ID,
        title: String,
        phaseLabel: String,
        agencyPhaseTitle: String? = nil,
        agencyPhaseDetail: String? = nil,
        stateSummary: String,
        roleLabel: String? = nil,
        counterpartyName: String? = nil,
        selectedPublicProfileID: ExchangePublicNodeProfile.ID? = nil,
        selectedOfferID: ExchangeOffer.ID? = nil,
        selectedPublicProfileTitle: String? = nil,
        selectedOfferTitle: String? = nil,
        selectedOfferSummary: String? = nil,
        primaryImageURL: String? = nil,
        selectedOfferImageURLs: [String] = [],
        latestUserIntent: String? = nil,
        latestInboundLine: String? = nil,
        latestOutboundLine: String? = nil,
        pendingDraftSubject: String? = nil,
        pendingDraftPreview: String? = nil,
        hasPendingApproval: Bool,
        deliveryLine: String,
        boundaryLine: String,
        nextMoveLine: String,
        trustLine: String? = nil,
        reachabilityLine: String? = nil,
        missingFacts: [String] = [],
        whatChanged: [String] = [],
        strengthReasons: [String] = [],
        weaknessReasons: [String] = [],
        safeActionLabels: [String] = [],
        requiresUserJudgment: Bool = false,
        canRunAutonomously: Bool = false,
        groundedFactLines: [String] = [],
        answerabilityLine: String? = nil,
        decisionNeedLines: [String] = [],
        agencySuggestions: [ExchangeAgencySuggestion] = [],
        commercialSurfaceFactLines: [String] = [],
        offerFulfillmentLine: String? = nil,
        offerContactSummary: String? = nil,
        requiredBuyerInputLines: [String] = [],
        faqDisplayLines: [String] = [],
        packageDisplayLines: [String] = [],
        explanationLines: [String] = [],
        autonomyHoldLine: String? = nil,
        autonomyHoldReason: String? = nil,
        trustPostureTitle: String? = nil,
        trustPostureSummary: String? = nil,
        trustEvidenceLines: [String] = [],
        trustCautionLines: [String] = [],
        trustRouteLabel: String? = nil,
        trustIsLedgerBacked: Bool = false
    ) {
        self.threadID = threadID
        self.title = title
        self.phaseLabel = phaseLabel
        self.agencyPhaseTitle = agencyPhaseTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.agencyPhaseDetail = agencyPhaseDetail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.stateSummary = stateSummary
        self.roleLabel = roleLabel
        self.counterpartyName = counterpartyName
        self.selectedPublicProfileID = selectedPublicProfileID
        self.selectedOfferID = selectedOfferID
        self.selectedPublicProfileTitle = selectedPublicProfileTitle
        self.selectedOfferTitle = selectedOfferTitle
        self.selectedOfferSummary = selectedOfferSummary
        self.primaryImageURL = primaryImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.selectedOfferImageURLs = selectedOfferImageURLs
        self.latestUserIntent = latestUserIntent
        self.latestInboundLine = latestInboundLine
        self.latestOutboundLine = latestOutboundLine
        self.pendingDraftSubject = pendingDraftSubject
        self.pendingDraftPreview = pendingDraftPreview
        self.hasPendingApproval = hasPendingApproval
        self.deliveryLine = deliveryLine
        self.boundaryLine = boundaryLine
        self.nextMoveLine = nextMoveLine
        self.trustLine = trustLine
        self.reachabilityLine = reachabilityLine
        self.missingFacts = missingFacts
        self.whatChanged = whatChanged
        self.strengthReasons = strengthReasons
        self.weaknessReasons = weaknessReasons
        self.safeActionLabels = safeActionLabels
        self.requiresUserJudgment = requiresUserJudgment
        self.canRunAutonomously = canRunAutonomously
        self.groundedFactLines = groundedFactLines
        self.answerabilityLine = answerabilityLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.decisionNeedLines = decisionNeedLines
        self.agencySuggestions = agencySuggestions
        self.commercialSurfaceFactLines = commercialSurfaceFactLines
        self.offerFulfillmentLine = offerFulfillmentLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.offerContactSummary = offerContactSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.requiredBuyerInputLines = requiredBuyerInputLines
        self.faqDisplayLines = faqDisplayLines
        self.packageDisplayLines = packageDisplayLines
        self.explanationLines = explanationLines
        self.autonomyHoldLine = autonomyHoldLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.autonomyHoldReason = autonomyHoldReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.trustPostureTitle = trustPostureTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.trustPostureSummary = trustPostureSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.trustEvidenceLines = trustEvidenceLines
        self.trustCautionLines = trustCautionLines
        self.trustRouteLabel = trustRouteLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.trustIsLedgerBacked = trustIsLedgerBacked
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
