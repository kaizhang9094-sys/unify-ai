import XCTest
import AnumCore
@testable import AnumAPP

@MainActor
final class ExchangeAutonomousFollowUpSettingsTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "ExchangeAutonomousFollowUpSettingsTests.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_bootstrapThreadAutonomy_writesManualOnlyWhenKeyMissing() {
        let defaults = isolatedDefaults()
        defaults.removeObject(forKey: AppServices.safeAutoFollowUpsUserDefaultsKey)

        AppServices.bootstrapThreadAutonomyModeIfNeeded(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: AppServices.safeAutoFollowUpsUserDefaultsKey),
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue
        )
    }

    func test_bootstrapThreadAutonomy_preservesRoutineAutoRespond() {
        let defaults = isolatedDefaults()
        let raw = ExchangeModels.ExchangeThreadAutonomyMode.routineAutoRespond.rawValue
        defaults.set(raw, forKey: AppServices.safeAutoFollowUpsUserDefaultsKey)

        AppServices.bootstrapThreadAutonomyModeIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppServices.safeAutoFollowUpsUserDefaultsKey), raw)
    }

    func test_bootstrapThreadAutonomy_preservesFullWithinBoundaries() {
        let defaults = isolatedDefaults()
        let raw = ExchangeModels.ExchangeThreadAutonomyMode.fullWithinBoundaries.rawValue
        defaults.set(raw, forKey: AppServices.safeAutoFollowUpsUserDefaultsKey)

        AppServices.bootstrapThreadAutonomyModeIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppServices.safeAutoFollowUpsUserDefaultsKey), raw)
    }

    func test_bootstrapThreadAutonomy_preservesExplicitManualOnly() {
        let defaults = isolatedDefaults()
        let raw = ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue
        defaults.set(raw, forKey: AppServices.safeAutoFollowUpsUserDefaultsKey)

        AppServices.bootstrapThreadAutonomyModeIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppServices.safeAutoFollowUpsUserDefaultsKey), raw)
    }

    func test_bootstrapThreadAutonomy_normalizesInvalidValueToManualOnly() {
        let defaults = isolatedDefaults()
        defaults.set("not-a-real-mode", forKey: AppServices.safeAutoFollowUpsUserDefaultsKey)

        AppServices.bootstrapThreadAutonomyModeIfNeeded(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: AppServices.safeAutoFollowUpsUserDefaultsKey),
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue
        )
    }

    func test_policyReturnsManualOnlyAfterBootstrap_notMissing() {
        let defaults = isolatedDefaults()
        defaults.removeObject(forKey: AppServices.safeAutoFollowUpsUserDefaultsKey)

        AppServices.bootstrapThreadAutonomyModeIfNeeded(defaults: defaults)

        XCTAssertEqual(
            ExchangeAutonomousSendPolicy.currentThreadAutonomyAuthority(defaults: defaults),
            .manualOnly
        )
    }

    func test_manualOnlyStillDisablesSafeAutoFollowUps_matchesToggleOff() {
        XCTAssertFalse(AppServices.modeAllowsSafeAutoFollowUps(.manualOnly))
        let defaults = isolatedDefaults()
        defaults.set(
            ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue,
            forKey: AppServices.safeAutoFollowUpsUserDefaultsKey
        )
        XCTAssertEqual(
            ExchangeAutonomousSendPolicy.currentThreadAutonomyAuthority(defaults: defaults),
            .manualOnly
        )
    }

    func test_safeAutoFollowUps_reusesCanonicalThreadAutonomyKey() {
        XCTAssertEqual(AppServices.safeAutoFollowUpsUserDefaultsKey, "secretary.threadAutonomy.mode")
    }

    func test_modeAllowsSafeAutoFollowUps_matchesGateAuthority() {
        XCTAssertFalse(AppServices.modeAllowsSafeAutoFollowUps(.manualOnly))
        XCTAssertFalse(AppServices.modeAllowsSafeAutoFollowUps(.draftOnly))
        XCTAssertTrue(AppServices.modeAllowsSafeAutoFollowUps(.routineAutoRespond))
        XCTAssertTrue(AppServices.modeAllowsSafeAutoFollowUps(.fullWithinBoundaries))
    }

    func test_settingsCopy_isPlainLanguageAndNoInternalGateTerms() {
        let title = SecretaryStyleSettingsView.safeAutoFollowUpsTitle.lowercased()
        let description = SecretaryStyleSettingsView.safeAutoFollowUpsDescription.lowercased()

        XCTAssertEqual(title, "allow safe auto-follow-ups")
        XCTAssertTrue(description.contains("low-risk clarification"))
        XCTAssertTrue(description.contains("still asks for your approval"))
        XCTAssertFalse(description.contains("autonomydisposition"))
        XCTAssertFalse(description.contains("queue permit"))
        XCTAssertFalse(description.contains("policy engine"))
        XCTAssertFalse(description.contains("state machine"))
    }
}
