import Foundation

// MARK: - Dimensions and tiers

public enum ProviderInboundDimension: String, Codable, Sendable, Hashable, CaseIterable {
    case discount
    case licenseInsurance
    case warranty
    case certification
    case exactSlot
    case booking
    case finalQuote
    case serviceArea
    case price
    case availability
    case serviceFit
    case policyTerms
    case other
}

public enum ProviderInboundRiskTier: String, Codable, Sendable, Hashable, Comparable {
    case lowFact
    case mediumScope
    case highClaim
    case commitment

    private var rank: Int {
        switch self {
        case .lowFact: return 0
        case .mediumScope: return 1
        case .highClaim: return 2
        case .commitment: return 3
        }
    }

    public static func < (lhs: ProviderInboundRiskTier, rhs: ProviderInboundRiskTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct ProviderInboundDimensionDetection: Sendable, Hashable {
    public var askedDimensions: [ProviderInboundDimension]
    public var riskTier: ProviderInboundRiskTier

    public init(askedDimensions: [ProviderInboundDimension], riskTier: ProviderInboundRiskTier) {
        self.askedDimensions = askedDimensions
        self.riskTier = riskTier
    }
}

// MARK: - Detector

/// Deterministic inbound dimension / risk detection from requester text (no LLM).
public enum ProviderInboundDimensionDetector: Sendable {

    public static func detect(requesterText: String) -> ProviderInboundDimensionDetection {
        let lower = requesterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else {
            return ProviderInboundDimensionDetection(askedDimensions: [.other], riskTier: .lowFact)
        }

        var dims: [ProviderInboundDimension] = []
        var tier: ProviderInboundRiskTier = .lowFact

        func add(_ d: ProviderInboundDimension, tier t: ProviderInboundRiskTier) {
            if !dims.contains(d) { dims.append(d) }
            if t > tier { tier = t }
        }

        if matchesDiscount(lower) { add(.discount, tier: .highClaim) }
        if matchesLicenseInsurance(lower) { add(.licenseInsurance, tier: .highClaim) }
        if matchesWarranty(lower) { add(.warranty, tier: .highClaim) }
        if matchesCertification(lower) { add(.certification, tier: .highClaim) }
        if matchesExactSlot(lower) { add(.exactSlot, tier: .mediumScope) }
        if matchesBooking(lower) { add(.booking, tier: .commitment) }
        if matchesFinalQuote(lower) { add(.finalQuote, tier: .commitment) }
        if matchesServiceArea(lower) { add(.serviceArea, tier: .mediumScope) }
        if matchesPrice(lower) { add(.price, tier: .lowFact) }
        if matchesAvailability(lower) { add(.availability, tier: .mediumScope) }
        if matchesServiceFit(lower) { add(.serviceFit, tier: .mediumScope) }
        if matchesPolicyTerms(lower) { add(.policyTerms, tier: .mediumScope) }

        if dims.isEmpty {
            dims = [.other]
        }

        return ProviderInboundDimensionDetection(askedDimensions: dims, riskTier: tier)
    }

    // MARK: - Patterns

    private static func matchesDiscount(_ lower: String) -> Bool {
        let needles = [
            "% off", "percent off", "discount", "special rate", "today-only", "today only",
            "deal if", "lower price if", "price break"
        ]
        return needles.contains(where: { lower.contains($0) })
    }

    private static func matchesLicenseInsurance(_ lower: String) -> Bool {
        let needles = [
            "licensed", "license", "insured", "insurance", "liability coverage",
            "bonded", "carry insurance"
        ]
        return needles.contains(where: { lower.contains($0) })
    }

    private static func matchesWarranty(_ lower: String) -> Bool {
        lower.contains("warranty") || lower.contains("guarantee on work") || lower.contains("work guarantee")
    }

    private static func matchesCertification(_ lower: String) -> Bool {
        let needles = ["certified", "certification", "accredited", "accreditation", "certificate"]
        return needles.contains(where: { lower.contains($0) })
    }

    private static func matchesExactSlot(_ lower: String) -> Bool {
        if lower.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil {
            return true
        }
        let needles = ["confirm ", "exact slot", "exact time", "specific time", "that window"]
        return needles.contains(where: { lower.contains($0) })
            && (lower.contains("saturday") || lower.contains("sunday") || lower.contains("weekend")
                || lower.contains("monday") || lower.contains("tuesday") || lower.contains("wednesday")
                || lower.contains("thursday") || lower.contains("friday") || lower.contains("pm")
                || lower.contains("am"))
    }

    private static func matchesBooking(_ lower: String) -> Bool {
        let needles = [
            "book me", "book for", "please book", "schedule me", "reserve", "hold the slot",
            "confirm booking", "set up an appointment"
        ]
        return needles.contains(where: { lower.contains($0) })
            || (lower.contains("book") && lower.contains("saturday"))
            || (lower.contains("book") && lower.contains("appointment"))
    }

    private static func matchesFinalQuote(_ lower: String) -> Bool {
        let needles = ["final quote", "binding quote", "firm quote", "quote of $", "send a quote of"]
        return needles.contains(where: { lower.contains($0) })
    }

    private static func matchesServiceArea(_ lower: String) -> Bool {
        let needles = [
            "service area", "come to", "travel to", "cover ", "serve ", "same day in",
            "work in ", "available in "
        ]
        return needles.contains(where: { lower.contains($0) })
    }

    private static func matchesPrice(_ lower: String) -> Bool {
        if lower.contains("$") { return true }
        let needles = ["how much", "what do you charge", "price", "pricing", "cost", "rate for", "quote for"]
        return needles.contains(where: { lower.contains($0) })
    }

    private static func matchesAvailability(_ lower: String) -> Bool {
        let needles = [
            "availability", "available", "when can", "lead time", "how soon", "timeline",
            "open slot", "next available"
        ]
        return needles.contains(where: { lower.contains($0) })
    }

    private static func matchesServiceFit(_ lower: String) -> Bool {
        let needles = [
            "do you do", "can you handle", "take on", "work on", "fit for", "within scope",
            "type of job", "kind of work"
        ]
        return needles.contains(where: { lower.contains($0) })
    }

    private static func matchesPolicyTerms(_ lower: String) -> Bool {
        let needles = ["cancellation", "cancel policy", "refund", "deposit policy", "terms and conditions"]
        return needles.contains(where: { lower.contains($0) })
    }
}
