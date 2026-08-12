import XCTest
@testable import AnumCore

final class UnifyDataLifecycleCatalogTests: XCTestCase {

    func testCompanionKeysDoNotMatchSecretaryWipePrefixes() {
        for key in CompanionWipeUserDefaultsKeys.all {
            XCTAssertFalse(
                SecretaryWipeUserDefaultsCatalog.shouldRemoveKey(key),
                "Companion key must not be classified as Secretary: \(key)"
            )
        }
    }

    func testSecretaryCatalogMatchesExpectedPrefixes() {
        XCTAssertTrue(SecretaryWipeUserDefaultsCatalog.shouldRemoveKey("secretary.discovery.mode"))
        XCTAssertTrue(SecretaryWipeUserDefaultsCatalog.shouldRemoveKey("exchange.contactContext.v1"))
        XCTAssertTrue(SecretaryWipeUserDefaultsCatalog.shouldRemoveKey("forYou.standingInterest.v2.node-abc"))
        XCTAssertTrue(SecretaryWipeUserDefaultsCatalog.shouldRemoveKey("DirectChatPrefixCachedReplayForceFullNext"))

        XCTAssertFalse(SecretaryWipeUserDefaultsCatalog.shouldRemoveKey("companionName"))
        XCTAssertFalse(SecretaryWipeUserDefaultsCatalog.shouldRemoveKey("hasOnboarded"))
        XCTAssertFalse(SecretaryWipeUserDefaultsCatalog.shouldRemoveKey("Anum.identity.selectedId"))
    }

    func testExchangeDatabaseURLTripleIncludesWALAndSHM() {
        let base = URL(fileURLWithPath: "/tmp/Anum", isDirectory: true)
        let urls = UnifyDataLifecycleFiles.exchangeDatabaseURLs(baseDirectory: base)
        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls[0].lastPathComponent, "exchange.sqlite")
        XCTAssertTrue(urls[1].path.hasSuffix("-wal"))
        XCTAssertTrue(urls[2].path.hasSuffix("-shm"))
    }
}
