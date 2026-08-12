import Foundation

// MARK: - Subject resolver

/// Resolves user-facing opportunity / request subject for requester autonomous outbound copy.
public enum RequesterOutboundSubjectResolver: Sendable {

    public enum TitleSource: String, Sendable {
        case requestCaptured
        case humanRequesterText
        case intentObjective
        case offerTitle
        case profileDisplayName
        case counterpartyName
        case sanitizedThreadTitle
        case fallbackThisOpportunity
    }

    public struct Result: Sendable, Equatable {
        public var label: String
        public var source: TitleSource
        public var usedCapturedRequest: Bool
        public var genericRejected: Bool

        public init(label: String, source: TitleSource, usedCapturedRequest: Bool, genericRejected: Bool) {
            self.label = label
            self.source = source
            self.usedCapturedRequest = usedCapturedRequest
            self.genericRejected = genericRejected
        }
    }

    public static func resolve(
        thread: ExchangeThread,
        turns: [ExchangeTurn],
        offer: ExchangeOffer?,
        publicProfile: ExchangePublicNodeProfile?,
        counterpartyDisplayName: String?
    ) -> Result {
        let rawTitle = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericRejected = ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(rawTitle)

        if let captured = ExchangeThreadCardTitleProjection.requestCapturedText(from: turns)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !captured.isEmpty,
           !ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(captured) {
            logSubject(threadID: thread.id, source: .requestCaptured, label: captured, genericRejected: genericRejected)
            return Result(label: captured, source: .requestCaptured, usedCapturedRequest: true, genericRejected: genericRejected)
        }

        let human = thread.humanRequesterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !human.isEmpty,
           !isNonUserFacingRequesterFallback(human),
           !ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(human) {
            logSubject(threadID: thread.id, source: .humanRequesterText, label: human, genericRejected: genericRejected)
            return Result(label: human, source: .humanRequesterText, usedCapturedRequest: false, genericRejected: genericRejected)
        }

        let objective = thread.intent.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        if !objective.isEmpty,
           !ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(objective) {
            logSubject(threadID: thread.id, source: .intentObjective, label: objective, genericRejected: genericRejected)
            return Result(label: objective, source: .intentObjective, usedCapturedRequest: false, genericRejected: genericRejected)
        }

        let opportunity = RequesterInquiryOpportunityLabel.resolve(
            offer: offer,
            publicProfile: publicProfile,
            counterpartyDisplayName: counterpartyDisplayName
        )
        if opportunity.source != .fallbackThisOpportunity {
            let source: TitleSource = switch opportunity.source {
            case .offerTitle: .offerTitle
            case .profileDisplayName: .profileDisplayName
            case .counterpartyName: .counterpartyName
            case .fallbackThisOpportunity: .fallbackThisOpportunity
            }
            logSubject(threadID: thread.id, source: source, label: opportunity.label, genericRejected: genericRejected)
            return Result(
                label: opportunity.label,
                source: source,
                usedCapturedRequest: false,
                genericRejected: genericRejected
            )
        }

        if !rawTitle.isEmpty,
           !genericRejected,
           let sanitized = ExchangeUserFacingCopySanitizer.sanitize(rawTitle, field: .title),
           !sanitized.isEmpty,
           !ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(sanitized) {
            logSubject(threadID: thread.id, source: .sanitizedThreadTitle, label: sanitized, genericRejected: false)
            return Result(label: sanitized, source: .sanitizedThreadTitle, usedCapturedRequest: false, genericRejected: false)
        }

        logSubject(
            threadID: thread.id,
            source: .fallbackThisOpportunity,
            label: opportunity.label,
            genericRejected: genericRejected
        )
        return Result(
            label: opportunity.label,
            source: .fallbackThisOpportunity,
            usedCapturedRequest: false,
            genericRejected: genericRejected
        )
    }

    /// Returns nil when the line is a generic scaffold title unsuitable for outbound copy.
    public static func sanitizedOutboundSubject(_ raw: String?) -> String? {
        guard let line = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
            return nil
        }
        guard !ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(line) else { return nil }
        return line
    }

    private static func isNonUserFacingRequesterFallback(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "new request" || lower == "untitled exchange"
    }

    #if DEBUG
    private static func logSubject(
        threadID: ExchangeThread.ID,
        source: TitleSource,
        label: String,
        genericRejected: Bool
    ) {
        let preview = label.replacingOccurrences(of: "\n", with: " ").prefix(160)
        Swift.print(
            "[RequesterOutboundSubject] threadID=\(threadID.uuidString) source=\(source.rawValue) labelPreview=\(preview) genericRejected=\(genericRejected)"
        )
    }
    #else
    private static func logSubject(
        threadID: ExchangeThread.ID,
        source: TitleSource,
        label: String,
        genericRejected: Bool
    ) {}
    #endif
}

// MARK: - First-contact phase

public enum RequesterOutboundPhase: Sendable {

