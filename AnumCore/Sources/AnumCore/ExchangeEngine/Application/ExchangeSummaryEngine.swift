import Foundation

/// Produces concise, user-legible summaries for exchange threads.
///
/// This engine should explain:
/// - what happened
/// - what did not happen
/// - whether anything changed externally
/// - what the next best move is
public struct ExchangeSummaryEngine: Sendable {
    public init() {}

    public func threadSummary(
        thread: ExchangeThread,
        latestTurn: ExchangeTurn? = nil
    ) -> String {
        if let failure = thread.latestFailure {
            return failureSummary(failure)
        }

        if let outcome = thread.outcome,
           case .resolved = thread.state {
            return outcome.summary
        }

        switch thread.state {
        case .drafting:
            return draftingSummary(thread)

        case .draftReady(let status):
            return draftReadySummary(thread, status: status)

        case .needsClarification(let status):
            return clarificationSummary(thread, status: status)

        case .searching(let status):
            return searchingSummary(thread, status: status)

        case .matchFound(let status):
            return matchFoundSummary(thread, status: status)

        case .matchCandidatesWeak(let status):
            return weakMatchSummary(thread, status: status)

        case .noViableMatch(let status):
            return noMatchSummary(thread, status: status)

        case .awaitingApproval(let status):
            return approvalStateSummary(thread, status: status)

        case .sending(let status):
            return sendingSummary(thread, status: status)

        case .blockedByDeliveryFailure:
            if let failure = thread.latestFailure {
                return failureSummary(failure)
            }
            if let deliveryNote = nonBlank(thread.delivery?.note) {
                return deliveryNote
            }
            return "Delivery did not complete successfully."

        case .awaitingResponse(let status):
            return awaitingResponseSummary(thread, status: status)

        case .declined(let status):
            if let reason = nonBlank(status.reasonSummary) {
                return reason
            }
            return "The proposed action was declined."

        case .stalled(let status):
            return stalledSummary(thread, status: status)

        case .resolved(let status):
            return resolvedSummary(thread, status: status)

        case .blockedBySystemFailure:
            if let failure = thread.latestFailure {
                return failureSummary(failure)
            }
            return "A system issue interrupted the thread."
        }
    }

    public func inboxLine(
        thread: ExchangeThread,
        latestTurn: ExchangeTurn? = nil
    ) -> String {
        threadSummary(thread: thread, latestTurn: latestTurn)
    }

    public func approvalSummary(
        approval: ExchangeApproval,
        draft: ExchangeMessageDraft?
    ) -> String {
        guard let draft else {
            return approval.summary
        }

        let preview = draft.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preview.isEmpty else {
            return approval.summary
        }

        return "\(approval.summary) \(preview)"
    }

    public func outcomeSummary(_ outcome: ExchangeOutcome) -> String {
        outcome.visibleExplanation
    }

    public func failureSummary(_ failure: ExchangeFailure) -> String {
        [
            failure.summary,
            "What happened: \(cleanSentence(failure.whatHappened))",
            "What did not happen: \(cleanSentence(failure.whatDidNotHappen))",
            "External status: \(cleanSentence(failure.externalEffect.summaryLine))",
            "Next step: \(cleanSentence(failure.recommendedNextStep.summaryLine))"
        ]
        .joined(separator: "\n\n")
    }
}

private extension ExchangeSummaryEngine {
    func draftingSummary(_ thread: ExchangeThread) -> String {
        if let expectationLine = expectationHeadline(thread.expectation) {
            return "I captured the request and am preparing the thread. \(expectationLine)"
        }
        return "I captured the request and am preparing the thread."
    }

    func draftReadySummary(
        _ thread: ExchangeThread,
        status: ExchangeState.DraftReadyStatus
    ) -> String {
        var parts: [String] = []

        if let summary = nonBlank(status.summary) {
            parts.append(summary)
        } else {
            parts.append("A draft has been prepared and is being held locally.")
        }

        if let expectationLine = expectationHeadline(thread.expectation) {
            parts.append(expectationLine)
        }

        if let triggerLine = decisionTriggerLine(thread.expectation) {
            parts.append(triggerLine)
        }

        return parts.joined(separator: " ")
    }

    func clarificationSummary(
        _ thread: ExchangeThread,
        status: ExchangeState.ClarificationStatus
    ) -> String {
        var parts: [String] = []

        if let expectationLine = expectationHeadline(thread.expectation) {
            parts.append(expectationLine)
        }

        parts.append(status.question)

        if let triggerLine = decisionTriggerLine(thread.expectation) {
            parts.append(triggerLine)
        }

        return parts.joined(separator: "\n\n")
    }

