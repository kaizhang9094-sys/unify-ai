import XCTest
import AnumCore

final class ExchangeRelayDeliveryStatusMappingTests: XCTestCase {

    func test_mapServerStatus_acceptedAndQueued() {
        XCTAssertEqual(ExchangeRelayDeliveryStatusMapping.mapServerStatus("accepted"), .accepted)
        XCTAssertEqual(ExchangeRelayDeliveryStatusMapping.mapServerStatus("  ACCEPTED  "), .accepted)
        XCTAssertEqual(ExchangeRelayDeliveryStatusMapping.mapServerStatus("queued"), .accepted)
    }

    func test_mapServerStatus_delivered() {
        XCTAssertEqual(ExchangeRelayDeliveryStatusMapping.mapServerStatus("delivered"), .delivered)
    }

    func test_mapServerStatus_failedAndRejected() {
        XCTAssertEqual(ExchangeRelayDeliveryStatusMapping.mapServerStatus("failed"), .failed)
        XCTAssertEqual(ExchangeRelayDeliveryStatusMapping.mapServerStatus("rejected"), .failed)
    }

    func test_mapServerStatus_unknownVocabulary() {
        XCTAssertEqual(ExchangeRelayDeliveryStatusMapping.mapServerStatus(""), .unknown)
        XCTAssertEqual(ExchangeRelayDeliveryStatusMapping.mapServerStatus("in-flight"), .unknown)
    }

    func test_percentEncodedPathSegment_encodesReservedCharacters() {
        let encoded = ExchangeRelayDeliveryStatusMapping.percentEncodedPathSegmentForStatusReference("a/b c")
        XCTAssertTrue(encoded.contains("%2F"), encoded)
        XCTAssertTrue(encoded.contains("%20"), encoded)
    }

    func test_percentEncodedPathSegment_leavesUnreservedAlone() {
        let id = "550e8400-e29b-41d4-a716-446655440099"
        XCTAssertEqual(
            ExchangeRelayDeliveryStatusMapping.percentEncodedPathSegmentForStatusReference(id),
            id
        )
    }

    func test_parseServerISO8601Date_fractionalAndBasic() throws {
        let withFrac = "2026-06-01T12:00:00.123Z"
        let d1 = try XCTUnwrap(ExchangeRelayDeliveryStatusMapping.parseServerISO8601Date(withFrac))
        XCTAssertEqual(Calendar.current.component(.year, from: d1), 2026)

        let basic = "2026-06-01T12:00:00Z"
        let d2 = try XCTUnwrap(ExchangeRelayDeliveryStatusMapping.parseServerISO8601Date(basic))
        XCTAssertEqual(Calendar.current.component(.month, from: d2), 6)
    }

    func test_parseCheckedAt_nilOrEmptyUsesNowBounded() {
        let t0 = ExchangeRelayDeliveryStatusMapping.parseCheckedAt(nil)
        let t1 = ExchangeRelayDeliveryStatusMapping.parseCheckedAt("")
        let t2 = ExchangeRelayDeliveryStatusMapping.parseCheckedAt("   ")
        XCTAssertLessThan(abs(t0.timeIntervalSinceNow), 5.0)
        XCTAssertLessThan(abs(t1.timeIntervalSinceNow), 5.0)
        XCTAssertLessThan(abs(t2.timeIntervalSinceNow), 5.0)
    }

    func test_parseCheckedAt_invalidFallsBackToNow() {
        let t = ExchangeRelayDeliveryStatusMapping.parseCheckedAt("not-a-date")
        XCTAssertLessThan(abs(t.timeIntervalSinceNow), 5.0)
    }
}
