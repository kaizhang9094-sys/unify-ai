import Foundation

fileprivate func userFacingRenderableExternalOutboundDraft(for detail: ExchangeModels.ThreadDetail) -> Bool {
    ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(
        in: detail.drafts,
        thread: detail.thread,
        turns: detail.turns
    )
}

/// Stateless assembly of `ExchangeThreadSituation` from canonical `ThreadDetail` snapshots.
public enum ExchangeThreadSituationBuilder {

    /// - Parameters:
    ///   - resolvedOffer / resolvedPublicProfile: optional rows from `ExchangeStore` when ids are present.
    public static func build(
        detail: ExchangeModels.ThreadDetail,
        resolvedOffer: ExchangeOffer? = nil,
        resolvedPublicProfile: ExchangePublicNodeProfile? = nil
    ) -> ExchangeThreadSituation {
        let thread = detail.thread
        let drafts = sortedDrafts(from: detail)
        let latestDraft = drafts.first

        let pendingApproval = latestPendingApproval(for: detail)
        let pendingDraftForApproval: ExchangeMessageDraft? = pendingApproval.flatMap { approval in
            guard let draftID = approval.draftID else { return nil }
            return detail.drafts.first(where: { $0.id == draftID })
        }
        let pendingDraftPreviewSource = pendingDraftForApproval ?? latestDraft

        let secondHalf = detail.secondHalfDisplay

        let phaseLabel = thread.state.phaseTitle
        let agencyPhaseTitle = secondHalf?.agencyPhaseTitle
        let agencyPhaseDetail = secondHalf?.agencyPhaseDetail

        let trimmedTitle = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? "Untitled thread" : trimmedTitle

        let baseSummary =
            (detail.interpretationSummary?.nilIfBlank)
            ?? detail.summary.nilIfBlank
            ?? phaseLabel

        let cpName = selectedCounterpartyName(for: detail)

        let offerDisplayTitle = resolvedOffer.flatMap { o in
            let t = o.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        let profileDisplayTitle = resolvedPublicProfile.map(profileDisplayTitle(_:))

        let selectedOfferImageURLs: [String] = resolvedOffer?.normalizedPublicOfferImageURLs() ?? []

        let presentationLead = ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: thread.selectedOfferID,
            selectedPublicProfileID: thread.selectedPublicProfileID
        )

        let primaryURL: String? = {
            switch presentationLead {
            case .offerLed:
                if let offer = resolvedOffer, let o = offer.displayHeroImageURL.flatMap({ $0.nilIfBlank }) {
                    return o
                }
                if let profile = resolvedPublicProfile, let p = profile.primaryImageURL.flatMap({ $0.nilIfBlank }) {
                    return p
                }
                return matchMetadataImageURL(from: detail.selectedMatch?.metadata ?? [:])

            case .profileLed:
                if let profile = resolvedPublicProfile, let p = profile.primaryImageURL.flatMap({ $0.nilIfBlank }) {
                    return p
                }
                if let fromMeta = matchMetadataImageURL(
                    from: detail.selectedMatch?.metadata ?? [:],
                    keys: ["primary_image_url", "image_url"]
                ) {
                    return fromMeta
                }
                if let offer = resolvedOffer, let o = offer.displayHeroImageURL.flatMap({ $0.nilIfBlank }) {
                    return o
                }
                return matchMetadataImageURL(
                    from: detail.selectedMatch?.metadata ?? [:],
                    keys: ["offer_image_url", "primary_image_url", "image_url"]
                )

            case .ambiguous:
                if let offer = resolvedOffer, let o = offer.displayHeroImageURL.flatMap({ $0.nilIfBlank }) {
                    return o
                }
                if let profile = resolvedPublicProfile, let p = profile.primaryImageURL.flatMap({ $0.nilIfBlank }) {
                    return p
                }
                return matchMetadataImageURL(from: detail.selectedMatch?.metadata ?? [:])
            }
        }()

        let hasPersistedActionableOutboundDraft =
            userFacingRenderableExternalOutboundDraft(for: detail)

        let delivery = deliveryStatusLine(
            thread: thread,
            latestApproval: pendingApproval,
            hasPersistedActionableOutboundDraft: hasPersistedActionableOutboundDraft,
            secondHalf: secondHalf
        )

        let boundary = combinedBoundary(secondHalf: secondHalf, detail: detail)
        let nextMove = combinedNextMove(secondHalf: secondHalf, detail: detail)

        let missingFacts = mergedMissingFacts(secondHalf: secondHalf)
        let whatChanged = sanitizeLines(secondHalf?.decision?.whatChanged ?? [])

        let strengths = mergedStrengths(secondHalf: secondHalf)
        let weaknesses = mergedWeaknesses(secondHalf: secondHalf)

        let trustLine =
            secondHalf.flatMap { nonBlankLine($0.operatingContext.trust) }
            ?? thread.selectedMatchRationale?.nilIfBlank

        let reachability = secondHalf.flatMap { nonBlankLine($0.operatingContext.postureSummary) }

        let userIntentTurn = detail.turns.last(where: { $0.kind == .requestCaptured })

        let (inboundLine, outboundLine) = latestInboundOutboundLines(detail.turns)

        let needsJudgmentFlag =
            pendingApproval?.status == .pending
            || secondHalf?.needsHumanAttention == true
            || (secondHalf?.decision?.needsUserJudgment ?? false)

        let autonomyFlag = secondHalf?.canRunAutonomously ?? false

        let buttonHints = sanitizedButtonTitles(secondHalf?.buttons ?? [])

        var explanations: [String] = []

        if let offerDisplayTitle {
            explanations.append("Selected offer: \(offerDisplayTitle)")
        } else if let oid = thread.selectedOfferID.flatMap({ $0.nilIfBlank }) {
            explanations.append("Selected offer id: \(oid)")
        }

        if let profileDisplayTitle {
            explanations.append("Selected surface: \(profileDisplayTitle)")
        } else if let pid = thread.selectedPublicProfileID.flatMap({ $0.nilIfBlank }) {
            explanations.append("Selected public surface id: \(pid)")
        }

        if let cpName {
            explanations.append("Counterparty: \(cpName)")
        }

        explanations.append("Boundary: \(boundary)")
        explanations.append("Next move: \(nextMove)")
        explanations.append(delivery)

        if isAwaitingResponse(detail) {
            explanations.append("Waiting on the other side.")
        }

        if pendingApproval != nil {
            explanations.append("Needs approval.")
        }

        if !missingFacts.isEmpty {
            let sample = missingFacts.prefix(3).joined(separator: "; ")
            explanations.append("Missing: \(sample)")
        }

        explanations = uniquedLines(explanations)

        let commercialSurfaceFactLines: [String] = resolvedOffer.flatMap { offer -> [String] in
            guard offer.commercialFacts.hasPublishedCommercialSurface else {
                return []
            }
            return Array(offer.commercialSurfaceSkimLines.prefix(20))
        } ?? []

        let offerFulfillmentLine = resolvedOffer.flatMap { offerFulfillmentDisplayLine(for: $0) }
        let offerContactSummary = resolvedOffer.flatMap { offerContactDisplaySummary(for: $0) }
        let requiredBuyerInputLines = resolvedOffer.map { offerRequiredBuyerInputLines(for: $0) } ?? []
        let faqDisplayLines = resolvedOffer.map { offerFAQDisplayLines(for: $0) } ?? []
        let packageDisplayLines = resolvedOffer.map { offerPackageDisplayLines(for: $0) } ?? []

        return ExchangeThreadSituation(
            threadID: thread.id,
            title: title,
            phaseLabel: phaseLabel,
            agencyPhaseTitle: agencyPhaseTitle,
            agencyPhaseDetail: agencyPhaseDetail,
            stateSummary: baseSummary,
            roleLabel: secondHalf.flatMap { $0.roleLabel.nilIfBlank },
            counterpartyName: cpName,
            selectedPublicProfileID: thread.selectedPublicProfileID,
            selectedOfferID: thread.selectedOfferID,
            selectedPublicProfileTitle: profileDisplayTitle,
            selectedOfferTitle: offerDisplayTitle,
            selectedOfferSummary: resolvedOffer?.summary?.nilIfBlank,
            primaryImageURL: primaryURL,
            selectedOfferImageURLs: selectedOfferImageURLs,
            latestUserIntent: userIntentTurn?.summary.nilIfBlank ?? detail.interpretationSummary?.nilIfBlank,
            latestInboundLine: inboundLine,
            latestOutboundLine: outboundLine,
            pendingDraftSubject: pendingDraftPreviewSource?.subject?.nilIfBlank,
            pendingDraftPreview: draftBodyPreview(pendingDraftPreviewSource),
            hasPendingApproval: pendingApproval?.status == .pending,
            deliveryLine: delivery,
            boundaryLine: boundary,
            nextMoveLine: nextMove,
            trustLine: trustLine,
            reachabilityLine: reachability,
            missingFacts: missingFacts,
            whatChanged: whatChanged,
            strengthReasons: strengths,
            weaknessReasons: weaknesses,
            safeActionLabels: buttonHints.isEmpty
                ? defaultSafeHints(needsJudgment: needsJudgmentFlag, secondHalf: secondHalf)
                : buttonHints,
            requiresUserJudgment: needsJudgmentFlag,
            canRunAutonomously: autonomyFlag,
            groundedFactLines: [],
            answerabilityLine: nil,
            decisionNeedLines: [],
            agencySuggestions: [],
            commercialSurfaceFactLines: commercialSurfaceFactLines,
            offerFulfillmentLine: offerFulfillmentLine,
            offerContactSummary: offerContactSummary,
            requiredBuyerInputLines: requiredBuyerInputLines,
            faqDisplayLines: faqDisplayLines,
            packageDisplayLines: packageDisplayLines,
            explanationLines: explanations,
            trustPostureTitle: nil,
            trustPostureSummary: nil,
            trustEvidenceLines: [],
            trustCautionLines: [],
            trustRouteLabel: nil,
            trustIsLedgerBacked: false
        )
    }

