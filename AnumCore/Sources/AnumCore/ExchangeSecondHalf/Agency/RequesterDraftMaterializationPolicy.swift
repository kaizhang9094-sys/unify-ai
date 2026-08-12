import Foundation

/// Decides whether requester outbound drafts should run expensive LLM body materialization.
///
/// Template/display drafts may already exist from coordinator + executor layers.
/// This policy gates only the LLM rewrite step in `materializeAgencyAuthoredOutboundDraftIfNeeded`.
public struct RequesterDraftMaterializationPolicy: Sendable, Equatable {
    public enum Decision: Equatable, Sendable {
        case composeForAutonomousSend
        case composeForUserReview
        case useExistingTemplateOnly
        case suggestOnlyNoDraft
        case blocked
    }

    public enum Trigger: String, Sendable, Equatable {
        /// Background second-half after discovery, inbox refresh, relay, etc.
        case automaticSecondHalf
        /// Explicit user action such as "let secretary handle".
        case userExplicit
    }

    public var decision: Decision
    public var reason: String
    public var canAutoSend: Bool
    public var shouldRunLLMCompose: Bool
    public var shouldPersistVisibleDraft: Bool

    public init(
        decision: Decision,
        reason: String,
        canAutoSend: Bool,
        shouldRunLLMCompose: Bool,
        shouldPersistVisibleDraft: Bool
    ) {
        self.decision = decision
        self.reason = reason
        self.canAutoSend = canAutoSend
        self.shouldRunLLMCompose = shouldRunLLMCompose
        self.shouldPersistVisibleDraft = shouldPersistVisibleDraft
    }

    public static func trigger(fromSecondHalfSource source: String) -> Trigger {
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("user_let_secretary_handle") {
            return .userExplicit
        }
        return .automaticSecondHalf
    }

    public static func evaluate(
        userAuthority: ExchangeAutonomousUserAuthority,
        trigger: Trigger,
        boundaryRequiresHumanApproval: Bool,
        moveNeedsApproval: Bool
    ) -> RequesterDraftMaterializationPolicy {
        if boundaryRequiresHumanApproval || moveNeedsApproval {
            return RequesterDraftMaterializationPolicy(
                decision: .composeForUserReview,
                reason: "boundary_or_move_requires_approval",
                canAutoSend: false,
                shouldRunLLMCompose: true,
                shouldPersistVisibleDraft: true
            )
        }

        switch userAuthority {
        case .manualOnly:
            if trigger == .automaticSecondHalf {
                return RequesterDraftMaterializationPolicy(
                    decision: .useExistingTemplateOnly,
                    reason: "manual_only_automatic_second_half",
                    canAutoSend: false,
                    shouldRunLLMCompose: false,
                    shouldPersistVisibleDraft: false
                )
            }
            return RequesterDraftMaterializationPolicy(
                decision: .composeForUserReview,
                reason: "manual_only_user_explicit",
                canAutoSend: false,
                shouldRunLLMCompose: true,
                shouldPersistVisibleDraft: true
            )

        case .draftOnly:
            return RequesterDraftMaterializationPolicy(
                decision: .composeForUserReview,
                reason: "draft_only_prepare_for_review",
                canAutoSend: false,
                shouldRunLLMCompose: true,
                shouldPersistVisibleDraft: true
            )

        case .routineAutoRespond, .fullWithinBoundaries:
            return RequesterDraftMaterializationPolicy(
                decision: .composeForAutonomousSend,
                reason: "autonomous_send_mode_allowed",
                canAutoSend: true,
                shouldRunLLMCompose: true,
                shouldPersistVisibleDraft: true
            )

        case .missing, .invalid:
            if trigger == .automaticSecondHalf {
                return RequesterDraftMaterializationPolicy(
                    decision: .useExistingTemplateOnly,
                    reason: "missing_or_invalid_authority_automatic",
                    canAutoSend: false,
                    shouldRunLLMCompose: false,
                    shouldPersistVisibleDraft: false
                )
            }
            return RequesterDraftMaterializationPolicy(
                decision: .composeForUserReview,
                reason: "missing_or_invalid_authority_user_explicit",
                canAutoSend: false,
                shouldRunLLMCompose: true,
                shouldPersistVisibleDraft: true
            )
        }
    }
}
