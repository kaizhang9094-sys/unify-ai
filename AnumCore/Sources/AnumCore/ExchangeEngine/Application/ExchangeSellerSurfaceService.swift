import Foundation

/// Built seller-facing local surface for app/UI use.
///
/// This is a local projection of:
/// - owner display name
/// - public profile
/// - publication state
/// - all offers
/// - currently publishable offers
public struct ExchangeSellerSurface: Sendable, Hashable {
    public var ownerDisplayName: String?
    public var publicProfile: ExchangePublicNodeProfile?
    public var publicationState: ExchangePublicationState?
    public var offers: [ExchangeOffer]
    public var publishedOffers: [ExchangeOffer]

    public init(
        ownerDisplayName: String?,
        publicProfile: ExchangePublicNodeProfile?,
        publicationState: ExchangePublicationState?,
        offers: [ExchangeOffer],
        publishedOffers: [ExchangeOffer]
    ) {
        self.ownerDisplayName = ownerDisplayName?.nilIfBlank
        self.publicProfile = publicProfile
        self.publicationState = publicationState
        self.offers = offers
        self.publishedOffers = publishedOffers
    }
}

public struct ExchangeSellerValidationIssue: Sendable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Hashable {
        case warning
        case error
    }

    public var id: UUID
    public var offerID: ExchangeOffer.ID?
    public var severity: Severity
    public var summary: String

    public init(
        id: UUID = UUID(),
        offerID: ExchangeOffer.ID? = nil,
        severity: Severity,
        summary: String
    ) {
        self.id = id
        self.offerID = offerID
        self.severity = severity
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Node-owned seller operating layer.
///
/// Responsibility:
/// - own the user's public selling surface locally
/// - assemble local public profile + local offers into a publishable seller surface
/// - assemble local public profile + local offers into retrieval documents
/// - keep seller state separate from request-side thread interpretation
///
/// It should not:
/// - rank discovery candidates
/// - execute federation delivery
/// - mutate thread transport state
/// - own publication transport policy
public protocol ExchangeSellerSurfaceService: Sendable {
    func buildLocalSellerSurface(
        ownerDisplayName: String?,
        publicProfile: ExchangePublicNodeProfile?,
        offers: [ExchangeOffer],
        publicationState: ExchangePublicationState?
    ) async throws -> ExchangeSellerSurface

    func validateSurface(
        publicProfile: ExchangePublicNodeProfile?,
        offers: [ExchangeOffer]
    ) -> [ExchangeSellerValidationIssue]

    func buildPublishedPayload(
        ownerNodeID: String,
        ownerDisplayName: String?,
        publicProfile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer],
        publicationState: ExchangePublicationState?,
        now: Date
    ) -> ExchangePublishedSellerSurfacePayload

    func buildRetrievalDocuments(
        ownerNodeID: String,
        publicProfile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer]
    ) -> [ExchangeRetrievalDocument]
}

public struct ExchangeDefaultSellerSurfaceService: ExchangeSellerSurfaceService, Sendable {
    private let retrievalDocumentBuilder: ExchangeRetrievalDocumentBuilder
    private let indexedSurfaceBuilder: ExchangeIndexedProviderSurfaceBuilder

    public init(
        retrievalDocumentBuilder: ExchangeRetrievalDocumentBuilder = .init(),
        indexedSurfaceBuilder: ExchangeIndexedProviderSurfaceBuilder = .init()
    ) {
        self.retrievalDocumentBuilder = retrievalDocumentBuilder
        self.indexedSurfaceBuilder = indexedSurfaceBuilder
    }

    public func buildLocalSellerSurface(
        ownerDisplayName: String?,
        publicProfile: ExchangePublicNodeProfile?,
        offers: [ExchangeOffer],
        publicationState: ExchangePublicationState?
    ) async throws -> ExchangeSellerSurface {
        let sortedOffers = offers.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.title < rhs.title
        }

        let publishedOffers = sortedOffers.filter {
            $0.status == .active && $0.visibility != .hidden
        }

