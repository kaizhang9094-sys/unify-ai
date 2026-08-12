import Foundation

/// Top-level second-half policy config.
///
/// Centralizes budgets, limits, and threshold decisions so engines do not
/// hardcode product behavior.
public struct ExchangeSecondHalfPolicy: Codable, Hashable, Sendable {
    /// Maximum autonomous clarification rounds before surfacing or escalating.
    public var clarificationRoundLimit: Int

    /// Maximum routine auto-answer passes before the system must involve the user.
    public var autoAnswerLimit: Int

    /// Maximum total follow-up attempts for a thread.
    public var followUpLimit: Int

    /// How long a thread may sit without meaningful change before it is stale.
    public var staleThreshold: TimeInterval

    /// Whether a promising qualification may be surfaced before it is fully decision-ready.
    public var allowSurfaceWhenPromising: Bool

    /// Minimum quality tier required to surface now.
    public var minimumSurfaceQualityTier: ExchangeOpportunityQualityTier

    /// Minimum readiness level required before the system should frame the thread
    /// as decision-ready.
    public var decisionReadinessThreshold: ExchangeReadinessLevel

    /// Whether commitment-bearing actions must always require approval.
    public var requireApprovalForCommitmentBearingActions: Bool

    /// Whether obligation-bearing and sensitive disclosure actions also require approval.
    public var requireApprovalForSensitiveActions: Bool

    public var autonomy: ExchangeAutonomyPolicy
    public var followUp: ExchangeFollowUpPolicy
    public var providerIntake: ExchangeProviderIntakePolicy

    public init(
        clarificationRoundLimit: Int = 1,
        autoAnswerLimit: Int = 1,
        followUpLimit: Int = 2,
        staleThreshold: TimeInterval = 60 * 60 * 24 * 3, // 3 days
        allowSurfaceWhenPromising: Bool = true,
        minimumSurfaceQualityTier: ExchangeOpportunityQualityTier = .promising,
        decisionReadinessThreshold: ExchangeReadinessLevel = .decisionReady,
        requireApprovalForCommitmentBearingActions: Bool = true,
        requireApprovalForSensitiveActions: Bool = true,
        autonomy: ExchangeAutonomyPolicy = .default,
        followUp: ExchangeFollowUpPolicy = .default,
        providerIntake: ExchangeProviderIntakePolicy = .default
    ) {
        self.clarificationRoundLimit = max(0, clarificationRoundLimit)
        self.autoAnswerLimit = max(0, autoAnswerLimit)
        self.followUpLimit = max(0, followUpLimit)
        self.staleThreshold = max(0, staleThreshold)
        self.allowSurfaceWhenPromising = allowSurfaceWhenPromising
        self.minimumSurfaceQualityTier = minimumSurfaceQualityTier
        self.decisionReadinessThreshold = decisionReadinessThreshold
        self.requireApprovalForCommitmentBearingActions = requireApprovalForCommitmentBearingActions
        self.requireApprovalForSensitiveActions = requireApprovalForSensitiveActions
        self.autonomy = autonomy
        self.followUp = followUp
        self.providerIntake = providerIntake
    }
}

public extension ExchangeSecondHalfPolicy {
    static let `default` = ExchangeSecondHalfPolicy()

    func maySurface(
        qualification: ExchangeOpportunityQualification
    ) -> Bool {
        if qualification.isDecisionReady {
            return true
        }

        switch minimumSurfaceQualityTier {
        case .weak:
            return true
        case .promising:
            return allowSurfaceWhenPromising
                ? qualification.qualityTier == .promising || qualification.qualityTier == .strong || qualification.qualityTier == .decisionReady
                : qualification.qualityTier == .strong || qualification.qualityTier == .decisionReady
        case .strong:
            return qualification.qualityTier == .strong || qualification.qualityTier == .decisionReady
        case .decisionReady:
            return qualification.qualityTier == .decisionReady
        }
    }

    func hasExceededClarificationLimit(_ rounds: Int) -> Bool {
        rounds >= clarificationRoundLimit
    }

    func hasExceededAutoAnswerLimit(_ rounds: Int) -> Bool {
        rounds >= autoAnswerLimit
    }

    func hasExceededFollowUpLimit(_ attempts: Int) -> Bool {
        attempts >= followUpLimit
    }

    func requiresApproval(for boundary: ExchangeCommitmentBoundary) -> Bool {
        switch boundary.kind {
        case .safe:
            return false
        case .sensitiveDisclosure, .policyException:
            return requireApprovalForSensitiveActions || boundary.requiresHumanApproval
        case .obligationBearing,
             .commitmentBearing,
             .customPricing,
             .scheduleCommitment,
             .legalCommercialCommitment:
            return requireApprovalForCommitmentBearingActions || boundary.requiresHumanApproval
        }
    }

    func isDecisionReady(
        stance: ExchangeThreadStance
    ) -> Bool {
        switch stance.readinessLevel {
        case .decisionReady, .commitmentReady:
            return true
        case .weak, .incomplete, .promising:
            return false
        }
    }
}
