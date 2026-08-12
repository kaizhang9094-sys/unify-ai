import XCTest
@testable import AnumCore

final class ExchangePhase4IParityVerificationTests: XCTestCase {
    func testPhase4IParityVerificationImmediate() async {
        let rows = await ExchangePhase4IParityVerification.runAll(timingLabel: "immediate")
        XCTAssertEqual(rows.count, 5)
    }

    func testPhase4IParityVerificationAfterGateWait() async {
        try? await Task.sleep(nanoseconds: 30_000_000_000)
        let rows = await ExchangePhase4IParityVerification.runAll(timingLabel: "after30sGateWait")
        XCTAssertEqual(rows.count, 5)
    }
}
