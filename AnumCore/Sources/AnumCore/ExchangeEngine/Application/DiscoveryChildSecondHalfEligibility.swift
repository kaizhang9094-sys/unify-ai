import Foundation

/// Determines whether a discovery child coordination thread should auto-run second-half.
///
/// Child thread creation (recall / umbrella workbench) is intentionally wider than
/// automatic coordination automation. This gate decouples the two policies.
public struct DiscoveryChildSecondHalfEligibility: Sendable, Equatable {
    public enum Decision: Equatable, Sendable {
        case eligible
        case shortlistOnly
        case weakCandidate
        case blocked
    }

    public enum Trigger: String, Sendable, Equatable {
        /// Automatic run immediately after discovery (`runSecondHalfAfterDiscoveryResponse`).
        case discoveryAuto
        /// Explicit user action such as "let secretary handle".
        case userExplicit
    }

    public var decision: Decision
    public var reason: String
    public var diagnostics: [String: String]

    public var shouldRunSecondHalf: Bool {
        decision == .eligible
    }

    public init(
        decision: Decision,
        reason: String,
        diagnostics: [String: String] = [:]
    ) {
        self.decision = decision
        self.reason = reason
        self.diagnostics = diagnostics
    }

    /// Minimum fit score for a rank-1 **moderate** child to auto-run second-half on discovery.
    public static let moderateRankOneMinimumFitScore: Double = 0.65

    public static func evaluate(
        childThread: ExchangeThread,
        childMatch: ExchangeMatch?,
        umbrellaThread: ExchangeThread,
        umbrellaMatches: [ExchangeMatch],
        trigger: Trigger = .discoveryAuto
    ) -> DiscoveryChildSecondHalfEligibility {
        var diagnostics: [String: String] = [
            "trigger": trigger.rawValue,
            "childThreadID": childThread.id.uuidString,
            "umbrellaThreadID": umbrellaThread.id.uuidString,
            "sourceRank": childThread.sourceRank.map(String.init) ?? "nil",
            "sourceMatchID": childThread.sourceMatchID?.uuidString ?? "nil",
        ]

        guard childThread.threadRole == .candidateCoordination else {
            diagnostics["threadRole"] = childThread.threadRole.rawValue
            return .init(
                decision: .eligible,
                reason: "not_candidate_coordination_child",
                diagnostics: diagnostics
            )
        }

        guard let childMatch else {
            return .init(
                decision: .blocked,
                reason: "missing_child_match",
                diagnostics: diagnostics
            )
        }

        diagnostics["matchStrength"] = childMatch.strength.rawValue
        diagnostics["fitScore"] = String(format: "%.3f", childMatch.score)
        diagnostics["offerID"] = childMatch.offerID ?? "nil"
        diagnostics["counterpartyID"] = childMatch.counterpartyID

        let semanticTarget = ExchangeSemanticTarget.from(thread: umbrellaThread)
        let requireConcreteProof = trigger == .discoveryAuto
            && semanticTarget.minimumProofPolicy.requiresConcreteProof

        let proofSafety = SecondHalfProofGate.evaluateSemanticMatchProofSafety(
            match: childMatch,
            policyThread: umbrellaThread,
            requireConcreteProof: requireConcreteProof
        )
        diagnostics.merge(proofSafety.diagnostics) { _, new in new }

        if !proofSafety.isSafe {
            if proofSafety.isWeakMatch {
                return .init(
                    decision: .weakCandidate,
                    reason: proofSafety.reason,
                    diagnostics: diagnostics
                )
            }
            return .init(
                decision: .shortlistOnly,
                reason: proofSafety.reason,
                diagnostics: diagnostics
            )
        }

        guard trigger == .discoveryAuto else {
            return .init(
                decision: .eligible,
                reason: "user_explicit_second_half",
                diagnostics: diagnostics
            )
        }

        let primaryMatch = primaryDiscoveryMatch(
            umbrellaThread: umbrellaThread,
            matches: umbrellaMatches
        )
        diagnostics["primaryMatchID"] = primaryMatch?.id.uuidString ?? "nil"

        let isPrimaryChild =
            childThread.sourceRank == 1 ||
            (primaryMatch != nil && childThread.sourceMatchID == primaryMatch?.id) ||
            (primaryMatch != nil && childMatch.id == primaryMatch?.id)

        diagnostics["isPrimaryChild"] = isPrimaryChild ? "true" : "false"

        if !isPrimaryChild {
            return .init(
                decision: .shortlistOnly,
                reason: "non_primary_shortlist_candidate",
                diagnostics: diagnostics
            )
        }

        switch childMatch.strength {
        case .strong:
            return .init(
                decision: .eligible,
                reason: "primary_strong_candidate",
                diagnostics: diagnostics
            )
        case .moderate:
            if childMatch.score >= moderateRankOneMinimumFitScore {
                return .init(
                    decision: .eligible,
                    reason: "primary_moderate_above_fit_floor",
                    diagnostics: diagnostics
                )
            }
            return .init(
                decision: .shortlistOnly,
                reason: "primary_moderate_below_fit_floor",
                diagnostics: diagnostics
            )
        case .weak:
            return .init(
                decision: .weakCandidate,
                reason: "weak_match_strength",
                diagnostics: diagnostics
            )
        }
    }

    // MARK: - Primary discovery match (mirrors object-lane bestMatch ordering on umbrella rows)

    static func primaryDiscoveryMatch(
        umbrellaThread: ExchangeThread,
        matches: [ExchangeMatch]
    ) -> ExchangeMatch? {
        let viable = matches.filter { $0.strength != .weak }
        guard !viable.isEmpty else { return nil }

        let semanticTarget = ExchangeSemanticTarget.from(thread: umbrellaThread)

        if ExchangeOfferObjectLane.isObjectLaneActive(thread: umbrellaThread) {
            return viable.max(by: { lhs, rhs in
                !objectLaneMatchPrefers(lhs: lhs, rhs: rhs)
            })
        }

        if semanticTarget.minimumProofPolicy.requiresConcreteProof {
            return viable.max(by: { lhs, rhs in
                !semanticProofMatchPrefers(lhs: lhs, rhs: rhs)
            })
        }

        return viable.max(by: { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.counterpartyID > rhs.counterpartyID
        })
    }

    static func semanticProofMatchPrefers(lhs: ExchangeMatch, rhs: ExchangeMatch) -> Bool {
        let lhsProof = lhs.semanticProof ?? .empty
        let rhsProof = rhs.semanticProof ?? .empty

        if lhsProof.summary.satisfiesMinimumProof != rhsProof.summary.satisfiesMinimumProof {
            return lhsProof.summary.satisfiesMinimumProof
        }

        if lhsProof.summary.maxProofStrength.selectionPriority
            != rhsProof.summary.maxProofStrength.selectionPriority {
            return lhsProof.summary.maxProofStrength.selectionPriority
                > rhsProof.summary.maxProofStrength.selectionPriority
        }

        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.counterpartyID < rhs.counterpartyID
    }

    static func objectLaneMatchPrefers(lhs: ExchangeMatch, rhs: ExchangeMatch) -> Bool {
        let lhsObject = maxQualifyingObjectEvidenceScore(for: lhs)
        let rhsObject = maxQualifyingObjectEvidenceScore(for: rhs)
        if lhsObject != rhsObject { return lhsObject > rhsObject }
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.counterpartyID < rhs.counterpartyID
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
}