        return ExchangeSellerSurface(
            ownerDisplayName: ownerDisplayName?.nilIfBlank,
            publicProfile: publicProfile,
            publicationState: publicationState,
            offers: sortedOffers,
            publishedOffers: publishedOffers
        )
    }

    public func validateSurface(
        publicProfile: ExchangePublicNodeProfile?,
        offers: [ExchangeOffer]
    ) -> [ExchangeSellerValidationIssue] {
        var issues: [ExchangeSellerValidationIssue] = []

        if publicProfile == nil {
            issues.append(
                ExchangeSellerValidationIssue(
                    severity: .warning,
                    summary: "No public profile exists yet for this seller surface."
                )
            )
        }

        for offer in offers {
            if offer.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(
                    ExchangeSellerValidationIssue(
                        offerID: offer.id,
                        severity: .error,
                        summary: "Offer title is missing."
                    )
                )
            }

            if offer.status == .active,
               offer.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank == nil {
                issues.append(
                    ExchangeSellerValidationIssue(
                        offerID: offer.id,
                        severity: .warning,
                        summary: "Active offer should have a short summary."
                    )
                )
            }

            if offer.status == .active,
               offer.visibility == .hidden {
                issues.append(
                    ExchangeSellerValidationIssue(
                        offerID: offer.id,
                        severity: .warning,
                        summary: "Active offer is hidden and will not surface publicly."
                    )
                )
            }

            if let publicProfile,
               let offerProfileID = offer.publicProfileID,
               offerProfileID != publicProfile.id {
                issues.append(
                    ExchangeSellerValidationIssue(
                        offerID: offer.id,
                        severity: .warning,
                        summary: "Offer is linked to a different public profile than the current seller surface."
                    )
                )
            }
        }

        return issues
    }

    public func buildPublishedPayload(
        ownerNodeID: String,
        ownerDisplayName: String?,
        publicProfile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer],
        publicationState: ExchangePublicationState?,
        now: Date
    ) -> ExchangePublishedSellerSurfacePayload {
        let outwardOffers = outwardFacingOffers(from: offers)

        let projectedProfile = ExchangePublishedSellerSurfacePayload.PublicProfileProjection(
            id: publicProfile.id,
            displayName: publicProfile.displayName ?? ownerDisplayName?.nilIfBlank,
            headline: ExchangePublicProfileScaffoldText.filteredOptional(publicProfile.headline),
            summary: ExchangePublicProfileScaffoldText.filteredOptional(publicProfile.summary),
            visibility: publicProfile.visibility.rawValue,
            availability: publicProfile.availability.rawValue,
            interests: publicProfile.interests,
            offers: publicProfile.offers.filter { !ExchangePublicProfileScaffoldText.isGenerated($0) },
            openTo: publicProfile.openTo.filter { !ExchangePublicProfileScaffoldText.isGenerated($0) },
            excludedTopics: publicProfile.excludedTopics,
            activityTags: publicProfile.activityTags,
            regionTags: publicProfile.regionTags,
            semantic: semanticProjection(from: publicProfile.semantic),
            reachability: .init(
                acceptingInbound: publicProfile.reachability.acceptingInbound,
                accessMode: publicProfile.reachability.accessMode.rawValue,
                disclosureCeiling: publicProfile.reachability.disclosureCeiling.rawValue,
                routeableOnly: publicProfile.reachability.routeableOnly
            ),
            primaryImageURL: publicProfile.visibility == .hidden ? nil : publicProfile.primaryImageURL,
            publicSupporterPresentation: publicProfile.publicSupporterPresentation
        )

        #if DEBUG
        GuardianCrownDebugLog.log(
            "PublishBuild",
            "nodeID=\(ownerNodeID) profileID=\(publicProfile.id) " +
            "presentation=\(GuardianCrownDebugLog.presentationLabel(projectedProfile.publicSupporterPresentation)) " +
            "included=\(projectedProfile.publicSupporterPresentation != nil)"
        )
        #endif

        let projectedOffers = outwardOffers.map { offer in
            let serviceAreas = offer.effectiveServiceAreas
            let published = ExchangePublishedSellerSurfacePayload.PublishedOffer(
                id: offer.id,
                title: offer.title,
                summary: offer.summary,
                category: offer.category,
                tags: offer.tags,
                regionTags: offer.regionTags,
                visibility: offer.visibility.rawValue,
                semantic: semanticProjection(from: offer.semantic),
                fulfillment: fulfillmentProjection(from: offer.fulfillment),
                primaryImageURL: offer.primaryImageURL,
                galleryImageURLs: offer.galleryImageURLs,
                commercialFacts: ExchangeDefaultSellerSurfaceService.publishableCommercialFacts(for: offer),
                contactInfo: ExchangeDefaultSellerSurfaceService.publishableOfferContactInfo(for: offer),
                serviceAreas: serviceAreas
            )
            Self.logPublicationCoverage(offerID: offer.id, serviceAreas: serviceAreas)
            return published
        }

        let fingerprint = makeFingerprint(
            nodeID: ownerNodeID,
            profile: projectedProfile,
            offers: projectedOffers
        )

        return ExchangePublishedSellerSurfacePayload(
            nodeID: ownerNodeID,
            displayName: ownerDisplayName?.nilIfBlank ?? publicProfile.displayName,
            publicProfile: projectedProfile,
            offers: projectedOffers,
            publishedAt: now,
            fingerprint: publicationState?.lastPublishedFingerprint == fingerprint
                ? publicationState?.lastPublishedFingerprint
                : fingerprint
        )
    }

    public func buildRetrievalDocuments(
        ownerNodeID: String,
        publicProfile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer]
    ) -> [ExchangeRetrievalDocument] {
        buildRetrievalDocumentsFromIndexedSurface(
            ownerNodeID: ownerNodeID,
            publicProfile: publicProfile,
            offers: offers
        )
    }

    func buildRetrievalDocumentsFromIndexedSurface(
        ownerNodeID: String,
        publicProfile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer]
    ) -> [ExchangeRetrievalDocument] {
        let outwardOffers = outwardFacingOffers(from: offers)
        let indexedSurface = indexedSurfaceBuilder.build(
            profile: publicProfile,
            offers: outwardOffers
        )
        return retrievalDocumentBuilder.build(
            from: indexedSurface,
            counterpartyID: ownerNodeID,
            sourceKind: .local
        )
    }

    func buildRetrievalDocumentsLegacyDirect(
        ownerNodeID: String,
        publicProfile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer]
    ) -> [ExchangeRetrievalDocument] {
        let outwardOffers = outwardFacingOffers(from: offers)
        return retrievalDocumentBuilder.buildDocuments(
            profile: publicProfile,
            offers: outwardOffers,
            counterpartyID: ownerNodeID,
            sourceKind: .local
        )
    }
}

