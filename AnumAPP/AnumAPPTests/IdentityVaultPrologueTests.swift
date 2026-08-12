import XCTest
import InnerSelfCore
@testable import AnumAPP

@MainActor
final class IdentityVaultPrologueTests: XCTestCase {

    private let ud = UserDefaults.standard

    private let keysTouched: [String] = [
        "hasOnboarded",
        "companionName",
        "companionPrologue",
        "onboarding.relationshipRole",
        "onboarding.userAge",
        "onboarding.isAdult"
    ]

    override func setUp() async throws {
        try await super.setUp()
        for k in keysTouched {
            ud.removeObject(forKey: k)
        }
        IdentityVault.shared.invalidateScaffoldCache()
    }

    override func tearDown() async throws {
        for k in keysTouched {
            ud.removeObject(forKey: k)
        }
        IdentityVault.shared.invalidateScaffoldCache()
        try await super.tearDown()
    }

    func test_nonEmptyCompanionPrologue_suppressesRawRelationshipRole() {
        ud.set(true, forKey: "hasOnboarded")
        ud.set("treeHoleListener", forKey: "onboarding.relationshipRole")
        ud.set("UnitTest", forKey: "companionName")
        ud.set(25, forKey: "onboarding.userAge")
        ud.set("You are my steady north star.", forKey: "companionPrologue")

        IdentityVault.shared.invalidateScaffoldCache()
        let scaffold = IdentityVault.shared.scaffoldSystemText()

        XCTAssertFalse(scaffold.contains("treeHoleListener"), scaffold)
        XCTAssertFalse(scaffold.contains("relationship_role=treeHoleListener"))
        XCTAssertTrue(scaffold.contains("You are my steady north star."))
        XCTAssertTrue(scaffold.contains("## PROLOGUE (stable companion identity)"))
        XCTAssertTrue(scaffold.contains("onboarding_scope=preferences only"))
    }

    func test_emptyPrologue_humanizesTreeHoleRelationshipRole() {
        ud.removeObject(forKey: "companionPrologue")
        ud.set(true, forKey: "hasOnboarded")
        ud.set("treeHoleListener", forKey: "onboarding.relationshipRole")
        ud.set("UnitTest", forKey: "companionName")
        ud.set(25, forKey: "onboarding.userAge")

        IdentityVault.shared.invalidateScaffoldCache()
        let scaffold = IdentityVault.shared.scaffoldSystemText()

        XCTAssertTrue(scaffold.contains("relationship_role=calm listener"), scaffold)
        XCTAssertFalse(scaffold.contains("treeHoleListener"), scaffold)
    }

    func test_companionWipeKeys_includeOnboardingRelationshipRole() {
        XCTAssertTrue(CompanionWipeUserDefaultsKeys.all.contains("onboarding.relationshipRole"))
        XCTAssertTrue(CompanionWipeUserDefaultsKeys.all.contains("companionPrologue"))
    }

    func test_wipeKeyList_removesOnboardingRelationshipRole() {
        ud.set("treeHoleListener", forKey: "onboarding.relationshipRole")
        for key in CompanionWipeUserDefaultsKeys.all {
            ud.removeObject(forKey: key)
        }
        XCTAssertNil(ud.string(forKey: "onboarding.relationshipRole"))
    }
}
