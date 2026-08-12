import Foundation

/// Post-generation checks for `providerInquiryCompare.draftReply` before compare-first autonomous send.
public enum ExchangeProviderInquiryCompareDraftReplyValidator: Sendable {

    public struct Outcome: Sendable {
        public let body: String
        public let allowsCompareFirstDirectSend: Bool
        public let action: String
        public let violations: [String]

        public init(body: String, allowsCompareFirstDirectSend: Bool, action: String, violations: [String]) {
            self.body = body
            self.allowsCompareFirstDirectSend = allowsCompareFirstDirectSend
            self.action = action
            self.violations = violations
        }
    }

    private static let socialSchedulingPhrases: [String] = [
        "i'd love", "i would love", "happy to chat", "grab a coffee", "meet up", "let's meet",
        "lets meet", "i can show", "i can schedule", "love to chat", "happy to meet"
    ]

    private static let hedgingPhrases: [String] = [
        "sounds like", "seems like", "i think", "i guess"
    ]

    private static let promotionalPhrases: [String] = [
        "lovely spot", "amazing", "exciting", "serious potential", "great opportunity"
    ]

    private static let adjacentTopicPhrases: [String] = [
        "neighborhood vibes", "vibes in the neighborhood"
    ]

    /// Provider draft must not ask the requester to confirm provider-side facts.
    private static let roleReversalPhrases: [(pattern: String, code: String)] = [
        ("your credentials", "role_reversal_your_credentials"),
        ("verify your credentials", "role_reversal_verify_your_credentials"),
        ("verify your specific credentials", "role_reversal_verify_your_credentials"),
        ("your schedule availability", "role_reversal_your_schedule_availability"),
        ("approval from your provider", "role_reversal_approval_from_your_provider"),
        ("explicit approval for this discount from your provider", "role_reversal_discount_approval_from_provider"),
        ("confirm those details with you", "role_reversal_confirm_details_with_you"),
        ("confirm license and insurance with you", "role_reversal_confirm_credentials_with_you"),
        ("confirm the current license and insurance with you", "role_reversal_confirm_credentials_with_you"),
        ("i would need to confirm license and insurance with you", "role_reversal_confirm_credentials_with_you"),
        ("receive your confirmation before proceeding", "role_reversal_receive_your_confirmation"),
        ("your confirmation before proceeding", "role_reversal_your_confirmation_before_proceeding"),
        ("i need to verify your", "role_reversal_i_need_to_verify_your"),
        ("i would need to confirm that you have received", "role_reversal_requester_discount_approval")
    ]

    public static func validate(
        rawDraft: String,
        compare: ExchangeProviderInquiryCompareResult?
    ) -> Outcome {
        let trimmed = rawDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(body: trimmed, allowsCompareFirstDirectSend: false, action: "blocked", violations: ["empty_body"])
        }

        let lower = trimmed.lowercased()
        let violations: [String] = collectViolations(lower: lower, compare: compare)

        if violations.isEmpty {
            return Outcome(body: trimmed, allowsCompareFirstDirectSend: true, action: "pass", violations: [])
        }

        if let rewritten = attemptNarrowRewrite(trimmed: trimmed, compare: compare), rewritten != trimmed {
            let v2 = collectViolations(lower: rewritten.lowercased(), compare: compare)
            if v2.isEmpty {
                return Outcome(body: rewritten, allowsCompareFirstDirectSend: true, action: "rewritten", violations: violations)
            }
        }

        return Outcome(body: trimmed, allowsCompareFirstDirectSend: false, action: "blocked", violations: violations)
    }

    private static func collectViolations(
        lower: String,
        compare: ExchangeProviderInquiryCompareResult?
    ) -> [String] {
        var violations: [String] = []
        for p in socialSchedulingPhrases where lower.contains(p) {
            violations.append("social_or_scheduling:\(p)")
        }
        for p in adjacentTopicPhrases where lower.contains(p) {
            violations.append("adjacent_topic:\(p)")
        }
        violations.append(contentsOf: collectRoleReversalViolations(lower: lower))

        let answerable = compare?.answerableFromOffer == true
        if answerable {
            for p in hedgingPhrases where lower.contains(p) {
                violations.append("hedging_when_answerable:\(p)")
            }
            let broadAsk = isBroadAsk(compare?.requesterAsk ?? "")
            if !broadAsk {
                for p in promotionalPhrases where lower.contains(p) {
                    violations.append("promotional_when_narrow:\(p)")
                }
            }
        }
        return violations
    }

    private static func collectRoleReversalViolations(lower: String) -> [String] {
        var out: [String] = []
        for entry in roleReversalPhrases where lower.contains(entry.pattern) {
            out.append(entry.code)
        }
        return out
    }

    private static func isBroadAsk(_ ask: String) -> Bool {
        let t = ask.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.contains("tell me more") { return true }
        if t.contains("overview") || t.contains("summary of") { return true }
        if t.count > 160 { return true }
        let words = t.split(separator: " ").count
        return words > 18
    }

    private static func attemptNarrowRewrite(
        trimmed: String,
        compare: ExchangeProviderInquiryCompareResult?
    ) -> String? {
        guard let compare, compare.answerableFromOffer else { return nil }
        let answers = compare.knownAnswers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let first = answers.first else { return nil }
        guard isNarrowAsk(compare.requesterAsk) else { return nil }
        if first.count <= 280, first.count >= 3 {
            return first
        }
        return nil
    }

    private static func isNarrowAsk(_ ask: String?) -> Bool {
        guard let ask else { return false }
        let t = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        if t.count > 200 { return false }
        let words = t.split(separator: " ").count
        return words <= 22
    }

    #if DEBUG
    public static func debugLogValidation(
        threadID: UUID,
        outcome: Outcome,
        before: String
    ) {
        let valid = outcome.allowsCompareFirstDirectSend
        let viol = outcome.violations.joined(separator: "|")
        let beforePrefix = String(before.prefix(120))
        let afterPrefix = String(outcome.body.prefix(120))
        let roleReversal = outcome.violations.filter { $0.hasPrefix("role_reversal_") }
        if !roleReversal.isEmpty {
            Swift.print(
                "[ProviderDraftReplyValidation] thread=\(threadID.uuidString) roleReversalWarnings=\(roleReversal.joined(separator: ","))"
            )
        }
        Swift.print(
            "[ProviderDraftReplyValidation] thread=\(threadID.uuidString) valid=\(valid) violations=\(viol) action=\(outcome.action) beforePrefix=\(beforePrefix) afterPrefix=\(afterPrefix)"
        )
    }
    #endif
}
