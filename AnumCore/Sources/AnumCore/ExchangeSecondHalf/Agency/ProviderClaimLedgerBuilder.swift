import Foundation

/// Builds a closed-ontology `ProviderClaimLedger` from public profile + offer schema (no LLM, no haystack).
public enum ProviderClaimLedgerBuilder: Sendable {

    // MARK: - Future structured fields (not on schema today)

    // Credentials: `ExchangeOffer.CommercialFacts` and `ExchangePublicNodeProfile` have no
    // `licensed`, `insured`, or `certification` booleans/lines — headline/profession text is intentionally ignored.
    private static let licensedSourceField = "offer.commercial.licensed"
    private static let insuredSourceField = "offer.commercial.insured"
    private static let certifiedSourceField = "offer.commercial.certification"
    // Discount: no `discountPolicy` / `discountOffered` field on CommercialFacts; FAQ text is not evidence.
    private static let discountOfferedSourceField = "offer.commercial.discountOffered"
    private static let customDiscountSourceField = "offer.commercial.customDiscount"
    private static let responseTimeSourceField = "offer.commercial.responseTime"
    private static let exactSlotSourceField = "offer.fulfillment.exactAvailabilitySlot"
    private static let bookingConfirmationSourceField = "offer.fulfillment.bookingConfirmation"
    private static let policyExceptionSourceField = "offer.commercial.policyException"
    private static let customQuoteSourceField = "offer.commercial.customQuote"

    public static func build(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?
    ) -> ProviderClaimLedger {
        let commercial = offer?.commercialFacts ?? .empty
        let fulfillment = offer?.fulfillment ?? .init()
        let permission = commercial.permissionOnlyAutoAnswerPolicy()

        var entries: [ProviderClaimLedgerEntry] = []
        entries.reserveCapacity(ProviderClaimType.allCases.count)

        for claimType in ProviderClaimType.allCases {
            entries.append(
                entry(
                    for: claimType,
                    profile: profile,
                    offer: offer,
                    commercial: commercial,
                    fulfillment: fulfillment,
                    permission: permission
                )
            )
        }

        return ProviderClaimLedger(
            entries: entries,
            offerID: offer?.id,
            profileID: profile?.id ?? offer?.publicProfileID,
            builtAt: Date()
        )
    }

    // MARK: - Per-claim rules

    private static func entry(
        for claimType: ProviderClaimType,
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        commercial: ExchangeOffer.CommercialFacts,
        fulfillment: ExchangeOffer.Fulfillment,
        permission: ExchangeOffer.AutoAnswerPolicy
    ) -> ProviderClaimLedgerEntry {
        switch claimType {
        case .licensed:
            return credentialEntry(
                claimType: .licensed,
                sourceField: licensedSourceField,
                riskTier: .high
            )
        case .insured:
            return credentialEntry(
                claimType: .insured,
                sourceField: insuredSourceField,
                riskTier: .high
            )
        case .certified:
            return credentialEntry(
                claimType: .certified,
                sourceField: certifiedSourceField,
                riskTier: .high
            )
        case .discountOffered:
            return discountOfferedEntry(commercial: commercial, permission: permission)
        case .responseTime:
            return responseTimeEntry()
        case .serviceArea:
            return serviceAreaEntry(profile: profile, offer: offer, commercial: commercial, permission: permission)
        case .availability:
            return availabilityEntry(commercial: commercial, offer: offer, permission: permission)
        case .exactAvailabilitySlot:
            return exactAvailabilitySlotEntry()
        case .leadTime:
            return leadTimeEntry(fulfillment: fulfillment)
        case .pricing:
            return pricingEntry(commercial: commercial, permission: permission)
        case .packageAvailability:
            return packageAvailabilityEntry(commercial: commercial)
        case .warrantyOrGuarantee:
            return warrantyEntry(commercial: commercial, permission: permission)
        case .bookingConfirmation:
            return bookingConfirmationEntry()
        case .policyException:
            return policyExceptionEntry(commercial: commercial, permission: permission)
        case .customQuote:
            return customQuoteEntry(permission: permission)
        case .customDiscount:
            return customDiscountEntry()
        }
    }