    func searchingSummary(
        _ thread: ExchangeThread,
        status: ExchangeState.SearchStatus
    ) -> String {
        let subject = summarySubject(for: thread)

        var first = "I’m searching for viable matches."
        if let subject, !subject.isEmpty {
            first = "I’m searching for viable matches for \(subject)."
        }

        var extras: [String] = []

        if let expectationLine = expectationHeadline(thread.expectation) {
            extras.append(expectationLine)
        }

        if let autonomy = autonomyLine(thread.expectation) {
            extras.append(autonomy)
        }

        return ([first] + extras).joined(separator: " ")
    }

    func matchFoundSummary(
        _ thread: ExchangeThread,
        status: ExchangeState.MatchFoundStatus
    ) -> String {
        var parts: [String] = []

        if let selectedName = selectedCounterpartyLabel(from: thread, status: status) {
            parts.append("I found a likely path through \(selectedName).")
        } else if let subject = summarySubject(for: thread) {
            parts.append("I found a likely match for \(subject).")
        } else if let summary = nonBlank(status.summary) {
            parts.append(cleanSentence(summary))
        } else {
            parts.append("I found a likely path.")
        }

        if status.candidateCount > 1 {
            parts.append("\(status.candidateCount) candidates were considered, and one path is currently selected.")
        }

        if let next = nonBlank(status.nextStep) {
            parts.append(cleanSentence(next))
        } else if let next = nonBlank(thread.interpretation?.userNextStep) {
            parts.append(cleanSentence(next))
        } else {
            parts.append("Next step: review this path before anything moves outward.")
        }

        if let expectationLine = expectationHeadline(thread.expectation) {
            parts.append(expectationLine)
        }

        return parts.joined(separator: " ")
    }

    func weakMatchSummary(
        _ thread: ExchangeThread,
        status: ExchangeState.WeakMatchStatus
    ) -> String {
        var parts: [String] = []

        if let subject = summarySubject(for: thread) {
            parts.append("I found possible matches for \(subject), but none are strong enough to advance confidently yet.")
        } else {
            parts.append("I found possible matches, but none are strong enough to advance confidently yet.")
        }

        if let refinement = nonBlank(status.suggestedRefinement) {
            parts.append(cleanSentence(refinement))
        }

        if let outcomeLine = outcomeTargetLine(thread.expectation) {
            parts.append(outcomeLine)
        }

        return parts.joined(separator: " ")
    }

    func noMatchSummary(
        _ thread: ExchangeThread,
        status: ExchangeState.NoMatchStatus
    ) -> String {
        var parts: [String] = []

        if let subject = summarySubject(for: thread) {
            parts.append("I understood this as a request for \(subject), but I could not find a viable match yet.")
        } else {
            parts.append("I understood the request, but I could not find a viable match yet.")
        }

        if let next = nonBlank(status.suggestedNextStep) {
            parts.append(cleanSentence(next))
        }

        if let outcomeLine = outcomeTargetLine(thread.expectation) {
            parts.append(outcomeLine)
        }

        return parts.joined(separator: " ")
    }

    func approvalStateSummary(
        _ thread: ExchangeThread,
        status: ExchangeState.ApprovalStatus
    ) -> String {
        var parts: [String] = [status.summary]

        if let expectationLine = expectationHeadline(thread.expectation) {
            parts.append(expectationLine)
        }

        if let autonomy = autonomyLine(thread.expectation) {
            parts.append(autonomy)
        }

        return parts.joined(separator: " ")
    }

    func sendingSummary(
        _ thread: ExchangeThread,
        status: ExchangeState.SendingStatus
    ) -> String {
        let base: String

        if let delivery = thread.delivery {
            switch delivery.status {
            case .readyToSend:
                base = "Approval is in place and the outbound step is ready to send."
            case .sending:
                base = "The outbound step is now being sent."
            case .sent:
                base = "The outbound step was sent and is awaiting the next update."
            case .failed:
                base = nonBlank(delivery.note) ?? "The outbound step failed."
            case .pendingApproval:
                base = "The outbound step is still waiting for approval."
            case .notStarted:
                base = "The outbound step is in progress."
            }
        } else if let channel = nonBlank(status.channelSummary) {
            base = "The outbound step is in progress. \(channel)"
        } else {
            base = "The outbound step is in progress."
        }

        var parts: [String] = [base]

        if let expectationLine = expectationHeadline(thread.expectation) {
            parts.append(expectationLine)
        }

        if let autonomy = autonomyLine(thread.expectation) {
            parts.append(autonomy)
        }

        return parts.joined(separator: " ")
    }

