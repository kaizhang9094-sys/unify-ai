import Foundation

public enum ExchangeInboundInquiryAnswerability: String, Codable, CaseIterable, Hashable, Sendable {
    case answerableFromKnownFacts
    case requiresUserInput
    case insufficientContext
    case outOfScope
}

public enum ExchangeInboundInquiryClassification: String, Codable, CaseIterable, Hashable, Sendable {
    case routine
    case exceptional
}

/// Provider-side incoming inquiry model.
///
/// This separates inbound provider intake handling from generic thread messages,
/// which is important for making the provider-side secretary act like a real
/// inbound operator rather than a dumb relay.
public struct ExchangeInboundInquiry: Codable, Hashable, Sendable {
    public var inquirySummary: String
    public var requesterAsk: String
    public var matchedOfferOrProfileAnchor: String?
    public var answerabilityStatus: ExchangeInboundInquiryAnswerability
    public var classification: ExchangeInboundInquiryClassification

    public init(
        inquirySummary: String,
        requesterAsk: String,
        matchedOfferOrProfileAnchor: String? = nil,
        answerabilityStatus: ExchangeInboundInquiryAnswerability,
        classification: ExchangeInboundInquiryClassification
    ) {
        self.inquirySummary = inquirySummary
        self.requesterAsk = requesterAsk
        self.matchedOfferOrProfileAnchor = matchedOfferOrProfileAnchor
        self.answerabilityStatus = answerabilityStatus
        self.classification = classification
    }
}

public extension ExchangeInboundInquiry {
    var isRoutine: Bool {
        classification == .routine
    }

    var requiresProviderUserInput: Bool {
        answerabilityStatus == .requiresUserInput
    }

    var canBeAnsweredFromKnownFacts: Bool {
        answerabilityStatus == .answerableFromKnownFacts
    }

    var shouldLikelyBeDeclined: Bool {
        answerabilityStatus == .outOfScope
    }
}
