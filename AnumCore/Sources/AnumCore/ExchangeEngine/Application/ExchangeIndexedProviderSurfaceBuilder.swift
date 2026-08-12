import Foundation

public struct ExchangeIndexedProviderSurfaceBuilder: Sendable {
    public init() {}

    public func build(
        profile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer]
    ) -> ExchangeIndexedProviderSurface {
        let indexedOffers = offers.map { buildOfferSurface(offer: $0) }

        let identityBlocks = sanitizeTextBlocks([
            profile.displayName,
            profile.headline
        ])

        let introBlocks = identityBlocks

        let aboutBlocks = sanitizeTextBlocks(
            [
                profile.summary,
                profile.semantic.notes,
                profile.approach.note
            ] +
            profile.activityTags.map { Optional($0) } +
            profile.excludedTopics.map { Optional($0) }
        )

        let capabilityBlocks = sanitizeTextBlocks(
            [
                profile.semantic.domains.joined(separator: " "),
                profile.semantic.intentKinds.joined(separator: " "),
                profile.semantic.audienceKinds.map(\.rawValue).joined(separator: " "),
                profile.semantic.fulfillmentModes.map(\.rawValue).joined(separator: " ")
            ].filter { !$0.isEmpty }.map { Optional($0) }
        )

        // Demand-side only: "Looking For" / openTo. Do not merge `profile.offers` here — those strings
        // are seller-surface / commercial-adjacent and are indexed on `surfaceType=offer` rows.
        let seekingBlocks = sanitizeTextBlocks(
            profile.openTo.map { Optional($0) }
        )

        let affinityBlocks = sanitizeTextBlocks(
            profile.interests.map { Optional($0) }
        )

        let regionBlocks = sanitizeTextBlocks(
            profile.regionTags.map { Optional($0) }
        )

        let sourceTextBlocks = sanitizeTextBlocks(
            (identityBlocks + capabilityBlocks + seekingBlocks + affinityBlocks + regionBlocks).map { Optional($0) }
        )

        let providerTerms = sanitizeAtomicTerms([
            profile.displayName,
            profile.headline
        ])

        let capabilityTerms = sanitizeAtomicTerms(
            profile.semantic.searchableTerms +
            profile.semantic.domains +
            profile.semantic.intentKinds
        )

        let seekingTerms = sanitizeAtomicTerms(profile.openTo)

        let affinityTerms = sanitizeAtomicTerms(
            profile.interests
        )

        let broadRecallTokens = sanitizeAtomicTerms(
            providerTerms +
            capabilityTerms +
            seekingTerms +
            affinityTerms +
            profile.regionTags +
            profile.regionAliases
        )

        let semanticConcepts = sanitizeTextBlocks(
            capabilityBlocks.map { Optional($0) } +
            profile.excludedTopics.map { Optional($0) }
        )

        let hardConstraints = sanitizeTextBlocks(
            inferHardConstraints(from: semanticConcepts + capabilityBlocks + seekingBlocks)
        )

        let softPreferences = sanitizeTextBlocks(
            inferSoftPreferences(from: semanticConcepts)
        )

        let retrievalSlices = ExchangeIndexedProviderRetrievalSlices(
            identityBlocks: identityBlocks,
            introBlocks: introBlocks,
            aboutBlocks: aboutBlocks,
            capabilityBlocks: capabilityBlocks,
            seekingBlocks: seekingBlocks,
            affinityBlocks: affinityBlocks,
            regionBlocks: regionBlocks,
            seekingTerms: seekingTerms
        )

        #if DEBUG
        print(
            "[RetrievalSlice][route] slice=seeking included=openTo:\(profile.openTo.count) " +
            "excludedOfferTerms=profile.offers:\(profile.offers.count) indexedOffers:\(offers.count)"
        )
        #endif

        let providerCommercialInputs: [ExchangeIndexedProviderSurface.CommercialConstraint] = []
        let commercialConstraints = sanitizeProviderCommercialConstraints(providerCommercialInputs)

        let providerTimeInputs: [ExchangeIndexedProviderSurface.TimeAvailabilityConstraint] =
            [ExchangeIndexedProviderSurface.TimeAvailabilityConstraint(
                text: profile.availability.rawValue,
                isHard: profile.availability == .unavailable
            )]
        let timeAvailabilityConstraints = sanitizeProviderTimeConstraints(providerTimeInputs)

        let reachability = ExchangeIndexedProviderSurface.ReachabilitySummary(
            accessMode: profile.reachability.accessMode.rawValue,
            acceptingInbound: profile.reachability.acceptingInbound,
            disclosureCeiling: profile.reachability.disclosureCeiling.rawValue,
            routeableOnly: profile.reachability.routeableOnly,
            intentCategoryPolicy: profile.reachability.intentCategoryPolicy.rawValue,
            allowedModes: profile.reachability.allowedModes,
            allowedIntentKinds: profile.reachability.allowedIntentKinds,
            allowedAudienceKinds: profile.reachability.allowedAudienceKinds.map(\.rawValue),
            minimumTrustLevel: profile.reachability.minimumTrustLevel?.rawValue,
            requiresCategoryMatch: profile.reachability.requiresCategoryMatch,
            requiresMutualFit: profile.reachability.requiresMutualFit,
            contactHints: sanitizeTextBlocks([profile.approach.note])
        )

        let regions = ExchangeIndexedProviderSurface.RegionEvidence(
            regionTags: profile.regionTags,
            canonicalRegionIDs: profile.canonicalRegionIDs,
            parentRegionIDs: profile.parentRegionIDs,
            regionAliases: profile.regionAliases,
            serviceAreaNotes: []
        )

        let latestDate = ([profile.updatedAt] + indexedOffers.map(\.updatedAt)).max() ?? profile.updatedAt

        return ExchangeIndexedProviderSurface(
            id: profile.id,
            publicProfileID: profile.id,
            nodeID: profile.nodeID,
            displayName: profile.displayName,
            headline: profile.headline,
            summary: profile.summary,
            visibility: profile.visibility.rawValue,
            availability: profile.availability.rawValue,
            regions: regions,
            providerTerms: providerTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: affinityTerms,
            broadRecallTokens: broadRecallTokens,
            semanticConcepts: semanticConcepts,
            hardConstraints: hardConstraints,
            softPreferences: softPreferences,
            commercialConstraints: commercialConstraints,
            timeAvailabilityConstraints: timeAvailabilityConstraints,
            reachability: reachability,
            offers: indexedOffers,
            sourceTextBlocks: sourceTextBlocks,
            retrievalSlices: retrievalSlices,
            updatedAt: latestDate,
            schemaVersion: 2
        )
    }

    public func buildOfferSurface(
        offer: ExchangeOffer
    ) -> ExchangeIndexedOfferSurface {
        let offerCoreTextInputs: [String?] = [
            offer.fulfillment.leadTimeNote,
            offer.fulfillment.capacityNote,
            offer.commercialFacts.serviceAreaNote,
            offer.commercialFacts.availabilityNote,
            offer.commercialFacts.minimumEngagement,
            offer.commercialFacts.cancellationPolicy,
            offer.commercialFacts.refundPolicy,
            offer.commercialFacts.warrantyPolicy,
            offer.contactInfo?.availabilityNote,
            offer.contactInfo?.serviceAddressOrArea
        ]
        let packageSlices: [ExchangeIndexedOfferPackageSlice] = offer.commercialFacts.packages.enumerated().compactMap { index, pkg in
            let descriptiveParts = sanitizeTextBlocks([Optional(pkg.title), pkg.summary])
            guard !descriptiveParts.isEmpty else { return nil }
            let stableKey = pkg.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "idx:\(index)"
                : pkg.id
            return ExchangeIndexedOfferPackageSlice(
                stableKey: stableKey,
                title: pkg.title,
                summary: pkg.summary,
                descriptiveText: descriptiveParts.joined(separator: ". ")
            )
        }
        let faqSlices: [ExchangeIndexedOfferFAQSlice] = offer.commercialFacts.faqs.enumerated().compactMap { index, faq in
            let question = faq.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = faq.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty || !answer.isEmpty else { return nil }
            return ExchangeIndexedOfferFAQSlice(
                stableKey: "idx:\(index)",
                question: question,
                answer: answer
            )
        }
        let offerContactInputs: [String?] = [
            offer.contactInfo?.contactName,
            offer.contactInfo?.businessName,
            offer.contactInfo?.email,
            offer.contactInfo?.phone,
            offer.contactInfo?.website
        ]
        let contactPolicyText = sanitizeTextBlocks(
            offerCoreTextInputs +
            offer.commercialFacts.requiredBuyerInputs +
            offerContactInputs
        )

        let serviceAreaTokens = ExchangeDeclaredServiceAreaSupport.normalizedSearchTokens(
            from: offer.effectiveServiceAreas
        )
        var sourceTextInputs: [String] = [
            offer.title,
            offer.summary,
            offer.category,
            offer.semantic.notes
        ].compactMap { $0 }
        sourceTextInputs.append(contentsOf: offer.tags)
        sourceTextInputs.append(contentsOf: offer.regionTags)
        sourceTextInputs.append(contentsOf: serviceAreaTokens)
        sourceTextInputs.append(contentsOf: offer.regionAliases)
        sourceTextInputs.append(contentsOf: contactPolicyText)
        let sourceTextBlocks = sanitizeTextBlocks(sourceTextInputs)

        let providerTerms = sanitizeAtomicTerms(
            [offer.title, offer.category] +
            offer.tags
        )

        let objectIdentityTerms = sanitizeAtomicTerms(
            [offer.title, offer.category] +
            offer.tags +
            offer.semantic.serviceKinds
        )

        let capabilityTerms = sanitizeAtomicTerms(
            offer.semantic.searchableTerms +
            offer.commercialFacts.searchablePieces +
            [offer.category]
        )

        let affinityTerms = sanitizeAtomicTerms(offer.regionTags)
        let broadRecallTokens = sanitizeAtomicTerms(providerTerms + capabilityTerms + affinityTerms + offer.regionAliases)
        let semanticConcepts = sanitizeTextBlocks([offer.summary, offer.semantic.notes].compactMap { $0 })
        let descriptiveDetailBlocks = sanitizeTextBlocks(
            [offer.summary, offer.semantic.notes].compactMap { $0 }
        )
        let hardConstraints = sanitizeTextBlocks(inferHardConstraints(from: semanticConcepts + sourceTextBlocks))
        let softPreferences = sanitizeTextBlocks(inferSoftPreferences(from: semanticConcepts + sourceTextBlocks))
        let offerCommercialInputs: [ExchangeIndexedOfferSurface.CommercialConstraint] =
            offer.commercialFacts.searchablePieces.map {
                ExchangeIndexedOfferSurface.CommercialConstraint(text: $0, isHard: isHardConstraint($0))
            }
        let commercialConstraints = sanitizeOfferCommercialConstraints(offerCommercialInputs)
        let offerTimeInputs: [ExchangeIndexedOfferSurface.TimeAvailabilityConstraint] = [
            ExchangeIndexedOfferSurface.TimeAvailabilityConstraint(
                text: offer.fulfillment.leadTimeNote ?? "",
                isHard: isHardConstraint(offer.fulfillment.leadTimeNote)
            ),
            ExchangeIndexedOfferSurface.TimeAvailabilityConstraint(
                text: offer.fulfillment.capacityNote ?? "",
                isHard: false
            ),
            ExchangeIndexedOfferSurface.TimeAvailabilityConstraint(
                text: offer.commercialFacts.availabilityNote ?? "",
                isHard: false
            )
        ]
        let timeAvailabilityConstraints = sanitizeOfferTimeConstraints(offerTimeInputs)

        return ExchangeIndexedOfferSurface(
            id: offer.id,
            offerID: offer.id,
            title: offer.title,
            summary: offer.summary,
            category: offer.category,
            freeTextCategory: offer.category,
            providerTerms: providerTerms,
            objectIdentityTerms: objectIdentityTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: affinityTerms,
            broadRecallTokens: broadRecallTokens,
            semanticConcepts: semanticConcepts,
            descriptiveDetailBlocks: descriptiveDetailBlocks,
            packageSlices: packageSlices,
            faqSlices: faqSlices,
            hardConstraints: hardConstraints,
            softPreferences: softPreferences,
            commercialConstraints: commercialConstraints,
            fulfillment: .init(
                pricingMode: offer.fulfillment.pricingMode.rawValue,
                commitmentMode: offer.fulfillment.commitmentMode.rawValue,
                remoteFriendly: offer.fulfillment.remoteFriendly,
                leadTimeNote: offer.fulfillment.leadTimeNote,
                capacityNote: offer.fulfillment.capacityNote,
                serviceAreaNote: offer.commercialFacts.serviceAreaNote
            ),
            timeAvailabilityConstraints: timeAvailabilityConstraints,
            contactOrPolicyText: contactPolicyText,
            sourceTextBlocks: sourceTextBlocks,
            serviceAreas: offer.effectiveServiceAreas,
            visibility: offer.visibility.rawValue,
            status: offer.status.rawValue,
            updatedAt: offer.updatedAt,
            schemaVersion: 1
        )
    }
}

