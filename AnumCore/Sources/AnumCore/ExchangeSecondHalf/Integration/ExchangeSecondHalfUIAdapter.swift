import Foundation

#if DEBUG
@inline(__always)
private func exchSecondHalfUILog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeSecondHalfUIAdapter] \(message())")
}
#else
@inline(__always)
private func exchSecondHalfUILog(_ message: @autoclosure () -> String) {}
#endif

/// UI bridge from the greenfield ExchangeSecondHalf subsystem to the current app UI.
///
/// Design rule:
/// this file is the only place that should translate second-half meaning into
/// current UI concepts such as cards, badges, buttons, review panels, reception
/// summaries, activity steps, and thread detail sections.
///
/// The UI should not need to know about:
/// - qualification engines
/// - commitment boundary internals
/// - provider/requester flow logic
/// - state-machine rules
/// - draft composition details
///
/// It should consume this one stable display shape.
public struct ExchangeSecondHalfUIAdapter: Sendable {
    public init() {}

    /// Shown when a snapshot metric is missing — avoids exposing internal "Unknown" wording.
    private static let insufficientSignalLabel = "Not enough signal yet"

    // MARK: - Root display model

    public struct DisplayModel: Codable, Hashable, Sendable {
        public struct PlainLanguage: Codable, Hashable, Sendable {
            public var plainStatusLabel: String
            public var plainOneLineSummary: String
            public var primaryUserQuestion: String?
            public var primaryCTA: String
            public var secondaryCTA: String?
            public var latestMeaningfulEvent: String?
            public var matchReasonChips: [String]
            public var satisfiedConditionChips: [String]
            public var unresolvedConditionChips: [String]
            public var contradictionSummary: String?
            public var impliedFlexibilitySummary: String?
            public var missingInfoSummary: String?
            public var followUpReason: String?
            public var recommendationSummary: String?
            public var decisionReadinessLabel: String?
            public var blockedReason: String?
            public var approvalReason: String?
            public var providerReplySummary: String?
            public var userActionRequired: Bool
            public var isMovingAutonomously: Bool
            public var isWaitingOnProvider: Bool
            public var isWaitingOnUser: Bool
            public var isPoorFit: Bool
            public var isPromisingButIncomplete: Bool

            public init(
                plainStatusLabel: String = "",
                plainOneLineSummary: String = "",
                primaryUserQuestion: String? = nil,
                primaryCTA: String = "Open thread",
                secondaryCTA: String? = nil,
                latestMeaningfulEvent: String? = nil,
                matchReasonChips: [String] = [],
                satisfiedConditionChips: [String] = [],
                unresolvedConditionChips: [String] = [],
                contradictionSummary: String? = nil,
                impliedFlexibilitySummary: String? = nil,
                missingInfoSummary: String? = nil,
                followUpReason: String? = nil,
                recommendationSummary: String? = nil,
                decisionReadinessLabel: String? = nil,
                blockedReason: String? = nil,
                approvalReason: String? = nil,
                providerReplySummary: String? = nil,
                userActionRequired: Bool = false,
                isMovingAutonomously: Bool = false,
                isWaitingOnProvider: Bool = false,
                isWaitingOnUser: Bool = false,
                isPoorFit: Bool = false,
                isPromisingButIncomplete: Bool = false
            ) {
                self.plainStatusLabel = plainStatusLabel
                self.plainOneLineSummary = plainOneLineSummary
                self.primaryUserQuestion = primaryUserQuestion
                self.primaryCTA = primaryCTA
                self.secondaryCTA = secondaryCTA
                self.latestMeaningfulEvent = latestMeaningfulEvent
                self.matchReasonChips = matchReasonChips
                self.satisfiedConditionChips = satisfiedConditionChips
                self.unresolvedConditionChips = unresolvedConditionChips
                self.contradictionSummary = contradictionSummary
                self.impliedFlexibilitySummary = impliedFlexibilitySummary
                self.missingInfoSummary = missingInfoSummary
                self.followUpReason = followUpReason
                self.recommendationSummary = recommendationSummary
                self.decisionReadinessLabel = decisionReadinessLabel
                self.blockedReason = blockedReason
                self.approvalReason = approvalReason
                self.providerReplySummary = providerReplySummary
                self.userActionRequired = userActionRequired
                self.isMovingAutonomously = isMovingAutonomously
                self.isWaitingOnProvider = isWaitingOnProvider
                self.isWaitingOnUser = isWaitingOnUser
                self.isPoorFit = isPoorFit
                self.isPromisingButIncomplete = isPromisingButIncomplete
            }
        }
        /// Optional because some callers may adapt directly from a projection/result
        /// before they have attached the display back onto a legacy thread.
        public var threadID: UUID?

        /// Where this second-half item should naturally appear in the current UI.
        public var placement: Placement

        /// High-level identity/summary.
        public var title: String
        public var subtitle: String
        public var summary: String

        /// Backward-compatible fields from the first lightweight adapter.
        public var postureSummary: String
        public var recommendation: String
        public var stateLabel: String
        public var roleLabel: String
        public var escalationReason: String?
        public var actionTitle: String?
        public var summaryLines: [String]

        /// Rich display sections.
        public var hero: Hero
        public var status: Status
        public var nextMove: NextMove?
        public var badges: [Badge]
        public var buttons: [ActionButton]

        public var decision: DecisionSection?
        public var providerReception: ProviderReceptionSection?
        public var requesterReview: RequesterReviewSection?
        public var operatingContext: OperatingContextSection
        public var boundary: BoundarySection
        public var style: StyleSection?
        public var draft: DraftSection?
        public var activitySteps: [ActivityStep]
        public var timelineItems: [TimelineItem]

        /// Convenience flags for current UI routing.
        public var needsHumanAttention: Bool
        public var canRunAutonomously: Bool
        public var agencyPhase: AgencyPhase?
        public var agencyPhaseTitle: String?
        public var agencyPhaseDetail: String?
        public var hasDecisionPacket: Bool
        public var hasProviderReception: Bool
        public var hasRequesterReview: Bool
        public var hasDraft: Bool
        public var isTerminal: Bool

        /// Pass 2 deterministic agency grounding (projection-only; mirrors `ExchangeSecondHalfProjection.agencyAssessment`).
        public var agencyAssessment: ExchangeAgencyAssessment?

        /// Validated closure copy for persistence round-trip (optional).
        public var requesterClosureComposedCopy: ExchangeRequesterClosureComposedCopy?
        public var plain: PlainLanguage

        public init(
            threadID: UUID? = nil,
            placement: Placement,
            title: String,
            subtitle: String,
            summary: String,
            postureSummary: String,
            recommendation: String,
            stateLabel: String,
            roleLabel: String,
            escalationReason: String? = nil,
            actionTitle: String? = nil,
            summaryLines: [String] = [],
            hero: Hero,
            status: Status,
            nextMove: NextMove? = nil,
            badges: [Badge] = [],
            buttons: [ActionButton] = [],
            decision: DecisionSection? = nil,
            providerReception: ProviderReceptionSection? = nil,
            requesterReview: RequesterReviewSection? = nil,
            operatingContext: OperatingContextSection,
            boundary: BoundarySection,
            style: StyleSection? = nil,
            draft: DraftSection? = nil,
            activitySteps: [ActivityStep] = [],
            timelineItems: [TimelineItem] = [],
            needsHumanAttention: Bool,
            canRunAutonomously: Bool,
            agencyPhase: AgencyPhase? = nil,
            agencyPhaseTitle: String? = nil,
            agencyPhaseDetail: String? = nil,
            hasDecisionPacket: Bool,
            hasProviderReception: Bool,
            hasRequesterReview: Bool,
            hasDraft: Bool,
            isTerminal: Bool,
            agencyAssessment: ExchangeAgencyAssessment? = nil,
            requesterClosureComposedCopy: ExchangeRequesterClosureComposedCopy? = nil,
            plain: PlainLanguage = .init()
        ) {
            self.threadID = threadID
            self.placement = placement
            self.title = title
            self.subtitle = subtitle
            self.summary = summary
            self.postureSummary = postureSummary
            self.recommendation = recommendation
            self.stateLabel = stateLabel
            self.roleLabel = roleLabel
            self.escalationReason = escalationReason
            self.actionTitle = actionTitle
            self.summaryLines = summaryLines
            self.hero = hero
            self.status = status
            self.nextMove = nextMove
            self.badges = badges
            self.buttons = buttons
            self.decision = decision
            self.providerReception = providerReception
            self.requesterReview = requesterReview
            self.operatingContext = operatingContext
            self.boundary = boundary
            self.style = style
            self.draft = draft
            self.activitySteps = activitySteps
            self.timelineItems = timelineItems
            self.needsHumanAttention = needsHumanAttention
            self.canRunAutonomously = canRunAutonomously
            self.agencyPhase = agencyPhase
            self.agencyPhaseTitle = agencyPhaseTitle ?? agencyPhase?.displayTitle
            self.agencyPhaseDetail = agencyPhaseDetail
            self.hasDecisionPacket = hasDecisionPacket
            self.hasProviderReception = hasProviderReception
            self.hasRequesterReview = hasRequesterReview
            self.hasDraft = hasDraft
            self.isTerminal = isTerminal
            self.agencyAssessment = agencyAssessment
            self.requesterClosureComposedCopy = requesterClosureComposedCopy
            self.plain = plain
        }
    }

    // MARK: - Placement

    public enum Placement: String, Codable, CaseIterable, Hashable, Sendable {
        case none
        case currentFocus
        case needsInput
        case needsApproval
        case providerReception
        case requesterReview
        case activeCoordination
        case decisionReady
        case recovery
        case completed
    }

    public enum AgencyPhase: String, Codable, CaseIterable, Hashable, Sendable {
        case evaluatingResult
        case clarificationReady
        case clarificationSent
        /// Requester clarification to provider exists locally only — nothing queued/sent yet.
        case providerClarificationDraftReady
        case awaitingProviderAnswer
        case providerAnswerReceived
        case finalReviewReady
        case needsUserApproval
        case needsUserInput
        case blocked
        case failed
        case stalled
        case completed
        case activeCoordination
        case unknown
    }

    // MARK: - Core sections

    public struct Hero: Codable, Hashable, Sendable {
        public var eyebrow: String
        public var title: String
        public var subtitle: String
        public var statusLine: String
        public var primaryMetric: String?
        public var secondaryMetric: String?
        public var tertiaryMetric: String?

        public init(
            eyebrow: String,
            title: String,
            subtitle: String,
            statusLine: String,
            primaryMetric: String? = nil,
            secondaryMetric: String? = nil,
            tertiaryMetric: String? = nil
        ) {
            self.eyebrow = eyebrow
            self.title = title
            self.subtitle = subtitle
            self.statusLine = statusLine
            self.primaryMetric = primaryMetric
            self.secondaryMetric = secondaryMetric
            self.tertiaryMetric = tertiaryMetric
        }
    }

    public struct Status: Codable, Hashable, Sendable {
        public var state: String
        public var role: String
        public var quality: String
        public var readiness: String
        public var leadStrength: String?
        public var reviewStrength: String?
        public var isBlocking: Bool
        public var isAutonomous: Bool
        public var isDecisionReady: Bool
        public var isTerminal: Bool

        public init(
            state: String,
            role: String,
            quality: String,
            readiness: String,
            leadStrength: String? = nil,
            reviewStrength: String? = nil,
            isBlocking: Bool,
            isAutonomous: Bool,
            isDecisionReady: Bool,
            isTerminal: Bool
        ) {
            self.state = state
            self.role = role
            self.quality = quality
            self.readiness = readiness
            self.leadStrength = leadStrength
            self.reviewStrength = reviewStrength
            self.isBlocking = isBlocking
            self.isAutonomous = isAutonomous
            self.isDecisionReady = isDecisionReady
            self.isTerminal = isTerminal
        }
    }

    public struct Badge: Codable, Hashable, Sendable, Identifiable {
        public enum Tone: String, Codable, CaseIterable, Hashable, Sendable {
            case neutral
            case active
            case success
            case warning
            case blocked
            case approval
            case privateBoundary
        }

        public var id: String
        public var title: String
        public var tone: Tone

        public init(
            id: String,
            title: String,
            tone: Tone = .neutral
        ) {
            self.id = id
            self.title = title
            self.tone = tone
        }
    }

    public struct ActionButton: Codable, Hashable, Sendable, Identifiable {
        public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
            case review
            case approve
            case decline
            case answer
            case clarify
            case editDraft
            case letSecretaryHandle
            case compare
            case pause
            case recover
            case complete
            case openThread
            case configureStyle
            case configureReception
        }

        public enum Prominence: String, Codable, CaseIterable, Hashable, Sendable {
            case primary
            case secondary
            case destructive
            case quiet
        }

        public var id: String
        public var title: String
        public var kind: Kind
        public var prominence: Prominence
        public var requiresConfirmation: Bool

