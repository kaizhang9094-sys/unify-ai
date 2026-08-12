import Foundation

/// Deterministic consent/boundary normalization after `providerInquiryCompare` JSON.
public struct ProviderInquiryCompareGovernor: Sendable {
    public init() {}

    public struct BoundaryHints: Sendable, Hashable {
        public var isCustomPricing: Bool
        public var includesScheduleCommitment: Bool
        public var includesLegalCommercialCommitment: Bool
        public var includesSensitiveDisclosure: Bool
        public var isPolicyException: Bool

        public init(
            isCustomPricing: Bool = false,
            includesScheduleCommitment: Bool = false,
            includesLegalCommercialCommitment: Bool = false,
            includesSensitiveDisclosure: Bool = false,
            isPolicyException: Bool = false
        ) {
            self.isCustomPricing = isCustomPricing
            self.includesScheduleCommitment = includesScheduleCommitment
            self.includesLegalCommercialCommitment = includesLegalCommercialCommitment
            self.includesSensitiveDisclosure = includesSensitiveDisclosure
            self.isPolicyException = isPolicyException
        }
    }

    public enum NormalizedAction: String, Sendable, Hashable {
        case sendWithinConsent
        case askProviderInput
        case holdForBoundaryApproval
        case blocked
        case wait
    }

    /// Split of `compare.missingFacts` for send-within-consent gating: only **blocking** subsets should prevent auto-send.
    public struct MissingFactsClassification: Sendable, Hashable {
        public var explicitlyRequestedMissingFacts: [String]
        public var draftClaimedMissingFacts: [String]
        public var intentRequiredMissingFacts: [String]
        public var nonBlockingMissingFacts: [String]

        /// Union of explicit + draft-claimed + intent-required (deduped, stable order).
        public var blockingMissingFactsForSend: [String] {
            var seen = Set<String>()
            var out: [String] = []
            for row in explicitlyRequestedMissingFacts + draftClaimedMissingFacts + intentRequiredMissingFacts {
                let t = row.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { continue }
                if seen.insert(t.lowercased()).inserted {
                    out.append(t)
                }
            }
            return out
        }

        public init(
            explicitlyRequestedMissingFacts: [String] = [],
            draftClaimedMissingFacts: [String] = [],
            intentRequiredMissingFacts: [String] = [],
            nonBlockingMissingFacts: [String] = []
        ) {
            self.explicitlyRequestedMissingFacts = explicitlyRequestedMissingFacts
            self.draftClaimedMissingFacts = draftClaimedMissingFacts
            self.intentRequiredMissingFacts = intentRequiredMissingFacts
            self.nonBlockingMissingFacts = nonBlockingMissingFacts
        }
    }

    public struct Outcome: Sendable, Hashable {
        public var normalizedAction: NormalizedAction
        /// Compare with draft cleared when unsafe to emit.
        public var clampedCompare: ExchangeProviderInquiryCompareResult
        public var downgradeReason: String?
        public var missingFactsClassification: MissingFactsClassification?

        public init(
            normalizedAction: NormalizedAction,
            clampedCompare: ExchangeProviderInquiryCompareResult,
            downgradeReason: String? = nil,
            missingFactsClassification: MissingFactsClassification? = nil
        ) {
            self.normalizedAction = normalizedAction
            self.clampedCompare = clampedCompare
            self.downgradeReason = downgradeReason
            self.missingFactsClassification = missingFactsClassification
        }
    }

    /// Automation permission lanes copied from seller toggles (`ExchangeOffer.AutoAnswerPolicy` / `permissionOnlyAutoAnswerPolicy()`).
    public struct PermissionPolicy: Sendable, Hashable {
        public var canAnswerPricing: Bool
        public var canAnswerAvailability: Bool
        public var canAnswerPolicies: Bool
        public var canAnswerServiceArea: Bool
        public var canAnswerFAQs: Bool

        public init(
            canAnswerPricing: Bool,
            canAnswerAvailability: Bool,
            canAnswerPolicies: Bool,
            canAnswerServiceArea: Bool,
            canAnswerFAQs: Bool
        ) {
            self.canAnswerPricing = canAnswerPricing
            self.canAnswerAvailability = canAnswerAvailability
            self.canAnswerPolicies = canAnswerPolicies
            self.canAnswerServiceArea = canAnswerServiceArea
            self.canAnswerFAQs = canAnswerFAQs
        }
    }

