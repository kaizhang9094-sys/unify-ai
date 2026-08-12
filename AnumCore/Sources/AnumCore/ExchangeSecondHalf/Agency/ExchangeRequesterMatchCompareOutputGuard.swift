import Foundation

/// Light hygiene on LLM requester-match compare output. Does not substitute deterministic template questions.
public enum ExchangeRequesterMatchCompareOutputGuard: Sendable {

    public static let maxProviderQuestions = 2

    public static func sanitize(
        _ result: ExchangeRequesterMatchCompareResult,
        matchedEvidenceHaystack: String,
        originalRequesterMessage: String = "",
        requesterRequirementsSummary: String? = nil
    ) -> ExchangeRequesterMatchCompareResult {
        var out = result
        let hay = matchedEvidenceHaystack.lowercased()
        let intentBlob = intentRequirementBlob(
            originalRequesterMessage: originalRequesterMessage,
            requesterRequirementsSummary: requesterRequirementsSummary
        )

        let cleanedQuestions = result.providerQuestions
            .map { stripRoboticSuffixes($0) }
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                guard !shouldSuppressProviderQuestion(trimmed, intentBlob: intentBlob, evidenceHaystack: hay) else {
                    return nil
                }
                return trimmed
            }

        var deduped: [String] = []
        var seen = Set<String>()
        for q in cleanedQuestions {
            let key = q.lowercased()
            guard seen.insert(key).inserted else { continue }
            deduped.append(q)
            if deduped.count >= maxProviderQuestions { break }
        }

        out.providerQuestions = deduped
        out.missingFacts = result.missingFacts
            .map { stripRoboticSuffixes($0) }
            .filter { !RequesterInquiryQuestionNormalizer.isInternalDraftScaffold($0) }
            .filter { !isInternalAnalysisScaffold($0) }
        if out.missingFacts.count > 12 {
            out.missingFacts = Array(out.missingFacts.prefix(12))
        }