        public init(
            id: String,
            title: String,
            kind: Kind,
            prominence: Prominence = .secondary,
            requiresConfirmation: Bool = false
        ) {
            self.id = id
            self.title = title
            self.kind = kind
            self.prominence = prominence
            self.requiresConfirmation = requiresConfirmation
        }
    }

    public struct NextMove: Codable, Hashable, Sendable {
        /// Human-facing action label (e.g. "Prepare decision"). UI should use this for display.
        public var action: String
        /// Canonical `ExchangeSecondHalfAction.rawValue` for autonomous / persistence paths.
        public var actionRaw: String?
        public var title: String
        public var rationale: String
        public var requiredInputs: [String]
        public var needsGeneration: Bool
        public var needsUserInput: Bool
        public var needsApproval: Bool
        public var isAutonomous: Bool
        public var isBlockingOnHuman: Bool

        public init(
            action: String,
            actionRaw: String? = nil,
            title: String,
            rationale: String,
            requiredInputs: [String] = [],
            needsGeneration: Bool,
            needsUserInput: Bool,
            needsApproval: Bool,
            isAutonomous: Bool,
            isBlockingOnHuman: Bool
        ) {
            self.action = action
            self.actionRaw = actionRaw
            self.title = title
            self.rationale = rationale
            self.requiredInputs = requiredInputs
            self.needsGeneration = needsGeneration
            self.needsUserInput = needsUserInput
            self.needsApproval = needsApproval
            self.isAutonomous = isAutonomous
            self.isBlockingOnHuman = isBlockingOnHuman
        }
    }

    // MARK: - Specialized sections

    public struct DecisionSection: Codable, Hashable, Sendable {
        public var title: String
        public var summary: String
        public var clarifiedFacts: [String]
        public var whatChanged: [String]
        public var unresolvedIssues: [String]
        public var recommendation: String
        public var tradeoffs: [String]
        public var needsUserJudgment: Bool
        public var needsCommitmentApproval: Bool
        public var requesterPause: ExchangeRequesterPauseFrame?

        public init(
            title: String = "Decision Packet",
            summary: String,
            clarifiedFacts: [String] = [],
            whatChanged: [String] = [],
            unresolvedIssues: [String] = [],
            recommendation: String,
            tradeoffs: [String] = [],
            needsUserJudgment: Bool,
            needsCommitmentApproval: Bool,
            requesterPause: ExchangeRequesterPauseFrame? = nil
        ) {
            self.title = title
            self.summary = summary
            self.clarifiedFacts = clarifiedFacts
            self.whatChanged = whatChanged
            self.unresolvedIssues = unresolvedIssues
            self.recommendation = recommendation
            self.tradeoffs = tradeoffs
            self.needsUserJudgment = needsUserJudgment
            self.needsCommitmentApproval = needsCommitmentApproval
            self.requesterPause = requesterPause
        }
    }

    public struct ProviderReceptionSection: Codable, Hashable, Sendable {
        public var title: String
        public var subtitle: String
        public var inquirySummary: String?
        public var requesterAsk: String?
        public var matchedAnchor: String?
        public var leadStrength: String
        public var answerabilityStatus: String?
        public var escalationReason: String?
        public var nextMoveTitle: String?
        public var needsAttention: Bool
        public var isStrongLead: Bool

        public init(
            title: String,
            subtitle: String,
            inquirySummary: String? = nil,
            requesterAsk: String? = nil,
            matchedAnchor: String? = nil,
            leadStrength: String,
            answerabilityStatus: String? = nil,
            escalationReason: String? = nil,
            nextMoveTitle: String? = nil,
            needsAttention: Bool,
            isStrongLead: Bool
        ) {
            self.title = title
            self.subtitle = subtitle
            self.inquirySummary = inquirySummary
            self.requesterAsk = requesterAsk
            self.matchedAnchor = matchedAnchor
            self.leadStrength = leadStrength
            self.answerabilityStatus = answerabilityStatus
            self.escalationReason = escalationReason
            self.nextMoveTitle = nextMoveTitle
            self.needsAttention = needsAttention
            self.isStrongLead = isStrongLead
        }
    }

    public struct RequesterReviewSection: Codable, Hashable, Sendable {
        public var title: String
        public var subtitle: String
        public var reviewStrength: String
        public var strengthReasons: [String]
        public var weaknessReasons: [String]
        public var missingFacts: [String]
        public var recommendation: String?
        public var nextMoveTitle: String?
        public var isDecisionReady: Bool
        public var needsMoreQualification: Bool
        public var pauseFrame: ExchangeRequesterPauseFrame?

        public init(
            title: String,
            subtitle: String,
            reviewStrength: String,
            strengthReasons: [String] = [],
            weaknessReasons: [String] = [],
            missingFacts: [String] = [],
            recommendation: String? = nil,
            nextMoveTitle: String? = nil,
            isDecisionReady: Bool,
            needsMoreQualification: Bool,
            pauseFrame: ExchangeRequesterPauseFrame? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.reviewStrength = reviewStrength
            self.strengthReasons = strengthReasons
            self.weaknessReasons = weaknessReasons
            self.missingFacts = missingFacts
            self.recommendation = recommendation
            self.nextMoveTitle = nextMoveTitle
            self.isDecisionReady = isDecisionReady
            self.needsMoreQualification = needsMoreQualification
            self.pauseFrame = pauseFrame
        }
    }

    public struct OperatingContextSection: Codable, Hashable, Sendable {
        public var title: String
        public var role: String
        public var postureSummary: String
        public var readiness: String
        public var urgency: String
        public var trust: String
        public var priceSensitivity: String
        public var flexibility: String
        public var followUpHints: [String]
        /// User- / requester-answerable gaps only (qualification + requester decision needs). Prefer this for “what the local user should answer.”
        public var missingFacts: [String]
        /// Same as `missingFacts` for new code; kept alongside for explicit call sites.
        public var userFacingMissingFacts: [String]
        /// Provider / counterparty diagnostics and similar lines — not for “ask the user” cards.
        public var diagnosticMissingFacts: [String]
        public var strengthReasons: [String]
        public var weaknessReasons: [String]

        public init(
            title: String = "Operating Context",
            role: String,
            postureSummary: String,
            readiness: String,
            urgency: String,
            trust: String,
            priceSensitivity: String,
            flexibility: String,
            followUpHints: [String] = [],
            missingFacts: [String] = [],
            userFacingMissingFacts: [String]? = nil,
            diagnosticMissingFacts: [String] = [],
            strengthReasons: [String] = [],
            weaknessReasons: [String] = []
        ) {
            self.title = title
            self.role = role
            self.postureSummary = postureSummary
            self.readiness = readiness
            self.urgency = urgency
            self.trust = trust
            self.priceSensitivity = priceSensitivity
            self.flexibility = flexibility
            self.followUpHints = followUpHints
            let explicitUF = userFacingMissingFacts?.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? []
            let resolvedUserFacing = explicitUF.isEmpty ? missingFacts : explicitUF
            self.missingFacts = resolvedUserFacing
            self.userFacingMissingFacts = resolvedUserFacing
            self.diagnosticMissingFacts = diagnosticMissingFacts
            self.strengthReasons = strengthReasons
            self.weaknessReasons = weaknessReasons
        }
    }

    public struct BoundarySection: Codable, Hashable, Sendable {
        public var title: String
        public var kind: String
        public var reason: String
        public var requiresHumanApproval: Bool
        public var allowsAutonomousDrafting: Bool
        public var allowsAutonomousSending: Bool
        public var externalEffectLine: String

        public init(
            title: String = "Boundary",
            kind: String,
            reason: String,
            requiresHumanApproval: Bool,
            allowsAutonomousDrafting: Bool,
            allowsAutonomousSending: Bool,
            externalEffectLine: String
        ) {
            self.title = title
            self.kind = kind
            self.reason = reason
            self.requiresHumanApproval = requiresHumanApproval
            self.allowsAutonomousDrafting = allowsAutonomousDrafting
            self.allowsAutonomousSending = allowsAutonomousSending
            self.externalEffectLine = externalEffectLine
        }
    }

    public struct StyleSection: Codable, Hashable, Sendable {
        public var title: String
        public var tone: String
        public var warmthDirectness: String
        public var firmness: String
        public var disclosureStyle: String
        public var initiativeLevel: String
        public var negotiationStyle: String
        public var approvalSensitivity: String
        public var freeformInstructions: String?

        public init(
            title: String = "Secretary Style",
            tone: String,
            warmthDirectness: String,
            firmness: String,
            disclosureStyle: String,
            initiativeLevel: String,
            negotiationStyle: String,
            approvalSensitivity: String,
            freeformInstructions: String? = nil
        ) {
            self.title = title
            self.tone = tone
            self.warmthDirectness = warmthDirectness
            self.firmness = firmness
            self.disclosureStyle = disclosureStyle
            self.initiativeLevel = initiativeLevel
            self.negotiationStyle = negotiationStyle
            self.approvalSensitivity = approvalSensitivity
            self.freeformInstructions = freeformInstructions
        }
    }

    public struct DraftSection: Codable, Hashable, Sendable {
        public var title: String
        public var subject: String?
        public var bodyPreview: String
        /// Full outbound body for persistence (executor uses this over truncated `bodyPreview` when set).
        public var outboundBodyFull: String?
        public var usedStructuredFacts: [String]
        public var notes: [String]
        public var requiresApprovalBeforeSending: Bool
        /// Mirrors `ExchangeDraftComposer.Draft.agencyComposePolicy` when present.
        public var agencyComposePolicy: ExchangeDraftAgencyComposePolicy?

        public init(
            title: String = "Prepared Draft",
            subject: String? = nil,
            bodyPreview: String,
            outboundBodyFull: String? = nil,
            usedStructuredFacts: [String] = [],
            notes: [String] = [],
            requiresApprovalBeforeSending: Bool,
            agencyComposePolicy: ExchangeDraftAgencyComposePolicy? = nil
        ) {
            self.title = title
            self.subject = subject
            self.bodyPreview = bodyPreview
            self.outboundBodyFull = outboundBodyFull
            self.usedStructuredFacts = usedStructuredFacts
            self.notes = notes
            self.requiresApprovalBeforeSending = requiresApprovalBeforeSending
            self.agencyComposePolicy = agencyComposePolicy
        }

        enum CodingKeys: String, CodingKey {
            case title
            case subject
            case bodyPreview
            case outboundBodyFull
            case usedStructuredFacts
            case notes
            case requiresApprovalBeforeSending
            case agencyComposePolicy
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Prepared Draft"
            subject = try c.decodeIfPresent(String.self, forKey: .subject)
            bodyPreview = try c.decodeIfPresent(String.self, forKey: .bodyPreview) ?? ""
            outboundBodyFull = try c.decodeIfPresent(String.self, forKey: .outboundBodyFull)
            usedStructuredFacts = try c.decodeIfPresent([String].self, forKey: .usedStructuredFacts) ?? []
            notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
            requiresApprovalBeforeSending =
                try c.decodeIfPresent(Bool.self, forKey: .requiresApprovalBeforeSending) ?? false
            agencyComposePolicy = try c.decodeIfPresent(
                ExchangeDraftAgencyComposePolicy.self,
                forKey: .agencyComposePolicy
            )
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(title, forKey: .title)
            try c.encodeIfPresent(subject, forKey: .subject)
            try c.encode(bodyPreview, forKey: .bodyPreview)
            try c.encodeIfPresent(outboundBodyFull, forKey: .outboundBodyFull)
            try c.encode(usedStructuredFacts, forKey: .usedStructuredFacts)
            try c.encode(notes, forKey: .notes)
            try c.encode(requiresApprovalBeforeSending, forKey: .requiresApprovalBeforeSending)
            try c.encodeIfPresent(agencyComposePolicy, forKey: .agencyComposePolicy)
        }
    }

    public struct ActivityStep: Codable, Hashable, Sendable, Identifiable {
        public enum Status: String, Codable, CaseIterable, Hashable, Sendable {
            case pending
            case active
            case completed
            case blocked
        }

        public var id: String
        public var title: String
        public var detail: String?
        public var status: Status

        public init(
            id: String,
            title: String,
            detail: String? = nil,
            status: Status
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.status = status
        }
    }

    public struct TimelineItem: Codable, Hashable, Sendable, Identifiable {
        public enum Tone: String, Codable, CaseIterable, Hashable, Sendable {
            case neutral
            case active
            case success
            case warning
            case blocked
        }

        public var id: UUID
        public var title: String
        public var summary: String
        public var tone: Tone
        public var createdAt: Date

        public init(
            id: UUID = UUID(),
            title: String,
            summary: String,
            tone: Tone = .neutral,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.summary = summary
            self.tone = tone
            self.createdAt = createdAt
        }
    }

    // MARK: - Main public builders

    /// Main builder the app should use after the second-half coordinator runs.
    public func makeDisplayModel(
        from projection: ExchangeSecondHalfProjection,
        threadID: UUID? = nil,
        styleProfile: ExchangeSecretaryStyleProfile? = nil,
        outboundSendContext: ExchangeSecondHalfOutboundSendContext? = nil
    ) -> DisplayModel {
        exchSecondHalfUILog(
            "makeDisplayModel state=\(projection.currentState.rawValue) role=\(projection.role.rawValue)"
        )

        let title = makeTitle(from: projection)
        let subtitle = makeSubtitle(from: projection, outboundSendContext: outboundSendContext)
        let recommendation = makeRecommendation(from: projection)
        let summaryLines = makeSummaryLines(from: projection)
        let summary = makeSummary(
            projection: projection,
            title: title,
            subtitle: subtitle,
            recommendation: recommendation
        )

        let nextMove = projection.nextMove.map(makeNextMove)
        let decision = projection.decisionPacket.map(makeDecisionSection)
        let providerReception = projection.providerInboxCard.map(makeProviderReceptionSection)
        let requesterReview = projection.requesterReviewCard.map(makeRequesterReviewSection)
        let boundary = makeBoundarySection(from: projection)
        let operatingContext = makeOperatingContextSection(from: projection)
        let draft = makeDraftSection(from: projection)
        let style = styleProfile.map(makeStyleSection)
        let buttons = makeButtons(from: projection)
        let placement = makePlacement(from: projection)

        let agencyProviderLocks =
            projection.agencyAssessment?.providerAnswerability?.requiresHumanApproval == true

        /// Compare-first governed grounded reply: do not treat generic “human review” chip state as blocking
        /// autonomous provider outbound when pass-2 marks the compare draft as final and autonomous.
        let providerCompareFirstSkipsStaleHumanReviewState =
            projection.role == .provider &&
            projection.agencyAssessment?.providerAnswerability?.usesCompareFirstGroundedFinalBody == true &&
            projection.nextMove?.isAutonomous == true &&
            projection.agencyAssessment?.providerAnswerability?.requiresHumanApproval != true &&
            projection.escalationReason == nil

        let needsHumanAttention =
            projection.isBlockingOnHuman ||
            projection.escalationReason != nil ||
            projection.nextMove?.needsUserInput == true ||
            projection.nextMove?.needsApproval == true ||
            (projection.currentState.isHumanReviewState && !providerCompareFirstSkipsStaleHumanReviewState) ||
            agencyProviderLocks

        let canRunAutonomously =
            projection.nextMove?.isAutonomous == true &&
            projection.escalationReason == nil &&
            !agencyProviderLocks &&
            !projection.currentState.isTerminal

        let agencyPhase = deriveAgencyPhase(
            projection: projection,
            placement: placement,
            needsHumanAttention: needsHumanAttention,
            canRunAutonomously: canRunAutonomously,
            hasDecisionPacket: decision != nil,
            hasProviderReception: providerReception != nil,
            hasRequesterReview: requesterReview != nil,
            hasDraft: draft != nil,
            outboundSendContext: outboundSendContext
        )

        let awaitingProviderPresentationHint = presentationHintAwaitingProviderUnsentDraft(
            agencyPhase: agencyPhase,
            roleDisplayTitle: projection.role.displayTitle
        )

        let status = makeStatus(
            from: projection,
            stateLabelOverride: awaitingProviderPresentationHint.stateLabelOverride
        )
        let badges = makeBadges(
            from: projection,
            stateBadgeTitleOverride: awaitingProviderPresentationHint.stateBadgeTitleOverride
        )
        let hero = makeHero(
            projection: projection,
            title: title,
            subtitle: subtitle,
            recommendation: recommendation,
            status: status,
            agencyPhase: agencyPhase
        )

        let activitySteps = makeActivitySteps(from: projection)
        let timelineItems = makeTimelineItems(
            from: projection,
            summary: summary,
            recommendation: recommendation
        )

        let agencyPhaseDetail = makeAgencyPhaseDetail(
            phase: agencyPhase,
            nextMove: nextMove,
            summary: summary,
            recommendation: recommendation
        )

        let raw = DisplayModel(
            threadID: threadID,
            placement: placement,
            title: title,
            subtitle: subtitle,
            summary: summary,
            postureSummary: projection.stance.postureSummary,
            recommendation: recommendation,
            stateLabel: awaitingProviderPresentationHint.stateLabelOverride
                ?? projection.currentState.displayTitle,
            roleLabel: projection.role.displayTitle,
            escalationReason: projection.escalationReason,
            actionTitle: projection.nextMove?.title,
            summaryLines: summaryLines,
            hero: hero,
            status: status,
            nextMove: nextMove,
            badges: badges,
            buttons: buttons,
            decision: decision,
            providerReception: providerReception,
            requesterReview: requesterReview,
            operatingContext: operatingContext,
            boundary: boundary,
            style: style,
            draft: draft,
            activitySteps: activitySteps,
            timelineItems: timelineItems,
            needsHumanAttention: needsHumanAttention,
            canRunAutonomously: canRunAutonomously,
            agencyPhase: agencyPhase,
            agencyPhaseTitle: agencyPhase.displayTitle,
            agencyPhaseDetail: agencyPhaseDetail,
            hasDecisionPacket: decision != nil,
            hasProviderReception: providerReception != nil,
            hasRequesterReview: requesterReview != nil,
            hasDraft: draft != nil,
            isTerminal: projection.currentState.isTerminal,
            agencyAssessment: projection.agencyAssessment,
            requesterClosureComposedCopy: projection.requesterClosureComposedCopy
        )
        return sanitizedUserFacingDisplayModel(withPlainLanguage(raw))
    }

    /// Convenience builder for coordinator result.
    public func makeDisplayModel(
        from result: ExchangeSecondHalfCoordinator.Result,
        inquiry: ExchangeInboundInquiry? = nil,
        threadID: UUID? = nil,
        styleProfile: ExchangeSecretaryStyleProfile? = nil,
        agencyAssessment: ExchangeAgencyAssessment? = nil,
        requesterSurfaceContext: ExchangeRequesterReviewSurfaceContext? = nil,
        outboundSendContext: ExchangeSecondHalfOutboundSendContext? = nil
    ) -> DisplayModel {
        let projection = ExchangeSecondHalfProjection(
            coordinatorResult: result,
            inquiry: inquiry,
            agencyAssessment: agencyAssessment,
            requesterSurfaceContext: requesterSurfaceContext
        )

        return makeDisplayModel(
            from: projection,
            threadID: threadID,
            styleProfile: styleProfile,
            outboundSendContext: outboundSendContext
        )
    }

    /// Read-only projection from persisted thread second-half snapshot.
    ///
    /// Guardrail:
    /// - Deterministic only.
    /// - No AI calls.
    /// - No store writes.
    public func makeDisplayModel(
        from snapshot: ExchangeThread.SecondHalfSnapshot,
        thread: ExchangeThread,
        selectedCounterpartyName: String?,
        latestDraft: ExchangeMessageDraft? = nil
    ) -> DisplayModel {
        let normalizedRole = normalizeRoleLabel(snapshot.roleRaw, thread: thread)
        let normalizedState = normalizeStateLabel(snapshot.currentStateRaw)

        let composedPersisted = snapshot.requesterClosureComposedCopy

        let recommendation = firstNonBlank(
            composedPersisted?.recommendation,
            snapshot.recommendation,
            snapshot.nextMoveRationale,
            snapshot.postureSummary,
            thread.visibleSummary
        ) ?? "No recommendation available yet."

        let summary = firstNonBlank(
            composedPersisted?.summary,
            snapshot.decisionSummary,
            snapshot.providerReceptionSummary,
            snapshot.requesterReviewSummary,
            snapshot.draftPreview,
            snapshot.postureSummary,
            thread.visibleSummary,
            thread.title
        ) ?? "No summary available yet."

        let title = firstNonBlank(
            composedPersisted?.title,
            snapshot.nextMoveTitle,
            thread.title
        ) ?? "Coordination summary"

        let subtitle = firstNonBlank(
            snapshot.providerReceptionSummary,
            snapshot.requesterReviewSummary,
            snapshot.nextMoveRationale,
            snapshot.boundaryReason,
            recommendation
        ) ?? recommendation

        let needsApproval = snapshot.requiresHumanApproval
        let needsInput = !needsApproval && snapshot.needsHumanAttention
        let needsHumanAttention = needsApproval || needsInput
        let canRunAutonomously = snapshot.canRunAutonomously && !needsHumanAttention

        let hasDecisionPacket = snapshot.decisionSummary?.nonBlank != nil || composedPersisted != nil
        let pauseFromSnapshot = ExchangeRequesterReviewPresentation.sanitizedPauseFrame(snapshot.requesterPauseFrame)
        let includesDecisionSurface = hasDecisionPacket || pauseFromSnapshot != nil
        let hasProviderReception = snapshot.providerReceptionSummary?.nonBlank != nil
        let hasRequesterReview = snapshot.requesterReviewSummary?.nonBlank != nil
        let outboundSnapshotContext = ExchangeSecondHalfOutboundSendContext(
            thread: thread,
            latestDraft: latestDraft
        )
        let hasDraft = snapshot.draftPreview?.nonBlank != nil
            || outboundSnapshotContext.hasPreparedRequesterOutboundDraft(latestDraft: latestDraft)
        let isTerminal = isTerminalState(snapshot.currentStateRaw)

        let splitAudienceSnapshotFacts = snapshot.schemaVersion >= 2
        let snapshotUserFacingLines = splitAudienceSnapshotFacts ? (snapshot.userFacingMissingFacts ?? []) : []
        let snapshotDiagnosticLines = splitAudienceSnapshotFacts ? (snapshot.diagnosticMissingFacts ?? []) : []
        let snapshotMissingCompat = splitAudienceSnapshotFacts ? snapshotUserFacingLines : snapshot.missingFacts

        let placement: Placement = {
            if isTerminal { return .completed }
            if needsApproval { return .needsApproval }
            if needsInput { return .needsInput }
            if hasProviderReception { return .providerReception }
            if hasRequesterReview { return .requesterReview }
            if hasDecisionPacket { return .decisionReady }
            if canRunAutonomously { return .activeCoordination }
            return .currentFocus
        }()

        let agencyPhase = deriveAgencyPhaseFromSnapshot(
            snapshot: snapshot,
            placement: placement,
            needsHumanAttention: needsHumanAttention,
            canRunAutonomously: canRunAutonomously,
            hasDecisionPacket: hasDecisionPacket,
            hasProviderReception: hasProviderReception,
            hasRequesterReview: hasRequesterReview,
            hasDraft: hasDraft,
            roleDisplayTitle: normalizedRole,
            outboundSendContext: outboundSnapshotContext
        )

        let snapshotAwaitingProviderHint = presentationHintAwaitingProviderUnsentDraft(
            agencyPhase: agencyPhase,
            roleDisplayTitle: normalizedRole
        )
        let snapshotStateLabelResolved = snapshotAwaitingProviderHint.stateLabelOverride ?? normalizedState

        let providerReception: ProviderReceptionSection? = hasProviderReception
            ? .init(
                title: "New message",
                subtitle: snapshot.providerReceptionSummary ?? subtitle,
                inquirySummary: snapshot.providerReceptionSummary,
                requesterAsk: nil,
                matchedAnchor: selectedCounterpartyName?.nonBlank,
                leadStrength: snapshot.providerLeadStrength ?? Self.insufficientSignalLabel,
                answerabilityStatus: nil,
                escalationReason: snapshot.escalationReason,
                nextMoveTitle: snapshot.nextMoveTitle,
                needsAttention: needsHumanAttention,
                isStrongLead: snapshot.providerLeadStrength?.lowercased().contains("strong") == true
            )
            : nil

        let requesterReview: RequesterReviewSection? = hasRequesterReview
            ? .init(
                title: firstNonBlank(composedPersisted?.title, snapshot.nextMoveTitle, thread.title) ?? "Opportunity Review",
                subtitle: snapshot.requesterReviewSummary ?? subtitle,
                reviewStrength: snapshot.requesterReviewStrength ?? Self.insufficientSignalLabel,
                strengthReasons: ExchangeRequesterReviewPresentation.sanitizedStrengthReasons(
                    snapshot.strengthReasons
                ),
                weaknessReasons: ExchangeRequesterReviewPresentation.sanitizedWeaknessReasons(
                    snapshot.weaknessReasons
                ),
                missingFacts: snapshotMissingCompat,
                recommendation: snapshot.recommendation,
                nextMoveTitle: snapshot.nextMoveTitle,
                isDecisionReady: hasDecisionPacket,
                needsMoreQualification: !snapshotMissingCompat.isEmpty,
                pauseFrame: pauseFromSnapshot
            )
            : nil

        let decision: DecisionSection? = includesDecisionSurface
            ? .init(
                summary: {
                    if let c = composedPersisted {
                        return c.summary
                    }
                    return ExchangeRequesterReviewPresentation.decisionPacketSummary(
                        frame: ExchangeDecisionFrame(
                            summary: snapshot.decisionSummary ?? summary,
                            clarifiedFacts: snapshot.clarifiedFacts,
                            whatChanged: snapshot.whatChanged,
                            unresolvedIssues: snapshot.unresolvedIssues,
                            recommendation: snapshot.recommendation ?? recommendation,
                            tradeoffs: snapshot.tradeoffs,
                            needsUserJudgment: needsHumanAttention,
                            needsCommitmentApproval: needsApproval
                        )
                    )
                }(),
                clarifiedFacts: composedPersisted.map {
                    ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines($0.answeredBullets)
                } ?? ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(
                    snapshot.clarifiedFacts
                ),
                whatChanged: ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(snapshot.whatChanged),
                unresolvedIssues: composedPersisted.map {
                    ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines($0.stillOpenBullets)
                } ?? ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(
                    snapshot.unresolvedIssues
                ),
                recommendation: {
                    let raw = (
                        composedPersisted?.recommendation ?? snapshot.recommendation ?? recommendation
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let s = ExchangeRequesterReviewPresentation.sanitizedRecommendationBlock(raw), !s.isEmpty {
                        return s
                    }
                    if !raw.isEmpty, !ExchangeRequesterReviewPresentation.containsInternalRequesterLeak(raw) {
                        return raw
                    }
                    return "Review fit, open questions, and the suggested next step."
                }(),
                tradeoffs: ExchangeRequesterReviewPresentation.sanitizedDecisionTextLines(snapshot.tradeoffs),
                needsUserJudgment: needsHumanAttention,
                needsCommitmentApproval: needsApproval,
                requesterPause: pauseFromSnapshot
            )
            : nil

        let draft: DraftSection? = hasDraft
            ? draftSectionFromSnapshot(
                snapshot: snapshot,
                latestDraft: latestDraft,
                needsApproval: needsApproval
            )
            : nil

        let display = DisplayModel(
            threadID: thread.id,
            placement: placement,
            title: title,
            subtitle: subtitle,
            summary: summary,
            postureSummary: snapshot.postureSummary ?? summary,
            recommendation: recommendation,
            stateLabel: snapshotStateLabelResolved,
            roleLabel: normalizedRole,
            escalationReason: snapshot.escalationReason,
            actionTitle: composedPersisted?.nextActionLabel ?? snapshot.nextMoveTitle,
            summaryLines: snapshot.whatChanged + snapshot.strengthReasons + snapshot.weaknessReasons,
            hero: .init(
                eyebrow: "Coordination summary",
                title: title,
                subtitle: subtitle,
                statusLine: recommendation,
                primaryMetric: snapshot.quality,
                secondaryMetric: snapshot.readiness,
                tertiaryMetric: normalizedRole
            ),
            status: .init(
                state: snapshotStateLabelResolved,
                role: normalizedRole,
                quality: snapshot.quality ?? Self.insufficientSignalLabel,
                readiness: snapshot.readiness ?? Self.insufficientSignalLabel,
                leadStrength: snapshot.providerLeadStrength,
                reviewStrength: snapshot.requesterReviewStrength,
                isBlocking: needsHumanAttention,
                isAutonomous: canRunAutonomously,
                isDecisionReady: hasDecisionPacket,
                isTerminal: isTerminal
            ),
            nextMove: snapshot.nextMoveTitle == nil && snapshot.nextMoveRationale == nil && snapshot.nextMoveActionRaw == nil
                ? nil
                : .init(
                    action: snapshot.nextMoveActionRaw.flatMap { ExchangeSecondHalfAction(rawValue: $0)?.displayTitle }
                        ?? ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                            snapshot.nextMoveActionRaw,
                            field: .status,
                            fallback: "Next step"
                        ),
                    actionRaw: snapshot.nextMoveActionRaw.flatMap { raw in
                        ExchangeSecondHalfAction(rawValue: raw) != nil ? raw : nil
                    },
                    title: composedPersisted?.nextActionLabel ?? snapshot.nextMoveTitle ?? "Next move",
                    rationale: snapshot.nextMoveRationale ?? recommendation,
                    requiredInputs: snapshot.requiredInputs,
                    needsGeneration: false,
                    needsUserInput: needsInput,
                    needsApproval: needsApproval,
                    isAutonomous: canRunAutonomously,
                    isBlockingOnHuman: needsHumanAttention
                ),
            badges: [],
            buttons: [],
            decision: decision,
            providerReception: providerReception,
            requesterReview: requesterReview,
            operatingContext: .init(
                role: normalizedRole,
                postureSummary: snapshot.postureSummary ?? summary,
                readiness: snapshot.readiness ?? Self.insufficientSignalLabel,
                urgency: snapshot.urgency ?? Self.insufficientSignalLabel,
                trust: snapshot.trust ?? selectedCounterpartyName ?? Self.insufficientSignalLabel,
                priceSensitivity: snapshot.priceSensitivity ?? Self.insufficientSignalLabel,
                flexibility: snapshot.flexibility ?? Self.insufficientSignalLabel,
                followUpHints: snapshot.requiredInputs,
                missingFacts: snapshotMissingCompat,
                userFacingMissingFacts: splitAudienceSnapshotFacts ? snapshotUserFacingLines : nil,
                diagnosticMissingFacts: snapshotDiagnosticLines,
                strengthReasons: snapshot.strengthReasons,
                weaknessReasons: snapshot.weaknessReasons
            ),
            boundary: .init(
                kind: snapshot.boundaryKind ?? "safe",
                reason: snapshot.boundaryReason ?? "No boundary reason recorded.",
                requiresHumanApproval: needsApproval,
                allowsAutonomousDrafting: !needsApproval,
                allowsAutonomousSending: canRunAutonomously,
                externalEffectLine: snapshot.externalEffectLine ?? "No external effect recorded."
            ),
            style: nil,
            draft: draft,
            activitySteps: [],
            timelineItems: [],
            needsHumanAttention: needsHumanAttention,
            canRunAutonomously: canRunAutonomously,
            agencyPhase: agencyPhase,
            agencyPhaseTitle: agencyPhase.displayTitle,
            agencyPhaseDetail: makeAgencyPhaseDetail(
                phase: agencyPhase,
                nextMove: nil,
                summary: summary,
                recommendation: recommendation
            ),
            hasDecisionPacket: includesDecisionSurface,
            hasProviderReception: hasProviderReception,
            hasRequesterReview: hasRequesterReview,
            hasDraft: hasDraft,
            isTerminal: isTerminal,
            agencyAssessment: nil,
            requesterClosureComposedCopy: composedPersisted
        )

        let idHydratedOffer =
            thread.selectedOfferID.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let idHydratedProfile =
            thread.selectedPublicProfileID.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false

        let surfaced = display.applyingSurfaceAwareOpportunityMissingFacts(
            thread: thread,
            hasHydratedOffer: idHydratedOffer,
            hasHydratedProfile: idHydratedProfile
        )
        return sanitizedUserFacingDisplayModel(withPlainLanguage(surfaced))
    }

    /// Lightweight button-only builder for UI surfaces that only need actions.
    public func makeActionButtons(
        from projection: ExchangeSecondHalfProjection
    ) -> [ActionButton] {
        makeButtons(from: projection)
    }

    /// Lightweight badge-only builder for list cells.
    public func makeBadgesOnly(
        from projection: ExchangeSecondHalfProjection
    ) -> [Badge] {
        makeBadges(from: projection)
    }

    /// Lightweight activity-only builder for your work trace / progress rail.
    public func makeActivityStepsOnly(
        from projection: ExchangeSecondHalfProjection
    ) -> [ActivityStep] {
        makeActivitySteps(from: projection)
    }

    // MARK: - Section builders

    private func makeTitle(
        from projection: ExchangeSecondHalfProjection
    ) -> String {
        switch projection.role {
        case .provider:
            return projection.providerInboxCard?.title
                ?? "Provider Reception"

        case .requester:
            if projection.currentState == .decisionReady {
                return "Decision Ready"
            }

            return projection.requesterReviewCard?.title
                ?? "Opportunity Review"
        }
    }

    private func normalizeRoleLabel(_ raw: String, thread: ExchangeThread) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let lower = trimmed.lowercased()
            if let role = ExchangeSecondHalfRole(rawValue: lower) {
                return role.displayTitle
            }
            if let role = ExchangeSecondHalfRole.allCases.first(where: {
                $0.displayTitle.caseInsensitiveCompare(trimmed) == .orderedSame
            }) {
                return role.displayTitle
            }
            return trimmed
        }
        if thread.lastInboundEnvelopeID?.nonBlank != nil {
            return ExchangeSecondHalfRole.provider.displayTitle
        }
        return Self.insufficientSignalLabel
    }

    private func normalizeStateLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Self.insufficientSignalLabel }
        if let state = ExchangeSecondHalfState(rawValue: trimmed) {
            return state.displayTitle
        }
        if let state = ExchangeSecondHalfState.allCases.first(where: {
            $0.displayTitle.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return state.displayTitle
        }
        return ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
            trimmed,
            field: .status,
            fallback: Self.insufficientSignalLabel
        )
    }

    private func isTerminalState(_ raw: String) -> Bool {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered == "accepted" ||
            lowered == "completed" ||
            lowered == "declined" ||
            lowered == "expired"
    }

    private func firstNonBlank(_ values: String?...) -> String? {
        for value in values {
            if let cleaned = value?.nonBlank {
                return cleaned
            }
        }
        return nil
    }

    private func makeSubtitle(
        from projection: ExchangeSecondHalfProjection,
        outboundSendContext: ExchangeSecondHalfOutboundSendContext?
    ) -> String {
        switch projection.role {
        case .provider:
            return projection.providerInboxCard?.subtitle
                ?? projection.nextMove?.rationale
                ?? projection.currentState.displayTitle

        case .requester:
            if projection.currentState == .awaitingProviderClarification {
                let ctx = outboundSendContext ?? ExchangeSecondHalfOutboundSendContext()
                if !ctx.hasPositiveSendProofForRequesterProviderClarification() {
                    return projection.requesterReviewCard?.subtitle
                        ?? projection.nextMove?.rationale.nonBlank
                        ?? "Draft prepared locally. Review before anything is sent externally."
                }
            }
            return projection.requesterReviewCard?.subtitle
                ?? projection.nextMove?.rationale
                ?? projection.currentState.displayTitle
        }
    }

    private func makeRecommendation(
        from projection: ExchangeSecondHalfProjection
    ) -> String {
        projection.decisionPacket?.recommendation.nonBlank
        ?? projection.requesterReviewCard?.recommendation?.nonBlank
        ?? projection.nextMove?.rationale.nonBlank
        ?? projection.providerInboxCard?.subtitle.nonBlank
        ?? "No recommendation available yet."
    }

    private func makeSummary(
        projection: ExchangeSecondHalfProjection,
        title: String,
        subtitle: String,
        recommendation: String
    ) -> String {
        if let decisionSummary = projection.decisionPacket?.summary.nonBlank {
            return decisionSummary
        }

        if let providerSummary = projection.providerInboxCard?.inquirySummary?.nonBlank {
            return providerSummary
        }

        if let requesterSummary = projection.requesterReviewCard?.subtitle.nonBlank {
            return requesterSummary
        }

        return "\(title). \(subtitle) \(recommendation)"
    }

    private func makeHero(
        projection: ExchangeSecondHalfProjection,
        title: String,
        subtitle: String,
        recommendation: String,
        status: Status,
        agencyPhase: AgencyPhase
    ) -> Hero {
        let eyebrow: String
        switch projection.role {
        case .requester:
            eyebrow = "Your opportunity"
        case .provider:
            eyebrow = "Message for you"
        }

        let statusLine: String
        if projection.isBlockingOnHuman {
            statusLine = "Needs human attention."
        } else if projection.role == .requester,
                  agencyPhase == .providerClarificationDraftReady {
            statusLine =
                "Nothing has reached the provider yet. Review your draft question before sending."
        } else if projection.nextMove?.isAutonomous == true {
            statusLine = "Secretary can continue autonomously."
        } else if projection.currentState.isTerminal {
            statusLine = "This exchange is \(projection.currentState.displayTitle.lowercased())."
        } else {
            statusLine = recommendation
        }

        return Hero(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            statusLine: statusLine,
            primaryMetric: status.quality,
            secondaryMetric: status.readiness,
            tertiaryMetric: projection.role.displayTitle
        )
    }

    private func makeStatus(
        from projection: ExchangeSecondHalfProjection,
        stateLabelOverride: String? = nil
    ) -> Status {
        Status(
            state: stateLabelOverride ?? projection.currentState.displayTitle,
            role: projection.role.displayTitle,
            quality: projection.qualification.qualityTier.displayTitle,
            readiness: projection.stance.readinessLevel.displayTitle,
            leadStrength: projection.providerInboxCard?.leadStrength.rawValue.displayTitleFromRaw,
            reviewStrength: projection.requesterReviewCard?.reviewStrength.rawValue.displayTitleFromRaw,
            isBlocking: projection.isBlockingOnHuman,
            isAutonomous: projection.nextMove?.isAutonomous == true,
            isDecisionReady: projection.qualification.isDecisionReady || projection.currentState == .decisionReady,
            isTerminal: projection.currentState.isTerminal
        )
    }

    private func makeNextMove(
        from viewModel: ExchangeNextMoveViewModel
    ) -> NextMove {
        NextMove(
            action: viewModel.action.displayTitle,
            actionRaw: viewModel.action.rawValue,
            title: viewModel.title,
            rationale: viewModel.rationale,
            requiredInputs: dedupe(viewModel.requiredInputs),
            needsGeneration: viewModel.needsGeneration,
            needsUserInput: viewModel.needsUserInput,
            needsApproval: viewModel.needsApproval,
            isAutonomous: viewModel.isAutonomous,
            isBlockingOnHuman: viewModel.isBlockingOnHuman
        )
    }

    private func makeDecisionSection(
        from packet: ExchangeDecisionPacketViewModel
    ) -> DecisionSection {
        DecisionSection(
            summary: packet.summary,
            clarifiedFacts: dedupe(packet.clarifiedFacts),
            whatChanged: dedupe(packet.whatChanged),
            unresolvedIssues: dedupe(packet.unresolvedIssues),
            recommendation: packet.recommendation,
            tradeoffs: dedupe(packet.tradeoffs),
            needsUserJudgment: packet.needsUserJudgment,
            needsCommitmentApproval: packet.needsCommitmentApproval,
            requesterPause: packet.requesterPause
        )
    }

    private func makeProviderReceptionSection(
        from card: ExchangeProviderInboxCardViewModel
    ) -> ProviderReceptionSection {
        ProviderReceptionSection(
            title: card.title,
            subtitle: card.subtitle,
            inquirySummary: card.inquirySummary?.nonBlank,
            requesterAsk: card.requesterAsk?.nonBlank,
            matchedAnchor: card.matchedAnchor?.nonBlank,
            leadStrength: card.leadStrength.rawValue.displayTitleFromRaw,
            answerabilityStatus: card.answerabilityStatus?.displayTitleFromRaw,
            escalationReason: card.escalationReason?.nonBlank,
            nextMoveTitle: card.nextMove?.title,
            needsAttention: card.needsAttention,
            isStrongLead: card.isStrongLead
        )
    }

    private func makeRequesterReviewSection(
        from card: ExchangeRequesterReviewCardViewModel
    ) -> RequesterReviewSection {
        RequesterReviewSection(
            title: card.title,
            subtitle: card.subtitle,
            reviewStrength: card.reviewStrength.rawValue.displayTitleFromRaw,
            strengthReasons: dedupe(card.strengthReasons),
            weaknessReasons: dedupe(card.weaknessReasons),
            missingFacts: dedupe(card.missingFacts),
            recommendation: card.recommendation?.nonBlank,
            nextMoveTitle: card.nextMove?.title,
            isDecisionReady: card.isDecisionReady,
            needsMoreQualification: card.needsMoreQualification,
            pauseFrame: card.pauseFrame
        )
    }

    private func makeOperatingContextSection(
        from projection: ExchangeSecondHalfProjection
    ) -> OperatingContextSection {
        let qualMissing = projection.qualification.missingFacts
        let stanceHints = projection.stance.followUpHints

        var userFacing = dedupe(qualMissing)
        var hints = dedupe(stanceHints)
        var strength = dedupe(projection.qualification.strengthReasons)
        var diagnostic: [String] = []

        if let req = projection.agencyAssessment?.requesterDecisionNeeds {
            let extraMissing = dedupe(Array(req.missingDecisionFacts.prefix(8)))
            let extraStrength = dedupe(Array(req.knownDecisionFacts.prefix(8)))
            userFacing = mergedStrings(primary: userFacing, secondary: extraMissing, cap: 16)

            hints = mergedStrings(
                primary: hints,
                secondary: req.recommendedQuestions.map { "Ask: \(trimLine($0))" },
                cap: 14
            )

            strength = mergedStrings(primary: strength, secondary: extraStrength, cap: 14)
        }

        if let prov = projection.agencyAssessment?.providerAnswerability {
            diagnostic = mergedStrings(
                primary: diagnostic,
                secondary: Array(prov.missingFacts.prefix(6)),
                cap: 12
            )

            hints = mergedStrings(
                primary: hints,
                secondary: compactHintLines(for: prov),
                cap: 16
            )
        }

        return OperatingContextSection(
            role: projection.role.displayTitle,
            postureSummary: projection.stance.postureSummary,
            readiness: projection.stance.readinessLevel.displayTitle,
            urgency: projection.stance.urgencyLevel.displayTitle,
            trust: projection.stance.trustLevel.displayTitle,
            priceSensitivity: projection.stance.priceSensitivity.displayTitle,
            flexibility: projection.stance.flexibilityLevel.displayTitle,
            followUpHints: hints,
            missingFacts: userFacing,
            userFacingMissingFacts: userFacing,
            diagnosticMissingFacts: diagnostic,
            strengthReasons: strength,
            weaknessReasons: dedupe(projection.qualification.weaknessReasons)
        )
    }

    private func mergedStrings(primary: [String], secondary: [String], cap: Int) -> [String] {
        Array(dedupe(primary + secondary).prefix(cap))
    }

    private func trimLine(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactHintLines(for prov: ExchangeProviderAnswerability) -> [String] {
        var hints: [String] = []

        if let headline = optionalDisplayLine(from: prov.answerability) {
            hints.append("Next focus: \(headline)")
        }

        if let line = optionalDisplayLine(from: prov.proposedAnswer) {
            hints.append("Brief detail: \(clippedHint(line))")
        }

        hints.append(contentsOf: prov.knownFactsUsed.prefix(4).map { trimLine($0) })

        return hints
    }

    private func optionalDisplayLine(from text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func optionalDisplayLine(from kind: ExchangeProviderAnswerability.Answerability) -> String? {
        let line = kind.pass2DisplayLabel
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return line
    }

    private func clippedHint(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count > 160 else {
            return trimmed
        }

        let end = trimmed.index(trimmed.startIndex, offsetBy: 160)
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func makeBoundarySection(
        from projection: ExchangeSecondHalfProjection
    ) -> BoundarySection {
        let requiresApproval =
            projection.escalationReason != nil ||
            projection.nextMove?.needsApproval == true ||
            projection.decisionPacket?.needsCommitmentApproval == true

        let kind: String
        let reason: String
        let allowsDrafting: Bool
        let allowsSending: Bool

        if let escalationReason = projection.escalationReason?.nonBlank {
            kind = "approvalRequired"
            reason = escalationReason
            allowsDrafting = true
            allowsSending = false
        } else if projection.nextMove?.needsApproval == true {
            kind = "approvalRequired"
            reason = projection.nextMove?.rationale ?? "This move needs approval before it proceeds."
            allowsDrafting = true
            allowsSending = false
        } else {
            kind = "safe"
            reason = "Routine non-binding coordination."
            allowsDrafting = true
            allowsSending = projection.nextMove?.isAutonomous == true
        }

        let externalEffectLine: String
        if requiresApproval {
            externalEffectLine = "Nothing commitment-bearing should leave your boundary without approval."
        } else if allowsSending {
            externalEffectLine = "This appears safe for autonomous coordination."
        } else {
            externalEffectLine = "Nothing needs to be sent externally yet."
        }

        return BoundarySection(
            kind: kind.displayTitleFromRaw,
            reason: reason,
            requiresHumanApproval: requiresApproval,
            allowsAutonomousDrafting: allowsDrafting,
            allowsAutonomousSending: allowsSending,
            externalEffectLine: externalEffectLine
        )
    }

    private func makeStyleSection(
        from style: ExchangeSecretaryStyleProfile
    ) -> StyleSection {
        StyleSection(
            tone: style.tone.rawValue.displayTitleFromRaw,
            warmthDirectness: style.warmthDirectness.rawValue.displayTitleFromRaw,
            firmness: style.firmness.rawValue.displayTitleFromRaw,
            disclosureStyle: style.disclosureStyle.rawValue.displayTitleFromRaw,
            initiativeLevel: style.initiativeLevel.rawValue.displayTitleFromRaw,
            negotiationStyle: style.negotiationStyle.rawValue.displayTitleFromRaw,
            approvalSensitivity: style.approvalSensitivity.rawValue.displayTitleFromRaw,
            freeformInstructions: style.freeformInstructions?.nonBlank
        )
    }

    private func draftSectionFromSnapshot(
        snapshot: ExchangeThread.SecondHalfSnapshot,
        latestDraft: ExchangeMessageDraft?,
        needsApproval: Bool
    ) -> DraftSection? {
        let storedBody = latestDraft?.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = firstNonBlank(
            snapshot.draftPreview,
            storedBody.isEmpty ? nil : storedBody.collapsedPreview(maxLength: 220)
        ) ?? ""
        guard !preview.isEmpty else { return nil }
        return DraftSection(
            subject: firstNonBlank(snapshot.draftSubject, latestDraft?.subject?.nonBlank),
            bodyPreview: preview,
            outboundBodyFull: storedBody.isEmpty ? nil : storedBody,
            usedStructuredFacts: snapshot.draftFactsUsed,
            notes: [],
            requiresApprovalBeforeSending: needsApproval
        )
    }

    private func makeDraftSection(
        from projection: ExchangeSecondHalfProjection
    ) -> DraftSection? {
        guard let draft = projection.pendingDraft else { return nil }

        let fullBody = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)

        return DraftSection(
            subject: draft.subject?.nonBlank,
            bodyPreview: draft.body.collapsedPreview(maxLength: 220),
            outboundBodyFull: fullBody.isEmpty ? nil : fullBody,
            usedStructuredFacts: dedupe(draft.usedStructuredFacts),
            notes: dedupe(draft.notes),
            requiresApprovalBeforeSending: projection.escalationReason != nil || projection.nextMove?.needsApproval == true,
            agencyComposePolicy: draft.agencyComposePolicy
        )
    }

    // MARK: - Badges / buttons / placement

    private func makeBadges(
        from projection: ExchangeSecondHalfProjection,
        stateBadgeTitleOverride: String? = nil
    ) -> [Badge] {
        var badges: [Badge] = []

        badges.append(
            Badge(
                id: "role",
                title: projection.role.displayTitle,
                tone: .neutral
            )
        )

        badges.append(
            Badge(
                id: "state",
                title: stateBadgeTitleOverride ?? projection.currentState.displayTitle,
                tone: badgeTone(for: projection.currentState)
            )
        )

        badges.append(
            Badge(
                id: "quality",
                title: projection.qualification.qualityTier.displayTitle,
                tone: badgeTone(for: projection.qualification.qualityTier)
            )
        )

        if projection.qualification.isDecisionReady || projection.currentState == .decisionReady {
            badges.append(
                Badge(
                    id: "decision_ready",
                    title: "Decision Ready",
                    tone: .success
                )
            )
        }

        if projection.isBlockingOnHuman {
            badges.append(
                Badge(
                    id: "needs_human",
                    title: "Needs You",
                    tone: .approval
                )
            )
        }

        if projection.escalationReason != nil {
            badges.append(
                Badge(
                    id: "approval_required",
                    title: "Approval Required",
                    tone: .approval
                )
            )
        }

        if projection.nextMove?.isAutonomous == true && !projection.isBlockingOnHuman {
            badges.append(
                Badge(
                    id: "autonomous",
                    title: "Autonomous",
                    tone: .active
                )
            )
        }

        if projection.providerInboxCard?.needsAttention == true {
            badges.append(
                Badge(
                    id: "provider_attention",
                    title: "Reception",
                    tone: .warning
                )
            )
        }

        if projection.pendingDraft != nil {
            badges.append(
                Badge(
                    id: "draft",
                    title: "Draft Ready",
                    tone: projection.escalationReason == nil ? .active : .approval
                )
            )
        }

        badges.append(
            Badge(
                id: "boundary",
                title: projection.escalationReason == nil ? "Safe Boundary" : "Boundary Check",
                tone: projection.escalationReason == nil ? .privateBoundary : .approval
            )
        )

        return dedupeBadges(badges)
    }

    private func makeButtons(
        from projection: ExchangeSecondHalfProjection
    ) -> [ActionButton] {
        var buttons: [ActionButton] = []

        let providerCompareFirstSkipsStaleHumanReviewState =
            projection.role == .provider &&
            projection.agencyAssessment?.providerAnswerability?.usesCompareFirstGroundedFinalBody == true &&
            projection.nextMove?.isAutonomous == true &&
            projection.agencyAssessment?.providerAnswerability?.requiresHumanApproval != true &&
            projection.escalationReason == nil

        let humanReviewRequiresReviewButton =
            projection.currentState.isHumanReviewState && !providerCompareFirstSkipsStaleHumanReviewState

        if projection.isBlockingOnHuman || humanReviewRequiresReviewButton {
            buttons.append(
                ActionButton(
                    id: "review",
                    title: "Review",
                    kind: .review,
                    prominence: .primary
                )
            )
        }

        if projection.nextMove?.needsApproval == true || projection.escalationReason != nil {
            buttons.append(
                ActionButton(
                    id: "approve",
                    title: "Approve",
                    kind: .approve,
                    prominence: .primary,
                    requiresConfirmation: true
                )
            )
            buttons.append(
                ActionButton(
                    id: "decline",
                    title: "Decline",
                    kind: .decline,
                    prominence: .destructive,
                    requiresConfirmation: true
                )
            )
        }

        if projection.pendingDraft != nil {
            buttons.append(
                ActionButton(
                    id: "edit_draft",
                    title: "Edit Draft",
                    kind: .editDraft,
                    prominence: .secondary
                )
            )
        }

        switch projection.nextMove?.action {
        case .askClarification:
            buttons.append(
                ActionButton(
                    id: "clarify",
                    title: "Clarify",
                    kind: .clarify,
                    prominence: .primary
                )
            )

        case .answerClarification, .autoRespond:
            buttons.append(
                ActionButton(
                    id: "answer",
                    title: "Answer",
                    kind: .answer,
                    prominence: .primary
                )
            )

        case .compareOptions:
            buttons.append(
                ActionButton(
                    id: "compare",
                    title: "Compare",
                    kind: .compare,
                    prominence: .secondary
                )
            )

        case .requestUserInput:
            buttons.append(
                ActionButton(
                    id: "review_input",
                    title: "Add Input",
                    kind: .review,
                    prominence: .primary
                )
            )

        case .markBlocked:
            buttons.append(
                ActionButton(
                    id: "recover",
                    title: "Recover",
                    kind: .recover,
                    prominence: .primary
                )
            )

        case .complete:
            buttons.append(
                ActionButton(
                    id: "complete",
                    title: "Complete",
                    kind: .complete,
                    prominence: .primary
                )
            )

        default:
            break
        }

        if projection.nextMove?.isAutonomous == true && projection.escalationReason == nil {
            buttons.append(
                ActionButton(
                    id: "let_secretary_handle",
                    title: "Let Secretary Handle",
                    kind: .letSecretaryHandle,
                    prominence: .secondary
                )
            )
        }

        if projection.role == .provider {
            buttons.append(
                ActionButton(
                    id: "configure_reception",
                    title: "Reception Settings",
                    kind: .configureReception,
                    prominence: .quiet
                )
            )
        }

        buttons.append(
            ActionButton(
                id: "configure_style",
                title: "Representation Note",
                kind: .configureStyle,
                prominence: .quiet
            )
        )

        buttons.append(
            ActionButton(
                id: "open_thread",
                title: "Open Thread",
                kind: .openThread,
                prominence: .quiet
            )
        )

        return dedupeButtons(buttons)
    }

    private func makePlacement(
        from projection: ExchangeSecondHalfProjection
    ) -> Placement {
        if projection.currentState.isTerminal {
            return .completed
        }

        if projection.currentState == .blocked || projection.currentState == .stalled {
            return .recovery
        }

        if projection.escalationReason != nil || projection.nextMove?.needsApproval == true {
            return .needsApproval
        }

        if projection.nextMove?.needsUserInput == true || projection.currentState.isHumanReviewState {
            return .needsInput
        }

        if projection.currentState == .decisionReady || projection.qualification.isDecisionReady {
            return .decisionReady
        }

        if projection.providerInboxCard != nil {
            return .providerReception
        }

        if projection.requesterReviewCard != nil {
            return .requesterReview
        }

        if projection.nextMove?.isAutonomous == true {
            return .activeCoordination
        }

        return .currentFocus
    }

    private struct AwaitingProviderPresentationHint: Sendable, Hashable {
        var stateLabelOverride: String?
        var stateBadgeTitleOverride: String?
    }

    /// Re-derives agency phase and draft-ready presentation after requester outbound queue blocked in draft-only mode.
    public func refreshDisplayAfterRequesterOutboundSendBlocked(
        display: DisplayModel,
        thread: ExchangeThread,
        latestDraft: ExchangeMessageDraft?
    ) -> DisplayModel {
        let outboundContext = ExchangeSecondHalfOutboundSendContext(
            thread: thread,
            latestDraft: latestDraft
        )
        guard outboundContext.shouldSurfacePreparedRequesterDraftWhenSendBlocked else {
            return display
        }
        guard isRequesterDisplayRole(display.status.role) else {
            return display
        }

        var refreshed = mergePreparedDraftSection(into: display, latestDraft: latestDraft)
        let draftReady = requesterOutboundDraftReadyForUI(
            hasDraft: refreshed.draft != nil || refreshed.hasDraft,
            outboundSendContext: outboundContext
        )
        guard draftReady else { return display }

        let awaitingProvider = isAwaitingProviderClarificationDisplayState(display.status.state)
            || display.nextMove?.actionRaw == ExchangeSecondHalfAction.askClarification.rawValue
        let phase: AgencyPhase
        if awaitingProvider {
            phase = .providerClarificationDraftReady
        } else if display.nextMove?.actionRaw == ExchangeSecondHalfAction.askClarification.rawValue {
            phase = .clarificationReady
        } else {
            phase = .providerClarificationDraftReady
        }

        refreshed.agencyPhase = phase
        refreshed.agencyPhaseTitle = phase.displayTitle
        refreshed.agencyPhaseDetail = makeAgencyPhaseDetail(
            phase: phase,
            nextMove: refreshed.nextMove,
            summary: refreshed.summary,
            recommendation: refreshed.recommendation
        )
        refreshed.hasDraft = true

        let presentationHint = presentationHintAwaitingProviderUnsentDraft(
            agencyPhase: phase,
            roleDisplayTitle: display.status.role
        )
        if let stateLabel = presentationHint.stateLabelOverride {
            refreshed.status.state = stateLabel
        }
        if let badgeTitle = presentationHint.stateBadgeTitleOverride,
           let stateBadgeIndex = refreshed.badges.firstIndex(where: { $0.id == "state" }) {
            refreshed.badges[stateBadgeIndex].title = badgeTitle
        }
        refreshed.hero = makeHeroFromDisplay(
            display: refreshed,
            agencyPhase: phase
        )
        return sanitizedUserFacingDisplayModel(refreshed)
    }

    private func mergePreparedDraftSection(
        into display: DisplayModel,
        latestDraft: ExchangeMessageDraft?
    ) -> DisplayModel {
        guard let latestDraft,
              latestDraft.isActionable else {
            return display
        }
        let body = latestDraft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return display }

        var refreshed = display
        if var existing = refreshed.draft {
            existing.bodyPreview = body.collapsedPreview(maxLength: 220)
            existing.outboundBodyFull = body
            if let subject = latestDraft.subject?.nonBlank {
                existing.subject = subject
            }
            existing.requiresApprovalBeforeSending = false
            refreshed.draft = existing
        } else {
            refreshed.draft = DraftSection(
                subject: latestDraft.subject?.nonBlank,
                bodyPreview: body.collapsedPreview(maxLength: 220),
                outboundBodyFull: body,
                requiresApprovalBeforeSending: false
            )
        }
        refreshed.hasDraft = true
        return refreshed
    }

    private func makeHeroFromDisplay(
        display: DisplayModel,
        agencyPhase: AgencyPhase
    ) -> Hero {
        let statusLine: String
        if display.status.isBlocking {
            statusLine = "Needs human attention."
        } else if isRequesterDisplayRole(display.status.role),
                  agencyPhase == .providerClarificationDraftReady {
            statusLine =
                "Nothing has reached the provider yet. Review your draft question before sending."
        } else if display.nextMove?.isAutonomous == true {
            statusLine = "Secretary can continue autonomously."
        } else if display.status.isTerminal {
            statusLine = "This exchange is \(display.status.state.lowercased())."
        } else {
            statusLine = display.recommendation
        }

        return Hero(
            eyebrow: display.hero.eyebrow,
            title: display.hero.title,
            subtitle: display.hero.subtitle,
            statusLine: statusLine,
            primaryMetric: display.hero.primaryMetric,
            secondaryMetric: display.hero.secondaryMetric,
            tertiaryMetric: display.hero.tertiaryMetric
        )
    }

    private func isRequesterDisplayRole(_ roleDisplayTitle: String) -> Bool {
        roleDisplayTitle.caseInsensitiveCompare(ExchangeSecondHalfRole.requester.displayTitle) == .orderedSame
    }

    private func isAwaitingProviderClarificationDisplayState(_ stateLabel: String) -> Bool {
        let normalized = stateLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("waiting on them") { return true }
        if normalized.contains("awaitingproviderclarification") { return true }
        if normalized.contains("awaiting provider clarification") { return true }
        if let parsed = ExchangeSecondHalfState(rawValue: stateLabel),
           parsed == .awaitingProviderClarification {
            return true
        }
        return ExchangeSecondHalfState.allCases.contains {
            $0.displayTitle.caseInsensitiveCompare(stateLabel) == .orderedSame
                && $0 == .awaitingProviderClarification
        }
    }

    private func requesterOutboundDraftReadyForUI(
        hasDraft: Bool,
        outboundSendContext: ExchangeSecondHalfOutboundSendContext
    ) -> Bool {
        if hasDraft {
            return true
        }
        guard outboundSendContext.hasPreparedRequesterOutboundDraft() else {
            return false
        }
        if outboundSendContext.shouldSurfacePreparedRequesterDraftWhenSendBlocked {
            return true
        }
        return !outboundSendContext.requesterOutboundExplicitlyBlockedByRecording
    }

    private func presentationHintAwaitingProviderUnsentDraft(
        agencyPhase: AgencyPhase,
        roleDisplayTitle: String
    ) -> AwaitingProviderPresentationHint {
        guard agencyPhase == .providerClarificationDraftReady,
              roleDisplayTitle.caseInsensitiveCompare(ExchangeSecondHalfRole.requester.displayTitle) == .orderedSame
        else {
            return AwaitingProviderPresentationHint()
        }
        return AwaitingProviderPresentationHint(
            stateLabelOverride: "Draft ready",
            stateBadgeTitleOverride: "Draft ready"
        )
    }

    private func deriveAgencyPhase(
        projection: ExchangeSecondHalfProjection,
        placement: Placement,
        needsHumanAttention: Bool,
        canRunAutonomously: Bool,
        hasDecisionPacket: Bool,
        hasProviderReception: Bool,
        hasRequesterReview: Bool,
        hasDraft: Bool,
        outboundSendContext: ExchangeSecondHalfOutboundSendContext?
    ) -> AgencyPhase {
        if projection.currentState.isTerminal {
            return .completed
        }

        if projection.currentState == .blocked { return .blocked }
        if projection.currentState == .stalled { return .stalled }

        if projection.escalationReason != nil || projection.nextMove?.needsApproval == true || placement == .needsApproval {
            return .needsUserApproval
        }

        if projection.nextMove?.needsUserInput == true || placement == .needsInput || needsHumanAttention {
            return .needsUserInput
        }

        if projection.role == .requester, projection.currentState == .awaitingProviderClarification {
            let ctx = outboundSendContext ?? ExchangeSecondHalfOutboundSendContext()
            let draftReady = requesterOutboundDraftReadyForUI(
                hasDraft: hasDraft,
                outboundSendContext: ctx
            )
            if ctx.hasPositiveSendProofForRequesterProviderClarification() {
                return .awaitingProviderAnswer
            }
            if draftReady {
                return .providerClarificationDraftReady
            }
            if ctx.requesterOutboundBlockedWithoutDraftSurfacing {
                return .activeCoordination
            }
            if projection.nextMove?.action == .askClarification {
                return .activeCoordination
            }
            return .activeCoordination
        }

        if projection.currentState == .awaitingRequesterClarification {
            return hasDraft ? .clarificationReady : .needsUserInput
        }

        if hasDecisionPacket || projection.currentState == .decisionReady || placement == .decisionReady {
            return .finalReviewReady
        }

        if hasProviderReception && (hasRequesterReview || projection.currentState == .requesterReview) {
            return .providerAnswerReceived
        }

        if projection.nextMove?.action == .askClarification {
            return hasDraft ? .clarificationReady : .activeCoordination
        }

        if projection.currentState == .qualifying || projection.currentState == .matchFound {
            return .evaluatingResult
        }

        if placement == .recovery {
            return .failed
        }

        if canRunAutonomously || placement == .activeCoordination || placement == .providerReception || placement == .requesterReview {
            return .activeCoordination
        }

        return .unknown
    }

    private func deriveAgencyPhaseFromSnapshot(
        snapshot: ExchangeThread.SecondHalfSnapshot,
        placement: Placement,
        needsHumanAttention: Bool,
        canRunAutonomously: Bool,
        hasDecisionPacket: Bool,
        hasProviderReception: Bool,
        hasRequesterReview: Bool,
        hasDraft: Bool,
        roleDisplayTitle: String,
        outboundSendContext: ExchangeSecondHalfOutboundSendContext
    ) -> AgencyPhase {
        let state = snapshot.currentStateRaw.lowercased()

        if isTerminalState(state) { return .completed }
        if state.contains("blocked") { return .blocked }
        if state.contains("stalled") { return .stalled }
        if state.contains("failed") || placement == .recovery { return .failed }

        if snapshot.requiresHumanApproval || placement == .needsApproval {
            return .needsUserApproval
        }

        if snapshot.needsHumanAttention || placement == .needsInput || needsHumanAttention {
            return .needsUserInput
        }

        let requesterRole = roleDisplayTitle.caseInsensitiveCompare(ExchangeSecondHalfRole.requester.displayTitle) == .orderedSame
        let awaitingProvider = state.contains("awaitingproviderclarification")
            || state.contains("awaiting provider clarification")
        if requesterRole, awaitingProvider {
            let draftReady = requesterOutboundDraftReadyForUI(
                hasDraft: hasDraft,
                outboundSendContext: outboundSendContext
            )
            if outboundSendContext.hasPositiveSendProofForRequesterProviderClarification() {
                return .awaitingProviderAnswer
            }
            if draftReady {
                return .providerClarificationDraftReady
            }
            if outboundSendContext.requesterOutboundBlockedWithoutDraftSurfacing {
                return .activeCoordination
            }
            if snapshot.nextMoveActionRaw == ExchangeSecondHalfAction.askClarification.rawValue {
                return .activeCoordination
            }
            return .activeCoordination
        }

        if state.contains("awaitingrequesterclarification") || state.contains("awaiting requester clarification") {
            return hasDraft ? .clarificationReady : .needsUserInput
        }

        if hasDecisionPacket || state.contains("decisionready") || placement == .decisionReady {
            return .finalReviewReady
        }

        if hasProviderReception && (hasRequesterReview || state.contains("requesterreview")) {
            return .providerAnswerReceived
        }

        if snapshot.nextMoveActionRaw == ExchangeSecondHalfAction.askClarification.rawValue {
            return hasDraft ? .clarificationReady : .activeCoordination
        }

        if state.contains("qualifying") || state.contains("matchfound") || state.contains("match found") {
            return .evaluatingResult
        }

        if canRunAutonomously || placement == .activeCoordination || placement == .providerReception || placement == .requesterReview {
            return .activeCoordination
        }

        return .unknown
    }

    private func makeAgencyPhaseDetail(
        phase: AgencyPhase,
        nextMove: NextMove?,
        summary: String,
        recommendation: String
    ) -> String? {
        switch phase {
        case .clarificationReady:
            return "A clarification draft is ready to send safely."
        case .providerClarificationDraftReady:
            return "Review and send the question to the provider. Nothing has been sent yet."
        case .clarificationSent:
            return "Clarification was sent. Waiting for provider answer."
        case .awaitingProviderAnswer:
            return "Waiting for provider answer."
        case .finalReviewReady:
            return "Decision packet is ready for final review."
        case .needsUserApproval:
            return "This step crosses a boundary and needs your approval."
        case .needsUserInput:
            return "This step needs your input before continuing."
        case .evaluatingResult:
            return "The secretary is evaluating the selected result."
        case .blocked:
            return "This path is currently blocked."
        case .failed:
            return "This path needs recovery."
        case .stalled:
            return "This path is stalled."
        case .providerAnswerReceived, .completed, .activeCoordination, .unknown:
            return firstNonBlank(nextMove?.rationale, recommendation, summary)
        }
    }

    // MARK: - Activity / timeline

    private func makeActivitySteps(
        from projection: ExchangeSecondHalfProjection
    ) -> [ActivityStep] {
        let state = projection.currentState

        return [
            ActivityStep(
                id: "match",
                title: "Match exists",
                detail: "A plausible opportunity or inbound path exists.",
                status: activityStatus(
                    current: state,
                    step: .matchFound,
                    activeStates: [.matchFound]
                )
            ),
            ActivityStep(
                id: "qualify",
                title: "Qualify opportunity",
                detail: "Check strength, missing facts, and whether one more clarification helps.",
                status: activityStatus(
                    current: state,
                    step: .qualifying,
                    activeStates: [.qualifying]
                )
            ),
            ActivityStep(
                id: "clarify",
                title: "Clarify missing facts",
                detail: projection.qualification.missingFacts.first,
                status: clarificationActivityStatus(from: projection)
            ),
            ActivityStep(
                id: "review",
                title: projection.role == .provider ? "Provider review" : "Requester review",
                detail: projection.nextMove?.rationale,
                status: reviewActivityStatus(from: projection)
            ),
            ActivityStep(
                id: "decision",
                title: "Frame decision",
                detail: projection.decisionPacket?.recommendation,
                status: decisionActivityStatus(from: projection)
            ),
            ActivityStep(
                id: "approval",
                title: "Commitment boundary",
                detail: projection.escalationReason ?? "No commitment approval required yet.",
                status: approvalActivityStatus(from: projection)
            ),
            ActivityStep(
                id: "outcome",
                title: "Outcome",
                detail: projection.currentState.isTerminal ? projection.currentState.displayTitle : nil,
                status: outcomeActivityStatus(from: projection)
            )
        ]
    }

    private func makeTimelineItems(
        from projection: ExchangeSecondHalfProjection,
        summary: String,
        recommendation: String
    ) -> [TimelineItem] {
        var items: [TimelineItem] = []

        items.append(
            TimelineItem(
                title: projection.currentState.displayTitle,
                summary: summary,
                tone: timelineTone(for: projection.currentState)
            )
        )

        if let delta = projection.latestDelta, delta.hasMeaningfulChange {
            let deltaSummary =
                delta.significanceExplanation.nonBlank
            ?? dedupe(delta.newFactsLearned).joined(separator: " ")

            items.append(
                TimelineItem(
                    title: "What changed",
                    summary: deltaSummary,
                    tone: .active
                )
            )
        }

        if let decision = projection.decisionPacket {
            items.append(
                TimelineItem(
                    title: "Recommendation",
                    summary: decision.recommendation.nonBlank ?? recommendation,
                    tone: decision.needsCommitmentApproval ? .warning : .success
                )
            )
        }

        if let escalation = projection.escalationReason?.nonBlank {
            items.append(
                TimelineItem(
                    title: "Approval boundary",
                    summary: escalation,
                    tone: .warning
                )
            )
        }

        if let draft = projection.pendingDraft {
            items.append(
                TimelineItem(
                    title: "Draft prepared",
                    summary: draft.body.collapsedPreview(maxLength: 160),
                    tone: projection.escalationReason == nil ? .active : .warning
                )
            )
        }

        return items
    }

    private func makeSummaryLines(
        from projection: ExchangeSecondHalfProjection
    ) -> [String] {
        var lines: [String] = []

        lines.append(contentsOf: projection.latestDecisionFrame?.whatChanged ?? [])
        lines.append(contentsOf: projection.latestDecisionFrame?.clarifiedFacts ?? [])
        lines.append(contentsOf: projection.latestDecisionFrame?.unresolvedIssues.map { "Unresolved: \($0)" } ?? [])
        lines.append(contentsOf: projection.latestDecisionFrame?.tradeoffs.map { "Tradeoff: \($0)" } ?? [])
        lines.append(contentsOf: projection.latestDelta?.newFactsLearned ?? [])
        lines.append(contentsOf: projection.qualification.strengthReasons)
        lines.append(contentsOf: projection.qualification.weaknessReasons)
        lines.append(contentsOf: projection.qualification.missingFacts.map { "Missing: \($0)" })

        if let escalationReason = projection.escalationReason {
            lines.append("Approval: \(escalationReason)")
        }

        if let next = projection.nextMove {
            lines.append("Next: \(next.title). \(next.rationale)")
        }

        return dedupe(lines)
    }

    // MARK: - Activity helpers

    private func activityStatus(
        current: ExchangeSecondHalfState,
        step: ExchangeSecondHalfState,
        activeStates: Set<ExchangeSecondHalfState>
    ) -> ActivityStep.Status {
        if current == .blocked {
            return .blocked
        }

        if activeStates.contains(current) {
            return .active
        }

        if stateRank(current) > stateRank(step) {
            return .completed
        }

        return .pending
    }

    private func clarificationActivityStatus(
        from projection: ExchangeSecondHalfProjection
    ) -> ActivityStep.Status {
        if projection.currentState == .blocked {
            return .blocked
        }

        if projection.currentState.isAwaitingClarification ||
            projection.nextMove?.action.isClarificationAction == true ||
            projection.qualification.needsClarification {
            return .active
        }

        if projection.currentState == .decisionReady ||
            projection.currentState == .awaitingCommitmentApproval ||
            projection.currentState.isTerminal {
            return .completed
        }

        return .pending
    }

    private func reviewActivityStatus(
        from projection: ExchangeSecondHalfProjection
    ) -> ActivityStep.Status {
        if projection.currentState == .blocked {
            return .blocked
        }

        if projection.currentState == .providerReview ||
            projection.currentState == .requesterReview ||
            projection.currentState.isHumanReviewState {
            return .active
        }

        if projection.currentState == .decisionReady ||
            projection.currentState == .awaitingCommitmentApproval ||
            projection.currentState.isTerminal {
            return .completed
        }

        return .pending
    }

    private func decisionActivityStatus(
        from projection: ExchangeSecondHalfProjection
    ) -> ActivityStep.Status {
        if projection.currentState == .blocked {
            return .blocked
        }

        if projection.currentState == .decisionReady ||
            projection.nextMove?.action == .frameDecision ||
            projection.decisionPacket != nil {
            return .active
        }

        if projection.currentState == .awaitingCommitmentApproval ||
            projection.currentState == .accepted ||
            projection.currentState == .completed {
            return .completed
        }

        return .pending
    }

    private func approvalActivityStatus(
        from projection: ExchangeSecondHalfProjection
    ) -> ActivityStep.Status {
        if projection.currentState == .blocked {
            return .blocked
        }

        if projection.currentState == .awaitingCommitmentApproval ||
            projection.escalationReason != nil ||
            projection.nextMove?.needsApproval == true {
            return .active
        }

        if projection.currentState == .accepted ||
            projection.currentState == .completed {
            return .completed
        }

        return .pending
    }

    private func outcomeActivityStatus(
        from projection: ExchangeSecondHalfProjection
    ) -> ActivityStep.Status {
        if projection.currentState == .blocked {
            return .blocked
        }

        if projection.currentState.isTerminal {
            return .completed
        }

        return .pending
    }

    private func stateRank(_ state: ExchangeSecondHalfState) -> Int {
        switch state {
        case .matchFound:
            return 0
        case .qualifying:
            return 1
        case .awaitingProviderClarification,
             .awaitingRequesterClarification:
            return 2
        case .providerReview,
             .requesterReview:
            return 3
        case .decisionReady:
            return 4
        case .awaitingCommitmentApproval:
            return 5
        case .accepted:
            return 6
        case .completed:
            return 7
        case .stalled:
            return 3
        case .blocked:
            return 3
        case .declined,
             .expired:
            return 7
        }
    }

    // MARK: - Tone helpers

    private func badgeTone(
        for state: ExchangeSecondHalfState
    ) -> Badge.Tone {
        switch state {
        case .matchFound, .qualifying:
            return .active
        case .awaitingProviderClarification,
             .awaitingRequesterClarification,
             .providerReview,
             .requesterReview:
            return .warning
        case .decisionReady:
            return .success
        case .awaitingCommitmentApproval:
            return .approval
        case .accepted, .completed:
            return .success
        case .declined, .expired:
            return .neutral
        case .stalled:
            return .warning
        case .blocked:
            return .blocked
        }
    }

    private func badgeTone(
        for tier: ExchangeOpportunityQualityTier
    ) -> Badge.Tone {
        switch tier {
        case .weak:
            return .warning
        case .promising:
            return .active
        case .strong:
            return .success
        case .decisionReady:
            return .success
        }
    }

    private func timelineTone(
        for state: ExchangeSecondHalfState
    ) -> TimelineItem.Tone {
        switch state {
        case .matchFound,
             .qualifying,
             .awaitingProviderClarification,
             .awaitingRequesterClarification,
             .providerReview,
             .requesterReview:
            return .active
        case .decisionReady,
             .accepted,
             .completed:
            return .success
        case .awaitingCommitmentApproval,
             .stalled:
            return .warning
        case .blocked:
            return .blocked
        case .declined,
             .expired:
            return .neutral
        }
    }

    // MARK: - Dedupe helpers

    private func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                output.append(trimmed)
            }
        }

        return output
    }

    private func dedupeBadges(_ badges: [Badge]) -> [Badge] {
        var seen = Set<String>()
        var output: [Badge] = []

        for badge in badges {
            if seen.insert(badge.id).inserted {
                output.append(badge)
            }
        }

        return output
    }

    private func dedupeButtons(_ buttons: [ActionButton]) -> [ActionButton] {
        var seen = Set<String>()
        var output: [ActionButton] = []

        for button in buttons {
            if seen.insert(button.id).inserted {
                output.append(button)
            }
        }

        return output
    }

    // MARK: - Plain-language projection

    private func withPlainLanguage(_ m: DisplayModel) -> DisplayModel {
        var out = m
        let unresolved = Array((m.requesterReview?.missingFacts ?? m.operatingContext.userFacingMissingFacts).prefix(4))
        let strengths = Array((m.requesterReview?.strengthReasons ?? []).prefix(3))
        let weaknesses = Array((m.requesterReview?.weaknessReasons ?? []).prefix(3))
        let providerReply = m.providerReception?.subtitle
            ?? m.providerReception?.inquirySummary
            ?? m.providerReception?.requesterAsk

        let contradiction = (weaknesses + m.summaryLines).first {
            let l = $0.lowercased()
            return l.contains("contradict") || l.contains("no seller financing") || l.contains("poor fit")
        }
        let impliedFlex = (strengths + m.summaryLines).first {
            let l = $0.lowercased()
            return l.contains("impliedflexible") || l.contains("partially satisfied") || l.contains("may consider")
        }

        let waitingOnProvider = m.agencyPhase == .awaitingProviderAnswer
            || m.placement == .activeCoordination
        let waitingOnUser = m.needsHumanAttention
            || m.placement == .needsInput
            || m.placement == .needsApproval
        let poorFit = contradiction != nil
            || m.status.readiness.lowercased().contains("blocked")
        let promisingButIncomplete = !poorFit && !unresolved.isEmpty

        out.plain = DisplayModel.PlainLanguage(
            plainStatusLabel: {
                if waitingOnUser { return "Needs your input" }
                if waitingOnProvider { return "Waiting for provider" }
                if m.boundary.requiresHumanApproval { return "Needs your approval" }
                if poorFit { return "Match got weaker" }
                if m.status.isDecisionReady { return "Ready for review" }
                return "In progress"
            }(),
            plainOneLineSummary: !m.summary.isEmpty ? m.summary : m.recommendation,
            primaryUserQuestion: m.nextMove?.requiredInputs.first,
            primaryCTA: m.nextMove?.needsApproval == true ? "Review now" : (m.nextMove?.needsUserInput == true ? "Add detail" : "Open thread"),
            secondaryCTA: waitingOnProvider ? "View transcript" : "See details",
            latestMeaningfulEvent: m.timelineItems.first?.summary ?? providerReply ?? m.nextMove?.title,
            matchReasonChips: strengths,
            satisfiedConditionChips: strengths.filter { !$0.lowercased().contains("missing") },
            unresolvedConditionChips: unresolved,
            contradictionSummary: contradiction,
            impliedFlexibilitySummary: impliedFlex,
            missingInfoSummary: Self.userFacingMissingInfoSummary(from: unresolved),
            followUpReason: m.nextMove?.requiredInputs.first ?? m.nextMove?.rationale,
            recommendationSummary: !m.recommendation.isEmpty ? m.recommendation : nil,
            decisionReadinessLabel: m.status.isDecisionReady ? "Ready for your decision" : "Not decision-ready yet",
            blockedReason: m.status.isBlocking ? m.boundary.reason : nil,
            approvalReason: m.boundary.requiresHumanApproval ? m.boundary.reason : nil,
            providerReplySummary: providerReply,
            userActionRequired: waitingOnUser,
            isMovingAutonomously: m.canRunAutonomously && !m.needsHumanAttention,
            isWaitingOnProvider: waitingOnProvider,
            isWaitingOnUser: waitingOnUser,
            isPoorFit: poorFit,
            isPromisingButIncomplete: promisingButIncomplete
        )

        return out
    }

    private static func userFacingMissingInfoSummary(from unresolved: [String]) -> String? {
        let blockedMarkers = [
            "intent gap",
            "flathard",
            "hard requirement",
            "match caution",
            "mismatch",
            "unknown",
            "qualification",
            "resolvedsurface",
            "operatingmissing",
            "partially satisfied",
            "impliedflexible"
        ]

        let cleaned = unresolved
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { item in
                let lower = item.lowercased()
                return !blockedMarkers.contains { lower.contains($0) }
            }

        guard !cleaned.isEmpty else {
            return nil
        }

        return "Still missing: " + cleaned.prefix(2).joined(separator: ", ") + "."
    }

    // MARK: - User-facing display sanitization

    /// Strips internal / machine language before any UI or cached handoff. Storage snapshots stay raw.
    func sanitizedUserFacingDisplayModel(_ m: DisplayModel) -> DisplayModel {
        let bodyFB = "New activity in this thread"
        let titleFB = "Coordination"

        func sTitle(_ x: String?) -> String {
            ExchangeUserFacingCopySanitizer.sanitizeOrFallback(x, field: .title, fallback: titleFB)
        }
        func sBody(_ x: String?) -> String {
            ExchangeUserFacingCopySanitizer.sanitizeOrFallback(x, field: .body, fallback: bodyFB)
        }
        func sSub(_ x: String?) -> String {
            ExchangeUserFacingCopySanitizer.sanitizeOrFallback(x, field: .subtitle, fallback: bodyFB)
        }
        func sStatus(_ x: String?) -> String {
            ExchangeUserFacingCopySanitizer.sanitizeOrFallback(x, field: .status, fallback: Self.insufficientSignalLabel)
        }
        func sGen(_ x: String?) -> String? {
            ExchangeUserFacingCopySanitizer.sanitize(x, field: .general)
        }
        func sLines(_ lines: [String]) -> [String] {
            lines.compactMap { sGen($0) }.filter { !$0.isEmpty }
        }

        var out = m
        out.title = sTitle(m.title)
        out.subtitle = sSub(m.subtitle)
        out.summary = sBody(m.summary)
        out.postureSummary = sBody(m.postureSummary)
        out.recommendation = sBody(m.recommendation)
        out.stateLabel = sStatus(m.stateLabel)
        out.roleLabel = sStatus(m.roleLabel)
        out.escalationReason = ExchangeUserFacingCopySanitizer.sanitize(m.escalationReason, field: .body)
        out.actionTitle = ExchangeUserFacingCopySanitizer.sanitize(m.actionTitle, field: .subtitle)
        out.summaryLines = sLines(m.summaryLines)

        out.hero = Hero(
            eyebrow: sSub(m.hero.eyebrow),
            title: sTitle(m.hero.title),
            subtitle: sSub(m.hero.subtitle),
            statusLine: sBody(m.hero.statusLine),
            primaryMetric: m.hero.primaryMetric.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .status) }
                ?? m.hero.primaryMetric,
            secondaryMetric: m.hero.secondaryMetric.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .status) }
                ?? m.hero.secondaryMetric,
            tertiaryMetric: m.hero.tertiaryMetric.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .status) }
                ?? m.hero.tertiaryMetric
        )

        out.status = Status(
            state: sStatus(m.status.state),
            role: sStatus(m.status.role),
            quality: sStatus(m.status.quality),
            readiness: sStatus(m.status.readiness),
            leadStrength: m.status.leadStrength.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .status) },
            reviewStrength: m.status.reviewStrength.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .status) },
            isBlocking: m.status.isBlocking,
            isAutonomous: m.status.isAutonomous,
            isDecisionReady: m.status.isDecisionReady,
            isTerminal: m.status.isTerminal
        )

        if var nm = m.nextMove {
            nm.action = sStatus(nm.action)
            nm.title = sSub(nm.title)
            nm.rationale = sBody(nm.rationale)
            nm.requiredInputs = sLines(nm.requiredInputs)
            out.nextMove = nm
        }

        out.badges = m.badges.map {
            Badge(id: $0.id, title: sTitle($0.title), tone: $0.tone)
        }

        out.buttons = m.buttons.map {
            ActionButton(id: $0.id, title: sTitle($0.title), kind: $0.kind, prominence: $0.prominence, requiresConfirmation: $0.requiresConfirmation)
        }

        if var d = m.decision {
            d.title = sTitle(d.title)
            d.summary = sBody(d.summary)
            d.clarifiedFacts = sLines(d.clarifiedFacts)
            d.whatChanged = sLines(d.whatChanged)
            d.unresolvedIssues = sLines(d.unresolvedIssues)
            d.recommendation = sBody(d.recommendation)
            d.tradeoffs = sLines(d.tradeoffs)
            d.requesterPause = ExchangeRequesterReviewPresentation.sanitizedPauseFrame(m.decision?.requesterPause)
            out.decision = d
        }

        if var p = m.providerReception {
            p.title = sTitle(p.title)
            p.subtitle = sSub(p.subtitle)
            p.inquirySummary = p.inquirySummary.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .body) }
            p.requesterAsk = p.requesterAsk.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .body) }
            p.matchedAnchor = p.matchedAnchor.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .title) }
            p.leadStrength = sStatus(p.leadStrength)
            p.answerabilityStatus = p.answerabilityStatus.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .status) }
            p.escalationReason = ExchangeUserFacingCopySanitizer.sanitize(p.escalationReason, field: .body)
            p.nextMoveTitle = p.nextMoveTitle.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .subtitle) }
            out.providerReception = p
        }

        if var r = m.requesterReview {
            r.title = sTitle(r.title)
            r.subtitle = sSub(r.subtitle)
            r.reviewStrength = sStatus(r.reviewStrength)
            r.strengthReasons = sLines(r.strengthReasons)
            r.weaknessReasons = sLines(r.weaknessReasons)
            r.missingFacts = sLines(r.missingFacts)
            r.recommendation = r.recommendation.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .body) }
            r.nextMoveTitle = r.nextMoveTitle.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .subtitle) }
            r.pauseFrame = ExchangeRequesterReviewPresentation.sanitizedPauseFrame(m.requesterReview?.pauseFrame)
            out.requesterReview = r
        }

        out.operatingContext = OperatingContextSection(
            title: sTitle(m.operatingContext.title),
            role: sStatus(m.operatingContext.role),
            postureSummary: sBody(m.operatingContext.postureSummary),
            readiness: sStatus(m.operatingContext.readiness),
            urgency: sStatus(m.operatingContext.urgency),
            trust: sStatus(m.operatingContext.trust),
            priceSensitivity: sStatus(m.operatingContext.priceSensitivity),
            flexibility: sStatus(m.operatingContext.flexibility),
            followUpHints: sLines(m.operatingContext.followUpHints),
            missingFacts: sLines(m.operatingContext.missingFacts),
            userFacingMissingFacts: sLines(m.operatingContext.userFacingMissingFacts),
            diagnosticMissingFacts: sLines(m.operatingContext.diagnosticMissingFacts),
            strengthReasons: sLines(m.operatingContext.strengthReasons),
            weaknessReasons: sLines(m.operatingContext.weaknessReasons)
        )

        out.boundary = BoundarySection(
            title: sTitle(m.boundary.title),
            kind: m.boundary.kind,
            reason: sBody(m.boundary.reason),
            requiresHumanApproval: m.boundary.requiresHumanApproval,
            allowsAutonomousDrafting: m.boundary.allowsAutonomousDrafting,
            allowsAutonomousSending: m.boundary.allowsAutonomousSending,
            externalEffectLine: sBody(m.boundary.externalEffectLine)
        )

        if var st = m.style {
            st.title = sTitle(st.title)
            st.tone = sStatus(st.tone)
            st.warmthDirectness = sStatus(st.warmthDirectness)
            st.firmness = sStatus(st.firmness)
            st.disclosureStyle = sStatus(st.disclosureStyle)
            st.initiativeLevel = sStatus(st.initiativeLevel)
            st.negotiationStyle = sStatus(st.negotiationStyle)
            st.approvalSensitivity = sStatus(st.approvalSensitivity)
            st.freeformInstructions = st.freeformInstructions.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .body) }
            out.style = st
        }

        if var dr = m.draft {
            dr.title = sTitle(dr.title)
            dr.subject = dr.subject.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .subtitle) }
            dr.bodyPreview = sBody(dr.bodyPreview)
            dr.usedStructuredFacts = sLines(dr.usedStructuredFacts)
            dr.notes = sLines(dr.notes)
            out.draft = dr
        }

        out.activitySteps = m.activitySteps.map { step in
            ActivityStep(
                id: step.id,
                title: sTitle(step.title),
                detail: step.detail.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .body) },
                status: step.status
            )
        }

        out.timelineItems = m.timelineItems.map { item in
            TimelineItem(
                id: item.id,
                title: sTitle(item.title),
                summary: sBody(item.summary),
                tone: item.tone,
                createdAt: item.createdAt
            )
        }

        out.agencyPhaseTitle = m.agencyPhaseTitle.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .subtitle) }
            ?? m.agencyPhaseTitle
        out.agencyPhaseDetail = m.agencyPhaseDetail.flatMap { ExchangeUserFacingCopySanitizer.sanitize($0, field: .body) }
            ?? m.agencyPhaseDetail

        if let c = m.requesterClosureComposedCopy {
            out.requesterClosureComposedCopy = ExchangeRequesterClosureComposedCopy(
                title: sTitle(c.title),
                summary: sBody(c.summary),
                answeredBullets: sLines(c.answeredBullets),
                stillOpenBullets: sLines(c.stillOpenBullets),
                recommendation: sBody(c.recommendation),
                nextActionLabel: sSub(c.nextActionLabel)
            )
        }

        out.plain = DisplayModel.PlainLanguage(
            plainStatusLabel: sTitle(m.plain.plainStatusLabel),
            plainOneLineSummary: sBody(m.plain.plainOneLineSummary),
            primaryUserQuestion: sGen(m.plain.primaryUserQuestion),
            primaryCTA: sTitle(m.plain.primaryCTA),
            secondaryCTA: sSub(m.plain.secondaryCTA),
            latestMeaningfulEvent: sBody(m.plain.latestMeaningfulEvent),
            matchReasonChips: sLines(m.plain.matchReasonChips),
            satisfiedConditionChips: sLines(m.plain.satisfiedConditionChips),
            unresolvedConditionChips: sLines(m.plain.unresolvedConditionChips),
            contradictionSummary: sBody(m.plain.contradictionSummary),
            impliedFlexibilitySummary: sBody(m.plain.impliedFlexibilitySummary),
            missingInfoSummary: sBody(m.plain.missingInfoSummary),
            followUpReason: sBody(m.plain.followUpReason),
            recommendationSummary: sBody(m.plain.recommendationSummary),
            decisionReadinessLabel: sSub(m.plain.decisionReadinessLabel),
            blockedReason: sBody(m.plain.blockedReason),
            approvalReason: sBody(m.plain.approvalReason),
            providerReplySummary: sBody(m.plain.providerReplySummary),
            userActionRequired: m.plain.userActionRequired,
            isMovingAutonomously: m.plain.isMovingAutonomously,
            isWaitingOnProvider: m.plain.isWaitingOnProvider,
            isWaitingOnUser: m.plain.isWaitingOnUser,
            isPoorFit: m.plain.isPoorFit,
            isPromisingButIncomplete: m.plain.isPromisingButIncomplete
        )

        #if DEBUG
        let stripped = m.title != out.title || m.summary != out.summary || m.hero.statusLine != out.hero.statusLine
        Swift.print(
            "[SecretaryDisplayClean] surface=secondHalfDisplay titleSource=sanitized bodySource=sanitized strippedInternal=\(stripped)"
        )
        #endif

        return out
    }
}

