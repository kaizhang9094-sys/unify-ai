import Foundation

/// Builds `ExchangeCandidateSemanticProof` from projector attach context.
enum ExchangeSemanticProofBuilder {
    private static let exactObjectEvidenceFloor: Double = 0.45
    private static let strongTargetOverlap = 2

    static func build(
        target: ExchangeSemanticTarget,
        document: ExchangeRetrievalDocument,
        counterpartyID: String,
        matchedOffers: [ExchangeOffer],
        recallObjectEvidenceScore: Double?,
        coarse: ExchangeDiscoveryEngine.CoarseSignal,
        dominantSurfaceKind: ExchangeSemanticSurfaceKind,
        publicProfile: ExchangePublicNodeProfile?,
        attachPath: AttachPath
    ) -> ExchangeCandidateSemanticProof {
        let vocabulary = ExchangeSemanticTargetProofTerms.vocabulary(for: target)
        var offerAttachments: [ExchangeCandidateSemanticProof.OfferAttachment] = []
        offerAttachments.reserveCapacity(matchedOffers.count)

        for offer in matchedOffers {
            let surfaceTokens = ExchangeSemanticTargetProofTerms.offerSurfaceTokens(
                offer: offer,
                document: document
            )
            let compatibility = ExchangeSemanticTargetProofTerms.compatibility(
                vocabulary: vocabulary,
                surfaceTokens: surfaceTokens
            )

            let reason: ExchangeCandidateSemanticProof.AttachmentReason
            let strength: ExchangeSemanticProofStrength
            let channel: ExchangeSemanticProofChannel?
            let objectScore: Double?

            switch attachPath {
            case .objectEmbeddingProven, .objectEmbeddingRecall:
                reason = .objectEmbeddingProven
                objectScore = recallObjectEvidenceScore
                strength = objectEmbeddingStrength(
                    score: objectScore,
                    compatibility: compatibility
                )
                channel = .objectEmbedding
            case .directOfferDocument:
                reason = .directOfferDocumentHit
                objectScore = nil
                strength = directDocumentStrength(
                    compatibility: compatibility,
                    coarseOfferOverlap: coarse.offerOverlap
                )
                channel = .directOfferDocument
            case .profileInherited:
                reason = .profileInheritedOffer
                objectScore = nil
                strength = inheritedOfferStrength(
                    compatibility: compatibility,
                    attachPath: attachPath
                )
                channel = .inheritedOffer
            }

            let satisfies = satisfiesMinimumProof(
                target: target,
                channel: channel,
                strength: strength,
                compatibility: compatibility,
                reason: reason
            )

            offerAttachments.append(
                .init(
                    offerID: offer.id,
                    reason: reason,
                    proofStrength: strength,
                    objectEvidenceScore: objectScore,
                    lexicalOverlap: compatibility.targetOverlap + compatibility.genericOverlap,
                    targetOverlap: compatibility.targetOverlap,
                    genericOverlap: compatibility.genericOverlap,
                    satisfiesMinimumProof: satisfies
                )
            )

            #if DEBUG
            exSemanticProofLog(
                "[ProjectorOfferAttach] " +
                "nodeID=\(counterpartyID) " +
                "offerID=\(offer.id) " +
                "targetTerms=\(vocabulary.logLabel) " +
                "targetOverlap=\(compatibility.targetOverlap) " +
                "genericOverlap=\(compatibility.genericOverlap) " +
                "reason=\(reason.rawValue) " +
                "proofStrength=\(strength.rawValue) " +
                "satisfiesMinimumProof=\(satisfies) " +
                "objectEvidenceScore=\(objectScore.map { String(format: "%.3f", $0) } ?? "nil")"
            )
            #endif
        }

        let surfaceAttachment = buildSurfaceAttachment(
            target: target,
            vocabulary: vocabulary,
            document: document,
            publicProfile: publicProfile,
            dominantSurfaceKind: dominantSurfaceKind,
            attachPath: attachPath
        )

        let summary = summarize(
            target: target,
            offerAttachments: offerAttachments,
            surfaceAttachment: surfaceAttachment
        )

        return ExchangeCandidateSemanticProof(
            offerAttachments: offerAttachments,
            surfaceAttachment: surfaceAttachment,
            summary: summary
        )
    }

