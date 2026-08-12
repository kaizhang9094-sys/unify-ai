import Foundation

/// Canonical snapshot consumed by deterministic agency engines (Pass 1: read-only).
///
/// Builds on `ExchangeThreadSituation`, hydrated seller surfaces, and structured operating memory.
/// No transport — callers fetch store rows upstream.
public struct ExchangeAgencyContext: Sendable, Hashable {
    public enum Side: String, Codable, Sendable, Hashable {
        case requester
        case provider
    }

    public var threadID: ExchangeThread.ID?
    public var side: Side
    public var selectedOfferID: ExchangeOffer.ID?
    public var selectedPublicProfileID: ExchangePublicNodeProfile.ID?
    public var selectedCounterpartyID: ExchangeCounterparty.ID?

    /// Primary utterance framing the thread — request text, inferred goal, or latest inbound cue.
    public var userIntent: String

    public var secretaryStyleText: String?

    public var situation: ExchangeThreadSituation?

    public var publicProfile: ExchangePublicNodeProfile?
    public var offer: ExchangeOffer?

    public var operatingMemory: ExchangeStructuredOperatingMemory

    /// Recent thread/timeline lines (compact, already trimmed by caller).
    public var threadHistoryLines: [String]

    /// Seller- and projection-derived facts surfaced to reasoning.
    public var knownFacts: [String]

    /// Situation/engine gaps consolidated for this pass.
    public var missingFacts: [String]

    /// Deterministic requester intent vs surfaced surface gaps (Pass-2); drives decision needs ahead of templates.
    public var intentGaps: [ExchangeRequesterIntentGap]

    /// Single merged clarification question for provider-bound drafts when gaps are actionable.
    public var intentGapCombinedClarificationQuestion: String?

    /// Human-readable escalation / boundary snippets (boundary line, weaknesses, posture).
    public var boundaryHints: [String]

    public var reachabilityLine: String?

    /// Whether routing posture implies direct reachable contact (`false` ≠ block UI — snapshot only).
    public var canContactDirectly: Bool

    /// When set, Pass-2 deterministic engines gate missing-fact synthesis to this surface (from `ExchangeIntent`).
    public var opportunitySurfaceAnchor: ExchangeOpportunitySurfaceAnchor?

    /// Resolved requester location for Pass-2 missing-fact templates (no raw coordinates).
    public var requesterLocationFact: ExchangeSecondHalfLocationFact?

    public var createdAt: Date

    public init(
        threadID: ExchangeThread.ID? = nil,
        side: Side,
        selectedOfferID: ExchangeOffer.ID? = nil,
        selectedPublicProfileID: ExchangePublicNodeProfile.ID? = nil,
        selectedCounterpartyID: ExchangeCounterparty.ID? = nil,
        userIntent: String,
        secretaryStyleText: String? = nil,
        situation: ExchangeThreadSituation? = nil,
        publicProfile: ExchangePublicNodeProfile? = nil,
        offer: ExchangeOffer? = nil,
        operatingMemory: ExchangeStructuredOperatingMemory,
        threadHistoryLines: [String] = [],
        knownFacts: [String] = [],
        missingFacts: [String] = [],
        intentGaps: [ExchangeRequesterIntentGap] = [],
        intentGapCombinedClarificationQuestion: String? = nil,
        boundaryHints: [String] = [],
        reachabilityLine: String? = nil,
        canContactDirectly: Bool = true,
        opportunitySurfaceAnchor: ExchangeOpportunitySurfaceAnchor? = nil,
        requesterLocationFact: ExchangeSecondHalfLocationFact? = nil,
        createdAt: Date = Date()
    ) {
        self.threadID = threadID
        self.side = side
        self.selectedOfferID = selectedOfferID
        self.selectedPublicProfileID = selectedPublicProfileID
        self.selectedCounterpartyID = selectedCounterpartyID
        self.userIntent = userIntent
        if let st = secretaryStyleText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !st.isEmpty {
            self.secretaryStyleText = st
        } else {
            self.secretaryStyleText = nil
        }
        self.situation = situation
        self.publicProfile = publicProfile
        self.offer = offer
        self.operatingMemory = operatingMemory
        self.threadHistoryLines = threadHistoryLines
        self.knownFacts = knownFacts
        self.missingFacts = missingFacts
        self.intentGaps = intentGaps
        let trimmedCombined = intentGapCombinedClarificationQuestion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.intentGapCombinedClarificationQuestion =
            (trimmedCombined?.isEmpty == false) ? trimmedCombined : nil
        self.boundaryHints = boundaryHints
        self.reachabilityLine = reachabilityLine
        self.canContactDirectly = canContactDirectly
        self.opportunitySurfaceAnchor = opportunitySurfaceAnchor
        self.requesterLocationFact = requesterLocationFact
        self.createdAt = createdAt
    }
}

private extension String {
    var nilOrEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
