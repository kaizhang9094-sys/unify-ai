import Foundation

extension ExchangeFitEngine {
    struct SemanticProofOfferShaping: Sendable {
        var offerEvidence: Double
        var forcedWeak: Bool
        var reason: String
    }

    func applySemanticProofOfferShaping(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        lexicalOfferEvidence: Double,
        objectLaneActive: Bool,
        objectLaneOfferEvidence: Double?,
        forcedWeakDueToObjectMismatch: Bool
    ) -> SemanticProofOfferShaping {
        let semanticTarget = ExchangeSemanticTarget.from(thread: thread)
        let proof = candidate.semanticProof

        var offerEvidence = objectLaneActive
            ? (objectLaneOfferEvidence ?? lexicalOfferEvidence)
            : lexicalOfferEvidence
        let offerEvidenceBefore = offerEvidence

        var forcedWeak = forcedWeakDueToObjectMismatch
        var reason = forcedWeak ? "object_lane_mismatch" : "baseline"

        if semanticTarget.minimumProofPolicy.requiresConcreteProof, !proof.isEmpty {
            if proof.summary.satisfiesMinimumProof {
                offerEvidence = applySemanticProofOfferBoost(base: offerEvidence, proof: proof)
                offerEvidence = min(max(
                    offerEvidence + proofSpecificityOfferBonus(proof: proof, candidate: candidate),
                    0
                ), 1)
                reason = "satisfied_semantic_proof"
            } else {
                offerEvidence = min(offerEvidence, unsatisfiedConcreteProofOfferEvidenceCap)
                forcedWeak = true
                reason = unsatisfiedProofReason(proof: proof)
            }
        } else if !proof.isEmpty {
            if proof.summary.satisfiesMinimumProof {
                offerEvidence = applySemanticProofOfferBoost(base: offerEvidence, proof: proof)
                offerEvidence = min(max(
                    offerEvidence + proofSpecificityOfferBonus(proof: proof, candidate: candidate),
                    0
                ), 1)
                reason = "satisfied_semantic_proof_recall_target"
            } else if proof.summary.hasWeakRecallOnly {
                offerEvidence = min(offerEvidence, weakRecallOnlyOfferEvidenceCap)
                reason = "weak_recall_only"
            } else if proof.summary.maxProofStrength == .compatible {
                offerEvidence = min(offerEvidence, compatibleOnlyOfferEvidenceCap)
                reason = "compatible_only_no_minimum"
            }
        }

        let hasRequiredProof = !semanticTarget.minimumProofPolicy.requiresConcreteProof
            || proof.isEmpty
            || proof.summary.satisfiesMinimumProof

        if semanticTarget.minimumProofPolicy.requiresConcreteProof,
           !proof.isEmpty,
           !proof.summary.satisfiesMinimumProof {
            forcedWeak = true
        }

        logFitProofInput(
            thread: thread,
            candidate: candidate,
            proof: proof,
            offerEvidenceBefore: offerEvidenceBefore,
            offerEvidenceAfter: offerEvidence,
            forcedWeak: forcedWeak,
            reason: reason,
            hasRequiredProof: hasRequiredProof
        )

        return SemanticProofOfferShaping(
            offerEvidence: offerEvidence,
            forcedWeak: forcedWeak,
            reason: reason
        )
    }