    /// No structured credential field exists on offer/profile schema today — always absent (not inferred from headline/FAQ/haystack).
    private static func credentialEntry(
        claimType: ProviderClaimType,
        sourceField: String,
        riskTier: ProviderClaimRiskTier
    ) -> ProviderClaimLedgerEntry {
        ProviderClaimLedgerEntry(
            claimType: claimType,
            status: .absent,
            sourceField: sourceField,
            sourceValuePreview: nil,
            mayAutoAnswer: false,
            requiresProviderConfirmation: true,
            riskTier: riskTier
        )
    }

    private static func discountOfferedEntry(
        commercial: ExchangeOffer.CommercialFacts,
        permission: ExchangeOffer.AutoAnswerPolicy
    ) -> ProviderClaimLedgerEntry {
        // When a first-class discount field is added to CommercialFacts, gate present/absent on that field only.
        if let explicit = explicitStructuredDiscountValue(commercial: commercial) {
            return ProviderClaimLedgerEntry(
                claimType: .discountOffered,
                status: .present,
                sourceField: discountOfferedSourceField,
                sourceValuePreview: preview(explicit),
                mayAutoAnswer: false,
                requiresProviderConfirmation: true,
                riskTier: .high
            )
        }
        return ProviderClaimLedgerEntry(
            claimType: .discountOffered,
            status: .absent,
            sourceField: discountOfferedSourceField,
            sourceValuePreview: nil,
            mayAutoAnswer: false,
            requiresProviderConfirmation: true,
            riskTier: .high
        )
    }

    private static func explicitStructuredDiscountValue(commercial: ExchangeOffer.CommercialFacts) -> String? {
        // Placeholder for a future `discountPolicy` / `discountOffered` Codable field — not in schema v1.5.
        _ = commercial
        return nil
    }

    private static func responseTimeEntry() -> ProviderClaimLedgerEntry {
        ProviderClaimLedgerEntry(
            claimType: .responseTime,
            status: .unknown,
            sourceField: responseTimeSourceField,
            sourceValuePreview: nil,
            mayAutoAnswer: false,
            requiresProviderConfirmation: true,
            riskTier: .medium
        )
    }

    private static func serviceAreaEntry(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        commercial: ExchangeOffer.CommercialFacts,
        permission: ExchangeOffer.AutoAnswerPolicy
    ) -> ProviderClaimLedgerEntry {
        if let note = trim(commercial.serviceAreaNote) {
            return presentEntry(
                claimType: .serviceArea,
                sourceField: "offer.commercial.serviceAreaNote",
                value: note,
                mayAutoAnswer: permission.canAnswerServiceArea,
                requiresProviderConfirmation: !permission.canAnswerServiceArea,
                riskTier: .medium
            )
        }
        if let area = trim(offer?.contactInfo?.serviceAddressOrArea) {
            return presentEntry(
                claimType: .serviceArea,
                sourceField: "offer.contactInfo.serviceAddressOrArea",
                value: area,
                mayAutoAnswer: permission.canAnswerServiceArea,
                requiresProviderConfirmation: !permission.canAnswerServiceArea,
                riskTier: .medium
            )
        }
        let regionPreview = regionCoveragePreview(offer: offer, profile: profile)
        if let regionPreview {
            return presentEntry(
                claimType: .serviceArea,
                sourceField: regionPreview.field,
                value: regionPreview.text,
                mayAutoAnswer: permission.canAnswerServiceArea,
                requiresProviderConfirmation: !permission.canAnswerServiceArea,
                riskTier: .medium
            )
        }
        return absentEntry(
            claimType: .serviceArea,
            sourceField: "offer.commercial.serviceAreaNote",
            requiresProviderConfirmation: true,
            riskTier: .medium
        )
    }

    private static func availabilityEntry(
        commercial: ExchangeOffer.CommercialFacts,
        offer: ExchangeOffer?,
        permission: ExchangeOffer.AutoAnswerPolicy
    ) -> ProviderClaimLedgerEntry {
        if let note = trim(commercial.availabilityNote) {
            return presentEntry(
                claimType: .availability,
                sourceField: "offer.commercial.availabilityNote",
                value: note,
                mayAutoAnswer: permission.canAnswerAvailability && commercial.hasAvailabilityEvidence,
                requiresProviderConfirmation: !permission.canAnswerAvailability,
                riskTier: .medium
            )
        }
        if let contactNote = trim(offer?.contactInfo?.availabilityNote) {
            return presentEntry(
                claimType: .availability,
                sourceField: "offer.contactInfo.availabilityNote",
                value: contactNote,
                mayAutoAnswer: permission.canAnswerAvailability,
                requiresProviderConfirmation: !permission.canAnswerAvailability,
                riskTier: .medium
            )
        }
        return absentEntry(
            claimType: .availability,
            sourceField: "offer.commercial.availabilityNote",
            requiresProviderConfirmation: true,
            riskTier: .medium
        )
    }

