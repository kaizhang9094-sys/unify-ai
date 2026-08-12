#if DEBUG
import Foundation

// MARK: - Fixtures

public enum DirectChatReplyOnDeviceSmokeAuditFixtures {
    public struct Fixture: Sendable, Hashable {
        public var id: String
        public var remoteNodeID: String
        public var contactDisplayName: String
        public var latestIncomingMessage: String?
        public var recentTranscript: [ExchangeModels.DirectReplyTranscriptMessage]
        public var relationshipType: ExchangeModels.ContactRelationshipType
        public var relationshipGoal: ExchangeModels.RelationshipGoal
        public var relationshipNotes: String
        public var toneOverride: String?
        public var aiAssistLevel: ExchangeModels.ContactAIAssistLevel
        public var expectBlocked: Bool
        public var forbiddenNeedles: [String]
        public var maxReplyChars: Int?
        /// When the service uses policy fallback, expected reply text (audit check only).
        public var expectedFallbackReply: String?

        public init(
            id: String,
            remoteNodeID: String = "smoke-direct-reply-node",
            contactDisplayName: String,
            latestIncomingMessage: String?,
            recentTranscript: [ExchangeModels.DirectReplyTranscriptMessage],
            relationshipType: ExchangeModels.ContactRelationshipType,
            relationshipGoal: ExchangeModels.RelationshipGoal,
            relationshipNotes: String = "",
            toneOverride: String? = nil,
            aiAssistLevel: ExchangeModels.ContactAIAssistLevel = .suggestOnly,
            expectBlocked: Bool = false,
            forbiddenNeedles: [String] = [],
            maxReplyChars: Int? = nil,
            expectedFallbackReply: String? = nil
        ) {
            self.id = id
            self.remoteNodeID = remoteNodeID
            self.contactDisplayName = contactDisplayName
            self.latestIncomingMessage = latestIncomingMessage
            self.recentTranscript = recentTranscript
            self.relationshipType = relationshipType
            self.relationshipGoal = relationshipGoal
            self.relationshipNotes = relationshipNotes
            self.toneOverride = toneOverride
            self.aiAssistLevel = aiAssistLevel
            self.expectBlocked = expectBlocked
            self.forbiddenNeedles = forbiddenNeedles
            self.maxReplyChars = maxReplyChars
            self.expectedFallbackReply = expectedFallbackReply
        }
    }

    private static func msg(
        _ role: ExchangeModels.DirectReplyTranscriptRole,
        _ text: String
    ) -> ExchangeModels.DirectReplyTranscriptMessage {
        ExchangeModels.DirectReplyTranscriptMessage(role: role, text: text)
    }

    public static let commercialForbiddenNeedles: [String] = [
        "published offer",
        "provider confirmation",
        "per our listing",
        "profile indicates",
        "commercial profile",
        "I can help with that",
        "As an AI"
    ]

