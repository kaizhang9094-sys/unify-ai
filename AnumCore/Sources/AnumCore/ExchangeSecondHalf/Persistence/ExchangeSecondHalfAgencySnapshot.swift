import Foundation

/// Durable, bounded agency overlay for second-half detail rehydration.
///
/// This payload is designed for persistence and UI replay, not for recomputation.
public struct ExchangeSecondHalfAgencySnapshot: Codable, Hashable, Sendable {
    public struct RequesterDecisionSnapshot: Codable, Hashable, Sendable {
        public var readinessRaw: String?
        public var knownFacts: [String]
        public var missingFacts: [String]
        public var recommendedQuestions: [String]
        public var rationalePreview: String?

        public init(
            readinessRaw: String? = nil,
            knownFacts: [String] = [],
            missingFacts: [String] = [],
            recommendedQuestions: [String] = [],
            rationalePreview: String? = nil
        ) {
            self.readinessRaw = readinessRaw
            self.knownFacts = knownFacts
            self.missingFacts = missingFacts
            self.recommendedQuestions = recommendedQuestions
            self.rationalePreview = rationalePreview
        }

        enum CodingKeys: String, CodingKey {
            case readinessRaw
            case knownFacts
            case missingFacts
            case recommendedQuestions
            case rationalePreview
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            readinessRaw = try container.decodeIfPresent(String.self, forKey: .readinessRaw)
            knownFacts = try container.decodeIfPresent([String].self, forKey: .knownFacts) ?? []
            missingFacts = try container.decodeIfPresent([String].self, forKey: .missingFacts) ?? []
            recommendedQuestions = try container.decodeIfPresent([String].self, forKey: .recommendedQuestions) ?? []
            rationalePreview = try container.decodeIfPresent(String.self, forKey: .rationalePreview)
        }
    }

    public struct ProviderAnswerabilitySnapshot: Codable, Hashable, Sendable {
        public struct GroundedFactSnapshot: Codable, Hashable, Sendable {
            public var text: String
            public var sourceRaw: String
            public var field: String?

            public init(
                text: String,
                sourceRaw: String,
                field: String? = nil
            ) {
                self.text = text
                self.sourceRaw = sourceRaw
                self.field = field
            }
        }

        public var statusRaw: String?
        public var statusLabel: String?
        public var knownFactsUsed: [String]
        public var groundedFacts: [GroundedFactSnapshot]
        public var missingFacts: [String]
        public var proposedAnswerPreview: String?
        public var requiresHumanApproval: Bool
        public var allowsAutonomousDrafting: Bool
        public var allowsAutonomousSending: Bool
        public var boundaryReasonPreview: String?

        public init(
            statusRaw: String? = nil,
            statusLabel: String? = nil,
            knownFactsUsed: [String] = [],
            groundedFacts: [GroundedFactSnapshot] = [],
            missingFacts: [String] = [],
            proposedAnswerPreview: String? = nil,
            requiresHumanApproval: Bool = false,
            allowsAutonomousDrafting: Bool = false,
            allowsAutonomousSending: Bool = false,
            boundaryReasonPreview: String? = nil
        ) {
            self.statusRaw = statusRaw
            self.statusLabel = statusLabel
            self.knownFactsUsed = knownFactsUsed
            self.groundedFacts = groundedFacts
            self.missingFacts = missingFacts
            self.proposedAnswerPreview = proposedAnswerPreview
            self.requiresHumanApproval = requiresHumanApproval
            self.allowsAutonomousDrafting = allowsAutonomousDrafting
            self.allowsAutonomousSending = allowsAutonomousSending
            self.boundaryReasonPreview = boundaryReasonPreview
        }

