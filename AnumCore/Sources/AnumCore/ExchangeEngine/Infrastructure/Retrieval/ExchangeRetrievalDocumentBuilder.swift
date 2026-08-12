import Foundation

#if DEBUG
@inline(__always)
private func exRetrievalDocBuilderLog(_ message: @autoclosure () -> String) {
    print("[ExchangeRetrievalDocumentBuilder] \(message())")
}
#else
@inline(__always)
private func exRetrievalDocBuilderLog(_ message: @autoclosure () -> String) { }
#endif

/// Builds retrieval documents from public profiles + offers.
///
/// Architecture:
/// - one offer => one offer retrieval doc
/// - one public profile may yield:
///   - one capability doc (work / semantic capability)
///   - one seeking doc (openTo + listed offers text), when non-empty
///   - one affinity doc (interests), when non-empty
///
/// Important:
/// - This is retrieval projection only
/// - It must not mutate domain state
/// - It should preserve semantic separation between provider/capability/affinity surfaces
public struct ExchangeRetrievalDocumentBuilder: Sendable {
    private let placeResolver: ExchangeLocalPlaceResolver

    public init(placeResolver: ExchangeLocalPlaceResolver = ExchangeLocalPlaceResolver()) {
        self.placeResolver = placeResolver
    }

    public func buildDocuments(
        counterparties: [ExchangeCounterparty],
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> [ExchangeRetrievalDocument] {
        exRetrievalDocBuilderLog(
            "buildDocuments(counterparties) start count=\(counterparties.count) source=\(sourceKind.rawValue)"
        )

        var documents: [ExchangeRetrievalDocument] = []
        documents.reserveCapacity(counterparties.count * 4)

        for counterparty in counterparties {
            guard let profile = counterparty.publicProfile else { continue }

            if shouldEmitProfileIntroContent(profile: profile) {
                documents.append(
                    buildProfileIntroDocument(
                        counterparty: counterparty,
                        profile: profile,
                        sourceKind: sourceKind
                    )
                )
            }

            if shouldEmitProfileAboutContent(profile: profile) {
                documents.append(
                    buildProfileAboutDocument(
                        counterparty: counterparty,
                        profile: profile,
                        sourceKind: sourceKind
                    )
                )
            }

            if shouldEmitProfileCapabilityContent(profile: profile) {
                documents.append(
                    buildCapabilityDocument(
                        counterparty: counterparty,
                        profile: profile,
                        sourceKind: sourceKind
                    )
                )
            }

            if shouldEmitSeekingDocument(profile: profile) {
                documents.append(
                    buildSeekingDocument(
                        counterparty: counterparty,
                        profile: profile,
                        sourceKind: sourceKind
                    )
                )
            }

            if shouldEmitAffinityDocument(profile: profile) {
                documents.append(
                    buildAffinityDocument(
                        counterparty: counterparty,
                        profile: profile,
                        sourceKind: sourceKind
                    )
                )
            }
        }

        let final = dedupe(documents)
        exRetrievalDocBuilderLog("buildDocuments(counterparties) done docs=\(final.count)")
        return final
    }

    public func buildDocuments(
        matches: [ExchangeDirectoryMatch],
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> [ExchangeRetrievalDocument] {
        exRetrievalDocBuilderLog(
            "buildDocuments(matches) start count=\(matches.count) source=\(sourceKind.rawValue)"
        )

        var documents: [ExchangeRetrievalDocument] = []
        documents.reserveCapacity(matches.count * 5)

        var preservedRemoteDocumentCount = 0
        var preservedEmbeddedDocumentCount = 0
        var rebuiltFallbackDocumentCount = 0

        for match in matches {
            let remoteDocuments = match.retrievalDocuments.filter { document in
                document.sourceKind == sourceKind || sourceKind == .remote
            }

            if !remoteDocuments.isEmpty,
               !remoteDocuments.contains(where: retrievalDocumentContainsGeneratedScaffold) {
                documents.append(contentsOf: remoteDocuments)
                preservedRemoteDocumentCount += remoteDocuments.count
                preservedEmbeddedDocumentCount += remoteDocuments.filter(\.hasEmbedding).count

                exRetrievalDocBuilderLog(
                    "buildDocuments(matches) preserved remote docs matchID=\(match.id) docs=\(remoteDocuments.count) embedded=\(remoteDocuments.filter(\.hasEmbedding).count)"
                )

                continue
            }

            let counterparty = match.counterparty
            let profile = match.publicProfile ?? counterparty.publicProfile

            if let profile {
                if shouldEmitProfileIntroContent(profile: profile) {
                    documents.append(
                        buildProfileIntroDocument(
                            counterparty: counterparty,
                            profile: profile,
                            sourceKind: sourceKind
                        )
                    )
                    rebuiltFallbackDocumentCount += 1
                }

                if shouldEmitProfileAboutContent(profile: profile) {
                    documents.append(
                        buildProfileAboutDocument(
                            counterparty: counterparty,
                            profile: profile,
                            sourceKind: sourceKind
                        )
                    )
                    rebuiltFallbackDocumentCount += 1
                }

                if shouldEmitProfileCapabilityContent(profile: profile) {
                    documents.append(
                        buildCapabilityDocument(
                            counterparty: counterparty,
                            profile: profile,
                            sourceKind: sourceKind
                        )
                    )
                    rebuiltFallbackDocumentCount += 1
                }

                if shouldEmitSeekingDocument(profile: profile) {
                    documents.append(
                        buildSeekingDocument(
                            counterparty: counterparty,
                            profile: profile,
                            sourceKind: sourceKind
                        )
                    )
                    rebuiltFallbackDocumentCount += 1
                }

                if shouldEmitAffinityDocument(profile: profile) {
                    documents.append(
                        buildAffinityDocument(
                            counterparty: counterparty,
                            profile: profile,
                            sourceKind: sourceKind
                        )
                    )
                    rebuiltFallbackDocumentCount += 1
                }
            }

            for offer in match.offers where shouldIndex(offer: offer) {
                documents.append(
                    buildOfferDocument(
                        counterparty: counterparty,
                        profile: profile,
                        offer: offer,
                        sourceKind: sourceKind
                    )
                )
                documents.append(
                    contentsOf: buildOfferPackageDocuments(
                        counterparty: counterparty,
                        profile: profile,
                        offer: offer,
                        sourceKind: sourceKind
                    )
                )
                documents.append(
                    contentsOf: buildOfferFAQDocuments(
                        counterparty: counterparty,
                        profile: profile,
                        offer: offer,
                        sourceKind: sourceKind
                    )
                )
                documents.append(
                    buildOfferObjectDocument(
                        counterparty: counterparty,
                        profile: profile,
                        offer: offer,
                        sourceKind: sourceKind
                    )
                )
                rebuiltFallbackDocumentCount += 2
            }
        }

        let final = dedupe(documents)
        exRetrievalDocBuilderLog(
            "buildDocuments(matches) done docs=\(final.count) preservedRemote=\(preservedRemoteDocumentCount) preservedEmbedded=\(preservedEmbeddedDocumentCount) rebuiltFallback=\(rebuiltFallbackDocumentCount)"
        )
        return final
    }

    public func buildDocuments(
        profile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer],
        counterpartyID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> [ExchangeRetrievalDocument] {
        exRetrievalDocBuilderLog(
            "buildDocuments(profile+offers) start profileID=\(profile.id) offers=\(offers.count) source=\(sourceKind.rawValue)"
        )

        let syntheticCounterparty = ExchangeCounterparty(
            id: counterpartyID,
            kind: .secretaryNode,
            displayName: profile.displayName ?? counterpartyID,
            source: .relayNetwork,
            identity: .init(
                nodeID: profile.nodeID,
                publicKeyID: nil,
                verification: .unverified
            ),
            publicProfile: profile,
            tags: normalizedTerms(
                profile.offers.filter { !ExchangePublicProfileScaffoldText.isGenerated($0) } +
                profile.openTo.filter { !ExchangePublicProfileScaffoldText.isGenerated($0) } +
                profile.activityTags +
                profile.regionTags +
                profile.interests
            ),
            semantic: .init(
                activities: [],
                serviceCategories: normalizedTerms(profile.semantic.domains),
                productCategories: [],
                marketTags: normalizedTerms(profile.semantic.intentKinds),
                placeTags: normalizedTerms(profile.regionTags)
            ),
            contactRoutes: [],
            status: mapCounterpartyStatus(profile.availability)
        )

        var documents: [ExchangeRetrievalDocument] = []

        if shouldEmitProfileIntroContent(profile: profile) {
            documents.append(
                buildProfileIntroDocument(
                    counterparty: syntheticCounterparty,
                    profile: profile,
                    sourceKind: sourceKind
                )
            )
        }

        if shouldEmitProfileAboutContent(profile: profile) {
            documents.append(
                buildProfileAboutDocument(
                    counterparty: syntheticCounterparty,
                    profile: profile,
                    sourceKind: sourceKind
                )
            )
        }

        if shouldEmitProfileCapabilityContent(profile: profile) {
            documents.append(
                buildCapabilityDocument(
                    counterparty: syntheticCounterparty,
                    profile: profile,
                    sourceKind: sourceKind
                )
            )
        }

        if shouldEmitSeekingDocument(profile: profile) {
            documents.append(
                buildSeekingDocument(
                    counterparty: syntheticCounterparty,
                    profile: profile,
                    sourceKind: sourceKind
                )
            )
        }

        if shouldEmitAffinityDocument(profile: profile) {
            documents.append(
                buildAffinityDocument(
                    counterparty: syntheticCounterparty,
                    profile: profile,
                    sourceKind: sourceKind
                )
            )
        }

        for offer in offers where shouldIndex(offer: offer) {
            documents.append(
                buildOfferDocument(
                    counterparty: syntheticCounterparty,
                    profile: profile,
                    offer: offer,
                    sourceKind: sourceKind
                )
            )
            documents.append(
                contentsOf: buildOfferPackageDocuments(
                    counterparty: syntheticCounterparty,
                    profile: profile,
                    offer: offer,
                    sourceKind: sourceKind
                )
            )
            documents.append(
                contentsOf: buildOfferFAQDocuments(
                    counterparty: syntheticCounterparty,
                    profile: profile,
                    offer: offer,
                    sourceKind: sourceKind
                )
            )
            documents.append(
                buildOfferObjectDocument(
                    counterparty: syntheticCounterparty,
                    profile: profile,
                    offer: offer,
                    sourceKind: sourceKind
                )
            )
        }

        let final = dedupe(documents)
        exRetrievalDocBuilderLog("buildDocuments(profile+offers) done docs=\(final.count)")
        return final
    }

    public func build(
        from indexedSurface: ExchangeIndexedProviderSurface,
        counterpartyID: String? = nil,
        sourceKind: ExchangeRetrievalDocument.SourceKind = .local
    ) -> [ExchangeRetrievalDocument] {
        let ownerID = counterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? counterpartyID!
            : indexedSurface.nodeID

        var docs: [ExchangeRetrievalDocument] = []
        if shouldEmitIndexedProfileIntroDocument(indexedSurface: indexedSurface) {
            docs.append(
                buildIndexedProviderIntroDocument(
                    indexedSurface: indexedSurface,
                    counterpartyID: ownerID,
                    sourceKind: sourceKind
                )
            )
        }

        if shouldEmitIndexedProfileAboutDocument(indexedSurface: indexedSurface) {
            docs.append(
                buildIndexedProviderAboutDocument(
                    indexedSurface: indexedSurface,
                    counterpartyID: ownerID,
                    sourceKind: sourceKind
                )
            )
        }

        if shouldEmitIndexedCapabilityDocument(indexedSurface: indexedSurface) {
            docs.append(
                buildIndexedProviderCapabilityDocument(
                    indexedSurface: indexedSurface,
                    counterpartyID: ownerID,
                    sourceKind: sourceKind
                )
            )
        }

        if shouldEmitIndexedSeekingDocument(indexedSurface: indexedSurface) {
            docs.append(
                buildIndexedProviderSeekingDocument(
                    indexedSurface: indexedSurface,
                    counterpartyID: ownerID,
                    sourceKind: sourceKind
                )
            )
        }

        if shouldEmitIndexedAffinityDocument(indexedSurface: indexedSurface) {
            docs.append(
                buildIndexedProviderAffinityDocument(
                    indexedSurface: indexedSurface,
                    counterpartyID: ownerID,
                    sourceKind: sourceKind
                )
            )
        }

        for offer in indexedSurface.offers {
            guard let offerDoc = build(
                from: offer,
                parentSurface: indexedSurface,
                counterpartyID: ownerID,
                sourceKind: sourceKind
            ) else {
                continue
            }
            docs.append(offerDoc)
            docs.append(
                contentsOf: buildIndexedOfferPackageDocuments(
                    indexedOffer: offer,
                    parentSurface: indexedSurface,
                    counterpartyID: ownerID,
                    sourceKind: sourceKind
                )
            )
            docs.append(
                contentsOf: buildIndexedOfferFAQDocuments(
                    indexedOffer: offer,
                    parentSurface: indexedSurface,
                    counterpartyID: ownerID,
                    sourceKind: sourceKind
                )
            )
            if let objectDoc = buildOfferObjectDocument(
                from: offer,
                parentSurface: indexedSurface,
                counterpartyID: ownerID,
                sourceKind: sourceKind
            ) {
                docs.append(objectDoc)
            }
        }

        return dedupe(docs)
    }

    public func build(
        from indexedOffer: ExchangeIndexedOfferSurface,
        parentSurface: ExchangeIndexedProviderSurface? = nil,
        counterpartyID: String? = nil,
        sourceKind: ExchangeRetrievalDocument.SourceKind = .local
    ) -> ExchangeRetrievalDocument? {
        guard shouldIndexIndexedOffer(indexedOffer) else { return nil }
        let ownerID = counterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? counterpartyID!
            : (parentSurface?.nodeID ?? indexedOffer.offerID)

        let atomicProviderTerms = sanitizeAtomicIndexedTerms(indexedOffer.providerTerms)
        let atomicCapabilityTerms = sanitizeAtomicIndexedTerms(indexedOffer.capabilityTerms)
        let atomicAffinityTerms = sanitizeAtomicIndexedTerms(indexedOffer.affinityTerms)
        let tags = normalizeIndexedTerms(indexedOffer.providerTerms + [indexedOffer.category].compactMap { $0 })
        let regionTags = normalizeIndexedTerms(parentSurface?.regions.regionTags ?? [])
        let canonicalRegionIDs = normalizeIndexedTerms(parentSurface?.regions.canonicalRegionIDs ?? [])
        let regionAliases = normalizeIndexedTerms(parentSurface?.regions.regionAliases ?? [])
        let parentRegionIDs = normalizeIndexedTerms(parentSurface?.regions.parentRegionIDs ?? [])

        let displayPrimary = compactNonBlank([
            indexedOffer.title,
            indexedOffer.summary,
            indexedOffer.freeTextCategory
        ]).joined(separator: ". ")

        let displaySecondary = tags.joined(separator: " ")

        let lexicalFallback = compactNonBlank([
            displayPrimary,
            displaySecondary
        ]).joined(separator: ". ")

        let semanticFallback = compactNonBlank([
            indexedOffer.descriptiveDetailBlocks?.joined(separator: ". "),
            indexedOffer.semanticConcepts.joined(separator: ". ")
        ]).joined(separator: ". ")

        let projection = indexedEnglishRetrievalProjection(
            canonicalEnglish: indexedOffer.canonicalEnglishRetrievalText,
            displayPrimary: displayPrimary,
            displaySecondary: displaySecondary,
            lexicalFallback: lexicalFallback,
            semanticFallback: semanticFallback
        )
        let usesEnglish = projection.canonicalEnglishRetrievalText != nil
        let filteredProviderTerms = englishFilteredIndexedTerms(atomicProviderTerms, usesEnglishOnlyProjection: usesEnglish)
        let filteredCapabilityTerms = englishFilteredIndexedTerms(atomicCapabilityTerms, usesEnglishOnlyProjection: usesEnglish)
        let filteredAffinityTerms = englishFilteredIndexedTerms(atomicAffinityTerms, usesEnglishOnlyProjection: usesEnglish)

        let filterTokens = normalizeIndexedTerms(
            tags +
            filteredProviderTerms +
            filteredCapabilityTerms +
            filteredAffinityTerms +
            sanitizeAtomicIndexedTerms(indexedOffer.broadRecallTokens) +
            regionTags +
            regionAliases
        )

        let serviceAreas = indexedOffer.serviceAreas

        return ExchangeRetrievalDocument(
            id: "offer::\(indexedOffer.offerID)",
            counterpartyID: ownerID,
            nodeID: parentSurface?.nodeID,
            publicProfileID: parentSurface?.publicProfileID,
            offerID: indexedOffer.offerID,
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: sourceKind,
            docKind: .offerDetail,
            sourceField: "offer_detail",
            visibility: indexedOffer.visibility,
            availability: parentSurface?.availability,
            accessMode: parentSurface?.reachability.accessMode,
            acceptingInbound: parentSurface?.reachability.acceptingInbound,
            routeableOnly: parentSurface?.reachability.routeableOnly,
            title: indexedOffer.title,
            summary: indexedOffer.summary,
            category: indexedOffer.category,
            tags: tags,
            regionTags: regionTags,
            canonicalRegionIDs: canonicalRegionIDs,
            regionAliases: regionAliases,
            parentRegionIDs: parentRegionIDs,
            serviceAreas: serviceAreas,
            primaryText: projection.primaryText,
            secondaryText: projection.secondaryText,
            lexicalText: projection.lexicalText,
            semanticText: projection.semanticText,
            canonicalEnglishRetrievalText: projection.canonicalEnglishRetrievalText,
            providerTerms: filteredProviderTerms,
            capabilityTerms: filteredCapabilityTerms,
            affinityTerms: filteredAffinityTerms,
            filterTokens: filterTokens,
            embedding: nil,
            updatedAt: indexedOffer.updatedAt
        )
    }
}

private extension ExchangeRetrievalDocumentBuilder {
    func resolvedProfileSlices(from indexed: ExchangeIndexedProviderSurface) -> ExchangeIndexedProviderRetrievalSlices {
        if let slices = indexed.retrievalSlices {
            var normalized = slices
            if normalized.introBlocks.isEmpty && !normalized.identityBlocks.isEmpty {
                normalized.introBlocks = normalized.identityBlocks
            }
            return normalized
        }
        let merged = indexed.sourceTextBlocks
        return ExchangeIndexedProviderRetrievalSlices(
            identityBlocks: [],
            introBlocks: [],
            aboutBlocks: merged,
            capabilityBlocks: [],
            seekingBlocks: [],
            affinityBlocks: [],
            regionBlocks: [],
            seekingTerms: []
        )
    }

    func buildIndexedProviderIntroDocument(
        indexedSurface: ExchangeIndexedProviderSurface,
        counterpartyID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let slices = resolvedProfileSlices(from: indexedSurface)
        let introBlocks = publishSafeCompactNonBlank(slices.introBlocks.map { Optional($0) })
        let title = ExchangePublicProfileScaffoldText.filteredOptional(indexedSurface.displayName)
            ?? indexedSurface.nodeID
        let primaryText = publishSafeCompactNonBlank(introBlocks.map { Optional($0) }).joined(separator: ". ")
        let summary = introBlocks.dropFirst().joined(separator: " · ")
        let providerTerms = sanitizeAtomicIndexedTerms(introBlocks)
        let filterTokens = normalizeIndexedTerms(
            providerTerms +
            indexedSurface.regions.regionTags +
            indexedSurface.regions.regionAliases
        )

        let projection = indexedEnglishRetrievalProjection(
            canonicalEnglish: indexedSurface.canonicalEnglishRetrievalText,
            displayPrimary: primaryText,
            displaySecondary: summary,
            lexicalFallback: primaryText,
            semanticFallback: primaryText
        )
        let usesEnglish = projection.canonicalEnglishRetrievalText != nil
        let filteredProviderTerms = englishFilteredIndexedTerms(providerTerms, usesEnglishOnlyProjection: usesEnglish)

        return ExchangeRetrievalDocument(
            id: "profile-intro::\(indexedSurface.publicProfileID)",
            counterpartyID: counterpartyID,
            nodeID: indexedSurface.nodeID,
            publicProfileID: indexedSurface.publicProfileID,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfile,
            sourceKind: sourceKind,
            docKind: .profileIntro,
            sourceField: "profile_intro",
            visibility: indexedSurface.visibility,
            availability: indexedSurface.availability,
            accessMode: indexedSurface.reachability.accessMode,
            acceptingInbound: indexedSurface.reachability.acceptingInbound,
            routeableOnly: indexedSurface.reachability.routeableOnly,
            title: title,
            summary: summary.isEmpty ? nil : summary,
            category: nil,
            tags: providerTerms,
            regionTags: normalizeIndexedTerms(indexedSurface.regions.regionTags),
            canonicalRegionIDs: normalizeIndexedTerms(indexedSurface.regions.canonicalRegionIDs),
            regionAliases: normalizeIndexedTerms(indexedSurface.regions.regionAliases),
            parentRegionIDs: normalizeIndexedTerms(indexedSurface.regions.parentRegionIDs),
            primaryText: projection.primaryText,
            secondaryText: projection.secondaryText,
            lexicalText: projection.lexicalText,
            semanticText: projection.semanticText,
            canonicalEnglishRetrievalText: projection.canonicalEnglishRetrievalText,
            providerTerms: filteredProviderTerms,
            capabilityTerms: [],
            affinityTerms: [],
            filterTokens: filterTokens,
            embedding: nil,
            updatedAt: indexedSurface.updatedAt
        )
    }

    func buildIndexedProviderAboutDocument(
        indexedSurface: ExchangeIndexedProviderSurface,
        counterpartyID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let slices = resolvedProfileSlices(from: indexedSurface)
        let aboutBlocks = publishSafeCompactNonBlank(slices.aboutBlocks.map { Optional($0) })
        let title = ExchangePublicProfileScaffoldText.filteredOptional(indexedSurface.displayName)
            ?? indexedSurface.nodeID
        let primaryText = aboutBlocks.joined(separator: ". ")
        let secondaryText = ""
        let lexicalText = primaryText
        let tags = normalizeIndexedTerms(aboutBlocks)
        let filterTokens = normalizeIndexedTerms(
            tags +
            indexedSurface.regions.regionTags +
            indexedSurface.regions.regionAliases
        )

        return ExchangeRetrievalDocument(
            id: "profile-about::\(indexedSurface.publicProfileID)",
            counterpartyID: counterpartyID,
            nodeID: indexedSurface.nodeID,
            publicProfileID: indexedSurface.publicProfileID,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileCapability,
            sourceKind: sourceKind,
            docKind: .profileAbout,
            sourceField: "profile_about",
            visibility: indexedSurface.visibility,
            availability: indexedSurface.availability,
            accessMode: indexedSurface.reachability.accessMode,
            acceptingInbound: indexedSurface.reachability.acceptingInbound,
            routeableOnly: indexedSurface.reachability.routeableOnly,
            title: title,
            summary: aboutBlocks.first,
            category: nil,
            tags: tags,
            regionTags: normalizeIndexedTerms(indexedSurface.regions.regionTags),
            canonicalRegionIDs: normalizeIndexedTerms(indexedSurface.regions.canonicalRegionIDs),
            regionAliases: normalizeIndexedTerms(indexedSurface.regions.regionAliases),
            parentRegionIDs: normalizeIndexedTerms(indexedSurface.regions.parentRegionIDs),
            primaryText: primaryText,
            secondaryText: secondaryText,
            lexicalText: lexicalText,
            semanticText: primaryText,
            canonicalEnglishRetrievalText: indexedSurface.canonicalEnglishRetrievalText,
            providerTerms: [],
            capabilityTerms: [],
            affinityTerms: [],
            filterTokens: filterTokens,
            embedding: nil,
            updatedAt: indexedSurface.updatedAt
        )
    }

    func buildIndexedProviderCapabilityDocument(
        indexedSurface: ExchangeIndexedProviderSurface,
        counterpartyID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let slices = resolvedProfileSlices(from: indexedSurface)
        let title = ExchangePublicProfileScaffoldText.filteredOptional(indexedSurface.displayName)
            ?? indexedSurface.nodeID
        let capabilityBlocks = publishSafeCompactNonBlank(slices.capabilityBlocks.map { Optional($0) })
        let tags = normalizeIndexedTerms(indexedSurface.capabilityTerms)
        let capabilityTerms = sanitizeAtomicIndexedTerms(indexedSurface.capabilityTerms)
        let filterTokens = normalizeIndexedTerms(
            tags +
            capabilityTerms +
            indexedSurface.regions.regionTags +
            indexedSurface.regions.regionAliases
        )

        let displayPrimary = capabilityBlocks.joined(separator: ". ")
        let displaySecondary = compactNonBlank([
            indexedSurface.softPreferences.joined(separator: ". ")
        ]).joined(separator: ". ")

        let semanticFallback = compactNonBlank([
            capabilityBlocks.joined(separator: ". "),
            indexedSurface.semanticConcepts.joined(separator: ". "),
            indexedSurface.softPreferences.joined(separator: ". ")
        ]).joined(separator: ". ")

        let projection = indexedEnglishRetrievalProjection(
            canonicalEnglish: indexedSurface.canonicalEnglishRetrievalText,
            displayPrimary: displayPrimary,
            displaySecondary: displaySecondary,
            lexicalFallback: compactNonBlank([displayPrimary, displaySecondary]).joined(separator: ". "),
            semanticFallback: semanticFallback
        )
        let usesEnglish = projection.canonicalEnglishRetrievalText != nil
        let filteredCapabilityTerms = englishFilteredIndexedTerms(capabilityTerms, usesEnglishOnlyProjection: usesEnglish)

        return ExchangeRetrievalDocument(
            id: "profile-capability::\(indexedSurface.publicProfileID)",
            counterpartyID: counterpartyID,
            nodeID: indexedSurface.nodeID,
            publicProfileID: indexedSurface.publicProfileID,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileCapability,
            sourceKind: sourceKind,
            docKind: .profileCapability,
            sourceField: "profile_capability",
            visibility: indexedSurface.visibility,
            availability: indexedSurface.availability,
            accessMode: indexedSurface.reachability.accessMode,
            acceptingInbound: indexedSurface.reachability.acceptingInbound,
            routeableOnly: indexedSurface.reachability.routeableOnly,
            title: title,
            summary: capabilityBlocks.first,
            category: nil,
            tags: tags,
            regionTags: normalizeIndexedTerms(indexedSurface.regions.regionTags),
            canonicalRegionIDs: normalizeIndexedTerms(indexedSurface.regions.canonicalRegionIDs),
            regionAliases: normalizeIndexedTerms(indexedSurface.regions.regionAliases),
            parentRegionIDs: normalizeIndexedTerms(indexedSurface.regions.parentRegionIDs),
            primaryText: projection.primaryText,
            secondaryText: projection.secondaryText,
            lexicalText: projection.lexicalText,
            semanticText: projection.semanticText,
            canonicalEnglishRetrievalText: projection.canonicalEnglishRetrievalText,
            providerTerms: [],
            capabilityTerms: filteredCapabilityTerms,
            affinityTerms: [],
            filterTokens: filterTokens,
            embedding: nil,
            updatedAt: indexedSurface.updatedAt
        )
    }

    func buildIndexedProviderSeekingDocument(
        indexedSurface: ExchangeIndexedProviderSurface,
        counterpartyID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let slices = resolvedProfileSlices(from: indexedSurface)
        let title = indexedSurface.displayName ?? indexedSurface.nodeID
        let blocks = slices.seekingBlocks
        let primaryText = compactNonBlank([title, blocks.first]).joined(separator: " · ")
        let secondaryText = compactNonBlank(Array(blocks.dropFirst())).joined(separator: ". ")
        let joinedSeeking = compactNonBlank(blocks).joined(separator: ". ")
        let lexicalText = compactNonBlank([primaryText, secondaryText]).joined(separator: ". ")

        let seekingTerms = sanitizeAtomicIndexedTerms(slices.seekingTerms)
        let tags = normalizeIndexedTerms(seekingTerms + indexedSurface.providerTerms)
        let providerTerms = sanitizeAtomicIndexedTerms(indexedSurface.providerTerms)
        let filterTokens = normalizeIndexedTerms(
            tags +
            seekingTerms +
            providerTerms +
            indexedSurface.regions.regionTags +
            indexedSurface.regions.regionAliases
        )

        let projection = indexedEnglishRetrievalProjection(
            canonicalEnglish: indexedSurface.canonicalEnglishRetrievalText,
            displayPrimary: primaryText,
            displaySecondary: secondaryText,
            lexicalFallback: lexicalText,
            semanticFallback: joinedSeeking
        )
        let usesEnglish = projection.canonicalEnglishRetrievalText != nil
        let filteredSeekingTerms = englishFilteredIndexedTerms(seekingTerms, usesEnglishOnlyProjection: usesEnglish)
        let filteredProviderTerms = englishFilteredIndexedTerms(providerTerms, usesEnglishOnlyProjection: usesEnglish)

        return ExchangeRetrievalDocument(
            id: "profile-seeking::\(indexedSurface.publicProfileID)",
            counterpartyID: counterpartyID,
            nodeID: indexedSurface.nodeID,
            publicProfileID: indexedSurface.publicProfileID,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileSeeking,
            sourceKind: sourceKind,
            docKind: .profileSeeking,
            sourceField: "profile_seeking",
            visibility: indexedSurface.visibility,
            availability: indexedSurface.availability,
            accessMode: indexedSurface.reachability.accessMode,
            acceptingInbound: indexedSurface.reachability.acceptingInbound,
            routeableOnly: indexedSurface.reachability.routeableOnly,
            title: title,
            summary: joinedSeeking.isEmpty ? nil : String(joinedSeeking.prefix(400)),
            category: nil,
            tags: tags,
            regionTags: normalizeIndexedTerms(indexedSurface.regions.regionTags),
            canonicalRegionIDs: normalizeIndexedTerms(indexedSurface.regions.canonicalRegionIDs),
            regionAliases: normalizeIndexedTerms(indexedSurface.regions.regionAliases),
            parentRegionIDs: normalizeIndexedTerms(indexedSurface.regions.parentRegionIDs),
            primaryText: projection.primaryText,
            secondaryText: projection.secondaryText,
            lexicalText: projection.lexicalText,
            semanticText: projection.semanticText,
            canonicalEnglishRetrievalText: projection.canonicalEnglishRetrievalText,
            providerTerms: filteredProviderTerms,
            capabilityTerms: filteredSeekingTerms,
            affinityTerms: [],
            filterTokens: filterTokens,
            embedding: nil,
            updatedAt: indexedSurface.updatedAt
        )
    }

    func buildIndexedProviderAffinityDocument(
        indexedSurface: ExchangeIndexedProviderSurface,
        counterpartyID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let slices = resolvedProfileSlices(from: indexedSurface)
        let title = indexedSurface.displayName ?? indexedSurface.nodeID
        let affinityJoined = compactNonBlank(slices.affinityBlocks).joined(separator: ". ")
        let primaryText = compactNonBlank([title, affinityJoined]).joined(separator: ". ")
        let secondaryText = ""
        let lexicalText = compactNonBlank([title, indexedSurface.headline, affinityJoined]).joined(separator: ". ")
        let tags = normalizeIndexedTerms(indexedSurface.affinityTerms)
        let providerTerms = sanitizeAtomicIndexedTerms(indexedSurface.providerTerms)
        let affinityTerms = sanitizeAtomicIndexedTerms(indexedSurface.affinityTerms)
        let filterTokens = normalizeIndexedTerms(
            tags +
            providerTerms +
            affinityTerms +
            indexedSurface.regions.regionTags +
            indexedSurface.regions.regionAliases
        )

        let projection = indexedEnglishRetrievalProjection(
            canonicalEnglish: indexedSurface.canonicalEnglishRetrievalText,
            displayPrimary: primaryText,
            displaySecondary: secondaryText,
            lexicalFallback: lexicalText,
            semanticFallback: affinityJoined
        )
        let usesEnglish = projection.canonicalEnglishRetrievalText != nil
        let filteredProviderTerms = englishFilteredIndexedTerms(providerTerms, usesEnglishOnlyProjection: usesEnglish)
        let filteredAffinityTerms = englishFilteredIndexedTerms(affinityTerms, usesEnglishOnlyProjection: usesEnglish)

        return ExchangeRetrievalDocument(
            id: "profile-affinity::\(indexedSurface.publicProfileID)",
            counterpartyID: counterpartyID,
            nodeID: indexedSurface.nodeID,
            publicProfileID: indexedSurface.publicProfileID,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileAffinity,
            sourceKind: sourceKind,
            docKind: .profileAffinity,
            sourceField: "profile_affinity",
            visibility: indexedSurface.visibility,
            availability: indexedSurface.availability,
            accessMode: indexedSurface.reachability.accessMode,
            acceptingInbound: indexedSurface.reachability.acceptingInbound,
            routeableOnly: indexedSurface.reachability.routeableOnly,
            title: title,
            summary: indexedSurface.headline,
            category: nil,
            tags: tags,
            regionTags: normalizeIndexedTerms(indexedSurface.regions.regionTags),
            canonicalRegionIDs: normalizeIndexedTerms(indexedSurface.regions.canonicalRegionIDs),
            regionAliases: normalizeIndexedTerms(indexedSurface.regions.regionAliases),
            parentRegionIDs: normalizeIndexedTerms(indexedSurface.regions.parentRegionIDs),
            primaryText: projection.primaryText,
            secondaryText: projection.secondaryText,
            lexicalText: projection.lexicalText,
            semanticText: projection.semanticText,
            canonicalEnglishRetrievalText: projection.canonicalEnglishRetrievalText,
            providerTerms: filteredProviderTerms,
            capabilityTerms: [],
            affinityTerms: filteredAffinityTerms,
            filterTokens: filterTokens,
            embedding: nil,
            updatedAt: indexedSurface.updatedAt
        )
    }

    func shouldEmitIndexedProfileIntroDocument(indexedSurface: ExchangeIndexedProviderSurface) -> Bool {
        let slices = resolvedProfileSlices(from: indexedSurface)
        return !publishSafeCompactNonBlank(
            (slices.introBlocks.isEmpty ? slices.identityBlocks : slices.introBlocks).map { Optional($0) }
        ).isEmpty
    }

    func shouldEmitIndexedProfileAboutDocument(indexedSurface: ExchangeIndexedProviderSurface) -> Bool {
        let slices = resolvedProfileSlices(from: indexedSurface)
        return !publishSafeCompactNonBlank(slices.aboutBlocks.map { Optional($0) }).isEmpty
    }

    func shouldEmitIndexedCapabilityDocument(indexedSurface: ExchangeIndexedProviderSurface) -> Bool {
        let slices = resolvedProfileSlices(from: indexedSurface)
        let capabilityBlocks = publishSafeCompactNonBlank(slices.capabilityBlocks.map { Optional($0) })
        if !capabilityBlocks.isEmpty { return true }

        let terms = sanitizeAtomicIndexedTerms(
            indexedSurface.capabilityTerms.filter { !ExchangePublicProfileScaffoldText.isGenerated($0) }
        )
        if !terms.isEmpty { return true }

        return !publishSafeCompactNonBlank(indexedSurface.softPreferences.map { Optional($0) }).isEmpty
    }

    func shouldEmitProfileIntroContent(profile: ExchangePublicNodeProfile) -> Bool {
        !publishSafeCompactNonBlank([
            profile.displayName,
            profile.headline
        ]).isEmpty
    }

    func shouldEmitProfileAboutContent(profile: ExchangePublicNodeProfile) -> Bool {
        let fields: [String?] = [
            profile.summary,
            profile.semantic.notes,
            profile.approach.note
        ] + profile.activityTags.map { Optional($0) } + profile.excludedTopics.map { Optional($0) }
        return !ExchangePublicProfileScaffoldText.filteredBlocks(fields).isEmpty
    }

    func shouldEmitProfileCapabilityContent(profile: ExchangePublicNodeProfile) -> Bool {
        let capabilityFields: [String?] = [
            profile.semantic.domains.joined(separator: " "),
            profile.semantic.intentKinds.joined(separator: " "),
            profile.semantic.audienceKinds.map(\.rawValue).joined(separator: " "),
            profile.semantic.fulfillmentModes.map(\.rawValue).joined(separator: " ")
        ].filter { !$0.isEmpty }.map { Optional($0) }
        if !ExchangePublicProfileScaffoldText.filteredBlocks(capabilityFields).isEmpty {
            return true
        }
        return !normalizedTerms(
            profile.semantic.searchableTerms +
            profile.semantic.domains +
            profile.semantic.intentKinds
        ).isEmpty
    }

    func shouldEmitIndexedCapabilityContent(profile: ExchangePublicNodeProfile) -> Bool {
        shouldEmitProfileCapabilityContent(profile: profile)
    }

    func shouldEmitIndexedSeekingDocument(indexedSurface: ExchangeIndexedProviderSurface) -> Bool {
        let slices = resolvedProfileSlices(from: indexedSurface)
        let seekingBlocks = ExchangePublicProfileScaffoldText.filteredBlocks(
            slices.seekingBlocks.map { Optional($0) }
        )
        let seekingTerms = sanitizeAtomicIndexedTerms(
            slices.seekingTerms.filter { !ExchangePublicProfileScaffoldText.isGenerated($0) }
        )
        return !seekingBlocks.isEmpty || !seekingTerms.isEmpty
    }

    func shouldEmitIndexedAffinityDocument(indexedSurface: ExchangeIndexedProviderSurface) -> Bool {
        let slices = resolvedProfileSlices(from: indexedSurface)
        return !normalizeIndexedTerms(
            indexedSurface.affinityTerms + slices.affinityBlocks
        ).isEmpty
    }

    func shouldIndexIndexedOffer(_ offer: ExchangeIndexedOfferSurface) -> Bool {
        let status = offer.status.lowercased()
        let visibility = offer.visibility.lowercased()
        return status == ExchangeOffer.Status.active.rawValue.lowercased() &&
            (visibility == ExchangeOffer.Visibility.publicDiscoverable.rawValue.lowercased() ||
             visibility == ExchangeOffer.Visibility.limitedSurface.rawValue.lowercased())
    }

    func sanitizeAtomicIndexedTerms(_ values: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            guard normalized.count <= 120 else { continue }
            guard !normalized.contains(",") else { continue }
            let words = normalized.split(whereSeparator: \.isWhitespace).count
            guard words <= 8 else { continue }
            guard !seen.contains(normalized) else { continue }
            guard !ExchangePublicProfileScaffoldText.isGenerated(normalized) else { continue }
            seen.insert(normalized)
            out.append(normalized)
        }
        return out.sorted()
    }

    func retrievalDocumentContainsGeneratedScaffold(_ document: ExchangeRetrievalDocument) -> Bool {
        let fields: [String?] = [
            document.title,
            document.summary,
            document.primaryText,
            document.secondaryText,
            document.lexicalText,
            document.semanticText
        ]
        return fields
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .contains(where: ExchangePublicProfileScaffoldText.isGenerated)
    }

    func publishSafeCompactNonBlank(_ values: [String?]) -> [String] {
        compactNonBlank(
            ExchangePublicProfileScaffoldText.filteredBlocks(values).map { Optional($0) }
        )
    }

    func publishSafeSummaryLine(for profile: ExchangePublicNodeProfile) -> String? {
        if let headline = ExchangePublicProfileScaffoldText.filteredOptional(profile.headline) {
            return headline
        }
        return ExchangePublicProfileScaffoldText.filteredOptional(profile.summary)
    }

    func normalizeIndexedTerms(_ values: [String]) -> [String] {
        normalizedTerms(values)
    }

    func buildProfileIntroDocument(
        counterparty: ExchangeCounterparty,
        profile: ExchangePublicNodeProfile,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let title = ExchangePublicProfileScaffoldText.filteredOptional(profile.displayName)
            ?? ExchangePublicProfileScaffoldText.filteredOptional(counterparty.displayName)
            ?? counterparty.displayName
        let introBlocks = publishSafeCompactNonBlank([
            profile.displayName,
            profile.headline
        ])
        let primaryText = introBlocks.joined(separator: ". ")
        let summary = profile.headline
        let providerTerms = normalizedTerms(introBlocks)
        let regionEvidence = mergedRegionEvidence(
            serverCanonicalIDs: profile.canonicalRegionIDs,
            serverParentIDs: profile.parentRegionIDs,
            serverRegionAliases: profile.regionAliases,
            tagRegionTags: profile.regionTags
        )

        return ExchangeRetrievalDocument(
            id: "profile-intro::\(profile.id)",
            counterpartyID: counterparty.id,
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfile,
            sourceKind: sourceKind,
            docKind: .profileIntro,
            sourceField: "profile_intro",
            visibility: profile.visibility.rawValue,
            availability: profile.availability.rawValue,
            accessMode: profile.reachability.accessMode.rawValue,
            acceptingInbound: profile.reachability.acceptingInbound,
            routeableOnly: profile.reachability.routeableOnly,
            title: title,
            summary: summary,
            category: nil,
            tags: providerTerms,
            regionTags: normalizedTerms(profile.regionTags),
            canonicalRegionIDs: regionEvidence.canonicalIDs,
            regionAliases: regionEvidence.aliases,
            parentRegionIDs: regionEvidence.parentIDs,
            primaryText: primaryText,
            secondaryText: "",
            lexicalText: primaryText,
            semanticText: primaryText,
            providerTerms: providerTerms,
            capabilityTerms: [],
            affinityTerms: [],
            filterTokens: normalizedTerms(providerTerms + profile.regionTags),
            embedding: nil,
            updatedAt: counterparty.updatedAt
        )
    }

    func buildProfileAboutDocument(
        counterparty: ExchangeCounterparty,
        profile: ExchangePublicNodeProfile,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let title = ExchangePublicProfileScaffoldText.filteredOptional(profile.displayName)
            ?? ExchangePublicProfileScaffoldText.filteredOptional(counterparty.displayName)
            ?? counterparty.displayName
        let aboutBlocks = publishSafeCompactNonBlank([
            profile.summary,
            profile.semantic.notes,
            profile.approach.note
        ] + profile.activityTags.map { Optional($0) } + profile.excludedTopics.map { Optional($0) })
        let primaryText = aboutBlocks.joined(separator: ". ")
        let tags = normalizedTerms(aboutBlocks)
        let regionEvidence = mergedRegionEvidence(
            serverCanonicalIDs: profile.canonicalRegionIDs,
            serverParentIDs: profile.parentRegionIDs,
            serverRegionAliases: profile.regionAliases,
            tagRegionTags: profile.regionTags
        )

        return ExchangeRetrievalDocument(
            id: "profile-about::\(profile.id)",
            counterpartyID: counterparty.id,
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileCapability,
            sourceKind: sourceKind,
            docKind: .profileAbout,
            sourceField: "profile_about",
            visibility: profile.visibility.rawValue,
            availability: profile.availability.rawValue,
            accessMode: profile.reachability.accessMode.rawValue,
            acceptingInbound: profile.reachability.acceptingInbound,
            routeableOnly: profile.reachability.routeableOnly,
            title: title,
            summary: aboutBlocks.first,
            category: nil,
            tags: tags,
            regionTags: normalizedTerms(profile.regionTags),
            canonicalRegionIDs: regionEvidence.canonicalIDs,
            regionAliases: regionEvidence.aliases,
            parentRegionIDs: regionEvidence.parentIDs,
            primaryText: primaryText,
            secondaryText: "",
            lexicalText: primaryText,
            semanticText: primaryText,
            providerTerms: [],
            capabilityTerms: [],
            affinityTerms: [],
            filterTokens: normalizedTerms(tags + profile.regionTags),
            embedding: nil,
            updatedAt: counterparty.updatedAt
        )
    }

    func buildCapabilityDocument(
        counterparty: ExchangeCounterparty,
        profile: ExchangePublicNodeProfile,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let title = ExchangePublicProfileScaffoldText.filteredOptional(profile.displayName)
            ?? ExchangePublicProfileScaffoldText.filteredOptional(counterparty.displayName)
            ?? counterparty.displayName

        let capabilityBlocks = publishSafeCompactNonBlank([
            profile.semantic.domains.joined(separator: " "),
            profile.semantic.intentKinds.joined(separator: " "),
            profile.semantic.audienceKinds.map(\.rawValue).joined(separator: " "),
            profile.semantic.fulfillmentModes.map(\.rawValue).joined(separator: " ")
        ].filter { !$0.isEmpty }.map { Optional($0) })

        let primaryText = capabilityBlocks.joined(separator: ". ")
        let secondaryText = ""
        let lexicalText = primaryText

        let semanticText = publishSafeCompactNonBlank([
            profile.semantic.domains.joined(separator: " "),
            profile.semantic.intentKinds.joined(separator: " "),
            profile.semantic.audienceKinds.map(\.rawValue).joined(separator: " "),
            profile.semantic.fulfillmentModes.map(\.rawValue).joined(separator: " ")
        ]).joined(separator: ". ")

        let tags = normalizedTerms(profile.semantic.searchableTerms)

        let capabilityTerms = normalizedTerms(
            profile.semantic.searchableTerms +
            profile.semantic.domains +
            profile.semantic.intentKinds +
            profile.semantic.audienceKinds.map(\.rawValue) +
            profile.semantic.fulfillmentModes.map(\.rawValue)
        )

        let filterTokens = normalizedTerms(
            tags +
            capabilityTerms +
            profile.regionTags
        )
        let regionEvidence = mergedRegionEvidence(
            serverCanonicalIDs: profile.canonicalRegionIDs,
            serverParentIDs: profile.parentRegionIDs,
            serverRegionAliases: profile.regionAliases,
            tagRegionTags: profile.regionTags
        )

        return ExchangeRetrievalDocument(
            id: "profile-capability::\(profile.id)",
            counterpartyID: counterparty.id,
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileCapability,
            sourceKind: sourceKind,
            docKind: .profileCapability,
            sourceField: "profile_capability",
            visibility: profile.visibility.rawValue,
            availability: profile.availability.rawValue,
            accessMode: profile.reachability.accessMode.rawValue,
            acceptingInbound: profile.reachability.acceptingInbound,
            routeableOnly: profile.reachability.routeableOnly,
            title: title,
            summary: capabilityBlocks.first,
            category: nil,
            tags: tags,
            regionTags: normalizedTerms(profile.regionTags),
            canonicalRegionIDs: regionEvidence.canonicalIDs,
            regionAliases: regionEvidence.aliases,
            parentRegionIDs: regionEvidence.parentIDs,
            primaryText: primaryText,
            secondaryText: secondaryText,
            lexicalText: lexicalText,
            semanticText: semanticText,
            providerTerms: [],
            capabilityTerms: capabilityTerms,
            affinityTerms: [],
            filterTokens: filterTokens,
            embedding: nil,
            updatedAt: counterparty.updatedAt
        )
    }

    func buildSeekingDocument(
        counterparty: ExchangeCounterparty,
        profile: ExchangePublicNodeProfile,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let title = ExchangePublicProfileScaffoldText.filteredOptional(profile.displayName)
            ?? ExchangePublicProfileScaffoldText.filteredOptional(counterparty.displayName)
            ?? counterparty.displayName
        let blocks = publishSafeCompactNonBlank(profile.openTo.map { Optional($0) })
        let primaryText = publishSafeCompactNonBlank([title, blocks.first]).joined(separator: " · ")
        let secondaryText = publishSafeCompactNonBlank(
            blocks.dropFirst().map { Optional($0) }
        ).joined(separator: ". ")
        let joined = blocks.joined(separator: ". ")
        let lexicalText = publishSafeCompactNonBlank([primaryText, secondaryText]).joined(separator: ". ")

        let capabilityTerms = normalizedTerms(
            profile.openTo.filter { !ExchangePublicProfileScaffoldText.isGenerated($0) }
        )
        let tags = normalizedTerms(capabilityTerms + [title].compactMap { $0 })
        let providerTerms = normalizedTerms(
            publishSafeCompactNonBlank([
                title,
                profile.headline,
                publishSafeSummaryLine(for: profile)
            ])
        )
        let filterTokens = normalizedTerms(
            tags +
            capabilityTerms +
            providerTerms +
            profile.regionTags
        )
        let regionEvidence = mergedRegionEvidence(
            serverCanonicalIDs: profile.canonicalRegionIDs,
            serverParentIDs: profile.parentRegionIDs,
            serverRegionAliases: profile.regionAliases,
            tagRegionTags: profile.regionTags
        )

        return ExchangeRetrievalDocument(
            id: "profile-seeking::\(profile.id)",
            counterpartyID: counterparty.id,
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileSeeking,
            sourceKind: sourceKind,
            docKind: .profileSeeking,
            sourceField: "profile_seeking",
            visibility: profile.visibility.rawValue,
            availability: profile.availability.rawValue,
            accessMode: profile.reachability.accessMode.rawValue,
            acceptingInbound: profile.reachability.acceptingInbound,
            routeableOnly: profile.reachability.routeableOnly,
            title: title,
            summary: joined.isEmpty ? nil : String(joined.prefix(400)),
            category: nil,
            tags: tags,
            regionTags: normalizedTerms(profile.regionTags),
            canonicalRegionIDs: regionEvidence.canonicalIDs,
            regionAliases: regionEvidence.aliases,
            parentRegionIDs: regionEvidence.parentIDs,
            primaryText: primaryText,
            secondaryText: secondaryText,
            lexicalText: lexicalText,
            semanticText: joined,
            providerTerms: providerTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: [],
            filterTokens: filterTokens,
            embedding: nil,
            updatedAt: counterparty.updatedAt
        )
    }

    func buildAffinityDocument(
        counterparty: ExchangeCounterparty,
        profile: ExchangePublicNodeProfile,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let title = profile.displayName ?? counterparty.displayName
        let summary = profile.summaryLine

        let interestsJoined = profile.interests.joined(separator: ". ")
        let primaryText = compactNonBlank([title, interestsJoined]).joined(separator: ". ")
        let secondaryText = ""

        let lexicalText = compactNonBlank([
            title,
            profile.headline,
            interestsJoined
        ]).joined(separator: ". ")

        let tags = normalizedTerms(profile.interests)

        let affinityTerms = normalizedTerms(profile.interests)

        let providerTerms = normalizedTerms([
            title,
            profile.headline,
            summary
        ].compactMap { $0 })

        let filterTokens = normalizedTerms(
            tags +
            affinityTerms +
            providerTerms +
            profile.regionTags
        )
        let regionEvidence = mergedRegionEvidence(
            serverCanonicalIDs: profile.canonicalRegionIDs,
            serverParentIDs: profile.parentRegionIDs,
            serverRegionAliases: profile.regionAliases,
            tagRegionTags: profile.regionTags
        )

        return ExchangeRetrievalDocument(
            id: "profile-affinity::\(profile.id)",
            counterpartyID: counterparty.id,
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileAffinity,
            sourceKind: sourceKind,
            docKind: .profileAffinity,
            sourceField: "profile_affinity",
            visibility: profile.visibility.rawValue,
            availability: profile.availability.rawValue,
            accessMode: profile.reachability.accessMode.rawValue,
            acceptingInbound: profile.reachability.acceptingInbound,
            routeableOnly: profile.reachability.routeableOnly,
            title: title,
            summary: profile.headline,
            category: nil,
            tags: tags,
            regionTags: normalizedTerms(profile.regionTags),
            canonicalRegionIDs: regionEvidence.canonicalIDs,
            regionAliases: regionEvidence.aliases,
            parentRegionIDs: regionEvidence.parentIDs,
            primaryText: primaryText,
            secondaryText: secondaryText,
            lexicalText: lexicalText,
            semanticText: "",
            providerTerms: providerTerms,
            capabilityTerms: [],
            affinityTerms: affinityTerms,
            filterTokens: filterTokens,
            embedding: nil,
            updatedAt: counterparty.updatedAt
        )
    }

    func buildOfferDocument(
        counterparty: ExchangeCounterparty,
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let title = offer.title
        let summary = offer.summary

        let primaryText = compactNonBlank([
            title,
            summary,
            offer.category
        ]).joined(separator: ". ")

        let secondaryText = compactNonBlank([
            offer.tags.joined(separator: " ")
        ]).joined(separator: ". ")

        let lexicalText = compactNonBlank([
            primaryText,
            secondaryText
        ]).joined(separator: ". ")

        let semanticText = compactNonBlank([
            offer.semantic.domains.joined(separator: " "),
            offer.semantic.serviceKinds.joined(separator: " "),
            offer.semantic.audienceKinds.map(\.rawValue).joined(separator: " "),
            offer.semantic.fulfillmentModes.map(\.rawValue).joined(separator: " "),
            offer.semantic.notes,
            offer.summary
        ]).joined(separator: ". ")

        let tags = normalizedTerms(
            offer.tags +
            [offer.category].compactMap { $0 }
        )

        let providerTerms = normalizedTerms(
            [offer.title] +
            [offer.summary].compactMap { $0 } +
            [offer.category].compactMap { $0 } +
            offer.tags +
            offer.semantic.domains +
            offer.semantic.serviceKinds
        )

        let capabilityTerms = normalizedTerms(
            offer.semantic.serviceKinds +
            offer.semantic.audienceKinds.map(\.rawValue) +
            offer.semantic.fulfillmentModes.map(\.rawValue)
        )

        let filterTokens = normalizedTerms(
            tags +
            providerTerms +
            capabilityTerms +
            offer.regionTags
        )
        let regionEvidence = mergedRegionEvidence(
            serverCanonicalIDs: offer.canonicalRegionIDs,
            serverParentIDs: offer.parentRegionIDs,
            serverRegionAliases: offer.regionAliases,
            tagRegionTags: offer.regionTags
        )

        let serviceAreas = offer.effectiveServiceAreas
        let document = ExchangeRetrievalDocument(
            id: "offer::\(offer.id)",
            counterpartyID: counterparty.id,
            nodeID: offer.nodeID,
            publicProfileID: offer.publicProfileID ?? profile?.id,
            offerID: offer.id,
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: sourceKind,
            docKind: .offerDetail,
            sourceField: "offer_detail",
            visibility: offer.visibility.rawValue,
            availability: profile?.availability.rawValue,
            accessMode: profile?.reachability.accessMode.rawValue,
            acceptingInbound: profile?.reachability.acceptingInbound,
            routeableOnly: profile?.reachability.routeableOnly,
            title: title,
            summary: summary,
            category: offer.category,
            tags: tags,
            regionTags: normalizedTerms(offer.regionTags),
            canonicalRegionIDs: regionEvidence.canonicalIDs,
            regionAliases: regionEvidence.aliases,
            parentRegionIDs: regionEvidence.parentIDs,
            serviceAreas: serviceAreas,
            primaryText: primaryText,
            secondaryText: secondaryText,
            lexicalText: lexicalText,
            semanticText: semanticText,
            providerTerms: providerTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: [],
            filterTokens: filterTokens,
            embedding: nil,
            updatedAt: offer.updatedAt
        )
        Self.logDocumentCoverage(document)
        return document
    }

    func buildOfferPackageDocuments(
        counterparty: ExchangeCounterparty,
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> [ExchangeRetrievalDocument] {
        offer.commercialFacts.packages.enumerated().compactMap { index, pkg in
            let descriptiveParts = publishSafeCompactNonBlank([Optional(pkg.title), pkg.summary])
            guard !descriptiveParts.isEmpty else { return nil }
            let stableKey = pkg.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "idx:\(index)"
                : pkg.id
            let primaryText = descriptiveParts.joined(separator: ". ")
            let tags = normalizedTerms(descriptiveParts)
            let regionEvidence = mergedRegionEvidence(
                serverCanonicalIDs: offer.canonicalRegionIDs,
                serverParentIDs: offer.parentRegionIDs,
                serverRegionAliases: offer.regionAliases,
                tagRegionTags: offer.regionTags
            )

            return ExchangeRetrievalDocument(
                id: "offer-package::\(offer.id)::\(stableKey)",
                counterpartyID: counterparty.id,
                nodeID: offer.nodeID,
                publicProfileID: offer.publicProfileID ?? profile?.id,
                offerID: offer.id,
                entityType: .offer,
                surfaceType: .offer,
                sourceKind: sourceKind,
                docKind: .offerPackage,
                sourceField: "offer_package",
                visibility: offer.visibility.rawValue,
                availability: profile?.availability.rawValue,
                accessMode: profile?.reachability.accessMode.rawValue,
                acceptingInbound: profile?.reachability.acceptingInbound,
                routeableOnly: profile?.reachability.routeableOnly,
                title: pkg.title,
                summary: pkg.summary,
                category: offer.category,
                tags: tags,
                regionTags: normalizedTerms(offer.regionTags),
                canonicalRegionIDs: regionEvidence.canonicalIDs,
                regionAliases: regionEvidence.aliases,
                parentRegionIDs: regionEvidence.parentIDs,
                primaryText: primaryText,
                secondaryText: "",
                lexicalText: primaryText,
                semanticText: primaryText,
                providerTerms: normalizedTerms([pkg.title]),
                capabilityTerms: [],
                affinityTerms: [],
                filterTokens: normalizedTerms(tags + [offer.title]),
                embedding: nil,
                updatedAt: offer.updatedAt
            )
        }
    }

    func buildOfferFAQDocuments(
        counterparty: ExchangeCounterparty,
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> [ExchangeRetrievalDocument] {
        offer.commercialFacts.faqs.enumerated().compactMap { index, faq in
            let question = faq.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = faq.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty || !answer.isEmpty else { return nil }
            let stableKey = "idx:\(index)"
            let primaryText = compactNonBlank([question, answer]).joined(separator: ". ")
            let tags = normalizedTerms([question, answer])
            let regionEvidence = mergedRegionEvidence(
                serverCanonicalIDs: offer.canonicalRegionIDs,
                serverParentIDs: offer.parentRegionIDs,
                serverRegionAliases: offer.regionAliases,
                tagRegionTags: offer.regionTags
            )

            return ExchangeRetrievalDocument(
                id: "offer-faq::\(offer.id)::\(stableKey)",
                counterpartyID: counterparty.id,
                nodeID: offer.nodeID,
                publicProfileID: offer.publicProfileID ?? profile?.id,
                offerID: offer.id,
                entityType: .offer,
                surfaceType: .offer,
                sourceKind: sourceKind,
                docKind: .offerFAQ,
                sourceField: "offer_faq",
                visibility: offer.visibility.rawValue,
                availability: profile?.availability.rawValue,
                accessMode: profile?.reachability.accessMode.rawValue,
                acceptingInbound: profile?.reachability.acceptingInbound,
                routeableOnly: profile?.reachability.routeableOnly,
                title: question.isEmpty ? "FAQ" : question,
                summary: answer.isEmpty ? nil : answer,
                category: offer.category,
                tags: tags,
                regionTags: normalizedTerms(offer.regionTags),
                canonicalRegionIDs: regionEvidence.canonicalIDs,
                regionAliases: regionEvidence.aliases,
                parentRegionIDs: regionEvidence.parentIDs,
                primaryText: primaryText,
                secondaryText: "",
                lexicalText: primaryText,
                semanticText: primaryText,
                providerTerms: [],
                capabilityTerms: [],
                affinityTerms: [],
                filterTokens: normalizedTerms(tags + [offer.title]),
                embedding: nil,
                updatedAt: offer.updatedAt
            )
        }
    }

    func buildIndexedOfferPackageDocuments(
        indexedOffer: ExchangeIndexedOfferSurface,
        parentSurface: ExchangeIndexedProviderSurface?,
        counterpartyID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> [ExchangeRetrievalDocument] {
        guard shouldIndexIndexedOffer(indexedOffer) else { return [] }
        return indexedOffer.packageSlices.compactMap { slice in
            guard !slice.descriptiveText.isEmpty else { return nil }
            let tags = normalizeIndexedTerms([slice.title, slice.summary].compactMap { $0 })
            let displayPrimary = slice.descriptiveText
            let projection = indexedEnglishRetrievalProjection(
                canonicalEnglish: indexedOffer.canonicalEnglishRetrievalText,
                displayPrimary: displayPrimary,
                displaySecondary: "",
                lexicalFallback: displayPrimary,
                semanticFallback: displayPrimary
            )

            return ExchangeRetrievalDocument(
                id: "offer-package::\(indexedOffer.offerID)::\(slice.stableKey)",
                counterpartyID: counterpartyID,
                nodeID: parentSurface?.nodeID,
                publicProfileID: parentSurface?.publicProfileID,
                offerID: indexedOffer.offerID,
                entityType: .offer,
                surfaceType: .offer,
                sourceKind: sourceKind,
                docKind: .offerPackage,
                sourceField: "offer_package",
                visibility: indexedOffer.visibility,
                availability: parentSurface?.availability,
                accessMode: parentSurface?.reachability.accessMode,
                acceptingInbound: parentSurface?.reachability.acceptingInbound,
                routeableOnly: parentSurface?.reachability.routeableOnly,
                title: slice.title,
                summary: slice.summary,
                category: indexedOffer.category,
                tags: tags,
                regionTags: normalizeIndexedTerms(parentSurface?.regions.regionTags ?? []),
                canonicalRegionIDs: normalizeIndexedTerms(parentSurface?.regions.canonicalRegionIDs ?? []),
                regionAliases: normalizeIndexedTerms(parentSurface?.regions.regionAliases ?? []),
                parentRegionIDs: normalizeIndexedTerms(parentSurface?.regions.parentRegionIDs ?? []),
                serviceAreas: indexedOffer.serviceAreas,
                primaryText: projection.primaryText,
                secondaryText: projection.secondaryText,
                lexicalText: projection.lexicalText,
                semanticText: projection.semanticText,
                canonicalEnglishRetrievalText: projection.canonicalEnglishRetrievalText,
                providerTerms: sanitizeAtomicIndexedTerms([slice.title]),
                capabilityTerms: [],
                affinityTerms: [],
                filterTokens: normalizeIndexedTerms(tags + [indexedOffer.title]),
                embedding: nil,
                updatedAt: indexedOffer.updatedAt
            )
        }
    }

    func buildIndexedOfferFAQDocuments(
        indexedOffer: ExchangeIndexedOfferSurface,
        parentSurface: ExchangeIndexedProviderSurface?,
        counterpartyID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> [ExchangeRetrievalDocument] {
        guard shouldIndexIndexedOffer(indexedOffer) else { return [] }
        return indexedOffer.faqSlices.compactMap { slice in
            let primaryText = compactNonBlank([slice.question, slice.answer]).joined(separator: ". ")
            guard !primaryText.isEmpty else { return nil }
            let tags = normalizeIndexedTerms([slice.question, slice.answer])
            let projection = indexedEnglishRetrievalProjection(
                canonicalEnglish: indexedOffer.canonicalEnglishRetrievalText,
                displayPrimary: primaryText,
                displaySecondary: "",
                lexicalFallback: primaryText,
                semanticFallback: primaryText
            )

            return ExchangeRetrievalDocument(
                id: "offer-faq::\(indexedOffer.offerID)::\(slice.stableKey)",
                counterpartyID: counterpartyID,
                nodeID: parentSurface?.nodeID,
                publicProfileID: parentSurface?.publicProfileID,
                offerID: indexedOffer.offerID,
                entityType: .offer,
                surfaceType: .offer,
                sourceKind: sourceKind,
                docKind: .offerFAQ,
                sourceField: "offer_faq",
                visibility: indexedOffer.visibility,
                availability: parentSurface?.availability,
                accessMode: parentSurface?.reachability.accessMode,
                acceptingInbound: parentSurface?.reachability.acceptingInbound,
                routeableOnly: parentSurface?.reachability.routeableOnly,
                title: slice.question.isEmpty ? "FAQ" : slice.question,
                summary: slice.answer.isEmpty ? nil : slice.answer,
                category: indexedOffer.category,
                tags: tags,
                regionTags: normalizeIndexedTerms(parentSurface?.regions.regionTags ?? []),
                canonicalRegionIDs: normalizeIndexedTerms(parentSurface?.regions.canonicalRegionIDs ?? []),
                regionAliases: normalizeIndexedTerms(parentSurface?.regions.regionAliases ?? []),
                parentRegionIDs: normalizeIndexedTerms(parentSurface?.regions.parentRegionIDs ?? []),
                serviceAreas: indexedOffer.serviceAreas,
                primaryText: projection.primaryText,
                secondaryText: projection.secondaryText,
                lexicalText: projection.lexicalText,
                semanticText: projection.semanticText,
                canonicalEnglishRetrievalText: projection.canonicalEnglishRetrievalText,
                providerTerms: [],
                capabilityTerms: [],
                affinityTerms: [],
                filterTokens: normalizeIndexedTerms(tags + [indexedOffer.title]),
                embedding: nil,
                updatedAt: indexedOffer.updatedAt
            )
        }
    }

    func buildOfferObjectDocument(
        counterparty: ExchangeCounterparty,
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument {
        let identityText = offerObjectIdentityText(from: offer)
        let tags = normalizedTerms(
            offer.tags +
            [offer.category].compactMap { $0 }
        )
        let serviceKinds = normalizedTerms(offer.semantic.serviceKinds)

        let document = ExchangeRetrievalDocument(
            id: "offer-object::\(offer.id)",
            counterpartyID: counterparty.id,
            nodeID: offer.nodeID,
            publicProfileID: offer.publicProfileID ?? profile?.id,
            offerID: offer.id,
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: sourceKind,
            docKind: .offerObject,
            sourceField: "offer_object",
            visibility: offer.visibility.rawValue,
            availability: profile?.availability.rawValue,
            accessMode: profile?.reachability.accessMode.rawValue,
            acceptingInbound: profile?.reachability.acceptingInbound,
            routeableOnly: profile?.reachability.routeableOnly,
            title: offer.title,
            summary: nil,
            category: offer.category,
            tags: tags,
            regionTags: [],
            canonicalRegionIDs: [],
            regionAliases: [],
            parentRegionIDs: [],
            serviceAreas: [],
            primaryText: identityText,
            secondaryText: "",
            lexicalText: identityText,
            semanticText: serviceKinds.joined(separator: " "),
            providerTerms: normalizedTerms(
                [offer.title, offer.category].compactMap { $0 } + offer.tags
            ),
            capabilityTerms: serviceKinds,
            affinityTerms: [],
            filterTokens: tags,
            embedding: nil,
            updatedAt: offer.updatedAt
        )
        Self.logDocumentCoverage(document)
        return document
    }

    func buildOfferObjectDocument(
        from indexedOffer: ExchangeIndexedOfferSurface,
        parentSurface: ExchangeIndexedProviderSurface?,
        counterpartyID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) -> ExchangeRetrievalDocument? {
        guard shouldIndexIndexedOffer(indexedOffer) else { return nil }

        let objectProjection = indexedOfferObjectRetrievalProjection(
            indexedOffer: indexedOffer,
            parentSurface: parentSurface
        )
        guard !objectProjection.identityText.isEmpty else { return nil }

        let tags = normalizeIndexedTerms(
            objectProjection.objectTerms.filter { term in
                term != indexedOffer.title &&
                term != indexedOffer.category
            }
        )
        let serviceKinds = normalizeIndexedTerms(
            objectProjection.objectTerms.filter { term in
                term != indexedOffer.title &&
                term != indexedOffer.category &&
                !tags.contains(term)
            }
        )
        let providerTerms = normalizeIndexedTerms(
            [indexedOffer.title, indexedOffer.category].compactMap { $0 } + tags
        )
        let filteredProviderTerms = englishFilteredIndexedTerms(
            providerTerms,
            usesEnglishOnlyProjection: objectProjection.usesEnglishOnlyProjection
        )
        let filteredCapabilityTerms = englishFilteredIndexedTerms(
            serviceKinds,
            usesEnglishOnlyProjection: objectProjection.usesEnglishOnlyProjection
        )

        return ExchangeRetrievalDocument(
            id: "offer-object::\(indexedOffer.offerID)",
            counterpartyID: counterpartyID,
            nodeID: parentSurface?.nodeID,
            publicProfileID: parentSurface?.publicProfileID,
            offerID: indexedOffer.offerID,
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: sourceKind,
            docKind: .offerObject,
            sourceField: "offer_object",
            visibility: indexedOffer.visibility,
            availability: parentSurface?.availability,
            accessMode: parentSurface?.reachability.accessMode,
            acceptingInbound: parentSurface?.reachability.acceptingInbound,
            routeableOnly: parentSurface?.reachability.routeableOnly,
            title: indexedOffer.title,
            summary: nil,
            category: indexedOffer.category,
            tags: tags,
            regionTags: normalizeIndexedTerms(parentSurface?.regions.regionTags ?? []),
            canonicalRegionIDs: normalizeIndexedTerms(parentSurface?.regions.canonicalRegionIDs ?? []),
            regionAliases: normalizeIndexedTerms(parentSurface?.regions.regionAliases ?? []),
            parentRegionIDs: normalizeIndexedTerms(parentSurface?.regions.parentRegionIDs ?? []),
            serviceAreas: indexedOffer.serviceAreas,
            primaryText: objectProjection.primaryText,
            secondaryText: objectProjection.secondaryText,
            lexicalText: objectProjection.lexicalText,
            semanticText: objectProjection.semanticText,
            canonicalEnglishRetrievalText: objectProjection.canonicalEnglishRetrievalText,
            providerTerms: filteredProviderTerms,
            capabilityTerms: filteredCapabilityTerms,
            affinityTerms: [],
            filterTokens: tags,
            embedding: nil,
            updatedAt: indexedOffer.updatedAt
        )
    }

    func offerObjectIdentityText(from offer: ExchangeOffer) -> String {
        compactNonBlank([
            offer.title,
            offer.category,
            offer.tags.joined(separator: " "),
            offer.semantic.serviceKinds.joined(separator: " ")
        ]).joined(separator: ". ")
    }

    static func logDocumentCoverage(_ document: ExchangeRetrievalDocument) {
        guard document.surfaceType == .offer else { return }
        let resolved = document.serviceAreas.compactMap(\.spatial).filter(\.hasResolvedCells)
        let hasCoverage = !resolved.isEmpty
        let cellCount = resolved.reduce(0) { $0 + $1.h3Cells.count }
        let resolution = resolved.first?.h3Resolution.map(String.init) ?? "nil"
        print(
            "[RetrievalH3] documentCoverage docID=\(document.id) surface=offer hasCoverage=\(hasCoverage) resolution=\(resolution) cellCount=\(cellCount)"
        )
    }

    func shouldEmitSeekingDocument(
        profile: ExchangePublicNodeProfile
    ) -> Bool {
        !normalizedTerms(
            profile.openTo.filter { !ExchangePublicProfileScaffoldText.isGenerated($0) }
        ).isEmpty
    }

    func shouldEmitAffinityDocument(
        profile: ExchangePublicNodeProfile
    ) -> Bool {
        !normalizedTerms(profile.interests).isEmpty
    }

    func shouldIndex(offer: ExchangeOffer) -> Bool {
        offer.status == .active &&
        (offer.visibility == .publicDiscoverable || offer.visibility == .limitedSurface)
    }

    /// Descriptive offer detail for embedding (FAQ, package titles/summaries). Excludes price and logistics.
    func offerDetailDescriptiveSemanticText(from offer: ExchangeOffer) -> String? {
        let faqText = offer.commercialFacts.faqs.flatMap { [$0.question, $0.answer] }.compactMap { $0 }
        let packageText = offer.commercialFacts.packages.flatMap { [$0.title, $0.summary] }.compactMap { $0 }
        let joined = compactNonBlank([
            offer.summary,
            offer.semantic.notes,
            faqText.joined(separator: ". "),
            packageText.joined(separator: ". ")
        ]).joined(separator: ". ")
        return joined.isEmpty ? nil : joined
    }

    /// Canonical, searchable sentences for v1.5 commercial surface (public only).
    func canonicalCommercialRetrievalFingerprint(_ offer: ExchangeOffer) -> String? {
        let cf = offer.commercialFacts
        guard cf.hasPublishedCommercialSurface else {
            return nil
        }

        var rows: [String] = []

        if let pd = cf.priceDisplay { rows.append("Price: \(pd)") }

        var rangeParts: [String] = []
        if let a = cf.priceMin {
            rangeParts.append("min \(RetrievalOfferDecimalFormatting.string(for: a))")
        }
        if let b = cf.priceMax {
            rangeParts.append("max \(RetrievalOfferDecimalFormatting.string(for: b))")
        }
        if !rangeParts.isEmpty {
            rows.append("Price range: \(rangeParts.joined(separator: " · "))")
        }

        for pkg in cf.packages {
            var s = "Package: \(pkg.title)"
            if let u = pkg.summary {
                s += " — \(u)"
            }
            if let p = pkg.priceDisplay {
                s += " (\(p))"
            }
            rows.append(s)
        }

        if let san = cf.serviceAreaNote {
            rows.append("Service area: \(san)")
        }
        if let an = cf.availabilityNote {
            rows.append("Availability: \(an)")
        }
        if let me = cf.minimumEngagement {
            rows.append("Minimum engagement: \(me)")
        }
        if let c = cf.cancellationPolicy {
            rows.append("Cancellation policy: \(c)")
        }
        if let r = cf.refundPolicy {
            rows.append("Refund policy: \(r)")
        }
        if let w = cf.warrantyPolicy {
            rows.append("Warranty policy: \(w)")
        }
        for input in cf.requiredBuyerInputs {
            rows.append("Required buyer input: \(input)")
        }
        for f in cf.faqs {
            rows.append("FAQ: \(f.question) / \(f.answer)")
        }

        guard !rows.isEmpty else {
            return nil
        }

        return rows.joined(separator: ". ")
    }

    func compactNonBlank(_ values: [String?]) -> [String] {
        values.compactMap {
            let trimmed = $0?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    func dedupe(_ documents: [ExchangeRetrievalDocument]) -> [ExchangeRetrievalDocument] {
        var byID: [String: ExchangeRetrievalDocument] = [:]
        for document in documents {
            byID[document.id] = document
        }

        return byID.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    func normalizedTerms(_ values: [String]) -> [String] {
        Array(
            Set(
                values.compactMap {
                    let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return trimmed.isEmpty ? nil : trimmed
                }
            )
        )
        .sorted()
    }

    /// When the server sends canonical region IDs, those win for hard gating; tag-based resolver
    /// still augments parents and aliases. If the server sends none, behavior matches legacy
    /// tag-only resolution.
    func mergedRegionEvidence(
        serverCanonicalIDs: [String],
        serverParentIDs: [String],
        serverRegionAliases: [String],
        tagRegionTags: [String]
    ) -> (canonicalIDs: [String], aliases: [String], parentIDs: [String]) {
        let tagDerived = resolveRegionEvidence(tags: tagRegionTags)
        let serverCanon = normalizedTerms(serverCanonicalIDs)
        if !serverCanon.isEmpty {
            return (
                canonicalIDs: serverCanon,
                aliases: normalizedTerms(serverRegionAliases + tagDerived.aliases),
                parentIDs: normalizedTerms(serverParentIDs + tagDerived.parentIDs)
            )
        }
        return tagDerived
    }

    func resolveRegionEvidence(tags: [String]) -> (canonicalIDs: [String], aliases: [String], parentIDs: [String]) {
        let aliases = normalizedTerms(tags)
        var canonicalIDs = Set<String>()
        var parentIDs = Set<String>()
        var aliasSet = Set(aliases)

        for alias in aliases {
            let entity = ExchangeQueryEntity(
                kind: .place,
                rawText: alias,
                confidence: 0.85,
                provenance: .deterministicExtractor,
                hardConstraintEligible: true
            )
            guard let resolved = placeResolver.resolvePlaceSync(entity) else { continue }
            canonicalIDs.insert(resolved.canonicalID.lowercased())
            for parent in resolved.parentRegionIDs {
                parentIDs.insert(parent.lowercased())
            }
            for resolvedAlias in resolved.aliases {
                let cleaned = resolvedAlias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !cleaned.isEmpty {
                    aliasSet.insert(cleaned)
                }
            }
        }

        return (
            canonicalIDs: Array(canonicalIDs).sorted(),
            aliases: Array(aliasSet).sorted(),
            parentIDs: Array(parentIDs).sorted()
        )
    }

    func mapCounterpartyStatus(
        _ availability: ExchangePublicNodeProfile.Availability
    ) -> ExchangeCounterparty.Status {
        switch availability {
        case .open:
            return .active
        case .limited:
            return .paused
        case .paused, .unavailable:
            return .unavailable
        }
    }

    func indexedEnglishRetrievalProjection(
        canonicalEnglish: String?,
        displayPrimary: String,
        displaySecondary: String,
        lexicalFallback: String,
        semanticFallback: String
    ) -> (
        primaryText: String,
        secondaryText: String,
        lexicalText: String,
        semanticText: String,
        canonicalEnglishRetrievalText: String?
    ) {
        guard let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(canonicalEnglish) else {
            return (
                primaryText: displayPrimary,
                secondaryText: displaySecondary,
                lexicalText: lexicalFallback,
                semanticText: semanticFallback,
                canonicalEnglishRetrievalText: nil
            )
        }
        let semanticTrimmed = semanticFallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let semantic = semanticTrimmed.isEmpty ? english : semanticTrimmed
        return (
            primaryText: "",
            secondaryText: "",
            lexicalText: "",
            semanticText: semantic,
            canonicalEnglishRetrievalText: english
        )
    }

    func englishFilteredIndexedTerms(
        _ terms: [String],
        usesEnglishOnlyProjection: Bool
    ) -> [String] {
        guard usesEnglishOnlyProjection else { return terms }
        return ExchangeRetrievalEnglishProjection.englishOnlyTokens(from: terms)
    }

    func indexedOfferObjectRetrievalProjection(
        indexedOffer: ExchangeIndexedOfferSurface,
        parentSurface: ExchangeIndexedProviderSurface?
    ) -> (
        identityText: String,
        objectTerms: [String],
        primaryText: String,
        secondaryText: String,
        lexicalText: String,
        semanticText: String,
        canonicalEnglishRetrievalText: String?,
        usesEnglishOnlyProjection: Bool
    ) {
        let rawObjectTerms = sanitizeAtomicIndexedTerms(
            (indexedOffer.objectIdentityTerms ?? []) +
            indexedOffer.semanticConcepts +
            indexedOffer.capabilityTerms +
            indexedOffer.broadRecallTokens
        )
        let englishCarrier = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            indexedOffer.canonicalEnglishRetrievalText
        ) ?? ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            parentSurface?.canonicalEnglishRetrievalText
        )
        let usesEnglish = englishCarrier != nil
        let englishObjectTerms = usesEnglish
            ? englishFilteredIndexedTerms(rawObjectTerms, usesEnglishOnlyProjection: true)
            : rawObjectTerms
        let objectTerms = dedupeIndexedTermsPreservingOrder(englishObjectTerms + (englishCarrier.map { [$0] } ?? []))
        let identityFallback = compactNonBlank([
            rawObjectTerms.isEmpty ? nil : rawObjectTerms.joined(separator: " ")
        ]).joined(separator: ". ")
        let englishObjectPhrase = compactNonBlank([
            englishObjectTerms.isEmpty ? nil : englishObjectTerms.joined(separator: " ")
        ]).joined(separator: ". ")
        let displayPrimary = englishObjectPhrase.isEmpty ? identityFallback : englishObjectPhrase
        let semanticFallback = compactNonBlank(
            usesEnglish
                ? [englishCarrier, englishObjectPhrase]
                : [englishCarrier, englishObjectPhrase, identityFallback]
        ).joined(separator: ". ")
        let projection = indexedEnglishRetrievalProjection(
            canonicalEnglish: englishCarrier,
            displayPrimary: displayPrimary,
            displaySecondary: "",
            lexicalFallback: displayPrimary.isEmpty ? identityFallback : displayPrimary,
            semanticFallback: semanticFallback
        )
        let identityText = compactNonBlank([
            projection.canonicalEnglishRetrievalText,
            projection.semanticText,
            projection.lexicalText,
            displayPrimary
        ]).joined(separator: ". ")
        return (
            identityText: identityText,
            objectTerms: objectTerms,
            primaryText: projection.primaryText,
            secondaryText: projection.secondaryText,
            lexicalText: projection.lexicalText,
            semanticText: projection.semanticText,
            canonicalEnglishRetrievalText: projection.canonicalEnglishRetrievalText,
            usesEnglishOnlyProjection: usesEnglish
        )
    }

    func dedupeIndexedTermsPreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            out.append(normalized)
        }
        return out
    }
}

private enum RetrievalOfferDecimalFormatting {
    static func string(for d: Decimal) -> String {
        (d as NSDecimalNumber).stringValue
    }
}