    func awaitingResponseSummary(
        _ thread: ExchangeThread,
        status: ExchangeState.ResponseWaitStatus
    ) -> String {
        var base = "The thread is waiting for a response."

        if let delivery = thread.delivery,
           delivery.status == .sent || delivery.status == .sending {
            base = "The outbound step was confirmed, and the thread is now waiting for a response."
        } else if status.lastOutboundAt != nil {
            base = "The outbound step has been sent, and the thread is now waiting for a response."
        }

        var parts: [String] = [base]

        if let completion = completionSignalLine(thread.expectation) {
            parts.append(completion)
        }

        if let autonomy = autonomyLine(thread.expectation) {
            parts.append(autonomy)
        }

        return parts.joined(separator: " ")
    }

    func stalledSummary(
        _ thread: ExchangeThread,
        status: ExchangeState.StallStatus
    ) -> String {
        var parts: [String] = [status.reasonSummary]

        if let triggerLine = decisionTriggerLine(thread.expectation) {
            parts.append(triggerLine)
        }

        return parts.joined(separator: " ")
    }

    func resolvedSummary(
        _ thread: ExchangeThread,
        status: ExchangeState.ResolutionStatus
    ) -> String {
        if let expectationLine = expectationHeadline(thread.expectation) {
            return "\(status.summary) \(expectationLine)"
        }
        return status.summary
    }

    func selectedCounterpartyLabel(
        from thread: ExchangeThread,
        status: ExchangeState.MatchFoundStatus
    ) -> String? {
        if let rationale = nonBlank(thread.selectedMatchRationale) {
            return cleanSummaryPhrase(rationale)
        }

        if let counterpartyID = nonBlank(status.selectedCounterpartyID) {
            return counterpartyID
        }

        if let profileID = nonBlank(status.selectedPublicProfileID) {
            return profileID
        }

        if let offerID = nonBlank(status.selectedOfferID) {
            return offerID
        }

        if let threadCounterpartyID = nonBlank(thread.selectedCounterpartyID) {
            return threadCounterpartyID
        }

        return nil
    }

    func expectationHeadline(_ expectation: ExchangeExpectation?) -> String? {
        guard let expectation else { return nil }

        let goal = primaryGoalLine(expectation.primaryGoal)
        let preferred = outcomeTargetLabel(expectation.preferredOutcome)
        let acceptable = outcomeTargetLabel(expectation.acceptableOutcome)

        return "Goal: \(goal). Preferred result: \(preferred). Acceptable result: \(acceptable)."
    }

    func completionSignalLine(_ expectation: ExchangeExpectation?) -> String? {
        guard let expectation else { return nil }
        guard !expectation.completionSignals.isEmpty else { return nil }

        let rendered = expectation.completionSignals
            .prefix(3)
            .map(completionSignalLabel)
            .joined(separator: ", ")

        guard !rendered.isEmpty else { return nil }
        return "Completion signals: \(rendered)."
    }

    func outcomeTargetLine(_ expectation: ExchangeExpectation?) -> String? {
        guard let expectation else { return nil }

        return "Preferred result: \(outcomeTargetLabel(expectation.preferredOutcome)). Acceptable result: \(outcomeTargetLabel(expectation.acceptableOutcome))."
    }

    func autonomyLine(_ expectation: ExchangeExpectation?) -> String? {
        guard let expectation else { return nil }

        var parts: [String] = []

        if expectation.maxAutoReplies > 0 {
            parts.append("Auto-reply budget remaining: \(expectation.autoReplyBudgetRemaining) of \(expectation.maxAutoReplies).")
        } else {
            parts.append("No autonomous back-and-forth is currently budgeted.")
        }

        if !expectation.stopConditions.isEmpty {
            let stopText = expectation.stopConditions
                .prefix(3)
                .map(stopConditionLabel)
                .joined(separator: ", ")

            if !stopText.isEmpty {
                parts.append("Autonomy stops when: \(stopText).")
            }
        }

        return parts.joined(separator: " ")
    }

    func decisionTriggerLine(_ expectation: ExchangeExpectation?) -> String? {
        guard let expectation else { return nil }
        guard !expectation.requiresUserDecisionOn.isEmpty else { return nil }

        let rendered = expectation.requiresUserDecisionOn
            .prefix(3)
            .map(userDecisionTriggerLabel)
            .joined(separator: ", ")

        guard !rendered.isEmpty else { return nil }
        return "User decision may be needed for: \(rendered)."
    }

