import XCTest

/// Federation inbox contract tests (`GET /v1/inbox/:nodeID` payloads).
///
/// Fixtures are emitted by **`unify-federation/federation-server/tests/inbox-swift-contract-fixtures.test.js`** into
/// `federation-server/tests/fixtures/inbox-swift-contract/`, then copied to
/// **`AnumAPPTests/FederationInboxContract/Fixtures/`**.
///
/// The nested DTO shapes mirror `ExchangeHTTPRelayClient`’s `InboxSyncResponseDTO` /
/// `InboxReceiptDTO` (see `ExchangeHTTPRelayClient.swift` lines ~649–690). Those production types stay
/// file-private inside `AnumCore`, so tests use an equivalent mirror for deterministic JSON decoding.
enum FederationInboxContractLens {}

extension FederationInboxContractLens {

    struct InboxSyncResponseDTO: Decodable, Sendable {
        let ok: Bool?
        let receipts: [InboxReceiptDTO]
        let nextCursor: String?
        let hasMore: Bool
        let syncedAt: String?
        let note: String?
    }

    struct InboxReceiptDTO: Decodable, Sendable {
        let receiptID: String
        let mailboxNodeID: String?
        let envelopeID: String
        let externalReference: String?
        let threadID: String?
        let senderNodeID: String
        let senderDisplayName: String?
        let senderPublicKeyID: String?
        let recipientNodeID: String
        let recipientDisplayName: String?
        let payload: InboxPayloadDTO
        let protocolVersion: String
        let status: String
        let compatibility: String?
        let compatibilityValue: String?
        let createdAt: String
        let receivedAt: String?
        let sequenceNumber: Int?
        let parentEnvelopeID: String?
        let route: RouteDTO?
        let metadata: [String: String]
    }

    struct InboxPayloadDTO: Decodable, Sendable {
        let kind: String
        let subject: String?
        let body: String
        let disclosureLevel: String?
        let intentTitle: String?
        let mode: String?
        let localThreadID: String?
    }

    struct RouteDTO: Decodable, Sendable {
        let kind: String
        let destination: String
        let relayNodeID: String?
        let mailboxID: String?
        let note: String?
    }
}

/// Mirrors `ExchangeHTTPRelayClient.syncInbox` filtering for malformed thread identifiers.
///
/// Source of truth today: UUID parse guard on `threadID`.
private enum FederationInboxSyncMapperProbe {
    static func wouldRetainReceiptLocally(_ dto: FederationInboxContractLens.InboxReceiptDTO) -> Bool {
        UUID(uuidString: dto.threadID ?? "") != nil
    }
}

final class FederationInboxRelayContractDecodeTests: XCTestCase {

    private let expectedThreadStable = "550e8400-e29b-41d4-a716-4466554400aa"