    enum AttachPath: Sendable, Hashable {
        /// Object lane active and legacy proven attach path.
        case objectEmbeddingProven
        /// Vector recall only; semantic proof still evaluated but legacy lane fields stay empty.
        case objectEmbeddingRecall
        case directOfferDocument
        case profileInherited
    }

    static func resolveAttachPath(
        document: ExchangeRetrievalDocument,
        thread: ExchangeThread,
        objectLaneActive: Bool,
        legacyProvenObjectOfferIDs: Set<String>,
        recallObjectEvidenceScore: Double?
    ) -> AttachPath {
        if objectLaneActive,
           !legacyProvenObjectOfferIDs.isEmpty,
           ExchangeOfferObjectLane.isOfferObjectDocument(document) {
            return .objectEmbeddingProven
        }

        if ExchangeOfferObjectLane.isOfferObjectDocument(document),
           recallObjectEvidenceScore != nil {
            return .objectEmbeddingRecall
        }

        switch document.surfaceType {
        case .offer:
            return .directOfferDocument
        default:
            return .profileInherited
        }
    }

    // MARK: - Private

    private static func buildSurfaceAttachment(
        target: ExchangeSemanticTarget,
        vocabulary: ExchangeSemanticTargetProofTerms.Vocabulary,
        document: ExchangeRetrievalDocument,
        publicProfile: ExchangePublicNodeProfile?,
        dominantSurfaceKind: ExchangeSemanticSurfaceKind,
        attachPath: AttachPath
    ) -> ExchangeCandidateSemanticProof.SurfaceAttachment? {
        let surfaceTokens = ExchangeSemanticTargetProofTerms.profileSurfaceTokens(
            document: document,
            publicProfile: publicProfile
        )
        let compatibility = ExchangeSemanticTargetProofTerms.compatibility(
            vocabulary: vocabulary,
            surfaceTokens: surfaceTokens
        )

        guard compatibility.targetOverlap > 0
            || compatibility.genericOverlap > 0
            || attachPath != .profileInherited else {
            return nil
        }

        let reason: ExchangeCandidateSemanticProof.AttachmentReason
        let channel: ExchangeSemanticProofChannel?

        switch dominantSurfaceKind {
        case .capability:
            reason = .capabilitySurfaceBridge
            channel = .capabilitySurface
        case .affinity:
            reason = .affinitySurfaceBridge
            channel = .affinitySurface
        case .offer, .offerObject:
            reason = attachPath == .profileInherited ? .profileInheritedOffer : .directOfferDocumentHit
            channel = attachPath == .profileInherited ? .inheritedOffer : .directOfferDocument
        case .profile, .seeking, .mixed, .unknown:
            reason = .profileInheritedOffer
            channel = .providerProfile
        }

        let strength = surfaceStrength(
            compatibility: compatibility,
            attachPath: attachPath,
            channel: channel
        )

        return ExchangeCandidateSemanticProof.SurfaceAttachment(
            surfaceKind: dominantSurfaceKind,
            reason: reason,
            proofStrength: strength,
            lexicalOverlap: compatibility.targetOverlap + compatibility.genericOverlap,
            satisfiesMinimumProof: satisfiesMinimumProof(
                target: target,
                channel: channel,
                strength: strength,
                compatibility: compatibility,
                reason: reason
            )
        )
    }

