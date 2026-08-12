import XCTest
import AnumCore

final class FederationHTTPErrorMessageTests: XCTestCase {

    func test_userFacingReason_extractsErrorField() {
        let data = #"{"ok":false,"error":"Not allowed"}"#.data(using: .utf8)!
        let raw = String(data: data, encoding: .utf8)!
        XCTAssertEqual(
            FederationHTTPErrorMessage.userFacingReason(data: data, fallback: raw),
            "Not allowed"
        )
    }

    func test_userFacingReason_ignoresWhitespaceAroundError() {
        let data = #"{"ok":false,"error":"  trim me  "}"#.data(using: .utf8)!
        let raw = String(data: data, encoding: .utf8)!
        XCTAssertEqual(
            FederationHTTPErrorMessage.userFacingReason(data: data, fallback: raw),
            "trim me"
        )
    }

    func test_userFacingReason_fallsBackWhenMessageFieldOnly() {
        let data = #"{"message":"use raw"}"#.data(using: .utf8)!
        let raw = String(data: data, encoding: .utf8)!
        XCTAssertEqual(
            FederationHTTPErrorMessage.userFacingReason(data: data, fallback: raw),
            raw
        )
    }

    func test_userFacingReason_fallsBackOnNonJSON() {
        let data = Data("not json".utf8)
        let raw = "not json"
        XCTAssertEqual(
            FederationHTTPErrorMessage.userFacingReason(data: data, fallback: raw),
            raw
        )
    }

    func test_userFacingReason_emptyDataUsesFallback() {
        XCTAssertEqual(
            FederationHTTPErrorMessage.userFacingReason(data: Data(), fallback: "HTTP 500"),
            "HTTP 500"
        )
    }

    func test_userFacingReason_emptyErrorStringUsesFallback() {
        let data = #"{"ok":false,"error":""}"#.data(using: .utf8)!
        let raw = String(data: data, encoding: .utf8)!
        XCTAssertEqual(
            FederationHTTPErrorMessage.userFacingReason(data: data, fallback: raw),
            raw
        )
    }

    func test_FederationJSONErrorEnvelope_decodesOptionalCode() throws {
        let data = #"{"ok":false,"code":"x","error":"y"}"#.data(using: .utf8)!
        let env = try JSONDecoder().decode(FederationJSONErrorEnvelope.self, from: data)
        XCTAssertEqual(env.code, "x")
        XCTAssertEqual(env.error, "y")
        XCTAssertEqual(env.ok, false)
    }
}
