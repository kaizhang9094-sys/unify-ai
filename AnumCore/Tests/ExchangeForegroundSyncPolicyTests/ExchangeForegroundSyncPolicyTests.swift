import XCTest
@testable import AnumCore

final class ExchangeForegroundSyncPolicyTests: XCTestCase {
    private let policy = ExchangeForegroundSyncPolicy()

    func testStableSeedIsDeterministic() {
        let first = ExchangeForegroundSyncPolicy.stableSeed(from: "loadtest-node-a")
        let second = ExchangeForegroundSyncPolicy.stableSeed(from: "loadtest-node-a")
        XCTAssertEqual(first, second)
    }

    func testJitteredPollIntervalStaysWithinBoundsForActiveConversation() {
        let seed = ExchangeForegroundSyncPolicy.stableSeed(from: "node-jitter-active")
        let interval = policy.jitteredPollIntervalSeconds(
            routeKind: .activeConversation,
            pushDeliveryEffective: true,
            recentPushSyncSucceeded: false,
            stableSeed: seed
        )
        XCTAssertGreaterThanOrEqual(interval, 15)
        XCTAssertLessThanOrEqual(interval, 24)
    }

    func testJitteredPollIntervalStaysWithinBoundsForPassiveWorkspace() {
        let seed = ExchangeForegroundSyncPolicy.stableSeed(from: "node-jitter-passive")
        let interval = policy.jitteredPollIntervalSeconds(
            routeKind: .passiveWorkspace,
            pushDeliveryEffective: false,
            recentPushSyncSucceeded: false,
            stableSeed: seed
        )
        XCTAssertGreaterThanOrEqual(interval, 100)
        XCTAssertLessThanOrEqual(interval, 180)
    }

    func testAutomaticForegroundSyncGraceIsLongerThanPollGrace() {
        XCTAssertGreaterThan(
            policy.automaticForegroundSyncGraceInterval,
            policy.recentSyncGraceInterval
        )
        XCTAssertEqual(policy.automaticForegroundSyncGraceInterval, 45, accuracy: 0.1)
    }

    func testShouldSkipAutomaticForegroundSyncWithinGraceWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let withinAutomaticOnly = now.addingTimeInterval(-35)
        XCTAssertTrue(
            policy.shouldSkipAutomaticForegroundSync(lastCompletedAt: withinAutomaticOnly, now: now)
        )
        XCTAssertFalse(
            policy.shouldSkipPollDueToRecentSync(lastCompletedAt: withinAutomaticOnly, now: now)
        )
    }

    func testJitteredInitialDelayIsAtLeastOneSecond() {
        let seed = ExchangeForegroundSyncPolicy.stableSeed(from: "node-initial-delay")
        XCTAssertGreaterThanOrEqual(policy.jitteredInitialDelaySeconds(stableSeed: seed), 1)
    }
}