    /// Merges Pass 2 overlays when `detail.secondHalfDisplay.agencyAssessment` is present.
    public static func applyingPass2Assessment(
        _ base: ExchangeThreadSituation,
        assessment: ExchangeAgencyAssessment,
        roleLabel: String
    ) -> ExchangeThreadSituation {
        var grounded = uniqLines(base.groundedFactLines + Array(assessment.groundedFactLines.prefix(12)))

        var decisionNeedLines = uniqLines(base.decisionNeedLines)

        var answerLine =
            assessment.answerabilityLine.flatMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } ?? base.answerabilityLine

        var mergedSafeLabels = uniqLines(base.safeActionLabels)

        if roleLabel.caseInsensitiveCompare(ExchangeSecondHalfRole.requester.displayTitle) == .orderedSame,
           let rn = assessment.requesterDecisionNeeds {
            decisionNeedLines =
                uniqLines(
                    decisionNeedLines
                        + Array(rn.missingDecisionFacts.prefix(8))
                        + Array(rn.recommendedQuestions.prefix(4))
                        + clippedLines([rn.rationale], maxCharacters: 200)
                )

            grounded = uniqLines(grounded + Array(rn.knownDecisionFacts.prefix(10)))

            let suggestedAffordances =
                uniqLines(
                    Array(rn.recommendedQuestions.prefix(4)).map { "Suggested question: \(trimLinePass2($0))" }
                )
            mergedSafeLabels = uniqLines(mergedSafeLabels + suggestedAffordances)
        }