    func primaryGoalLine(_ value: ExchangeExpectation.PrimaryGoal) -> String {
        switch value {
        case .obtainQuote: return "obtain a quote"
        case .establishContact: return "establish contact"
        case .secureIntroduction: return "secure an introduction"
        case .arrangeCall: return "arrange a call"
        case .arrangeMeeting: return "arrange a meeting"
        case .gatherInformation: return "gather information"
        case .confirmAvailability: return "confirm availability"
        case .confirmFit: return "confirm fit"
        case .advanceNegotiation: return "advance negotiation"
        case .resolveThread: return "resolve the thread"
        case .other: return "move the request forward"
        }
    }

    func outcomeTargetLabel(_ value: ExchangeExpectation.OutcomeTarget) -> String {
        switch value {
        case .completed: return "completed"
        case .meaningfulProgress: return "meaningful progress"
        case .basicResponse: return "a basic response"
        }
    }

    func completionSignalLabel(_ value: ExchangeExpectation.CompletionSignal) -> String {
        switch value {
        case .quoteReceived: return "quote received"
        case .introAccepted: return "introduction accepted"
        case .introDeclined: return "introduction declined"
        case .availabilityConfirmed: return "availability confirmed"
        case .meetingProposed: return "meeting proposed"
        case .meetingConfirmed: return "meeting confirmed"
        case .answerReceived: return "answer received"
        case .capabilityConfirmed: return "capability confirmed"
        case .capabilityDeclined: return "capability declined"
        case .scopeClarified: return "scope clarified"
        case .termsAccepted: return "terms accepted"
        case .explicitDecline: return "explicit decline"
        case .resolvedByUser: return "resolved by user"
        }
    }

    func stopConditionLabel(_ value: ExchangeExpectation.StopCondition) -> String {
        switch value {
        case .autoReplyBudgetExhausted: return "auto-reply budget is exhausted"
        case .counterpartyRequestsSensitiveInfo: return "sensitive information is requested"
        case .counterpartyRequestsCommitment: return "commitment is requested"
        case .counterpartyChangesScopeMaterially: return "scope changes materially"
        case .counterpartyIntroducesPricingNegotiation: return "pricing negotiation appears"
        case .counterpartyIntroducesContractualTerms: return "contractual terms appear"
        case .ambiguityTooHigh: return "ambiguity becomes too high"
        case .repeatedLoopDetected: return "a repeated loop is detected"
        case .userInputRequired: return "user input is required"
        case .approvalRequired: return "approval is required"
        case .disclosureBoundaryReached: return "the disclosure boundary is reached"
        }
    }

    func userDecisionTriggerLabel(_ value: ExchangeExpectation.UserDecisionTrigger) -> String {
        switch value {
        case .approveOutbound: return "approve outbound"
        case .answerMissingInfo: return "answer missing information"
        case .chooseBetweenOptions: return "choose between options"
        case .reviewQuote: return "review quote"
        case .reviewCounteroffer: return "review counteroffer"
        case .approveCommitment: return "approve commitment"
        case .approveDisclosureExpansion: return "approve broader disclosure"
        case .confirmSchedulingChoice: return "confirm scheduling choice"
        case .resolveAmbiguity: return "resolve ambiguity"
        }
    }

    func summarySubject(for thread: ExchangeThread) -> String? {
        if let target = nonBlank(thread.intent.targetDescription) {
            return cleanSummaryPhrase(target)
        }

        if let role = nonBlank(thread.facets?.targetRole) {
            if let place = nonBlank(thread.facets?.placeName ?? thread.facets?.locationText) {
                return "\(cleanSummaryPhrase(role)) in \(cleanSummaryPhrase(place))"
            }
            return cleanSummaryPhrase(role)
        }

        if let activity = nonBlank(thread.facets?.activity) {
            if let place = nonBlank(thread.facets?.placeName ?? thread.facets?.locationText) {
                return "\(cleanSummaryPhrase(activity)) in \(cleanSummaryPhrase(place))"
            }
            return cleanSummaryPhrase(activity)
        }

        let title = nonBlank(thread.intent.title)
        if let title, title.lowercased() != "exchange request" {
            return cleanSummaryPhrase(title)
        }

        return nil
    }

    func cleanSummaryPhrase(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanSentence(_ value: String) -> String {
        let cleaned = cleanSummaryPhrase(value)
        guard !cleaned.isEmpty else { return value }

        let lower = cleaned.lowercased()

        if lower.contains("relationshipled") ||
            lower.contains("localservice") ||
            lower.contains("physicalgoods") ||
            lower.contains("digitalservice") ||
            lower.contains("informationrequest") ||
            lower.contains("high-fit-preferred") ||
            lower.contains("selection ") ||
            lower.contains("number multiple") {
            return "The current result needs refinement before it can move forward."
        }

        return cleaned
    }

    func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
