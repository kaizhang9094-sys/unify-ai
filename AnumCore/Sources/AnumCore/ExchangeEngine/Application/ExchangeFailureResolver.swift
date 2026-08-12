import Foundation

#if DEBUG
@inline(__always)
private func exFailureLog(_ message: @autoclosure () -> String) {
    print("[ExchangeFailureResolver] \(message())")
}
#else
@inline(__always)
private func exFailureLog(_ message: @autoclosure () -> String) { }
#endif

/// Converts raw failure situations into legible Exchange failures,
/// mapped thread state, and recommended next steps.
///
/// This is one of the most important trust-preserving components in Exchange.
/// It must never imply action happened when it did not.
public struct ExchangeFailureResolver: Sendable {
    public init() {}

    public func resolve(_ input: FailureInput) -> Resolution {
        exFailureLog(
            "resolve kind=\(input.kind.rawValue) summary=\(input.summary) reasonCode=\(input.reasonCode ?? "nil") externalEffect=\(input.externalEffect)"
        )

        let resolution: Resolution

        switch input.kind {
        case .understanding:
            resolution = resolveUnderstanding(input)
        case .discovery:
            resolution = resolveDiscovery(input)
        case .fit:
            resolution = resolveFit(input)
        case .delivery:
            resolution = resolveDelivery(input)
        case .negotiation:
            resolution = resolveNegotiation(input)
        case .system:
            resolution = resolveSystem(input)
        }

        exFailureLog(
            "resolved kind=\(input.kind.rawValue) mappedState=\(ExchangeTransition.ExchangeStateKey(resolution.mappedState).rawValue) visibleSummary=\(resolution.visibleSummary)"
        )

        return resolution
    }
}

public extension ExchangeFailureResolver {
    struct FailureInput: Sendable, Hashable {
        public var kind: Kind
        public var summary: String
        public var detail: String?
        public var externalEffect: ExchangeFailure.ExternalEffect
        public var recommendation: Recommendation
        public var technicalDetails: String?
        public var reasonCode: String?

        public init(
            kind: Kind,
            summary: String,
            detail: String? = nil,
            externalEffect: ExchangeFailure.ExternalEffect = .none,
            recommendation: Recommendation = .none,
            technicalDetails: String? = nil,
            reasonCode: String? = nil
        ) {
            self.kind = kind
            self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.externalEffect = externalEffect
            self.recommendation = recommendation
            self.technicalDetails = technicalDetails?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            self.reasonCode = reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
    }

    enum Kind: String, Sendable, Hashable {
        case understanding
        case discovery
        case fit
        case delivery
        case negotiation
        case system
    }

    enum Recommendation: Sendable, Hashable {
        case clarify(question: String)
        case refineSearch(String)
        case widenSearch(String)
        case retrySoon
        case retryLater
        case reviewMismatch(String)
        case sendFollowUp
        case closeThread(String)
        case contactSupport
        case none
    }

    struct Resolution: Sendable, Hashable {
        public var failure: ExchangeFailure
        public var mappedState: ExchangeState
        public var visibleSummary: String

        public init(
            failure: ExchangeFailure,
            mappedState: ExchangeState,
            visibleSummary: String
        ) {
            self.failure = failure
            self.mappedState = mappedState
            self.visibleSummary = visibleSummary
        }
    }
}

private extension ExchangeFailureResolver {
    func resolveUnderstanding(_ input: FailureInput) -> Resolution {
        let question: String = {
            if case .clarify(let question) = input.recommendation { return question }
            return "What exactly do you want me to coordinate?"
        }()

        let failure = ExchangeFailure.understanding(
            summary: normalizedSummary(input.summary, fallback: "I do not yet understand enough to act."),
            whatHappened: input.detail ?? "The request was interpreted only partially, and acting now would risk false precision.",
            question: question,
            reasonCode: input.reasonCode
        )

        let state = ExchangeState.needsClarification(
            ExchangeState.ClarificationStatus(question: question)
        )

        exFailureLog(
            "resolveUnderstanding question=\(question) summary=\(failure.summary)"
        )

        return Resolution(
            failure: failure,
            mappedState: state,
            visibleSummary: failure.summary
        )
    }

    func cleanUserFacingText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lower = trimmed.lowercased()