        if roleLabel.caseInsensitiveCompare(ExchangeSecondHalfRole.provider.displayTitle) == .orderedSame,
           let ans = assessment.providerAnswerability {
            answerLine = ans.answerability.pass2DisplayLabel
            grounded = uniqLines(grounded + Array(ans.knownFactsUsed.prefix(10)))

            decisionNeedLines =
                uniqLines(
                    decisionNeedLines + Array(ans.missingFacts.prefix(6))
                )

            mergedSafeLabels =
                uniqLines(
                    mergedSafeLabels +
                        uniqLines(ans.missingFacts.prefix(3).map { "Suggested: \(trimLinePass2($0))" })
                )
        }

        if mergedSafeLabels.count > 14 {
            mergedSafeLabels = Array(mergedSafeLabels.prefix(14))
        }

        return ExchangeThreadSituation(
            threadID: base.threadID,
            title: base.title,
            phaseLabel: base.phaseLabel,
            agencyPhaseTitle: base.agencyPhaseTitle,
            agencyPhaseDetail: base.agencyPhaseDetail,
            stateSummary: base.stateSummary,
            roleLabel: base.roleLabel,
            counterpartyName: base.counterpartyName,
            selectedPublicProfileID: base.selectedPublicProfileID,
            selectedOfferID: base.selectedOfferID,
            selectedPublicProfileTitle: base.selectedPublicProfileTitle,
            selectedOfferTitle: base.selectedOfferTitle,
            selectedOfferSummary: base.selectedOfferSummary,
            primaryImageURL: base.primaryImageURL,
            selectedOfferImageURLs: base.selectedOfferImageURLs,
            latestUserIntent: base.latestUserIntent,
            latestInboundLine: base.latestInboundLine,
            latestOutboundLine: base.latestOutboundLine,
            pendingDraftSubject: base.pendingDraftSubject,
            pendingDraftPreview: base.pendingDraftPreview,
            hasPendingApproval: base.hasPendingApproval,
            deliveryLine: base.deliveryLine,
            boundaryLine: base.boundaryLine,
            nextMoveLine: base.nextMoveLine,
            trustLine: base.trustLine,
            reachabilityLine: base.reachabilityLine,
            missingFacts: base.missingFacts,
            whatChanged: base.whatChanged,
            strengthReasons: base.strengthReasons,
            weaknessReasons: base.weaknessReasons,
            safeActionLabels: mergedSafeLabels,
            requiresUserJudgment: base.requiresUserJudgment,
            canRunAutonomously: base.canRunAutonomously,
            groundedFactLines: Array(grounded.prefix(16)),
            answerabilityLine: answerLine,
            decisionNeedLines: Array(decisionNeedLines.prefix(14)),
            agencySuggestions: Array(assessment.agencySuggestions.prefix(5)),
            commercialSurfaceFactLines: base.commercialSurfaceFactLines,
            offerFulfillmentLine: base.offerFulfillmentLine,
            offerContactSummary: base.offerContactSummary,
            requiredBuyerInputLines: base.requiredBuyerInputLines,
            faqDisplayLines: base.faqDisplayLines,
            packageDisplayLines: base.packageDisplayLines,
            explanationLines: base.explanationLines,
            autonomyHoldLine: base.autonomyHoldLine,
            autonomyHoldReason: base.autonomyHoldReason,
            trustPostureTitle: base.trustPostureTitle,
            trustPostureSummary: base.trustPostureSummary,
            trustEvidenceLines: base.trustEvidenceLines,
            trustCautionLines: base.trustCautionLines,
            trustRouteLabel: base.trustRouteLabel,
            trustIsLedgerBacked: base.trustIsLedgerBacked
        )
    }

    private static func clippedLines(_ inputs: [String], maxCharacters: Int) -> [String] {
        inputs.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if trimmed.count <= maxCharacters {
                return trimmed
            }

            let end = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
            return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
    }

    private static func trimLinePass2(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqLines(_ rows: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for row in rows {
            let trimmed = row.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }

            out.append(trimmed)
            if out.count >= 28 {
                break
            }
        }

        return out
    }
}

