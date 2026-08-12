import Foundation

/// Inputs for composing requester closure copy. Deterministic pause frame is authoritative for validation.
public struct ExchangeRequesterClosureComposerInput: Sendable {
    public var requesterAskBlob: String
    public var latestProviderReply: String?
    public var deterministicPause: ExchangeRequesterPauseFrame
    public var decisionFrame: ExchangeDecisionFrame?
    public var boundaryRequiresHumanApproval: Bool
    public var boundaryReasonLine: String?
    public var selectedOfferSummary: String?
    public var selectedProfileSummary: String?
    public var styleProfile: ExchangeSecretaryStyleProfile
    public var representationSupplement: String?

    public init(
        requesterAskBlob: String,
        latestProviderReply: String? = nil,
        deterministicPause: ExchangeRequesterPauseFrame,
        decisionFrame: ExchangeDecisionFrame? = nil,
        boundaryRequiresHumanApproval: Bool = false,
        boundaryReasonLine: String? = nil,
        selectedOfferSummary: String? = nil,
        selectedProfileSummary: String? = nil,
        styleProfile: ExchangeSecretaryStyleProfile,
        representationSupplement: String? = nil
    ) {
        self.requesterAskBlob = requesterAskBlob
        self.latestProviderReply = latestProviderReply
        self.deterministicPause = deterministicPause
        self.decisionFrame = decisionFrame
        self.boundaryRequiresHumanApproval = boundaryRequiresHumanApproval
        self.boundaryReasonLine = boundaryReasonLine
        self.selectedOfferSummary = selectedOfferSummary
        self.selectedProfileSummary = selectedProfileSummary
        self.styleProfile = styleProfile
        self.representationSupplement = representationSupplement
    }
}
