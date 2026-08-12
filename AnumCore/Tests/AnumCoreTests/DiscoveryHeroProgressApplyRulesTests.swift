import XCTest
@testable import AnumCore

enum DiscoveryHeroProgressApplyRules {
    static func shouldApply(
        updateGeneration: UInt64,
        currentGeneration: UInt64,
        isActive: Bool
    ) -> Bool {
        updateGeneration == currentGeneration && isActive
    }

    static func shouldAdvanceStage(
        current: DiscoveryHeroProgressUpdate.Stage,
        incoming: DiscoveryHeroProgressUpdate.Stage
    ) -> Bool {
        current != incoming
    }
}

final class DiscoveryHeroProgressApplyRulesTests: XCTestCase {
    func testStaleGenerationUpdateIsIgnored() {
        XCTAssertFalse(
            DiscoveryHeroProgressApplyRules.shouldApply(
                updateGeneration: 3,
                currentGeneration: 4,
                isActive: true
            )
        )
    }

    func testSameGenerationAdvancesStage() {
        XCTAssertTrue(
            DiscoveryHeroProgressApplyRules.shouldAdvanceStage(
                current: .understandingRequest,
                incoming: .searchingPublicNodes
            )
        )
    }

    func testSameStageRepeatIsIdempotent() {
        XCTAssertFalse(
            DiscoveryHeroProgressApplyRules.shouldAdvanceStage(
                current: .searchingPublicNodes,
                incoming: .searchingPublicNodes
            )
        )
    }
}
