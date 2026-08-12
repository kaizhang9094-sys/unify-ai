import XCTest
@testable import AnumCore

final class ForYouConnectionToolbarStateTests: XCTestCase {
    func testNotTrustedNotPendingReturnsConnect() {
        XCTAssertEqual(
            ForYouConnectionToolbarProjection.resolve(isTrusted: false, isPending: false),
            .connect
        )
    }

    func testPendingReturnsPendingEvenWhenLinkedThreadWouldHaveShownOpen() {
        XCTAssertEqual(
            ForYouConnectionToolbarProjection.resolve(isTrusted: false, isPending: true),
            .pending
        )
    }

    func testTrustedReturnsConnected() {
        XCTAssertEqual(
            ForYouConnectionToolbarProjection.resolve(isTrusted: true, isPending: false),
            .connected
        )
    }

    func testTrustedWinsOverPending() {
        XCTAssertEqual(
            ForYouConnectionToolbarProjection.resolve(isTrusted: true, isPending: true),
            .connected
        )
    }
}
