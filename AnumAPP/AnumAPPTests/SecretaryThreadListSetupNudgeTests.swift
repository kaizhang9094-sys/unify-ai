import XCTest
import AnumCore
@testable import AnumAPP

/// Eligibility-only coverage for `SecretaryThreadListSetupNudge` (UI card on Exchange thread list).
@MainActor
final class SecretaryThreadListSetupNudgeTests: XCTestCase {
    private let emptyWorkspace = ExchangeModels.SellerWorkspaceSummary(
        publicProfile: nil,
        offers: [],
        activeOfferCount: 0,
        draftOfferCount: 0,
        pausedOfferCount: 0,
        archivedOfferCount: 0,
        needsPublicationAttention: false,
        statusLine: "Fixture"
    )

    func test_eligible_whenThreadsExist_autoFollowUpsOff_notDismissed() {
        XCTAssertTrue(
            SecretaryThreadListSetupNudge.shouldShowCard(
                hasLoadedInbox: true,
                threadRowCount: 1,
                isDismissed: false,
                allowSafeAutoFollowUps: false,
                secretaryConstitutionText: "Custom style note.",
                sellerWorkspace: nil
            )
        )
    }

    func test_hidden_whenDismissed() {
        XCTAssertFalse(
            SecretaryThreadListSetupNudge.shouldShowCard(
                hasLoadedInbox: true,
                threadRowCount: 2,
                isDismissed: true,
                allowSafeAutoFollowUps: false,
                secretaryConstitutionText: "",
                sellerWorkspace: nil
            )
        )
    }

    func test_hidden_whenAutoFollowUpsOn_andStyleFilled_andWorkspaceUnset() {
        XCTAssertFalse(
            SecretaryThreadListSetupNudge.shouldShowCard(
                hasLoadedInbox: true,
                threadRowCount: 1,
                isDismissed: false,
                allowSafeAutoFollowUps: true,
                secretaryConstitutionText: "Tone: concise.",
                sellerWorkspace: nil
            )
        )
    }

    func test_hidden_whenNoThreads() {
        XCTAssertFalse(
            SecretaryThreadListSetupNudge.shouldShowCard(
                hasLoadedInbox: true,
                threadRowCount: 0,
                isDismissed: false,
                allowSafeAutoFollowUps: false,
                secretaryConstitutionText: "",
                sellerWorkspace: nil
            )
        )
    }

    func test_hidden_beforeInboxLoaded() {
        XCTAssertFalse(
            SecretaryThreadListSetupNudge.shouldShowCard(
                hasLoadedInbox: false,
                threadRowCount: 1,
                isDismissed: false,
                allowSafeAutoFollowUps: false,
                secretaryConstitutionText: "",
                sellerWorkspace: nil
            )
        )
    }

    func test_eligible_whenStyleEmpty_evenIfAutoSendModeOn() {
        XCTAssertTrue(
            SecretaryThreadListSetupNudge.shouldShowCard(
                hasLoadedInbox: true,
                threadRowCount: 1,
                isDismissed: false,
                allowSafeAutoFollowUps: true,
                secretaryConstitutionText: "   ",
                sellerWorkspace: nil
            )
        )
    }

    func test_eligible_whenWorkspaceHasNoActiveOffers() {
        XCTAssertTrue(
            SecretaryThreadListSetupNudge.shouldShowCard(
                hasLoadedInbox: true,
                threadRowCount: 1,
                isDismissed: false,
                allowSafeAutoFollowUps: true,
                secretaryConstitutionText: "Custom.",
                sellerWorkspace: emptyWorkspace
            )
        )
    }

    func test_dismissedUserDefaultsKey_isStable() {
        XCTAssertEqual(
            SecretaryThreadListSetupNudge.dismissedUserDefaultsKey,
            "secretary.threadListSetupNudge.dismissed"
        )
    }
}