        enum CodingKeys: String, CodingKey {
            case statusRaw
            case statusLabel
            case knownFactsUsed
            case groundedFacts
            case missingFacts
            case proposedAnswerPreview
            case requiresHumanApproval
            case allowsAutonomousDrafting
            case allowsAutonomousSending
            case boundaryReasonPreview
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            statusRaw = try container.decodeIfPresent(String.self, forKey: .statusRaw)
            statusLabel = try container.decodeIfPresent(String.self, forKey: .statusLabel)
            knownFactsUsed = try container.decodeIfPresent([String].self, forKey: .knownFactsUsed) ?? []
            groundedFacts = try container.decodeIfPresent([GroundedFactSnapshot].self, forKey: .groundedFacts) ?? []
            missingFacts = try container.decodeIfPresent([String].self, forKey: .missingFacts) ?? []
            proposedAnswerPreview = try container.decodeIfPresent(String.self, forKey: .proposedAnswerPreview)
            requiresHumanApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresHumanApproval) ?? false
            allowsAutonomousDrafting = try container.decodeIfPresent(Bool.self, forKey: .allowsAutonomousDrafting) ?? false
            allowsAutonomousSending = try container.decodeIfPresent(Bool.self, forKey: .allowsAutonomousSending) ?? false
            boundaryReasonPreview = try container.decodeIfPresent(String.self, forKey: .boundaryReasonPreview)
        }
    }

    public struct SuggestionSnapshot: Codable, Hashable, Sendable {
        public var kindRaw: String
        public var title: String
        public var summary: String
        public var requiresUserApproval: Bool
        public var canRunAutonomously: Bool
        public var riskLevel: String
        public var reasons: [String]

        public init(
            kindRaw: String,
            title: String,
            summary: String,
            requiresUserApproval: Bool,
            canRunAutonomously: Bool,
            riskLevel: String,
            reasons: [String]
        ) {
            self.kindRaw = kindRaw
            self.title = title
            self.summary = summary
            self.requiresUserApproval = requiresUserApproval
            self.canRunAutonomously = canRunAutonomously
            self.riskLevel = riskLevel
            self.reasons = reasons
        }

        enum CodingKeys: String, CodingKey {
            case kindRaw
            case title
            case summary
            case requiresUserApproval
            case canRunAutonomously
            case riskLevel
            case reasons
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kindRaw = try container.decodeIfPresent(String.self, forKey: .kindRaw) ?? ""
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
            requiresUserApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresUserApproval) ?? false
            canRunAutonomously = try container.decodeIfPresent(Bool.self, forKey: .canRunAutonomously) ?? false
            riskLevel = try container.decodeIfPresent(String.self, forKey: .riskLevel) ?? ""
            reasons = try container.decodeIfPresent([String].self, forKey: .reasons) ?? []
        }
    }

    public struct DecisionSnapshot: Codable, Hashable, Sendable {
        public var recommendedActionRaw: String?
        public var autonomyDispositionRaw: String
        public var requiresUserApproval: Bool
        public var requiresUserInput: Bool
        public var blockReasons: [String]
        public var permitReasons: [String]

        public init(
            recommendedActionRaw: String? = nil,
            autonomyDispositionRaw: String = ExchangeAgencyAutonomyDisposition.holdForUserInput.rawValue,
            requiresUserApproval: Bool = false,
            requiresUserInput: Bool = true,
            blockReasons: [String] = [],
            permitReasons: [String] = []
        ) {
            self.recommendedActionRaw = recommendedActionRaw
            self.autonomyDispositionRaw = autonomyDispositionRaw
            self.requiresUserApproval = requiresUserApproval
            self.requiresUserInput = requiresUserInput
            self.blockReasons = blockReasons
            self.permitReasons = permitReasons
        }
    }

    public var groundedFactLines: [String]
    public var suggestedQuestionLines: [String]
    public var answerabilityLine: String?
    public var requesterDecision: RequesterDecisionSnapshot?
    public var providerAnswerability: ProviderAnswerabilitySnapshot?
    public var suggestions: [SuggestionSnapshot]
    public var decision: DecisionSnapshot?
    public var autonomyHoldLine: String?
    public var autonomyHoldReason: String?
    public var gateBlocked: Bool
    public var gateReasonSlug: String?
    public var gateSuggestionKind: String?

    public init(
        groundedFactLines: [String] = [],
        suggestedQuestionLines: [String] = [],
        answerabilityLine: String? = nil,
        requesterDecision: RequesterDecisionSnapshot? = nil,
        providerAnswerability: ProviderAnswerabilitySnapshot? = nil,
        suggestions: [SuggestionSnapshot] = [],
        decision: DecisionSnapshot? = nil,
        autonomyHoldLine: String? = nil,
        autonomyHoldReason: String? = nil,
        gateBlocked: Bool = false,
        gateReasonSlug: String? = nil,
        gateSuggestionKind: String? = nil
    ) {
        self.groundedFactLines = groundedFactLines
        self.suggestedQuestionLines = suggestedQuestionLines
        self.answerabilityLine = answerabilityLine
        self.requesterDecision = requesterDecision
        self.providerAnswerability = providerAnswerability
        self.suggestions = suggestions
        self.decision = decision
        self.autonomyHoldLine = autonomyHoldLine
        self.autonomyHoldReason = autonomyHoldReason
        self.gateBlocked = gateBlocked
        self.gateReasonSlug = gateReasonSlug
        self.gateSuggestionKind = gateSuggestionKind
    }

    enum CodingKeys: String, CodingKey {
        case groundedFactLines
        case suggestedQuestionLines
        case answerabilityLine
        case requesterDecision
        case providerAnswerability
        case suggestions
        case decision
        case autonomyHoldLine
        case autonomyHoldReason
        case gateBlocked
        case gateReasonSlug
        case gateSuggestionKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groundedFactLines = try container.decodeIfPresent([String].self, forKey: .groundedFactLines) ?? []
        suggestedQuestionLines = try container.decodeIfPresent([String].self, forKey: .suggestedQuestionLines) ?? []
        answerabilityLine = try container.decodeIfPresent(String.self, forKey: .answerabilityLine)
        requesterDecision = try container.decodeIfPresent(RequesterDecisionSnapshot.self, forKey: .requesterDecision)
        providerAnswerability = try container.decodeIfPresent(ProviderAnswerabilitySnapshot.self, forKey: .providerAnswerability)
        suggestions = try container.decodeIfPresent([SuggestionSnapshot].self, forKey: .suggestions) ?? []
        decision = try container.decodeIfPresent(DecisionSnapshot.self, forKey: .decision)
        autonomyHoldLine = try container.decodeIfPresent(String.self, forKey: .autonomyHoldLine)
        autonomyHoldReason = try container.decodeIfPresent(String.self, forKey: .autonomyHoldReason)
        gateBlocked = try container.decodeIfPresent(Bool.self, forKey: .gateBlocked) ?? false
        gateReasonSlug = try container.decodeIfPresent(String.self, forKey: .gateReasonSlug)
        gateSuggestionKind = try container.decodeIfPresent(String.self, forKey: .gateSuggestionKind)
    }
}