    public static let all: [Fixture] = [
        Fixture(
            id: "friend.coffee_saturday",
            contactDisplayName: "Alex",
            latestIncomingMessage: "Want to grab coffee Saturday morning?",
            recentTranscript: [
                msg(.remoteContact, "Hey! Long time."),
                msg(.localUser, "Yeah it's been a minute."),
                msg(.remoteContact, "Want to grab coffee Saturday morning?")
            ],
            relationshipType: .friend,
            relationshipGoal: .maintainFriendship,
            forbiddenNeedles: commercialForbiddenNeedles
        ),
        Fixture(
            id: "professional.deck_followup",
            contactDisplayName: "Jordan",
            latestIncomingMessage: "Did you get a chance to send the deck?",
            recentTranscript: [
                msg(.localUser, "I'll pull the deck together tonight."),
                msg(.remoteContact, "Did you get a chance to send the deck?")
            ],
            relationshipType: .colleague,
            relationshipGoal: .warmProfessionalContact,
            forbiddenNeedles: commercialForbiddenNeedles,
            expectedFallbackReply:
                "Not yet — I'm working on it and will send it over when it's ready."
        ),
        Fixture(
            id: "blocked.no_inbound",
            contactDisplayName: "Sam",
            latestIncomingMessage: nil,
            recentTranscript: [
                msg(.localUser, "Ping me when you're free.")
            ],
            relationshipType: .friend,
            relationshipGoal: .maintainFriendship,
            expectBlocked: true
        ),
        Fixture(
            id: "blocked.auto_reply_disabled",
            contactDisplayName: "Riley",
            latestIncomingMessage: "Can you cover my shift Sunday?",
            recentTranscript: [
                msg(.remoteContact, "Can you cover my shift Sunday?")
            ],
            relationshipType: .friend,
            relationshipGoal: .maintainFriendship,
            aiAssistLevel: .autoReplyDisabled,
            expectBlocked: true
        ),
        Fixture(
            id: "casual.running_late_tone",
            contactDisplayName: "Morgan",
            latestIncomingMessage: "Running about 10 min late — still good?",
            recentTranscript: [
                msg(.localUser, "See you at the cafe at 3."),
                msg(.remoteContact, "Running about 10 min late — still good?")
            ],
            relationshipType: .friend,
            relationshipGoal: .maintainFriendship,
            toneOverride: "Very brief texting. One short sentence.",
            forbiddenNeedles: commercialForbiddenNeedles,
            maxReplyChars: 220,
            expectedFallbackReply: "No worries, still good."
        ),
        Fixture(
            id: "thread.multi_turn_context",
            contactDisplayName: "Casey",
            latestIncomingMessage: "Should we do tacos or pizza?",
            recentTranscript: [
                msg(.remoteContact, "Dinner Friday?"),
                msg(.localUser, "Yes — 7 works."),
                msg(.remoteContact, "Should we do tacos or pizza?")
            ],
            relationshipType: .friend,
            relationshipGoal: .maintainFriendship,
            forbiddenNeedles: commercialForbiddenNeedles
        )
    ]
}

// MARK: - Row

public struct DirectChatReplyOnDeviceSmokeAuditRow: Codable, Sendable, Hashable {
    public var id: String
    public var success: Bool
    public var blocked: Bool
    public var elapsedMs: Int?
    public var reply: String
    public var reason: String?
    public var forbiddenHit: String?
    public var duplicateOfInbound: Bool
    public var failureReason: String?

    public init(
        id: String,
        success: Bool,
        blocked: Bool,
        elapsedMs: Int?,
        reply: String,
        reason: String?,
        forbiddenHit: String?,
        duplicateOfInbound: Bool,
        failureReason: String? = nil
    ) {
        self.id = id
        self.success = success
        self.blocked = blocked
        self.elapsedMs = elapsedMs
        self.reply = reply
        self.reason = reason
        self.forbiddenHit = forbiddenHit
        self.duplicateOfInbound = duplicateOfInbound
        self.failureReason = failureReason
    }
}

// MARK: - Runner

public enum DirectChatReplyOnDeviceSmokeAuditSupport {
    public static func run(
        suggestionService: DirectChatReplySuggestionService,
        pauseBetweenRowsNanoseconds: UInt64 = 600_000_000
    ) async -> [DirectChatReplyOnDeviceSmokeAuditRow] {
        var rows: [DirectChatReplyOnDeviceSmokeAuditRow] = []
        rows.reserveCapacity(DirectChatReplyOnDeviceSmokeAuditFixtures.all.count)

        for (index, fixture) in DirectChatReplyOnDeviceSmokeAuditFixtures.all.enumerated() {
            let input = buildInput(fixture: fixture)
            let wall = CFAbsoluteTimeGetCurrent()
            let output = await suggestionService.suggestReply(input: input)
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - wall) * 1000)

            let evaluation = evaluateRow(
                fixture: fixture,
                output: output
            )