        if deduped.isEmpty {
            out.shouldAskProvider = false
        } else {
            out.shouldAskProvider = result.shouldAskProvider || !deduped.isEmpty
        }
        return out
    }

    // MARK: - Suppression policy

    static func shouldSuppressProviderQuestion(
        _ question: String,
        intentBlob: String,
        evidenceHaystack: String
    ) -> Bool {
        if RequesterInquiryQuestionNormalizer.isInternalDraftScaffold(question) { return true }
        if isInternalAnalysisScaffold(question) { return true }
        if isRoboticTemplatePhrase(question) { return true }
        if isRequesterPreferenceWrongAudience(question, intentBlob: intentBlob) { return true }
        if isUnrequestedCredentialDiligence(question, intentBlob: intentBlob) { return true }
        if isUnrequestedTurnaroundDiligence(question, intentBlob: intentBlob) { return true }
        if questionRedundantWithEvidence(question, evidenceHaystack: evidenceHaystack) { return true }
        return false
    }

    static func intentRequirementBlob(
        originalRequesterMessage: String,
        requesterRequirementsSummary: String?
    ) -> String {
        let parts = [
            originalRequesterMessage,
            requesterRequirementsSummary ?? ""
        ]
        return parts
            .joined(separator: "\n")
            .lowercased()
    }

    static func requesterExplicitlyRequiresTurnaroundOrDeadline(intentBlob: String) -> Bool {
        if intentBlob.contains("time:") {
            let timeLine = intentBlob
                .split(separator: "\n")
                .first { $0.hasPrefix("time:") }
                .map(String.init)?
                .lowercased() ?? ""
            let schedulingOnlyNeedles = [
                "next week", "this week", "tomorrow", "weekend", "saturday", "sunday",
                "monday", "tuesday", "wednesday", "thursday", "friday",
                "下周", "周末", "morning", "afternoon", "evening", "am", "pm"
            ]
            let deadlineNeedles = [
                "turnaround", "deadline", "complete by", "finish by", "completion",
                "how long", "lead time", "timeline", "asap", "urgent", "duration"
            ]
            if schedulingOnlyNeedles.contains(where: { timeLine.contains($0) }),
               !deadlineNeedles.contains(where: { timeLine.contains($0) }) {
                return false
            }
        }
        let needles = [
            "turnaround", "deadline", "complete by", "finish by", "completion time",
            "how long", "lead time", "timeline", "estimated timeline", "how soon",
            "duration", "asap", "urgent", "by when", "finish date", "delivery date"
        ]
        return needles.contains { intentBlob.contains($0) }
    }

    /// Scheduling/availability asks are allowed when intent only names a date/week, not project duration.
    static func isAvailabilitySchedulingQuestion(_ question: String) -> Bool {
        let lower = question.lowercased()
        if lower.contains("are you available") || lower.contains("availability") { return true }
        if lower.contains("available ") || lower.hasPrefix("available ") { return true }
        if lower.contains("open to ") && (lower.contains("week") || lower.contains("weekend")) { return true }
        return false
    }

    static func isUnrequestedTurnaroundDiligence(_ question: String, intentBlob: String) -> Bool {
        guard !requesterExplicitlyRequiresTurnaroundOrDeadline(intentBlob: intentBlob) else { return false }
        let lower = question.lowercased()
        if isAvailabilitySchedulingQuestion(question) { return false }
        let turnaroundNeedles = [
            "typical turnaround",
            "turnaround time",
            "how long",
            "completion time",
            "lead time",
            "timeline",
            "estimated timeline",
            "how soon can you complete",
            "how long does it take",
            "how long would it take",
            "how long will it take",
            "project duration",
            "completion window"
        ]
        return turnaroundNeedles.contains { lower.contains($0) }
    }

    static func requesterExplicitlyRequiresCredential(intentBlob: String) -> Bool {
        if intentBlob.contains("credentialorlicenserequired: true") { return true }
        let needles = [
            "licensed", "license", "certified", "certification", "insured", "insurance",
            "credential", "bonded", "accredited", "standard required", "must be licensed"
        ]
        return needles.contains { intentBlob.contains($0) }
    }

    /// Internal LLM / planner analysis phrasing that must not reach providers.
    static func isInternalAnalysisScaffold(_ line: String) -> Bool {
        let lower = line.lowercased()
        let needles = [
            "hardened timeline",
            "high-level cues",
            "high level cues",
            "what hardened timeline",
            "rely on beyond",
            "beyond high-level",
            "beyond high level",
            "grounding cues",
            "surface cues"
        ]
        return needles.contains { lower.contains($0) }
    }

    /// Asks the provider about the requester's category/preferences (wrong audience).
    static func isRequesterPreferenceWrongAudience(_ question: String, intentBlob: String) -> Bool {
        let lower = question.lowercased()
        let wrongAudienceNeedles = [
            "your preferred contractor type",
            "preferred contractor type",
            "general vs. specialized",
            "general vs specialized",
            "what is your preferred",
            "which type do you prefer",
            "which do you prefer",
            "what type do you prefer"
        ]
        guard wrongAudienceNeedles.contains(where: { lower.contains($0) }) else { return false }
        if intentBlob.contains("preference:") || intentBlob.contains("prefer:") {
            return false
        }
        return true
    }

    /// Price/credential/standards diligence when intent did not require it.
    static func isUnrequestedCredentialDiligence(_ question: String, intentBlob: String) -> Bool {
        guard !requesterExplicitlyRequiresCredential(intentBlob: intentBlob) else { return false }
        let lower = question.lowercased()
        let credentialNeedles = [
            "certification body",
            "certification standard",
            "standard for this inspection",
            "certification for",
            "credential",
            "certified",
            "certification",
            "licensed",
            "license",
            "insured",
            "insurance"
        ]
        if credentialNeedles.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower.contains("standard") && (lower.contains("inspection") || lower.contains("certif")) {
            return true
        }
        return false
    }

    // MARK: - Robotic / evidence filtering

    static func stripRoboticSuffixes(_ line: String) -> String {
        var t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements: [(String, String)] = [
            (" for this request?", "?"),
            (" for this request", ""),
            (" for this job?", "?"),
            (" for this job", "")
        ]
        var lower = t.lowercased()
        for (suffix, replacement) in replacements {
            if lower.hasSuffix(suffix) {
                t = String(t.dropLast(suffix.count)) + replacement
                lower = t.lowercased()
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isRoboticTemplatePhrase(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("services matching") { return true }
        if lower.contains("could you clarify: geographic") { return true }
        if lower.contains("underspecified publicly") { return true }
        if lower.contains("geographic/service area fit") { return true }
        return false
    }

    /// Drop provider questions that largely repeat evidence already on the matched surface.
    static func questionRedundantWithEvidence(_ question: String, evidenceHaystack: String) -> Bool {
        guard !evidenceHaystack.isEmpty else { return false }
        let qLower = question.lowercased()
        guard isProviderFacingConfirmationQuestion(qLower) else { return false }

        let tokens = significantTokens(question)
        guard tokens.count >= 2 else { return false }

        let overlap = tokens.filter { evidenceHaystack.contains($0) }
        let ratio = Double(overlap.count) / Double(tokens.count)
        if ratio >= 0.55, overlap.count >= 2 {
            return true
        }
        return false
    }

    private static func isProviderFacingConfirmationQuestion(_ lower: String) -> Bool {
        lower.contains("do you handle")
            || lower.contains("do you offer")
            || lower.contains("do you provide")
            || lower.contains("can you confirm")
            || lower.contains("are you available")
            || lower.contains("do you serve")
    }

    private static func significantTokens(_ text: String) -> [String] {
        let lower = text.lowercased()
        let seps = CharacterSet.alphanumerics.inverted
        return lower
            .components(separatedBy: seps)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { token -> String in
                if token.count > 4, token.hasSuffix("s") { return String(token.dropLast()) }
                return token
            }
            .filter { token in
                guard token.count >= 4 else { return false }
                return !stopTokens.contains(token)
            }
    }

    private static let stopTokens: Set<String> = [
        "the", "and", "for", "with", "this", "that", "your", "you", "are", "can", "do",
        "does", "will", "would", "could", "should", "have", "has", "had", "not", "any",
        "about", "what", "when", "where", "how", "service", "services", "offer", "offers",
        "provide", "provides", "handle", "handles", "confirm", "whether", "around"
    ]
}
