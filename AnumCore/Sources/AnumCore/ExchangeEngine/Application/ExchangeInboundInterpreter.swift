import Foundation

/// Lightweight semantic interpreter for inbound counterparty messages.
///
/// This is intentionally narrow.
/// It should classify what changed in the thread, not generate prose.
public struct ExchangeInboundInterpreter: Sendable {
    public init() {}

    public func interpret(
        summary: String,
        body: String,
        thread: ExchangeThread,
        expectation: ExchangeExpectation
    ) -> Result {
        let raw = [summary, body]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = raw.lowercased()
        let facets = thread.facets

        if raw.isEmpty {
            return Result(
                disposition: .ambiguous,
                summary: "Inbound message was empty or unusable.",
                requiresReply: false,
                suggestedDraftKind: nil,
                detectedSignals: [],
                extractedQuestion: nil,
                extractedProposal: nil,
                rationale: "No reliable inbound content was available to interpret."
            )
        }

        if containsAny(lower, [
            "not interested", "no thanks", "pass", "decline", "can't help", "cannot help",
            "not a fit", "won't work", "do not want", "don't want"
        ]) {
            return Result(
                disposition: .declined,
                summary: "Counterparty declined or indicated no fit.",
                requiresReply: false,
                suggestedDraftKind: nil,
                detectedSignals: [.explicitDecline],
                extractedQuestion: nil,
                extractedProposal: nil,
                rationale: "Inbound text contains a clear decline or disqualification signal."
            )
        }

        if containsAny(lower, [
            "contract", "agreement", "terms", "deposit", "payment terms",
            "sign", "invoice", "wire", "etransfer", "e-transfer",
            "purchase order", "po", "counteroffer", "minimum order"
        ]) {
            return Result(
                disposition: .needsApproval,
                summary: "Counterparty introduced commitment-bearing or contractual material.",
                requiresReply: false,
                suggestedDraftKind: .negotiation,
                detectedSignals: [],
                extractedQuestion: extractQuestion(from: raw),
                extractedProposal: nil,
                rationale: "Inbound text moved into higher-risk territory that should pause for the user."
            )
        }

        if containsAny(lower, [
            "quote", "$", "price", "pricing", "estimate", "cost", "rate", "rates"
        ]) {
            if containsAny(lower, [
                "attached", "here is", "our quote", "pricing is", "estimate is",
                "it will be", "total is", "cost is", "rate is"
            ]) {
                return Result(
                    disposition: .completed,
                    summary: "Counterparty appears to have provided pricing or quote information.",
                    requiresReply: false,
                    suggestedDraftKind: nil,
                    detectedSignals: [.quoteReceived],
                    extractedQuestion: extractQuestion(from: raw),
                    extractedProposal: nil,
                    rationale: "Inbound text appears to provide quote-bearing information."
                )
            }

            let extractedQuestion = extractQuestion(from: raw)
            if containsQuestion(lower) || containsAny(lower, [
                "need more info", "need details", "need dimensions",
                "need quantity", "need your budget", "what budget"
            ]) {
                if isRoutineClarification(
                    lower,
                    thread: thread,
                    expectation: expectation,
                    facets: facets
                ) {
                    return Result(
                        disposition: .progressed,
                        summary: "Counterparty needs small routine details before continuing.",
                        requiresReply: true,
                        suggestedDraftKind: .quoteRequest,
                        detectedSignals: [],
                        extractedQuestion: extractedQuestion,
                        extractedProposal: nil,
                        rationale: "Inbound text requests routine quote-enabling details that may be handled within bounded continuation."
                    )
                }

                return Result(
                    disposition: .needsUserInput,
                    summary: "Counterparty needs more information before quoting.",
                    requiresReply: false,
                    suggestedDraftKind: nil,
                    detectedSignals: [],
                    extractedQuestion: extractedQuestion,
                    extractedProposal: nil,
                    rationale: "Quote flow is blocked pending missing user information or a higher-judgment answer."
                )
            }
        }

        if containsAny(lower, [
            "available", "availability", "free", "open slot", "works for me", "that works"
        ]) {
            let proposal = extractSchedulingProposal(from: raw)
            return Result(
                disposition: .progressed,
                summary: "Counterparty provided availability or a workable time signal.",
                requiresReply: proposal != nil,
                suggestedDraftKind: .scheduling,
                detectedSignals: proposal == nil ? [.availabilityConfirmed] : [.meetingProposed],
                extractedQuestion: extractQuestion(from: raw),
                extractedProposal: proposal,
                rationale: "Inbound text indicates scheduling progress."
            )
        }

        if containsQuestion(lower) || containsAny(lower, [
            "can you send", "could you send", "please send", "what is", "which one",
            "how many", "where", "when", "who", "what size", "what quantity",
            "what dimensions", "what specs", "what model", "which date", "which time"
        ]) {
            let extractedQuestion = extractQuestion(from: raw)

            if isRoutineClarification(
                lower,
                thread: thread,
                expectation: expectation,
                facets: facets
            ) {
                return Result(
                    disposition: .progressed,
                    summary: "Counterparty asked for routine clarification that may support bounded continuation.",
                    requiresReply: true,
                    suggestedDraftKind: suggestedDraftKind(for: thread),
                    detectedSignals: [],
                    extractedQuestion: extractedQuestion,
                    extractedProposal: nil,
                    rationale: "Inbound text asks for operational details that do not appear to require expanded commitment or disclosure."
                )
            }

            return Result(
                disposition: .needsUserInput,
                summary: "Counterparty is asking for additional information.",
                requiresReply: false,
                suggestedDraftKind: nil,
                detectedSignals: [],
                extractedQuestion: extractedQuestion,
                extractedProposal: nil,
                rationale: "Inbound text contains a question or missing-information request that should return to the user."
            )
        }

        if containsAny(lower, [
            "yes", "sounds good", "works", "let's do it", "happy to", "can do",
            "we can help", "we do that", "that is within scope"
        ]) {
            return Result(
                disposition: .progressed,
                summary: "Counterparty signaled positive fit or willingness to proceed.",
                requiresReply: true,
                suggestedDraftKind: suggestedDraftKind(for: thread),
                detectedSignals: [.capabilityConfirmed],
                extractedQuestion: extractQuestion(from: raw),
                extractedProposal: nil,
                rationale: "Inbound text indicates positive thread progress."
            )
        }

        return Result(
            disposition: .ambiguous,
            summary: "Inbound message was received but did not map cleanly to a safe next step.",
            requiresReply: false,
            suggestedDraftKind: nil,
            detectedSignals: [],
            extractedQuestion: extractQuestion(from: raw),
            extractedProposal: nil,
            rationale: "The message may contain signal, but not enough for safe bounded continuation."
        )
    }
}