            let row = DirectChatReplyOnDeviceSmokeAuditRow(
                id: fixture.id,
                success: evaluation.success,
                blocked: evaluation.blocked,
                elapsedMs: elapsedMs,
                reply: output.reply,
                reason: output.reason,
                forbiddenHit: evaluation.forbiddenHit,
                duplicateOfInbound: evaluation.duplicateOfInbound,
                failureReason: evaluation.failureReason
            )
            rows.append(row)
            printSmokeAuditRow(
                row,
                input: input,
                output: output,
                index: index + 1,
                total: DirectChatReplyOnDeviceSmokeAuditFixtures.all.count
            )

            if index < DirectChatReplyOnDeviceSmokeAuditFixtures.all.count - 1,
               pauseBetweenRowsNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: pauseBetweenRowsNanoseconds)
            }
        }

        return rows
    }

    public static func writeJSONL(rows: [DirectChatReplyOnDeviceSmokeAuditRow], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data()
        for (idx, row) in rows.enumerated() {
            data.append(try encoder.encode(row))
            if idx < rows.count - 1 { data.append(Data("\n".utf8)) }
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Input

    private static func buildInput(
        fixture: DirectChatReplyOnDeviceSmokeAuditFixtures.Fixture
    ) -> ExchangeModels.DirectReplySuggestionInput {
        let context = ExchangeModels.ContactContext(
            remoteNodeID: fixture.remoteNodeID,
            relationshipType: fixture.relationshipType,
            relationshipGoal: fixture.relationshipGoal,
            notes: fixture.relationshipNotes,
            toneOverride: fixture.toneOverride,
            aiAssistLevel: fixture.aiAssistLevel
        )
        return ExchangeModels.DirectReplySuggestionInput(
            remoteNodeID: fixture.remoteNodeID,
            localUserDisplayName: "Kai",
            contactDisplayName: fixture.contactDisplayName,
            latestIncomingMessage: fixture.latestIncomingMessage,
            recentTranscript: fixture.recentTranscript,
            contactContext: context,
            relationshipType: fixture.relationshipType,
            relationshipGoal: fixture.relationshipGoal,
            relationshipNotes: fixture.relationshipNotes,
            toneOverride: fixture.toneOverride,
            safetyRules: []
        )
    }

    // MARK: - Evaluation

    private struct RowEvaluation {
        var success: Bool
        var blocked: Bool
        var forbiddenHit: String?
        var duplicateOfInbound: Bool
        var failureReason: String?
    }

    private static func evaluateRow(
        fixture: DirectChatReplyOnDeviceSmokeAuditFixtures.Fixture,
        output: ExchangeModels.DirectReplySuggestionOutput
    ) -> RowEvaluation {
        let reply = output.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let blocked = reply.isEmpty
        var failureReasons: [String] = []

        if fixture.expectBlocked {
            if !blocked {
                failureReasons.append("expected_blocked_got_reply")
            }
        } else {
            if blocked {
                failureReasons.append("expected_reply_got_blocked")
            }
            if let maxChars = fixture.maxReplyChars, reply.count > maxChars {
                failureReasons.append("reply_too_long")
            }
        }

        let forbiddenHit = detectForbiddenNeedle(
            reply: reply,
            needles: fixture.forbiddenNeedles
        )
        if let forbiddenHit, !fixture.expectBlocked {
            failureReasons.append("forbidden_needle:\(forbiddenHit)")
        }

        let duplicateOfInbound = isDuplicateOfInbound(
            reply: reply,
            inbound: fixture.latestIncomingMessage
        )
        if duplicateOfInbound, !fixture.expectBlocked {
            failureReasons.append("exact_duplicate_of_inbound")
        }

        if fixture.expectedFallbackReply != nil,
           output.reason == "Fallback suggestion used." {
            let selectionKey =
                "\(fixture.remoteNodeID)|" +
                String((fixture.latestIncomingMessage ?? "").prefix(80))
            let expected = DirectChatReplySuggestionPolicy.fallbackReplyText(
                latestInboundMessage: fixture.latestIncomingMessage,
                relationshipType: fixture.relationshipType,
                selectionKey: selectionKey
            )
            if reply != expected {
                failureReasons.append("unexpected_fallback_reply")
            }
        }

        return RowEvaluation(
            success: failureReasons.isEmpty,
            blocked: blocked,
            forbiddenHit: forbiddenHit,
            duplicateOfInbound: duplicateOfInbound,
            failureReason: failureReasons.isEmpty ? nil : failureReasons.joined(separator: ";")
        )
    }

    private static func detectForbiddenNeedle(reply: String, needles: [String]) -> String? {
        let lowered = reply.lowercased()
        for needle in needles {
            let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }
            if lowered.contains(trimmed) {
                return needle
            }
        }
        return nil
    }

    private static func isDuplicateOfInbound(reply: String, inbound: String?) -> Bool {
        let normalizedReply = normalizeForDuplicateCheck(reply)
        guard !normalizedReply.isEmpty else { return false }
        return normalizeForDuplicateCheck(inbound) == normalizedReply
    }

    private static func normalizeForDuplicateCheck(_ value: String?) -> String {
        let trimmed = value?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased() ?? ""

        return trimmed
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func printSmokeAuditRow(
        _ row: DirectChatReplyOnDeviceSmokeAuditRow,
        input: ExchangeModels.DirectReplySuggestionInput,
        output: ExchangeModels.DirectReplySuggestionOutput,
        index: Int,
        total: Int
    ) {
        print(
            "[DirectChatReplySmokeAudit] \(index)/\(total) id=\(row.id) " +
                "success=\(row.success) blocked=\(row.blocked) elapsedMs=\(row.elapsedMs ?? -1) " +
                "duplicate=\(row.duplicateOfInbound) forbidden=\(row.forbiddenHit ?? "nil") " +
                "failure=\(row.failureReason ?? "nil")"
        )
        print("[DirectChatReplySmokeAudit]   INPUT \(formatInputLog(input))")
        print("[DirectChatReplySmokeAudit]   OUTPUT \(formatOutputLog(output))")
    }

    private static func formatInputLog(_ input: ExchangeModels.DirectReplySuggestionInput) -> String {
        let context = input.contactContext
        let latest = input.latestIncomingMessage ?? "nil"
        let transcript = formatTranscriptLog(input.recentTranscript)
        let tone = context.toneOverride ?? "nil"
        let notesChars = context.notes.count
        return [
            "contact=\(input.contactDisplayName ?? "nil")",
            "nodeID=\(input.remoteNodeID)",
            "latestIncoming=\(logQuoted(latest))",
            "transcript=\(transcript)",
            "relationship=\(context.relationshipType.rawValue)",
            "goal=\(context.relationshipGoal.rawValue)",
            "aiAssist=\(context.aiAssistLevel.rawValue)",
            "tone=\(logQuoted(tone))",
            "notesChars=\(notesChars)"
        ].joined(separator: " ")
    }

    private static func formatOutputLog(_ output: ExchangeModels.DirectReplySuggestionOutput) -> String {
        let reply = output.reply.isEmpty ? "nil" : logQuoted(output.reply)
        let reason = output.reason ?? "nil"
        let safety = output.safety ?? "nil"
        let fallbackReason = output.fallbackReason ?? "nil"
        let duplicateRetry = output.duplicateRetry ?? "none"
        return [
            "reply=\(reply)",
            "reason=\(logQuoted(reason))",
            "fallbackReason=\(fallbackReason)",
            "duplicateRetry=\(duplicateRetry)",
            "safety=\(safety)",
            "requiresApproval=\(output.requiresApproval)"
        ].joined(separator: " ")
    }

    private static func formatTranscriptLog(
        _ messages: [ExchangeModels.DirectReplyTranscriptMessage]
    ) -> String {
        guard !messages.isEmpty else { return "[]" }
        let lines = messages.map { message in
            let role = message.role == .localUser ? "local" : "remote"
            return "\(role):\(logQuoted(message.text))"
        }
        return "[\(lines.joined(separator: ", "))]"
    }

    private static func logQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
#endif