    /// Classifies each `compare.missingFacts` line for whether it should block `sendWithinConsent` auto-send.
    public static func classifyMissingFacts(compare: ExchangeProviderInquiryCompareResult) -> MissingFactsClassification {
        let requesterPool = requesterTextPool(from: compare)
        let draft = compare.draftReply?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let intentCat = compare.intentCategory?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let broad = isBroadGeneralInquiry(requesterPool)

        var explicit: [String] = []
        var draftClaimed: [String] = []
        var intentReq: [String] = []
        var nonBlocking: [String] = []

        let caveatAnswerable = compare.answerableFromOffer && !compare.needsProviderInput

        for raw in compare.missingFacts {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if caveatAnswerable, isPrecisionGapMissingFact(line: line) {
                nonBlocking.append(line)
                continue
            }

            if explicitlyRequestedMissingFact(line: line, requesterPoolLowercased: requesterPool, broadGeneralAsk: broad) {
                explicit.append(line)
            } else if draftClaimsMissingFact(line: line, draftLowercased: draft) {
                draftClaimed.append(line)
            } else if intentRequiredMissingFact(line: line, intentCategoryLowercased: intentCat) {
                intentReq.append(line)
            } else {
                nonBlocking.append(line)
            }
        }

        return MissingFactsClassification(
            explicitlyRequestedMissingFacts: explicit,
            draftClaimedMissingFacts: draftClaimed,
            intentRequiredMissingFacts: intentReq,
            nonBlockingMissingFacts: nonBlocking
        )
    }

    public func evaluate(
        compare: ExchangeProviderInquiryCompareResult,
        permissionPolicy: PermissionPolicy?,
        boundaryHints: BoundaryHints
    ) -> Outcome {
        let classification = Self.classifyMissingFacts(compare: compare)
        let blockingMissingForSend = classification.blockingMissingFactsForSend

        var working = compare
        var downgrade: String?

        let parsed = parseModelDisposition(compare.recommendedDisposition)
        var action = parsed ?? inferFromLegacyFields(compare)

        let legacyGroundingBlock = compare.needsProviderInput || !compare.answerableFromOffer
        let blockingMissingFactsSend = !blockingMissingForSend.isEmpty
        let hasBlockingGroundingIssue = legacyGroundingBlock || blockingMissingFactsSend

        if compare.requiresBoundaryApproval == true, !hasBlockingGroundingIssue {
            action = .holdForBoundaryApproval
            downgrade = "model_requires_boundary_approval"
        }

        if compare.canSendWithinConsent == false, action == .sendWithinConsent {
            action = .askProviderInput
            downgrade = (downgrade.map { $0 + "; " } ?? "") + "model_canSendWithinConsent_false"
        }

        let hasSnapshotBoundary =
            boundaryHints.isCustomPricing
            || boundaryHints.includesScheduleCommitment
            || boundaryHints.includesLegalCommercialCommitment
            || boundaryHints.includesSensitiveDisclosure
            || boundaryHints.isPolicyException

        // Never route missing facts to approval buckets.
        if action == .holdForBoundaryApproval, hasBlockingGroundingIssue {
            action = .askProviderInput
            downgrade = "downgrade_hold_to_ask_missing_facts"
        }

        if action == .sendWithinConsent {
            if legacyGroundingBlock {
                action = .askProviderInput
                downgrade = (downgrade.map { $0 + "; " } ?? "") + "downgrade_send_to_ask_needs_provider_or_unanswerable"
            } else if blockingMissingFactsSend {
                action = .askProviderInput
                downgrade = (downgrade.map { $0 + "; " } ?? "") + downgradeBlockingMissingFactsReason(classification: classification)
            } else if hasSnapshotBoundary {
                action = .holdForBoundaryApproval
                downgrade = "downgrade_send_to_hold_snapshot_boundary"
            } else if !consentAllowsSend(policy: permissionPolicy, compare: compare) {
                action = .askProviderInput
                downgrade = "downgrade_send_to_ask_policy"
            } else if working.draftReply == nil || (working.draftReply?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) {
                action = .askProviderInput
                downgrade = "downgrade_send_to_ask_no_draft"
            }
        }

        if action == .holdForBoundaryApproval, hasBlockingGroundingIssue {
            action = .askProviderInput
            downgrade = (downgrade.map { $0 + "; " } ?? "") + "hold_overridden_by_missing_facts"
        }

        var draft = working.draftReply
        if action != .sendWithinConsent {
            draft = nil
        }

        working.draftReply = draft
        working.needsProviderInput = action == .askProviderInput || action == .wait
        if action == .blocked {
            working.answerableFromOffer = false
            working.needsProviderInput = false
        }

        // Downstream compare-first gates key off `missingFacts.isEmpty`; keep only blocking lines (or empty) when sending.
        if action == .sendWithinConsent {
            working.missingFacts = blockingMissingForSend
        }

        return Outcome(
            normalizedAction: action,
            clampedCompare: working,
            downgradeReason: downgrade,
            missingFactsClassification: classification
        )
    }

