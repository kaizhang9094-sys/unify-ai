import Foundation

/// Resolves user-facing umbrella discovery grade from durable metadata and child context.
public enum ExchangeUmbrellaDiscoveryGradeProjection: Sendable {
    public struct Context: Sendable, Hashable {
        public var activatedChildCount: Int
        public var strongestChildSourceRank: Int?
        public var strongestChildProofValid: Bool?

        public init(
            activatedChildCount: Int = 0,
            strongestChildSourceRank: Int? = nil,
            strongestChildProofValid: Bool? = nil
        ) {
            self.activatedChildCount = max(0, activatedChildCount)
            self.strongestChildSourceRank = strongestChildSourceRank
            self.strongestChildProofValid = strongestChildProofValid
        }
    }

    public struct Resolution: Sendable, Hashable {
        public var internalStateKey: String
        public var classifyGrade: ExchangeThreadDiscoveryGradeMetadata.ClassifyGrade?
        public var projectedGrade: ExchangeThreadDiscoveryGradeMetadata.ProjectedGrade
        public var gradeReason: String
        public var usesMetadata: Bool

        public init(
            internalStateKey: String,
            classifyGrade: ExchangeThreadDiscoveryGradeMetadata.ClassifyGrade?,
            projectedGrade: ExchangeThreadDiscoveryGradeMetadata.ProjectedGrade,
            gradeReason: String,
            usesMetadata: Bool
        ) {
            self.internalStateKey = internalStateKey
            self.classifyGrade = classifyGrade
            self.projectedGrade = projectedGrade
            self.gradeReason = gradeReason
            self.usesMetadata = usesMetadata
        }
    }

    public static func resolve(
        thread: ExchangeThread,
        context: Context = Context()
    ) -> Resolution {
        let metadata = ExchangeThreadDiscoveryGradeMetadata.snapshot(from: thread.metadata)
        let internalStateKey = ExchangeTransition.ExchangeStateKey(thread.state).rawValue

        if let projected = metadata.projectedGrade {
            let reason = metadata.gradeReason ?? "metadata_projected_grade"
            return Resolution(
                internalStateKey: internalStateKey,
                classifyGrade: metadata.classifyGrade,
                projectedGrade: projected,
                gradeReason: reason,
                usesMetadata: true
            )
        }

        if case .matchCandidatesWeak = thread.state {
            #if DEBUG
            if thread.threadRole == .umbrellaSearch, context.activatedChildCount > 0 {
                ExchangeThreadDiscoveryGradeMetadata.logRead(
                    rootThreadID: thread.rootThreadID ?? thread.id,
                    metadata: thread.metadata,
                    usesMetadata: false,
                    activatedChildCount: context.activatedChildCount
                )
            }
            #endif
            return Resolution(
                internalStateKey: internalStateKey,
                classifyGrade: nil,
                projectedGrade: .weak,
                gradeReason: "internal_state_weak_fallback",
                usesMetadata: false
            )
        }

        if case .matchFound = thread.state {
            return Resolution(
                internalStateKey: internalStateKey,
                classifyGrade: nil,
                projectedGrade: .strong,
                gradeReason: "internal_state_match_found_fallback",
                usesMetadata: false
            )
        }

        return Resolution(
            internalStateKey: internalStateKey,
            classifyGrade: nil,
            projectedGrade: .weak,
            gradeReason: "default_fallback",
            usesMetadata: false
        )
    }

    public static func shouldUseWeakPresentation(
        thread: ExchangeThread,
        context: Context = Context()
    ) -> Bool {
        resolve(thread: thread, context: context).projectedGrade == .weak
    }

    public static func inboxStateTitle(for resolution: Resolution) -> String? {
        switch resolution.projectedGrade {
        case .strong:
            return "Found strong matches"
        case .moderate:
            return "Review matches"
        case .weak:
            return nil
        }
    }

    public static func visibleStatusLabel(for resolution: Resolution) -> String? {
        visibleStatusLabel(for: resolution.projectedGrade)
    }

    public static func visibleStatusSubtitle(for resolution: Resolution) -> String? {
        visibleStatusSubtitle(for: resolution.projectedGrade)
    }

    public static func visibleStatusLabel(for grade: ExchangeThreadDiscoveryGradeMetadata.ProjectedGrade) -> String? {
        switch grade {
        case .strong:
            return "Matches found"
        case .moderate:
            return "Review matches"
        case .weak:
            return nil
        }
    }

    public static func visibleStatusSubtitle(for grade: ExchangeThreadDiscoveryGradeMetadata.ProjectedGrade) -> String? {
        switch grade {
        case .strong:
            return "Review strong candidates before outreach."
        case .moderate:
            return "Matches need review before choosing."
        case .weak:
            return nil
        }
    }

    public static func executionBadgeTitle(for resolution: Resolution) -> String? {
        switch resolution.projectedGrade {
        case .strong:
            return "Matches Found"
        case .moderate:
            return "Review Matches"
        case .weak:
            return nil
        }
    }

    public static func executionTitle(for resolution: Resolution) -> String? {
        switch resolution.projectedGrade {
        case .strong:
            return "Found strong matches"
        case .moderate:
            return "Review matches"
        case .weak:
            return nil
        }
    }

    public static func executionSummary(for resolution: Resolution) -> String? {
        switch resolution.projectedGrade {
        case .strong:
            return "Strong candidates were surfaced and are ready for review."
        case .moderate:
            return "Viable matches were found and need your review."
        case .weak:
            return nil
        }
    }

    public static func searchResultBoundaryLine(for resolution: Resolution) -> String? {
        switch resolution.projectedGrade {
        case .strong:
            return "Strong matches ranked from your latest search."
        case .moderate:
            return "Matches ranked from your latest search — review before outreach."
        case .weak:
            return nil
        }
    }

    public static func isProofValidForProjection(
        match: ExchangeMatch?,
        thread: ExchangeThread
    ) -> Bool {
        guard let match else { return false }
        if match.strength == .weak { return false }

        let semanticTarget = ExchangeSemanticTarget.from(thread: thread)
        guard semanticTarget.minimumProofPolicy.requiresConcreteProof else {
            return true
        }

        let proof = match.semanticProof ?? .empty
        return proof.summary.satisfiesMinimumProof && !proof.summary.hasWeakRecallOnly
    }

    #if DEBUG
    public static func logDecision(
        rootThreadID: ExchangeThread.ID,
        resolution: Resolution,
        context: Context,
        strongestChildOfferID: String? = nil
    ) {
        Swift.print(
            "[UmbrellaStateDecision] " +
            "rootThreadID=\(rootThreadID.uuidString) " +
            "classifyGrade=\(resolution.classifyGrade?.rawValue ?? "nil") " +
            "strongestChild=rank:\(context.strongestChildSourceRank.map(String.init) ?? "nil") " +
            "offer:\(strongestChildOfferID ?? "nil") " +
            "proofValid=\(context.strongestChildProofValid.map { $0 ? "true" : "false" } ?? "nil") " +
            "internalState=\(resolution.internalStateKey) " +
            "projectedGrade=\(resolution.projectedGrade.rawValue) " +
            "reason=\(resolution.gradeReason) " +
            "activatedChildCount=\(context.activatedChildCount) " +
            "usesMetadata=\(resolution.usesMetadata ? "true" : "false")"
        )
    }
    #else
    public static func logDecision(
        rootThreadID: ExchangeThread.ID,
        resolution: Resolution,
        context: Context,
        strongestChildOfferID: String? = nil
    ) { }
    #endif
}