public extension ExchangeInboundInterpreter {
    struct Result: Sendable, Hashable {
        public var disposition: Disposition
        public var summary: String
        public var requiresReply: Bool
        public var suggestedDraftKind: ExchangeMessageDraft.Kind?
        public var detectedSignals: [ExchangeExpectation.CompletionSignal]
        public var extractedQuestion: String?
        public var extractedProposal: String?
        public var rationale: String?

        public init(
            disposition: Disposition,
            summary: String,
            requiresReply: Bool,
            suggestedDraftKind: ExchangeMessageDraft.Kind?,
            detectedSignals: [ExchangeExpectation.CompletionSignal],
            extractedQuestion: String?,
            extractedProposal: String?,
            rationale: String? = nil
        ) {
            self.disposition = disposition
            self.summary = summary
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.requiresReply = requiresReply
            self.suggestedDraftKind = suggestedDraftKind
            self.detectedSignals = detectedSignals
            self.extractedQuestion = extractedQuestion?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
            self.extractedProposal = extractedProposal?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
            self.rationale = rationale?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
        }
    }

    enum Disposition: String, Codable, Sendable, CaseIterable, Hashable {
        case completed
        case progressed
        case declined
        case needsUserInput
        case needsApproval
        case ambiguous
    }
}

private extension ExchangeInboundInterpreter {
    func suggestedDraftKind(for thread: ExchangeThread) -> ExchangeMessageDraft.Kind {
        switch thread.intent.kind {
        case .arrangeCall, .arrangeMeeting, .invite:
            return .scheduling
        case .followUp, .checkStatus:
            return .followUp
        case .negotiate:
            return .negotiation
        case .requestQuote:
            return .quoteRequest
        case .introduce:
            return .introduction
        case .message, .find, .source, .coordinate, .plan, .other:
            return .inquiry
        }
    }

    func isRoutineClarification(
        _ lower: String,
        thread: ExchangeThread,
        expectation: ExchangeExpectation,
        facets: ExchangeIntentFacets?
    ) -> Bool {
        if !thread.canUseAutonomousClarification {
            return false
        }

        if !expectation.allowsAutonomousClarification {
            return false
        }

        if expectation.isHighJudgment {
            return false
        }

        if containsAny(lower, [
            "budget", "maximum budget", "deposit", "payment", "pay", "price target",
            "contract", "agreement", "sign", "legal name", "full address",
            "credit card", "bank", "wire", "etransfer", "e-transfer"
        ]) {
            return false
        }

        if containsAny(lower, [
            "quantity", "dimensions", "size", "spec", "specs", "model",
            "date", "time", "availability", "location", "address"
        ]) {
            return true
        }

        if let fulfillment = facets?.fulfillmentMode {
            switch fulfillment {
            case .localOnly, .localPreferred:
                if containsAny(lower, ["where", "location", "address", "when", "time"]) {
                    return true
                }
            case .remoteFriendly, .digitalDelivery, .shippable, .unknown:
                break
            }
        }

        if thread.intent.kind == .arrangeCall || thread.intent.kind == .arrangeMeeting {
            if containsAny(lower, ["when", "what time", "which day", "availability"]) {
                return true
            }
        }

        if thread.intent.kind == .requestQuote {
            if containsAny(lower, ["quantity", "dimensions", "size", "spec", "specs", "model"]) {
                return true
            }
        }

        return false
    }

    func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    func containsQuestion(_ text: String) -> Bool {
        text.contains("?")
    }

    func extractQuestion(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let qIndex = trimmed.firstIndex(of: "?") else { return nil }

        let prefix = trimmed[..<trimmed.index(after: qIndex)]
        let candidate = String(prefix.suffix(180))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return candidate.isEmpty ? nil : candidate
    }

    func extractSchedulingProposal(from text: String) -> String? {
        let lowered = text.lowercased()
        let markers = [
            "tomorrow", "monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "sunday", "am", "pm"
        ]

        guard markers.contains(where: { lowered.contains($0) }) else { return nil }

        let clipped = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        return clipped.isEmpty ? nil : clipped
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
