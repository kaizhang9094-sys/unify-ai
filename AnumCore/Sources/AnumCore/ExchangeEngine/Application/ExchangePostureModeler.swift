import Foundation

/// Builds a durable posture snapshot from natural language and interpreted intent.
///
/// Posture is not the user's identity.
/// It is the secretary's current best reading of how the user wants to be carried
/// into this coordination thread.
public struct ExchangePostureModeler: Sendable {
    public static let legacyHeuristic = ExchangePostureModeler(
        intelligenceProvider: nil,
        useLegacyHeuristics: true
    )

    private let intelligenceProvider: (any ExchangeIntelligenceProvider)?
    private let useLegacyHeuristics: Bool

    public init(
        intelligenceProvider: (any ExchangeIntelligenceProvider)? = nil,
        useLegacyHeuristics: Bool = false
    ) {
        self.intelligenceProvider = intelligenceProvider
        self.useLegacyHeuristics = useLegacyHeuristics
    }

    public func model(
        userText: String,
        intent: ExchangeIntent,
        priorPosture: ExchangePosture? = nil
    ) async -> ExchangePosture {
        let normalized = userText.trimmingCharacters(in: .whitespacesAndNewlines)

        if useLegacyHeuristics || intelligenceProvider == nil || normalized.isEmpty {
            return fallbackModel(
                userText: userText,
                intent: intent,
                priorPosture: priorPosture
            )
        }

        let response: ExchangeIntelligencePostureResponse
        do {
            response = try await loadPostureResponse(
                ExchangeIntelligencePostureRequest(
                    userText: normalized,
                    intent: intent,
                    priorPosture: priorPosture
                )
            )
        } catch {
            return fallbackModel(
                userText: userText,
                intent: intent,
                priorPosture: priorPosture
            )
        }

        guard let sanitized = sanitizePostureResponse(
            response,
            intent: intent,
            priorPosture: priorPosture
        ) else {
            return fallbackModel(
                userText: userText,
                intent: intent,
                priorPosture: priorPosture
            )
        }

        return ExchangePosture(
            urgency: sanitized.urgency,
            warmth: sanitized.warmth,
            directness: sanitized.directness,
            openness: sanitized.openness,
            commitment: sanitized.commitment,
            privacy: sanitized.privacy,
            priceSensitivity: sanitized.priceSensitivity,
            flexibility: sanitized.flexibility,
            notes: sanitized.notes
        )
    }
}

private extension ExchangePostureModeler {
    func loadPostureResponse(
        _ request: ExchangeIntelligencePostureRequest
    ) async throws -> ExchangeIntelligencePostureResponse {
        guard let intelligenceProvider else {
            throw ExchangePostureModelerError.noIntelligenceProvider
        }
        return try await intelligenceProvider.modelPosture(request)
    }

    func sanitizePostureResponse(
        _ response: ExchangeIntelligencePostureResponse,
        intent: ExchangeIntent,
        priorPosture: ExchangePosture?
    ) -> ExchangeIntelligencePostureResponse? {
        let confidence = clampConfidence(response.confidence)
        guard confidence >= 0.20 else { return nil }

        let sanitizedNotes: String? = {
            let t = response.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let t, !t.isEmpty else { return nil }
            return String(t.prefix(240))
        }()

        return ExchangeIntelligencePostureResponse(
            urgency: response.urgency,
            warmth: response.warmth,
            directness: response.directness,
            openness: response.openness,
            commitment: response.commitment,
            privacy: response.privacy,
            priceSensitivity: response.priceSensitivity,
            flexibility: response.flexibility,
            notes: sanitizedNotes ?? buildNotes(
                intent: intent,
                urgency: response.urgency,
                warmth: response.warmth,
                directness: response.directness,
                openness: response.openness,
                commitment: response.commitment,
                privacy: response.privacy,
                priceSensitivity: response.priceSensitivity,
                flexibility: response.flexibility
            ),
            confidence: confidence
        )
    }

    func fallbackModel(
        userText: String,
        intent: ExchangeIntent,
        priorPosture: ExchangePosture?
    ) -> ExchangePosture {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        let urgency = inferUrgency(from: lower, intent: intent, prior: priorPosture)
        let warmth = inferWarmth(from: lower, mode: intent.mode, prior: priorPosture)
        let directness = inferDirectness(from: lower, intent: intent, prior: priorPosture)
        let openness = inferOpenness(from: lower, intent: intent, prior: priorPosture)
        let commitment = inferCommitment(from: lower, intent: intent, prior: priorPosture)
        let privacy = inferPrivacy(from: lower, prior: priorPosture)
        let priceSensitivity = inferPriceSensitivity(from: lower, intent: intent, prior: priorPosture)
        let flexibility = inferFlexibility(from: lower, intent: intent, prior: priorPosture)
        let notes = buildNotes(
            intent: intent,
            urgency: urgency,
            warmth: warmth,
            directness: directness,
            openness: openness,
            commitment: commitment,
            privacy: privacy,
            priceSensitivity: priceSensitivity,
            flexibility: flexibility
        )

        return ExchangePosture(
            urgency: urgency,
            warmth: warmth,
            directness: directness,
            openness: openness,
            commitment: commitment,
            privacy: privacy,
            priceSensitivity: priceSensitivity,
            flexibility: flexibility,
            notes: notes
        )
    }

