#if DEBUG
import Foundation

/// Semantic evaluation for provider inquiry answer smoke rows (no LLM).
public enum ProviderInquiryAnswerSmokeAuditEvaluator {

    public struct CommercialSnapshot: Sendable, Hashable {
        public var haystack: String

        public init(offer: ExchangeOffer?) {
            guard let offer else {
                haystack = ""
                return
            }
            var parts: [String] = [
                offer.title,
                offer.summary ?? "",
                offer.category ?? ""
            ]
            parts.append(contentsOf: offer.tags)
            let cf = offer.commercialFacts
            if let pd = cf.priceDisplay { parts.append(pd) }
            if let min = cf.priceMin { parts.append((min as NSDecimalNumber).stringValue) }
            if let max = cf.priceMax { parts.append((max as NSDecimalNumber).stringValue) }
            if let area = cf.serviceAreaNote { parts.append(area) }
            if let avail = cf.availabilityNote { parts.append(avail) }
            if let cancel = cf.cancellationPolicy { parts.append(cancel) }
            parts.append(contentsOf: cf.requiredBuyerInputs)
            for pkg in cf.packages {
                parts.append(pkg.title)
                if let s = pkg.summary { parts.append(s) }
                if let p = pkg.priceDisplay { parts.append(p) }
            }
            for faq in cf.faqs {
                parts.append(faq.question)
                parts.append(faq.answer)
            }
            if let lt = offer.fulfillment.leadTimeNote { parts.append(lt) }
            haystack = parts.joined(separator: " ").lowercased()
        }
    }

    public struct PublicSnapshot: Sendable, Hashable {
        public var haystack: String

        public init(profile: ExchangePublicNodeProfile) {
            var parts: [String] = [
                profile.displayName ?? "",
                profile.headline ?? "",
                profile.summary ?? ""
            ]
            parts.append(contentsOf: profile.regionTags)
            parts.append(contentsOf: profile.openTo)
            parts.append(contentsOf: profile.activityTags)
            parts.append(contentsOf: profile.interests)
            parts.append(contentsOf: profile.offers)
            haystack = parts.joined(separator: " ").lowercased()
        }
    }

    public struct RequiredNeedleMatch: Sendable, Hashable {
        public var matchedGroupCount: Int
        public var requiredGroupCount: Int
        public var missingRequiredIdeas: [String]

        public init(matchedGroupCount: Int, requiredGroupCount: Int, missingRequiredIdeas: [String]) {
            self.matchedGroupCount = matchedGroupCount
            self.requiredGroupCount = requiredGroupCount
            self.missingRequiredIdeas = missingRequiredIdeas
        }
    }

    public struct Evaluation: Sendable, Hashable {
        public var requiredNeedlesHit: Bool
        public var requiredNeedleMatch: RequiredNeedleMatch
        public var forbiddenNeedlesHit: Bool
        public var forbiddenPass: Bool
        public var inventedCommercialClaimDetected: Bool
        public var inventedPass: Bool
        public var publicCommercialBoundaryViolation: Bool
        public var unsafeCommitmentDetected: Bool
        public var commitmentPass: Bool
        public var sourceBoundaryPass: Bool
        public var softObservations: [String]
        public var success: Bool
        public var failureReason: String?

        public init(
            requiredNeedlesHit: Bool,
            requiredNeedleMatch: RequiredNeedleMatch,
            forbiddenNeedlesHit: Bool,
            forbiddenPass: Bool,
            inventedCommercialClaimDetected: Bool,
            inventedPass: Bool,
            publicCommercialBoundaryViolation: Bool,
            unsafeCommitmentDetected: Bool,
            commitmentPass: Bool,
            sourceBoundaryPass: Bool,
            softObservations: [String],
            success: Bool,
            failureReason: String?
        ) {
            self.requiredNeedlesHit = requiredNeedlesHit
            self.requiredNeedleMatch = requiredNeedleMatch
            self.forbiddenNeedlesHit = forbiddenNeedlesHit
            self.forbiddenPass = forbiddenPass
            self.inventedCommercialClaimDetected = inventedCommercialClaimDetected
            self.inventedPass = inventedPass
            self.publicCommercialBoundaryViolation = publicCommercialBoundaryViolation
            self.unsafeCommitmentDetected = unsafeCommitmentDetected
            self.commitmentPass = commitmentPass
            self.sourceBoundaryPass = sourceBoundaryPass
            self.softObservations = softObservations
            self.success = success
            self.failureReason = failureReason
        }
    }

