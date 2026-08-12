import XCTest
@testable import AnumCore

final class ExchangeServiceAreaMatcherTests: XCTestCase {
    func testExactMatchAurora() {
        let requirement = ExchangeLocationRequirement(
            displayName: "Aurora",
            normalizedName: "aurora",
            kind: .namedPlace,
            strictness: .required
        )
        let areas = [ExchangeDeclaredServiceArea(displayName: "Aurora")]
        let result = ExchangeServiceAreaMatcher.match(requirement: requirement, serviceAreas: areas)
        XCTAssertEqual(result.tier, .exact)
        XCTAssertTrue(result.isCompatible)
        XCTAssertFalse(result.isHardMismatch)
    }

    func testAliasMatchGTA() {
        let requirement = ExchangeLocationRequirement(
            displayName: "GTA",
            normalizedName: "gta",
            kind: .namedPlace,
            strictness: .preferred
        )
        let areas = [
            ExchangeDeclaredServiceArea(
                displayName: "Greater Toronto Area",
                normalizedName: "greater toronto area",
                aliases: ["gta"]
            )
        ]
        let result = ExchangeServiceAreaMatcher.match(requirement: requirement, serviceAreas: areas)
        XCTAssertEqual(result.tier, .alias)
        XCTAssertTrue(result.isCompatible)
    }

    func testRequiredMismatchDownranks() {
        let requirement = ExchangeLocationRequirement(
            displayName: "Mississauga",
            normalizedName: "mississauga",
            kind: .namedPlace,
            strictness: .required
        )
        let areas = [ExchangeDeclaredServiceArea(displayName: "Aurora")]
        let result = ExchangeServiceAreaMatcher.match(requirement: requirement, serviceAreas: areas)
        XCTAssertEqual(result.tier, .none)
        XCTAssertFalse(result.isCompatible)
        XCTAssertTrue(result.isHardMismatch)
    }

    func testRemoteAccepted() {
        let requirement = ExchangeLocationRequirement(
            displayName: "Online",
            normalizedName: "online",
            kind: .remote,
            strictness: .notLocal
        )
        let areas = [ExchangeDeclaredServiceArea(displayName: "Online")]
        let result = ExchangeServiceAreaMatcher.match(requirement: requirement, serviceAreas: areas)
        XCTAssertEqual(result.tier, .remoteAccepted)
        XCTAssertTrue(result.isCompatible)
    }

    func testNearMeRequiresClarification() {
        let requirement = ExchangeLocationRequirement(
            displayName: "near me",
            kind: .nearMe,
            strictness: .requiresClarification
        )
        let result = ExchangeServiceAreaMatcher.match(
            requirement: requirement,
            serviceAreas: [ExchangeDeclaredServiceArea(displayName: "Toronto")]
        )
        XCTAssertEqual(result.tier, .requiresClarification)
    }

    func testLegacyRegionTagHydration() {
        var offer = ExchangeOffer(
            id: "o1",
            nodeID: "n1",
            title: "Roofing",
            regionTags: ["Mississauga", "Online"]
        )
        XCTAssertTrue(offer.serviceAreas.isEmpty)
        ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&offer)
        XCTAssertEqual(offer.serviceAreas.count, 2)
        XCTAssertEqual(offer.regionTags, ["Mississauga", "Online"])
    }

    func testNormalizationStripsOntarioSuffix() {
        let normalized = ExchangeLocationNormalization.normalize("Aurora, Ontario", stripRegionalSuffixes: true)
        XCTAssertEqual(normalized, "aurora")
    }
}