        if lower.contains("relationshipled") ||
            lower.contains("localservice") ||
            lower.contains("physicalgoods") ||
            lower.contains("digitalservice") ||
            lower.contains("informationrequest") ||
            lower.contains("selection ") ||
            lower.contains("high-fit-preferred") ||
            lower.contains("number multiple") ||
            lower.contains("targetkind=") ||
            lower.contains("markettype=") ||
            lower.contains("fulfillmentmode=") ||
            lower.contains("risklevel=") {
            exFailureLog("cleanUserFacingText dropped internal taxonomy text")
            return ""
        }

        let cleaned = trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned != trimmed {
            exFailureLog("cleanUserFacingText normalized text")
        }

        return cleaned
    }

    func resolveDiscovery(_ input: FailureInput) -> Resolution {
        let nextStep = mapRecommendation(
            input.recommendation,
            fallback: .refineSearch(suggestion: "Refine the search criteria or widen the search scope.")
        )

        let summary = normalizedSummary(
            input.summary,
            fallback: "I understood the request, but could not find strong candidates."
        )

        let happened = cleanUserFacingText(
            input.detail ?? "A delivery attempt or send progression failed to complete."
        )

        let failure = ExchangeFailure.discovery(
            summary: summary,
            whatHappened: happened,
            whatDidNotHappen: "No strong candidate was advanced and no contact was made.",
            nextStep: nextStep,
            reasonCode: input.reasonCode
        )

        let state = ExchangeState.noViableMatch(
            ExchangeState.NoMatchStatus(
                explanation: summary,
                suggestedNextStep: nextStep.summaryLine
            )
        )

        exFailureLog(
            "resolveDiscovery nextStep=\(nextStep.summaryLine) summary=\(summary)"
        )

        return Resolution(
            failure: failure,
            mappedState: state,
            visibleSummary: summary
        )
    }

    func resolveFit(_ input: FailureInput) -> Resolution {
        let reason: String = {
            if case .reviewMismatch(let value) = mapRecommendation(
                input.recommendation,
                fallback: .reviewMismatch(reason: "The available candidates do not fit strongly enough.")
            ) {
                let cleaned = cleanUserFacingText(value)
                return cleaned.isEmpty ? "The available candidates do not fit strongly enough." : cleaned
            }
            return "The available candidates do not fit strongly enough."
        }()

        let summary = normalizedSummary(
            input.summary,
            fallback: "Candidates exist, but none are a strong enough fit right now."
        )

        let happened = cleanUserFacingText(
            input.detail ?? "Candidate evaluation completed, but no candidate cleared the fit threshold."
        )

        let failure = ExchangeFailure.fit(
            summary: summary,
            whatHappened: happened,
            mismatchReason: reason,
            reasonCode: input.reasonCode
        )

        let state = ExchangeState.matchCandidatesWeak(
            ExchangeState.WeakMatchStatus(
                candidateCount: 0,
                explanation: summary,
                suggestedRefinement: reason
            )
        )

        exFailureLog(
            "resolveFit mismatchReason=\(reason) summary=\(summary)"
        )

        return Resolution(
            failure: failure,
            mappedState: state,
            visibleSummary: summary
        )
    }

    func resolveDelivery(_ input: FailureInput) -> Resolution {
        let nextStep = mapRecommendation(
            input.recommendation,
            fallback: .retryDelivery
        )

        let summary = normalizedSummary(
            input.summary,
            fallback: "The thread could not progress through delivery."
        )

        let happened = input.detail ?? "A delivery attempt or send progression failed to complete."

        let whatDidNotHappen: String = {
            switch input.externalEffect {
            case .none:
                return "No message was sent."
            case .attemptedButNotConfirmed:
                return "Confirmed delivery did not occur."
            case .sent:
                return "The thread did not progress beyond outbound delivery."
            case .partiallyChanged:
                return "Delivery did not complete cleanly."
            case .changed:
                return "The intended coordination outcome was not completed."
            }
        }()

        let isRetryable: Bool = {
            switch nextStep {
            case .retryDelivery, .waitAndRetry:
                return true
            default:
                return false
            }
        }()

        let failure = ExchangeFailure.delivery(
            summary: summary,
            whatHappened: happened,
            whatDidNotHappen: whatDidNotHappen,
            externalEffect: input.externalEffect,
            nextStep: nextStep,
            reasonCode: input.reasonCode,
            technicalDetails: input.technicalDetails,
            isRetryable: isRetryable
        )

        let state = ExchangeState.blockedByDeliveryFailure(
            ExchangeState.DeliveryFailureStatus(
                failureID: failure.id,
                deliveryWasAttempted: input.externalEffect != .none
            )
        )

        exFailureLog(
            "resolveDelivery nextStep=\(nextStep.summaryLine) retryable=\(isRetryable) externalEffect=\(input.externalEffect)"
        )

        return Resolution(
            failure: failure,
            mappedState: state,
            visibleSummary: summary
        )
    }

