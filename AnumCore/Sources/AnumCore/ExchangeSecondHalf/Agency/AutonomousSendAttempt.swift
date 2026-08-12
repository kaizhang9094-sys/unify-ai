import Foundation

/// Observability-only snapshot for autonomous-send pipeline debugging (audit rows).
/// Does not include message body or draft body.
public struct AutonomousSendAttempt: Sendable, Hashable {
    public var lane: String
    public var role: String?
    public var threadID: UUID?
    public var draftID: UUID?
    public var selectedOfferID: String?
    public var selectedPublicProfileID: String?
    public var lastInboundEnvelopeID: String?
    public var pass3Allowed: Bool?
    public var pass3BlockReason: String?
    public var pass3Veto: String?
    public var policyAllowed: Bool?
    public var policyOutcome: String?
    public var eligibilityAllowed: Bool?
    public var eligibilityReason: String?
    public var permitKind: String?
    public var queued: Bool
    public var skipReason: String?
    public var errorSummary: String?

    public init(
        lane: String,
        role: String? = nil,
        threadID: UUID? = nil,
        draftID: UUID? = nil,
        selectedOfferID: String? = nil,
        selectedPublicProfileID: String? = nil,
        lastInboundEnvelopeID: String? = nil,
        pass3Allowed: Bool? = nil,
        pass3BlockReason: String? = nil,
        pass3Veto: String? = nil,
        policyAllowed: Bool? = nil,
        policyOutcome: String? = nil,
        eligibilityAllowed: Bool? = nil,
        eligibilityReason: String? = nil,
        permitKind: String? = nil,
        queued: Bool,
        skipReason: String? = nil,
        errorSummary: String? = nil
    ) {
        self.lane = lane
        self.role = role
        self.threadID = threadID
        self.draftID = draftID
        self.selectedOfferID = selectedOfferID
        self.selectedPublicProfileID = selectedPublicProfileID
        self.lastInboundEnvelopeID = lastInboundEnvelopeID
        self.pass3Allowed = pass3Allowed
        self.pass3BlockReason = pass3BlockReason
        self.pass3Veto = pass3Veto
        self.policyAllowed = policyAllowed
        self.policyOutcome = policyOutcome
        self.eligibilityAllowed = eligibilityAllowed
        self.eligibilityReason = eligibilityReason
        self.permitKind = permitKind
        self.queued = queued
        self.skipReason = skipReason
        self.errorSummary = errorSummary
    }

    public func toMetadata() -> [String: String] {
        var m: [String: String] = [
            "trace_kind": "autonomous_send_attempt_v1",
            "lane": lane,
            "queued": queued ? "true" : "false"
        ]
        if let role { m["role"] = role }
        if let threadID { m["thread_id"] = threadID.uuidString }
        if let draftID { m["draft_id"] = draftID.uuidString }
        if let selectedOfferID { m["selected_offer_id"] = selectedOfferID }
        if let selectedPublicProfileID { m["selected_public_profile_id"] = selectedPublicProfileID }
        if let lastInboundEnvelopeID { m["last_inbound_envelope_id"] = lastInboundEnvelopeID }
        if let pass3Allowed { m["pass3_allowed"] = pass3Allowed ? "true" : "false" }
        if let pass3BlockReason { m["pass3_block_reason"] = pass3BlockReason }
        if let pass3Veto { m["pass3_veto"] = pass3Veto }
        if let policyAllowed { m["policy_allowed"] = policyAllowed ? "true" : "false" }
        if let policyOutcome { m["policy_outcome"] = policyOutcome }
        if let eligibilityAllowed { m["eligibility_allowed"] = eligibilityAllowed ? "true" : "false" }
        if let eligibilityReason { m["eligibility_reason"] = eligibilityReason }
        if let permitKind { m["permit_kind"] = permitKind }
        if let skipReason { m["skip_reason"] = skipReason }
        if let errorSummary { m["error_summary"] = errorSummary }
        return m
    }

    /// Compact single-line detail for `ExchangeAuditRecord.detail` (privacy-safe).
    public func compactDetailLine() -> String {
        toMetadata()
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " | ")
    }
}
