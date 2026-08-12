import Foundation
import SwiftUI
import AnumCore

struct SecretaryPanelInfoLineDisplay: Identifiable, Hashable {
    let id: UUID
    let label: String
    let value: String

    init(
        id: UUID = UUID(),
        label: String,
        value: String
    ) {
        self.id = id
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isRenderable: Bool {
        !label.isEmpty && !value.isEmpty
    }
}

struct SecretaryPanelSectionDisplay: Identifiable, Hashable {
    let id: UUID
    let title: String
    let systemImage: String
    let summary: String?
    let lines: [SecretaryPanelInfoLineDisplay]

    init(
        id: UUID = UUID(),
        title: String,
        systemImage: String,
        summary: String? = nil,
        lines: [SecretaryPanelInfoLineDisplay] = []
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.systemImage = systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.lines = lines.filter(\.isRenderable)
    }

    var isRenderable: Bool {
        !title.isEmpty && (summary != nil || !lines.isEmpty)
    }
}

struct SecretaryActivityPanelDisplay: Hashable {
    let title: String
    let activityType: String
    let latestMovement: String
    let meaning: String
    let currentState: String
    let boundary: String
    let nextMove: String
    let primaryTitle: String
    let secondaryTitle: String
    let execution: SecretaryExecutionDisplay?
    let threadID: ExchangeThread.ID?

    /// Optional richer second-half sections.
    ///
    /// These let the activity panel show second-half depth without the view
    /// needing to know about ExchangeSecondHalf internals.
    let whatChanged: [String]
    let operatingContext: [SecretaryPanelInfoLineDisplay]
    let stanceLines: [SecretaryPanelInfoLineDisplay]
    let decisionLines: [SecretaryPanelInfoLineDisplay]
    let providerReceptionLines: [SecretaryPanelInfoLineDisplay]
    let requesterReviewLines: [SecretaryPanelInfoLineDisplay]
    let draftFactsUsed: [String]
    let extraSections: [SecretaryPanelSectionDisplay]

    init(
        title: String,
        activityType: String,
        latestMovement: String,
        meaning: String,
        currentState: String,
        boundary: String,
        nextMove: String,
        primaryTitle: String,
        secondaryTitle: String,
        execution: SecretaryExecutionDisplay? = nil,
        threadID: ExchangeThread.ID? = nil,
        whatChanged: [String] = [],
        operatingContext: [SecretaryPanelInfoLineDisplay] = [],
        stanceLines: [SecretaryPanelInfoLineDisplay] = [],
        decisionLines: [SecretaryPanelInfoLineDisplay] = [],
        providerReceptionLines: [SecretaryPanelInfoLineDisplay] = [],
        requesterReviewLines: [SecretaryPanelInfoLineDisplay] = [],
        draftFactsUsed: [String] = [],
        extraSections: [SecretaryPanelSectionDisplay] = []
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activityType = activityType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latestMovement = latestMovement.trimmingCharacters(in: .whitespacesAndNewlines)
        self.meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentState = currentState.trimmingCharacters(in: .whitespacesAndNewlines)
        self.boundary = boundary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nextMove = nextMove.trimmingCharacters(in: .whitespacesAndNewlines)
        self.primaryTitle = primaryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secondaryTitle = secondaryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.execution = execution
        self.threadID = threadID

        self.whatChanged = Self.cleanedList(whatChanged)
        self.operatingContext = operatingContext.filter(\.isRenderable)
        self.stanceLines = stanceLines.filter(\.isRenderable)
        self.decisionLines = decisionLines.filter(\.isRenderable)
        self.providerReceptionLines = providerReceptionLines.filter(\.isRenderable)
        self.requesterReviewLines = requesterReviewLines.filter(\.isRenderable)
        self.draftFactsUsed = Self.cleanedList(draftFactsUsed)
        self.extraSections = extraSections.filter(\.isRenderable)
    }

    var hasSecondHalfDepth: Bool {
        !whatChanged.isEmpty ||
        !operatingContext.isEmpty ||
        !stanceLines.isEmpty ||
        !decisionLines.isEmpty ||
        !providerReceptionLines.isEmpty ||
        !requesterReviewLines.isEmpty ||
        !draftFactsUsed.isEmpty ||
        !extraSections.isEmpty
    }

    private static func cleanedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            output.append(trimmed)
        }

        return output
    }
}