    func resolveNegotiation(_ input: FailureInput) -> Resolution {
        let nextStep = mapRecommendation(
            input.recommendation,
            fallback: .closeThread(reason: "This thread did not reach alignment.")
        )

        let summary = normalizedSummary(
            input.summary,
            fallback: "The thread occurred, but did not lead to alignment."
        )

        let happened = cleanUserFacingText(
            input.detail ?? "The exchange progressed far enough to evaluate fit, but did not reach alignment."
        )

        let failure = ExchangeFailure.negotiation(
            summary: summary,
            whatHappened: happened,
            nextStep: nextStep,
            reasonCode: input.reasonCode
        )

        let state: ExchangeState = {
            switch nextStep {
            case .closeThread:
                return .declined(
                    ExchangeState.DeclineStatus(reasonSummary: summary)
                )
            default:
                return .stalled(
                    ExchangeState.StallStatus(reasonSummary: summary)
                )
            }
        }()

        exFailureLog(
            "resolveNegotiation nextStep=\(nextStep.summaryLine) mappedState=\(ExchangeTransition.ExchangeStateKey(state).rawValue)"
        )

        return Resolution(
            failure: failure,
            mappedState: state,
            visibleSummary: summary
        )
    }

    func resolveSystem(_ input: FailureInput) -> Resolution {
        let nextStep = mapRecommendation(
            input.recommendation,
            fallback: .seekRecovery
        )

        let summary = normalizedSummary(
            input.summary,
            fallback: "A system problem interrupted the thread."
        )

        let happened = input.detail ?? "A technical failure occurred while attempting to progress the request."

        let whatDidNotHappen: String = {
            switch input.externalEffect {
            case .none:
                return "No external action was confirmed."
            case .attemptedButNotConfirmed:
                return "No confirmed completion was recorded."
            case .sent:
                return "The system could not confirm full downstream completion."
            case .partiallyChanged:
                return "The system could not complete the intended sequence cleanly."
            case .changed:
                return "The system did not complete the request cleanly."
            }
        }()

        let failure = ExchangeFailure.system(
            summary: summary,
            whatHappened: happened,
            whatDidNotHappen: whatDidNotHappen,
            externalEffect: input.externalEffect,
            nextStep: nextStep,
            reasonCode: input.reasonCode,
            technicalDetails: input.technicalDetails
        )

        let state = ExchangeState.blockedBySystemFailure(
            ExchangeState.SystemFailureStatus(failureID: failure.id)
        )

        exFailureLog(
            "resolveSystem nextStep=\(nextStep.summaryLine) externalEffect=\(input.externalEffect)"
        )

        return Resolution(
            failure: failure,
            mappedState: state,
            visibleSummary: summary
        )
    }

    func mapRecommendation(
        _ recommendation: Recommendation,
        fallback: ExchangeFailure.NextStep
    ) -> ExchangeFailure.NextStep {
        let mapped: ExchangeFailure.NextStep

        switch recommendation {
        case .clarify(let question):
            mapped = .clarify(question: question)
        case .refineSearch(let suggestion):
            mapped = .refineSearch(suggestion: suggestion)
        case .widenSearch(let suggestion):
            mapped = .widenSearch(suggestion: suggestion)
        case .retrySoon:
            mapped = .waitAndRetry(after: .soon)
        case .retryLater:
            mapped = .waitAndRetry(after: .tomorrow)
        case .reviewMismatch(let reason):
            mapped = .reviewMismatch(reason: reason)
        case .sendFollowUp:
            mapped = .considerFollowUp
        case .closeThread(let reason):
            mapped = .closeThread(reason: reason)
        case .contactSupport:
            mapped = .manualIntervention(note: "Contact support.")
        case .none:
            mapped = fallback
        }

        exFailureLog("mapRecommendation input=\(recommendation) mapped=\(mapped.summaryLine)")
        return mapped
    }

    func normalizedSummary(_ summary: String, fallback: String) -> String {
        let cleaned = cleanUserFacingText(summary)
        let final = cleaned.isEmpty ? fallback : cleaned
        if cleaned.isEmpty {
            exFailureLog("normalizedSummary used fallback=\(fallback)")
        }
        return final
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
