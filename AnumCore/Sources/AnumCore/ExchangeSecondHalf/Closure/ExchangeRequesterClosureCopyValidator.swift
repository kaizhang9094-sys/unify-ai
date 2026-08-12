import Foundation

/// Validates composed closure copy against deterministic pause semantics (no LLM authority).
public struct ExchangeRequesterClosureCopyValidator: Sendable {
    public init() {}

    /// Returns sanitized copy if valid; otherwise `nil` (caller falls back to deterministic pause strings).
    public func validate(
        _ composed: ExchangeRequesterClosureComposedCopy,
        against pause: ExchangeRequesterPauseFrame
    ) -> ExchangeRequesterClosureComposedCopy? {
        guard mechanicalOk(composed) else { return nil }
        guard !containsForbiddenVocabulary(composed) else { return nil }
        guard semanticGates(composed, pause: pause) else { return nil }
        guard fitMovementGates(composed, pause: pause) else { return nil }
        return sanitize(composed)
    }

    // MARK: - Mechanical

    private let maxTitle = 80
    private let maxSummary = 600
    private let maxBullet = 220
    private let maxRecommendation = 500
    private let maxNextAction = 60

    private func mechanicalOk(_ c: ExchangeRequesterClosureComposedCopy) -> Bool {
        func ok(_ s: String, max: Int) -> Bool {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && t.count <= max
        }
        guard ok(c.title, max: maxTitle),
              ok(c.summary, max: maxSummary),
              ok(c.recommendation, max: maxRecommendation),
              ok(c.nextActionLabel, max: maxNextAction)
        else { return false }

        for b in c.answeredBullets + c.stillOpenBullets {
            let t = b.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t.count > maxBullet { return false }
        }
        return true
    }

    private func sanitize(_ c: ExchangeRequesterClosureComposedCopy) -> ExchangeRequesterClosureComposedCopy {
        ExchangeRequesterClosureComposedCopy(
            title: ExchangeUserFacingCopySanitizer.sanitizeOrFallback(c.title, field: .title, fallback: "Update"),
            summary: ExchangeUserFacingCopySanitizer.sanitizeOrFallback(c.summary, field: .body, fallback: c.summary),
            answeredBullets: c.answeredBullets.compactMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .body) },
            stillOpenBullets: c.stillOpenBullets.compactMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .body) },
            recommendation: ExchangeUserFacingCopySanitizer.sanitizeOrFallback(c.recommendation, field: .body, fallback: c.recommendation),
            nextActionLabel: ExchangeUserFacingCopySanitizer.sanitizeOrFallback(c.nextActionLabel, field: .subtitle, fallback: "Next")
        )
    }

    // MARK: - Forbidden vocabulary

    private func containsForbiddenVocabulary(_ c: ExchangeRequesterClosureComposedCopy) -> Bool {
        let blob = [
            c.title, c.summary, c.recommendation, c.nextActionLabel,
            c.answeredBullets.joined(separator: " "),
            c.stillOpenBullets.joined(separator: " ")
        ].joined(separator: " ")

        if ExchangeRequesterReviewPresentation.containsInternalRequesterLeak(blob) { return true }

        let extra = [
            "pausereason", "pause reason", "fitmovement", "fit movement",
            "deterministic resolver", "pause frame", "policy engine", "boundary engine",
            "autonomy disposition", "provider answerability", "grounded facts",
            "thread state machine", "classification result", "planner output",
            "json", "knownfacts", "unresolvedissues", "missingfacts", "qualificationstatus"
        ]
        let lower = blob.lowercased()
        for needle in extra where lower.contains(needle) { return true }
        return false
    }

    // MARK: - Semantic gates

    private func semanticGates(_ c: ExchangeRequesterClosureComposedCopy, pause: ExchangeRequesterPauseFrame) -> Bool {
        let p = pause
        let combinedLower = (c.summary + " " + c.recommendation).lowercased()

        if !p.commitmentSignals.isEmpty {
            let warn = ["contract", "deposit", "sign", "commitment", "terms", "review carefully"]
            guard warn.contains(where: { combinedLower.contains($0) }) else { return false }
        }

        if !p.providerQuestions.isEmpty {
            let askedUser = c.summary.contains("?")
                || combinedLower.contains("you ")
                || combinedLower.contains("your ")
                || combinedLower.contains("prefer")
                || combinedLower.contains("confirm")
                || combinedLower.contains("answer")
            guard askedUser else { return false }
        }

        if !p.stillMissingFacts.isEmpty {
            let deny = [
                "everything is clear", "everything's clear", "all set", "fully answered",
                "nothing else", "fully resolved", "all details", "nothing missing"
            ]
            if deny.contains(where: { combinedLower.contains($0) }) { return false }
        }

        if !p.weakeningSignals.isEmpty {
            let optimistic = ["strong fit", "perfect match", "ideal fit", "great match", "looks perfect"]
            if optimistic.contains(where: { combinedLower.contains($0) }) { return false }
            let cautious = ["may not match", "keep searching", "mismatch", "different", "unclear fit", "weak match"]
            guard cautious.contains(where: { combinedLower.contains($0) }) else { return false }
        }

        if p.pauseReason == .waitingForRequesterInput {
            let nextLower = c.nextActionLabel.lowercased()
            let prompt = ["answer", "reply", "tell", "pick", "share", "your"]
            guard prompt.contains(where: { nextLower.contains($0) }) else { return false }
        }

        if p.pauseReason == .needsOneMoreClarification {
            let clarify = ["follow", "clarif", "question", "ask", "more detail"]
            guard clarify.contains(where: { combinedLower.contains($0) }) else { return false }
        }

        return true
    }

    // MARK: - Fit movement (natural language)

    private func fitMovementGates(_ c: ExchangeRequesterClosureComposedCopy, pause: ExchangeRequesterPauseFrame) -> Bool {
        let combinedLower = (c.summary + " " + c.recommendation).lowercased()

        switch pause.fitMovement {
        case .weakened:
            let optimistic = ["great match", "perfect match", "strong fit", "looks perfect", "ideal"]
            if optimistic.contains(where: { combinedLower.contains($0) }) { return false }

        case .improved:
            if pause.weakeningSignals.isEmpty {
                let worse = ["abandon", "bad fit", "wrong fit", "stop searching", "ignore"]
                if worse.contains(where: { combinedLower.contains($0) }) { return false }
            }

        case .unclear, .unchanged:
            let definitiveUp = ["fit improved a lot", "much better match", "perfect now"]
            let definitiveDown = ["fit collapsed", "completely wrong fit"]
            if definitiveUp.contains(where: { combinedLower.contains($0) }) && pause.answeredFacts.isEmpty {
                return false
            }
            if definitiveDown.contains(where: { combinedLower.contains($0) }) && pause.weakeningSignals.isEmpty {
                return false
            }
        }

        return true
    }
}