struct SecretaryApprovalPanelDisplay: Hashable {
    let title: String
    let decisionType: String
    let summary: String
    let boundary: String
    let draftSubject: String?
    let draftBody: String?
    let rationale: String?
    let primaryTitle: String
    let secondaryTitle: String
    let threadID: ExchangeThread.ID?
    let approvalID: ExchangeApproval.ID?

    /// When true and `approvalID` is nil, the primary action should call
    /// `ExchangeFacade.queuePreparedSecondHalfOutboundSend` instead of `approveAndQueue`.
    let prefersSecondHalfPreparedSend: Bool

    /// Decision-aware approval details.
    ///
    /// These allow the approval sheet to render more than “prepared draft.”
    let decisionSummary: String?
    let recommendation: String?
    let commitmentBoundaryTitle: String?
    let commitmentBoundaryReason: String?
    let requiresHumanApproval: Bool
    let clarifiedFacts: [String]
    let unresolvedIssues: [String]
    let tradeoffs: [String]
    let whatChanged: [String]
    let approvalReasons: [String]
    let extraSections: [SecretaryPanelSectionDisplay]

    init(
        title: String,
        decisionType: String,
        summary: String,
        boundary: String,
        draftSubject: String? = nil,
        draftBody: String? = nil,
        rationale: String? = nil,
        primaryTitle: String,
        secondaryTitle: String,
        threadID: ExchangeThread.ID? = nil,
        approvalID: ExchangeApproval.ID? = nil,
        prefersSecondHalfPreparedSend: Bool = false,
        decisionSummary: String? = nil,
        recommendation: String? = nil,
        commitmentBoundaryTitle: String? = nil,
        commitmentBoundaryReason: String? = nil,
        requiresHumanApproval: Bool = false,
        clarifiedFacts: [String] = [],
        unresolvedIssues: [String] = [],
        tradeoffs: [String] = [],
        whatChanged: [String] = [],
        approvalReasons: [String] = [],
        extraSections: [SecretaryPanelSectionDisplay] = []
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.decisionType = decisionType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.boundary = boundary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.draftSubject = draftSubject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.draftBody = draftBody?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.rationale = rationale?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.primaryTitle = primaryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secondaryTitle = secondaryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.threadID = threadID
        self.approvalID = approvalID
        self.prefersSecondHalfPreparedSend = prefersSecondHalfPreparedSend

        self.decisionSummary = decisionSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.recommendation = recommendation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.commitmentBoundaryTitle = commitmentBoundaryTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.commitmentBoundaryReason = commitmentBoundaryReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.requiresHumanApproval = requiresHumanApproval
        self.clarifiedFacts = Self.cleanedList(clarifiedFacts)
        self.unresolvedIssues = Self.cleanedList(unresolvedIssues)
        self.tradeoffs = Self.cleanedList(tradeoffs)
        self.whatChanged = Self.cleanedList(whatChanged)
        self.approvalReasons = Self.cleanedList(approvalReasons)
        self.extraSections = extraSections.filter(\.isRenderable)
    }

    var hasPreparedDraft: Bool {
        draftSubject != nil || draftBody != nil
    }

    var hasDecisionPacket: Bool {
        decisionSummary != nil ||
        recommendation != nil ||
        !clarifiedFacts.isEmpty ||
        !unresolvedIssues.isEmpty ||
        !tradeoffs.isEmpty ||
        !whatChanged.isEmpty
    }

    /// Adapter / projection often emits placeholder copy; do not treat it as a real commitment-boundary surface.
    static func isPlaceholderCommitmentBoundaryText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        return lower == "no boundary reason recorded."
            || lower == "no boundary recorded."
            || lower == "no boundary reason."
    }

    var hasPendingApprovalAction: Bool {
        approvalID != nil
    }

    var hasPreparedSendAction: Bool {
        prefersSecondHalfPreparedSend
    }

    /// Matches ``SecretaryOutboundApproveSend.perform`` eligibility: pending approval row or prepared-send bridge.
    var canRunPrimaryAction: Bool {
        hasPendingApprovalAction || hasPreparedSendAction
    }

    var canRunRejectAction: Bool {
        hasPendingApprovalAction
    }

    /// Primary CTA label aligned with the executable backend path (never "Approve" for prepared-only send).
    var resolvedPrimaryActionTitle: String {
        if prefersSecondHalfPreparedSend, approvalID == nil {
            return "Send"
        }
        return primaryTitle
    }

    /// When false, the sheet hides the “Human approval” pill to avoid “Not required” beside Approve/Send.
    var shouldShowHumanApprovalPill: Bool {
        requiresHumanApproval
    }

    var hasCommitmentBoundary: Bool {
        if requiresHumanApproval { return true }
        if !approvalReasons.isEmpty { return true }
        if let title = commitmentBoundaryTitle, !Self.isPlaceholderCommitmentBoundaryText(title) {
            return true
        }
        if let reason = commitmentBoundaryReason, !Self.isPlaceholderCommitmentBoundaryText(reason) {
            return true
        }
        return false
    }

    private static func cleanedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            output.append(trimmed)
        }

        return output
    }
}

