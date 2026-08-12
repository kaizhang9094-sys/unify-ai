import Foundation

/// Provider-side inbox/intake card projection.
///
/// This lets provider secretary mode feel like a real inbound operator surface,
/// not just a generic message relay.
public struct ExchangeProviderInboxCardViewModel: Codable, Hashable, Sendable {
    public enum LeadStrength: String, Codable, CaseIterable, Hashable, Sendable {
        case weak
        case promising
        case strong
    }

    public var title: String
    public var subtitle: String
    public var inquirySummary: String?
    public var requesterAsk: String?
    public var matchedAnchor: String?
    public var leadStrength: LeadStrength
    public var answerabilityStatus: String?
    public var escalationReason: String?
    public var nextMove: ExchangeNextMoveViewModel?

    public init(
        title: String,
        subtitle: String,
        inquirySummary: String? = nil,
        requesterAsk: String? = nil,
        matchedAnchor: String? = nil,
        leadStrength: LeadStrength,
        answerabilityStatus: String? = nil,
        escalationReason: String? = nil,
        nextMove: ExchangeNextMoveViewModel? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.inquirySummary = inquirySummary
        self.requesterAsk = requesterAsk
        self.matchedAnchor = matchedAnchor
        self.leadStrength = leadStrength
        self.answerabilityStatus = answerabilityStatus
        self.escalationReason = escalationReason
        self.nextMove = nextMove
    }
}

public extension ExchangeProviderInboxCardViewModel {
    init(
        inquiry: ExchangeInboundInquiry?,
        qualification: ExchangeOpportunityQualification,
        plan: ExchangeSecondHalfPlan,
        escalationReason: String?
    ) {
        self.init(
            inquiry: inquiry,
            qualification: qualification,
            plan: plan,
            answerabilityStatusOverride: nil,
            escalationReason: escalationReason,
            nextMove: ExchangeNextMoveViewModel(plan: plan)
        )
    }

    /// Pass 2 augmentation: optional overrides from deterministic provider answerability.
    init(
        inquiry: ExchangeInboundInquiry?,
        qualification: ExchangeOpportunityQualification,
        plan: ExchangeSecondHalfPlan,
        answerabilityStatusOverride: String?,
        escalationReason: String?,
        nextMove: ExchangeNextMoveViewModel?
    ) {
        let strength: LeadStrength
        switch qualification.qualityTier {
        case .weak:
            strength = .weak
        case .promising:
            strength = .promising
        case .strong, .decisionReady:
            strength = .strong
        }

        let move = nextMove ?? ExchangeNextMoveViewModel(plan: plan)

        let trimmedAnchor = inquiry?.matchedOfferOrProfileAnchor?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryTrimmed = inquiry?.inquirySummary
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let askTrimmed = inquiry?.requesterAsk
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let title: String
        if let anchor = trimmedAnchor, !anchor.isEmpty {
            title = Self.clippedLine(anchor, maxScalars: 80)
        } else if !summaryTrimmed.isEmpty {
            title = Self.clippedLine(summaryTrimmed, maxScalars: 72)
        } else {
            title = "New inquiry"
        }

        let strengthFallback = qualification.strengthReasons.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var subtitlePrimary = askTrimmed
        if subtitlePrimary.isEmpty, !summaryTrimmed.isEmpty,
           Self.normalizeWhitespace(summaryTrimmed) != Self.normalizeWhitespace(title) {
            subtitlePrimary = summaryTrimmed
        }
        if subtitlePrimary.isEmpty, let strengthFallback, !strengthFallback.isEmpty {
            subtitlePrimary = strengthFallback
        }
        if subtitlePrimary.isEmpty {
            subtitlePrimary = "Provider-side review in progress."
        }

        var subtitlePieces: [String] = [subtitlePrimary]
        let escalationTrimmed = escalationReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let escalationTrimmed, !escalationTrimmed.isEmpty,
           !subtitlePrimary.localizedCaseInsensitiveContains(escalationTrimmed) {
            subtitlePieces.append(escalationTrimmed)
        }

        let answerabilityTrimmed = answerabilityStatusOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let answerabilityTrimmed, !answerabilityTrimmed.isEmpty,
           !subtitlePrimary.localizedCaseInsensitiveContains(answerabilityTrimmed),
           !(escalationTrimmed?.localizedCaseInsensitiveContains(answerabilityTrimmed) ?? false) {
            subtitlePieces.append(answerabilityTrimmed)
        }

        let subtitle = subtitlePieces.joined(separator: " · ")

        self.init(
            title: title,
            subtitle: subtitle,
            inquirySummary: inquiry?.inquirySummary,
            requesterAsk: inquiry?.requesterAsk,
            matchedAnchor: inquiry?.matchedOfferOrProfileAnchor,
            leadStrength: strength,
            answerabilityStatus: answerabilityStatusOverride ?? inquiry?.answerabilityStatus.rawValue,
            escalationReason: escalationReason,
            nextMove: move
        )
    }

    private static func normalizeWhitespace(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    private static func clippedLine(_ value: String, maxScalars: Int) -> String {
        guard value.count > maxScalars else { return value }
        let clipped = String(value.prefix(maxScalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped + "…"
    }

    var isStrongLead: Bool {
        leadStrength == .strong
    }

    var needsAttention: Bool {
        escalationReason != nil || nextMove?.isBlockingOnHuman == true
    }
}