private extension ExchangeIndexedProviderSurfaceBuilder {
    func sanitizeTextBlocks(_ values: [String?]) -> [String] {
        ExchangePublicProfileScaffoldText.filteredBlocks(values)
    }

    func sanitizeAtomicTerms(_ values: [String?]) -> [String] {
        let blocks = sanitizeTextBlocks(values)
        var seen = Set<String>()
        var out: [String] = []
        for block in blocks {
            for token in splitAtomicTokens(from: block) {
                let normalized = token.lowercased()
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                out.append(normalized)
            }
        }
        return out.sorted()
    }

    func splitAtomicTokens(from value: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;/|\n")
        let parts = value.components(separatedBy: separators)
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                guard !token.isEmpty else { return false }
                guard token.count <= 120 else { return false }
                guard !token.contains(",") else { return false }
                let words = token.split(whereSeparator: \.isWhitespace).count
                return words <= 8
            }
    }

    func inferHardConstraints(from values: [String]) -> [String] {
        values.filter(isHardConstraint)
    }

    func inferSoftPreferences(from values: [String]) -> [String] {
        values.filter { value in
            let lower = value.lowercased()
            return lower.contains("prefer") ||
                lower.contains("open to") ||
                lower.contains("accepts") ||
                lower.contains("would like")
        }
    }

    func isHardConstraint(_ value: String?) -> Bool {
        guard let value else { return false }
        let lower = value.lowercased()
        return lower.contains("must") ||
            lower.contains("required") ||
            lower.contains("only") ||
            lower.contains("exact") ||
            lower.contains("excluded") ||
            lower.contains("not allowed")
    }

    func sanitizeProviderCommercialConstraints(
        _ values: [ExchangeIndexedProviderSurface.CommercialConstraint]
    ) -> [ExchangeIndexedProviderSurface.CommercialConstraint] {
        var seen = Set<String>()
        var out: [ExchangeIndexedProviderSurface.CommercialConstraint] = []
        for value in values {
            let trimmed = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(.init(text: trimmed, isHard: value.isHard))
        }
        return out
    }

    func sanitizeProviderTimeConstraints(
        _ values: [ExchangeIndexedProviderSurface.TimeAvailabilityConstraint]
    ) -> [ExchangeIndexedProviderSurface.TimeAvailabilityConstraint] {
        var seen = Set<String>()
        var out: [ExchangeIndexedProviderSurface.TimeAvailabilityConstraint] = []
        for value in values {
            let trimmed = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(.init(text: trimmed, isHard: value.isHard))
        }
        return out
    }

    func sanitizeOfferTimeConstraints(
        _ values: [ExchangeIndexedOfferSurface.TimeAvailabilityConstraint]
    ) -> [ExchangeIndexedOfferSurface.TimeAvailabilityConstraint] {
        var seen = Set<String>()
        var out: [ExchangeIndexedOfferSurface.TimeAvailabilityConstraint] = []
        for value in values {
            let trimmed = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(.init(text: trimmed, isHard: value.isHard))
        }
        return out
    }

    func sanitizeOfferCommercialConstraints(
        _ values: [ExchangeIndexedOfferSurface.CommercialConstraint]
    ) -> [ExchangeIndexedOfferSurface.CommercialConstraint] {
        var seen = Set<String>()
        var out: [ExchangeIndexedOfferSurface.CommercialConstraint] = []
        for value in values {
            let trimmed = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(.init(text: trimmed, isHard: value.isHard))
        }
        return out
    }
}
