import Foundation

#if DEBUG
/// Manual QA notes for deterministic agency / Pass overlays (no seeded production data).
///
/// Example: seller offer + public surface for mobile car detailing — use locally when wiring fixtures in debug builds only.
public enum ExchangeAgencyDebugScenarioNotes {

    /// Mobile car detailing sanity-check attributes (pricing mode, logistics, geography).
    public static let mobileCarDetailingSnippet = """

    DEBUG agency scenario — Mobile car detailing
    ───────────────────────────────────────────
    pricingMode: quoteRequired
    appointmentRequired: yes
    remoteFriendly: false
    leadTimeNote: Usually 2–3 days
    capacityNote: Weekends only
    regionTags: GTA, Markham, Richmond Hill
    summaryLine: Interior/exterior SUV/sedan detailing

    Intended checks:
    - Pass 2 grounding lines pick up geography + modalities
    - Pass 3 planner does not widen sends; veto when approval / wait overlays apply
    """
}
#endif