public extension ExchangeSecondHalfAgencySnapshot {
    static func fromAssessment(
        _ assessment: ExchangeAgencyAssessment,
        autonomyHoldLine: String? = nil,
        autonomyHoldReason: String? = nil,
        gate: ExchangeAgencyAutonomousOutboundGateResult? = nil
    ) -> ExchangeSecondHalfAgencySnapshot {
        let requester = assessment.requesterDecisionNeeds.map {
            RequesterDecisionSnapshot(
                readinessRaw: $0.decisionReadiness.rawValue,
                knownFacts: cappedLines($0.knownDecisionFacts, maxCount: 24),
                missingFacts: cappedLines($0.missingDecisionFacts, maxCount: 24),
                recommendedQuestions: cappedLines($0.recommendedQuestions, maxCount: 12),
                rationalePreview: cappedText($0.rationale, maxChars: 360)
            )
        }

        let provider = assessment.providerAnswerability.map {
            ProviderAnswerabilitySnapshot(
                statusRaw: $0.answerability.rawValue,
                statusLabel: cappedText(providerAnswerabilityStatusLabel($0.answerability), maxChars: 80),
                knownFactsUsed: cappedLines($0.knownFactsUsed, maxCount: 24),
                groundedFacts: $0.groundedFacts.prefix(24).map {
                    ProviderAnswerabilitySnapshot.GroundedFactSnapshot(
                        text: cappedText($0.text, maxChars: 220) ?? "",
                        sourceRaw: $0.source.rawValue,
                        field: cappedText($0.field, maxChars: 120)
                    )
                },
                missingFacts: cappedLines($0.missingFacts, maxCount: 24),
                proposedAnswerPreview: cappedText($0.proposedAnswer, maxChars: 600),
                requiresHumanApproval: $0.requiresHumanApproval,
                allowsAutonomousDrafting: $0.allowsAutonomousDrafting,
                allowsAutonomousSending: $0.allowsAutonomousSending,
                boundaryReasonPreview: cappedText($0.boundaryReason, maxChars: 360)
            )
        }

        let suggestions = assessment.agencySuggestions.prefix(10).map { item in
            SuggestionSnapshot(
                kindRaw: item.kind.rawValue,
                title: cappedText(item.title, maxChars: 120) ?? "",
                summary: cappedText(item.summary, maxChars: 220) ?? "",
                requiresUserApproval: item.requiresUserApproval,
                canRunAutonomously: item.canRunAutonomously,
                riskLevel: cappedText(item.riskLevel, maxChars: 40) ?? "unknown",
                reasons: cappedLines(item.reasons, maxCount: 8)
            )
        }

        let decision = assessment.agencyDecision
        let decisionSnapshot = DecisionSnapshot(
            recommendedActionRaw: decision.recommendedAction?.rawValue,
            autonomyDispositionRaw: decision.autonomyDisposition.rawValue,
            requiresUserApproval: decision.requiresUserApproval,
            requiresUserInput: decision.requiresUserInput,
            blockReasons: cappedLines(decision.blockReasons, maxCount: 8),
            permitReasons: cappedLines(decision.permitReasons, maxCount: 8)
        )

        return ExchangeSecondHalfAgencySnapshot(
            groundedFactLines: cappedLines(assessment.groundedFactLines, maxCount: 24),
            suggestedQuestionLines: cappedLines(assessment.suggestedQuestionLines, maxCount: 12),
            answerabilityLine: cappedText(assessment.answerabilityLine, maxChars: 180),
            requesterDecision: requester,
            providerAnswerability: provider,
            suggestions: suggestions,
            decision: decisionSnapshot,
            autonomyHoldLine: cappedText(autonomyHoldLine, maxChars: 180),
            autonomyHoldReason: cappedText(autonomyHoldReason, maxChars: 180),
            gateBlocked: gate?.allowed == false,
            gateReasonSlug: cappedText(gate?.agencyBlockReason, maxChars: 80),
            gateSuggestionKind: cappedText(gate?.agencySuggestionKind, maxChars: 80)
        )
    }