private extension ExchangeDefaultSellerSurfaceService {
    func outwardFacingOffers(
        from offers: [ExchangeOffer]
    ) -> [ExchangeOffer] {
        offers
            .filter { $0.status == .active && $0.visibility != .hidden }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.title < rhs.title
            }
    }
    
    func semanticProjection(
        from semantic: ExchangePublicNodeProfile.SemanticSurface
    ) -> [String: [String]] {
        [
            "domains": semantic.domains,
            "intentKinds": semantic.intentKinds,
            "audienceKinds": semantic.audienceKinds.map(\.rawValue),
            "fulfillmentModes": semantic.fulfillmentModes.map(\.rawValue)
        ]
    }
    
    func semanticProjection(
        from semantic: ExchangeOffer.SemanticSurface
    ) -> [String: [String]] {
        [
            "domains": semantic.domains,
            "serviceKinds": semantic.serviceKinds,
            "audienceKinds": semantic.audienceKinds.map(\.rawValue),
            "fulfillmentModes": semantic.fulfillmentModes.map(\.rawValue)
        ]
    }
    
    func fulfillmentProjection(
        from fulfillment: ExchangeOffer.Fulfillment
    ) -> [String: String] {
        var projection: [String: String] = [
            "pricingMode": fulfillment.pricingMode.rawValue,
            "commitmentMode": fulfillment.commitmentMode.rawValue,
            "remoteFriendly": fulfillment.remoteFriendly ? "true" : "false"
        ]
        
        if let leadTimeNote = fulfillment.leadTimeNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !leadTimeNote.isEmpty {
            projection["leadTimeNote"] = leadTimeNote
        }
        
        if let capacityNote = fulfillment.capacityNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !capacityNote.isEmpty {
            projection["capacityNote"] = capacityNote
        }
        
        return projection
    }
    
    func makeFingerprint(
        nodeID: String,
        profile: ExchangePublishedSellerSurfacePayload.PublicProfileProjection,
        offers: [ExchangePublishedSellerSurfacePayload.PublishedOffer]
    ) -> String {
        let profileSemanticFingerprint: String = {
            let sortedSemantic = profile.semantic.sorted { lhs, rhs in
                lhs.key < rhs.key
            }
            
            let entries: [String] = sortedSemantic.map { entry in
                let key = entry.key
                let values = entry.value.joined(separator: "|")
                return "\(key)=\(values)"
            }
            
            return entries.joined(separator: ";")
        }()
        
        let profileInboundFingerprint = profile.reachability.acceptingInbound
        ? "inbound:true"
        : "inbound:false"
        
        let profileRouteableFingerprint = profile.reachability.routeableOnly
        ? "routeable:true"
        : "routeable:false"
        
        var parts: [String] = [
            nodeID.lowercased(),
            profile.id.lowercased(),
            profile.displayName?.lowercased() ?? "",
            profile.headline?.lowercased() ?? "",
            profile.summary?.lowercased() ?? "",
            profile.visibility.lowercased(),
            profile.availability.lowercased(),
            profile.interests.joined(separator: "|"),
            profile.offers.joined(separator: "|"),
            profile.openTo.joined(separator: "|"),
            profile.excludedTopics.joined(separator: "|"),
            profile.activityTags.joined(separator: "|"),
            profile.regionTags.joined(separator: "|"),
            profileSemanticFingerprint,
            profile.reachability.accessMode.lowercased(),
            profile.reachability.disclosureCeiling.lowercased(),
            profileInboundFingerprint,
            profileRouteableFingerprint,
            profile.primaryImageURL ?? ""
        ]
        
        for offer in offers {
            let offerSemanticFingerprint: String = {
                let sortedSemantic = offer.semantic.sorted { lhs, rhs in
                    lhs.key < rhs.key
                }
                
                let entries: [String] = sortedSemantic.map { entry in
                    let key = entry.key
                    let values = entry.value.joined(separator: "|")
                    return "\(key)=\(values)"
                }
                
                return entries.joined(separator: ";")
            }()
            
            let offerFulfillmentFingerprint: String = {
                let sortedFulfillment = offer.fulfillment.sorted { lhs, rhs in
                    lhs.key < rhs.key
                }
                
                let entries: [String] = sortedFulfillment.map { entry in
                    let key = entry.key
                    let value = entry.value
                    return "\(key)=\(value)"
                }
                
                return entries.joined(separator: ";")
            }()
            
            let commercialFactsFingerprint: String = {
                guard let cf = offer.commercialFacts else { return "" }
                guard let data = try? JSONEncoder().encode(cf),
                      let s = String(data: data, encoding: .utf8) else {
                    return ""
                }
                return s
            }()
            let contactInfoFingerprint: String = {
                guard let ci = offer.contactInfo else { return "" }
                guard let data = try? JSONEncoder().encode(ci),
                      let s = String(data: data, encoding: .utf8) else {
                    return ""
                }
                return s
            }()

            let serviceAreasFingerprint: String = {
                guard !offer.serviceAreas.isEmpty else { return "" }
                guard let data = try? JSONEncoder().encode(offer.serviceAreas),
                      let encoded = String(data: data, encoding: .utf8) else {
                    return ""
                }
                return encoded
            }()

            let offerFingerprintParts: [String] = [
                offer.id.lowercased(),
                offer.title.lowercased(),
                offer.summary?.lowercased() ?? "",
                offer.category?.lowercased() ?? "",
                offer.visibility.lowercased(),
                offer.tags.joined(separator: "|"),
                offer.regionTags.joined(separator: "|"),
                serviceAreasFingerprint,
                offerSemanticFingerprint,
                offerFulfillmentFingerprint,
                ExchangeOffer.limitedOrderedOfferImageURLs(
                    primaryImageURL: offer.primaryImageURL,
                    galleryImageURLs: offer.galleryImageURLs
                ).joined(separator: "|"),
                commercialFactsFingerprint,
                contactInfoFingerprint
            ]
            
            let offerFingerprint = offerFingerprintParts.joined(separator: "¦")
            parts.append(offerFingerprint)
        }
        
        return parts.joined(separator: "§")
    }

    static func logPublicationCoverage(offerID: String, serviceAreas: [ExchangeDeclaredServiceArea]) {
        let resolvedAreas = serviceAreas.compactMap(\.spatial).filter(\.hasResolvedCells)
        let resolvedSpatialCount = resolvedAreas.count
        let textOnlyCount = max(0, serviceAreas.count - resolvedSpatialCount)
        let hasCoverage = resolvedSpatialCount > 0
        let cellCount = resolvedAreas.reduce(0) { $0 + $1.h3Cells.count }
        let resolution = resolvedAreas.first?.h3Resolution.map(String.init) ?? "nil"
        print(
            "[SellerServiceAreaPublish] offerID=\(offerID) serviceAreaCount=\(serviceAreas.count) " +
            "resolvedSpatialCount=\(resolvedSpatialCount) textOnlyCount=\(textOnlyCount)"
        )
        print(
            "[SellerH3] publicationCoverage offerID=\(offerID) hasCoverage=\(hasCoverage) resolution=\(resolution) cellCount=\(cellCount)"
        )
    }

    static func publishableCommercialFacts(
        for offer: ExchangeOffer
    ) -> ExchangeOffer.CommercialFacts? {
        let cf = offer.commercialFacts
        guard cf.hasPublishedCommercialSurface || cf.autoAnswerPolicy != .conservativeDefaults else {
            return nil
        }
        return cf
    }

    static func publishableOfferContactInfo(
        for offer: ExchangeOffer
    ) -> ExchangeOffer.ContactInfo? {
        guard offer.status == .active, offer.visibility != .hidden else { return nil }
        guard let contact = offer.contactInfo?.normalized(), !contact.isEmpty else {
            return nil
        }
        return contact
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