// MARK: - Display helpers

private extension String {
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var displayTitleFromRaw: String {
        let raw = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return raw }

        var output = ""
        var previousWasLowercase = false

        for scalar in raw.unicodeScalars {
            let char = Character(scalar)

            if scalar == "_" || scalar == "-" {
                output.append(" ")
                previousWasLowercase = false
                continue
            }

            let string = String(char)

            if string.uppercased() == string,
               string.lowercased() != string,
               previousWasLowercase {
                output.append(" ")
            }

            output.append(string)
            previousWasLowercase = string.lowercased() == string && string.uppercased() != string
        }

        return output
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    func collapsedPreview(maxLength: Int) -> String {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard collapsed.count > maxLength else {
            return collapsed
        }

        let index = collapsed.index(collapsed.startIndex, offsetBy: max(0, maxLength - 1))
        return String(collapsed[..<index]) + "…"
    }
}

// MARK: - DisplayModel invariants

public extension ExchangeSecondHalfUIAdapter.DisplayModel {
    /// When true, `hasDecisionPacket` matches a populated `decision` section (thread focus / prominence checks).
    var decisionPacketProjectionAligned: Bool {
        hasDecisionPacket == (decision != nil)
    }
}

// MARK: - Surface-aware missing facts (second-half display)

public extension ExchangeSecondHalfUIAdapter.DisplayModel {
    /// Reconciles persisted or merged missing-fact lists with `ExchangeIntent` surface anchoring so the Current Opportunity card
    /// does not show irrelevant offer/profile warnings after Pass-2 hydration.
    func applyingSurfaceAwareOpportunityMissingFacts(
        thread: ExchangeThread,
        hasHydratedOffer: Bool,
        hasHydratedProfile: Bool
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel {
        let anchor = thread.intent.resolvedOpportunitySurfaceAnchor(
            selectedOfferID: thread.selectedOfferID,
            selectedPublicProfileID: thread.selectedPublicProfileID,
            selectedCounterpartyID: thread.selectedCounterpartyID
        )

        let filter: ([String]) -> [String] = { lines in
            anchor.filterOpportunityMissingFactLines(
                lines,
                hasHydratedOffer: hasHydratedOffer,
                hasHydratedProfile: hasHydratedProfile
            )
        }

        var copy = self

        copy.operatingContext.missingFacts = filter(copy.operatingContext.missingFacts)
        copy.operatingContext.userFacingMissingFacts = filter(copy.operatingContext.userFacingMissingFacts)
        copy.operatingContext.diagnosticMissingFacts = filter(copy.operatingContext.diagnosticMissingFacts)

        if var review = copy.requesterReview {
            review.missingFacts = filter(review.missingFacts)
            review.needsMoreQualification = !review.missingFacts.isEmpty
            copy.requesterReview = review
        }

        if var decision = copy.decision {
            decision.unresolvedIssues = filter(decision.unresolvedIssues)
            copy.decision = decision
        }

        if var assessment = copy.agencyAssessment {
            if let needs = assessment.requesterDecisionNeeds {
                let filteredNeeds = ExchangeRequesterDecisionNeeds(
                    knownDecisionFacts: needs.knownDecisionFacts,
                    missingDecisionFacts: filter(needs.missingDecisionFacts),
                    recommendedQuestions: needs.recommendedQuestions,
                    decisionReadiness: needs.decisionReadiness,
                    rationale: needs.rationale
                )
                assessment.requesterDecisionNeeds = filteredNeeds
            }

            if let prov = assessment.providerAnswerability {
                let filteredProv = ExchangeProviderAnswerability(
                    answerability: prov.answerability,
                    knownFactsUsed: prov.knownFactsUsed,
                    groundedFacts: prov.groundedFacts,
                    missingFacts: filter(prov.missingFacts),
                    proposedAnswer: prov.proposedAnswer,
                    requiresHumanApproval: prov.requiresHumanApproval,
                    allowsAutonomousDrafting: prov.allowsAutonomousDrafting,
                    allowsAutonomousSending: prov.allowsAutonomousSending,
                    boundaryReason: prov.boundaryReason,
                    usesCompareFirstGroundedFinalBody: prov.usesCompareFirstGroundedFinalBody
                )
                assessment.providerAnswerability = filteredProv
            }

            copy.agencyAssessment = assessment
        }

        #if DEBUG
        let surfaceLabel: String = {
            switch anchor {
            case .offerSurface: return "offer"
            case .profileSurface: return "profile"
            case .counterpartyNode: return "counterpartyNode"
            }
        }()
        Swift.print(
            "[OpportunityQualificationMissing] displayFilter thread=\(thread.id.uuidString) " +
                "resolvedSurface=\(surfaceLabel) " +
                "operatingMissing=\(copy.operatingContext.missingFacts.count)"
        )
        #endif

        return copy
    }
}

public extension ExchangeSecondHalfUIAdapter {
    /// Machine-safe `ExchangeSecondHalfAction.rawValue` for autonomous send / materialization (never rely on `NextMove.action` display copy).
    static func canonicalSecondHalfActionRaw(for display: DisplayModel) -> String {
        if let explicit = display.nextMove?.actionRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty,
           ExchangeSecondHalfAction(rawValue: explicit) != nil {
            return explicit
        }
        let titleLine = display.nextMove?.action.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let mapped = ExchangeSecondHalfAction.allCases.first(where: { $0.displayTitle == titleLine }) {
            return mapped.rawValue
        }
        return titleLine
    }
}

// MARK: - Enum display helpers

private extension ExchangeOpportunityQualityTier {
    var displayTitle: String {
        switch self {
        case .weak:
            return "Weak"
        case .promising:
            return "Promising"
        case .strong:
            return "Strong"
        case .decisionReady:
            return "Decision Ready"
        }
    }
}

private extension ExchangeReadinessLevel {
    var displayTitle: String {
        rawValue.displayTitleFromRaw
    }
}

private extension ExchangeUrgencyLevel {
    var displayTitle: String {
        rawValue.displayTitleFromRaw
    }
}

private extension ExchangeTrustLevel {
    var displayTitle: String {
        rawValue.displayTitleFromRaw
    }
}

private extension ExchangePriceSensitivity {
    var displayTitle: String {
        rawValue.displayTitleFromRaw
    }
}

private extension ExchangeFlexibilityLevel {
    var displayTitle: String {
        rawValue.displayTitleFromRaw
    }
}

public extension ExchangeSecondHalfUIAdapter.AgencyPhase {
    /// Short status copy for chips — not workflow jargon.
    var displayTitle: String {
        switch self {
        case .evaluatingResult:
            return "Review in progress"
        case .clarificationReady:
            return "More details needed"
        case .providerClarificationDraftReady:
            return "Draft ready"
        case .clarificationSent:
            return "Waiting for response"
        case .awaitingProviderAnswer:
            return "Waiting for response"
        case .providerAnswerReceived:
            return "New message"
        case .finalReviewReady:
            return "Ready to review"
        case .needsUserApproval:
            return "Needs your approval"
        case .needsUserInput:
            return "Needs your reply"
        case .blocked:
            return "Blocked"
        case .failed:
            return "Something went wrong"
        case .stalled:
            return "Paused"
        case .completed:
            return "Done"
        case .activeCoordination:
            return "In progress"
        case .unknown:
            return "Active"
        }
    }
}