extension SecretaryApprovalPanelDisplay {
    /// Prefer a concrete pending approval row when navigating from notifications.
    func withPreferredApprovalID(_ id: ExchangeApproval.ID?) -> SecretaryApprovalPanelDisplay {
        SecretaryApprovalPanelDisplay(
            title: title,
            decisionType: decisionType,
            summary: summary,
            boundary: boundary,
            draftSubject: draftSubject,
            draftBody: draftBody,
            rationale: rationale,
            primaryTitle: primaryTitle,
            secondaryTitle: secondaryTitle,
            threadID: threadID,
            approvalID: id ?? approvalID,
            prefersSecondHalfPreparedSend: prefersSecondHalfPreparedSend,
            decisionSummary: decisionSummary,
            recommendation: recommendation,
            commitmentBoundaryTitle: commitmentBoundaryTitle,
            commitmentBoundaryReason: commitmentBoundaryReason,
            requiresHumanApproval: requiresHumanApproval,
            clarifiedFacts: clarifiedFacts,
            unresolvedIssues: unresolvedIssues,
            tradeoffs: tradeoffs,
            whatChanged: whatChanged,
            approvalReasons: approvalReasons,
            extraSections: extraSections
        )
    }
}

struct SecretaryCompareOptionDisplay: Identifiable, Hashable {
    let id: UUID
    let candidateCounterpartyID: String?
    let title: String
    let subtitle: String
    let trustLine: String
    let exposureLine: String
    let recommendationLine: String
    let isPreferred: Bool
    let isActionable: Bool

    /// Richer requester-review / decision-comparison lines.
    let strengthReasons: [String]
    let weaknessReasons: [String]
    let missingFacts: [String]
    let readinessLine: String?
    let boundaryLine: String?
    let nextMoveLine: String?

    init(
        id: UUID? = nil,
        candidateCounterpartyID: String? = nil,
        title: String,
        subtitle: String,
        trustLine: String,
        exposureLine: String,
        recommendationLine: String,
        isPreferred: Bool = false,
        isActionable: Bool? = nil,
        strengthReasons: [String] = [],
        weaknessReasons: [String] = [],
        missingFacts: [String] = [],
        readinessLine: String? = nil,
        boundaryLine: String? = nil,
        nextMoveLine: String? = nil
    ) {
        if let id {
            self.id = id
        } else if let candidateCounterpartyID,
                  let stableID = UUID(uuidString: candidateCounterpartyID) {
            self.id = stableID
        } else {
            self.id = UUID()
        }

        self.candidateCounterpartyID = candidateCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trustLine = trustLine.trimmingCharacters(in: .whitespacesAndNewlines)
        self.exposureLine = exposureLine.trimmingCharacters(in: .whitespacesAndNewlines)
        self.recommendationLine = recommendationLine.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isPreferred = isPreferred
        self.isActionable = isActionable ?? (candidateCounterpartyID != nil)

        self.strengthReasons = Self.cleanedList(strengthReasons)
        self.weaknessReasons = Self.cleanedList(weaknessReasons)
        self.missingFacts = Self.cleanedList(missingFacts)
        self.readinessLine = readinessLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.boundaryLine = boundaryLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.nextMoveLine = nextMoveLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    var hasReviewDepth: Bool {
        !strengthReasons.isEmpty ||
        !weaknessReasons.isEmpty ||
        !missingFacts.isEmpty ||
        readinessLine != nil ||
        boundaryLine != nil ||
        nextMoveLine != nil
    }

    private static func cleanedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            output.append(trimmed)
        }

        return output
    }
}

struct SecretaryComparePanelDisplay: Hashable {
    let title: String
    let summary: String
    let options: [SecretaryCompareOptionDisplay]
    let primaryTitle: String
    let secondaryTitle: String
    let threadID: ExchangeThread.ID?

