import XCTest
@testable import AnumCore

final class ExchangeBootstrapFederationURLTests: XCTestCase {
    private let productionURL = URL(string: "https://unify-federation-server-production.up.railway.app")!

    func testLiveFederationBaseURLIsProductionRailway() {
        XCTAssertEqual(ExchangeBootstrap.liveFederationBaseURL, productionURL)
    }

    func testDebugWithNoOverrideUsesProductionDefault() {
        let resolved = ExchangeBootstrap.resolveDebugFederationBaseURLConfiguration(
            environment: [:],
            launchArguments: [],
            userDefaultsString: nil
        )
        XCTAssertEqual(resolved.url, productionURL)
        XCTAssertEqual(resolved.source, .productionDefault)
    }

    func testDebugWithEmptyEnvironmentUsesProductionDefault() {
        let resolved = ExchangeBootstrap.resolveDebugFederationBaseURLConfiguration(
            environment: [ExchangeBootstrap.debugFederationBaseURLEnvironmentKey: "   "],
            launchArguments: [],
            userDefaultsString: nil
        )
        XCTAssertEqual(resolved.url, productionURL)
        XCTAssertEqual(resolved.source, .productionDefault)
    }

    func testDebugWithValidEnvironmentUsesOverride() {
        let staging = "https://staging.example.com"
        let resolved = ExchangeBootstrap.resolveDebugFederationBaseURLConfiguration(
            environment: [ExchangeBootstrap.debugFederationBaseURLEnvironmentKey: staging],
            launchArguments: [],
            userDefaultsString: nil
        )
        XCTAssertEqual(resolved.url.absoluteString, staging)
        XCTAssertEqual(resolved.source, .debugEnvironment)
    }

    func testDebugLaunchArgumentPrecedesEnvironment() {
        let resolved = ExchangeBootstrap.resolveDebugFederationBaseURLConfiguration(
            environment: [ExchangeBootstrap.debugFederationBaseURLEnvironmentKey: "https://env.example.com"],
            launchArguments: [
                "\(ExchangeBootstrap.debugFederationBaseURLLaunchArgumentKey)=https://launch.example.com"
            ],
            userDefaultsString: "https://defaults.example.com"
        )
        XCTAssertEqual(resolved.url.absoluteString, "https://launch.example.com")
        XCTAssertEqual(resolved.source, .debugLaunchArgument)
    }

    func testInvalidEnvironmentFallsBackToProductionDefault() {
        let resolved = ExchangeBootstrap.resolveDebugFederationBaseURLConfiguration(
            environment: [ExchangeBootstrap.debugFederationBaseURLEnvironmentKey: "not-a-url"],
            launchArguments: [],
            userDefaultsString: nil
        )
        XCTAssertEqual(resolved.url, productionURL)
        XCTAssertEqual(resolved.source, .productionDefault)
    }
}