    private static func summarize(
        target: ExchangeSemanticTarget,
        offerAttachments: [ExchangeCandidateSemanticProof.OfferAttachment],
        surfaceAttachment: ExchangeCandidateSemanticProof.SurfaceAttachment?
    ) -> ExchangeCandidateSemanticProof.Summary {
        let qualifyingOffers = offerAttachments.filter(\.satisfiesMinimumProof)
        let primaryOfferID = qualifyingOffers
            .max(by: { lhs, rhs in
                if lhs.targetOverlap != rhs.targetOverlap {
                    return lhs.targetOverlap < rhs.targetOverlap
                }
                return proofStrengthOrdering(lhs.proofStrength, rhs.proofStrength) < 0
            })?
            .offerID
            ?? offerAttachments
                .max(by: { lhs, rhs in
                    if lhs.targetOverlap != rhs.targetOverlap {
                        return lhs.targetOverlap < rhs.targetOverlap
                    }
                    return proofStrengthOrdering(lhs.proofStrength, rhs.proofStrength) < 0
                })?
                .offerID

        var maxStrength = ExchangeSemanticProofStrength.weakRecall
        for attachment in offerAttachments {
            maxStrength = maxStrengthByPriority(maxStrength, attachment.proofStrength)
        }
        if let surfaceAttachment {
            maxStrength = maxStrengthByPriority(maxStrength, surfaceAttachment.proofStrength)
        }

        let hasQualifyingProof = !qualifyingOffers.isEmpty
            || (surfaceAttachment?.satisfiesMinimumProof == true)

        let satisfiesMinimum: Bool = {
            guard target.minimumProofPolicy.requiresConcreteProof else {
                return maxStrength != .weakRecall || !offerAttachments.isEmpty || surfaceAttachment != nil
            }
            return hasQualifyingProof
        }()

        let hasWeakRecallOnly: Bool = {
            guard !offerAttachments.isEmpty || surfaceAttachment != nil else { return true }
            if hasQualifyingProof { return false }
            return offerAttachments.allSatisfy { $0.proofStrength == .weakRecall }
                && (surfaceAttachment == nil || surfaceAttachment?.proofStrength == .weakRecall)
        }()

        return ExchangeCandidateSemanticProof.Summary(
            primaryOfferID: primaryOfferID,
            maxProofStrength: maxStrength,
            satisfiesMinimumProof: satisfiesMinimum,
            hasWeakRecallOnly: hasWeakRecallOnly
        )
    }

    private static func satisfiesMinimumProof(
        target: ExchangeSemanticTarget,
        channel: ExchangeSemanticProofChannel?,
        strength: ExchangeSemanticProofStrength,
        compatibility: ExchangeSemanticTargetProofTerms.Compatibility,
        reason: ExchangeCandidateSemanticProof.AttachmentReason
    ) -> Bool {
        guard strength.satisfiesConcretePolicy else { return false }

        switch reason {
        case .profileInheritedOffer:
            return false
        case .objectEmbeddingProven, .directOfferDocumentHit, .capabilitySurfaceBridge, .affinitySurfaceBridge, .unmatched:
            break
        }

        guard compatibility.hasMeaningfulTargetOverlap else { return false }

        guard target.minimumProofPolicy.requiresConcreteProof else {
            return strength != .weakRecall
        }

        guard let channel, target.acceptableProofChannels.contains(channel) else {
            return false
        }

        switch target.minimumProofPolicy {
        case .recallOnly:
            return true
        case .concreteSurfaceRequired:
            switch channel {
            case .objectEmbedding, .directOfferDocument:
                return strength == .exact || strength == .concrete
            case .capabilitySurface, .affinitySurface, .inheritedOffer, .providerProfile:
                return false
            }
        case .concreteOfferOrCapabilityRequired:
            switch channel {
            case .objectEmbedding, .directOfferDocument, .capabilitySurface:
                return strength == .exact || strength == .concrete
            case .affinitySurface:
                return target.surfacePreference == .affinity
                    && (strength == .exact || strength == .concrete)
            case .inheritedOffer, .providerProfile:
                return false
            }
        }
    }

