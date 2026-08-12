import Foundation
import XCTest
@testable import AnumCore

@MainActor
final class ExchangeSecretaryNotificationTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_734_567_890)

    func test_upsertDedupesOnStableKey() async throws {
        let harness = try makeHarness()
        let facade = harness.facade

        let dedupeKey = "testDedupe:user:1"

        try await facade.upsertSecretaryNotification(
            SecretaryNotification(
                createdAt: fixedNow,
                updatedAt: fixedNow,
                kind: .newReply,
                dedupeKey: dedupeKey,
                title: "First",
                body: "Alpha"
            )
        )

        try await facade.upsertSecretaryNotification(
            SecretaryNotification(
                createdAt: fixedNow,
                updatedAt: fixedNow.addingTimeInterval(10),
                kind: .newReply,
                dedupeKey: dedupeKey,
                title: "Second",
                body: "Beta"
            )
        )

        let rows = try await facade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(limit: 20)
        )
        XCTAssertEqual(rows.filter { $0.dedupeKey == dedupeKey }.count, 1)
        let row = try XCTUnwrap(rows.first { $0.dedupeKey == dedupeKey })
        XCTAssertEqual(row.title, "Second")
        XCTAssertEqual(row.body, "Beta")

        let unreadAfterUpsert = try await facade.countUnreadSecretaryNotifications(excludingPriorityLow: true)
        XCTAssertEqual(unreadAfterUpsert, 1)
    }

    func test_hook_saveApproval_pending_createsNeedsApprovalNotification() async throws {
        let harness = try makeHarness()
        let facade = harness.facade

        await facade.registerSecretarySQLiteHooksIfNeeded()

        let threadID = UUID()
        let thread = fixtureThread(id: threadID, now: fixedNow)

        try await harness.store.createThread(thread)

        let approval = ExchangeApproval(
            threadID: threadID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            status: .pending,
            kind: .outboundSend,
            requestedAction: .sendMessage,
            summary: "Please approve the prepared message.",
            rationale: nil
        )

        try await harness.store.saveApproval(approval)

        let filtered = try await facade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(kinds: [.needsApproval], limit: 24)
        )
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.approvalID, approval.id)

        let unreadBeforeMark = try await facade.countUnreadSecretaryNotifications(excludingPriorityLow: true)
        XCTAssertGreaterThanOrEqual(unreadBeforeMark, 1)

        try await facade.markSecretaryNotificationsRead(ids: Set([try XCTUnwrap(filtered.first).id]))
        let unread = try await facade.countUnreadSecretaryNotifications(excludingPriorityLow: true)
        XCTAssertEqual(unread, 0)
    }

    func test_emitReconciledInbound_doesNotCreateNewReplyNotifications() async throws {
        let harness = try makeHarness()
        let facade = harness.facade

        let threadID = UUID()
        try await harness.store.createThread(fixtureThread(id: threadID, now: fixedNow))

        let envelopeID = "fixture-envelope-stable"
        let reconcile = ExchangeFederationReconcileResult(
            reconciledCount: 1,
            deferredCount: 0,
            rejectedCount: 0,
            reconciledThreadIDs: [threadID],
            reconciledEnvelopeIDs: [envelopeID],
            trustEligibleThreadIDs: []
        )

        await facade.emitSecretaryNotificationsForReconciledInbound(result: reconcile, now: fixedNow)
        await facade.emitSecretaryNotificationsForReconciledInbound(result: reconcile, now: fixedNow)

        let replies = try await facade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(kinds: [.newReply], limit: 24)
        )
        XCTAssertEqual(
            replies.count,
            0,
            "Reconcile hook must not insert .newReply; canonical path is replyReceived SQLite hook."
        )
    }

    func test_markSecretaryThreadPeekNotificationsRead_clearsNewReplyUnread() async throws {
        let harness = try makeHarness()
        let facade = harness.facade

        let threadID = UUID()
        try await harness.store.createThread(fixtureThread(id: threadID, now: fixedNow))

        let envelopeID = "peek-envelope-id"
        try await facade.upsertSecretaryNotification(
            SecretaryNotification(
                createdAt: fixedNow,
                updatedAt: fixedNow,
                kind: .newReply,
                dedupeKey: SecretaryNotificationDedupeKey.newReply(threadID: threadID, envelopeID: envelopeID),
                title: "New message",
                body: "Fixture inbound attention.",
                threadID: threadID,
                metadata: ["fixture": "thread_peek_mark_test"]
            )
        )

        let unreadBeforePeek = try await facade.countUnreadSecretaryNotifications(excludingPriorityLow: true)
        XCTAssertEqual(unreadBeforePeek, 1)

        try await facade.markSecretaryThreadPeekNotificationsRead(threadID: threadID)

        let unreadAfterPeek = try await facade.countUnreadSecretaryNotifications(excludingPriorityLow: true)
        XCTAssertEqual(unreadAfterPeek, 0)
    }

    func test_secretaryNotificationCopySanitizer_matchesBannedWordPolicy() {
        let samples: [String] = [
            "Relay status changed.",
            "Envelope arrived.",
            "Check the outbox.",
            "Metadata field updated.",
            "Execution finished.",
            "Trace line here.",
            "Agency review pending.",
            "Mutation applied.",
            "Pipeline stage done.",
            "Second half review.",
            "second_half token",
            "Autonomous mode on."
        ]
        for raw in samples {
            let out = SecretaryNotificationCopySanitizer.sanitizeSentence(raw)
            XCTAssertEqual(
                out,
                SecretaryNotificationCopySanitizer.neutralFallback,
                "Expected neutral fallback for banned sample: \(raw)"
            )
        }

        assertNotificationCopyBannedFree(SecretaryNotificationCopySanitizer.neutralFallback)

        let permutation = SecretaryNotificationCopySanitizer.sanitizeSentence(
            "Discuss one permutation calmly before you decide."
        )
        XCTAssertTrue(permutation.lowercased().contains("permutation"))
    }

    func test_notificationCopySanitizer_stripsBannedWords() {
        let banned = ["execution", "trace", "agency", "mutation", "pipeline"]
        let raw = banned.joined(separator: " ")
        let out = SecretaryNotificationCopySanitizer.sanitizeSentence(raw)

        XCTAssertEqual(out, SecretaryNotificationCopySanitizer.neutralFallback)

        let lower = out.lowercased()
        for word in banned {
            XCTAssertFalse(
                lower.contains(word),
                "Sanitized notification copy should not contain \(word)."
            )
        }

        let safePermutationLine = SecretaryNotificationCopySanitizer.sanitizeSentence(
            "Discuss one permutation calmly before you decide."
        )
        XCTAssertTrue(safePermutationLine.contains("permutation"))
    }

    func test_notificationCopySanitizer_preservesFriendlyUserCopy() {
        let line = SecretaryNotificationCopySanitizer.sanitizeSentence(
            "Thanks — please approve this draft when you can."
        )
        XCTAssertFalse(line.contains("execution"))
        XCTAssertTrue(line.contains("approve"))
    }

    // MARK: - Harness

    private func makeHarness() throws -> Harness {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("secretary-notif-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbURL = tmp.appendingPathComponent("exchange.sqlite")

        let bundle = try ExchangeBootstrap.makeBundle(
            databaseURL: dbURL,
            dependencies: ExchangeBootstrap.Dependencies()
        )

        return Harness(facade: bundle.facade, store: bundle.store)
    }

    private func fixtureThread(id: ExchangeThread.ID, now: Date) -> ExchangeThread {
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture",
            objective: "Fixture objective.",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
        return ExchangeThread(
            id: id,
            createdAt: now,
            updatedAt: now,
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            state: .draftReady(.init(preparedAt: now, summary: "Draft ready")),
            selectedCounterpartyID: "fixture-cp-node"
        )
    }

    private func assertNotificationCopyBannedFree(_ text: String) {
        let lower = text.lowercased()
        XCTAssertNil(
            lower.range(of: #"second(?:[\s_-]+half|_half)"#, options: [.regularExpression, .caseInsensitive])
        )
        let tokens = [
            "relay",
            "envelope",
            "outbox",
            "metadata",
            "execution",
            "trace",
            "agency",
            "mutation",
            "pipeline",
            "autonomous"
        ]
        for term in tokens {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            XCTAssertNil(
                lower.range(of: "\\b\(escaped)\\b", options: [.regularExpression, .caseInsensitive]),
                "'\(term)' leaked into notification copy."
            )
        }
    }

    private struct Harness {
        let facade: ExchangeFacade
        let store: any ExchangeStore
    }
}
