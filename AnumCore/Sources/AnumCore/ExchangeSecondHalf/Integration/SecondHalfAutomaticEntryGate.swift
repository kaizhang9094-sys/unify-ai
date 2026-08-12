import Foundation

/// Gates expensive automatic second-half evaluation before coordinator/facade work runs.
///
/// This does **not** introduce a separate user setting. It reads the same inputs as:
/// - `ExchangeAutonomousSendPolicy.currentThreadAutonomyAuthority()` (`UserDefaults` key `secretary.threadAutonomy.mode`)
/// - `RequesterDraftMaterializationPolicy.trigger(fromSecondHalfSource:)` for automatic vs user-explicit classification
/// - `RequesterDraftMaterializationPolicy.evaluate(...)` for whether automatic second-half work is allowed
///
/// Send-bridge `disabledByUserSetting` is enforced later via `ExchangeAutonomousSendPolicy.evaluateRequesterOutbound`
/// when `!userAuthority.allowsAutonomousSend`. This gate only moves the automatic **evaluation** skip earlier so
/// `ExchangeSecondHalfFacade.evaluateThread` does not run for modes that already block automatic second-half work
/// (e.g. `manualOnly` on `submit.childCoordination`).
public enum SecondHalfAutomaticEntryGate {
    public struct Decision: Sendable, Equatable {
        public var shouldRun: Bool
        public var enabled: Bool
        public var reason: String

        public init(shouldRun: Bool, enabled: Bool, reason: String) {
            self.shouldRun = shouldRun
            self.enabled = enabled
            self.reason = reason
        }
    }

    public static func evaluate(source: String) -> Decision {
        let trigger = RequesterDraftMaterializationPolicy.trigger(fromSecondHalfSource: source)
        let authority = ExchangeAutonomousSendPolicy.currentThreadAutonomyAuthority()

        if trigger == .userExplicit {
            return Decision(
                shouldRun: true,
                enabled: true,
                reason: "user_explicit"
            )
        }

        let materialization = RequesterDraftMaterializationPolicy.evaluate(
            userAuthority: authority,
            trigger: .automaticSecondHalf,
            boundaryRequiresHumanApproval: false,
            moveNeedsApproval: false
        )

        if shouldSkipAutomaticSecondHalf(materialization: materialization) {
            return Decision(
                shouldRun: false,
                enabled: false,
                reason: "disabledByUserSetting"
            )
        }

        return Decision(
            shouldRun: true,
            enabled: true,
            reason: materialization.reason
        )
    }

    /// Mirrors automatic paths that `RequesterDraftMaterializationPolicy` already treats as no-op
    /// (`shouldRunLLMCompose == false` with manual-only / unset-authority reasons).
    private static func shouldSkipAutomaticSecondHalf(
        materialization: RequesterDraftMaterializationPolicy
    ) -> Bool {
        guard !materialization.shouldRunLLMCompose else { return false }
        switch materialization.reason {
        case "manual_only_automatic_second_half",
             "missing_or_invalid_authority_automatic":
            return true
        default:
            return false
        }
    }

    #if DEBUG
    public static func logGate(
        source: String,
        decision: Decision,
        eligible: Bool
    ) {
        Swift.print(
            "[SecondHalfEntryGate] " +
            "source=\(source) " +
            "enabled=\(decision.enabled) " +
            "eligible=\(eligible) " +
            "action=\(decision.shouldRun ? "run" : "skip") " +
            "reason=\(decision.reason)"
        )
    }
    #endif
}