    private func downgradeBlockingMissingFactsReason(classification: MissingFactsClassification) -> String {
        var parts: [String] = []
        if !classification.explicitlyRequestedMissingFacts.isEmpty {
            parts.append("explicit=\(classification.explicitlyRequestedMissingFacts.count)")
        }
        if !classification.draftClaimedMissingFacts.isEmpty {
            parts.append("draftClaimed=\(classification.draftClaimedMissingFacts.count)")
        }
        if !classification.intentRequiredMissingFacts.isEmpty {
            parts.append("intentRequired=\(classification.intentRequiredMissingFacts.count)")
        }
        let detail = parts.isEmpty ? "unknown" : parts.joined(separator: ",")
        return "downgrade_send_to_ask_blocking_missing(\(detail))"
    }

    private static func requesterTextPool(from compare: ExchangeProviderInquiryCompareResult) -> String {
        let ask = compare.requesterAsk?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = compare.inquirySummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (ask + " " + summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Broad, non-specific follow-ups should not treat unrelated `missingFacts` lines as blocking.
    private static func isBroadGeneralInquiry(_ requesterLowercased: String) -> Bool {
        let r = requesterLowercased
        if r.isEmpty { return false }
        let needles = [
            "tell me more",
            "more about",
            "more details",
            "more information",
            "any details",
            "any more",
            "what else",
            "anything else",
            "learn more",
            "like to know more",
            "would love to know",
            "curious about",
            "interested in hearing",
            "general question",
            "quick question"
        ]
        return needles.contains { r.contains($0) }
    }

    private static func explicitlyRequestedMissingFact(
        line: String,
        requesterPoolLowercased: String,
        broadGeneralAsk: Bool
    ) -> Bool {
        let m = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !m.isEmpty, m.count >= 4 else { return false }
        if requesterPoolLowercased.isEmpty { return false }

        if requesterPoolLowercased.contains(m) { return true }

        let significantTokens = tokenizeForOverlap(m).filter { $0.count >= 4 }
        guard !significantTokens.isEmpty else { return false }

        if broadGeneralAsk {
            let hits = significantTokens.filter { requesterPoolLowercased.contains($0) }
            return hits.count >= 2
        }

        let hits = significantTokens.filter { requesterPoolLowercased.contains($0) }
        let need = max(1, (significantTokens.count + 1) / 2)
        return hits.count >= need
    }

    private static func draftClaimsMissingFact(line: String, draftLowercased: String) -> Bool {
        guard !draftLowercased.isEmpty else { return false }
        let m = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard m.count >= 4 else { return false }
        if draftLowercased.contains(m) { return true }
        let tokens = tokenizeForOverlap(m).filter { $0.count >= 5 }
        return tokens.contains { draftLowercased.contains($0) }
    }

    private static func intentRequiredMissingFact(line: String, intentCategoryLowercased: String) -> Bool {
        let cat = intentCategoryLowercased
        if cat.isEmpty { return false }
        let m = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if cat.contains("pric") || cat.contains("quote") || cat.contains("cost") || cat.contains("fee") {
            let pricingSignals = [
                "price", "pricing", "cost", "fee", "fees", "rent", "deposit", "down payment", "mortgage",
                "hoa", "tax", "taxes", "insurance", "premium", "rate", "payment", "financ", "loan", "apr"
            ]
            return pricingSignals.contains { m.contains($0) }
        }

        if cat.contains("schedul") || cat.contains("availab") || cat.contains("book") {
            let schedSignals = ["date", "time", "slot", "calendar", "appointment", "schedule", "availability", "tour", "showing"]
            return schedSignals.contains { m.contains($0) }
        }

        if cat.contains("policy") || cat.contains("cancel") || cat.contains("refund") || cat.contains("warranty") {
            let polSignals = ["policy", "policies", "cancel", "cancellation", "refund", "warranty", "terms", "contract", "agreement"]
            return polSignals.contains { m.contains($0) }
        }

        return false
    }

    private static func tokenizeForOverlap(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Finer timing precision the model may list in `missingFacts` without blocking a caveated commercial reply.
    private static func isPrecisionGapMissingFact(line: String) -> Bool {
        let m = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !m.isEmpty else { return false }

        let precisionSignals = [
            "exact ", "specific ", "precise ", "finer ", "precise timing", "precision gap",
            "exact slot", "exact time", "exact date", "exact start", "exact appointment",
            "specific slot", "specific time", "specific date", "specific start",
            "time slot", "start date", "start time", "appointment time", "calendar slot"
        ]
        if precisionSignals.contains(where: { m.contains($0) }) { return true }

        if m.hasPrefix("exact ") || m.hasPrefix("specific ") {
            let timingTokens = ["slot", "time", "date", "start", "appointment", "schedule", "availability", "timing"]
            return timingTokens.contains { m.contains($0) }
        }

        return false
    }

    private func consentAllowsSend(
        policy: PermissionPolicy?,
        compare: ExchangeProviderInquiryCompareResult
    ) -> Bool {
        guard let policy else { return false }

        let cat = compare.intentCategory?.lowercased() ?? ""
        let pricingLike = cat.contains("pric") || cat.contains("quote") || cat.contains("cost")
        let availLike = cat.contains("schedul") || cat.contains("availab") || cat.contains("book")
        let policyLike = cat.contains("policy") || cat.contains("cancel") || cat.contains("refund") || cat.contains("warranty")
        let areaLike = cat.contains("area") || cat.contains("location") || cat.contains("service")
        let faqLike = cat.contains("faq") || cat.contains("question")

        if pricingLike { return policy.canAnswerPricing }
        if availLike { return policy.canAnswerAvailability }
        if policyLike { return policy.canAnswerPolicies }
        if areaLike { return policy.canAnswerServiceArea }
        if faqLike { return policy.canAnswerFAQs }

        // Unknown intent category: allow only when model marked answerable and policy has at least one lane open.
        return compare.answerableFromOffer && (
            policy.canAnswerPricing || policy.canAnswerAvailability || policy.canAnswerPolicies
                || policy.canAnswerServiceArea || policy.canAnswerFAQs
        )
    }

    private func parseModelDisposition(_ raw: String?) -> NormalizedAction? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let n = normalizedDispositionKey(raw)
        switch n {
        case "sendwithinconsent", "send", "autosend", "safe_send":
            return .sendWithinConsent
        case "askproviderinput", "ask", "clarify", "needsinput", "preparebuthold", "prepare_but_hold":
            return .askProviderInput
        case "holdforboundaryapproval", "hold", "approval", "boundary":
            return .holdForBoundaryApproval
        case "blocked", "block", "reject":
            return .blocked
        case "wait", "pause", "defer":
            return .wait
        default:
            return nil
        }
    }

    private func normalizedDispositionKey(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func inferFromLegacyFields(_ compare: ExchangeProviderInquiryCompareResult) -> NormalizedAction {
        if compare.reason.lowercased().contains("provider_inquiry_compare_failed") {
            return .askProviderInput
        }
        if compare.needsProviderInput || !compare.answerableFromOffer {
            return .askProviderInput
        }
        return .sendWithinConsent
    }
}