    public static func isFirstExternalContact(
        thread: ExchangeThread,
        turns: [ExchangeTurn],
        outboxItems: [ExchangeOutboxItem] = []
    ) -> Bool {
        let hasSendConfirmed = turns.contains { $0.kind == .sendConfirmed }
        let hasReplyReceived = turns.contains {
            $0.kind == .replyReceived && $0.actor == .counterparty
        }
        let hasLastOutboundEnvelopeID = thread.lastOutboundEnvelopeID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let acknowledgedPhases: Set<ExchangeDeliveryState.Phase> = [.sent, .acknowledged]
        let hasAcknowledgedExternalOutbox = outboxItems.contains {
            $0.isActive && acknowledgedPhases.contains($0.deliveryState.phase)
        }

        return !hasSendConfirmed
            && !hasReplyReceived
            && !hasLastOutboundEnvelopeID
            && !hasAcknowledgedExternalOutbox
    }
}

// MARK: - First-contact body composer

public enum RequesterOutboundFirstContactComposer: Sendable {

    public struct Input: Sendable {
        public var greeting: String
        public var signoff: String
        public var capturedRequestText: String?
        public var subjectMatter: String
        public var counterpartyName: String?
        public var offerTitle: String?
        public var profileDisplayName: String?

        public init(
            greeting: String,
            signoff: String,
            capturedRequestText: String?,
            subjectMatter: String,
            counterpartyName: String? = nil,
            offerTitle: String? = nil,
            profileDisplayName: String? = nil
        ) {
            self.greeting = greeting
            self.signoff = signoff
            self.capturedRequestText = capturedRequestText
            self.subjectMatter = subjectMatter
            self.counterpartyName = counterpartyName
            self.offerTitle = offerTitle
            self.profileDisplayName = profileDisplayName
        }
    }

    public static func compose(_ input: Input) -> String {
        let askLine = userFacingAskLine(capturedRequestText: input.capturedRequestText, subjectMatter: input.subjectMatter)
        let discovery = discoveryLine(
            offerTitle: input.offerTitle,
            profileDisplayName: input.profileDisplayName
        )
        let relevance = "\(askLine)\(discovery)"
        let question = firstContactQuestion(from: input.capturedRequestText, subjectMatter: input.subjectMatter)
        let core = "\(relevance) \(question)"
        return [input.greeting, core, input.signoff]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func userFacingAskLine(capturedRequestText: String?, subjectMatter: String) -> String {
        if let captured = capturedRequestText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !captured.isEmpty,
           !ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(captured) {
            return normalizedAskPhrase(from: captured)
        }
        let subject = RequesterOutboundSubjectResolver.sanitizedOutboundSubject(subjectMatter) ?? "this opportunity"
        return "I'm reaching out about \(subject)"
    }

    private static func normalizedAskPhrase(from captured: String) -> String {
        var text = captured.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.hasPrefix("find me ") {
            text = String(text.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            return "I'm looking for \(text)"
        }
        if lower.hasPrefix("find a ") {
            text = String(text.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            return "I'm looking for a \(text)"
        }
        if lower.hasPrefix("find an ") {
            text = String(text.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            return "I'm looking for an \(text)"
        }
        if lower.hasPrefix("find ") {
            text = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            return "I'm looking for \(text)"
        }
        if lower.hasPrefix("i need ") || lower.hasPrefix("i want ") || lower.hasPrefix("i'm looking for ") {
            let first = text.prefix(1).uppercased()
            let rest = text.dropFirst()
            return "\(first)\(rest)"
        }
        return "I'm reaching out about \(text)"
    }

    private static func discoveryLine(offerTitle: String?, profileDisplayName: String?) -> String {
        if let profile = profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !profile.isEmpty {
            return " and came across your profile"
        }
        if let offer = offerTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !offer.isEmpty,
           !ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(offer) {
            return " and came across \(offer)"
        }
        return ""
    }

    private static func firstContactQuestion(from capturedRequestText: String?, subjectMatter: String) -> String {
        if let captured = capturedRequestText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !captured.isEmpty {
            if let question = trailingQuestionSentence(in: captured) {
                return question
            }
            let lower = captured.lowercased()
            if lower.contains("vc") || lower.contains("venture") || lower.contains("investor") {
                return "Are you currently open to hearing from early-stage founders?"
            }
            if lower.contains("startup") || lower.contains("founder") {
                return "Are you currently open to hearing from early-stage founders?"
            }
        }
        let subject = RequesterOutboundSubjectResolver.sanitizedOutboundSubject(subjectMatter)
        if let subject, !subject.isEmpty, subject != "this opportunity" {
            return "Are you currently open to discussing \(subject)?"
        }
        return "Are you currently open to hearing more about this?"
    }

    private static func trailingQuestionSentence(in text: String) -> String? {
        let parts = text.split(whereSeparator: { $0 == "?" })
        guard parts.count > 1 else { return nil }
        let candidate = String(parts[parts.count - 2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        return candidate + "?"
    }
}

#if DEBUG
enum RequesterOutboundBodySourceDebugLog: Sendable {
    static func log(
        threadID: ExchangeThread.ID,
        actionRaw: String,
        firstContact: Bool,
        bodySource: String,
        titleSource: String,
        containsGenericTitle: Bool
    ) {
        Swift.print(
            "[RequesterOutboundBodySource] threadID=\(threadID.uuidString) actionRaw=\(actionRaw) firstContact=\(firstContact) bodySource=\(bodySource) titleSource=\(titleSource) containsGenericTitle=\(containsGenericTitle)"
        )
    }
}
#endif
