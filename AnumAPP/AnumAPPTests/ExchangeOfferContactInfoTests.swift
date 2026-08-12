import XCTest
import SQLite3
import AnumCore

final class ExchangeOfferContactInfoTests: XCTestCase {
    func test_contactInfoCodableRoundtrip_preservesStructuredFields() throws {
        let contact = ExchangeOffer.ContactInfo(
            contactName: "Kai",
            businessName: "Unify Studio",
            email: "hello@example.com",
            phone: "+1 555 0100",
            website: "example.com",
            preferredContactMethod: .email,
            availabilityNote: "Weekdays after 10am",
            serviceAddressOrArea: "Toronto + GTA"
        )
        let offer = ExchangeOffer(
            id: "offer-contact-codable",
            nodeID: "node-contact-codable",
            publicProfileID: "pp-contact-codable",
            title: "Offer",
            status: .active,
            visibility: .publicDiscoverable,
            contactInfo: contact
        )

        let encoded = try JSONEncoder().encode(offer)
        let decoded = try JSONDecoder().decode(ExchangeOffer.self, from: encoded)

        XCTAssertEqual(decoded.contactInfo?.contactName, "Kai")
        XCTAssertEqual(decoded.contactInfo?.businessName, "Unify Studio")
        XCTAssertEqual(decoded.contactInfo?.email, "hello@example.com")
        XCTAssertEqual(decoded.contactInfo?.preferredContactMethod, .email)
        XCTAssertEqual(decoded.contactInfo?.website, "https://example.com")
    }

    func test_sqliteSaveLoad_roundtrip_withAndWithoutContactInfo() async throws {
        let store = try makeStore()

        let withoutContact = ExchangeOffer(
            id: "offer-no-contact",
            nodeID: "node-no-contact",
            publicProfileID: nil,
            title: "Without contact",
            status: .active,
            visibility: .publicDiscoverable
        )
        try await store.saveOffer(withoutContact)
        let loadedWithout = try await store.fetchOffer(id: withoutContact.id)
        XCTAssertNotNil(loadedWithout)
        XCTAssertNil(loadedWithout?.contactInfo)

        let withContact = ExchangeOffer(
            id: "offer-with-contact",
            nodeID: "node-with-contact",
            publicProfileID: nil,
            title: "With contact",
            status: .active,
            visibility: .publicDiscoverable,
            contactInfo: .init(
                contactName: "Seller",
                email: "sales@example.com",
                preferredContactMethod: .email
            )
        )
        try await store.saveOffer(withContact)
        let loadedWith = try await store.fetchOffer(id: withContact.id)
        XCTAssertEqual(loadedWith?.contactInfo?.email, "sales@example.com")
        XCTAssertEqual(loadedWith?.contactInfo?.preferredContactMethod, .email)
    }

    func test_contactInfoJsonColumn_onlyPopulatedWhenNonEmpty() async throws {
        let dbURL = try makeTempDatabaseURL()
        let store = try ExchangeSQLiteStore(databaseURL: dbURL)

        let emptyContactOffer = ExchangeOffer(
            id: "offer-contact-empty",
            nodeID: "node-contact-empty",
            publicProfileID: nil,
            title: "Empty contact",
            status: .active,
            visibility: .publicDiscoverable,
            contactInfo: .init()
        )
        try await store.saveOffer(emptyContactOffer)

        let fullContactOffer = ExchangeOffer(
            id: "offer-contact-full",
            nodeID: "node-contact-full",
            publicProfileID: nil,
            title: "Full contact",
            status: .active,
            visibility: .publicDiscoverable,
            contactInfo: .init(email: "person@example.com")
        )
        try await store.saveOffer(fullContactOffer)

        let emptyJSON = try readContactInfoJSON(dbURL: dbURL, offerID: emptyContactOffer.id)
        let fullJSON = try readContactInfoJSON(dbURL: dbURL, offerID: fullContactOffer.id)

        XCTAssertNil(emptyJSON)
        XCTAssertNotNil(fullJSON)
        XCTAssertTrue(fullJSON?.contains("person@example.com") == true)
    }

    func test_publishedPayload_includesContactInfo_onlyForOutwardVisibleOffers() {
        let service = ExchangeDefaultSellerSurfaceService()
        let profile = ExchangePublicNodeProfile(
            id: "pp-publish-contact",
            nodeID: "node-publish-contact",
            displayName: "Publish Contact Profile"
        )
        let visible = ExchangeOffer(
            id: "offer-visible-contact",
            nodeID: "node-publish-contact",
            publicProfileID: profile.id,
            title: "Visible",
            status: .active,
            visibility: .publicDiscoverable,
            contactInfo: .init(email: "visible@example.com")
        )
        let hidden = ExchangeOffer(
            id: "offer-hidden-contact",
            nodeID: "node-publish-contact",
            publicProfileID: profile.id,
            title: "Hidden",
            status: .active,
            visibility: .hidden,
            contactInfo: .init(email: "hidden@example.com")
        )
        let draft = ExchangeOffer(
            id: "offer-draft-contact",
            nodeID: "node-publish-contact",
            publicProfileID: profile.id,
            title: "Draft",
            status: .draft,
            visibility: .publicDiscoverable,
            contactInfo: .init(email: "draft@example.com")
        )

        let payload = service.buildPublishedPayload(
            ownerNodeID: "node-publish-contact",
            ownerDisplayName: "Owner",
            publicProfile: profile,
            offers: [visible, hidden, draft],
            publicationState: nil,
            now: Date()
        )

        XCTAssertEqual(payload.offers.count, 1)
        XCTAssertEqual(payload.offers.first?.id, "offer-visible-contact")
        XCTAssertEqual(payload.offers.first?.contactInfo?.email, "visible@example.com")
    }

    private func makeStore() throws -> ExchangeSQLiteStore {
        let dbURL = try makeTempDatabaseURL()
        return try ExchangeSQLiteStore(databaseURL: dbURL)
    }

    private func makeTempDatabaseURL() throws -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exchange-offer-contact-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp.appendingPathComponent("db-\(UUID().uuidString).sqlite")
    }

    private func readContactInfoJSON(dbURL: URL, offerID: String) throws -> String? {
        var db: OpaquePointer?
        defer {
            if db != nil {
                sqlite3_close(db)
            }
        }

        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "SQLite", code: 1)
        }

        let sql = "SELECT contact_info_json FROM exchange_offers WHERE id = ?1 LIMIT 1;"
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLite", code: 2)
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, offerID, -1, transient)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        guard let textPtr = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: textPtr)
    }
}