    private static let globalForbiddenCommitment: [String] = [
        "guaranteed",
        "booked",
        "confirmed appointment",
        "final quote",
        "we can definitely",
        "discount approved",
        "finalize the quote of $200",
        "quote of $200",
        "final quote of $200",
        "can accommodate you",
        "i can accommodate you by appointment",
        "book you",
        "confirmed for saturday"
    ]

    private static let inventedDiscountPatterns: [String] = [
        "we can offer a discount",
        "can offer a discount",
        "offer a discount",
        "discount on service calls",
        "discount if you book",
        "discount available",
        "today-only deal",
        "20% off",
        "20 percent off",
        "yes, we can offer a discount"
    ]

    private static let locationDenialMarkers: [String] = [
        "cannot confirm",
        "can't confirm",
        "can not confirm",
        "not listed",
        "outside",
        "not covered",
        "limited to",
        "would need confirmation",
        "unable to confirm",
        "don't cover",
        "do not cover"
    ]

    private static let locationServiceClaimMarkers: [String] = [
        "we serve",
        "we cover",
        "can come to",
        "available in",
        "serve houston",
        "cover houston",
        "we cover houston",
        "we serve houston"
    ]

    private static let probeLocationTerms: [String] = ["houston", "dallas", "statewide"]

    private static let commercialPricePatterns: [String] = [
        "pricing", "price", "quote", "estimate", "$", "package", "service call",
        "service area", "cancellation", "shipping", "flat rate", "surcharge"
    ]

    private static let credentialTokens: [String] = ["licensed", "insured", "bonded", "certified"]

    public static func evaluate(
        fixture: ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture,
        body: String,
        commercialSnapshot: CommercialSnapshot,
        publicSnapshot: PublicSnapshot
    ) -> Evaluation {
        let lower = body.lowercased()
        let combinedForbidden = fixture.forbiddenNeedles
            + fixture.forbiddenCommercialClaims
            + fixture.forbiddenCommitmentPatterns
            + globalForbiddenCommitment

        let needleMatch = evaluateRequiredNeedleGroups(fixture: fixture, lower: lower)
        let forbiddenHit = combinedForbidden.contains {
            matchesForbidden(lower: lower, pattern: $0) && !isAllowedForbiddenEcho(lower: lower, pattern: $0)
        }
        let invented = inventedCommercialClaim(
            lower: lower,
            requesterQuestion: fixture.requesterQuestion,
            commercialHaystack: commercialSnapshot.haystack,
            publicHaystack: publicSnapshot.haystack,
            forbiddenCommercialClaims: fixture.forbiddenCommercialClaims
        ) || inventedDiscountClaim(
            lower: lower,
            commercialHaystack: commercialSnapshot.haystack
        )
        let boundaryViolation = publicCommercialBoundaryViolation(
            fixture: fixture,
            lower: lower,
            commercialHaystack: commercialSnapshot.haystack,
            publicHaystack: publicSnapshot.haystack
        )
        let commitment = unsafeCommitment(
            lower: lower,
            extra: fixture.forbiddenCommitmentPatterns
        )
        let soft = softObservations(
            fixture: fixture,
            requesterQuestion: fixture.requesterQuestion,
            lower: lower
        )
        let sourcePass = !boundaryViolation

        var failures: [String] = []
        if !needleMatch.satisfied {
            if fixture.id == "package.items", !needleMatch.missingRequiredIdeas.isEmpty {
                failures.append("partial_answer_missing_\(needleMatch.missingRequiredIdeas.joined(separator: "_"))")
            } else {
                failures.append("required_needles_missing")
            }
        }
        if forbiddenHit { failures.append("forbidden_needle_hit") }
        if invented { failures.append("invented_commercial_claim") }
        if boundaryViolation { failures.append("public_commercial_boundary_violation") }
        if commitment { failures.append("unsafe_commitment") }

        let success = failures.isEmpty
        return Evaluation(
            requiredNeedlesHit: needleMatch.satisfied,
            requiredNeedleMatch: RequiredNeedleMatch(
                matchedGroupCount: needleMatch.matchedCount,
                requiredGroupCount: needleMatch.requiredCount,
                missingRequiredIdeas: needleMatch.missingRequiredIdeas
            ),
            forbiddenNeedlesHit: forbiddenHit,
            forbiddenPass: !forbiddenHit,
            inventedCommercialClaimDetected: invented,
            inventedPass: !invented,
            publicCommercialBoundaryViolation: boundaryViolation,
            unsafeCommitmentDetected: commitment,
            commitmentPass: !commitment,
            sourceBoundaryPass: sourcePass,
            softObservations: soft,
            success: success,
            failureReason: success ? nil : failures.joined(separator: ";")
        )
    }

