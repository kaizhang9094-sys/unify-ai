import Foundation

// MARK: - Input

public struct ProviderInboundClaimPolicyInput: Sendable, Hashable {
    public var requesterText: String
    public var detection: ProviderInboundDimensionDetection
    public var allowedSurfaces: ProviderAllowedFactSurfaces
    public var applyFactSurfaceGating: Bool
    public var offer: ExchangeOffer?
    public var profile: ExchangePublicNodeProfile?
    public var sellerControlledFacts: String

    public init(
        requesterText: String,
        detection: ProviderInboundDimensionDetection,
        allowedSurfaces: ProviderAllowedFactSurfaces,
        applyFactSurfaceGating: Bool,
        offer: ExchangeOffer?,
        profile: ExchangePublicNodeProfile?,
        sellerControlledFacts: String
    ) {
        self.requesterText = requesterText
        self.detection = detection
        self.allowedSurfaces = allowedSurfaces
        self.applyFactSurfaceGating = applyFactSurfaceGating
        self.offer = offer
        self.profile = profile
        self.sellerControlledFacts = sellerControlledFacts
    }
}

#if DEBUG
/// Haystack vs ledger-informed policy packet comparison (smoke audit / promotion checks).
public struct ProviderClaimLedgerPolicyComparison: Codable, Sendable, Hashable {
    public var detectedDimensions: [String]
    public var oldAllowed: String
    public var newAllowed: String
    public var oldMissing: String
    public var newMissing: String
    public var fallbackHaystackUsed: [String]
    public var disagreement: Bool

    public init(
        detectedDimensions: [String],
        oldAllowed: String,
        newAllowed: String,
        oldMissing: String,
        newMissing: String,
        fallbackHaystackUsed: [String],
        disagreement: Bool
    ) {
        self.detectedDimensions = detectedDimensions
        self.oldAllowed = oldAllowed
        self.newAllowed = newAllowed
        self.oldMissing = oldMissing
        self.newMissing = newMissing
        self.fallbackHaystackUsed = fallbackHaystackUsed
        self.disagreement = disagreement
    }
}
#endif

// MARK: - Engine (log-only)

/// Deterministic claim-boundary policy — computes packets for logging; does not alter compare or outbound yet.
public enum ProviderInboundClaimPolicyEngine: Sendable {

    /// Haystack/presence path (production packet until ledger path is promoted).
    public static func evaluateLogOnly(_ input: ProviderInboundClaimPolicyInput) -> ProviderClaimBoundaryPacket {
        evaluateHaystackPacket(input)
    }

    /// Ledger-informed evaluation for DEBUG comparison; returns the haystack packet (no production behavior change).
    public static func evaluateLogOnly(
        _ input: ProviderInboundClaimPolicyInput,
        ledger: ProviderClaimLedger
    ) -> ProviderClaimBoundaryPacket {
        #if DEBUG
        let compared = compareHaystackWithLedger(input, ledger: ledger)
        logLedgerPolicyIntegration(compared)
        return compared.haystackPacket
        #else
        return evaluateHaystackPacket(input)
        #endif
    }

    #if DEBUG
    /// Builds haystack + ledger packets and a disagreement summary without changing production return value.
    public static func compareHaystackWithLedger(
        _ input: ProviderInboundClaimPolicyInput,
        ledger: ProviderClaimLedger
    ) -> (haystackPacket: ProviderClaimBoundaryPacket, comparison: ProviderClaimLedgerPolicyComparison) {
        let haystackPacket = evaluateHaystackPacket(input)
        var fallbackHaystackUsed: [String] = []
        let ledgerPacket = evaluateLedgerInformedPacket(
            input: input,
            ledger: ledger,
            fallbackHaystackUsed: &fallbackHaystackUsed
        )
        let comparison = makePolicyComparison(
            input: input,
            haystackPacket: haystackPacket,
            ledgerPacket: ledgerPacket,
            fallbackHaystackUsed: fallbackHaystackUsed
        )
        return (haystackPacket, comparison)
    }
    #endif

    // MARK: - Haystack packet (legacy production)