    private static func exactAvailabilitySlotEntry() -> ProviderClaimLedgerEntry {
        ProviderClaimLedgerEntry(
            claimType: .exactAvailabilitySlot,
            status: .absent,
            sourceField: exactSlotSourceField,
            sourceValuePreview: nil,
            mayAutoAnswer: false,
            requiresProviderConfirmation: true,
            riskTier: .medium
        )
    }

    private static func leadTimeEntry(fulfillment: ExchangeOffer.Fulfillment) -> ProviderClaimLedgerEntry {
        if let note = trim(fulfillment.leadTimeNote) {
            return presentEntry(
                claimType: .leadTime,
                sourceField: "offer.fulfillment.leadTimeNote",
                value: note,
                mayAutoAnswer: true,
                requiresProviderConfirmation: false,
                riskTier: .low
            )
        }
        return absentEntry(
            claimType: .leadTime,
            sourceField: "offer.fulfillment.leadTimeNote",
            requiresProviderConfirmation: true,
            riskTier: .low
        )
    }

    private static func pricingEntry(
        commercial: ExchangeOffer.CommercialFacts,
        permission: ExchangeOffer.AutoAnswerPolicy
    ) -> ProviderClaimLedgerEntry {
        if let display = trim(commercial.priceDisplay) {
            return presentEntry(
                claimType: .pricing,
                sourceField: "offer.commercial.priceDisplay",
                value: display,
                mayAutoAnswer: permission.canAnswerPricing,
                requiresProviderConfirmation: !permission.canAnswerPricing,
                riskTier: .low
            )
        }
        if commercial.priceMin != nil || commercial.priceMax != nil {
            var parts: [String] = []
            if let min = commercial.priceMin {
                parts.append("min \((min as NSDecimalNumber).stringValue)")
            }
            if let max = commercial.priceMax {
                parts.append("max \((max as NSDecimalNumber).stringValue)")
            }
            let range = parts.joined(separator: " · ")
            return presentEntry(
                claimType: .pricing,
                sourceField: "offer.commercial.priceMinMax",
                value: range,
                mayAutoAnswer: permission.canAnswerPricing,
                requiresProviderConfirmation: !permission.canAnswerPricing,
                riskTier: .low
            )
        }
        return absentEntry(
            claimType: .pricing,
            sourceField: "offer.commercial.priceDisplay",
            requiresProviderConfirmation: true,
            riskTier: .low
        )
    }

    private static func packageAvailabilityEntry(
        commercial: ExchangeOffer.CommercialFacts
    ) -> ProviderClaimLedgerEntry {
        guard !commercial.packages.isEmpty else {
            return absentEntry(
                claimType: .packageAvailability,
                sourceField: "offer.commercial.packages",
                requiresProviderConfirmation: true,
                riskTier: .low
            )
        }
        let titles = commercial.packages.prefix(4).map(\.title).joined(separator: ", ")
        return presentEntry(
            claimType: .packageAvailability,
            sourceField: "offer.commercial.packages",
            value: titles,
            mayAutoAnswer: true,
            requiresProviderConfirmation: false,
            riskTier: .low
        )
    }

    private static func warrantyEntry(
        commercial: ExchangeOffer.CommercialFacts,
        permission: ExchangeOffer.AutoAnswerPolicy
    ) -> ProviderClaimLedgerEntry {
        if let policy = trim(commercial.warrantyPolicy) {
            return presentEntry(
                claimType: .warrantyOrGuarantee,
                sourceField: "offer.commercial.warrantyPolicy",
                value: policy,
                mayAutoAnswer: permission.canAnswerPolicies && commercial.hasPolicyEvidence,
                requiresProviderConfirmation: !permission.canAnswerPolicies,
                riskTier: .high
            )
        }
        return absentEntry(
            claimType: .warrantyOrGuarantee,
            sourceField: "offer.commercial.warrantyPolicy",
            requiresProviderConfirmation: true,
            riskTier: .high
        )
    }

