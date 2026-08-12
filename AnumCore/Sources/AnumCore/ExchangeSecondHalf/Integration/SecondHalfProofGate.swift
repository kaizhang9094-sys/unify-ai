import Foundation

/// Gates automatic discovery-triggered second-half evaluation on persisted semantic proof.
public enum SecondHalfProofGate: Sendable {
    public struct Input: Sendable {
        public var source: String
        public var trigger: RequesterDraftMaterializationPolicy.Trigger
        public var thread: ExchangeThread
        public var policyThread: ExchangeThread
        public var selectedMatch: ExchangeMatch?
        public var umbrellaMatches: [ExchangeMatch]
        public var activatedChildThreads: [ExchangeThread]
        public var offerSurfaceTokens: Set<String>?

        public init(
            source: String,
            trigger: RequesterDraftMaterializationPolicy.Trigger,
            thread: ExchangeThread,
            policyThread: ExchangeThread,
            selectedMatch: ExchangeMatch?,
            umbrellaMatches: [ExchangeMatch] = [],
            activatedChildThreads: [ExchangeThread] = [],
            offerSurfaceTokens: Set<String>? = nil
        ) {
            self.source = source
            self.trigger = trigger
            self.thread = thread
            self.policyThread = policyThread
            self.selectedMatch = selectedMatch
            self.umbrellaMatches = umbrellaMatches
            self.activatedChildThreads = activatedChildThreads
            self.offerSurfaceTokens = offerSurfaceTokens
        }
    }

    public struct Decision: Sendable, Equatable {
        public var applies: Bool
        public var shouldRun: Bool
        public var reason: String

        public init(applies: Bool, shouldRun: Bool, reason: String) {
            self.applies = applies
            self.shouldRun = shouldRun
            self.reason = reason
        }
    }

    public struct SemanticMatchProofSafetyResult: Sendable, Equatable {
        public var isSafe: Bool
        public var reason: String
        public var isWeakMatch: Bool
        public var diagnostics: [String: String]

        public init(
            isSafe: Bool,
            reason: String,
            isWeakMatch: Bool = false,
            diagnostics: [String: String] = [:]
        ) {
            self.isSafe = isSafe
            self.reason = reason
            self.isWeakMatch = isWeakMatch
            self.diagnostics = diagnostics
        }
    }

    public static func appliesToDiscoveryAutomaticSecondHalf(
        source: String,
        trigger: RequesterDraftMaterializationPolicy.Trigger
    ) -> Bool {
        guard trigger == .automaticSecondHalf else { return false }
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "submit" || normalized == "refreshsearch" {
            return true
        }
        if normalized.hasSuffix(".childcoordination") {
            return true
        }
        return false
    }

