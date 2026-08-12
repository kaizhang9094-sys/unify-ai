import XCTest
@testable import AnumCore

#if DEBUG

final class ExchangeE2EGateTests: XCTestCase {
    func testAppLaunchTriggerDoesNotStartE2E() {
        XCTAssertFalse(ExchangeE2EGate.shouldRun(trigger: .appLaunch))
    }

    func testViewAppearTriggerDoesNotStartE2E() {
        XCTAssertFalse(ExchangeE2EGate.shouldRun(trigger: .viewAppear))
    }

    func testForegroundResumeTriggerDoesNotStartE2E() {
        XCTAssertFalse(ExchangeE2EGate.shouldRun(trigger: .foregroundResume))
    }

    func testManualButtonTriggerStartsE2E() {
        XCTAssertTrue(ExchangeE2EGate.shouldRun(trigger: .manualButton(source: "test.button")))
    }

    func testDiscoveryOnlyModeSkipsManualSecondHalfCapture() {
        XCTAssertFalse(ExchangeE2EMode.discoveryOnly.includesManualSecondHalfCapture)
        XCTAssertFalse(ExchangeE2EMode.retrievalOnly.includesManualSecondHalfCapture)
    }

    func testDiscoveryAndSecondHalfModeIncludesManualSecondHalfCapture() {
        XCTAssertTrue(ExchangeE2EMode.discoveryAndSecondHalf.includesManualSecondHalfCapture)
        XCTAssertTrue(ExchangeE2EMode.discoveryAndSecondHalf.includesDiscoveryAutoSecondHalf)
    }

    func testDiscoveryOnlySuppressesFacadeAutoSecondHalfDuringActiveRun() async {
        await ExchangeE2EActiveRun.withMode(.discoveryOnly) {
            XCTAssertTrue(ExchangeE2EActiveRun.shouldSuppressDiscoveryAutoSecondHalf)
            XCTAssertEqual(ExchangeE2EActiveRun.currentMode, .discoveryOnly)
        }
        XCTAssertNil(ExchangeE2EActiveRun.currentMode)
    }

    func testDiscoveryAndSecondHalfDoesNotSuppressFacadeAutoSecondHalfDuringActiveRun() async {
        await ExchangeE2EActiveRun.withMode(.discoveryAndSecondHalf) {
            XCTAssertFalse(ExchangeE2EActiveRun.shouldSuppressDiscoveryAutoSecondHalf)
        }
    }

    func testSkippedSecondHalfSnapshotIsInert() {
        let skipped = MultilingualE2ESecondHalfSnapshot.skipped
        XCTAssertTrue(skipped.missingFacts.isEmpty)
        XCTAssertFalse(skipped.compareSucceeded)
        XCTAssertTrue(skipped.forbiddenMissingFactsTriggered.isEmpty)
    }
}

#endif
