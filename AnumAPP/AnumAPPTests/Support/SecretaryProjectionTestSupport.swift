import Foundation
import AnumCore

/// Tiny deterministic builders for `SecretaryProjectionEngine` tests only.
enum SecretaryProjectionTestSupport {
    /// Fixed instant for fixtures (no `Date()` drift in assertions).
    static let fixtureDate = Date(timeIntervalSince1970: 1_720_000_000)

    static func minimalSecondHalfDisplay(
        threadID: UUID = UUID(),
        placement: ExchangeSecondHalfUIAdapter.Placement,
        title: String = "Second-half title",
        heroTitle: String = "Hero headline",
        summary: String = "Second-half summary.",
        boundaryReason: String = "Human approval required before any outbound send.",
        externalEffectLine: String = "Private draft only; nothing has been sent externally.",
        needsHumanAttention: Bool = false,
        agencyPhase: ExchangeSecondHalfUIAdapter.AgencyPhase? = .unknown,
        agencyPhaseTitle: String? = nil,
        agencyPhaseDetail: String? = nil,
        hasDecisionPacket: Bool = false,
        hasDraft: Bool = false,
        canRunAutonomously: Bool = false,
        isTerminal: Bool = false,
        statusBlocking: Bool = false,
        statusRole: String = "Requester"
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel {
        ExchangeSecondHalfUIAdapter.DisplayModel(
            threadID: threadID,
            placement: placement,
            title: title,
            subtitle: "Fixture subtitle",
            summary: summary,
            postureSummary: "Fixture posture",
            recommendation: "Fixture recommendation",
            stateLabel: "Fixture state",
            roleLabel: "Fixture role",
            hero: ExchangeSecondHalfUIAdapter.Hero(
                eyebrow: "Fixture",
                title: heroTitle,
                subtitle: "Hero subtitle",
                statusLine: "Fixture status line"
            ),
            status: ExchangeSecondHalfUIAdapter.Status(
                state: "Coordination",
                role: statusRole,
                quality: "Fixture quality",
                readiness: "Fixture readiness",
                isBlocking: statusBlocking,
                isAutonomous: canRunAutonomously,
                isDecisionReady: hasDecisionPacket,
                isTerminal: isTerminal
            ),
            operatingContext: ExchangeSecondHalfUIAdapter.OperatingContextSection(
                role: "Requester",
                postureSummary: "Fixture operating posture",
                readiness: "Ready enough",
                urgency: "Normal",
                trust: "Fixture trust",
                priceSensitivity: "Unknown",
                flexibility: "Moderate"
            ),
            boundary: ExchangeSecondHalfUIAdapter.BoundarySection(
                kind: "approval",
                reason: boundaryReason,
                requiresHumanApproval: placement == .needsApproval || placement == .needsInput,
                allowsAutonomousDrafting: true,
                allowsAutonomousSending: false,
                externalEffectLine: externalEffectLine
            ),
            needsHumanAttention: needsHumanAttention,
            canRunAutonomously: canRunAutonomously,
            agencyPhase: agencyPhase,
            agencyPhaseTitle: agencyPhaseTitle,
            agencyPhaseDetail: agencyPhaseDetail,
            hasDecisionPacket: hasDecisionPacket,
            hasProviderReception: false,
            hasRequesterReview: false,
            hasDraft: hasDraft,
            isTerminal: isTerminal
        )
    }

    /// `hasDecisionPacket` plus a populated `decision` section (projection invariant for prominence).
    static func secondHalfDisplayWithAlignedDecisionPacket(
        threadID: UUID = UUID(),
        placement: ExchangeSecondHalfUIAdapter.Placement = .decisionReady
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel {
        ExchangeSecondHalfUIAdapter.DisplayModel(
            threadID: threadID,
            placement: placement,
            title: "Second-half title",
            subtitle: "Fixture subtitle",
            summary: "Second-half summary.",
            postureSummary: "Fixture posture",
            recommendation: "Fixture recommendation",
            stateLabel: "Fixture state",
            roleLabel: "Fixture role",
            hero: ExchangeSecondHalfUIAdapter.Hero(
                eyebrow: "Fixture",
                title: "Hero headline",
                subtitle: "Hero subtitle",
                statusLine: "Fixture status line"
            ),
            status: ExchangeSecondHalfUIAdapter.Status(
                state: "Coordination",
                role: "Requester",
                quality: "Fixture quality",
                readiness: "Fixture readiness",
                isBlocking: false,
                isAutonomous: false,
                isDecisionReady: true,
                isTerminal: false
            ),
            decision: ExchangeSecondHalfUIAdapter.DecisionSection(
                summary: "Enough detail to compare this path.",
                clarifiedFacts: ["Published lesson rate is $60/hr in Aurora."],
                whatChanged: [],
                unresolvedIssues: [],
                recommendation: "Ask for availability or move on.",
                tradeoffs: [],
                needsUserJudgment: true,
                needsCommitmentApproval: false
            ),
            operatingContext: ExchangeSecondHalfUIAdapter.OperatingContextSection(
                role: "Requester",
                postureSummary: "Fixture operating posture",
                readiness: "Ready enough",
                urgency: "Normal",
                trust: "Fixture trust",
                priceSensitivity: "Unknown",
                flexibility: "Moderate"
            ),
            boundary: ExchangeSecondHalfUIAdapter.BoundarySection(
                kind: "approval",
                reason: "Human approval required before any outbound send.",
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                allowsAutonomousSending: false,
                externalEffectLine: "Private draft only; nothing has been sent externally."
            ),
            needsHumanAttention: false,
            canRunAutonomously: false,
            agencyPhase: .unknown,
            agencyPhaseTitle: nil,
            agencyPhaseDetail: nil,
            hasDecisionPacket: true,
            hasProviderReception: false,
            hasRequesterReview: false,
            hasDraft: false,
            isTerminal: false
        )
    }
}
