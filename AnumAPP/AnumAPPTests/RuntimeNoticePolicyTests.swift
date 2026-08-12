import XCTest
@testable import AnumAPP

final class RuntimeNoticePolicyTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private var defaultsSuiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "RuntimeNoticePolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    private func makePolicy() -> RuntimeNoticePolicy {
        RuntimeNoticePolicy(now: { [unowned self] in self.now }, defaults: defaults)
    }

    func testDispatchSourceWarning_repeated_threeTimes_logOnlyNeverBanner() {
        var policy = makePolicy()
        for _ in 0..<3 {
            let eval = policy.evaluate(RuntimeNoticeRequest(source: .dispatchSourceWarning))
            XCTAssertEqual(eval.decision, .logOnly)
            XCTAssertNil(eval.userMessage)
        }
    }

    func testIOSMemoryWarning_repeatedWithin10Minutes_firstShowsSecondSuppresses() {
        var policy = makePolicy()
        let first = policy.evaluate(RuntimeNoticeRequest(source: .iOSMemoryWarning))
        XCTAssertEqual(first.decision, .show)
        policy.recordShown(first, at: now)
        now = now.addingTimeInterval(60)

        let second = policy.evaluate(RuntimeNoticeRequest(source: .iOSMemoryWarning))
        XCTAssertEqual(second.decision, .suppress)
        XCTAssertEqual(second.reason, "criticalThrottled10m")
    }

    func testDispatchSourceNormal_logOnlyNoBanner() {
        var policy = makePolicy()
        let eval = policy.evaluate(RuntimeNoticeRequest(source: .dispatchSourceNormal))
        XCTAssertEqual(eval.decision, .logOnly)
        XCTAssertEqual(eval.reason, "dispatchNormalClearsFlagOnly")
    }

    func testForegroundResume_noBanner() {
        var policy = makePolicy()
        policy.recordShown(
            policy.evaluate(
                RuntimeNoticeRequest(source: .diskSoftWarning, messageKind: .diskSpace, customMessage: "low disk")
            ),
            at: now
        )
        let eval = policy.noteForegroundResume()
        XCTAssertEqual(eval.decision, .logOnly)
        XCTAssertEqual(eval.reason, "foregroundResumeNoBanner")
    }

    func testAutoHideDoesNotAllowImmediateRepeat_cautionStillSuppressed() {
        var policy = makePolicy()
        let first = policy.evaluate(
            RuntimeNoticeRequest(source: .diskSoftWarning, messageKind: .diskSpace, customMessage: "low disk")
        )
        XCTAssertEqual(first.decision, .show)
        policy.recordShown(first, at: now)
        // Simulates auto-hide (no recordDismissed)
        let second = policy.evaluate(
            RuntimeNoticeRequest(source: .diskSoftWarning, messageKind: .diskSpace, customMessage: "low disk")
        )
        XCTAssertEqual(second.decision, .suppress)
        XCTAssertEqual(second.reason, "alreadyShownThisSession")
    }

    func testDismissCaution_suppressesFor24h() {
        var policy = makePolicy()
        policy.recordDismissed(severity: .caution, at: now)
        let eval = policy.evaluate(
            RuntimeNoticeRequest(source: .diskSoftWarning, messageKind: .diskSpace, customMessage: "low disk")
        )
        XCTAssertEqual(eval.decision, .suppress)
        XCTAssertEqual(eval.reason, "dismissedWithin24h")
    }

    func testDiskSoftWarning_sharesCautionBudgetWithModelTooLarge() {
        var policy = makePolicy()
        let disk = policy.evaluate(
            RuntimeNoticeRequest(source: .diskSoftWarning, messageKind: .diskSpace, customMessage: "disk msg")
        )
        XCTAssertEqual(disk.decision, .show)
        policy.recordShown(disk, at: now)

        let model = policy.evaluate(
            RuntimeNoticeRequest(source: .modelLoadEstimate, messageKind: .modelTooLarge)
        )
        XCTAssertEqual(RuntimeNoticePolicy.severity(for: .modelLoadEstimate), .info)
        XCTAssertEqual(model.decision, .logOnly)
    }

    func testModelPrewarmAndLoaded_logOnly() {
        var policy = makePolicy()
        XCTAssertEqual(policy.evaluate(RuntimeNoticeRequest(source: .modelPrewarm)).decision, .logOnly)
        XCTAssertEqual(policy.evaluate(RuntimeNoticeRequest(source: .modelLoaded)).decision, .logOnly)
    }

    func testCritical_after10Minutes_showsAgain() {
        var policy = makePolicy()
        let first = policy.evaluate(RuntimeNoticeRequest(source: .iOSMemoryWarning))
        policy.recordShown(first, at: now)
        now = now.addingTimeInterval(RuntimeNoticePolicy.criticalThrottleInterval + 1)
        let second = policy.evaluate(RuntimeNoticeRequest(source: .iOSMemoryWarning))
        XCTAssertEqual(second.decision, .show)
    }

    func testNoSlowdownCopyInDefaultMessages() {
        XCTAssertFalse(RuntimeNoticePolicy.memoryPressureCriticalMessage.lowercased().contains("if you notice"))
        XCTAssertFalse(RuntimeNoticePolicy.modelTooLargeCautionMessage.lowercased().contains("if you notice slowdown"))
    }
}
