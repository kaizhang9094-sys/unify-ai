import Foundation
import Testing
@testable import AnumCore

struct PublicMediaURLSupportTests {
    private let validKey = "a1b2c3d4e5f6789012345678abcdef01_my-node.png"

    @Test func storageKeyFromAbsoluteURL() {
        let url = "https://example.com/media/upload/\(validKey)?v=1"
        #expect(PublicMediaURLSupport.storageKeyFromPublicMediaURL(url) == validKey)
    }

    @Test func storageKeyFromRelativeURL() {
        let url = "/media/upload/\(validKey)"
        #expect(PublicMediaURLSupport.storageKeyFromPublicMediaURL(url) == validKey)
    }

    @Test func storageKeyRejectsInvalidPath() {
        #expect(PublicMediaURLSupport.storageKeyFromPublicMediaURL("/images/other.png") == nil)
        #expect(PublicMediaURLSupport.storageKeyFromPublicMediaURL("") == nil)
    }

    @Test func storageKeyRejectsTraversal() {
        let url = "/media/upload/../../../etc/passwd"
        #expect(PublicMediaURLSupport.storageKeyFromPublicMediaURL(url) == nil)
    }

    @Test func storageKeyRejectsNonMediaURL() {
        #expect(PublicMediaURLSupport.storageKeyFromPublicMediaURL("https://cdn.example.com/avatar.png") == nil)
    }

    @Test func deleteOutcomeSuccessDeleted() throws {
        let payload: [String: Any] = ["ok": true, "deleted": true]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let outcome = PublicMediaURLSupport.deleteOutcome(statusCode: 200, responseData: data)
        #expect(outcome == .deleted)
    }

    @Test func deleteOutcomeNotFoundIdempotent() throws {
        let payload: [String: Any] = ["ok": true, "deleted": false, "reason": "not_found"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let outcome = PublicMediaURLSupport.deleteOutcome(statusCode: 200, responseData: data)
        #expect(outcome == .notFound)
    }

    @Test func deleteOutcomeStillReferencedNonfatal() throws {
        let payload: [String: Any] = ["ok": false, "error": "MEDIA_STILL_REFERENCED"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let outcome = PublicMediaURLSupport.deleteOutcome(statusCode: 409, responseData: data)
        #expect(outcome == .stillReferenced)
    }

    @Test func deleteOutcomeOwnershipMismatch() throws {
        let payload: [String: Any] = ["ok": false, "error": "MEDIA_NOT_OWNED"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let outcome = PublicMediaURLSupport.deleteOutcome(statusCode: 403, responseData: data)
        #expect(outcome == .ownershipMismatch)
    }
}