    /// Allows the same panel to represent normal path comparison or a
    /// second-half opportunity review around one current opportunity.
    let panelKind: String
    let recommendation: String?
    let exposureSummary: String?
    let trustSummary: String?
    let readinessSummary: String?
    let missingFacts: [String]
    let strengthReasons: [String]
    let weaknessReasons: [String]
    let extraSections: [SecretaryPanelSectionDisplay]

    init(
        title: String,
        summary: String,
        options: [SecretaryCompareOptionDisplay],
        primaryTitle: String,
        secondaryTitle: String,
        threadID: ExchangeThread.ID? = nil,
        panelKind: String = "Compare Paths",
        recommendation: String? = nil,
        exposureSummary: String? = nil,
        trustSummary: String? = nil,
        readinessSummary: String? = nil,
        missingFacts: [String] = [],
        strengthReasons: [String] = [],
        weaknessReasons: [String] = [],
        extraSections: [SecretaryPanelSectionDisplay] = []
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.options = options
        self.primaryTitle = primaryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secondaryTitle = secondaryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.threadID = threadID

        self.panelKind = panelKind.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Compare Paths"
        self.recommendation = recommendation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.exposureSummary = exposureSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.trustSummary = trustSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.readinessSummary = readinessSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.missingFacts = Self.cleanedList(missingFacts)
        self.strengthReasons = Self.cleanedList(strengthReasons)
        self.weaknessReasons = Self.cleanedList(weaknessReasons)
        self.extraSections = extraSections.filter(\.isRenderable)
    }

    var hasOpportunityReviewDepth: Bool {
        recommendation != nil ||
        exposureSummary != nil ||
        trustSummary != nil ||
        readinessSummary != nil ||
        !missingFacts.isEmpty ||
        !strengthReasons.isEmpty ||
        !weaknessReasons.isEmpty ||
        !extraSections.isEmpty ||
        options.contains(where: \.hasReviewDepth)
    }

    private static func cleanedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            output.append(trimmed)
        }

        return output
    }
}

struct SecretaryRecoveryPanelDisplay: Hashable {
    let title: String
    let recoveryType: String
    let whatHappened: String
    let whatDidNotHappen: String
    let externalEffect: String
    let bestNextMove: String
    let primaryTitle: String
    let secondaryTitle: String
    let threadID: ExchangeThread.ID?

    init(
        title: String,
        recoveryType: String,
        whatHappened: String,
        whatDidNotHappen: String,
        externalEffect: String,
        bestNextMove: String,
        primaryTitle: String,
        secondaryTitle: String,
        threadID: ExchangeThread.ID? = nil
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.recoveryType = recoveryType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.whatHappened = whatHappened.trimmingCharacters(in: .whitespacesAndNewlines)
        self.whatDidNotHappen = whatDidNotHappen.trimmingCharacters(in: .whitespacesAndNewlines)
        self.externalEffect = externalEffect.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bestNextMove = bestNextMove.trimmingCharacters(in: .whitespacesAndNewlines)
        self.primaryTitle = primaryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secondaryTitle = secondaryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.threadID = threadID
    }
}

struct SecretaryTrustedPathPanelDisplay: Hashable {
    let title: String
    let summary: String
    let relationshipLabel: String
    let trustLabel: String
    let activityLabel: String
    let examples: [String]
    let primaryTitle: String
    let secondaryTitle: String
    let threadID: ExchangeThread.ID?
    /// When true, primary action should send a prepared second-half draft (if still sendable).
    let sendPreparedDraftAvailable: Bool
    /// When there is no linked thread, primary/secondary route to Ask Secretary / Message compose.
    let trustComposerFallback: Bool
    let trustedNodeID: String?
    let trustedNodeDisplayName: String?

    init(
        title: String,
        summary: String,
        relationshipLabel: String = "Trusted Path",
        trustLabel: String = "Warm / known route",
        activityLabel: String = "Available",
        examples: [String] = [],
        primaryTitle: String = "Open thread",
        secondaryTitle: String = "Not now",
        threadID: ExchangeThread.ID? = nil,
        sendPreparedDraftAvailable: Bool = false,
        trustComposerFallback: Bool = false,
        trustedNodeID: String? = nil,
        trustedNodeDisplayName: String? = nil
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.relationshipLabel = relationshipLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trustLabel = trustLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activityLabel = activityLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.examples = examples
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.primaryTitle = primaryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secondaryTitle = secondaryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.threadID = threadID
        self.sendPreparedDraftAvailable = sendPreparedDraftAvailable
        self.trustComposerFallback = trustComposerFallback
        self.trustedNodeID = trustedNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.trustedNodeDisplayName = trustedNodeDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