// MARK: - Second half pickers

private func combinedBoundary(
    secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?,
    detail: ExchangeModels.ThreadDetail
) -> String {
    if let secondHalf, let line = secondHalfBoundaryLine(secondHalf) {
        return line
    }
    return fallbackBoundary(detail: detail)
}

private func combinedNextMove(
    secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?,
    detail: ExchangeModels.ThreadDetail
) -> String {
    if let secondHalf, let line = secondHalfNextMoveLine(secondHalf) {
        return line
    }
    return fallbackNextMove(detail: detail)
}

private func secondHalfBoundaryLine(
    _ display: ExchangeSecondHalfUIAdapter.DisplayModel
) -> String? {
    let effect = display.boundary.externalEffectLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if !effect.isEmpty { return effect }
    let reason = display.boundary.reason.trimmingCharacters(in: .whitespacesAndNewlines)
    return reason.isEmpty ? nil : reason
}

private func secondHalfNextMoveLine(
    _ display: ExchangeSecondHalfUIAdapter.DisplayModel
) -> String? {
    if let nm = display.nextMove, let title = nonBlankLine(nm.title) {
        return title
    }
    if let action = display.actionTitle.flatMap(nonBlankLine) {
        return action
    }
    if let rec = display.recommendation.nilIfBlank { return rec }
    let state = display.status.state.trimmingCharacters(in: .whitespacesAndNewlines)
    return state.isEmpty ? nil : state
}