    private func fixturesDirectoryURL() throws -> URL {
        let url = URL(fileURLWithPath: "\(#filePath)", isDirectory: false)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), url.path)
        XCTAssertTrue(isDir.boolValue)
        return url
    }

    private func loadFixtureNamed(_ name: String) throws -> Data {
        let u = try fixturesDirectoryURL().appendingPathComponent("\(name).json", isDirectory: false)
        return try Data(contentsOf: u)
    }

    func test_manualSendInboxReceipt_decodesInSwift() throws {
        let data = try loadFixtureNamed("inbox_manual_send_fixture")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dto = try decoder.decode(FederationInboxContractLens.InboxSyncResponseDTO.self, from: data)
        XCTAssertEqual(dto.ok, true)
        XCTAssertEqual(dto.receipts.count, 1)

        let r = try XCTUnwrap(dto.receipts.first)

        XCTAssertEqual(r.threadID, expectedThreadStable)
        XCTAssertEqual(r.payload.body, "Manual human-approved send fixture body.")
        XCTAssertEqual(r.senderNodeID, "fixture-inbox-contract-a-sender-local")
        XCTAssertEqual(r.recipientNodeID, "fixture-inbox-contract-a-recipient-local")
        XCTAssertEqual(r.metadata["send_class"], "manual_approved")
        XCTAssertNil(r.mailboxNodeID)
        XCTAssertTrue(FederationInboxSyncMapperProbe.wouldRetainReceiptLocally(r))
    }

    func test_autonomousSendInboxReceipt_decodesInSwift() throws {
        let data = try loadFixtureNamed("inbox_autonomous_send_fixture")
        let decoder = JSONDecoder()

        let dto = try decoder.decode(FederationInboxContractLens.InboxSyncResponseDTO.self, from: data)
        XCTAssertEqual(dto.ok, true)

        let r = try XCTUnwrap(dto.receipts.first)
        XCTAssertEqual(r.payload.body, "Autonomous secretary fixture body.")
        XCTAssertEqual(r.metadata["autonomous"], "true")
        XCTAssertEqual(r.metadata["agency_mode"], "user_preauthorized")

        XCTAssertTrue(FederationInboxSyncMapperProbe.wouldRetainReceiptLocally(r))
    }

    /// Nested autonomy metadata arrives as JSON string values (Swift `[String:String]` safe).
    func test_inboxReceipt_nestedMetadata_stringified_decodesInSwift_afterServerNormalization() throws {
        let data = try loadFixtureNamed("inbox_nested_metadata_fixture")

        let dto = try JSONDecoder().decode(FederationInboxContractLens.InboxSyncResponseDTO.self, from: data)
        XCTAssertEqual(dto.ok, true)
        let r = try XCTUnwrap(dto.receipts.first)
        XCTAssertEqual(r.payload.body, "Nested metadata fixture.")

        let encodedBlob = try XCTUnwrap(r.metadata["autonomous"])
        let decoded = try JSONSerialization.jsonObject(with: Data(encodedBlob.utf8)) as? [String: String]
        XCTAssertEqual(decoded?["source"], "secretary")

        XCTAssertTrue(FederationInboxSyncMapperProbe.wouldRetainReceiptLocally(r))
    }

    func test_inboxReceipt_missingPersistedPayloadBody_emitEmptyString_decodesInSwift() throws {
        let data = try loadFixtureNamed("inbox_missing_payload_body_fixture")

        let dto = try JSONDecoder().decode(FederationInboxContractLens.InboxSyncResponseDTO.self, from: data)
        XCTAssertEqual(dto.ok, true)

        let r = try XCTUnwrap(dto.receipts.first)
        XCTAssertEqual(r.payload.kind, "message")
        XCTAssertEqual(r.payload.body, "")
        XCTAssertEqual(r.metadata["note"], "no_body_fixture")

        XCTAssertTrue(FederationInboxSyncMapperProbe.wouldRetainReceiptLocally(r))
    }

    /// LEGACY inbox JSON only: historically the relay could expose `threadID: nil` while decode still succeeded.
    /// Current federation-server rejects relay sends without a valid canonical thread UUID, so recipients no longer ingest this shape from `/v1/envelopes/send`. This case documents Swift’s client-side discard when sync mapping requires a parseable UUID.
    func test_legacyServerInboxNullThreadID_decodeThenMapperWouldDrop_documentsHistoricDropRisk() throws {
        let data = try loadFixtureNamed("inbox_legacy_null_thread_id_fixture")
        let dto = try JSONDecoder().decode(FederationInboxContractLens.InboxSyncResponseDTO.self, from: data)

        XCTAssertEqual(dto.ok, true)
        XCTAssertTrue(
            (dto.note ?? "").contains("LEGACY"),
            "Fixture note should describe historic server behavior, not current contract."
        )
        let r = try XCTUnwrap(dto.receipts.first)
        XCTAssertNil(r.threadID)

        XCTAssertEqual(r.payload.body, "Fixture with null DB thread column.")
        XCTAssertFalse(
            FederationInboxSyncMapperProbe.wouldRetainReceiptLocally(r),
            "Mirror ExchangeHTTPRelayClient.syncInbox-style guard for null-thread legacy envelopes."
        )
    }

    func test_paginationPage1_decodesHasMoreAndNextCursor() throws {
        let data = try loadFixtureNamed("inbox_pagination_page1_fixture")
        let dto = try JSONDecoder().decode(FederationInboxContractLens.InboxSyncResponseDTO.self, from: data)
        XCTAssertEqual(dto.ok, true)
        XCTAssertEqual(dto.receipts.count, 2)
        XCTAssertTrue(dto.hasMore)
        XCTAssertFalse((dto.nextCursor ?? "").isEmpty)
        XCTAssertTrue(FederationInboxSyncMapperProbe.wouldRetainReceiptLocally(try XCTUnwrap(dto.receipts.first)))
    }

    func test_paginationPage2_decodesTerminalPage() throws {
        let data = try loadFixtureNamed("inbox_pagination_page2_fixture")
        let dto = try JSONDecoder().decode(FederationInboxContractLens.InboxSyncResponseDTO.self, from: data)
        XCTAssertEqual(dto.ok, true)
        XCTAssertEqual(dto.receipts.count, 1)
        XCTAssertFalse(dto.hasMore)
        XCTAssertFalse((dto.nextCursor ?? "").isEmpty)
    }

    func test_syntheticLegacyThread_fixture_decodesAndMapperRetains() throws {
        let data = try loadFixtureNamed("inbox_synthetic_legacy_thread_fixture")
        let dto = try JSONDecoder().decode(FederationInboxContractLens.InboxSyncResponseDTO.self, from: data)
        XCTAssertEqual(dto.ok, true)
        let r = try XCTUnwrap(dto.receipts.first)
        XCTAssertEqual(r.threadID, "c2c43a34-5b80-5962-a2c0-7e9d2b24334a")
        XCTAssertEqual(r.metadata["threadResolution"], "syntheticLegacy")
        XCTAssertTrue(FederationInboxSyncMapperProbe.wouldRetainReceiptLocally(r))
    }
}