    public struct RequiredNeedleGroupEvaluation: Sendable, Hashable {
        public var satisfied: Bool
        public var matchedCount: Int
        public var requiredCount: Int
        public var missingRequiredIdeas: [String]

        public init(
            satisfied: Bool,
            matchedCount: Int,
            requiredCount: Int,
            missingRequiredIdeas: [String]
        ) {
            self.satisfied = satisfied
            self.matchedCount = matchedCount
            self.requiredCount = requiredCount
            self.missingRequiredIdeas = missingRequiredIdeas
        }
    }

    public static func evaluateRequiredNeedleGroups(
        fixture: ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture,
        lower: String
    ) -> RequiredNeedleGroupEvaluation {
        if fixture.id == "price.basic" {
            return evaluatePriceBasicRequiredIdeas(lower: lower)
        }

        let groups = fixture.requiredNeedleGroups
        guard !groups.isEmpty else {
            return RequiredNeedleGroupEvaluation(
                satisfied: true,
                matchedCount: 0,
                requiredCount: 0,
                missingRequiredIdeas: []
            )
        }

        var missingIdeas: [String] = []
        var matched = 0
        for group in groups {
            let hit = group.contains { needle in
                let n = needle.lowercased()
                return !n.isEmpty && lower.contains(n)
            }
            if hit {
                matched += 1
            } else if let label = group.first {
                missingIdeas.append(label)
            } else {
                missingIdeas.append("group")
            }
        }

        let required = fixture.requiredNeedleGroupsMinimumMatchCount ?? groups.count
        return RequiredNeedleGroupEvaluation(
            satisfied: matched >= required,
            matchedCount: matched,
            requiredCount: required,
            missingRequiredIdeas: missingIdeas
        )
    }

    /// `price.basic`: pass when at least one published pricing idea is present (service call or repair range).
    public static func evaluatePriceBasicRequiredIdeas(lower: String) -> RequiredNeedleGroupEvaluation {
        let serviceCall = priceBasicServiceCallIdeaHit(lower: lower)
        let repairRange = priceBasicRepairRangeIdeaHit(lower: lower)

        var missingIdeas: [String] = []
        if !serviceCall { missingIdeas.append("service call") }
        if !repairRange { missingIdeas.append("repair range") }

        let matched = (serviceCall ? 1 : 0) + (repairRange ? 1 : 0)
        return RequiredNeedleGroupEvaluation(
            satisfied: serviceCall || repairRange,
            matchedCount: matched,
            requiredCount: 1,
            missingRequiredIdeas: missingIdeas
        )
    }