    public static func evaluate(_ input: Input) -> Decision {
        guard appliesToDiscoveryAutomaticSecondHalf(
            source: input.source,
            trigger: input.trigger
        ) else {
            return Decision(applies: false, shouldRun: true, reason: "out_of_scope")
        }

        guard let match = input.selectedMatch else {
            let safety = SemanticMatchProofSafetyResult(
                isSafe: false,
                reason: "missing_selected_match"
            )
            logGate(
                source: input.source,
                threadID: input.thread.id,
                selectedOfferID: input.thread.canonicalCommercialOfferAnchor,
                matchID: nil,
                action: "block",
                safety: safety
            )
            return Decision(applies: true, shouldRun: false, reason: "missing_selected_match")
        }

        let selectedOfferID = trimmed(match.offerID)
        guard let selectedOfferID else {
            let safety = SemanticMatchProofSafetyResult(
                isSafe: false,
                reason: "missing_selected_offer",
                diagnostics: ["matchID": match.id.uuidString]
            )
            logGate(
                source: input.source,
                threadID: input.thread.id,
                selectedOfferID: nil,
                matchID: match.id,
                action: "block",
                safety: safety
            )
            return Decision(applies: true, shouldRun: false, reason: "missing_selected_offer")
        }

        let semanticTarget = ExchangeSemanticTarget.from(thread: input.policyThread)
        var safety = evaluateSemanticMatchProofSafety(
            match: match,
            policyThread: input.policyThread,
            requireConcreteProof: semanticTarget.minimumProofPolicy.requiresConcreteProof
        )

        if safety.isSafe, isOfferAutomationPath(thread: input.policyThread) {
            safety = evaluateInheritedProofSafety(match: match, current: safety)
        }

        if safety.isSafe {
            let coverage = SecondHalfProofTargetCoverage.coversNormalizedTarget(
                policyThread: input.policyThread,
                proof: match.semanticProof ?? .empty,
                selectedOfferID: selectedOfferID,
                offerSurfaceTokens: input.offerSurfaceTokens
            )
            safety.diagnostics["normalizedTarget"] = coverage.normalizedTarget ?? "nil"
            safety.diagnostics["concreteTargetTokens"] = coverage.concreteTargetTokens.joined(separator: ",")
            safety.diagnostics["concreteTargetCovered"] = coverage.covered ? "true" : "false"
            if !coverage.covered {
                safety = SemanticMatchProofSafetyResult(
                    isSafe: false,
                    reason: "target_concept_not_covered",
                    diagnostics: safety.diagnostics
                )
            }
        }

        if safety.isSafe,
           isChildCoordinationAutomaticSource(input.source),
           input.thread.threadRole == .candidateCoordination {
            let shownCheck = evaluateShownCandidateAlignment(
                childThread: input.thread,
                childOfferID: selectedOfferID,
                umbrellaThread: input.policyThread,
                umbrellaMatches: input.umbrellaMatches,
                activatedChildThreads: input.activatedChildThreads
            )
            safety.diagnostics.merge(shownCheck.diagnostics) { _, new in new }
            if !shownCheck.isShown {
                safety = SemanticMatchProofSafetyResult(
                    isSafe: false,
                    reason: shownCheck.reason,
                    diagnostics: safety.diagnostics
                )
            }
        }

        if safety.isSafe {
            let allowReason = resolveAllowReason(
                source: input.source,
                selectedOfferID: selectedOfferID,
                umbrellaThread: input.policyThread,
                childThread: input.thread
            )
            safety = SemanticMatchProofSafetyResult(
                isSafe: true,
                reason: allowReason,
                diagnostics: safety.diagnostics
            )
            logGate(
                source: input.source,
                threadID: input.thread.id,
                selectedOfferID: selectedOfferID,
                matchID: match.id,
                action: "allow",
                safety: safety
            )
            return Decision(applies: true, shouldRun: true, reason: safety.reason)
        }

        logGate(
            source: input.source,
            threadID: input.thread.id,
            selectedOfferID: selectedOfferID,
            matchID: match.id,
            action: "block",
            safety: safety
        )
        return Decision(applies: true, shouldRun: false, reason: safety.reason)
    }

    public static func evaluateSemanticMatchProofSafety(
        match: ExchangeMatch,
        policyThread: ExchangeThread,
        requireConcreteProof: Bool
    ) -> SemanticMatchProofSafetyResult {
        var diagnostics: [String: String] = [
            "matchStrength": match.strength.rawValue,
            "fitScore": String(format: "%.3f", match.score),
            "offerID": match.offerID ?? "nil",
            "counterpartyID": match.counterpartyID,
            "requireConcreteProof": requireConcreteProof ? "true" : "false",
        ]

        if match.strength == .weak {
            diagnostics["minimumProofPolicy"] = ExchangeSemanticTarget
                .from(thread: policyThread)
                .minimumProofPolicy.rawValue
            return SemanticMatchProofSafetyResult(
                isSafe: false,
                reason: "weak_match_strength",
                isWeakMatch: true,
                diagnostics: diagnostics
            )
        }

        if ExchangeOfferObjectLane.isObjectLaneActive(thread: policyThread) {
            let maxObjectEvidence = maxQualifyingObjectEvidenceScore(for: match)
            diagnostics["objectLaneActive"] = "true"
            diagnostics["maxObjectEvidence"] = String(format: "%.3f", maxObjectEvidence)

            if maxObjectEvidence <= 0 {
                return SemanticMatchProofSafetyResult(
                    isSafe: false,
                    reason: "insufficient_object_evidence",
                    diagnostics: diagnostics
                )
            }

            if ExchangeOfferObjectLane.resolveSelectedOfferID(
                provenObjectOfferIDs: Set(match.provenObjectOfferIDs),
                objectEvidenceScoreByOfferID: match.objectEvidenceScoreByOfferID,
                preferredOfferID: match.offerID
            ) == nil {
                return SemanticMatchProofSafetyResult(
                    isSafe: false,
                    reason: "unresolved_proven_offer",
                    diagnostics: diagnostics
                )
            }
        } else {
            diagnostics["objectLaneActive"] = "false"
        }

        let semanticTarget = ExchangeSemanticTarget.from(thread: policyThread)
        diagnostics["minimumProofPolicy"] = semanticTarget.minimumProofPolicy.rawValue

        guard requireConcreteProof else {
            return SemanticMatchProofSafetyResult(
                isSafe: true,
                reason: "proof_not_required",
                diagnostics: diagnostics
            )
        }

        let proof = match.semanticProof ?? .empty
        diagnostics["satisfiesMinimumProof"] = proof.summary.satisfiesMinimumProof ? "true" : "false"
        diagnostics["hasWeakRecallOnly"] = proof.summary.hasWeakRecallOnly ? "true" : "false"
        diagnostics["maxProofStrength"] = proof.summary.maxProofStrength.rawValue

        if proof.isEmpty {
            return SemanticMatchProofSafetyResult(
                isSafe: false,
                reason: "missing_semantic_proof",
                diagnostics: diagnostics
            )
        }

        if !proof.summary.satisfiesMinimumProof {
            return SemanticMatchProofSafetyResult(
                isSafe: false,
                reason: "insufficient_semantic_proof",
                diagnostics: diagnostics
            )
        }

        if proof.summary.hasWeakRecallOnly {
            return SemanticMatchProofSafetyResult(
                isSafe: false,
                reason: "weak_recall_only_proof",
                diagnostics: diagnostics
            )
        }

        return SemanticMatchProofSafetyResult(
            isSafe: true,
            reason: "proof_safe",
            diagnostics: diagnostics
        )
    }