    private static func bookingConfirmationEntry() -> ProviderClaimLedgerEntry {
        ProviderClaimLedgerEntry(
            claimType: .bookingConfirmation,
            status: .absent,
            sourceField: bookingConfirmationSourceField,
            sourceValuePreview: nil,
            mayAutoAnswer: false,
            requiresProviderConfirmation: true,
            riskTier: .commitment
        )
    }

    private static func policyExceptionEntry(
        commercial _: ExchangeOffer.CommercialFacts,
        permission _: ExchangeOffer.AutoAnswerPolicy
    ) -> ProviderClaimLedgerEntry {
        // No `policyException` controlled field on CommercialFacts — seller-specific exceptions need confirmation.
        return absentEntry(
            claimType: .policyException,
            sourceField: policyExceptionSourceField,
            requiresProviderConfirmation: true,
            riskTier: .medium
        )
    }

    private static func customQuoteEntry(
        permission: ExchangeOffer.AutoAnswerPolicy
    ) -> ProviderClaimLedgerEntry {
        let needsApproval = permission.requiresApprovalForCustomQuote
        return ProviderClaimLedgerEntry(
            claimType: .customQuote,
            status: .absent,
            sourceField: customQuoteSourceField,
            sourceValuePreview: nil,
            mayAutoAnswer: false,
            requiresProviderConfirmation: needsApproval,
            riskTier: .commitment
        )
    }

    private static func customDiscountEntry() -> ProviderClaimLedgerEntry {
        ProviderClaimLedgerEntry(
            claimType: .customDiscount,
            status: .absent,
            sourceField: customDiscountSourceField,
            sourceValuePreview: nil,
            mayAutoAnswer: false,
            requiresProviderConfirmation: true,
            riskTier: .high
        )
    }

    // MARK: - Entry factories

    private static func presentEntry(
        claimType: ProviderClaimType,
        sourceField: String,
        value: String,
        mayAutoAnswer: Bool,
        requiresProviderConfirmation: Bool,
        riskTier: ProviderClaimRiskTier
    ) -> ProviderClaimLedgerEntry {
        ProviderClaimLedgerEntry(
            claimType: claimType,
            status: .present,
            sourceField: sourceField,
            sourceValuePreview: preview(value),
            mayAutoAnswer: mayAutoAnswer,
            requiresProviderConfirmation: requiresProviderConfirmation,
            riskTier: riskTier
        )
    }

    private static func absentEntry(
        claimType: ProviderClaimType,
        sourceField: String,
        requiresProviderConfirmation: Bool,
        riskTier: ProviderClaimRiskTier
    ) -> ProviderClaimLedgerEntry {
        ProviderClaimLedgerEntry(
            claimType: claimType,
            status: .absent,
            sourceField: sourceField,
            sourceValuePreview: nil,
            mayAutoAnswer: false,
            requiresProviderConfirmation: requiresProviderConfirmation,
            riskTier: riskTier
        )
    }

    // MARK: - Helpers

    private static func trim(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func preview(_ value: String, maxLength: Int = 120) -> String {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxLength else { return t }
        let end = t.index(t.startIndex, offsetBy: maxLength)
        return String(t[..<end]) + "…"
    }

    private static func regionCoveragePreview(
        offer: ExchangeOffer?,
        profile: ExchangePublicNodeProfile?
    ) -> (field: String, text: String)? {
        if let offer, !offer.regionTags.isEmpty {
            return ("offer.regionTags", offer.regionTags.joined(separator: ", "))
        }
        if let offer, !offer.canonicalRegionIDs.isEmpty {
            return ("offer.canonicalRegionIDs", offer.canonicalRegionIDs.joined(separator: ", "))
        }
        if let profile, !profile.regionTags.isEmpty {
            return ("profile.regionTags", profile.regionTags.joined(separator: ", "))
        }
        if let profile, !profile.canonicalRegionIDs.isEmpty {
            return ("profile.canonicalRegionIDs", profile.canonicalRegionIDs.joined(separator: ", "))
        }
        return nil
    }
}