    private static func objectEmbeddingStrength(
        score: Double?,
        compatibility: ExchangeSemanticTargetProofTerms.Compatibility
    ) -> ExchangeSemanticProofStrength {
        guard let score else { return .weakRecall }

        guard compatibility.hasMeaningfulTargetOverlap else {
            if score >= ExchangeOfferObjectLane.minimumObjectEvidenceScore {
                return .compatible
            }
            return .weakRecall
        }

        if compatibility.targetOverlap >= strongTargetOverlap,
           score >= exactObjectEvidenceFloor {
            return .exact
        }
        if score >= ExchangeOfferObjectLane.minimumObjectEvidenceScore {
            return .concrete
        }
        return .weakRecall
    }

    private static func directDocumentStrength(
        compatibility: ExchangeSemanticTargetProofTerms.Compatibility,
        coarseOfferOverlap: Int
    ) -> ExchangeSemanticProofStrength {
        guard compatibility.hasMeaningfulTargetOverlap else {
            return .weakRecall
        }

        let overlap = max(compatibility.targetOverlap, coarseOfferOverlap)
        if overlap >= strongTargetOverlap { return .exact }
        if overlap >= ExchangeSemanticTargetProofTerms.minimumMeaningfulTargetOverlap {
            return .concrete
        }
        return .compatible
    }

    private static func inheritedOfferStrength(
        compatibility: ExchangeSemanticTargetProofTerms.Compatibility,
        attachPath: AttachPath
    ) -> ExchangeSemanticProofStrength {
        guard attachPath != .profileInherited else {
            return .weakRecall
        }
        guard compatibility.hasMeaningfulTargetOverlap else {
            return .weakRecall
        }
        return .compatible
    }

    private static func surfaceStrength(
        compatibility: ExchangeSemanticTargetProofTerms.Compatibility,
        attachPath: AttachPath,
        channel: ExchangeSemanticProofChannel?
    ) -> ExchangeSemanticProofStrength {
        if attachPath == .profileInherited {
            return .weakRecall
        }
        guard compatibility.hasMeaningfulTargetOverlap else {
            return .weakRecall
        }
        if compatibility.targetOverlap >= strongTargetOverlap {
            return .exact
        }
        if channel == .capabilitySurface || channel == .directOfferDocument {
            return .concrete
        }
        return .compatible
    }

    private static func maxStrengthByPriority(
        _ lhs: ExchangeSemanticProofStrength,
        _ rhs: ExchangeSemanticProofStrength
    ) -> ExchangeSemanticProofStrength {
        lhs.selectionPriority >= rhs.selectionPriority ? lhs : rhs
    }

    private static func proofStrengthOrdering(
        _ lhs: ExchangeSemanticProofStrength,
        _ rhs: ExchangeSemanticProofStrength
    ) -> Int {
        lhs.selectionPriority - rhs.selectionPriority
    }

    static func mapDominantSurfaceKind(
        from document: ExchangeRetrievalDocument,
        dominantSurface: ExchangeDiscoveryEngine.DiscoveryCandidate.SurfaceType
    ) -> ExchangeSemanticSurfaceKind {
        if ExchangeOfferObjectLane.isOfferObjectDocument(document) {
            return .offerObject
        }
        switch dominantSurface {
        case .offer:
            return .offer
        case .capability:
            return .capability
        case .affinity:
            return .affinity
        case .mixed:
            return .mixed
        case .unknown:
            switch document.surfaceType {
            case .offer:
                return .offer
            case .publicProfileCapability:
                return .capability
            case .publicProfileAffinity:
                return .affinity
            case .publicProfileSeeking:
                return .seeking
            case .publicProfile:
                return .profile
            case .unknown:
                return .unknown
            }
        }
    }
}

#if DEBUG
@inline(__always)
private func exSemanticProofLog(_ message: @autoclosure () -> String) {
    print(message())
}
#else
@inline(__always)
private func exSemanticProofLog(_ message: @autoclosure () -> String) { }
#endif
