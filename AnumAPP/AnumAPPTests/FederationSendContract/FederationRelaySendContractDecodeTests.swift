import XCTest

/// Decodes combined send/inbox snapshots from `unify-federation/federation-server/tests/send-swift-contract.test.js`
/// (mirrored under `FederationSendContract/Fixtures/`).
///
/// `SendResponseLens` mirrors `ExchangeHTTPRelayClient.SendResponse` (`ExchangeHTTPRelayClient.swift` ~643–647).
/// Inbox shape reuses `FederationInboxContractLens` from `FederationInboxRelayContractDecodeTests.swift`.
private struct SendResponseLens: Decodable, Sendable {
    let ok: Bool
    let envelopeID: String
    let status: String
}

private struct CombinedSendContractSnapshot: Decodable, Sendable {
    let label: String
    let sendResponse: SendResponseLens
    let inboxResponse: FederationInboxContractLens.InboxSyncResponseDTO
}

private struct CombinedIdempotentSendSnapshot: Decodable, Sendable {
    let label: String
    let firstSendResponse: SendResponseLens
    let secondSendResponse: SendResponseLens
    let inboxResponse: FederationInboxContractLens.InboxSyncResponseDTO
}

final class FederationRelaySendContractDecodeTests: XCTestCase {

    private let expectedThread = "550e8400-e29b-41d4-a716-446655440099"

    private func fixturesDirectoryURL() throws -> URL {
        let url = URL(fileURLWithPath: "\(#filePath)", isDirectory: false)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), url.path)
        XCTAssertTrue(isDir.boolValue)
        return url
    }

    private func loadSnapshot(_ name: String) throws -> Data {
        let u = try fixturesDirectoryURL().appendingPathComponent("\(name).json", isDirectory: false)
        return try Data(contentsOf: u)
    }

    func test_A_manualSend_sendResponseAndInbox_decodeMatchesFixture() throws {
        let data = try loadSnapshot("combined_send_contract_manual")
        let snap = try JSONDecoder().decode(CombinedSendContractSnapshot.self, from: data)

        XCTAssertEqual(snap.label, "manual_user_approved_shape")
        XCTAssertTrue(snap.sendResponse.ok)
        XCTAssertEqual(snap.sendResponse.envelopeID, "env-send-contract-manual-001")
        XCTAssertEqual(snap.sendResponse.status, "accepted")

        XCTAssertEqual(snap.inboxResponse.ok, true)
        let r = try XCTUnwrap(snap.inboxResponse.receipts.first)
        XCTAssertEqual(r.envelopeID, "env-send-contract-manual-001")
        XCTAssertEqual(r.threadID, expectedThread)
        XCTAssertEqual(r.payload.body, "Queued via userApproved permit path analogue.")
        XCTAssertEqual(r.payload.mode, "conversation")
        XCTAssertFalse(r.receiptID.isEmpty)
    }

    func test_B_requesterAutonomousSend_sendResponseAndInbox_decodeMatchesFixture() throws {
        let data = try loadSnapshot("combined_send_contract_requester_autonomous")
        let snap = try JSONDecoder().decode(CombinedSendContractSnapshot.self, from: data)

        XCTAssertEqual(snap.label, "requester_autonomous_shape")
        XCTAssertTrue(snap.sendResponse.ok)
        XCTAssertEqual(snap.sendResponse.envelopeID, "env-send-contract-req-auto-002")

        let r = try XCTUnwrap(snap.inboxResponse.receipts.first)
        XCTAssertEqual(r.payload.mode, "secretary")
        XCTAssertEqual(r.payload.intentTitle, "Autonomous planner suggestion")
    }

    func test_C_providerAutonomousMetadataProbe_sendResponseAndInbox_decodeMatchesFixture() throws {
        let data = try loadSnapshot("combined_send_contract_provider_autonomous")
        let snap = try JSONDecoder().decode(CombinedSendContractSnapshot.self, from: data)

        XCTAssertEqual(snap.label, "provider_auto_response_metadata_probe")
        let r = try XCTUnwrap(snap.inboxResponse.receipts.first)
        XCTAssertEqual(r.metadata["second_half_generated"], "true")
        XCTAssertEqual(r.metadata["second_half_auto_response"], "true")
        XCTAssertEqual(r.metadata["autonomy_numeric_probe"], "1")
    }

    func test_D_idempotentRetry_sendResponsesMatch_inboxSingleReceipt() throws {
        let data = try loadSnapshot("combined_send_contract_idempotent_retry")
        let snap = try JSONDecoder().decode(CombinedIdempotentSendSnapshot.self, from: data)

        XCTAssertEqual(snap.label, "idempotent_same_envelope_twice")
        XCTAssertEqual(snap.firstSendResponse.envelopeID, snap.secondSendResponse.envelopeID)
        XCTAssertTrue(snap.firstSendResponse.ok && snap.secondSendResponse.ok)

        let matches = snap.inboxResponse.receipts.filter { $0.envelopeID == "env-send-contract-idempotent-shared-007" }
        XCTAssertEqual(matches.count, 1)
    }

    func test_E_sendResponse_extraKeysIgnored_decodesLikeProductionDTO() throws {
        let data = try loadSnapshot("combined_send_contract_manual")
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let send = try XCTUnwrap(obj?["sendResponse"] as? [String: Any])
        XCTAssertNotNil(send["acceptedAt"])
        let sendData = try JSONSerialization.data(withJSONObject: send)
        let decoded = try JSONDecoder().decode(SendResponseLens.self, from: sendData)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.status, "accepted")
    }

    func test_F_inboxFromEachScenario_decodesFederationInboxContractShape() throws {
        for name in [
            "combined_send_contract_manual",
            "combined_send_contract_requester_autonomous",
            "combined_send_contract_provider_autonomous",
            "combined_send_contract_idempotent_retry"
        ] {
            let data = try loadSnapshot(name)
            if name.contains("idempotent") {
                _ = try JSONDecoder().decode(CombinedIdempotentSendSnapshot.self, from: data)
            } else {
                _ = try JSONDecoder().decode(CombinedSendContractSnapshot.self, from: data)
            }
        }
    }
}