    static func evaluateInheritedProofSafety(
        match: ExchangeMatch,
        current: SemanticMatchProofSafetyResult
    ) -> SemanticMatchProofSafetyResult {
        guard current.isSafe else { return current }
        guard let selectedOfferID = trimmed(match.offerID) else { return current }
        let proof = match.semanticProof ?? .empty
        guard let attachment = SecondHalfProofTargetCoverage.primaryOfferAttachment(
            proof: proof,
            selectedOfferID: selectedOfferID
        ) else {
            return current
        }

        var diagnostics = current.diagnostics
        diagnostics["proofAttachmentReason"] = attachment.reason.rawValue

        switch attachment.reason {
        case .profileInheritedOffer:
            return SemanticMatchProofSafetyResult(
                isSafe: false,
                reason: "inherited_profile_only_proof",
                diagnostics: diagnostics
            )
        case .objectEmbeddingProven, .directOfferDocumentHit, .capabilitySurfaceBridge, .affinitySurfaceBridge, .unmatched:
            return current
        }
    }

    static func evaluateShownCandidateAlignment(
        childThread: ExchangeThread,
        childOfferID: String,
        umbrellaThread: ExchangeThread,
        umbrellaMatches: [ExchangeMatch],
        activatedChildThreads: [ExchangeThread]
    ) -> (isShown: Bool, reason: String, diagnostics: [String: String]) {
        let canonicalOfferID = ExchangeThreadCanonicalDiscoverySelectionMetadata.selectedOfferID(
            from: umbrellaThread.metadata
        )
        let childThreads = activatedChildThreadsForShownResolution(
            childThread: childThread,
            activatedChildThreads: activatedChildThreads
        )
        let resolution = SecondHalfProofShownCandidates.activatedOfferIDs(
            umbrellaThread: umbrellaThread,
            umbrellaMatches: umbrellaMatches,
            activatedChildThreads: childThreads
        )
        let isShown = SecondHalfProofShownCandidates.isShownSelectedOffer(
            selectedOfferID: childOfferID,
            resolution: resolution
        )

        let diagnostics: [String: String] = [
            "childOfferID": childOfferID,
            "canonicalSelectedOfferID": canonicalOfferID ?? "nil",
            "sourceRank": childThread.sourceRank.map(String.init) ?? "nil",
            "shownOfferIDsCount": String(resolution.offerIDs.count),
            "shownOfferIDsPreview": previewOfferIDs(resolution.orderedOfferIDs),
            "isShownSelectedOffer": isShown ? "true" : "false",
        ]

        if isShown {
            return (true, "shown_candidate", diagnostics)
        }
        return (false, "not_shown_candidate", diagnostics)
    }

