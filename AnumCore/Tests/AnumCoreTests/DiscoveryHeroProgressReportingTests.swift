import XCTest
@testable import AnumCore

final class DiscoveryHeroProgressReportingTests: XCTestCase {
    func testNotifierReportsSearchingThenRankingInOrder() {
        let reporter = MockDiscoveryHeroProgressReporter()
        let context = DiscoveryHeroProgressContext(generation: 7, originalText: "Find a camping friend")
        let threadID = UUID()

        DiscoveryHeroProgressNotifier.report(
            reporter,
            context: context,
            stage: .searchingPublicNodes,
            threadID: threadID
        )
        DiscoveryHeroProgressNotifier.report(
            reporter,
            context: context,
            stage: .rankingResults,
            threadID: threadID
        )

        XCTAssertEqual(reporter.updates.count, 2)
        XCTAssertEqual(reporter.updates[0].stage, .searchingPublicNodes)
        XCTAssertEqual(reporter.updates[1].stage, .rankingResults)
        XCTAssertEqual(reporter.updates[0].generation, 7)
        XCTAssertEqual(reporter.updates[0].activeThreadID, threadID)
    }

    func testNotifierSkipsWhenContextMissing() {
        let reporter = MockDiscoveryHeroProgressReporter()

        DiscoveryHeroProgressNotifier.report(
            reporter,
            context: nil,
            stage: .searchingPublicNodes,
            threadID: nil
        )

        XCTAssertTrue(reporter.updates.isEmpty)
    }
}

private final class MockDiscoveryHeroProgressReporter: DiscoveryHeroProgressReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [DiscoveryHeroProgressUpdate] = []

    var updates: [DiscoveryHeroProgressUpdate] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func reportDiscoveryHeroProgress(_ update: DiscoveryHeroProgressUpdate) {
        lock.lock()
        stored.append(update)
        lock.unlock()
    }
}
