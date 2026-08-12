import Foundation

/// Maps governed provider inquiry compare output into `ExchangeInboundInquiry` intake fields.
public enum ProviderInboundCompareRoutingAdapter: Sendable {
    public static func makeInboundInquiry(
        compare: ExchangeProviderInquiryCompareResult,
        governed: ProviderInquiryCompareGovernor.Outcome,
        rawRequesterAsk: String,
        matchedOfferOrProfileAnchor: String?
    ) -> ExchangeInboundInquiry {
        let ask = firstNonEmpty(
            compare.requesterAsk,
            rawRequesterAsk
        )
        let summary = firstNonEmpty(
            compare.inquirySummary,
            summarizeFromCompare(compare, fallbackAsk: ask)
        )

        let status = answerability(for: governed.normalizedAction)
        let classification: ExchangeInboundInquiryClassification =
            governed.normalizedAction == .holdForBoundaryApproval || governed.normalizedAction == .blocked
            ? .exceptional
            : .routine

        return ExchangeInboundInquiry(
            inquirySummary: summary,
            requesterAsk: ask,
            matchedOfferOrProfileAnchor: matchedOfferOrProfileAnchor,
            answerabilityStatus: status,
            classification: classification
        )
    }

    private static func summarizeFromCompare(
        _ compare: ExchangeProviderInquiryCompareResult,
        fallbackAsk: String
    ) -> String {
        let clip = { (s: String, n: Int) -> String in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count <= n { return t }
            return String(t.prefix(n))
        }
        let fromReason = compare.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromReason.isEmpty, !fromReason.lowercased().hasPrefix("provider_inquiry_compare_failed") {
            return clip(fromReason, 220)
        }
        if !fallbackAsk.isEmpty {
            return clip(fallbackAsk, 220)
        }
        return "Inbound inquiry"
    }

    private static func answerability(
        for action: ProviderInquiryCompareGovernor.NormalizedAction
    ) -> ExchangeInboundInquiryAnswerability {
        switch action {
        case .sendWithinConsent:
            return .answerableFromKnownFacts
        case .askProviderInput, .wait:
            return .requiresUserInput
        case .holdForBoundaryApproval:
            return .requiresUserInput
        case .blocked:
            return .outOfScope
        }
    }

    private static func firstNonEmpty(_ a: String?, _ b: String) -> String {
        let ta = a?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !ta.isEmpty { return ta }
        return b.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