private func mergedMissingFacts(
    secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?
) -> [String] {
    guard let secondHalf else { return [] }
    var values: [String] = []
    values.append(contentsOf: secondHalf.operatingContext.userFacingMissingFacts)
    values.append(contentsOf: secondHalf.operatingContext.diagnosticMissingFacts)
    values.append(contentsOf: secondHalf.requesterReview?.missingFacts ?? [])
    return uniquedLines(values)
}

private func mergedStrengths(
    secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?
) -> [String] {
    guard let secondHalf else { return [] }
    var values: [String] = []
    values.append(contentsOf: secondHalf.decision?.clarifiedFacts ?? [])
    if let rec = secondHalf.decision?.recommendation.nilIfBlank {
        values.append(rec)
    }
    values.append(contentsOf: secondHalf.requesterReview?.strengthReasons ?? [])
    values.append(contentsOf: secondHalf.operatingContext.strengthReasons)
    return uniquedLines(values)
}

private func mergedWeaknesses(
    secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?
) -> [String] {
    guard let secondHalf else { return [] }
    var values: [String] = []
    values.append(contentsOf: secondHalf.decision?.unresolvedIssues ?? [])
    values.append(contentsOf: secondHalf.decision?.tradeoffs ?? [])
    values.append(contentsOf: secondHalf.requesterReview?.weaknessReasons ?? [])
    values.append(contentsOf: secondHalf.operatingContext.weaknessReasons)
    return uniquedLines(values)
}

private func sanitizedButtonTitles(
    _ buttons: [ExchangeSecondHalfUIAdapter.ActionButton]
) -> [String] {
    let titles = buttons.map(\.title).map { trim($0) }.filter { !$0.isEmpty }
    return uniquedLines(titles)
}