    static func activatedChildThreadsForShownResolution(
        childThread: ExchangeThread,
        activatedChildThreads: [ExchangeThread]
    ) -> [ExchangeThread] {
        if !activatedChildThreads.isEmpty {
            return activatedChildThreads
        }
        if childThread.threadRole == .candidateCoordination {
            return [childThread]
        }
        return []
    }

    static func resolveAllowReason(
        source: String,
        selectedOfferID: String,
        umbrellaThread: ExchangeThread,
        childThread: ExchangeThread
    ) -> String {
        guard isChildCoordinationAutomaticSource(source),
              childThread.threadRole == .candidateCoordination else {
            return "proof_safe_full_target"
        }
        let canonicalOfferID = ExchangeThreadCanonicalDiscoverySelectionMetadata.selectedOfferID(
            from: umbrellaThread.metadata
        )
        if let canonicalOfferID, selectedOfferID == canonicalOfferID {
            return "proof_safe_canonical_candidate"
        }
        return "proof_safe_shown_candidate"
    }

    static func previewOfferIDs(_ offerIDs: [String], limit: Int = 5) -> String {
        guard !offerIDs.isEmpty else { return "[]" }
        let preview = offerIDs.prefix(limit).joined(separator: ",")
        if offerIDs.count > limit {
            return "[\(preview),…]"
        }
        return "[\(preview)]"
    }

    static func isChildCoordinationAutomaticSource(_ source: String) -> Bool {
        source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix(".childcoordination")
    }

    static func isOfferAutomationPath(thread: ExchangeThread) -> Bool {
        guard let facets = thread.facets else { return false }
        switch facets.queryIntentClass {
        case .offerSearch, .providerSearch, .capabilitySearch:
            return facets.surfacePreference == .offer || facets.surfacePreference == .mixed
        default:
            return false
        }
    }

    static func maxQualifyingObjectEvidenceScore(for match: ExchangeMatch) -> Double {
        let provenIDs = Set(match.provenObjectOfferIDs)
        return match.objectEvidenceScoreByOfferID
            .filter { entry in
                provenIDs.contains(entry.key)
                    && entry.value >= ExchangeOfferObjectLane.minimumObjectEvidenceScore
            }
            .values
            .max() ?? 0
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    #if DEBUG
    public static func logGate(
        source: String,
        threadID: ExchangeThread.ID,
        selectedOfferID: String?,
        matchID: ExchangeMatch.ID?,
        action: String,
        safety: SemanticMatchProofSafetyResult
    ) {
        let proof = safety.diagnostics
        let satisfies = proof["satisfiesMinimumProof"] ?? "nil"
        let weakRecall = proof["hasWeakRecallOnly"] ?? "nil"
        let maxStrength = proof["maxProofStrength"] ?? "nil"
        let normalizedTarget = proof["normalizedTarget"] ?? "nil"
        let concreteCovered = proof["concreteTargetCovered"] ?? "nil"
        let canonicalSelected = proof["canonicalSelectedOfferID"] ?? "nil"
        let shownCount = proof["shownOfferIDsCount"] ?? "nil"
        let shownPreview = proof["shownOfferIDsPreview"] ?? "nil"
        let isShownSelected = proof["isShownSelectedOffer"] ?? "nil"
        let sourceRank = proof["sourceRank"] ?? "nil"
        Swift.print(
            "[SecondHalfProofGate] source=\(source) " +
            "threadID=\(threadID.uuidString) " +
            "selectedOfferID=\(selectedOfferID ?? "nil") " +
            "matchID=\(matchID?.uuidString ?? "nil") " +
            "action=\(action) " +
            "reason=\(safety.reason) " +
            "satisfiesMinimumProof=\(satisfies) " +
            "hasWeakRecallOnly=\(weakRecall) " +
            "maxProofStrength=\(maxStrength) " +
            "normalizedTarget=\(normalizedTarget) " +
            "concreteTargetCovered=\(concreteCovered) " +
            "canonicalSelectedOfferID=\(canonicalSelected) " +
            "shownOfferIDsCount=\(shownCount) " +
            "shownOfferIDsPreview=\(shownPreview) " +
            "isShownSelectedOffer=\(isShownSelected) " +
            "sourceRank=\(sourceRank)"
        )
    }
    #else
    public static func logGate(
        source: String,
        threadID: ExchangeThread.ID,
        selectedOfferID: String?,
        matchID: ExchangeMatch.ID?,
        action: String,
        safety: SemanticMatchProofSafetyResult
    ) { }
    #endif
}
