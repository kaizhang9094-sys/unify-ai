import XCTest
@testable import AnumCore

/// Signing contract: `ExchangeFederationRequestSigner.canonicalPath(for:)` must match the path+query
/// string Fastify uses (`request.raw?.url || request.url`) for signed GETs (e.g. inbox sync with cursor).
final class ExchangeFederationRequestSignerTests: XCTestCase {

    func test_canonicalPath_inboxGET_cursorThenLimit_matchesNodeURLSearchParamsOrder() throws {
        let signer = ExchangeFederationRequestSigner()
        let nodeID = "fixture-sign-compat-node"
        let cursor = "eyJ2IjoxLCJyZWNlaXZlZEF0IjoiMjAyNi0wMS0wMVQwMDowMDowMC4wMDBaIiwicmVjZWlwdElEIjoiYiJ9"

        var components = URLComponents()
        components.scheme = "https"
        components.host = "federation.test"
        components.path = "/v1/inbox/\(nodeID)"
        components.queryItems = [
            URLQueryItem(name: "cursor", value: cursor),
            URLQueryItem(name: "limit", value: "1")
        ]

        let url = try XCTUnwrap(components.url)
        let canonical = try signer.canonicalPath(for: url)

        let recomposed = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let encodedPath = try XCTUnwrap(recomposed?.percentEncodedPath)
        let encodedQuery = try XCTUnwrap(recomposed?.percentEncodedQuery)
        XCTAssertEqual(canonical, "\(encodedPath)?\(encodedQuery)", "canonicalPath matches percentEncodedPath + ? + percentEncodedQuery")

        let cursorRange = try XCTUnwrap(canonical.range(of: "cursor="))
        let limitRange = try XCTUnwrap(canonical.range(of: "limit="))
        XCTAssertLessThan(cursorRange.lowerBound, limitRange.lowerBound, "Relay inbox URL builds cursor before limit")

        // Golden from Node: `new URLSearchParams(); append cursor; append limit` on same path/cursor.
        let golden =
            "/v1/inbox/fixture-sign-compat-node?cursor=eyJ2IjoxLCJyZWNlaXZlZEF0IjoiMjAyNi0wMS0wMVQwMDowMDowMC4wMDBaIiwicmVjZWlwdElEIjoiYiJ9&limit=1"
        XCTAssertEqual(
            canonical,
            golden,
            "Swift canonicalPath must match Node signing string used in federation-server inbox GET tests"
        )
    }

    /// `+` in a query value is left literal in `URLComponents.percentEncodedQuery` on Apple platforms
    /// (not `%2B`). Inbox cursors are base64url, which avoids `+` and `/`, so production signing stays ASCII-stable.
    func test_canonicalPath_plusInQueryValue_matchesPercentEncodedQuery() throws {
        let signer = ExchangeFederationRequestSigner()
        var components = URLComponents()
        components.scheme = "https"
        components.host = "federation.test"
        components.path = "/v1/inbox/test-node"
        components.queryItems = [
            URLQueryItem(name: "cursor", value: "a+b+c"),
            URLQueryItem(name: "limit", value: "1")
        ]
        let url = try XCTUnwrap(components.url)
        let canonical = try signer.canonicalPath(for: url)

        let recomposed = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let encodedPath = try XCTUnwrap(recomposed?.percentEncodedPath)
        let encodedQuery = try XCTUnwrap(recomposed?.percentEncodedQuery)
        XCTAssertEqual(canonical, "\(encodedPath)?\(encodedQuery)")

        // Golden from Foundation on this platform (not Node): `+` stays unescaped in the query string.
        XCTAssertEqual(canonical, "/v1/inbox/test-node?cursor=a+b+c&limit=1")
        XCTAssertFalse(canonical.contains("%2B"), "Foundation keeps literal + here; do not assume %2B without measuring")
    }
}