private func trim(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func defaultSafeHints(
    needsJudgment: Bool,
    secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?
) -> [String] {
    if needsJudgment {
        return ["Review judgment", "Inspect boundary"]
    }
    if secondHalf != nil {
        return ["Review coordination", "Inspect boundary"]
    }
    return ["Inspect thread", "Inspect boundary"]
}

// MARK: - Mirror of lightweight Secretary projection (no app dependency)

private func fallbackBoundary(detail: ExchangeModels.ThreadDetail) -> String {
    let thread = detail.thread

    if let delivery = thread.delivery {
        switch delivery.status {
        case .notStarted:
            return "Nothing has left your boundary yet."
        case .pendingApproval:
            return "An outward move exists, but it remains behind approval."
        case .readyToSend:
            return "An outward move is prepared and ready to send."
        case .sending:
            return "An outward move is in progress."
        case .sent:
            return "Something has already moved beyond your boundary. Waiting on the other side."
        case .failed:
            return "An outward move was attempted, but it failed."
        @unknown default:
            return "The thread has an active delivery state."
        }
    }

    if isAwaitingResponse(detail) {
        return "Waiting on the other side after your last outward move."
    }

    if latestPendingApproval(for: detail) != nil
        || userFacingRenderableExternalOutboundDraft(for: detail) {
        return "Nothing has been sent yet. The current move is still local."
    }

    return "External movement is currently bounded."
}

private func fallbackNextMove(detail: ExchangeModels.ThreadDetail) -> String {
    if let approval = latestPendingApproval(for: detail) {
        return approval.rationale?.nilIfBlank
            ?? (userFacingRenderableExternalOutboundDraft(for: detail)
                ? "Review the prepared draft and decide whether it should move outward."
                : "Review before anything moves outward.")
    }

    if isClarification(detail) {
        return clarificationQuestion(detail)
    }

    if let failure = detail.thread.latestFailure {
        return failure.recommendedNextStep.summaryLine
    }

    if isAwaitingResponse(detail) {
        return "Wait for the reply window or prepare a bounded follow-up."
    }

    if showsFoundState(detail) {
        if userFacingRenderableExternalOutboundDraft(for: detail) {
            return "Review the prepared draft before deciding whether it should move."
        }
        if selectedCounterpartyName(for: detail) != nil {
            return "Inspect the selected path and decide whether to continue."
        }
    }

    if let next = detail.interpretationNextStep?.nilIfBlank {
        return next
    }

    switch detail.thread.state {
    case .awaitingApproval:
        return userFacingRenderableExternalOutboundDraft(for: detail)
            ? "Review the current draft and decide whether it should move."
            : "Review before anything moves outward."
    case .needsClarification:
        return "Clarify the request before the secretary continues."
    case .searching:
        return detail.thread.selectedCounterpartyID != nil
            ? "Inspect the selected path."
            : "Let the search continue or inspect candidate quality."
    case .matchFound:
        if userFacingRenderableExternalOutboundDraft(for: detail) {
            return "Review the prepared draft before deciding whether it should move."
        }
        return "Continue on this found path."
    case .matchCandidatesWeak:
        return "Review the weak paths and decide whether to refine or broaden."
    case .noViableMatch:
        return "Adjust the request or broaden the route."
    case .drafting:
        return "Review the path as the draft takes shape."
    case .draftReady:
        return userFacingRenderableExternalOutboundDraft(for: detail)
            ? "Review the prepared draft."
            : "Review what matters before deciding the next step."
    case .sending:
        return "Wait for delivery confirmation."
    case .blockedByDeliveryFailure:
        return "Inspect the failed move and choose the best recovery path."
    case .awaitingResponse:
        return "Wait for the reply window or prepare a bounded follow-up."
    case .declined:
        return "Review the decline and decide whether to reopen or close."
    case .stalled:
        return "Reassess the thread and choose whether to continue."
    case .resolved:
        return "Review the outcome."
    case .blockedBySystemFailure:
        return "Inspect the system failure and retry when the path is clear."
    }
}

private func clarificationQuestion(_ detail: ExchangeModels.ThreadDetail) -> String {
    if let question = detail.interpretationQuestion?.nilIfBlank {
        return question
    }

    if case .needsClarification(let status) = detail.thread.state,
       let explicit = status.question.nilIfBlank {
        return explicit
    }

    return "A bit more detail is needed before this can continue."
}

private func isClarification(_ detail: ExchangeModels.ThreadDetail) -> Bool {
    if detail.thread.interpretation?.needsClarification == true { return true }
    if case .needsClarification = detail.thread.state { return true }
    return false
}

private func isAwaitingResponse(_ detail: ExchangeModels.ThreadDetail) -> Bool {
    if case .awaitingResponse = detail.thread.state { return true }
    return false
}

private func showsFoundState(_ detail: ExchangeModels.ThreadDetail) -> Bool {
    if let sh = detail.secondHalfDisplay {
        if sh.hasDecisionPacket
            || sh.hasRequesterReview
            || sh.hasProviderReception
            || userFacingRenderableExternalOutboundDraft(for: detail)
            || sh.placement == .decisionReady
            || sh.placement == .requesterReview
            || sh.placement == .providerReception {
            return true
        }

        if sh.placement == .recovery || sh.status.isBlocking {
            return false
        }
    }

    if isClarification(detail) { return false }
    if detail.thread.latestFailure != nil { return false }

    if case .matchFound = detail.thread.state {
        return true
    }

    if latestPendingApproval(for: detail) != nil {
        return true
    }

    if userFacingRenderableExternalOutboundDraft(for: detail) {
        return true
    }

    if selectedCounterpartyName(for: detail) != nil {
        return true
    }

    return false
}

// MARK: - Delivery line (aligned with `ExchangeFacade.deliveryStatusText` semantics)

private func inboundThreadSuppressesStaleApprovalDeliveryLine(
    thread: ExchangeThread,
    latestApproval: ExchangeApproval?,
    secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?,
    hasPersistedActionableOutboundDraft: Bool
) -> Bool {
    guard thread.metadata["inbound_thread"] == "true" else { return false }
    guard !hasPersistedActionableOutboundDraft else { return false }
    guard latestApproval?.status == .pending else { return false }
    if let sh = secondHalf {
        guard sh.status.role.caseInsensitiveCompare(ExchangeSecondHalfRole.provider.displayTitle) == .orderedSame else {
            return false
        }
        if sh.placement == .needsInput { return true }
        if sh.agencyPhase == .needsUserInput { return true }
        if sh.nextMove?.needsUserInput == true { return true }
        let raw = ExchangeSecondHalfUIAdapter.canonicalSecondHalfActionRaw(for: sh)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw == ExchangeSecondHalfAction.requestUserInput.rawValue
    }
    return true
}

private func deliveryStatusLine(
    thread: ExchangeThread,
    latestApproval: ExchangeApproval?,
    hasPersistedActionableOutboundDraft: Bool,
    secondHalf: ExchangeSecondHalfUIAdapter.DisplayModel?
) -> String {
    if inboundThreadSuppressesStaleApprovalDeliveryLine(
        thread: thread,
        latestApproval: latestApproval,
        secondHalf: secondHalf,
        hasPersistedActionableOutboundDraft: hasPersistedActionableOutboundDraft
    ) {
        return "Checking…"
    }

    guard let delivery = thread.delivery else {
        if latestApproval?.status == .pending {
            return "Prepared locally · waiting for approval"
        }
        if hasPersistedActionableOutboundDraft, case .drafting = thread.state {
            return "Prepared locally · nothing sent"
        }
        return "No delivery signal yet"
    }

    switch delivery.status {
    case .notStarted:
        if hasPersistedActionableOutboundDraft, case .drafting = thread.state {
            return "Prepared locally · nothing sent"
        }
        return "No external action yet"
    case .pendingApproval:
        return "Waiting for approval before send"
    case .readyToSend:
        if latestApproval?.status == .pending {
            return "Prepared locally · waiting for approval"
        }
        return "Ready to send"
    case .sending:
        return "Sending now"
    case .sent:
        if let date = delivery.lastConfirmedSendAt {
            return "Sent \(relativeTimestamp(from: date))"
        }
        return "Sent"
    case .failed:
        return "Delivery failed"
    @unknown default:
        return "Delivery updated"
    }
}

private func relativeTimestamp(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - Draft + approval helpers

private func sortedDrafts(from detail: ExchangeModels.ThreadDetail) -> [ExchangeMessageDraft] {
    detail.drafts.sorted { lhs, rhs in
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private func latestPendingApproval(for detail: ExchangeModels.ThreadDetail) -> ExchangeApproval? {
    detail.approvals
        .filter { $0.status == .pending }
        .sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        .first
}

private func selectedCounterpartyName(for detail: ExchangeModels.ThreadDetail) -> String? {
    guard let selectedID = detail.thread.selectedCounterpartyID else { return nil }
    guard let selected = detail.counterparties.first(where: { $0.id == selectedID }) else { return nil }
    let line = selected.bestDisplayLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return line.isEmpty ? nil : line
}

private func profileDisplayTitle(_ profile: ExchangePublicNodeProfile) -> String {
    if let name = profile.displayName?.nilIfBlank {
        return name
    }
    if let headline = profile.headline?.nilIfBlank {
        return headline
    }
    return profile.id
}

private func draftBodyPreview(_ draft: ExchangeMessageDraft?) -> String? {
    guard let draft else { return nil }
    let trimmed = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.count <= 320 { return trimmed }
    let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 320)
    return String(trimmed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
}

// MARK: - Turns

private func latestInboundOutboundLines(_ turns: [ExchangeTurn]) -> (inbound: String?, outbound: String?) {
    var inbound: String?
    var outbound: String?

    for turn in turns.reversed() {
        switch turn.kind {
        case .replyReceived:
            if inbound == nil {
                inbound = turnDisplayLine(turn)
            }
        case .sendAttempted, .sendConfirmed:
            if outbound == nil {
                outbound = turnDisplayLine(turn)
            }
        default:
            break
        }

        if inbound != nil && outbound != nil {
            break
        }
    }

    return (inbound, outbound)
}

private func turnDisplayLine(_ turn: ExchangeTurn) -> String {
    let primary = turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    if let detail = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
        if primary.isEmpty { return detail }
        return "\(primary) — \(detail)"
    }
    return primary.isEmpty ? "Event" : primary
}

// MARK: - Match metadata

private func matchMetadataImageURL(from metadata: [String: String], keys: [String]) -> String? {
    for key in keys {
        guard let raw = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              !raw.lowercased().hasPrefix("file:")
        else { continue }

        if raw.contains("://") || raw.hasPrefix("//") {
            return raw
        }
    }
    return nil
}

private func matchMetadataImageURL(from metadata: [String: String]) -> String? {
    matchMetadataImageURL(from: metadata, keys: ["primary_image_url", "offer_image_url", "image_url"])
}

// MARK: - String utilities

private func nonBlankLine(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func uniquedLines(_ lines: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        if seen.insert(trimmed).inserted {
            output.append(trimmed)
        }
    }
    return output
}

private func sanitizeLines(_ lines: [String]) -> [String] {
    uniquedLines(lines)
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Thread Details display (resolved offer / profile)

private func offerFulfillmentDisplayLine(for offer: ExchangeOffer) -> String? {
    let fulfillment = offer.fulfillment
    var parts: [String] = []

    if fulfillment.remoteFriendly {
        parts.append("Remote friendly")
    }

    switch fulfillment.pricingMode {
    case .fixed:
        parts.append("Fixed price")
    case .quoteRequired:
        parts.append("Quote required")
    case .custom:
        parts.append("Custom pricing")
    case .undisclosed:
        break
    }

    switch fulfillment.commitmentMode {
    case .exploratory:
        if parts.isEmpty { parts.append("Exploratory") }
    case .active:
        parts.append("Active commitment")
    case .approvalRequired:
        parts.append("Approval required")
    }

    if let lead = fulfillment.leadTimeNote?.nilIfBlank {
        parts.append("Lead time: \(lead)")
    }

    if let capacity = fulfillment.capacityNote?.nilIfBlank {
        parts.append("Capacity: \(capacity)")
    }

    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

private func offerContactDisplaySummary(for offer: ExchangeOffer) -> String? {
    guard let contact = offer.contactInfo?.normalized(), !contact.isEmpty else { return nil }

    var parts: [String] = []
    if let name = contact.contactName?.nilIfBlank {
        parts.append(name)
    }
    if let business = contact.businessName?.nilIfBlank {
        parts.append(business)
    }
    if let method = contact.preferredContactMethod?.rawValue.nilIfBlank {
        parts.append("Preferred: \(method.capitalized)")
    }
    if let email = contact.email?.nilIfBlank {
        parts.append(email)
    }
    if let phone = contact.phone?.nilIfBlank {
        parts.append(phone)
    }
    if let website = contact.website?.nilIfBlank {
        parts.append(website)
    }
    if let area = contact.serviceAddressOrArea?.nilIfBlank {
        parts.append(area)
    }

    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

private func offerRequiredBuyerInputLines(for offer: ExchangeOffer) -> [String] {
    offer.commercialFacts.requiredBuyerInputs.compactMap(\.nilIfBlank)
}

private func offerFAQDisplayLines(for offer: ExchangeOffer) -> [String] {
    offer.commercialFacts.faqs.compactMap { faq in
        let question = faq.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = faq.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !answer.isEmpty else { return nil }
        return "\(question) — \(answer)"
    }
}

private func offerPackageDisplayLines(for offer: ExchangeOffer) -> [String] {
    offer.commercialFacts.packages.compactMap { pkg in
        let title = pkg.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var line = title
        if let summary = pkg.summary?.nilIfBlank {
            line += " — \(summary)"
        }
        if let price = pkg.priceDisplay?.nilIfBlank {
            line += " (\(price))"
        }
        return line
    }
}