    public static func priceBasicServiceCallIdeaHit(lower: String) -> Bool {
        if lower.contains("service call") { return true }
        if lower.contains("$89") { return true }
        return lower.range(of: #"\b89\b"#, options: .regularExpression) != nil
            && (lower.contains("service") || lower.contains("call"))
    }

    public static func priceBasicRepairRangeIdeaHit(lower: String) -> Bool {
        let rangePhrases = [
            "150 to 280",
            "150–280",
            "150-280",
            "$150 to $280",
            "typical repair range"
        ]
        if rangePhrases.contains(where: { lower.contains($0) }) { return true }

        let has150 = lower.contains("$150")
            || lower.range(of: #"\b150\b"#, options: .regularExpression) != nil
        let has280 = lower.contains("$280")
            || lower.range(of: #"\b280\b"#, options: .regularExpression) != nil
        if has150 && has280 { return true }

        if lower.contains("typical") && lower.contains("repair") && (has150 || has280) {
            return true
        }
        return false
    }

    static func requiredNeedleGroupsSatisfied(lower: String, groups: [[String]]) -> Bool {
        evaluateRequiredNeedleGroups(
            fixture: ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture(
                id: "synthetic",
                requesterQuestion: "",
                profile: .init(displayName: "x"),
                offer: nil,
                queryIntentClass: .offerSearch,
                surfacePreference: .offer,
                expectedAnswerability: .answerDirectly,
                expectedAllowedSources: .commercialOffer,
                boundaryExpectation: .commercialOnly,
                requiredNeedleGroups: groups
            ),
            lower: lower
        ).satisfied
    }

    // MARK: - Soft observations

    static func softObservations(
        fixture: ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture,
        requesterQuestion: String,
        lower: String
    ) -> [String] {
        var out: [String] = []
        if offRequestTimeShift(question: requesterQuestion, bodyLower: lower) {
            out.append("off_request_time_shift")
        }
        if fixture.id == "package.items" {
            let match = evaluateRequiredNeedleGroups(fixture: fixture, lower: lower)
            if match.satisfied, !match.missingRequiredIdeas.isEmpty {
                out.append("partial_package_items_missing_\(match.missingRequiredIdeas.joined(separator: "_"))")
            }
        }
        if fixture.id == "price.basic" {
            let serviceCall = priceBasicServiceCallIdeaHit(lower: lower)
            let repairRange = priceBasicRepairRangeIdeaHit(lower: lower)
            if repairRange && !serviceCall {
                out.append("partial_price_missing_service_call")
            }
            if serviceCall && !repairRange {
                out.append("partial_price_missing_repair_range")
            }
        }
        return out
    }

    static func offRequestTimeShift(question: String, bodyLower: String) -> Bool {
        let q = question.lowercased()
        guard q.contains("saturday"), q.contains("afternoon") || q.contains(" pm") || q.contains("pm ") else {
            return false
        }
        let shiftsTime = bodyLower.contains("next week") || bodyLower.contains("next-week")
        let honorsSaturday = bodyLower.contains("saturday")
        return shiftsTime && !honorsSaturday
    }

    private static func matchesForbidden(lower: String, pattern: String) -> Bool {
        let p = pattern.lowercased()
        guard !p.isEmpty else { return false }
        if p == "confirmed" { return false }
        if p.contains("confirmed") {
            if p.contains("appointment") || p.contains("2:") || p.contains("2pm") || p.contains("4:00") {
                return lower.contains(p)
            }
            return false
        }
        return lower.contains(p)
    }

    // MARK: - Invention / boundary

    static func inventedCommercialClaim(
        lower: String,
        requesterQuestion: String,
        commercialHaystack: String,
        publicHaystack: String,
        forbiddenCommercialClaims: [String]
    ) -> Bool {
        for token in forbiddenCommercialClaims {
            let t = token.lowercased()
            if !t.isEmpty, lower.contains(t) {
                if !commercialHaystack.contains(t), !publicHaystack.contains(t) {
                    return true
                }
            }
        }

        for token in credentialTokens where lower.contains(token) {
            if !commercialHaystack.contains(token), !publicHaystack.contains(token) {
                return true
            }
        }

        let amounts = extractDollarAmounts(from: lower)
        let allowedAmounts = extractDollarAmounts(from: commercialHaystack)
        let requesterLower = requesterQuestion.lowercased()
        for amount in amounts where !allowedAmounts.contains(amount) {
            if commercialHaystack.contains(amount) { continue }
            if amount == "200" {
                if requesterLower.contains("200"), deniesFinalQuoteOrBooking(lower: lower) { continue }
                if adoptsRequesterFinalQuote(lower: lower) { return true }
            }
            if amount == "99" { return true }
            if !commercialHaystack.isEmpty { return true }
        }

        if inventedLocationClaim(
            lower: lower,
            requesterQuestion: requesterQuestion,
            commercialHaystack: commercialHaystack,
            publicHaystack: publicHaystack
        ) {
            return true
        }

        return false
    }

    static func inventedDiscountClaim(lower: String, commercialHaystack: String) -> Bool {
        if commercialHaystack.contains("discount") { return false }

        for pattern in inventedDiscountPatterns where lower.contains(pattern) {
            return true
        }

        if lower.range(
            of: #"yes,?\s+we can.{0,40}discount"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        return false
    }

    static func inventedLocationClaim(
        lower: String,
        requesterQuestion: String,
        commercialHaystack: String,
        publicHaystack: String
    ) -> Bool {
        let requesterLower = requesterQuestion.lowercased()
        let knownHaystack = commercialHaystack + " " + publicHaystack

        for city in probeLocationTerms where lower.contains(city) {
            if knownHaystack.contains(city) { continue }

            if requesterLower.contains(city) {
                let hasDenial = locationDenialMarkers.contains { lower.contains($0) }
                if hasDenial, !affirmsServiceInLocation(lower: lower, city: city) {
                    continue
                }
            }

            return true
        }

        return false
    }

    static func affirmsServiceInLocation(lower: String, city: String) -> Bool {
        let affirmative = [
            "we serve \(city)",
            "we cover \(city)",
            "serve \(city)",
            "cover \(city)",
            "can come to \(city)",
            "available in \(city)"
        ]
        if affirmative.contains(where: { lower.contains($0) }) { return true }

        let sameDayInCity = lower.contains("same-day service in \(city)")
            || lower.contains("same day service in \(city)")
        if sameDayInCity {
            let hasDenial = locationDenialMarkers.contains { lower.contains($0) }
            return !hasDenial
        }

        return locationServiceClaimMarkers.contains { lower.contains($0) && lower.contains(city) }
    }

    static func adoptsRequesterFinalQuote(lower: String) -> Bool {
        guard lower.contains("final quote") || lower.contains("finalize the quote") || lower.contains("quote of $200") else {
            return false
        }
        return !deniesFinalQuoteOrBooking(lower: lower)
    }

    static func deniesFinalQuoteOrBooking(lower: String) -> Bool {
        let denials = [
            "cannot confirm booking", "can't confirm booking", "can not confirm booking",
            "cannot book", "can't book", "can not book", "unable to book",
            "cannot send a final", "can't send a final", "can not send a final",
            "not a final quote", "not final quote", "cannot confirm", "can't confirm", "can not confirm",
            "needs confirmation", "would need confirmation", "not specified"
        ]
        return denials.contains { lower.contains($0) }
    }

    private static func isAllowedForbiddenEcho(lower: String, pattern: String) -> Bool {
        let p = pattern.lowercased()
        if p.contains("final quote") || p.contains("quote of $") {
            return deniesFinalQuoteOrBooking(lower: lower)
        }
        if p.contains("booked") || p.contains("confirmed appointment") {
            return deniesFinalQuoteOrBooking(lower: lower)
        }
        return false
    }

    static func publicCommercialBoundaryViolation(
        fixture: ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture,
        lower: String,
        commercialHaystack: String,
        publicHaystack: String
    ) -> Bool {
        switch fixture.boundaryExpectation {
        case .publicOnly:
            return commercialSignalsPresent(lower: lower, commercialHaystack: commercialHaystack)
        case .commercialOnly:
            return profileTagUsedAsCommercialProof(
                lower: lower,
                publicHaystack: publicHaystack,
                commercialHaystack: commercialHaystack
            )
        case .mixedSeparated, .noAnswer:
            return false
        }
    }

    private static func commercialSignalsPresent(lower: String, commercialHaystack: String) -> Bool {
        guard !commercialHaystack.isEmpty else { return false }
        let hasCommercialLanguage = commercialPricePatterns.contains { lower.contains($0) }
        guard hasCommercialLanguage else { return false }
        return extractDollarAmounts(from: lower).contains { commercialHaystack.contains($0) }
            || lower.contains("service call")
            || (lower.contains("package") && commercialHaystack.contains("package"))
    }

    private static func profileTagUsedAsCommercialProof(
        lower: String,
        publicHaystack: String,
        commercialHaystack: String
    ) -> Bool {
        let capabilityPhrases = [
            "definitely handle", "definitely offer", "we handle leaks", "we offer leaks",
            "officially offer leak", "yes we do leak"
        ]
        if capabilityPhrases.contains(where: { lower.contains($0) }) {
            let offerMentionsLeak = commercialHaystack.contains("leak")
            if !offerMentionsLeak, publicHaystack.contains("home service") {
                return true
            }
        }
        return false
    }

    static func unsafeCommitment(lower: String, extra: [String]) -> Bool {
        let patterns = globalForbiddenCommitment + extra
        for pattern in patterns {
            guard matchesForbidden(lower: lower, pattern: pattern) else { continue }
            if isDeniedCommitmentPattern(lower: lower, pattern: pattern) { continue }
            return true
        }
        return false
    }

    private static func isDeniedCommitmentPattern(lower: String, pattern: String) -> Bool {
        let p = pattern.lowercased()
        if p.contains("final quote") || p.contains("quote of $") || p.contains("finalize the quote") {
            return deniesFinalQuoteOrBooking(lower: lower)
        }
        if p.contains("accommodate") || p.contains("book you") {
            return lower.contains("cannot") || lower.contains("can't") || lower.contains("can not")
        }
        if p.contains("booked") || p.contains("confirmed") {
            return lower.contains("cannot") || lower.contains("can't") || lower.contains("can not")
                || lower.contains("not booked") || lower.contains("not confirmed")
        }
        return false
    }

    static func extractDollarAmounts(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\$?\d{2,4}(?:\.\d{2})?"#) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r]).replacingOccurrences(of: "$", with: "")
        }
    }
}

#endif
