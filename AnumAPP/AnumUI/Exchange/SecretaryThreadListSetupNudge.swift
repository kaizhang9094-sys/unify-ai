import Foundation
import AnumCore

/// Eligibility for the first-time "set up Discovery / follow-ups" card on the Exchange thread list (UI-only).
enum SecretaryThreadListSetupNudge {
    /// Persisted when the user taps "Not now".
    static let dismissedUserDefaultsKey = "secretary.threadListSetupNudge.dismissed"

    /// Show the nudge when the user has threads to manage but discovery/follow-up setup looks incomplete.
    static func shouldShowCard(
        hasLoadedInbox: Bool,
        threadRowCount: Int,
        isDismissed: Bool,
        allowSafeAutoFollowUps: Bool,
        secretaryConstitutionText: String,
        sellerWorkspace: ExchangeModels.SellerWorkspaceSummary?
    ) -> Bool {
        guard hasLoadedInbox, threadRowCount > 0, !isDismissed else { return false }

        let constitutionEmpty = secretaryConstitutionText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        if !allowSafeAutoFollowUps { return true }
        if constitutionEmpty { return true }

        if let workspace = sellerWorkspace {
            if workspace.publicProfile == nil { return true }
            if workspace.activeOfferCount == 0 { return true }
        }

        return false
    }
}
