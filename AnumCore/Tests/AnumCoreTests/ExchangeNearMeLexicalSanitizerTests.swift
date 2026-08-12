import XCTest
@testable import AnumCore

final class ExchangeNearMeLexicalSanitizerTests: XCTestCase {
    func testFilterInterpretationTagsRemovesNearMeAndMe() {
        let filtered = ExchangeNearMeLexicalSanitizer.filterInterpretationTags([
            "roofer",
            "near me",
            "me",
            "find roofer near me"
        ])
        XCTAssertTrue(filtered.contains("roofer"))
        XCTAssertTrue(filtered.contains("find"))
        XCTAssertFalse(filtered.contains("me"))
        XCTAssertFalse(filtered.contains("near me"))
    }

    func testLexicalSearchTermsEmptyWhenSpatialNearMeResolved() {
        let requirement = ExchangeLocationRequirement(
            kind: .nearMe,
            strictness: .preferred,
            spatial: ExchangeH3GoldenVectors.goldenCoordinateCoverage()
        )
        XCTAssertTrue(requirement.hasResolvedSpatialNearMe)
        XCTAssertTrue(requirement.lexicalSearchTerms.isEmpty)
    }
}

private extension ExchangeH3GoldenVectors {
    static func goldenCoordinateCoverage() -> ExchangeSpatialCoverage {
        ExchangeH3CoverageBuilder.buildCoverage(
            center: ExchangeCoordinate(
                latitude: latitudeDegrees,
                longitude: longitudeDegrees
            ),
            radiusMeters: ExchangeH3CoverageBuilder.defaultRequesterRadiusMeters,
            source: .currentDevice
        )
    }
}