    func toAssessment() -> ExchangeAgencyAssessment {
        let requester: ExchangeRequesterDecisionNeeds? = requesterDecision.map { item in
            ExchangeRequesterDecisionNeeds(
                knownDecisionFacts: item.knownFacts,
                missingDecisionFacts: item.missingFacts,
                recommendedQuestions: item.recommendedQuestions,
                decisionReadiness: ExchangeRequesterDecisionNeeds.Readiness(rawValue: item.readinessRaw ?? "") ?? .weak,
                rationale: item.rationalePreview ?? ""
            )
        }

        let provider: ExchangeProviderAnswerability? = providerAnswerability.map { item in
            ExchangeProviderAnswerability(
                answerability: ExchangeProviderAnswerability.Answerability(rawValue: item.statusRaw ?? "") ?? .notAnswerable,
                knownFactsUsed: item.knownFactsUsed,
                groundedFacts: item.groundedFacts.compactMap { fact in
                    guard !fact.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    guard let source = ExchangeProviderFactSource(rawValue: fact.sourceRaw) else { return nil }
                    return ExchangeProviderGroundedFact(
                        text: fact.text,
                        source: source,
                        field: fact.field
                    )
                },
                missingFacts: item.missingFacts,
                proposedAnswer: item.proposedAnswerPreview,
                requiresHumanApproval: item.requiresHumanApproval,
                allowsAutonomousDrafting: item.allowsAutonomousDrafting,
                allowsAutonomousSending: item.allowsAutonomousSending,
                boundaryReason: item.boundaryReasonPreview ?? ""
            )
        }

        let mappedSuggestions: [ExchangeAgencySuggestion] = suggestions.compactMap { item in
            guard let kind = ExchangeAgencySuggestion.Kind(rawValue: item.kindRaw) else { return nil }
            return ExchangeAgencySuggestion(
                kind: kind,
                title: item.title,
                summary: item.summary,
                requiresUserApproval: item.requiresUserApproval,
                canRunAutonomously: item.canRunAutonomously,
                riskLevel: item.riskLevel,
                reasons: item.reasons
            )
        }

        let mappedDecision: ExchangeAgencyDecision = {
            guard let decision else { return .conservativeDefault }
            let disposition = ExchangeAgencyAutonomyDisposition(
                rawValue: decision.autonomyDispositionRaw
            ) ?? .holdForUserInput
            let action = decision.recommendedActionRaw.flatMap(ExchangeSecondHalfAction.init(rawValue:))
            return ExchangeAgencyDecision(
                recommendedAction: action,
                autonomyDisposition: disposition,
                requiresUserApproval: decision.requiresUserApproval,
                requiresUserInput: decision.requiresUserInput,
                blockReasons: decision.blockReasons,
                permitReasons: decision.permitReasons
            )
        }()

        return ExchangeAgencyAssessment(
            requesterDecisionNeeds: requester,
            providerAnswerability: provider,
            groundedFactLines: groundedFactLines,
            suggestedQuestionLines: suggestedQuestionLines,
            answerabilityLine: answerabilityLine,
            agencySuggestions: mappedSuggestions,
            agencyDecision: mappedDecision
        )
    }
}

private extension ExchangeSecondHalfAgencySnapshot {
    static func cappedLines(_ input: [String], maxCount: Int) -> [String] {
        input.compactMap { cappedText($0, maxChars: 220) }.prefix(maxCount).map { $0 }
    }

    static func cappedText(_ input: String?, maxChars: Int) -> String? {
        guard let input else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxChars))
    }
}

private func providerAnswerabilityStatusLabel(
    _ status: ExchangeProviderAnswerability.Answerability
) -> String {
    switch status {
    case .answerableFromPublicFacts:
        return "Answerable from public facts"
    case .partiallyAnswerableNeedsClarification:
        return "Partially answerable"
    case .requiresProviderApproval:
        return "Needs provider approval"
    case .notAnswerable:
        return "Not answerable"
    }
}
