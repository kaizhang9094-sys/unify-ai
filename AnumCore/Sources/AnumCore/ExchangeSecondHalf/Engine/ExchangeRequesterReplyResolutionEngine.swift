import Foundation

/// Deterministic, keyword-based interpretation of the latest provider reply for requester logical pause.
/// No LLM. Does not mutate persisted `unresolvedIssues`.
public struct ExchangeRequesterReplyResolutionEngine: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var requestTextBlob: String
        public var knownFactsLines: [String]
        public var clarifiedFactsLines: [String]
        public var unresolvedIssuesLines: [String]
        public var qualificationMissingFacts: [String]
        public var latestCounterpartyReplyText: String?
        public var hasFreshProviderAnswer: Bool
        public var qualificationTier: ExchangeOpportunityQualityTier
        public var secondHalfState: ExchangeSecondHalfState
        public var isThreadExplicitlyCompleted: Bool

        public init(
            requestTextBlob: String,
            knownFactsLines: [String] = [],
            clarifiedFactsLines: [String] = [],
            unresolvedIssuesLines: [String] = [],
            qualificationMissingFacts: [String] = [],
            latestCounterpartyReplyText: String? = nil,
            hasFreshProviderAnswer: Bool = false,
            qualificationTier: ExchangeOpportunityQualityTier = .weak,
            secondHalfState: ExchangeSecondHalfState = .matchFound,
            isThreadExplicitlyCompleted: Bool = false
        ) {
            self.requestTextBlob = requestTextBlob
            self.knownFactsLines = knownFactsLines
            self.clarifiedFactsLines = clarifiedFactsLines
            self.unresolvedIssuesLines = unresolvedIssuesLines
            self.qualificationMissingFacts = qualificationMissingFacts
            self.latestCounterpartyReplyText = latestCounterpartyReplyText
            self.hasFreshProviderAnswer = hasFreshProviderAnswer
            self.qualificationTier = qualificationTier
            self.secondHalfState = secondHalfState
            self.isThreadExplicitlyCompleted = isThreadExplicitlyCompleted
        }
    }

    public func resolve(input: Input) -> ExchangeRequesterPauseFrame {
        if input.isThreadExplicitlyCompleted {
            return ExchangeRequesterPauseFrame(
                answeredFacts: [],
                resolvedMissingLabels: [],
                stillMissingFacts: [],
                providerQuestions: [],
                commitmentSignals: [],
                weakeningSignals: [],
                fitMovement: .unchanged,
                pauseReason: .completed,
                summaryLine: "This thread is marked done.",
                recommendationLine: "No further action is needed unless you reopen the conversation.",
                nextActionLabel: "Done",
                canContinueOnReply: false
            )
        }

        let requestNorm = normalize(input.requestTextBlob)
        let replyBlob = buildReplyBlob(input: input)

        let wantsPrice = requestNorm.contains(anyOf: [
            "price", "rate", "cost", "fee", "how much", "charge", "$", "per hour", "hourly"
        ])
        let wantsAvailability = requestNorm.contains(anyOf: [
            "availability", "available", "schedule", "when", "time", "weekday", "weekend", "evening", "morning", "slot"
        ])
        let wantsLocationMode = requestNorm.contains(anyOf: [
            "location", "where", "studio", "online", "in person", "in-person", "remote", "lesson location", "service area", "address"
        ])

        let hasPriceInReply = replyBlob.contains(anyOf: ["$", "per hour", "/hour", "hour", "rate", "charge", "fee", "cost", "price"])
        let hasAvailabilityInReply = replyBlob.contains(anyOf: [
            "available", "availability", "weekday", "weekend", "evening", "morning", "schedule", "times", "slot", "pm", "am", "9-5", "9 to 5"
        ])
        let hasLocationModeInReply = replyBlob.contains(anyOf: [
            "studio", "online", "in person", "in-person", "remote", "at my", "service area", "address", "location"
        ])
        let hasServiceInReply = replyBlob.contains(anyOf: ["piano", "guitar", "lesson", "teach", "tutor", "music"])

        let commitmentSignals = detectCommitmentSignals(replyBlob: replyBlob)
        let providerQuestions = detectProviderQuestions(replyBlob: replyBlob)
        let weakeningSignals = detectWeakeningSignals(requestNorm: requestNorm, replyBlob: replyBlob)

        var answeredFacts: [String] = []
        if hasPriceInReply { answeredFacts.append("Price or rate mentioned in the provider reply.") }
        if hasAvailabilityInReply { answeredFacts.append("Availability or schedule mentioned in the provider reply.") }
        if hasLocationModeInReply { answeredFacts.append("Lesson location or format (studio / online / in-person) mentioned.") }
        if hasServiceInReply { answeredFacts.append("Service or instrument details mentioned.") }

        var resolvedLabels: [String] = []
        if wantsPrice, hasPriceInReply { resolvedLabels.append("price") }
        if wantsAvailability, hasAvailabilityInReply { resolvedLabels.append("availability") }
        if wantsLocationMode, hasLocationModeInReply { resolvedLabels.append("locationOrMode") }

        var stillMissing: [String] = []
        if wantsPrice, !hasPriceInReply { stillMissing.append("Price or rate is still unclear.") }
        if wantsAvailability, !hasAvailabilityInReply { stillMissing.append("Availability or schedule is still unclear.") }
        if wantsLocationMode, !hasLocationModeInReply { stillMissing.append("Lesson location or format is still unclear.") }

        let expectedWants = [wantsPrice, wantsAvailability, wantsLocationMode].filter { $0 }.count
        let expectedResolved = resolvedLabels.count

        let fitMovement: ExchangeRequesterFitMovement = {
            if !weakeningSignals.isEmpty { return .weakened }
            if !commitmentSignals.isEmpty || !providerQuestions.isEmpty { return .unclear }
            if expectedWants > 0, expectedResolved >= expectedWants { return .improved }
            if expectedResolved > 0 { return .unclear }
            return .unchanged
        }()

        var rawPause: ExchangeRequesterPauseReason = .needsOneMoreClarification

        if input.secondHalfState == .blocked || input.secondHalfState == .stalled {
            rawPause = .blockedNeedsCare
        } else if !input.hasFreshProviderAnswer, input.secondHalfState == .awaitingProviderClarification {
            rawPause = .waitingForProviderReply
        } else if !weakeningSignals.isEmpty {
            rawPause = .weakFitKeepSearching
        } else if !commitmentSignals.isEmpty {
            rawPause = .commitmentReview
        } else if !providerQuestions.isEmpty {
            rawPause = .waitingForRequesterInput
        } else if expectedWants > 0, expectedResolved >= expectedWants, stillMissing.isEmpty {
            rawPause = .waitingForRequesterDecision
        } else if expectedResolved > 0, !stillMissing.isEmpty {
            rawPause = .needsOneMoreClarification
        } else if !input.hasFreshProviderAnswer {
            rawPause = .waitingForProviderReply
        } else {
            rawPause = .needsOneMoreClarification
        }

        let (summaryLine, recommendationLine, nextActionLabel) = buildCopy(
            pause: rawPause,
            answeredFacts: answeredFacts,
            stillMissing: stillMissing,
            weakeningSignals: weakeningSignals
        )

        return ExchangeRequesterPauseFrame(
            answeredFacts: answeredFacts,
            resolvedMissingLabels: resolvedLabels,
            stillMissingFacts: stillMissing,
            providerQuestions: providerQuestions,
            commitmentSignals: commitmentSignals,
            weakeningSignals: weakeningSignals,
            fitMovement: fitMovement,
            pauseReason: rawPause,
            summaryLine: summaryLine,
            recommendationLine: recommendationLine,
            nextActionLabel: nextActionLabel,
            canContinueOnReply: rawPause != .completed
        )
    }

    /// Merge policy/boundary outcomes after the main boundary classification (explanatory only).
    public func mergePauseReason(
        base: ExchangeRequesterPauseFrame,
        boundaryRequiresHumanApproval: Bool,
        secondHalfState: ExchangeSecondHalfState
    ) -> ExchangeRequesterPauseFrame {
        var copy = base
        if secondHalfState == .blocked || secondHalfState == .stalled {
            copy.pauseReason = .blockedNeedsCare
        } else if boundaryRequiresHumanApproval {
            copy.pauseReason = .commitmentReview
            if copy.commitmentSignals.isEmpty {
                copy.commitmentSignals = ["Commitment or approval may be required before proceeding."]
            }
        }
        if copy.pauseReason == .waitingForRequesterDecision,
           (boundaryRequiresHumanApproval || !copy.providerQuestions.isEmpty || !copy.commitmentSignals.isEmpty) {
            if boundaryRequiresHumanApproval || !copy.commitmentSignals.isEmpty {
                copy.pauseReason = .commitmentReview
            } else if !copy.providerQuestions.isEmpty {
                copy.pauseReason = .waitingForRequesterInput
            }
        }
        let (s, r, n) = buildCopy(
            pause: copy.pauseReason,
            answeredFacts: copy.answeredFacts,
            stillMissing: copy.stillMissingFacts,
            weakeningSignals: copy.weakeningSignals
        )
        copy.summaryLine = s
        copy.recommendationLine = r
        copy.nextActionLabel = n
        copy.canContinueOnReply = copy.pauseReason != .completed
        return copy
    }

    // MARK: - Internals

    private func buildReplyBlob(input: Input) -> String {
        var parts: [String] = []
        if let t = input.latestCounterpartyReplyText?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            parts.append(t)
        }
        let factLines = input.clarifiedFactsLines + input.knownFactsLines
        for line in factLines {
            let lower = line.lowercased()
            if lower.hasPrefix("provider answer:") || lower.hasPrefix("reply:") {
                parts.append(line)
            }
        }
        return normalize(parts.joined(separator: " "))
    }

    private func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private func detectCommitmentSignals(replyBlob: String) -> [String] {
        var out: [String] = []
        let pairs: [(String, String)] = [
            ("contract", "Contract terms mentioned."),
            ("deposit", "Deposit mentioned."),
            ("sign", "Signing or signature mentioned."),
            ("guarantee", "Guarantee language mentioned."),
            ("6-month", "Fixed-term commitment mentioned."),
            ("6 month", "Fixed-term commitment mentioned."),
            ("recurring", "Recurring commitment mentioned.")
        ]
        for (needle, label) in pairs where replyBlob.contains(needle) {
            out.append(label)
        }
        return Array(Set(out)).sorted()
    }

    private func detectProviderQuestions(replyBlob: String) -> [String] {
        guard replyBlob.contains("?")
            || replyBlob.contains(anyOf: ["do you", "which ", " which", "prefer", "can you confirm", "would you", "could you"])
        else {
            return []
        }
        let trimmed = replyBlob.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 220 {
            return [String(trimmed.prefix(217)) + "…"]
        }
        return [trimmed]
    }

    private func detectWeakeningSignals(requestNorm: String, replyBlob: String) -> [String] {
        var signals: [String] = []
        if requestNorm.contains("piano"), replyBlob.contains("guitar"), !replyBlob.contains("piano") {
            signals.append("Reply emphasizes a different instrument than your request.")
        }
        if requestNorm.contains("aurora"), replyBlob.contains("toronto"), !replyBlob.contains("aurora") {
            signals.append("Reply references a different location than your request.")
        }
        return signals
    }

    private func buildCopy(
        pause: ExchangeRequesterPauseReason,
        answeredFacts: [String],
        stillMissing: [String],
        weakeningSignals: [String]
    ) -> (String, String, String) {
        switch pause {
        case .completed:
            return ("Thread completed.", "No further steps unless you resume the conversation.", "Done")
        case .blockedNeedsCare:
            return (
                "This coordination path looks blocked or needs careful review.",
                "Check the latest status and any system messages before continuing.",
                "Review status"
            )
        case .waitingForProviderReply:
            return (
                "Waiting for the provider’s reply.",
                "Once they respond, Unify will refresh this summary.",
                "Wait for reply"
            )
        case .weakFitKeepSearching:
            let w = weakeningSignals.first ?? "The reply may not match what you asked for."
            return (
                "Weak match for what you requested.",
                "\(w) Consider continuing your search or clarifying your needs.",
                "Keep searching"
            )
        case .commitmentReview:
            return (
                "Provider reply includes commitment-style terms.",
                "Review terms carefully before accepting or scheduling anything.",
                "Review commitment"
            )
        case .waitingForRequesterInput:
            return (
                "The provider asked you a question.",
                "Answer their question so the thread can move forward cleanly.",
                "Answer the question"
            )
        case .waitingForRequesterDecision:
            let answered = answeredFacts.prefix(3).joined(separator: " ")
            let a = answered.isEmpty ? "They shared useful details." : answered
            return (
                "Provider replied with details worth reviewing.",
                "\(a) When you’re ready, decide whether to move forward.",
                "Review and decide"
            )
        case .needsOneMoreClarification:
            let miss = stillMissing.prefix(2).joined(separator: " ")
            let m = miss.isEmpty ? "A few details may still be fuzzy." : miss
            return (
                "Provider replied, but some requested details are still thin.",
                "\(m) One more focused clarification may help.",
                "Ask one more clarification"
            )
        }
    }
}

// MARK: - Small string helpers

private extension String {
    func contains(anyOf terms: [String]) -> Bool {
        terms.contains { contains($0) }
    }
}