    func proofSpecificityOfferBonus(
        proof: ExchangeCandidateSemanticProof,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Double {
        guard proof.summary.satisfiesMinimumProof else { return 0 }

        guard let attachment = primaryQualifyingProofAttachment(proof: proof) else {
            return 0
        }

        var bonus = 0.0

        bonus += Double(attachment.targetOverlap) * 0.05
        bonus -= Double(attachment.genericOverlap) * 0.025

        if attachment.genericOverlap > attachment.targetOverlap {
            bonus -= 0.06
        }

        switch attachment.reason {
        case .directOfferDocumentHit, .objectEmbeddingProven:
            bonus += 0.06
        case .capabilitySurfaceBridge:
            bonus += 0.02
        case .profileInheritedOffer, .affinitySurfaceBridge, .unmatched:
            bonus -= 0.08
        }

        switch attachment.proofStrength {
        case .exact:
            bonus += 0.08
        case .concrete:
            bonus += 0.04
        case .compatible:
            bonus += 0.01
        case .weakRecall:
            bonus -= 0.06
        }

        if candidate.matchedOffers.count == 1, sellerDistinctOfferSurfaceCount(candidate: candidate) == 1 {
            bonus += 0.08
        } else if sellerDistinctOfferSurfaceCount(candidate: candidate) > 1 {
            bonus -= 0.10
        } else if candidate.matchedOffers.count > 2 {
            bonus -= 0.04
        }

        if let offer = candidate.matchedOffers.first(where: { $0.id == attachment.offerID }) {
            bonus += offerTargetSpecificityDensityBonus(
                attachment: attachment,
                offer: offer
            )
        }

        return min(max(bonus, -0.12), 0.22)
    }

    func applySemanticProofOfferBoost(
        base: Double,
        proof: ExchangeCandidateSemanticProof
    ) -> Double {
        let floor: Double
        switch proof.summary.maxProofStrength {
        case .exact:
            floor = 0.84
        case .concrete:
            floor = 0.68
        case .compatible:
            floor = 0.52
        case .weakRecall:
            floor = 0.22
        }
        return min(max(max(base, floor), 0), 1)
    }

    func sellerDistinctOfferSurfaceCount(
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate
    ) -> Int {
        if let docs = candidate.directoryEvidence?.retrievalDocuments, !docs.isEmpty {
            let offerIDs = Set(
                docs.compactMap { document -> String? in
                    guard document.entityType == .offer else { return nil }
                    let trimmed = document.offerID?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed?.isEmpty == false ? trimmed : nil
                }
            )
            if !offerIDs.isEmpty {
                return offerIDs.count
            }
        }

        if !candidate.provenObjectOfferIDs.isEmpty {
            return candidate.provenObjectOfferIDs.count
        }

        return candidate.matchedOffers.count
    }

    func primaryQualifyingProofAttachment(
        proof: ExchangeCandidateSemanticProof
    ) -> ExchangeCandidateSemanticProof.OfferAttachment? {
        let qualifying = proof.offerAttachments.filter(\.satisfiesMinimumProof)
        if !qualifying.isEmpty {
            return qualifying.max(by: { lhs, rhs in
                if lhs.targetOverlap != rhs.targetOverlap {
                    return lhs.targetOverlap < rhs.targetOverlap
                }
                return lhs.proofStrength.selectionPriority < rhs.proofStrength.selectionPriority
            })
        }

        return proof.offerAttachments.max(by: { lhs, rhs in
            if lhs.targetOverlap != rhs.targetOverlap {
                return lhs.targetOverlap < rhs.targetOverlap
            }
            return lhs.proofStrength.selectionPriority < rhs.proofStrength.selectionPriority
        })
    }

    // MARK: - Private

    private var unsatisfiedConcreteProofOfferEvidenceCap: Double { 0.12 }
    private var weakRecallOnlyOfferEvidenceCap: Double { 0.28 }
    private var compatibleOnlyOfferEvidenceCap: Double { 0.38 }

    private func unsatisfiedProofReason(proof: ExchangeCandidateSemanticProof) -> String {
        if proof.summary.hasWeakRecallOnly {
            return "unsatisfied_weak_recall_proof"
        }
        if proof.summary.maxProofStrength == .compatible {
            return "unsatisfied_compatible_only_proof"
        }
        return "unsatisfied_semantic_proof"
    }

    private func offerTargetSpecificityDensityBonus(
        attachment: ExchangeCandidateSemanticProof.OfferAttachment,
        offer: ExchangeOffer
    ) -> Double {
        guard attachment.targetOverlap > 0 else { return 0 }

        var values: [String] = [offer.title]
        if let summary = offer.summary { values.append(summary) }
        if let category = offer.category { values.append(category) }
        values.append(contentsOf: offer.tags)

        let tokenCount = tokenCountForSpecificityDensity(values.joined(separator: " "))
        guard tokenCount > 0 else { return 0 }

        let density = Double(attachment.targetOverlap) / Double(tokenCount)
        return min(density * 0.24, 0.10)
    }

    private func tokenCountForSpecificityDensity(_ text: String) -> Int {
        Set(
            text
                .lowercased()
                .split { !($0.isLetter || $0.isNumber) }
                .map(String.init)
                .filter { $0.count >= 2 }
        ).count
    }

    private func logFitProofInput(
        thread: ExchangeThread,
        candidate: ExchangeDiscoveryEngine.DiscoveryCandidate,
        proof: ExchangeCandidateSemanticProof,
        offerEvidenceBefore: Double,
        offerEvidenceAfter: Double,
        forcedWeak: Bool,
        reason: String,
        hasRequiredProof: Bool
    ) {
        let primary = primaryQualifyingProofAttachment(proof: proof)
        let primaryOfferID = primary?.offerID
            ?? proof.summary.primaryOfferID
            ?? candidate.matchedOffers.first?.id

        exFitProofLog(
            "[FitProofInput] " +
            "threadID=\(thread.id.uuidString) " +
            "counterpartyID=\(candidate.counterparty.id) " +
            "publicProfileID=\(candidate.publicProfileID ?? "nil") " +
            "offerID=\(primaryOfferID ?? "nil") " +
            "proofStrength=\(proof.summary.maxProofStrength.rawValue) " +
            "satisfiesMinimumProof=\(proof.summary.satisfiesMinimumProof) " +
            "hasRequiredProof=\(hasRequiredProof) " +
            "objectEvidenceScore=\(primary?.objectEvidenceScore.map { String(format: "%.3f", $0) } ?? "nil") " +
            "offerEvidenceBefore=\(String(format: "%.3f", offerEvidenceBefore)) " +
            "offerEvidenceAfter=\(String(format: "%.3f", offerEvidenceAfter)) " +
            "forcedWeak=\(forcedWeak) " +
            "reason=\(reason)"
        )
    }
}

#if DEBUG
@inline(__always)
private func exFitProofLog(_ message: @autoclosure () -> String) {
    print("[ExchangeFitEngine] \(message())")
}
#else
@inline(__always)
private func exFitProofLog(_ message: @autoclosure () -> String) { }
#endif