    private static func evaluateHaystackPacket(_ input: ProviderInboundClaimPolicyInput) -> ProviderClaimBoundaryPacket {
        let dims = input.detection.askedDimensions
        let commercial = input.offer?.commercialFacts ?? .empty
        let offerFactsHaystack = offerCommercialHaystack(commercial: commercial, sellerControlledFacts: input.sellerControlledFacts)
        let requesterLower = input.requesterText.lowercased()

        var allowed: [ProviderAllowedClaim] = []
        var missing: [ProviderMissingClaim] = []
        var caveats: [String] = []
        var forbidden: [String] = []
        var untrusted: [String] = []
        var answerability: ProviderPolicyAnswerability = .answerDirectly
        var responseMode: ProviderResponseMode = .groundedAnswer
        var riskTier = input.detection.riskTier
        var commitmentBoundary: ExchangeCommitmentBoundary?

        if dims.contains(.booking) || dims.contains(.finalQuote) {
            applyCommitmentPolicy(
                input: input,
                commercial: commercial,
                offerFactsHaystack: offerFactsHaystack,
                allowed: &allowed,
                missing: &missing,
                forbidden: &forbidden,
                untrusted: &untrusted,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier,
                commitmentBoundary: &commitmentBoundary
            )
        }

        if dims.contains(.discount) {
            applyDiscountPolicy(
                commercial: commercial,
                offerFactsHaystack: offerFactsHaystack,
                requesterLower: requesterLower,
                allowed: &allowed,
                missing: &missing,
                forbidden: &forbidden,
                untrusted: &untrusted,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.licenseInsurance) {
            applyCredentialPolicy(
                dimension: .licenseInsurance,
                commercial: commercial,
                offerFactsHaystack: offerFactsHaystack,
                allowed: &allowed,
                missing: &missing,
                forbidden: &forbidden,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.certification) {
            applyCredentialPolicy(
                dimension: .certification,
                commercial: commercial,
                offerFactsHaystack: offerFactsHaystack,
                allowed: &allowed,
                missing: &missing,
                forbidden: &forbidden,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.warranty) {
            applyWarrantyPolicy(
                commercial: commercial,
                offerFactsHaystack: offerFactsHaystack,
                allowed: &allowed,
                missing: &missing,
                forbidden: &forbidden,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.exactSlot) {
            applyExactSlotPolicy(
                commercial: commercial,
                allowed: &allowed,
                missing: &missing,
                caveats: &caveats,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.serviceArea) {
            applyServiceAreaPolicy(
                input: input,
                commercial: commercial,
                requesterLower: requesterLower,
                allowed: &allowed,
                missing: &missing,
                caveats: &caveats,
                forbidden: &forbidden,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.price), commercial.hasAnyPublicPriceSignal {
            if let pd = commercial.priceDisplay?.trimmingCharacters(in: .whitespacesAndNewlines), !pd.isEmpty {
                allowed.append(
                    ProviderAllowedClaim(
                        factID: "offer.commercial.priceDisplay",
                        text: pd,
                        source: .offer
                    )
                )
            }
        }

        if dims.contains(.availability), let note = trim(commercial.availabilityNote) {
            allowed.append(
                ProviderAllowedClaim(
                    factID: "offer.commercial.availabilityNote",
                    text: note,
                    source: .offer
                )
            )
        }

        // High-risk dimensions: profile headline/summary are never credential evidence.
        if dims.contains(where: { [.licenseInsurance, .certification, .warranty, .discount].contains($0) }) {
            forbidden.append("profile_headline_as_credential_evidence")
            forbidden.append("profile_summary_as_credential_evidence")
        }

        dedupePacket(
            dims: dims,
            riskTier: &riskTier,
            allowed: &allowed,
            missing: &missing,
            caveats: &caveats,
            forbidden: &forbidden,
            untrusted: &untrusted,
            answerability: &answerability,
            responseMode: &responseMode
        )

        return ProviderClaimBoundaryPacket(
            responseMode: responseMode,
            riskTier: riskTier,
            askedDimensions: dims,
            allowedClaims: allowed,
            missingClaims: missing,
            requiredCaveats: caveats,
            forbiddenClaims: forbidden,
            requesterClaimsUntrusted: untrusted,
            answerabilityStatus: answerability,
            commitmentBoundary: commitmentBoundary
        )
    }

    // MARK: - Ledger-informed packet (Phase B; not used for production return yet)

    private static func evaluateLedgerInformedPacket(
        input: ProviderInboundClaimPolicyInput,
        ledger: ProviderClaimLedger,
        fallbackHaystackUsed: inout [String]
    ) -> ProviderClaimBoundaryPacket {
        let dims = input.detection.askedDimensions
        let commercial = input.offer?.commercialFacts ?? .empty
        let offerFactsHaystack = offerCommercialHaystack(
            commercial: commercial,
            sellerControlledFacts: input.sellerControlledFacts
        )
        let requesterLower = input.requesterText.lowercased()

        var allowed: [ProviderAllowedClaim] = []
        var missing: [ProviderMissingClaim] = []
        var caveats: [String] = []
        var forbidden: [String] = []
        var untrusted: [String] = []
        var answerability: ProviderPolicyAnswerability = .answerDirectly
        var responseMode: ProviderResponseMode = .groundedAnswer
        var riskTier = input.detection.riskTier
        var commitmentBoundary: ExchangeCommitmentBoundary?

        if dims.contains(.booking) || dims.contains(.finalQuote) {
            applyLedgerCommitmentPolicy(
                input: input,
                ledger: ledger,
                commercial: commercial,
                offerFactsHaystack: offerFactsHaystack,
                fallbackHaystackUsed: &fallbackHaystackUsed,
                allowed: &allowed,
                missing: &missing,
                forbidden: &forbidden,
                untrusted: &untrusted,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier,
                commitmentBoundary: &commitmentBoundary
            )
        }

        if dims.contains(.discount) {
            applyLedgerDiscountPolicy(
                ledger: ledger,
                requesterLower: requesterLower,
                allowed: &allowed,
                missing: &missing,
                forbidden: &forbidden,
                untrusted: &untrusted,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.licenseInsurance) {
            applyLedgerLicenseInsurancePolicy(
                ledger: ledger,
                allowed: &allowed,
                missing: &missing,
                forbidden: &forbidden,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.certification) {
            applyLedgerCertificationPolicy(
                ledger: ledger,
                allowed: &allowed,
                missing: &missing,
                forbidden: &forbidden,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.warranty) {
            applyLedgerWarrantyPolicy(
                ledger: ledger,
                allowed: &allowed,
                missing: &missing,
                forbidden: &forbidden,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.exactSlot) {
            applyLedgerExactSlotPolicy(
                ledger: ledger,
                fallbackHaystackUsed: &fallbackHaystackUsed,
                commercial: commercial,
                allowed: &allowed,
                missing: &missing,
                caveats: &caveats,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.serviceArea) {
            applyLedgerServiceAreaPolicy(
                input: input,
                ledger: ledger,
                commercial: commercial,
                requesterLower: requesterLower,
                fallbackHaystackUsed: &fallbackHaystackUsed,
                allowed: &allowed,
                missing: &missing,
                caveats: &caveats,
                forbidden: &forbidden,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(.price) {
            applyLedgerPricingPolicy(
                ledger: ledger,
                commercial: commercial,
                fallbackHaystackUsed: &fallbackHaystackUsed,
                allowed: &allowed
            )
        }

        if dims.contains(.availability) {
            applyLedgerAvailabilityPolicy(
                ledger: ledger,
                commercial: commercial,
                fallbackHaystackUsed: &fallbackHaystackUsed,
                allowed: &allowed
            )
        }

        if dims.contains(.policyTerms) {
            applyLedgerPolicyTermsPolicy(
                ledger: ledger,
                fallbackHaystackUsed: &fallbackHaystackUsed,
                commercial: commercial,
                allowed: &allowed,
                missing: &missing,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }

        if dims.contains(where: { [.licenseInsurance, .certification, .warranty, .discount].contains($0) }) {
            forbidden.append("profile_headline_as_credential_evidence")
            forbidden.append("profile_summary_as_credential_evidence")
        }

        dedupePacket(
            dims: dims,
            riskTier: &riskTier,
            allowed: &allowed,
            missing: &missing,
            caveats: &caveats,
            forbidden: &forbidden,
            untrusted: &untrusted,
            answerability: &answerability,
            responseMode: &responseMode
        )

        return ProviderClaimBoundaryPacket(
            responseMode: responseMode,
            riskTier: riskTier,
            askedDimensions: dims,
            allowedClaims: allowed,
            missingClaims: missing,
            requiredCaveats: caveats,
            forbiddenClaims: forbidden,
            requesterClaimsUntrusted: untrusted,
            answerabilityStatus: answerability,
            commitmentBoundary: commitmentBoundary
        )
    }

    // MARK: - Ledger scenario policies

    private static func applyLedgerLicenseInsurancePolicy(
        ledger: ProviderClaimLedger,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        forbidden: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        let licensed = ledger.entry(for: .licensed)
        let insured = ledger.entry(for: .insured)
        let tokens = ["licensed", "insured", "bonded", "liability insurance"]

        if let licensed, licensed.status == .present {
            allowed.append(allowedClaim(from: licensed))
        }
        if let insured, insured.status == .present {
            allowed.append(allowedClaim(from: insured))
        }

        let licensedMissing = licensed.map { $0.status != .present } ?? true
        let insuredMissing = insured.map { $0.status != .present } ?? true
        guard licensedMissing || insuredMissing else { return }

        missing.append(
            ProviderMissingClaim(
                dimension: .licenseInsurance,
                reason: ledgerCredentialMissingReason(licensed: licensed, insured: insured)
            )
        )
        forbidden.append(contentsOf: tokens)
        elevate(
            to: .notInOffer,
            mode: .askProviderInput,
            tier: .highClaim,
            answerability: &answerability,
            responseMode: &responseMode,
            riskTier: &riskTier
        )
    }

    private static func applyLedgerCertificationPolicy(
        ledger: ProviderClaimLedger,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        forbidden: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        let certified = ledger.entry(for: .certified)
        let tokens = ["certified", "certification", "accredited"]
        if let certified, certified.status == .present {
            allowed.append(allowedClaim(from: certified))
            return
        }
        missing.append(
            ProviderMissingClaim(
                dimension: .certification,
                reason: certified.map { "Ledger: \($0.sourceField) is \($0.status.rawValue)." }
                    ?? "Ledger: certification claim not available."
            )
        )
        forbidden.append(contentsOf: tokens)
        elevate(
            to: .notInOffer,
            mode: .askProviderInput,
            tier: .highClaim,
            answerability: &answerability,
            responseMode: &responseMode,
            riskTier: &riskTier
        )
    }

    private static func applyLedgerDiscountPolicy(
        ledger: ProviderClaimLedger,
        requesterLower: String,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        forbidden: inout [String],
        untrusted: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        let discount = ledger.entry(for: .discountOffered)
        if let discount, discount.status == .present {
            allowed.append(allowedClaim(from: discount))
            return
        }
        missing.append(
            ProviderMissingClaim(
                dimension: .discount,
                reason: discount.map { "Ledger: \($0.sourceField) is \($0.status.rawValue)." }
                    ?? "Ledger: no published discount claim."
            )
        )
        forbidden.append(contentsOf: ["20% off", "discount approved", "special rate confirmed", "today-only deal"])
        extractRequesterDiscountTerms(requesterLower).forEach { untrusted.append($0) }
        elevate(
            to: .needsProviderConfirmation,
            mode: .askProviderInput,
            tier: .highClaim,
            answerability: &answerability,
            responseMode: &responseMode,
            riskTier: &riskTier
        )
    }

    private static func applyLedgerWarrantyPolicy(
        ledger: ProviderClaimLedger,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        forbidden: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        let warranty = ledger.entry(for: .warrantyOrGuarantee)
        if let warranty, warranty.status == .present {
            allowed.append(allowedClaim(from: warranty))
            return
        }
        missing.append(
            ProviderMissingClaim(
                dimension: .warranty,
                reason: warranty.map { "Ledger: \($0.sourceField) is \($0.status.rawValue)." }
                    ?? "Ledger: warranty not published."
            )
        )
        forbidden.append(contentsOf: ["warranty included", "guaranteed warranty", "full warranty"])
        elevate(
            to: .notInOffer,
            mode: .askProviderInput,
            tier: .highClaim,
            answerability: &answerability,
            responseMode: &responseMode,
            riskTier: &riskTier
        )
    }

    private static func applyLedgerExactSlotPolicy(
        ledger: ProviderClaimLedger,
        fallbackHaystackUsed: inout [String],
        commercial: ExchangeOffer.CommercialFacts,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        caveats: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        guard let availability = ledger.entry(for: .availability),
              let exactSlot = ledger.entry(for: .exactAvailabilitySlot) else {
            fallbackHaystackUsed.append("exactSlot")
            applyExactSlotPolicy(
                commercial: commercial,
                allowed: &allowed,
                missing: &missing,
                caveats: &caveats,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
            return
        }

        if availability.status == .present, availability.sourceValuePreview != nil {
            allowed.append(allowedClaim(from: availability))
            missing.append(
                ProviderMissingClaim(
                    dimension: .exactSlot,
                    reason: "Ledger: \(exactSlot.sourceField) is \(exactSlot.status.rawValue); general availability only."
                )
            )
            caveats.append("State published general availability and that exact timing needs confirmation.")
            elevate(
                to: .answerWithCaveat,
                mode: .partialAnswer,
                tier: .mediumScope,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier,
                onlyIfWeaker: true
            )
        } else {
            missing.append(
                ProviderMissingClaim(
                    dimension: .exactSlot,
                    reason: "Ledger: no published availability window to confirm an exact slot."
                )
            )
            elevate(
                to: .needsProviderConfirmation,
                mode: .askProviderInput,
                tier: .mediumScope,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }
    }

    private static func applyLedgerServiceAreaPolicy(
        input: ProviderInboundClaimPolicyInput,
        ledger: ProviderClaimLedger,
        commercial: ExchangeOffer.CommercialFacts,
        requesterLower: String,
        fallbackHaystackUsed: inout [String],
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        caveats: inout [String],
        forbidden: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        guard let area = ledger.entry(for: .serviceArea), area.status == .present,
              let areaText = area.sourceValuePreview else {
            fallbackHaystackUsed.append("serviceArea")
            applyServiceAreaPolicy(
                input: input,
                commercial: commercial,
                requesterLower: requesterLower,
                allowed: &allowed,
                missing: &missing,
                caveats: &caveats,
                forbidden: &forbidden,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
            return
        }

        allowed.append(allowedClaim(from: area))

        let probeLocations = probeLocationsInRequester(requesterLower)
        let areaLower = areaText.lowercased()
        let outside = probeLocations.contains { loc in
            if requesterImpliesOutside(areaLower: areaLower, location: loc) { return true }
            return !areaLower.contains(loc)
        }

        if outside {
            missing.append(
                ProviderMissingClaim(
                    dimension: .serviceArea,
                    reason: "Requester location appears outside published service area."
                )
            )
            caveats.append("Name requester area only to deny; cite published service area; do not claim coverage outside it.")
            forbidden.append(contentsOf: probeLocations.map { "serve \($0)" } + ["same day outside area"])
            elevate(
                to: .notInOffer,
                mode: .decline,
                tier: .highClaim,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }
    }

    private static func applyLedgerPricingPolicy(
        ledger: ProviderClaimLedger,
        commercial: ExchangeOffer.CommercialFacts,
        fallbackHaystackUsed: inout [String],
        allowed: inout [ProviderAllowedClaim]
    ) {
        if let pricing = ledger.entry(for: .pricing), pricing.status == .present {
            allowed.append(allowedClaim(from: pricing))
            return
        }
        if commercial.hasAnyPublicPriceSignal {
            fallbackHaystackUsed.append("price")
            if let pd = trim(commercial.priceDisplay) {
                allowed.append(
                    ProviderAllowedClaim(
                        factID: "offer.commercial.priceDisplay",
                        text: pd,
                        source: .offer
                    )
                )
            }
        }
    }

    private static func applyLedgerAvailabilityPolicy(
        ledger: ProviderClaimLedger,
        commercial: ExchangeOffer.CommercialFacts,
        fallbackHaystackUsed: inout [String],
        allowed: inout [ProviderAllowedClaim]
    ) {
        if let availability = ledger.entry(for: .availability), availability.status == .present {
            allowed.append(allowedClaim(from: availability))
            return
        }
        if let note = trim(commercial.availabilityNote) {
            fallbackHaystackUsed.append("availability")
            allowed.append(
                ProviderAllowedClaim(
                    factID: "offer.commercial.availabilityNote",
                    text: note,
                    source: .offer
                )
            )
        }
    }

    private static func applyLedgerPolicyTermsPolicy(
        ledger: ProviderClaimLedger,
        fallbackHaystackUsed: inout [String],
        commercial: ExchangeOffer.CommercialFacts,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        if let policy = ledger.entry(for: .policyException), policy.status == .present {
            allowed.append(allowedClaim(from: policy))
            return
        }
        let hasPolicyText =
            trim(commercial.cancellationPolicy) != nil
            || trim(commercial.refundPolicy) != nil
            || trim(commercial.minimumEngagement) != nil
        if hasPolicyText {
            fallbackHaystackUsed.append("policyTerms")
            if let cp = trim(commercial.cancellationPolicy) {
                allowed.append(
                    ProviderAllowedClaim(
                        factID: "offer.commercial.cancellationPolicy",
                        text: cp,
                        source: .offer
                    )
                )
            } else if let rp = trim(commercial.refundPolicy) {
                allowed.append(
                    ProviderAllowedClaim(
                        factID: "offer.commercial.refundPolicy",
                        text: rp,
                        source: .offer
                    )
                )
            }
            return
        }
        missing.append(
            ProviderMissingClaim(
                dimension: .policyTerms,
                reason: "Ledger: policy exception claim not published."
            )
        )
        elevate(
            to: .needsProviderConfirmation,
            mode: .askProviderInput,
            tier: .mediumScope,
            answerability: &answerability,
            responseMode: &responseMode,
            riskTier: &riskTier
        )
    }

    private static func applyLedgerCommitmentPolicy(
        input: ProviderInboundClaimPolicyInput,
        ledger: ProviderClaimLedger,
        commercial: ExchangeOffer.CommercialFacts,
        offerFactsHaystack: String,
        fallbackHaystackUsed: inout [String],
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        forbidden: inout [String],
        untrusted: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier,
        commitmentBoundary: inout ExchangeCommitmentBoundary?
    ) {
        if let pricing = ledger.entry(for: .pricing), pricing.status == .present {
            allowed.append(allowedClaim(from: pricing))
        } else if commercial.hasAnyPublicPriceSignal, let pd = trim(commercial.priceDisplay) {
            fallbackHaystackUsed.append("commitment.pricing")
            allowed.append(
                ProviderAllowedClaim(
                    factID: "offer.commercial.priceDisplay",
                    text: pd,
                    source: .offer
                )
            )
        }

        let booking = ledger.entry(for: .bookingConfirmation)
        let customQuote = ledger.entry(for: .customQuote)
        _ = offerFactsHaystack
        missing.append(
            ProviderMissingClaim(
                dimension: .booking,
                reason: booking.map {
                    "Ledger: \($0.sourceField) is \($0.status.rawValue); booking requires provider confirmation."
                } ?? "Booking requires provider confirmation."
            )
        )
        if input.detection.askedDimensions.contains(.finalQuote),
           customQuote?.status != .present {
            missing.append(
                ProviderMissingClaim(
                    dimension: .finalQuote,
                    reason: customQuote.map {
                        "Ledger: \($0.sourceField) is \($0.status.rawValue); binding quote needs provider confirmation."
                    } ?? "Binding quote needs provider confirmation."
                )
            )
        }

        forbidden.append(contentsOf: [
            "booked", "confirmed appointment", "final quote", "booking confirmed", "appointment confirmed"
        ])
        extractRequesterCommitmentTerms(input.requesterText).forEach { untrusted.append($0) }
        commitmentBoundary = .commitmentBearing(reason: "Inbound asks for booking or binding quote.")
        elevate(
            to: .refuseCommitment,
            mode: .decline,
            tier: .commitment,
            answerability: &answerability,
            responseMode: &responseMode,
            riskTier: &riskTier
        )
    }

    private static func allowedClaim(from entry: ProviderClaimLedgerEntry) -> ProviderAllowedClaim {
        ProviderAllowedClaim(
            factID: entry.sourceField,
            text: entry.sourceValuePreview ?? entry.sourceField,
            source: .offer
        )
    }

    private static func ledgerCredentialMissingReason(
        licensed: ProviderClaimLedgerEntry?,
        insured: ProviderClaimLedgerEntry?
    ) -> String {
        var parts: [String] = []
        if licensed?.status != .present {
            parts.append("licensed=\(licensed?.status.rawValue ?? "missing")")
        }
        if insured?.status != .present {
            parts.append("insured=\(insured?.status.rawValue ?? "missing")")
        }
        return "Credential claims not published on seller surface (\(parts.joined(separator: ", ")))."
    }

    #if DEBUG
    private static func makePolicyComparison(
        input: ProviderInboundClaimPolicyInput,
        haystackPacket: ProviderClaimBoundaryPacket,
        ledgerPacket: ProviderClaimBoundaryPacket,
        fallbackHaystackUsed: [String]
    ) -> ProviderClaimLedgerPolicyComparison {
        let oldAllowed = allowedFactIDSummary(haystackPacket)
        let newAllowed = allowedFactIDSummary(ledgerPacket)
        let oldMissing = missingClaimSummary(haystackPacket)
        let newMissing = missingClaimSummary(ledgerPacket)
        let disagreement =
            oldAllowed != newAllowed
            || oldMissing != newMissing
            || haystackPacket.answerabilityStatus != ledgerPacket.answerabilityStatus
            || haystackPacket.riskTier != ledgerPacket.riskTier
        return ProviderClaimLedgerPolicyComparison(
            detectedDimensions: input.detection.askedDimensions.map(\.rawValue),
            oldAllowed: oldAllowed,
            newAllowed: newAllowed,
            oldMissing: oldMissing,
            newMissing: newMissing,
            fallbackHaystackUsed: fallbackHaystackUsed,
            disagreement: disagreement
        )
    }

    private static func allowedFactIDSummary(_ packet: ProviderClaimBoundaryPacket) -> String {
        let ids = packet.allowedClaims.map(\.factID).sorted()
        return ids.isEmpty ? "none" : ids.joined(separator: ",")
    }

    private static func missingClaimSummary(_ packet: ProviderClaimBoundaryPacket) -> String {
        let lines = packet.missingClaims
            .map { "\($0.dimension.rawValue):\($0.reason)" }
            .sorted()
        return lines.isEmpty ? "none" : lines.joined(separator: "|")
    }

    private static func logLedgerPolicyIntegration(
        _ compared: (haystackPacket: ProviderClaimBoundaryPacket, comparison: ProviderClaimLedgerPolicyComparison)
    ) {
        let c = compared.comparison
        let dims = c.detectedDimensions.joined(separator: ",")
        let fallback = c.fallbackHaystackUsed.isEmpty ? "none" : c.fallbackHaystackUsed.joined(separator: ",")
        print(
            "[ProviderClaimLedgerPolicy] detectedDimensions=\(dims) " +
                "ledgerAllowed=\(c.newAllowed) ledgerMissing=\(c.newMissing) " +
                "fallbackHaystackUsed=\(fallback)"
        )
        print(
            "[ProviderClaimLedgerCompare] oldAllowed=\(c.oldAllowed) newAllowed=\(c.newAllowed) " +
                "oldMissing=\(c.oldMissing) newMissing=\(c.newMissing) disagreement=\(c.disagreement)"
        )
    }

    /// Per-fixture smoke line (fixture id included for catalog correlation).
    public static func logLedgerPolicyComparisonForSmoke(
        fixtureID: String,
        comparison: ProviderClaimLedgerPolicyComparison
    ) {
        let dims = comparison.detectedDimensions.joined(separator: ",")
        let fallback = comparison.fallbackHaystackUsed.isEmpty
            ? "none"
            : comparison.fallbackHaystackUsed.joined(separator: ",")
        print(
            "[ProviderClaimLedgerSmoke] fixture=\(fixtureID) detectedDimensions=\(dims) " +
                "oldAllowed=\(comparison.oldAllowed) newAllowed=\(comparison.newAllowed) " +
                "oldMissing=\(comparison.oldMissing) newMissing=\(comparison.newMissing) " +
                "fallbackHaystackUsed=\(fallback) disagreement=\(comparison.disagreement)"
        )
    }
    #endif

    // MARK: - Scenario policies (haystack)

    private static func applyDiscountPolicy(
        commercial: ExchangeOffer.CommercialFacts,
        offerFactsHaystack: String,
        requesterLower: String,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        forbidden: inout [String],
        untrusted: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        let publishedDiscount = hasPublishedDiscountSignal(commercial: commercial, offerFactsHaystack: offerFactsHaystack)
        if !publishedDiscount {
            missing.append(
                ProviderMissingClaim(
                    dimension: .discount,
                    reason: "No published discount or special-rate policy in seller-controlled offer facts."
                )
            )
            forbidden.append(contentsOf: ["20% off", "discount approved", "special rate confirmed", "today-only deal"])
            extractRequesterDiscountTerms(requesterLower).forEach { untrusted.append($0) }
            elevate(
                to: .needsProviderConfirmation,
                mode: .askProviderInput,
                tier: .highClaim,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }
    }

    private static func applyCredentialPolicy(
        dimension: ProviderInboundDimension,
        commercial: ExchangeOffer.CommercialFacts,
        offerFactsHaystack: String,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        forbidden: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        let tokens: [String]
        switch dimension {
        case .licenseInsurance:
            tokens = ["licensed", "insured", "bonded", "liability insurance"]
        case .certification:
            tokens = ["certified", "certification", "accredited"]
        default:
            tokens = []
        }
        guard !tokens.isEmpty else { return }

        if let line = explicitOfferFactLine(for: tokens, offerFactsHaystack: offerFactsHaystack) {
            allowed.append(
                ProviderAllowedClaim(
                    factID: "offer.explicit.\(dimension.rawValue)",
                    text: line,
                    source: .offer
                )
            )
            return
        }

        missing.append(
            ProviderMissingClaim(
                dimension: dimension,
                reason: "Credential or certification not specified in published offer facts (profile profession is not evidence)."
            )
        )
        forbidden.append(contentsOf: tokens)
        elevate(
            to: .notInOffer,
            mode: .askProviderInput,
            tier: .highClaim,
            answerability: &answerability,
            responseMode: &responseMode,
            riskTier: &riskTier
        )
    }

    private static func applyWarrantyPolicy(
        commercial: ExchangeOffer.CommercialFacts,
        offerFactsHaystack: String,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        forbidden: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        if let wp = trim(commercial.warrantyPolicy) {
            allowed.append(
                ProviderAllowedClaim(
                    factID: "offer.commercial.warrantyPolicy",
                    text: wp,
                    source: .offer
                )
            )
            return
        }
        if offerFactsHaystack.contains("warranty") {
            return
        }
        missing.append(
            ProviderMissingClaim(
                dimension: .warranty,
                reason: "Warranty not published in seller-controlled offer facts."
            )
        )
        forbidden.append(contentsOf: ["warranty included", "guaranteed warranty", "full warranty"])
        elevate(
            to: .notInOffer,
            mode: .askProviderInput,
            tier: .highClaim,
            answerability: &answerability,
            responseMode: &responseMode,
            riskTier: &riskTier
        )
    }

    private static func applyExactSlotPolicy(
        commercial: ExchangeOffer.CommercialFacts,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        caveats: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        let hasGeneral =
            trim(commercial.availabilityNote) != nil
            || trim(commercial.minimumEngagement) != nil
        if hasGeneral, let note = trim(commercial.availabilityNote) {
            allowed.append(
                ProviderAllowedClaim(
                    factID: "offer.commercial.availabilityNote",
                    text: note,
                    source: .offer
                )
            )
            missing.append(
                ProviderMissingClaim(
                    dimension: .exactSlot,
                    reason: "Published availability is general; exact slot not confirmed."
                )
            )
            caveats.append("State published general availability and that exact timing needs confirmation.")
            elevate(
                to: .answerWithCaveat,
                mode: .partialAnswer,
                tier: .mediumScope,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier,
                onlyIfWeaker: true
            )
        } else {
            missing.append(
                ProviderMissingClaim(
                    dimension: .exactSlot,
                    reason: "No published availability window to confirm an exact slot."
                )
            )
            elevate(
                to: .needsProviderConfirmation,
                mode: .askProviderInput,
                tier: .mediumScope,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }
    }

    private static func applyServiceAreaPolicy(
        input: ProviderInboundClaimPolicyInput,
        commercial: ExchangeOffer.CommercialFacts,
        requesterLower: String,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        caveats: inout [String],
        forbidden: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier
    ) {
        guard let areaNote = trim(commercial.serviceAreaNote) else {
            missing.append(
                ProviderMissingClaim(
                    dimension: .serviceArea,
                    reason: "No published service-area fact."
                )
            )
            elevate(
                to: .needsProviderConfirmation,
                mode: .askProviderInput,
                tier: .mediumScope,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
            return
        }

        allowed.append(
            ProviderAllowedClaim(
                factID: "offer.commercial.serviceAreaNote",
                text: areaNote,
                source: .offer
            )
        )

        let probeLocations = probeLocationsInRequester(requesterLower)
        let areaLower = areaNote.lowercased()
        let outside = probeLocations.contains { loc in
            if requesterImpliesOutside(areaLower: areaLower, location: loc) { return true }
            return !areaLower.contains(loc)
        }

        if outside {
            missing.append(
                ProviderMissingClaim(
                    dimension: .serviceArea,
                    reason: "Requester location appears outside published service area."
                )
            )
            caveats.append("Name requester area only to deny; cite published service area; do not claim coverage outside it.")
            forbidden.append(contentsOf: probeLocations.map { "serve \($0)" } + ["same day outside area"])
            elevate(
                to: .notInOffer,
                mode: .decline,
                tier: .highClaim,
                answerability: &answerability,
                responseMode: &responseMode,
                riskTier: &riskTier
            )
        }
    }

    private static func applyCommitmentPolicy(
        input: ProviderInboundClaimPolicyInput,
        commercial: ExchangeOffer.CommercialFacts,
        offerFactsHaystack: String,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        forbidden: inout [String],
        untrusted: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier,
        commitmentBoundary: inout ExchangeCommitmentBoundary?
    ) {
        if commercial.hasAnyPublicPriceSignal, let pd = trim(commercial.priceDisplay) {
            allowed.append(
                ProviderAllowedClaim(
                    factID: "offer.commercial.priceDisplay",
                    text: pd,
                    source: .offer
                )
            )
        }
        missing.append(
            ProviderMissingClaim(
                dimension: .booking,
                reason: "Booking and final quote require provider confirmation."
            )
        )
        forbidden.append(contentsOf: [
            "booked", "confirmed appointment", "final quote", "booking confirmed", "appointment confirmed"
        ])
        extractRequesterCommitmentTerms(input.requesterText).forEach { untrusted.append($0) }
        commitmentBoundary = .commitmentBearing(reason: "Inbound asks for booking or binding quote.")
        elevate(
            to: .refuseCommitment,
            mode: .decline,
            tier: .commitment,
            answerability: &answerability,
            responseMode: &responseMode,
            riskTier: &riskTier
        )
    }

    // MARK: - Helpers

    private static func offerCommercialHaystack(
        commercial: ExchangeOffer.CommercialFacts,
        sellerControlledFacts: String
    ) -> String {
        var parts: [String] = []
        if let block = extractSection(sellerControlledFacts, marker: "=== OFFER_FACTS ===") {
            parts.append(block)
        }
        parts.append(commercial.searchablePieces.joined(separator: " "))
        return parts.joined(separator: " ").lowercased()
    }

    private static func extractSection(_ facts: String, marker: String) -> String? {
        guard let startRange = facts.range(of: marker) else { return nil }
        let after = facts[startRange.upperBound...]
        let endMarkers = ["=== PROFILE_FACTS ===", "=== OPERATING_MEMORY_EXCERPT ==="]
        var end = after.endIndex
        for em in endMarkers where em != marker {
            if let r = after.range(of: em) {
                end = min(end, r.lowerBound)
            }
        }
        return String(after[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasPublishedDiscountSignal(
        commercial: ExchangeOffer.CommercialFacts,
        offerFactsHaystack: String
    ) -> Bool {
        let discountNeedles = ["discount policy", "discount:", "% off", "percent off", "special rate policy"]
        if discountNeedles.contains(where: { offerFactsHaystack.contains($0) }) { return true }
        return commercial.faqs.contains {
            $0.question.lowercased().contains("discount") || $0.answer.lowercased().contains("discount")
        }
    }

    private static func explicitOfferFactLine(for tokens: [String], offerFactsHaystack: String) -> String? {
        let lines = offerFactsHaystack.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        for line in lines where !line.isEmpty {
            let low = line.lowercased()
            if low.hasPrefix("profile_") { continue }
            if low.contains("professional"), !low.contains("licensed"), !low.contains("insured") { continue }
            if tokens.contains(where: { low.contains($0) }) {
                return line
            }
        }
        return nil
    }

    private static func probeLocationsInRequester(_ lower: String) -> [String] {
        let known = ["houston", "dallas", "san antonio", "austin", "california", "nationwide"]
        return known.filter { lower.contains($0) }
    }

    private static func requesterImpliesOutside(areaLower: String, location: String) -> Bool {
        if areaLower.contains("austin") && location == "houston" { return true }
        if areaLower.contains("metro only") && location != "austin" { return true }
        return false
    }

    private static func extractRequesterDiscountTerms(_ lower: String) -> [String] {
        var out: [String] = []
        if lower.contains("20%") || lower.contains("20 percent") { out.append("20% off") }
        if lower.contains("discount") { out.append("requester-proposed discount") }
        if lower.contains("book today") { out.append("book today") }
        return out
    }

    private static func extractRequesterCommitmentTerms(_ text: String) -> [String] {
        var out: [String] = []
        let lower = text.lowercased()
        if lower.contains("book") { out.append("requester booking request") }
        if lower.range(of: #"final quote of \$\d+"#, options: .regularExpression) != nil {
            out.append("requester final quote amount")
        } else if lower.contains("final quote") {
            out.append("requester final quote")
        }
        return out
    }

    private static func trim(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static func elevate(
        to newAnswerability: ProviderPolicyAnswerability,
        mode: ProviderResponseMode,
        tier: ProviderInboundRiskTier,
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode,
        riskTier: inout ProviderInboundRiskTier,
        onlyIfWeaker: Bool = false
    ) {
        if onlyIfWeaker, answerabilityRank(answerability) >= answerabilityRank(newAnswerability) {
            return
        }
        if answerabilityRank(newAnswerability) > answerabilityRank(answerability) {
            answerability = newAnswerability
            responseMode = mode
        }
        if tier > riskTier { riskTier = tier }
    }

    private static func answerabilityRank(_ a: ProviderPolicyAnswerability) -> Int {
        switch a {
        case .answerDirectly: return 0
        case .answerWithCaveat: return 1
        case .needsProviderConfirmation: return 2
        case .notInOffer: return 3
        case .refuseCommitment: return 4
        }
    }

    private static func dedupePacket(
        dims: [ProviderInboundDimension],
        riskTier: inout ProviderInboundRiskTier,
        allowed: inout [ProviderAllowedClaim],
        missing: inout [ProviderMissingClaim],
        caveats: inout [String],
        forbidden: inout [String],
        untrusted: inout [String],
        answerability: inout ProviderPolicyAnswerability,
        responseMode: inout ProviderResponseMode
    ) {
        var seenAllowed: Set<String> = []
        allowed = allowed.filter { seenAllowed.insert($0.factID).inserted }

        var seenMissing: Set<String> = []
        missing = missing.filter { seenMissing.insert($0.dimension.rawValue + $0.reason).inserted }

        var seenCaveat: Set<String> = []
        caveats = caveats.filter { seenCaveat.insert($0).inserted }
        forbidden = Array(Set(forbidden))
        untrusted = Array(Set(untrusted))

        if dims == [.other], answerability == .answerDirectly {
            responseMode = .groundedAnswer
            riskTier = .lowFact
        }
    }
}