    func clampConfidence(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    func inferUrgency(
        from text: String,
        intent: ExchangeIntent,
        prior: ExchangePosture?
    ) -> ExchangePosture.Urgency {
        if containsAny(text, ["immediately", "asap", "urgent", "today", "right now"]) {
            return .immediate
        }
        if containsAny(text, ["soon", "quickly", "this week"]) {
            return .high
        }
        if containsAny(text, ["no rush", "whenever", "sometime"]) {
            return .low
        }
        if intent.constraints.contains(where: { $0.key == "timing" && $0.value == "urgent" }) {
            return .high
        }
        return prior?.urgency ?? .normal
    }

    func inferWarmth(
        from text: String,
        mode: ExchangeMode,
        prior: ExchangePosture?
    ) -> ExchangePosture.Warmth {
        if containsAny(text, ["friendly", "warm", "gentle", "kind", "softly"]) {
            return .warm
        }
        if containsAny(text, ["formal", "professional", "keep it reserved", "strictly business"]) {
            return .reserved
        }
        if let prior {
            return prior.warmth
        }
        switch mode {
        case .relational:
            return .warm
        case .transactional, .cooperative:
            return .neutral
        }
    }

    func inferDirectness(
        from text: String,
        intent: ExchangeIntent,
        prior: ExchangePosture?
    ) -> ExchangePosture.Directness {
        if containsAny(text, ["direct", "firm", "straight to the point", "clear and concise"]) {
            return .firm
        }
        if containsAny(text, ["soft", "casual", "light touch", "gentle"]) {
            return .soft
        }
        switch intent.kind {
        case .requestQuote, .checkStatus, .followUp:
            return .firm
        case .introduce, .invite, .arrangeMeeting:
            return prior?.directness ?? .balanced
        default:
            return prior?.directness ?? .balanced
        }
    }

    func inferOpenness(
        from text: String,
        intent: ExchangeIntent,
        prior: ExchangePosture?
    ) -> ExchangePosture.Openness {
        if containsAny(text, ["only strong matches", "high fit only", "be selective", "best only"]) {
            return .selective
        }
        if containsAny(text, ["open to options", "broad search", "explore widely"]) {
            return .exploratory
        }
        if intent.mode == .transactional && intent.constraints.count >= 2 {
            return .selective
        }
        return prior?.openness ?? .selective
    }

    func inferCommitment(
        from text: String,
        intent: ExchangeIntent,
        prior: ExchangePosture?
    ) -> ExchangePosture.Commitment {
        if containsAny(text, ["just exploring", "just looking", "curious", "not ready"]) {
            return .exploring
        }
        if containsAny(text, ["committed", "go ahead if it fits", "ready to lock in"]) {
            return .committed
        }
        if containsAny(text, ["serious", "ready to move", "ready to proceed"]) {
            return .serious
        }
        switch intent.kind {
        case .requestQuote, .arrangeCall, .arrangeMeeting:
            return prior?.commitment ?? .serious
        default:
            return prior?.commitment ?? .exploring
        }
    }

    func inferPrivacy(
        from text: String,
        prior: ExchangePosture?
    ) -> ExchangePosture.Privacy {
        if containsAny(text, ["private", "discreet", "guarded", "do not share too much", "keep details minimal"]) {
            return .guarded
        }
        if containsAny(text, ["feel free to share", "you can be open", "full context is fine"]) {
            return .disclosive
        }
        return prior?.privacy ?? .balanced
    }

    func inferPriceSensitivity(
        from text: String,
        intent: ExchangeIntent,
        prior: ExchangePosture?
    ) -> ExchangePosture.PriceSensitivity {
        if containsAny(text, ["cheapest", "lowest price", "very budget sensitive"]) {
            return .high
        }
        if containsAny(text, ["budget", "cost matters", "price matters"]) {
            return .moderate
        }
        if containsAny(text, ["quality first", "price is secondary", "premium is fine"]) {
            return .low
        }
        if intent.kind == .requestQuote {
            return prior?.priceSensitivity ?? .moderate
        }
        return prior?.priceSensitivity ?? .notSpecified
    }

    func inferFlexibility(
        from text: String,
        intent: ExchangeIntent,
        prior: ExchangePosture?
    ) -> ExchangePosture.Flexibility {
        if containsAny(text, ["must", "strictly", "only", "non-negotiable"]) {
            return .rigid
        }
        if containsAny(text, ["flexible", "open", "can adjust", "not fixed"]) {
            return .flexible
        }
        if intent.constraints.contains(where: \.isHardConstraint) {
            return .moderate
        }
        return prior?.flexibility ?? .moderate
    }

    func buildNotes(
        intent: ExchangeIntent,
        urgency: ExchangePosture.Urgency,
        warmth: ExchangePosture.Warmth,
        directness: ExchangePosture.Directness,
        openness: ExchangePosture.Openness,
        commitment: ExchangePosture.Commitment,
        privacy: ExchangePosture.Privacy,
        priceSensitivity: ExchangePosture.PriceSensitivity,
        flexibility: ExchangePosture.Flexibility
    ) -> String? {
        var parts: [String] = []

        if intent.requiresClarificationBeforeAction {
            parts.append("Interpretation is incomplete; posture should be treated cautiously.")
        }
        if privacy == .guarded {
            parts.append("Minimize unnecessary disclosure.")
        }
        if openness == .selective {
            parts.append("Prefer disciplined filtering over broad surfacing.")
        }
        if directness == .firm && warmth == .warm {
            parts.append("Carry a warm but efficient tone.")
        }
        if urgency == .immediate {
            parts.append("Bias toward speed without implying action already happened.")
        }
        if commitment == .exploring {
            parts.append("Do not overstate commitment in outreach.")
        }
        if priceSensitivity == .high {
            parts.append("Cost sensitivity is likely material.")
        }
        if flexibility == .rigid {
            parts.append("Protect hard constraints during matching and drafting.")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
}

private enum ExchangePostureModelerError: Error {
    case noIntelligenceProvider
}
